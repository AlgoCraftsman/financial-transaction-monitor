import importlib.util
import json
import time
from pathlib import Path


def load_fraud_detector():
    module_path = Path(__file__).resolve().parents[1] / "lambda-functions" / "fraud_detector.py"
    spec = importlib.util.spec_from_file_location("fraud_detector", module_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def valid_alert(**overrides):
    alert = {
        "alert_id": "alert-123",
        "transaction_id": "txn-123",
        "user_id": "user-123",
        "amount": 5000,
        "currency": "CAD",
        "risk_score": 90,
        "risk_level": "high",
        "risk_flags": ["high_amount", "velocity_exceeded"],
        "timestamp": int(time.time()),
        "detected_at": int(time.time()),
        "environment": "dev",
    }
    alert.update(overrides)
    return alert


def test_validate_alert_accepts_valid_payload():
    detector = load_fraud_detector()

    assert detector.validate_alert(valid_alert()) == []


def test_validate_alert_rejects_bad_risk_score():
    detector = load_fraud_detector()

    errors = detector.validate_alert(valid_alert(risk_score=120))

    assert "risk_score must be between 0 and 100" in errors


def test_process_record_saves_valid_alert(monkeypatch):
    detector = load_fraud_detector()
    saved = []

    monkeypatch.setattr(detector, "save_alert", lambda alert: saved.append(alert))
    monkeypatch.setattr(detector, "archive_alert", lambda alert: None)

    result = detector.process_record(
        {"messageId": "msg-1", "body": json.dumps(valid_alert())}
    )

    assert result["status"] == "success"
    assert saved[0]["alert_id"] == "alert-123"


def test_publish_alert_notification_skips_when_topic_not_configured(monkeypatch):
    detector = load_fraud_detector()
    called = []

    monkeypatch.delenv("FRAUD_ALERT_TOPIC_ARN", raising=False)
    monkeypatch.setattr(detector, "get_sns_client", lambda: called.append(True))

    detector.publish_alert_notification(valid_alert())

    assert called == []
