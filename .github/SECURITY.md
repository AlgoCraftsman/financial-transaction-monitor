# Security Model

This repository processes synthetic financial transaction data and is designed
for short-lived portfolio deployments. It does not include customer data,
credentials, or a production identity system.

## Implemented Controls

- AWS IAM authorization protects every transaction and fraud-alert API route.
- The public health route returns service status only.
- SQS queues use server-side encryption and dead-letter queues.
- SNS notifications use the AWS-managed SNS encryption key.
- DynamoDB and S3 encrypt data at rest.
- S3 blocks public access, keeps object versions, and expires current and
  noncurrent audit objects through lifecycle rules.
- IAM policies grant each Lambda function only the service actions it needs.
- CloudWatch logs, alarms, and dashboards provide operational visibility.
- Checkov runs as an enforced CI gate. Resource-level suppressions include an
  explanation so accepted risks remain visible during review.

## Accepted Portfolio Boundaries

The following controls are intentionally deferred because this is a
single-region, synthetic-data portfolio workload:

- Customer-managed KMS keys for DynamoDB, S3, Lambda environment variables,
  and CloudWatch Logs
- Cross-region S3 replication and a separate S3 access-log bucket
- Lambda VPC networking and code signing
- One-year CloudWatch log retention

These controls add recurring cost or operational infrastructure without
materially improving the short-lived demo. A production implementation would
select them from formal data-classification, retention, recovery, and threat
model requirements.

## Reporting a Vulnerability

Do not open a public issue for a suspected vulnerability. Use GitHub's private
vulnerability reporting or security advisory feature for this repository.
