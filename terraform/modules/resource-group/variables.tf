variable "name" {
  description = "Resource group name."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._()-]{1,90}$", var.name)) && !endswith(var.name, ".")
    error_message = "name must be 1-90 characters of letters, digits, periods, underscores, hyphens or parentheses and must not end with a period."
  }
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "uksouth"
}

variable "tags" {
  description = "Tags applied to the resource group."
  type        = map(string)
  default     = {}
}

variable "lock_level" {
  description = "Management lock applied to the resource group. null disables the lock; CanNotDelete is recommended for preprod and prod."
  type        = string
  default     = null

  validation {
    condition     = var.lock_level == null || contains(["CanNotDelete", "ReadOnly"], coalesce(var.lock_level, "CanNotDelete"))
    error_message = "lock_level must be null, CanNotDelete or ReadOnly."
  }
}

variable "budget_amount" {
  description = "Monthly budget in the billing currency. null disables the consumption budget."
  type        = number
  default     = null

  validation {
    condition     = var.budget_amount == null || coalesce(var.budget_amount, 1) > 0
    error_message = "budget_amount must be greater than zero when set."
  }
}

variable "budget_start_date" {
  description = "Budget period start in RFC 3339 format. Must be the first day of a month and no earlier than the current month."
  type        = string
  default     = "2026-11-01T00:00:00Z"

  validation {
    condition     = can(regex("^[0-9]{4}-[0-9]{2}-01T00:00:00Z$", var.budget_start_date))
    error_message = "budget_start_date must look like YYYY-MM-01T00:00:00Z."
  }
}

variable "budget_thresholds" {
  description = "Percentages of the budget at which actual spend notifications are sent."
  type        = list(number)
  default     = [50, 80, 100]

  validation {
    condition     = alltrue([for t in var.budget_thresholds : t > 0 && t <= 1000])
    error_message = "Each budget threshold must be between 1 and 1000 percent."
  }
}

variable "budget_forecast_threshold" {
  description = "Percentage of the budget at which a forecasted-spend notification is sent."
  type        = number
  default     = 110
}

variable "budget_contact_emails" {
  description = "Email addresses notified when a budget threshold is reached."
  type        = list(string)
  default     = []
}

variable "budget_action_group_ids" {
  description = "Optional action group resource IDs invoked when a threshold is reached."
  type        = list(string)
  default     = []
}
