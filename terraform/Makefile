.PHONY: help init fmt validate plan apply destroy output clean ci

TF_VAR_FILE ?= terraform.tfvars

help:
	@echo "Terraform commands"
	@echo "  make init       Initialize Terraform"
	@echo "  make fmt        Format Terraform files"
	@echo "  make validate   Validate Terraform configuration"
	@echo "  make plan       Preview infrastructure changes"
	@echo "  make apply      Apply infrastructure changes"
	@echo "  make destroy    Destroy infrastructure"
	@echo "  make output     Show Terraform outputs"
	@echo "  make clean      Remove local Terraform artifacts"
	@echo "  make ci         Run format and validation checks"

init:
	terraform init

fmt:
	terraform fmt -recursive

validate:
	terraform validate

plan:
	terraform plan -var-file=$(TF_VAR_FILE)

apply:
	terraform apply -var-file=$(TF_VAR_FILE)

destroy:
	terraform destroy -var-file=$(TF_VAR_FILE)

output:
	terraform output

clean:
	rm -rf .terraform
	rm -f *.zip
	rm -f terraform.tfstate*
	rm -f *tfplan*
	rm -f crash.log

ci: fmt validate
