# Demo Run Evidence

This document summarizes a successful end-to-end AWS demo run for the financial
transaction monitoring ETL pipeline. Raw command outputs were reviewed locally
and summarized here with account-specific identifiers omitted.

## Run Summary

- Date captured: June 22, 2026
- Region: `ca-central-1`
- Environment: `dev`
- Runtime: Python 3.11 Lambda functions
- Generated transactions: 25
- DynamoDB transaction records sampled: 5
- DynamoDB fraud alert records sampled: 3
- S3 audit objects observed: 28

The S3 object count matches the expected output from the demo batch:

- 25 transaction audit records
- 3 fraud alert audit records

## Deployed Resources

Terraform output confirmed the deployed stack included:

- Transaction queue: `txn-monitor-transactions-dev`
- Fraud alert queue: `txn-monitor-fraud-alerts-dev`
- Transactions table: `txn-monitor-transactions-dev`
- Fraud alerts table: `txn-monitor-fraud-alerts-dev`
- Transaction processor Lambda: `txn-monitor-transaction-processor-dev`
- Fraud detector Lambda: `txn-monitor-fraud-detector-dev`
- Audit log bucket: `txn-monitor-transaction-logs-dev-<account-id>`

## Transaction Generation

The synthetic transaction generator emitted 25 transaction events and sent them
to the transaction SQS queue.

Example generated event:

```json
{
  "transaction_id": "ed530448-f6cb-437b-b30d-1beb822c18de",
  "user_id": "user-1019",
  "amount": 754.42,
  "currency": "GBP",
  "timestamp": 1782180001,
  "transaction_type": "refund",
  "merchant_id": "merchant-824",
  "merchant_category": "restaurant",
  "location": "Mississauga"
}
```

## Transaction Processing Evidence

DynamoDB showed processed transaction records with enriched risk fields.

Example transaction record:

```json
{
  "transaction_id": "8a5686fa-a394-459e-8acd-ac181cf3268a",
  "user_id": "user-1007",
  "amount": "9274.22",
  "currency": "EUR",
  "transaction_type": "purchase",
  "risk_score": "55",
  "risk_level": "medium",
  "risk_flags": ["high_amount", "very_high_amount", "off_hours"],
  "status": "processed",
  "environment": "dev"
}
```

CloudWatch logs confirmed the transaction processor received, scored, saved, and
archived records:

```text
batch_received size=5 function=txn-monitor-transaction-processor-dev
transaction_scored transaction_id=159eb1c1-ed6d-4c25-8668-873a093015dd user_id=user-1020 amount=6359.16 risk_score=75 flags=['high_amount', 'very_high_amount', 'high_value_withdrawal', 'off_hours']
transaction_saved transaction_id=159eb1c1-ed6d-4c25-8668-873a093015dd risk_score=75
transaction_archived s3_key=transactions/dev/2026/06/23/ed530448-f6cb-437b-b30d-1beb822c18de.json
batch_complete total=1 success=1 duplicate=0 failed=0
```

## Fraud Alert Evidence

High-risk transaction records were forwarded to the fraud alert queue and stored
in the fraud alerts DynamoDB table.

Example fraud alert record:

```json
{
  "alert_id": "33f47b93-3d41-4cfb-9e5b-3bd13e42d102",
  "transaction_id": "159eb1c1-ed6d-4c25-8668-873a093015dd",
  "user_id": "user-1020",
  "amount": "6359.16",
  "currency": "EUR",
  "risk_score": "75",
  "risk_level": "high",
  "risk_flags": ["high_amount", "very_high_amount", "high_value_withdrawal", "off_hours"],
  "status": "open",
  "environment": "dev"
}
```

CloudWatch logs confirmed the fraud detector saved and archived alerts:

```text
batch_received size=1 function=txn-monitor-fraud-detector-dev
fraud_alert_saved alert_id=33f47b93-3d41-4cfb-9e5b-3bd13e42d102 transaction_id=159eb1c1-ed6d-4c25-8668-873a093015dd risk_score=75
fraud_alert_archived s3_key=alerts/dev/2026/06/23/33f47b93-3d41-4cfb-9e5b-3bd13e42d102.json
batch_complete total=1 success=1 duplicate=0 failed=0
```

## S3 Audit Evidence

The audit bucket contained transaction and alert JSON objects using the expected
partitioned key structure:

```text
alerts/dev/2026/06/23/33f47b93-3d41-4cfb-9e5b-3bd13e42d102.json
alerts/dev/2026/06/23/79ab8232-4d33-4894-b916-ea50ca231850.json
alerts/dev/2026/06/23/96c49d2d-508f-4fa2-895a-e946aa4bed16.json
transactions/dev/2026/06/23/089d8a3c-8d03-4457-82de-f79a1ae9445e.json
transactions/dev/2026/06/23/159eb1c1-ed6d-4c25-8668-873a093015dd.json
```

## Result

The demo validated the full implemented pipeline:

```text
Synthetic transactions
  -> SQS transaction queue
  -> Transaction processor Lambda
  -> DynamoDB transactions table
  -> S3 transaction audit logs
  -> SQS fraud alert queue
  -> Fraud detector Lambda
  -> DynamoDB fraud alerts table
  -> S3 fraud alert audit logs
```

No credentials or account-specific identifiers are included in this document.
