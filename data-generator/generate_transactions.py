"""
Generate synthetic financial transactions for local testing or SQS ingestion.
"""

from __future__ import annotations

import argparse
import json
import random
import time
import uuid
from decimal import Decimal
from typing import Any

CURRENCIES = ["CAD", "USD", "EUR", "GBP"]
MERCHANT_CATEGORIES = [
    "grocery",
    "fuel",
    "travel",
    "electronics",
    "restaurant",
    "cash",
    "money_transfer",
]
TRANSACTION_TYPES = ["purchase", "withdrawal", "transfer", "refund", "payment"]
LOCATIONS = ["Toronto", "Mississauga", "Ottawa", "Montreal", "Vancouver", "New York"]


def _amount(high_risk: bool) -> Decimal:
    if high_risk:
        return Decimal(str(round(random.uniform(1500, 9500), 2)))
    return Decimal(str(round(random.uniform(5, 850), 2)))


def generate_transaction(high_risk: bool = False) -> dict[str, Any]:
    transaction_type = random.choice(TRANSACTION_TYPES)
    if high_risk:
        transaction_type = random.choice(["withdrawal", "transfer", "purchase"])

    return {
        "transaction_id": str(uuid.uuid4()),
        "user_id": f"user-{random.randint(1000, 1025)}",
        "amount": float(_amount(high_risk)),
        "currency": random.choice(CURRENCIES),
        "timestamp": int(time.time()),
        "transaction_type": transaction_type,
        "merchant_id": f"merchant-{random.randint(100, 999)}",
        "merchant_category": random.choice(MERCHANT_CATEGORIES),
        "location": random.choice(LOCATIONS),
    }


def send_to_sqs(queue_url: str, transactions: list[dict[str, Any]], region: str) -> None:
    import boto3

    sqs = boto3.client("sqs", region_name=region)
    for transaction in transactions:
        sqs.send_message(QueueUrl=queue_url, MessageBody=json.dumps(transaction))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate synthetic transaction events.")
    parser.add_argument("--count", type=int, default=10, help="Number of transactions to emit.")
    parser.add_argument(
        "--high-risk-ratio",
        type=float,
        default=0.2,
        help="Fraction of generated transactions that should look suspicious.",
    )
    parser.add_argument("--queue-url", help="Optional SQS queue URL to send events to.")
    parser.add_argument("--region", default="ca-central-1", help="AWS region for SQS sends.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    transactions = [
        generate_transaction(random.random() < args.high_risk_ratio)
        for _ in range(args.count)
    ]

    if args.queue_url:
        send_to_sqs(args.queue_url, transactions, args.region)

    for transaction in transactions:
        print(json.dumps(transaction))


if __name__ == "__main__":
    main()
