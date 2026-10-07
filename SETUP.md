# Setup: run Live Poll on your own Azure + GitHub

**~45 min · once · you end up with your own dev, prod and CI.**

You fork this repo. Everything after that is yours: your Azure resources, your GitHub Actions runs, your PRs. Nothing touches the original.

---

## 0 · Prerequisites

| Need | Check |
|---|---|
| An Azure subscription where you are **Owner** (Xomnia's conditioned Owner is enough) | `az account show` |
| A GitHub account | `gh auth status` |
| Azure CLI, GitHub CLI, git | `az version`, `gh --version` |
| Terraform **1.16.x** | `terraform version` |
| Docker (only to run the app locally) | `docker info` |

```sh
az login
gh auth login
```

---

## 1 · Fork and clone · 5 min

1. On GitHub: **Fork** `JiDarwish/terraform-live-poll-demo` into your account.
2. Clone **your fork**:
   ```sh
   gh repo clone <you>/terraform-live-poll-demo && cd terraform-live-poll-demo
   ```
3. Your fork → **Actions** tab → **"I understand my workflows, go ahead and enable them"**. Forks start with workflows disabled.

Your fork is public, like the original. That's fine: there are no secrets anywhere in this setup.

---

## 2 · Configure · 5 min

```sh
scripts/setup.sh
```

It asks for two things:

| Question | Example | Why |
|---|---|---|
| **Suffix**, 2–8 lowercase letters/digits | `ab01` | goes into every name. Storage names are global across all of Azure, and colleagues can share one subscription. |
| **Region** | `westeurope` | where everything lives |

Then it:
1. looks up your subscription, your object id and your fork's GitHub ids;
2. checks that your 3 storage names are free;
3. registers the Azure resource providers (`Microsoft.App`, …);
4. points `gh` at **your fork**, so PRs never go to the original by accident;
5. writes the config files. Check them with `git diff`.

It never runs Terraform. You do that next.

---

## 3 · Bootstrap · 10 min

Bootstrap creates the state storage, your 3 resource groups, the CI identity, the app identities and every role.

```sh
cd bootstrap

# 1. First run keeps state on your laptop: the state container doesn't exist yet.
printf 'terraform {\n  backend "local" {}\n}\n' > local_override.tf
terraform init
terraform apply                   # expect: 17 to add, then answer: yes

# 2. Move the state into the container you just created.
rm local_override.tf
terraform init -migrate-state -backend-config=backend.hcl   # answer: yes
terraform plan                    # expect: No changes
rm terraform.tfstate terraform.tfstate.backup
```

A 403 on `migrate-state` means your new blob role hasn't propagated yet. Wait 2–5 min and run it again.

---

## 4 · Give GitHub its login · 2 min

Still in `bootstrap/`:

```sh
gh variable set AZURE_CLIENT_ID       --body "$(terraform output -raw azure_client_id)"
gh variable set AZURE_TENANT_ID       --body "$(terraform output -raw azure_tenant_id)"
gh variable set AZURE_SUBSCRIPTION_ID --body "$(terraform output -raw azure_subscription_id)"
gh variable list                  # expect: 3 rows
```

These are ids, not secrets. CI logs in with OIDC.

---

## 5 · Deploy prod through CI · 5 min

```sh
cd ..
git add -A && git commit -m "configure for <you>"
git push
```

The push changes `infra/`, so the **terraform** workflow plans and applies prod. Watch it:

```sh
gh run watch
```

Expect `Apply complete! Resources: 4 added`.

---

## 6 · Mark the starting point · 1 min

```sh
git tag -f session-start && git push -f origin session-start
```

`-f`, because your fork may have copied the original's tag. `scripts/reset.sh` returns `infra/` to this tag between sessions.

---

## 7 · Check · 2 min

```sh
az containerapp show -n ca-livepoll-prod -g rg-livepoll-<suffix>-prod --query properties.configuration.ingress.fqdn -o tsv
```

Open `https://<that>/results` and scan the QR code with your phone. The first load takes 10–20 s (scale to zero).

---

## 8 · Try dev from your laptop · 15 min

This is Beat 1 of the [runbook](RUNBOOK.md).

```sh
cd infra
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
terraform init -backend-config=envs/dev.backend.hcl
terraform plan -var-file=envs/dev.tfvars      # expect: 4 to add
terraform apply -var-file=envs/dev.tfvars
terraform output results_url
```

When it works, destroy dev again. Sessions start with an empty dev:

```sh
terraform destroy -var-file=envs/dev.tfvars
```

**Done.** Present with [RUNBOOK.md](RUNBOOK.md). The day before each session, run `scripts/reset.sh`.

---

## Later

### Get improvements from the original

Your fork on GitHub → **Sync fork**. A conflict can only happen in a config file (`*.tfvars`, `*.backend.hcl`). **Keep your version** of those lines.

### Build your own image (optional)

By default you run the original's public image (`app_image` in `infra/envs/*.tfvars`). To run your own:

1. Change something in `app/` and push to `main`. The **app-image** workflow builds `ghcr.io/<you>/terraform-live-poll-demo:<git sha>`.
2. GitHub → your profile → **Packages** → the package → **Package settings** → make it **public**, if it isn't. Azure pulls it without a password.
3. Put the new image in `app_image` in both tfvars files, in a PR. Read the plan, then merge.

### Remove everything

```sh
az group delete -n rg-livepoll-<suffix>-dev   --yes --no-wait
az group delete -n rg-livepoll-<suffix>-prod  --yes --no-wait
az group delete -n rg-livepoll-<suffix>-tfstate --yes
```

Role assignments and the CI login go with them. Then delete your fork if you want.

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `AADSTS700213: No matching federated identity record` | the CI identity trusts a different repo than the one running | Rerun `scripts/setup.sh`, then `terraform apply` in `bootstrap/` |
| `403` on `terraform init -migrate-state` | your blob role is still propagating | Wait 2–5 min and rerun |
| `setup.sh`: a storage name is "taken by someone else" | storage names are global across Azure | Rerun with another suffix |
| `MissingSubscriptionRegistration` | a resource provider isn't registered yet | Rerun `scripts/setup.sh` (step 4 registers them) |
| A PR opened on the **original** repo | `gh` wasn't pointed at your fork | Close it. `gh repo set-default <you>/terraform-live-poll-demo` |
