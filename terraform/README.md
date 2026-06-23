# Terraform Infrastructure

This directory defines the AWS infrastructure for the financial transaction
monitoring ETL pipeline.

## Resources

- DynamoDB transactions table
- DynamoDB fraud alerts table
- SQS transaction queue and dead-letter queue
- SQS fraud alert queue and dead-letter queue
- S3 audit log bucket
- Lambda transaction processor
- Lambda fraud detector
- IAM roles and least-privilege inline policies
- CloudWatch log groups
- CloudWatch alarms for Lambda errors, Lambda duration, and DLQ messages
- X-Ray tracing configuration

## Quick Start

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

The default region is `ca-central-1`.

## Configuration

Important variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `project_name` | `txn-monitor` | Prefix for AWS resource names |
| `environment` | `dev` | Environment suffix |
| `aws_region` | `ca-central-1` | AWS deployment region |
| `fraud_risk_threshold` | `75` | Score required to create an alert |
| `velocity_check_window_minutes` | `60` | User transaction lookback window |
| `max_transactions_per_window` | `10` | Velocity threshold |
| `suspicious_amount_threshold` | `1000.00` | Amount threshold for risk scoring |
| `lambda_duration_alarm_threshold_percent` | `80` | Percent of Lambda timeout used for duration alarms |

`terraform.tfvars` is ignored by Git. Use `terraform.tfvars.example` as the
starting point for local deployments.

## Lambda Packaging

Terraform uses the `archive` provider to package:

- `../lambda-functions/transaction_processor.py`
- `../lambda-functions/fraud_detector.py`

Generated ZIP files stay local and are ignored by Git.

## Testing the Deployed Pipeline

After `terraform apply`, send synthetic transactions:

```bash
QUEUE_URL=$(terraform output -raw sqs_transaction_queue_url)
python ../data-generator/generate_transactions.py --count 25 --queue-url "$QUEUE_URL"
```

Inspect records:

```bash
aws dynamodb scan \
  --table-name "$(terraform output -raw dynamodb_transactions_table_name)" \
  --limit 5 \
  --region "$(terraform output -raw aws_region)"

aws dynamodb scan \
  --table-name "$(terraform output -raw dynamodb_fraud_alerts_table_name)" \
  --limit 5 \
  --region "$(terraform output -raw aws_region)"
```

Tail logs:

```bash
aws logs tail "/aws/lambda/$(terraform output -raw transaction_processor_function_name)" \
  --follow \
  --region "$(terraform output -raw aws_region)"
```

Review alarm names:

```bash
terraform output cloudwatch_alarm_names
```

## Cost Controls

- DynamoDB uses on-demand billing.
- SQS and Lambda are usage-based.
- CloudWatch log retention is configurable.
- CloudWatch alarms cover Lambda errors, Lambda duration near timeout, and DLQ depth.
- S3 lifecycle rules transition audit objects to Glacier and expire old logs.

## Destroying the Stack

No resources are live by default. If you deploy the stack, destroy it when you are
done testing:

```bash
terraform destroy
```
