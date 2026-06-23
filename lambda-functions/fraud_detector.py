"""
Fraud detector Lambda.

Trigger: SQS fraud alert queue
Writes: DynamoDB fraud alerts table
Archives: alert audit records to S3
"""

import json
import logging
import os
import time
from decimal import Decimal, InvalidOperation
from typing import Any

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ENVIRONMENT = os.environ.get("ENVIRONMENT", "dev")
REQUIRED_FIELDS = {
    "alert_id",
    "transaction_id",
    "user_id",
    "amount",
    "risk_score",
    "risk_flags",
    "timestamp",
    "detected_at",
}

_alerts_table = None
_s3_client = None
_sns_client = None


def _required_env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def get_alerts_table():
    global _alerts_table
    if _alerts_table is None:
        dynamodb = boto3.resource("dynamodb")
        _alerts_table = dynamodb.Table(_required_env("FRAUD_ALERTS_TABLE"))
    return _alerts_table


def get_s3_client():
    global _s3_client
    if _s3_client is None:
        _s3_client = boto3.client("s3")
    return _s3_client


def get_sns_client():
    global _sns_client
    if _sns_client is None:
        _sns_client = boto3.client("sns")
    return _sns_client


def validate_alert(alert: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    missing = REQUIRED_FIELDS - alert.keys()
    if missing:
        errors.append(f"Missing required fields: {sorted(missing)}")
        return errors

    for field in ("alert_id", "transaction_id", "user_id"):
        if not isinstance(alert[field], str) or not alert[field].strip():
            errors.append(f"{field} must be a non-empty string")

    try:
        amount = Decimal(str(alert["amount"]))
        if amount <= 0:
            errors.append("amount must be greater than 0")
    except (InvalidOperation, TypeError):
        errors.append(f"amount must be a valid number, got: {alert['amount']!r}")

    try:
        risk_score = int(alert["risk_score"])
        if risk_score < 0 or risk_score > 100:
            errors.append("risk_score must be between 0 and 100")
    except (TypeError, ValueError):
        errors.append(f"risk_score must be an integer, got: {alert['risk_score']!r}")

    if not isinstance(alert["risk_flags"], list) or not all(
        isinstance(flag, str) for flag in alert["risk_flags"]
    ):
        errors.append("risk_flags must be a list of strings")

    for field in ("timestamp", "detected_at"):
        try:
            int(alert[field])
        except (TypeError, ValueError):
            errors.append(f"{field} must be a Unix epoch integer")

    return errors


def save_alert(alert: dict[str, Any]) -> None:
    now = int(time.time())
    item = {
        "alert_id": alert["alert_id"],
        "created_at": int(alert["detected_at"]),
        "transaction_id": alert["transaction_id"],
        "user_id": alert["user_id"],
        "amount": Decimal(str(alert["amount"])),
        "currency": alert.get("currency", "USD"),
        "risk_score": int(alert["risk_score"]),
        "risk_level": alert.get("risk_level", "high"),
        "risk_flags": alert["risk_flags"],
        "transaction_timestamp": int(alert["timestamp"]),
        "status": "open",
        "environment": alert.get("environment", ENVIRONMENT),
        "stored_at": now,
        "ttl": now + 180 * 24 * 3600,
    }
    get_alerts_table().put_item(
        Item=item,
        ConditionExpression="attribute_not_exists(alert_id)",
    )
    logger.warning(
        "fraud_alert_saved alert_id=%s transaction_id=%s risk_score=%d",
        alert["alert_id"],
        alert["transaction_id"],
        int(alert["risk_score"]),
    )


def archive_alert(alert: dict[str, Any]) -> None:
    timestamp = time.gmtime(int(alert["detected_at"]))
    key = (
        f"alerts/{ENVIRONMENT}/"
        f"{timestamp.tm_year}/{timestamp.tm_mon:02d}/{timestamp.tm_mday:02d}/"
        f"{alert['alert_id']}.json"
    )
    try:
        get_s3_client().put_object(
            Bucket=_required_env("S3_BUCKET"),
            Key=key,
            Body=json.dumps(alert),
            ContentType="application/json",
            ServerSideEncryption="AES256",
        )
        logger.info("fraud_alert_archived s3_key=%s", key)
    except ClientError as exc:
        logger.error(
            "fraud_alert_archive_failed alert_id=%s error=%s",
            alert["alert_id"],
            exc.response["Error"]["Code"],
        )


def publish_alert_notification(alert: dict[str, Any]) -> None:
    topic_arn = os.environ.get("FRAUD_ALERT_TOPIC_ARN")
    if not topic_arn:
        return

    message = {
        "alert_id": alert["alert_id"],
        "transaction_id": alert["transaction_id"],
        "user_id": alert["user_id"],
        "amount": alert["amount"],
        "currency": alert.get("currency", "USD"),
        "risk_score": alert["risk_score"],
        "risk_flags": alert["risk_flags"],
    }
    try:
        get_sns_client().publish(
            TopicArn=topic_arn,
            Subject="High-risk transaction alert",
            Message=json.dumps(message, indent=2),
        )
        logger.warning("fraud_alert_notification_sent alert_id=%s", alert["alert_id"])
    except ClientError as exc:
        logger.error(
            "fraud_alert_notification_failed alert_id=%s error=%s",
            alert["alert_id"],
            exc.response["Error"]["Code"],
        )


def process_record(record: dict[str, Any]) -> dict[str, Any]:
    message_id = record.get("messageId", "unknown")

    try:
        alert = json.loads(record["body"])
    except (json.JSONDecodeError, KeyError) as exc:
        logger.error("parse_failed message_id=%s error=%s", message_id, exc)
        return {"message_id": message_id, "status": "parse_error", "error": str(exc)}

    alert_id = alert.get("alert_id", "unknown")
    errors = validate_alert(alert)
    if errors:
        logger.error("validation_failed alert_id=%s errors=%s", alert_id, errors)
        return {
            "message_id": message_id,
            "alert_id": alert_id,
            "status": "validation_error",
            "errors": errors,
        }

    try:
        save_alert(alert)
    except ClientError as exc:
        code = exc.response["Error"]["Code"]
        if code == "ConditionalCheckFailedException":
            logger.warning("duplicate_alert alert_id=%s", alert_id)
            return {"message_id": message_id, "alert_id": alert_id, "status": "duplicate"}
        logger.error("fraud_alert_write_failed alert_id=%s error=%s", alert_id, code)
        raise

    archive_alert(alert)
    publish_alert_notification(alert)
    return {"message_id": message_id, "alert_id": alert_id, "status": "success"}


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, list[dict[str, str]]]:
    records = event.get("Records", [])
    function_name = getattr(context, "function_name", "fraud_detector")
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
