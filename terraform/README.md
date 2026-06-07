# Transaction Monitoring System - Infrastructure

Production-grade transaction monitoring system demonstrating event-driven architecture with AWS Lambda, real-time fraud detection, and Infrastructure as Code with Terraform.

## Architecture Overview

```
API Gateway → SQS (Transaction Queue) → Lambda (Transaction Processor) → DynamoDB (Transactions)
                                                    ↓
                                            SQS (Fraud Alert Queue) → Lambda (Fraud Detector) → DynamoDB (Fraud Alerts)
                                                    ↓
                                            S3 (Transaction Logs)
```

## Tech Stack

- **Infrastructure:** AWS (Lambda, DynamoDB, SQS, S3, API Gateway)
- **IaC:** Terraform >= 1.6
- **Runtime:** Python 3.11+
- **Monitoring:** CloudWatch, X-Ray
- **CI/CD:** GitHub Actions

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.6
- [AWS CLI](https://aws.amazon.com/cli/) configured with appropriate credentials
- AWS account with permissions to create:
  - Lambda functions
  - DynamoDB tables
  - SQS queues
  - S3 buckets
  - IAM roles and policies
  - CloudWatch log groups
  - API Gateway (optional)

## Quick Start

### 1. Clone and Configure

```bash
# Copy example variables
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your configuration
nano terraform.tfvars
```

### 2. Initialize Terraform

```bash
# Initialize Terraform and download providers
terraform init

# Validate configuration
terraform validate

# Preview changes
terraform plan
```

### 3. Deploy Infrastructure

```bash
# Deploy all resources
terraform apply

# Or deploy with auto-approve (use with caution)
terraform apply -auto-approve
```

### 4. Verify Deployment

```bash
# View outputs
terraform output

# Check specific output
terraform output sqs_transaction_queue_url
```

## Project Structure

```
.
├── main.tf                      # Core infrastructure resources
├── variables.tf                 # Input variables and validation
├── outputs.tf                   # Output values
├── terraform.tfvars.example     # Example configuration
├── .gitignore                   # Git ignore rules
└── README.md                    # This file
```

## Resource Overview

### DynamoDB Tables

1. **Transactions Table**
   - Hash Key: `transaction_id`
   - Range Key: `timestamp`
   - GSI: `UserIdIndex`, `RiskScoreIndex`
   - Features: Point-in-time recovery, TTL, encryption

2. **Fraud Alerts Table**
   - Hash Key: `alert_id`
   - Range Key: `created_at`
   - GSI: `StatusIndex`

### SQS Queues

1. **Transaction Queue** - Main processing queue
2. **Transaction DLQ** - Dead-letter queue for failed transactions
3. **Fraud Alert Queue** - High-priority fraud alerts
4. **Fraud Alert DLQ** - Dead-letter queue for failed alerts

### S3 Buckets

1. **Transaction Logs** - Audit logs and analytics
   - Encryption: AES256
   - Lifecycle: 90 days → Glacier, 365 days → Expire
   - Versioning: Enabled (production)

### IAM Roles

1. **Transaction Processor Role** - Permissions for transaction processing
2. **Fraud Detector Role** - Permissions for fraud detection

### CloudWatch

- Log groups for each Lambda function
- Configurable retention periods
- X-Ray tracing support

## Configuration

### Key Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `project_name` | `txn-monitor` | Project name prefix |
| `environment` | `dev` | Environment (dev/staging/production) |
| `aws_region` | `us-east-1` | AWS region |
| `lambda_runtime` | `python3.11` | Python runtime version |
| `fraud_risk_threshold` | `75` | Risk score threshold (0-100) |
| `log_retention_days` | `30` | CloudWatch log retention |

### Environment-Specific Configs

**Development:**
```hcl
environment                   = "dev"
log_retention_days            = 7
enable_point_in_time_recovery = false
fraud_risk_threshold          = 50
```

**Production:**
```hcl
environment                   = "production"
log_retention_days            = 90
enable_point_in_time_recovery = true
enable_waf                    = true
enable_vpc_endpoints          = true
fraud_risk_threshold          = 80
```

## Security Best Practices

### Current Implementation

- Encryption at rest (DynamoDB, S3)
- IAM least-privilege roles
- Private S3 buckets
- SQS dead-letter queues
- CloudWatch logging
- X-Ray tracing

### Production Recommendations

1. **Enable Remote State**
   ```hcl
   # Uncomment backend block in main.tf
   backend "s3" {
     bucket         = "your-terraform-state-bucket"
     key            = "transaction-monitoring/terraform.tfstate"
     region         = "us-east-1"
     dynamodb_table = "terraform-state-lock"
     encrypt        = true
   }
   ```

2. **Enable Point-in-Time Recovery**
   ```hcl
   enable_point_in_time_recovery = true
   ```

3. **Configure VPC Endpoints**
   ```hcl
   enable_vpc_endpoints = true
   ```

4. **Enable WAF**
   ```hcl
   enable_waf = true
   ```

5. **Use Secrets Manager**
   - Store API keys, webhook URLs, database credentials
   - Never commit secrets to version control

## Cost Optimization

### Implemented Strategies

1. **DynamoDB**: Pay-per-request billing (ideal for variable workloads)
2. **Lambda**: Right-sized memory allocation
3. **S3**: Lifecycle policies (Glacier after 90 days)
4. **CloudWatch**: Configurable log retention
5. **SQS**: Long polling to reduce empty receives

### Estimated Monthly Costs (Development)

- DynamoDB: ~$1-5 (light usage)
- Lambda: ~$0-2 (free tier)
- S3: ~$1-3
- SQS: ~$0-1 (free tier)
- CloudWatch: ~$1-2
- **Total: ~$3-13/month**

*Production costs will vary based on transaction volume*

## Monitoring & Observability

### CloudWatch Dashboards

```bash
# View Lambda metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value=txn-monitor-transaction-processor-dev \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-02T00:00:00Z \
  --period 3600 \
  --statistics Sum
```

### X-Ray Tracing

When enabled, X-Ray provides:
- End-to-end request tracing
- Service maps
- Performance bottleneck identification

### Alarms 

Recommended CloudWatch alarms:
- Lambda error rate > 5%
- DynamoDB throttling events
- SQS DLQ message count > 0
- API Gateway 5xx errors > 1%

## Testing

### Test Transaction Queue

```bash
# Get queue URL
QUEUE_URL=$(terraform output -raw sqs_transaction_queue_url)

# Send test message
aws sqs send-message \
  --queue-url $QUEUE_URL \
  --message-body '{
    "transaction_id": "test-123",
    "user_id": "user-456",
    "amount": 99.99,
    "timestamp": 1234567890
  }'
```

### Verify DynamoDB

```bash
# Get table name
TABLE_NAME=$(terraform output -raw dynamodb_transactions_table_name)

# Scan table
aws dynamodb scan --table-name $TABLE_NAME --limit 10
```

## Next Steps

After infrastructure deployment:

1. **Deploy Lambda Functions**
   - Create Python function code
   - Package dependencies
   - Upload to Lambda

2. **Configure API Gateway**
   - Create REST API
   - Set up endpoints
   - Configure throttling

3. **Set Up CI/CD**
   - Configure GitHub Actions
   - Automated testing
   - Deployment pipeline

4. **Configure Monitoring**
   - Create CloudWatch dashboards
   - Set up alarms
   - Configure SNS notifications

5. **Load Testing**
   - Performance testing
   - Capacity planning
   - Optimize configurations

## Maintenance

### Update Infrastructure

```bash
# Pull latest changes
git pull

# Review changes
terraform plan

# Apply updates
terraform apply
```

### Destroy Resources

```bash
# Preview deletion
terraform plan -destroy

# Destroy all resources (WARNING: Irreversible)
terraform destroy
```

## Additional Resources

- [AWS Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [DynamoDB Best Practices](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html)
- [Terraform AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)

## License

MIT License - See LICENSE file for details

---


