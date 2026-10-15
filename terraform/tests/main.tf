# Harness root for the native tests in this folder.
#
# terraform test needs a configuration directory; this file makes tests/ one
# without declaring any resources. Run from the repository root:
#
#   terraform -chdir=terraform/tests init -backend=false
#   terraform -chdir=terraform/tests test -test-directory=.
terraform {
  required_version = ">= 1.7"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.14"
    }
  }
}
