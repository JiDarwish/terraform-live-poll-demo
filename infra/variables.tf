variable "environment" {
  description = "Which environment this is. Picks the resource group, identity and names."
  type        = string

  # Validation: a typo fails at plan, before anything touches Azure.
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be \"dev\" or \"prod\"."
  }
}

variable "storage_account_name" {
  description = "Vote storage account. Globally unique across Azure, so it's fixed per env in tfvars."
  type        = string
}

variable "poll_question" {
  description = "The question on every phone."
  type        = string
}

variable "poll_options" {
  description = "One button per option."
  type        = list(string)
}

variable "poll_color" {
  description = "Accent colour of the poll, as a hex code."
  type        = string
}

variable "app_image_tag" {
  description = "Git SHA of the app image to run. Built by the app-image workflow."
  type        = string
}
