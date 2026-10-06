environment          = "prod"
resource_group_name  = "rg-livepoll-jd01-prod"
storage_account_name = "stlivepollprodjd01"

poll_question = "How confident are you with Terraform?"
poll_options  = ["What's Terraform?", "Heard of it", "Used it", "I could teach this"]
poll_color    = "#2f7d5b"

app_image = "ghcr.io/jidarwish/terraform-live-poll-demo:f77630b6ac666da3fbe7a2b6493bacaecab0d5c6"
