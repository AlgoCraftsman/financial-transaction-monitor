# Architecture Decisions

These notes capture the main engineering tradeoffs behind the financial
transaction monitoring ETL pipeline.

## Use SQS Between Pipeline Stages

SQS decouples ingestion from processing. The transaction generator does not need
to know whether Lambda is warm, busy, or temporarily failing; it only needs to
publish a valid transaction event.

This also gives the pipeline managed retry behavior and dead-letter queues. If a
message fails repeatedly, it is preserved for investigation instead of being
dropped silently.

## Use Lambda for Event Processing

Lambda fits the bursty shape of a transaction monitoring portfolio workload. It
keeps the operational model small, avoids always-on compute, and integrates
directly with SQS, CloudWatch, IAM, and X-Ray.

For this project, two focused functions are easier to reason about than one large
handler:

- The transaction processor validates, scores, stores, archives, and forwards
  high-risk events.
- The fraud detector stores and archives confirmed alert events.

## Use DynamoDB for Operational Transaction State

DynamoDB is a good fit for low-latency operational lookups in a serverless
pipeline. The transaction table stores enriched transaction records and supports
the access patterns needed by the processor:

- lookup by transaction ID and timestamp
- query recent transactions by user for velocity checks
- query transactions by risk level for investigation workflows

The fraud alerts table keeps alert state separate from transaction history, which
matches how an analyst or downstream alert workflow would inspect open cases.

## Use S3 for Audit Logs

DynamoDB stores hot operational records. S3 stores append-only audit copies of
processed transactions and fraud alerts.

This split keeps the DynamoDB tables focused on fast lookups while preserving a
lower-cost history that can later feed analytics, compliance review, or batch ETL
jobs. S3 lifecycle rules also make retention cost explicit.

## Use Terraform for Infrastructure

Terraform keeps the AWS architecture reviewable and reproducible. A recruiter or
engineer can inspect the infrastructure without needing access to the AWS account.

Terraform also packages the Lambda handlers with the `archive` provider, so the
deployment path is visible in code instead of relying on undocumented manual ZIP
steps.

## Use ca-central-1 as the Default Region

The project is positioned around the Toronto fintech market, so `ca-central-1` is
the closest AWS region and is a sensible default for locality.

The services used here are serverless or usage-based in that region: Lambda, SQS,
DynamoDB on-demand, S3, CloudWatch, and IAM. The default region can still be
changed through `terraform.tfvars` for users who prefer another AWS region.

## Use API Gateway for Query and Alert Review Endpoints

API Gateway gives the project a lightweight operational read layer without
changing the event-driven ingestion path. The API handler supports transaction
lookup, user transaction history, alert lookup, alert listing by status, and
alert status updates.

The health endpoint is public because it returns no transaction data. Every
transaction and alert route uses AWS IAM authorization, which prevents anonymous
reads and state changes without introducing a separate identity platform for a
short-lived portfolio deployment. A user-facing production application would
add fine-grained roles and a dedicated identity provider.

## Use SNS for High-Risk Alert Notifications

SNS provides a simple managed notification channel for high-risk alerts. Email
subscriptions are optional and configured through Terraform variables, so the
default deployment does not require personal email addresses.

This keeps the core pipeline deployable for a portfolio review while showing how
alert delivery can be connected when an operator wants notifications.

## What Would Change for Production

For a production deployment, the next changes would be:

- Remote Terraform state in S3 with DynamoDB state locking
- Fine-grained API roles and a user-facing identity provider
- Fine-grained API request validation and throttling by environment
- Idempotency and replay runbooks for DLQ recovery
- Tighter IAM resource scoping where AWS service constraints allow it
- Separate dev, staging, and production accounts or workspaces
- Formal retention requirements for DynamoDB TTL and S3 lifecycle policies
- Load testing against realistic transaction volumes
- Expanded dashboards for fraud rate, API latency, and investigation outcomes

Those additions are intentionally kept outside the core portfolio scope so the
implemented repository remains focused and easy to review.
