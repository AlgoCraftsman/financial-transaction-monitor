
"""
Transaction Processor Lambda Function
--------------------------------------
Trigger:    SQS - txn-monitor-transactions-{env}
Writes to:  DynamoDB - txn-monitor-transactions-{env}
Forwards:   SQS - txn-monitor-fraud-alerts-{env}  (when risk_score >= threshold)
Logs to:    S3  - txn-monitor-transaction-logs-{env}-{account_id}
"""
 
import json
import os
import time
import uuid
import logging
from decimal import Decimal, InvalidOperation
from typing import Any
 
import boto3
from boto3.dynamodb.conditions import Key
from botocore.exceptions import ClientError
 
# ============================================================================
# Logging
# ============================================================================
 
logger = logging.getLogger()
logger.setLevel(logging.INFO)
 
# ============================================================================
# Environment Variables (injected by Terraform / Lambda config)
# ============================================================================
 
TRANSACTIONS_TABLE   = os.environ["TRANSACTIONS_TABLE"]       # txn-monitor-transactions-dev
FRAUD_ALERT_QUEUE    = os.environ["FRAUD_ALERT_QUEUE_URL"]    # https://sqs...fraud-alerts-dev
S3_BUCKET            = os.environ["S3_BUCKET"]                # txn-monitor-transaction-logs-dev-...
FRAUD_RISK_THRESHOLD = int(os.environ.get("FRAUD_RISK_THRESHOLD", "75"))
VELOCITY_WINDOW_MIN  = int(os.environ.get("VELOCITY_WINDOW_MINUTES", "60"))
MAX_TXN_PER_WINDOW   = int(os.environ.get("MAX_TRANSACTIONS_PER_WINDOW", "10"))
SUSPICIOUS_AMOUNT    = float(os.environ.get("SUSPICIOUS_AMOUNT_THRESHOLD", "1000.0"))
ENVIRONMENT          = os.environ.get("ENVIRONMENT", "dev")
 
# ============================================================================
# AWS Clients
# ============================================================================
 
dynamodb = boto3.resource("dynamodb")
sqs      = boto3.client("sqs")
s3       = boto3.client("s3")
 
transactions_table = dynamodb.Table(TRANSACTIONS_TABLE)
 
# ============================================================================
# Validation
# ============================================================================
 
REQUIRED_FIELDS = {"transaction_id", "user_id", "amount", "timestamp"}
 
VALID_CURRENCIES       = {"USD", "CAD", "EUR", "GBP", "JPY", "AUD", "CHF"}
VALID_TRANSACTION_TYPES = {"purchase", "withdrawal", "transfer", "refund", "payment"}
 
 
def validate_transaction(txn: dict) -> list[str]:
    """
    Validates the transaction payload.
    Returns a list of error strings (empty = valid).
    """
    errors = []
 
    # Required fields
    missing = REQUIRED_FIELDS - txn.keys()
    if missing:
        errors.append(f"Missing required fields: {sorted(missing)}")
        return errors  # Can't continue without the basics
 
    # transaction_id
    if not isinstance(txn["transaction_id"], str) or not txn["transaction_id"].strip():
        errors.append("transaction_id must be a non-empty string")
 
    # user_id
    if not isinstance(txn["user_id"], str) or not txn["user_id"].strip():
        errors.append("user_id must be a non-empty string")
 
    # amount
    try:
        amount = Decimal(str(txn["amount"]))
        if amount <= 0:
            errors.append("amount must be greater than 0")
        if amount > Decimal("1000000"):
            errors.append("amount exceeds maximum allowed value (1,000,000)")
    except (InvalidOperation, TypeError):
        errors.append(f"amount must be a valid number, got: {txn['amount']!r}")
 
    # timestamp — expect Unix epoch (integer or float)
    try:
        ts = float(txn["timestamp"])
        now = time.time()
        if ts > now + 300:          # 5-min future tolerance
            errors.append("timestamp is too far in the future")
        if ts < now - 86400 * 30:   # Older than 30 days
            errors.append("timestamp is older than 30 days")
    except (TypeError, ValueError):
        errors.append(f"timestamp must be a Unix epoch number, got: {txn['timestamp']!r}")
 
    # Optional but validated if present
    if "currency" in txn and txn["currency"] not in VALID_CURRENCIES:
        errors.append(f"currency must be one of {sorted(VALID_CURRENCIES)}")
 
    if "transaction_type" in txn and txn["transaction_type"] not in VALID_TRANSACTION_TYPES:
        errors.append(f"transaction_type must be one of {sorted(VALID_TRANSACTION_TYPES)}")
 
    return errors
 
 
# ============================================================================
# Risk Scoring
# ============================================================================
 
def compute_risk_score(txn: dict, velocity_count: int) -> tuple[int, list[str]]:
    """
    Rule-based risk scoring (0–100).
    Returns (score, list_of_triggered_rule_names).
 
    Rules are additive; score is clamped to 100.
    Designed to be replaced / augmented with an ML model later.
    """
    score  = 0
    flags: list[str] = []
 
    amount = float(txn["amount"])
 
    # --- Amount rules ---
    if amount >= SUSPICIOUS_AMOUNT:
        score += 25
        flags.append("high_amount")
 
    if amount >= SUSPICIOUS_AMOUNT * 5:     # 5x threshold = very high
        score += 20
        flags.append("very_high_amount")
 
    # Round-number amounts are a classic fraud signal
    if amount == int(amount) and amount >= 500:
        score += 10
        flags.append("round_number_amount")
 
    # --- Velocity rules ---
    if velocity_count >= MAX_TXN_PER_WINDOW:
        score += 30
        flags.append("velocity_exceeded")
    elif velocity_count >= MAX_TXN_PER_WINDOW * 0.7:   # 70% of limit = warning
        score += 15
        flags.append("velocity_warning")
 
    # --- Transaction type rules ---
    txn_type = txn.get("transaction_type", "")
    if txn_type == "withdrawal" and amount >= SUSPICIOUS_AMOUNT:
        score += 20
        flags.append("high_value_withdrawal")
 
    if txn_type == "transfer" and amount >= SUSPICIOUS_AMOUNT * 2:
        score += 15
        flags.append("high_value_transfer")
 
    # --- Off-hours heuristic (UTC 01:00–05:00) ---
    hour_utc = time.gmtime(float(txn["timestamp"])).tm_hour
    if 1 <= hour_utc <= 5:
        score += 10
        flags.append("off_hours")
 
    return min(score, 100), flags
 
 
def get_velocity_count(user_id: str, window_start_epoch: int) -> int:
    """
    Counts how many transactions the user has made since window_start_epoch.
    Uses the UserIdIndex GSI (hash: user_id, range: timestamp).
    Returns 0 on any DynamoDB error to avoid blocking legitimate transactions.
    """
    try:
        resp = transactions_table.query(
            IndexName="UserIdIndex",
            KeyConditionExpression=(
                Key("user_id").eq(user_id) &
                Key("timestamp").gte(window_start_epoch)
            ),
            Select="COUNT",
        )
        return resp.get("Count", 0)
    except ClientError as exc:
        logger.warning(
            "velocity_check_failed user_id=%s error=%s",
            user_id, exc.response["Error"]["Code"],
        )
        return 0
 
 
# ============================================================================
# DynamoDB Write
# ============================================================================
 
def save_transaction(txn: dict, risk_score: int, risk_flags: list[str]) -> None:
    """
    Writes the enriched transaction record to DynamoDB.
 
    Schema (matches main.tf):
      PK: transaction_id (S)
      SK: timestamp      (N)
      GSI1: UserIdIndex  (user_id / timestamp)
      GSI2: RiskScoreIndex (risk_score / timestamp)
      TTL: ttl           (N)  — 90 days
    """
    ttl = int(time.time()) + 90 * 24 * 3600   # 90-day TTL
 
    item = {
        "transaction_id":   txn["transaction_id"],
        "timestamp":        int(txn["timestamp"]),
        "user_id":          txn["user_id"],
        "amount":           Decimal(str(txn["amount"])),
        "risk_score":       risk_score,
        "risk_flags":       risk_flags,
        "currency":         txn.get("currency", "USD"),
        "transaction_type": txn.get("transaction_type", "purchase"),
        "merchant_id":      txn.get("merchant_id", ""),
        "merchant_category":txn.get("merchant_category", ""),
        "location":         txn.get("location", ""),
        "status":           "processed",
        "processed_at":     int(time.time()),
        "environment":      ENVIRONMENT,
        "ttl":              ttl,
    }
 
    transactions_table.put_item(
        Item=item,
        ConditionExpression="attribute_not_exists(transaction_id)",  # Idempotency guard
    )
    logger.info(
        "transaction_saved transaction_id=%s risk_score=%d",
        txn["transaction_id"], risk_score,
    )
 
 
# ============================================================================
# Fraud Alert Forwarding
# ============================================================================
 
def forward_fraud_alert(txn: dict, risk_score: int, risk_flags: list[str]) -> None:
    """
    Sends a message to the fraud alert SQS queue.
    The fraud_detector Lambda consumes this queue.
    """
    alert_payload = {
        "alert_id":       str(uuid.uuid4()),
        "transaction_id": txn["transaction_id"],
        "user_id":        txn["user_id"],
        "amount":         float(txn["amount"]),
        "currency":       txn.get("currency", "USD"),
        "risk_score":     risk_score,
        "risk_flags":     risk_flags,
        "timestamp":      int(txn["timestamp"]),
        "detected_at":    int(time.time()),
        "environment":    ENVIRONMENT,
    }
 
    sqs.send_message(
        QueueUrl=FRAUD_ALERT_QUEUE,
        MessageBody=json.dumps(alert_payload),
        MessageAttributes={
            "risk_score": {
                "StringValue": str(risk_score),
                "DataType":    "Number",
            },
            "user_id": {
                "StringValue": txn["user_id"],
                "DataType":    "String",
            },
        },
        MessageGroupId=txn["user_id"],          # Groups alerts by user (FIFO-compatible)
    )
    logger.warning(
        "fraud_alert_forwarded transaction_id=%s user_id=%s risk_score=%d flags=%s",
        txn["transaction_id"], txn["user_id"], risk_score, risk_flags,
    )
 
 
# ============================================================================
# S3 Audit Log
# ============================================================================
 
def archive_to_s3(txn: dict, risk_score: int, risk_flags: list[str]) -> None:
    """
    Writes a JSON audit record to S3.
    Key pattern: logs/{env}/YYYY/MM/DD/{transaction_id}.json
    Failures are logged but do NOT fail the Lambda — archival is best-effort.
    """
    ts   = time.gmtime(float(txn["timestamp"]))
    key  = (
        f"logs/{ENVIRONMENT}/"
        f"{ts.tm_year}/{ts.tm_mon:02d}/{ts.tm_mday:02d}/"
        f"{txn['transaction_id']}.json"
    )
 
    record: dict[str, Any] = {
        **txn,
        "amount":      float(txn["amount"]),   # S3 doesn't need Decimal
        "risk_score":  risk_score,
        "risk_flags":  risk_flags,
        "archived_at": int(time.time()),
        "environment": ENVIRONMENT,
    }
 
    try:
        s3.put_object(
            Bucket=S3_BUCKET,
            Key=key,
            Body=json.dumps(record),
            ContentType="application/json",
            ServerSideEncryption="AES256",
        )
        logger.info("transaction_archived s3_key=%s", key)
    except ClientError as exc:
        logger.error(
            "s3_archive_failed transaction_id=%s error=%s",
            txn["transaction_id"], exc.response["Error"]["Code"],
        )
 
 
# ============================================================================
# Per-Record Processing
# ============================================================================
 
def process_record(record: dict) -> dict:
    """
    Processes a single SQS message.
    Returns a status dict (used for structured logging and batch failure tracking).
    """
    message_id = record.get("messageId", "unknown")
 
    # --- Parse ---
    try:
        txn = json.loads(record["body"])
    except (json.JSONDecodeError, KeyError) as exc:
        logger.error("parse_failed message_id=%s error=%s", message_id, exc)
        return {"message_id": message_id, "status": "parse_error", "error": str(exc)}
 
    transaction_id = txn.get("transaction_id", "unknown")
 
    # --- Validate ---
    errors = validate_transaction(txn)
    if errors:
        logger.error(
            "validation_failed transaction_id=%s errors=%s", transaction_id, errors
        )
        return {
            "message_id":     message_id,
            "transaction_id": transaction_id,
            "status":         "validation_error",
            "errors":         errors,
        }
 
    # --- Velocity check ---
    window_start = int(time.time()) - VELOCITY_WINDOW_MIN * 60
    velocity     = get_velocity_count(txn["user_id"], window_start)
 
    # --- Score ---
    risk_score, risk_flags = compute_risk_score(txn, velocity)
 
    logger.info(
        "transaction_scored transaction_id=%s user_id=%s amount=%s "
        "risk_score=%d velocity=%d flags=%s",
        transaction_id, txn["user_id"], txn["amount"],
        risk_score, velocity, risk_flags,
    )
 
    # --- Persist ---
    try:
        save_transaction(txn, risk_score, risk_flags)
    except ClientError as exc:
        code = exc.response["Error"]["Code"]
        if code == "ConditionalCheckFailedException":
            # Duplicate message — already processed; treat as success (idempotent)
            logger.warning("duplicate_transaction transaction_id=%s", transaction_id)
            return {"message_id": message_id, "transaction_id": transaction_id, "status": "duplicate"}
        logger.error("dynamodb_write_failed transaction_id=%s error=%s", transaction_id, code)
        raise   # Re-raise so SQS retries (up to maxReceiveCount=3 before DLQ)
 
    # --- Forward fraud alert if above threshold ---
    if risk_score >= FRAUD_RISK_THRESHOLD:
        try:
            forward_fraud_alert(txn, risk_score, risk_flags)
        except ClientError as exc:
            # Log but don't re-raise — the transaction is already saved
            logger.error(
                "fraud_forward_failed transaction_id=%s error=%s",
                transaction_id, exc.response["Error"]["Code"],
            )
 
    # --- Archive (best-effort) ---
    archive_to_s3(txn, risk_score, risk_flags)
 
    return {
        "message_id":     message_id,
        "transaction_id": transaction_id,
        "status":         "success",
        "risk_score":     risk_score,
        "risk_flags":     risk_flags,
    }
 
 
# ============================================================================
# Lambda Handler
# ============================================================================
 
def lambda_handler(event: dict, context: Any) -> dict:
    """
    Entry point. Processes an SQS batch of up to 10 messages.
 
    Uses SQS partial batch failure reporting so successfully processed
    messages are deleted even when others fail.
    To enable this in Terraform:
      function_response_types = ["ReportBatchItemFailures"]
    """
    records    = event.get("Records", [])
    batch_size = len(records)
 
    logger.info("batch_received size=%d function=%s", batch_size, context.function_name)
 
    results             = []
    failed_message_ids: list[dict] = []
 
    for record in records:
        try:
            result = process_record(record)
            results.append(result)
 
            if result["status"] not in ("success", "duplicate"):
                # Validation / parse errors are unrecoverable — don't retry
                # but also don't block the rest of the batch from being deleted.
                logger.warning(
                    "unrecoverable_record message_id=%s status=%s",
                    result["message_id"], result["status"],
                )
        except Exception as exc:
            # Transient / unexpected error — signal SQS to retry this message
            message_id = record.get("messageId", "unknown")
            logger.exception("unexpected_error message_id=%s error=%s", message_id, exc)
            failed_message_ids.append({"itemIdentifier": message_id})
 
    # Summary log
    successes  = sum(1 for r in results if r.get("status") == "success")
    duplicates = sum(1 for r in results if r.get("status") == "duplicate")
    failures   = len(failed_message_ids)
 
    logger.info(
        "batch_complete total=%d success=%d duplicate=%d failed=%d",
        batch_size, successes, duplicates, failures,
    )
 
    # Return partial failure report so SQS only retries the failed messages
    return {"batchItemFailures": failed_message_ids}