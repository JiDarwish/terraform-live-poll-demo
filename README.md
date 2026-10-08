# Live Poll: a Terraform demo you can vote on

A QR code on the projector, the room votes from their phones, and Terraform controls the question, the options and the vote store. Every Terraform change shows up on 20 phones.

**Want to present it? Fork this repo, then follow [SETUP.md](SETUP.md)** (~45 min, your own Azure + GitHub).

- **What and why:** [SPEC.md](SPEC.md)
- **How to present it, and how to reset:** [RUNBOOK.md](RUNBOOK.md)

## Run the app locally

Azurite stands in for Azure Table Storage, so you need no Azure account. It is for local runs only: dev, prod and CI never use it. In Azure, the app uses a real storage account with managed identity, no keys.

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
| `bootstrap/` | run once (see SETUP.md): state storage, resource groups, identities, every role assignment |
| `scripts/` | `setup.sh` configures your fork, `reset.sh` resets between sessions |
| `infra/` | the Terraform the room reads, for dev and prod |

## Dev from the laptop

```sh
cd infra
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
terraform init -backend-config=envs/dev.backend.hcl
terraform plan -var-file=envs/dev.tfvars
terraform apply -var-file=envs/dev.tfvars
terraform output results_url
```

## prod through CI

prod is never applied from a laptop. `.github/workflows/terraform.yml` does it:

| Event | What runs |
|---|---|
| PR touching `infra/` | plan, posted as one PR comment (`Plan: X to add, Y to change, Z to destroy`) |
| merge to `main` | plan + apply |
| Actions → terraform → Run workflow | plan + apply: puts prod back to what the code says (drift) |

Login is OIDC: the workflow trades a GitHub token for an Azure token as `id-livepoll-github`. No secrets are stored. PRs from other people's forks are skipped.
