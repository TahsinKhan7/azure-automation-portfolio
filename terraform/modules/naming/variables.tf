variable "prefix" {
  description = "Short organisation or platform prefix used at the start of every resource name (2-4 lowercase letters)."
  type        = string
  default     = "dp"

  validation {
    condition     = can(regex("^[a-z]{2,4}$", var.prefix))
    error_message = "prefix must be 2 to 4 lowercase letters."
  }
}

variable "environment" {
  description = "Deployment environment. One of: dev, ite, iqe, preprod, prod."
  type        = string

  validation {
    condition     = contains(["dev", "ite", "iqe", "preprod", "prod"], var.environment)
    error_message = "environment must be one of: dev, ite, iqe, preprod, prod."
  }
}

variable "location" {
  description = "Azure region the resources are deployed to. Must have an entry in location_short_codes."
  type        = string
  default     = "uksouth"

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.location))
    error_message = "location must be the lowercase Azure region name without spaces, for example uksouth."
  }
}

variable "workload" {
  description = "Workload or application identifier (2-10 lowercase alphanumerics), for example data, ingest, api."
  type        = string
  default     = "data"

  validation {
    condition     = can(regex("^[a-z0-9]{2,10}$", var.workload))
    error_message = "workload must be 2 to 10 lowercase letters or digits with no separators."
  }
}

variable "instance" {
  description = "Two-digit instance number used to disambiguate repeated deployments of the same workload."
  type        = string
  default     = "01"

  validation {
    condition     = can(regex("^[0-9]{2}$", var.instance))
    error_message = "instance must be exactly two digits, for example 01."
  }
}

variable "location_short_codes" {
  description = "Map of Azure region name to the short code embedded in resource names."
  type        = map(string)
  default = {
    uksouth     = "uks"
    ukwest      = "ukw"
    northeurope = "neu"
    westeurope  = "weu"
  }
}
