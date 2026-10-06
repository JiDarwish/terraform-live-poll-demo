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
  description = "The repo whose workflows may log in as the CI identity, as GitHub writes it in the OIDC subject."
  type        = string
  # GitHub puts immutable ids in the subject: owner@owner_id/repo@repo_id. A deleted and
  # re-created repo with the same name gets a new id, so its tokens no longer match. Look it up with:
  #   gh api repos/JiDarwish/terraform-live-poll-demo -q '"\(.owner.login)@\(.owner.id)/\(.name)@\(.id)"'
  default = "JiDarwish@29838474/terraform-live-poll-demo@1407041292"
}
