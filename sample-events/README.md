# Sample Events

These sample payloads show the transaction and alert shapes used by the
financial transaction monitoring ETL pipeline.

The transaction timestamps are placeholders. The Lambda validator rejects
transactions more than 30 days old or more than 5 minutes in the future. Before
sending the transaction examples to a live SQS queue, replace `timestamp` with
the current Unix epoch time.

## Files

| File | Purpose | Expected behavior |
| --- | --- | --- |
| `low-risk-transaction.json` | Normal purchase transaction | The transaction processor validates it, assigns a low risk score, writes it to the transactions table, and archives it to S3. It should not create a fraud alert. |
| `high-risk-transaction.json` | Large round-number withdrawal | The transaction processor validates it, assigns a high risk score, writes it to the transactions table, archives it to S3, and forwards a fraud alert message. |
| `invalid-transaction.json` | Bad transaction with an empty user ID and negative amount | The transaction processor rejects it as a validation error. It should not be stored, archived, or forwarded as an alert. |
| `fraud-alert.json` | Example alert message emitted by the transaction processor | The fraud detector validates it, writes it to the fraud alerts table, and archives it to S3. |

## Send a Sample Transaction

From the repository root, after Terraform has deployed the stack:

```powershell
Push-Location terraform
$REGION = terraform output -raw aws_region
$QUEUE_URL = terraform output -raw sqs_transaction_queue_url
Pop-Location

$payload = Get-Content sample-events\high-risk-transaction.json -Raw | ConvertFrom-Json
$payload.timestamp = [int][double]::Parse((Get-Date -UFormat %s))
$messageBody = $payload | ConvertTo-Json -Depth 10 -Compress
aws sqs send-message --queue-url $QUEUE_URL --message-body $messageBody --region $REGION
```
