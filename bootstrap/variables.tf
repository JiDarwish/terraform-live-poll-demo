variable "subscription_id" {
  description = "Azure subscription for every livepoll resource group."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "westeurope"
}

variable "presenter_object_id" {
  description = "Entra object id of the presenter: az ad signed-in-user show --query id -o tsv"
  type        = string
}

variable "github_repository" {
  description = "The repo whose workflows may log in as the CI identity."
  type        = string
  default     = "JiDarwish/terraform-live-poll-demo"
}
