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

## API Response Evidence

API evidence was captured on June 23, 2026 from the deployed `dev` stack in
`ca-central-1`. The public API host and account-specific identifiers are omitted.

Health check response:

```http
GET /health
```

```json
{
  "status": "ok"
}
```

A deterministic high-risk transaction was sent through the transaction SQS queue
to create an alert for API validation:

```json
{
  "transaction_id": "demo-high-risk-api-003",
  "user_id": "demo-user-001",
  "amount": 10000.0,
  "currency": "CAD",
  "transaction_type": "withdrawal",
  "merchant_category": "atm",
  "location": "Toronto"
}
```

Transaction lookup response:

```http
GET /transactions/demo-high-risk-api-003?timestamp=1782232460
```

```json
{
  "transaction": {
    "transaction_id": "demo-high-risk-api-003",
    "user_id": "demo-user-001",
    "amount": 10000,
    "currency": "CAD",
    "transaction_type": "withdrawal",
    "merchant_category": "atm",
    "location": "Toronto",
    "risk_score": 75,
    "risk_level": "high",
    "risk_flags": [
      "high_amount",
      "very_high_amount",
      "round_number_amount",
      "high_value_withdrawal"
    ],
    "status": "processed",
    "environment": "dev"
  }
}
```

Alert lookup response:

```http
GET /alerts/f92a7983-d51e-441c-87e5-37482b06de2c
```

```json
{
  "alert": {
    "alert_id": "f92a7983-d51e-441c-87e5-37482b06de2c",
    "transaction_id": "demo-high-risk-api-003",
    "user_id": "demo-user-001",
    "amount": 10000,
    "currency": "CAD",
    "risk_score": 75,
    "risk_level": "high",
    "risk_flags": [
      "high_amount",
      "very_high_amount",
      "round_number_amount",
      "high_value_withdrawal"
    ],
    "status": "open",
    "environment": "dev"
  }
}
```

Alert lifecycle response:

```http
PATCH /alerts/f92a7983-d51e-441c-87e5-37482b06de2c/status
```

```json
{
  "investigating": {
    "alert": {
      "alert_id": "f92a7983-d51e-441c-87e5-37482b06de2c",
      "transaction_id": "demo-high-risk-api-003",
      "status": "investigating",
      "updated_at": 1782246940
    }
  },
  "resolved": {
    "alert": {
      "alert_id": "f92a7983-d51e-441c-87e5-37482b06de2c",
      "transaction_id": "demo-high-risk-api-003",
      "status": "resolved",
      "updated_at": 1782246940
    }
  }
}
```

Final alert lookup response:

```http
GET /alerts/f92a7983-d51e-441c-87e5-37482b06de2c
```

```json
{
  "alert": {
    "alert_id": "f92a7983-d51e-441c-87e5-37482b06de2c",
    "transaction_id": "demo-high-risk-api-003",
    "status": "resolved",
    "risk_score": 75,
    "risk_level": "high",
    "updated_at": 1782246940
  }
}
```

CloudWatch logs confirmed the API demo transaction was scored, persisted,
forwarded, archived, stored as an alert, archived as an alert audit record, and
published to SNS:

```text
transaction_scored transaction_id=demo-high-risk-api-003 user_id=demo-user-001 amount=10000.0 risk_score=75 velocity=0 flags=['high_amount', 'very_high_amount', 'round_number_amount', 'high_value_withdrawal']
transaction_saved transaction_id=demo-high-risk-api-003 risk_score=75
fraud_alert_forwarded transaction_id=demo-high-risk-api-003 user_id=demo-user-001 risk_score=75 flags=['high_amount', 'very_high_amount', 'round_number_amount', 'high_value_withdrawal']
transaction_archived s3_key=transactions/dev/2026/06/23/demo-high-risk-api-003.json
fraud_alert_saved alert_id=f92a7983-d51e-441c-87e5-37482b06de2c transaction_id=demo-high-risk-api-003 risk_score=75
fraud_alert_archived s3_key=alerts/dev/2026/06/23/f92a7983-d51e-441c-87e5-37482b06de2c.json
fraud_alert_notification_sent alert_id=f92a7983-d51e-441c-87e5-37482b06de2c
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
  -> SNS fraud alert notification
  -> API Gateway alert lookup and lifecycle updates
```

No credentials or account-specific identifiers are included in this document.
