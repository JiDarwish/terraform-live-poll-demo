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

variable "suffix" {
  description = "Your short tag, in every name: makes the storage names globally unique and lets presenters share a subscription."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,8}$", var.suffix))
    error_message = "suffix must be 2-8 lowercase letters or digits."
  }
}

variable "github_repository" {
  description = "Your fork, as GitHub writes it in the OIDC subject: owner@owner_id/repo@repo_id. setup.sh fills it in."
  type        = string
  # GitHub puts immutable ids in the subject. A deleted and re-created repo with the same name
  # gets a new id, so its tokens no longer match. Look it up with:
  #   gh api repos/OWNER/REPO -q '"\(.owner.login)@\(.owner.id)/\(.name)@\(.id)"'
}
