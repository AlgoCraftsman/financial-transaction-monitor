"""
Transaction processor Lambda.

Trigger: SQS transaction queue
Writes: DynamoDB transactions table
Forwards: high-risk transactions to the fraud alert queue
Archives: transaction audit records to S3
"""

import json
import logging
import os
import time
import uuid
from decimal import Decimal, InvalidOperation
from typing import Any

import boto3
from boto3.dynamodb.conditions import Key
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

FRAUD_RISK_THRESHOLD = int(os.environ.get("FRAUD_RISK_THRESHOLD", "75"))
VELOCITY_WINDOW_MINUTES = int(os.environ.get("VELOCITY_WINDOW_MINUTES", "60"))
MAX_TRANSACTIONS_PER_WINDOW = int(os.environ.get("MAX_TRANSACTIONS_PER_WINDOW", "10"))
SUSPICIOUS_AMOUNT_THRESHOLD = Decimal(
    os.environ.get("SUSPICIOUS_AMOUNT_THRESHOLD", "1000.00")
)
ENVIRONMENT = os.environ.get("ENVIRONMENT", "dev")

REQUIRED_FIELDS = {"transaction_id", "user_id", "amount", "timestamp"}
VALID_CURRENCIES = {"USD", "CAD", "EUR", "GBP", "JPY", "AUD", "CHF"}
VALID_TRANSACTION_TYPES = {"purchase", "withdrawal", "transfer", "refund", "payment"}

_transactions_table = None
_sqs_client = None
_s3_client = None


def _required_env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def get_transactions_table():
    global _transactions_table
    if _transactions_table is None:
        dynamodb = boto3.resource("dynamodb")
        _transactions_table = dynamodb.Table(_required_env("TRANSACTIONS_TABLE"))
    return _transactions_table


def get_sqs_client():
    global _sqs_client
    if _sqs_client is None:
        _sqs_client = boto3.client("sqs")
    return _sqs_client


def get_s3_client():
    global _s3_client
    if _s3_client is None:
        _s3_client = boto3.client("s3")
    return _s3_client


def validate_transaction(transaction: dict[str, Any]) -> list[str]:
    errors: list[str] = []

    missing = REQUIRED_FIELDS - transaction.keys()
    if missing:
        errors.append(f"Missing required fields: {sorted(missing)}")
        return errors

    if not isinstance(transaction["transaction_id"], str) or not transaction[
        "transaction_id"
    ].strip():
        errors.append("transaction_id must be a non-empty string")

    if not isinstance(transaction["user_id"], str) or not transaction["user_id"].strip():
        errors.append("user_id must be a non-empty string")

    try:
        amount = Decimal(str(transaction["amount"]))
        if amount <= 0:
            errors.append("amount must be greater than 0")
        if amount > Decimal("1000000"):
            errors.append("amount exceeds maximum allowed value (1,000,000)")
    except (InvalidOperation, TypeError):
        errors.append(f"amount must be a valid number, got: {transaction['amount']!r}")

    try:
        timestamp = float(transaction["timestamp"])
        now = time.time()
        if timestamp > now + 300:
            errors.append("timestamp is too far in the future")
        if timestamp < now - 86400 * 30:
            errors.append("timestamp is older than 30 days")
    except (TypeError, ValueError):
        errors.append(
            f"timestamp must be a Unix epoch number, got: {transaction['timestamp']!r}"
        )

    if "currency" in transaction and transaction["currency"] not in VALID_CURRENCIES:
        errors.append(f"currency must be one of {sorted(VALID_CURRENCIES)}")

    if (
        "transaction_type" in transaction
        and transaction["transaction_type"] not in VALID_TRANSACTION_TYPES
    ):
        errors.append(
            f"transaction_type must be one of {sorted(VALID_TRANSACTION_TYPES)}"
        )

    return errors


def compute_risk_score(
    transaction: dict[str, Any], velocity_count: int
) -> tuple[int, list[str]]:
    score = 0
    flags: list[str] = []
    amount = Decimal(str(transaction["amount"]))

    if amount >= SUSPICIOUS_AMOUNT_THRESHOLD:
        score += 25
        flags.append("high_amount")

    if amount >= SUSPICIOUS_AMOUNT_THRESHOLD * 5:
        score += 20
        flags.append("very_high_amount")

    if amount == amount.to_integral_value() and amount >= Decimal("500"):
        score += 10
        flags.append("round_number_amount")

    if velocity_count >= MAX_TRANSACTIONS_PER_WINDOW:
        score += 30
        flags.append("velocity_exceeded")
    elif velocity_count >= MAX_TRANSACTIONS_PER_WINDOW * 0.7:
        score += 15
        flags.append("velocity_warning")

    transaction_type = transaction.get("transaction_type", "")
    if transaction_type == "withdrawal" and amount >= SUSPICIOUS_AMOUNT_THRESHOLD:
        score += 20
        flags.append("high_value_withdrawal")

    if transaction_type == "transfer" and amount >= SUSPICIOUS_AMOUNT_THRESHOLD * 2:
        score += 15
        flags.append("high_value_transfer")

    hour_utc = time.gmtime(float(transaction["timestamp"])).tm_hour
    if 1 <= hour_utc <= 5:
        score += 10
        flags.append("off_hours")

    return min(score, 100), flags


def classify_risk(score: int) -> str:
    if score >= FRAUD_RISK_THRESHOLD:
        return "high"
    if score >= 50:
        return "medium"
    return "low"


def get_velocity_count(user_id: str, window_start_epoch: int) -> int:
    try:
        response = get_transactions_table().query(
            IndexName="UserIdIndex",
            KeyConditionExpression=(
                Key("user_id").eq(user_id) & Key("timestamp").gte(window_start_epoch)
            ),
            Select="COUNT",
        )
        return response.get("Count", 0)
    except ClientError as exc:
        logger.warning(
            "velocity_check_failed user_id=%s error=%s",
            user_id,
            exc.response["Error"]["Code"],
        )
        return 0


def save_transaction(
    transaction: dict[str, Any], risk_score: int, risk_flags: list[str]
) -> None:
    now = int(time.time())
    item = {
        "transaction_id": transaction["transaction_id"],
        "timestamp": int(transaction["timestamp"]),
        "user_id": transaction["user_id"],
        "amount": Decimal(str(transaction["amount"])),
        "currency": transaction.get("currency", "USD"),
        "transaction_type": transaction.get("transaction_type", "purchase"),
        "merchant_id": transaction.get("merchant_id", ""),
        "merchant_category": transaction.get("merchant_category", ""),
        "location": transaction.get("location", ""),
        "risk_score": risk_score,
        "risk_level": classify_risk(risk_score),
        "risk_flags": risk_flags,
        "status": "processed",
        "processed_at": now,
        "environment": ENVIRONMENT,
        "ttl": now + 90 * 24 * 3600,
    }

    get_transactions_table().put_item(
        Item=item,
        ConditionExpression="attribute_not_exists(transaction_id)",
    )
    logger.info(
        "transaction_saved transaction_id=%s risk_score=%d",
        transaction["transaction_id"],
        risk_score,
    )


def forward_fraud_alert(
    transaction: dict[str, Any], risk_score: int, risk_flags: list[str]
) -> None:
    alert_payload = {
        "alert_id": str(uuid.uuid4()),
        "transaction_id": transaction["transaction_id"],
        "user_id": transaction["user_id"],
        "amount": float(transaction["amount"]),
        "currency": transaction.get("currency", "USD"),
        "risk_score": risk_score,
        "risk_level": classify_risk(risk_score),
        "risk_flags": risk_flags,
        "timestamp": int(transaction["timestamp"]),
        "detected_at": int(time.time()),
        "environment": ENVIRONMENT,
    }

    get_sqs_client().send_message(
        QueueUrl=_required_env("FRAUD_ALERT_QUEUE_URL"),
        MessageBody=json.dumps(alert_payload),
        MessageAttributes={
            "risk_score": {
                "StringValue": str(risk_score),
                "DataType": "Number",
            },
            "risk_level": {
                "StringValue": classify_risk(risk_score),
                "DataType": "String",
            },
            "user_id": {
                "StringValue": transaction["user_id"],
                "DataType": "String",
            },
        },
    )
    logger.warning(
        "fraud_alert_forwarded transaction_id=%s user_id=%s risk_score=%d flags=%s",
        transaction["transaction_id"],
        transaction["user_id"],
        risk_score,
        risk_flags,
    )


def archive_to_s3(
    transaction: dict[str, Any], risk_score: int, risk_flags: list[str]
) -> None:
    timestamp = time.gmtime(float(transaction["timestamp"]))
    key = (
        f"transactions/{ENVIRONMENT}/"
        f"{timestamp.tm_year}/{timestamp.tm_mon:02d}/{timestamp.tm_mday:02d}/"
        f"{transaction['transaction_id']}.json"
    )
    record: dict[str, Any] = {
        **transaction,
        "amount": float(transaction["amount"]),
        "risk_score": risk_score,
        "risk_level": classify_risk(risk_score),
        "risk_flags": risk_flags,
        "archived_at": int(time.time()),
        "environment": ENVIRONMENT,
    }

    try:
        get_s3_client().put_object(
            Bucket=_required_env("S3_BUCKET"),
            Key=key,
            Body=json.dumps(record),
            ContentType="application/json",
            ServerSideEncryption="AES256",
        )
        logger.info("transaction_archived s3_key=%s", key)
    except ClientError as exc:
        logger.error(
            "s3_archive_failed transaction_id=%s error=%s",
            transaction["transaction_id"],
            exc.response["Error"]["Code"],
        )


def process_record(record: dict[str, Any]) -> dict[str, Any]:
    message_id = record.get("messageId", "unknown")

    try:
        transaction = json.loads(record["body"])
    except (json.JSONDecodeError, KeyError) as exc:
        logger.error("parse_failed message_id=%s error=%s", message_id, exc)
        return {"message_id": message_id, "status": "parse_error", "error": str(exc)}

    transaction_id = transaction.get("transaction_id", "unknown")
    errors = validate_transaction(transaction)
    if errors:
        logger.error(
            "validation_failed transaction_id=%s errors=%s", transaction_id, errors
        )
        return {
            "message_id": message_id,
            "transaction_id": transaction_id,
            "status": "validation_error",
            "errors": errors,
        }

    window_start = int(time.time()) - VELOCITY_WINDOW_MINUTES * 60
    velocity_count = get_velocity_count(transaction["user_id"], window_start)
    risk_score, risk_flags = compute_risk_score(transaction, velocity_count)

    logger.info(
        "transaction_scored transaction_id=%s user_id=%s amount=%s "
        "risk_score=%d velocity=%d flags=%s",
        transaction_id,
        transaction["user_id"],
        transaction["amount"],
        risk_score,
        velocity_count,
        risk_flags,
    )

    try:
        save_transaction(transaction, risk_score, risk_flags)
    except ClientError as exc:
        code = exc.response["Error"]["Code"]
        if code == "ConditionalCheckFailedException":
            logger.warning("duplicate_transaction transaction_id=%s", transaction_id)
            return {
                "message_id": message_id,
                "transaction_id": transaction_id,
                "status": "duplicate",
            }
        logger.error("dynamodb_write_failed transaction_id=%s error=%s", transaction_id, code)
        raise

    if risk_score >= FRAUD_RISK_THRESHOLD:
        try:
            forward_fraud_alert(transaction, risk_score, risk_flags)
        except ClientError as exc:
            logger.error(
                "fraud_forward_failed transaction_id=%s error=%s",
                transaction_id,
                exc.response["Error"]["Code"],
            )

    archive_to_s3(transaction, risk_score, risk_flags)

    return {
        "message_id": message_id,
        "transaction_id": transaction_id,
        "status": "success",
        "risk_score": risk_score,
        "risk_level": classify_risk(risk_score),
        "risk_flags": risk_flags,
    }


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, list[dict[str, str]]]:
    records = event.get("Records", [])
    function_name = getattr(context, "function_name", "transaction_processor")
    logger.info("batch_received size=%d function=%s", len(records), function_name)

    results: list[dict[str, Any]] = []
    failed_message_ids: list[dict[str, str]] = []

    for record in records:
        try:
            result = process_record(record)
            results.append(result)
            if result["status"] not in ("success", "duplicate"):
                logger.warning(
                    "unrecoverable_record message_id=%s status=%s",
                    result["message_id"],
                    result["status"],
                )
        except Exception as exc:
            message_id = record.get("messageId", "unknown")
            logger.exception("unexpected_error message_id=%s error=%s", message_id, exc)
            failed_message_ids.append({"itemIdentifier": message_id})

    logger.info(
        "batch_complete total=%d success=%d duplicate=%d failed=%d",
        len(records),
        sum(1 for item in results if item.get("status") == "success"),
        sum(1 for item in results if item.get("status") == "duplicate"),
        len(failed_message_ids),
    )

    return {"batchItemFailures": failed_message_ids}
