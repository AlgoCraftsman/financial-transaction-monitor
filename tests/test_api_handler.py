import importlib.util
import json
from decimal import Decimal
from pathlib import Path


def load_api_handler():
    module_path = Path(__file__).resolve().parents[1] / "lambda-functions" / "api_handler.py"
    spec = importlib.util.spec_from_file_location("api_handler", module_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_health_route_returns_ok():
    handler = load_api_handler()

    result = handler.lambda_handler({"routeKey": "GET /health"}, None)

    assert result["statusCode"] == 200
    assert json.loads(result["body"]) == {"status": "ok"}


def test_decimal_values_are_json_safe():
    handler = load_api_handler()

    result = handler.response(
        200,
        {
            "amount": Decimal("42.50"),
            "count": Decimal("3"),
        },
    )

    assert json.loads(result["body"]) == {"amount": 42.5, "count": 3}


def test_invalid_alert_status_is_rejected():
    handler = load_api_handler()

    result = handler.update_alert_status(
        {"body": json.dumps({"status": "closed"})},
        {"alert_id": "alert-123"},
    )

    assert result["statusCode"] == 400
    assert "open" in json.loads(result["body"])["message"]
