# Live Poll: a Terraform demo you can vote on

A QR code on the projector, the room votes from their phones, and Terraform controls the question, the options and the vote store. Every Terraform change shows up on 20 phones.

- **What and why:** [SPEC.md](SPEC.md)
- **How to present it:** `RUNBOOK.md` (coming in M5)

## Run the app locally

```sh
cd app
docker compose up          # the app + Azurite (Azure's storage emulator)
open http://localhost:8000/results
```

Change the poll: `POLL_QUESTION="Tabs or spaces?" POLL_OPTIONS="Tabs|Spaces" docker compose up -d app`

## Test

```sh
pip install -r app/requirements-dev.txt
pytest app/tests
```

## Layout

| Folder | What |
|---|---|
| `app/` | the poll (FastAPI, Azure Table Storage) |
| `bootstrap/` | run once: state storage, resource groups, identities, every role assignment |
| `infra/` | the Terraform the room reads, for dev and prod (M3) |

## Bootstrap (run once)

Creates the state storage, `rg-livepoll-dev` and `rg-livepoll-prod`, the CI identity (GitHub OIDC, no secrets), one app identity per env, and every role assignment. `infra/` grants no roles: Xomnia's Owner role can't hand out role-granting roles, so CI never gets one.

```sh
cd bootstrap
cp terraform.tfvars.example terraform.tfvars   # fill in the two ids

# 1. First run keeps state on the laptop: the state container doesn't exist yet.
printf 'terraform {\n  backend "local" {}\n}\n' > local_override.tf
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# 2. Move the state into the container it just created.
rm local_override.tf
terraform init -migrate-state      # "yes". A 403 means your blob role hasn't propagated: wait 2-5 min.
terraform plan                     # expect: No changes
rm terraform.tfstate terraform.tfstate.backup tfplan

# 3. The three ids GitHub Actions logs in with. Not secrets.
REPO=JiDarwish/terraform-live-poll-demo
gh variable set AZURE_CLIENT_ID       --repo $REPO --body "$(terraform output -raw azure_client_id)"
gh variable set AZURE_TENANT_ID       --repo $REPO --body "$(terraform output -raw azure_tenant_id)"
gh variable set AZURE_SUBSCRIPTION_ID --repo $REPO --body "$(terraform output -raw azure_subscription_id)"
```

Later changes: `cd bootstrap && terraform init && terraform apply`. The state is remote from then on.
