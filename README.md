# Financial Transaction Monitoring ETL Pipeline

This project is a serverless AWS pipeline for ingesting financial transactions,
scoring them for fraud risk, and storing both transaction records and fraud
alerts for investigation.

The repository is designed as a portfolio project that demonstrates practical
AWS data engineering skills: event-driven ingestion, Lambda processing,
DynamoDB data modeling, S3 audit storage, Terraform infrastructure, automated
tests, and CI validation.

## Architecture

```mermaid
flowchart LR
    Generator["Synthetic transaction generator"] --> TransactionQueue["SQS transaction queue"]
    TransactionQueue --> Processor["Lambda transaction processor"]
    TransactionQueue --> TransactionDLQ["SQS transaction DLQ"]

    Processor --> Transactions["DynamoDB transactions table"]
    Processor --> AuditLogs["S3 transaction audit logs"]
    Processor -->|High-risk only| AlertQueue["SQS fraud alert queue"]

    AlertQueue --> Detector["Lambda fraud detector"]
    AlertQueue --> AlertDLQ["SQS fraud alert DLQ"]
    Detector --> Alerts["DynamoDB fraud alerts table"]
    Detector --> AlertLogs["S3 alert audit logs"]

    Processor -. metrics and logs .-> CloudWatch["CloudWatch Logs and X-Ray"]
    Detector -. metrics and logs .-> CloudWatch
```

More architecture notes are in [docs/architecture.md](docs/architecture.md).

## What It Demonstrates

- Event-driven ETL design with SQS and Lambda
- Rule-based fraud risk scoring with velocity checks
- DynamoDB data modeling with secondary indexes
- S3 audit logging with encryption and lifecycle policies
- Dead-letter queues for failed transaction and alert processing
- Infrastructure as Code using Terraform
- Local synthetic transaction generation
- Unit tests for Lambda business logic
- GitHub Actions validation for Python and Terraform

## Repository Structure

```text
.
|-- data-generator/                 # Synthetic transaction event generator
|-- docs/                           # Architecture notes
|-- lambda-functions/               # Lambda handlers
|-- sample-events/                  # Example input and alert payloads
|-- terraform/                      # AWS infrastructure
|-- tests/                          # Unit tests
|-- .github/workflows/ci.yml        # CI checks
|-- pyproject.toml                  # Test configuration
`-- requirements-dev.txt            # Local development dependencies
```

## Pipeline Flow

1. `data-generator/generate_transactions.py` emits realistic transaction JSON.
2. Transactions are sent to the SQS transaction queue.
3. `transaction_processor.py` validates each payload, checks user velocity,
   calculates a risk score, writes the enriched record to DynamoDB, and archives
   an audit copy to S3.
4. High-risk transactions are forwarded to the fraud alert queue.
5. `fraud_detector.py` validates alert messages, stores them in the fraud alerts
   table, and archives alert audit records to S3.
6. Failed retryable messages move to dead-letter queues after the configured
   receive count.

## Local Development

Create a virtual environment and install dependencies:

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt
```

On Windows PowerShell:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements-dev.txt
```

Run tests:

```bash
pytest -q
```

Generate sample transactions locally:

```bash
python data-generator/generate_transactions.py --count 5
```

Review example payloads and expected behavior:

```bash
ls sample-events
```

## Terraform Deployment

The default region is `ca-central-1`, which is the closest AWS region to Toronto
and supports the services used by this project. The stack uses pay-per-request or
serverless pricing patterns where possible.

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

After deployment, send generated transactions to SQS:

```bash
QUEUE_URL=$(terraform output -raw sqs_transaction_queue_url)
python ../data-generator/generate_transactions.py --count 25 --queue-url "$QUEUE_URL"
```

## Security and Cost Notes

- `terraform.tfvars` is intentionally ignored because local variable files can
  contain account-specific or sensitive values.
- DynamoDB uses on-demand billing for unpredictable workloads.
- S3 blocks public access and encrypts objects at rest.
- Lambda logs are retained for a configurable period.
- Dead-letter queues preserve failed events for investigation.
- No AWS resources are required to run the unit tests.

## Current Scope

Implemented:

- Transaction ingestion queue
- Transaction processor Lambda
- Fraud alert queue
- Fraud detector Lambda
- DynamoDB transaction and alert storage
- S3 audit logging
- Terraform deployment
- Synthetic transaction generation
- Unit tests and CI

Future production extensions:

- API Gateway query endpoint
- CloudWatch dashboard and alarms
- SNS or email notifications
- Remote Terraform state
- Load testing and performance tuning
