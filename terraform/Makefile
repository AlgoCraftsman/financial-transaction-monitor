.PHONY: help init plan apply destroy fmt validate clean test output

# Default target
.DEFAULT_GOAL := help

# Variables
TF_VAR_FILE ?= terraform.tfvars
ENV ?= dev

help: ## Show this help message
	@echo "Transaction Monitoring System - Terraform Commands"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

init: ## Initialize Terraform
	@echo " Initializing Terraform..."
	terraform init

plan: ## Run Terraform plan
	@echo " Planning infrastructure changes..."
	terraform plan -var-file=$(TF_VAR_FILE)

apply: ## Apply Terraform configuration
	@echo " Applying infrastructure changes..."
	terraform apply -var-file=$(TF_VAR_FILE)

apply-auto: ## Apply without confirmation (use with caution)
	@echo " Auto-applying infrastructure changes..."
	terraform apply -var-file=$(TF_VAR_FILE) -auto-approve

destroy: ## Destroy all resources
	@echo " WARNING: This will destroy all resources!"
	@echo "Press Ctrl+C to cancel, or wait 5 seconds to continue..."
	@sleep 5
	terraform destroy -var-file=$(TF_VAR_FILE)

destroy-auto: ## Destroy without confirmation (use with caution)
	@echo " Auto-destroying all resources..."
	terraform destroy -var-file=$(TF_VAR_FILE) -auto-approve

fmt: ## Format Terraform files
	@echo " Formatting Terraform files..."
	terraform fmt -recursive

validate: ## Validate Terraform configuration
	@echo " Validating Terraform configuration..."
	terraform validate

clean: ## Clean up Terraform files
	@echo " Cleaning up..."
	rm -rf .terraform
	rm -f .terraform.lock.hcl
	rm -f terraform.tfstate*
	rm -f tfplan*
	rm -f crash.log

output: ## Show Terraform outputs
	@echo " Terraform outputs:"
	@terraform output

output-json: ## Show outputs in JSON format
	@terraform output -json

refresh: ## Refresh Terraform state
	@echo " Refreshing Terraform state..."
	terraform refresh -var-file=$(TF_VAR_FILE)

graph: ## Generate dependency graph
	@echo " Generating dependency graph..."
	terraform graph | dot -Tpng > infrastructure-graph.png
	@echo "Graph saved to infrastructure-graph.png"

cost-estimate: ## Estimate infrastructure costs (requires infracost)
	@echo " Estimating costs..."
	@if command -v infracost >/dev/null 2>&1; then \
		infracost breakdown --path .; \
	else \
		echo "Error: infracost not installed. Visit https://www.infracost.io/docs/"; \
	fi

lint: ## Run Terraform linting (requires tflint)
	@echo " Linting Terraform files..."
	@if command -v tflint >/dev/null 2>&1; then \
		tflint --init; \
		tflint; \
	else \
		echo "Error: tflint not installed. Visit https://github.com/terraform-linters/tflint"; \
	fi

security-scan: ## Run security scan (requires tfsec)
	@echo " Running security scan..."
	@if command -v tfsec >/dev/null 2>&1; then \
		tfsec .; \
	else \
		echo "Error: tfsec not installed. Visit https://github.com/aquasecurity/tfsec"; \
	fi

test-queue: ## Send test message to SQS
	@echo " Sending test message to transaction queue..."
	@QUEUE_URL=$$(terraform output -raw sqs_transaction_queue_url 2>/dev/null); \
	if [ -z "$$QUEUE_URL" ]; then \
		echo "Error: Queue URL not found. Run 'make apply' first."; \
		exit 1; \
	fi; \
	aws sqs send-message \
		--queue-url $$QUEUE_URL \
		--message-body '{"transaction_id":"test-'$$(date +%s)'","user_id":"user-test","amount":99.99,"timestamp":'$$(date +%s)'}' \
		--region $$(terraform output -raw aws_region)

check-logs: ## View Lambda logs
	@echo " Recent Lambda logs:"
	@LOG_GROUP=$$(terraform output -raw cloudwatch_transaction_processor_log_group 2>/dev/null); \
	if [ -z "$$LOG_GROUP" ]; then \
		echo "Error: Log group not found. Run 'make apply' first."; \
		exit 1; \
	fi; \
	aws logs tail $$LOG_GROUP --follow --region $$(terraform output -raw aws_region)

check-dlq: ## Check dead-letter queue for failed messages
	@echo " Checking dead-letter queue..."
	@DLQ_URL=$$(terraform output -raw sqs_transaction_dlq_url 2>/dev/null); \
	if [ -z "$$DLQ_URL" ]; then \
		echo "Error: DLQ URL not found. Run 'make apply' first."; \
		exit 1; \
	fi; \
	aws sqs receive-message --queue-url $$DLQ_URL --region $$(terraform output -raw aws_region)

list-tables: ## List DynamoDB tables
	@echo " DynamoDB tables:"
	@terraform output dynamodb_transactions_table_name 2>/dev/null || echo "No tables found"
	@terraform output dynamodb_fraud_alerts_table_name 2>/dev/null || echo ""

setup-remote-state: ## Setup remote state backend (S3 + DynamoDB)
	@echo "  Setting up remote state backend..."
	@read -p "Enter S3 bucket name for state: " BUCKET; \
	read -p "Enter DynamoDB table name for locking: " TABLE; \
	read -p "Enter AWS region: " REGION; \
	echo "Creating S3 bucket..."; \
	aws s3 mb s3://$$BUCKET --region $$REGION || true; \
	aws s3api put-bucket-versioning --bucket $$BUCKET --versioning-configuration Status=Enabled; \
	aws s3api put-bucket-encryption --bucket $$BUCKET --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'; \
	echo "Creating DynamoDB table..."; \
	aws dynamodb create-table \
		--table-name $$TABLE \
		--attribute-definitions AttributeName=LockID,AttributeType=S \
		--key-schema AttributeName=LockID,KeyType=HASH \
		--billing-mode PAY_PER_REQUEST \
		--region $$REGION || true; \
	echo "Remote state backend ready!"

upgrade-providers: ## Upgrade Terraform providers
	@echo " Upgrading providers..."
	terraform init -upgrade

docs: ## Generate Terraform documentation (requires terraform-docs)
	@echo "Generating documentation..."
	@if command -v terraform-docs >/dev/null 2>&1; then \
		terraform-docs markdown table . > TERRAFORM.md; \
		echo "Documentation generated in TERRAFORM.md"; \
	else \
		echo "Error: terraform-docs not installed. Visit https://terraform-docs.io/"; \
	fi

check-drift: ## Check for infrastructure drift
	@echo "🔍 Checking for configuration drift..."
	terraform plan -detailed-exitcode -var-file=$(TF_VAR_FILE) || \
		(echo " Drift detected!" && exit 1)

workspace-list: ## List Terraform workspaces
	@echo "Terraform workspaces:"
	@terraform workspace list

workspace-new: ## Create new workspace (usage: make workspace-new ENV=staging)
	@echo "Creating workspace: $(ENV)"
	terraform workspace new $(ENV)

workspace-select: ## Select workspace (usage: make workspace-select ENV=staging)
	@echo "Switching to workspace: $(ENV)"
	terraform workspace select $(ENV)

all: init validate plan ## Initialize, validate, and plan

deploy: init validate apply ## Full deployment workflow

ci: init validate plan ## CI/CD validation workflow
	@echo "CI checks passed!"

install-tools: ## Install required tools
	@echo "Installing required tools..."
	@echo "Installing tflint..."
	@curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash || true
	@echo "Installing tfsec..."
	@curl -s https://raw.githubusercontent.com/aquasecurity/tfsec/master/scripts/install_linux.sh | bash || true
	@echo "Visit https://www.infracost.io/docs/ to install infracost"
	@echo "Visit https://terraform-docs.io/ to install terraform-docs"
