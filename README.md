# financial-transaction-monitor
Transaction monitoring systems are tools used to track and analyze financial transactions as they occur and are a critical component of fraud detection and risk management processes.

This project is a real-time financial transaction monitoring pipeline with fraud detection using AWS Lambda, DynamoDB, and Terraform.

## Architecture

![Architecture Diagram](docs/architecture-diagram.png)

## Project Goals

Building a production-grade transaction monitoring system to demonstrate:
- Event-driven architecture with AWS Lambda
- Real-time fraud detection algorithms
- Infrastructure as Code with Terraform
- Cost-optimized AWS deployment

## Tech Stack

- **Infrastructure:** AWS (Lambda, DynamoDB, SQS, S3, API Gateway)
- **IaC:** Terraform
- **Language:** Python 3.11
- **Monitoring:** CloudWatch, X-Ray
- **CI/CD:** GitHub Actions

## Features (Planned)

- [x] Infrastructure as Code setup
- [ ] Real-time transaction ingestion
- [ ] Rule-based fraud detection
- [ ] Risk scoring engine
- [ ] Alert notifications
- [ ] RESTful query API
- [ ] Monitoring dashboard


## Project Status

**Week 1: Foundation**

### Days 1-5

- Set up repo structure
- Set up AWS account (Enabled MFA on Root account, Created IAM user with admin access, Created AWS budget alert ($1), Created CloudWatch billing alarm)
- Set up AWS CLI locally

---

**Week 2: Infrastructure as Code**

### Days 6-10

- Wrote Terraform configuration covering the full AWS stack:
 - DynamoDB tables (transaction storage)
 - SQS queues (event ingestion pipeline)
 - S3 buckets (data archival /Lambda deployment packages)
 - API Gateway (RESTful transaction endpoints)
 - Lambda function stubs (placeholder handlers, ready for business logic)
 - CloudWatch alarms & X-Ray tracing (observability layer)
 - IAM roles & policies (least-privilege access)
- Successfully applied infrastrucutre to AWS Console
- Implementing data generator (synthetic transaction stream)

---



**Note:** This is a portfolio project demonstrating cloud architecture and data engineering skills for the Toronto fintech market.
