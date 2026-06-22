import importlib.util
import json
import time
from decimal import Decimal
from pathlib import Path


def load_transaction_processor():
    module_path = Path(__file__).resolve().parents[1] / "lambda-functions" / "transaction_processor.py"
    spec = importlib.util.spec_from_file_location("transaction_processor", module_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def valid_transaction(**overrides):
    transaction = {
        "transaction_id": "txn-123",
        "user_id": "user-123",
        "amount": 125.45,
        "currency": "CAD",
        "timestamp": int(time.time()),
        "transaction_type": "purchase",
    }
    transaction.update(overrides)
    return transaction


def test_validate_transaction_accepts_valid_payload():
    processor = load_transaction_processor()

    assert processor.validate_transaction(valid_transaction()) == []


def test_validate_transaction_rejects_missing_fields():
    processor = load_transaction_processor()

    errors = processor.validate_transaction({"transaction_id": "txn-123"})

    assert errors
    assert "Missing required fields" in errors[0]


def test_compute_risk_score_caps_high_risk_transaction():
    processor = load_transaction_processor()
    processor.SUSPICIOUS_AMOUNT_THRESHOLD = Decimal("1000.00")
    processor.MAX_TRANSACTIONS_PER_WINDOW = 10

    score, flags = processor.compute_risk_score(
        {
            "amount": 5000,
            "timestamp": 1704110400,
            "transaction_type": "withdrawal",
        },
        velocity_count=10,
    )

    assert score == 100
    assert "very_high_amount" in flags
    assert "velocity_exceeded" in flags
    assert "high_value_withdrawal" in flags


def test_process_record_forwards_high_risk_alert(monkeypatch):
    processor = load_transaction_processor()
    transaction = valid_transaction(
        amount=5000,
        transaction_type="withdrawal",
        timestamp=int(time.time()),
    )
    forwarded = []
    saved = []

    monkeypatch.setattr(processor, "get_velocity_count", lambda user_id, window_start: 10)
    monkeypatch.setattr(
        processor,
        "save_transaction",
        lambda txn, score, flags: saved.append((txn, score, flags)),
    )
    monkeypatch.setattr(
        processor,
        "forward_fraud_alert",
        lambda txn, score, flags: forwarded.append((txn, score, flags)),
    )
    monkeypatch.setattr(processor, "archive_to_s3", lambda txn, score, flags: None)

    result = processor.process_record(
        {"messageId": "msg-1", "body": json.dumps(transaction)}
    )

    assert result["status"] == "success"
    assert result["risk_level"] == "high"
    assert saved
    assert forwarded
