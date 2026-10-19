# Harness root for the native tests in this folder.
#
# terraform test needs a configuration directory; this file makes tests/ one
# without declaring any resources. Run from the repository root:
#
#   terraform -chdir=terraform/tests init -backend=false
#   terraform -chdir=terraform/tests test -test-directory=.
terraform {
  required_version = ">= 1.7"

  # The provider is declared here so `terraform init -backend=false` resolves it
  # for the modules under test and their mock_provider blocks; the harness
  # itself creates no resources.
  required_providers {
    # tflint-ignore: terraform_unused_required_providers
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.14"
    }
  }
}
