# Architecture Notes

## Implemented Pipeline

The pipeline focuses on a clear financial transaction monitoring flow:

```text
Synthetic transactions
  -> SQS transaction queue
  -> Lambda transaction processor
  -> DynamoDB transactions table
  -> S3 transaction audit logs
  -> SQS fraud alert queue for high-risk transactions
  -> Lambda fraud detector
  -> DynamoDB fraud alerts table
  -> S3 alert audit logs
  -> SNS email notification topic

API Gateway HTTP API
  -> Lambda API handler
  -> DynamoDB transactions and fraud alerts tables
```

## Design Choices

**SQS between stages**

SQS decouples producers from Lambda processing and gives the pipeline retry and
dead-letter behavior. This is useful for transaction workloads that may arrive in
bursts.

**DynamoDB for hot operational data**

Transactions are keyed by `transaction_id` and `timestamp`. A user index supports
velocity checks, and a risk-level index supports high-risk transaction queries.
Fraud alerts are keyed by `alert_id` and `created_at`, with a status index for
investigation workflows.

**S3 for audit history**

Both processed transactions and alert records are archived as JSON objects. This
keeps the operational tables lean while preserving data for later analytics or
review.

**Terraform packaging**

Terraform packages each Lambda handler into a ZIP file with the `archive`
provider. The ZIP outputs are build artifacts and are ignored by Git.

See [decisions.md](decisions.md) for more detail on the architectural tradeoffs.

## Production Extensions

The current project intentionally keeps the production surface focused. The next
reasonable additions would be API authentication, remote Terraform state, load
testing, and formal DLQ replay runbooks.
