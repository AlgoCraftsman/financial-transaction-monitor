"""
API handler Lambda for transaction and fraud alert queries.

Routes:
GET /transactions/{transaction_id}
GET /transactions/user/{user_id}
GET /alerts
GET /alerts/{alert_id}
PATCH /alerts/{alert_id}/status
"""

import json
import os
import time
from decimal import Decimal
from typing import Any

import boto3
from boto3.dynamodb.conditions import Key
from botocore.exceptions import ClientError

VALID_ALERT_STATUSES = {"open", "investigating", "resolved"}

_dynamodb = None
_transactions_table = None
_alerts_table = None


def _required_env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def get_dynamodb():
    global _dynamodb
    if _dynamodb is None:
        _dynamodb = boto3.resource("dynamodb")
    return _dynamodb


def get_transactions_table():
    global _transactions_table
    if _transactions_table is None:
        _transactions_table = get_dynamodb().Table(_required_env("TRANSACTIONS_TABLE"))
    return _transactions_table


def get_alerts_table():
    global _alerts_table
    if _alerts_table is None:
        _alerts_table = get_dynamodb().Table(_required_env("FRAUD_ALERTS_TABLE"))
    return _alerts_table


def to_json_safe(value: Any) -> Any:
    if isinstance(value, Decimal):
        if value % 1 == 0:
            return int(value)
        return float(value)
    if isinstance(value, list):
        return [to_json_safe(item) for item in value]
    if isinstance(value, dict):
        return {key: to_json_safe(item) for key, item in value.items()}
    return value


def response(status_code: int, body: dict[str, Any]) -> dict[str, Any]:
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(to_json_safe(body)),
    }


def parse_positive_int(value: str | None, default: int = 25, maximum: int = 100) -> int:
    try:
        parsed = int(value or default)
    except ValueError:
        return default
    return max(1, min(parsed, maximum))


def get_transaction(path_params: dict[str, str], query_params: dict[str, str]) -> dict[str, Any]:
    transaction_id = path_params.get("transaction_id")
    timestamp = query_params.get("timestamp")

    if not transaction_id or not timestamp:
        return response(
            400,
            {"message": "transaction_id path parameter and timestamp query parameter are required"},
        )

    try:
        timestamp_value = int(timestamp)
    except ValueError:
        return response(400, {"message": "timestamp must be a Unix epoch integer"})

    item = get_transactions_table().get_item(
        Key={"transaction_id": transaction_id, "timestamp": timestamp_value}
    ).get("Item")

    if not item:
        return response(404, {"message": "transaction not found"})

    return response(200, {"transaction": item})


def get_user_transactions(
    path_params: dict[str, str], query_params: dict[str, str]
) -> dict[str, Any]:
    user_id = path_params.get("user_id")
    if not user_id:
        return response(400, {"message": "user_id path parameter is required"})

    limit = parse_positive_int(query_params.get("limit"))
    result = get_transactions_table().query(
        IndexName="UserIdIndex",
        KeyConditionExpression=Key("user_id").eq(user_id),
        ScanIndexForward=False,
        Limit=limit,
    )
    return response(200, {"transactions": result.get("Items", [])})


def list_alerts(query_params: dict[str, str]) -> dict[str, Any]:
    status = query_params.get("status", "open")
    if status not in VALID_ALERT_STATUSES:
        return response(
            400,
            {"message": f"status must be one of {sorted(VALID_ALERT_STATUSES)}"},
        )

    limit = parse_positive_int(query_params.get("limit"))
    result = get_alerts_table().query(
        IndexName="StatusIndex",
        KeyConditionExpression=Key("status").eq(status),
        ScanIndexForward=False,
        Limit=limit,
    )
    return response(200, {"alerts": result.get("Items", [])})


def get_alert(path_params: dict[str, str]) -> dict[str, Any]:
    alert_id = path_params.get("alert_id")
    if not alert_id:
        return response(400, {"message": "alert_id path parameter is required"})

    result = get_alerts_table().query(
        KeyConditionExpression=Key("alert_id").eq(alert_id),
        ScanIndexForward=False,
        Limit=1,
    )
    items = result.get("Items", [])
    if not items:
        return response(404, {"message": "alert not found"})
    return response(200, {"alert": items[0]})


def update_alert_status(event: dict[str, Any], path_params: dict[str, str]) -> dict[str, Any]:
    alert_id = path_params.get("alert_id")
    if not alert_id:
        return response(400, {"message": "alert_id path parameter is required"})

    try:
        payload = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return response(400, {"message": "request body must be valid JSON"})

    status = payload.get("status")
    if status not in VALID_ALERT_STATUSES:
        return response(
            400,
            {"message": f"status must be one of {sorted(VALID_ALERT_STATUSES)}"},
        )

    current = get_alert(path_params)
    if current["statusCode"] != 200:
        return current

    alert = json.loads(current["body"])["alert"]
    updated_at = int(event.get("requestContext", {}).get("timeEpoch", 0) / 1000) or int(
        time.time()
    )
    updated = get_alerts_table().update_item(
        Key={"alert_id": alert_id, "created_at": int(alert["created_at"])},
        UpdateExpression="SET #status = :status, updated_at = :updated_at",
        ExpressionAttributeNames={"#status": "status"},
        ExpressionAttributeValues={
            ":status": status,
            ":updated_at": updated_at,
        },
        ReturnValues="ALL_NEW",
    )
    return response(200, {"alert": updated["Attributes"]})


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    route_key = event.get("routeKey", "")
    path_params = event.get("pathParameters") or {}
    query_params = event.get("queryStringParameters") or {}

    try:
        if route_key == "GET /transactions/{transaction_id}":
            return get_transaction(path_params, query_params)
        if route_key == "GET /transactions/user/{user_id}":
            return get_user_transactions(path_params, query_params)
        if route_key == "GET /alerts":
            return list_alerts(query_params)
        if route_key == "GET /alerts/{alert_id}":
            return get_alert(path_params)
        if route_key == "PATCH /alerts/{alert_id}/status":
            return update_alert_status(event, path_params)
        if route_key == "GET /health":
            return response(200, {"status": "ok"})
        return response(404, {"message": "route not found"})
    except ClientError as exc:
        return response(500, {"message": "AWS service error", "code": exc.response["Error"]["Code"]})
