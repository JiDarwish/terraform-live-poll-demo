# Live Poll v3: a Terraform demo you can vote on

**Status:** approved 2026-10-06. Updated the same day: all role assignments live in `bootstrap/` (D10).
**Replaces:** `JiDarwish/terraform-live-poll` (v2). That repo stays as a reference until v3 works end to end, then it is archived.
**Presenter:** one person, alone. They run bootstrap, own the subscription and present every beat.

---

## 1. The idea

A QR code is on the projector. The room scans it and votes from their phones, and the projector shows the results live. Terraform controls the question, the options, the colour and the vote store, so **every Terraform change is visible on 20 phones**.

- **Format:** the centrepiece of a Terraform training session, about 60–90 min of demo. Slides carry the rest.
- **Audience:** fresh-graduate data engineers with no Terraform experience.
- **Thesis:** *everything goes through plan.* Terraform shows what it will do before it does it, and keeps a record (state) of what it did.
- **The rule the room sees:** *the laptop changes dev. Only CI changes what is on your phone (prod).*
- **Design goal:** the Terraform code is small enough to explain line by line, and every choice in it is one we would defend at a client.

---

## 2. Decisions

| # | Decision |
|---|---|
| D1 | The app is reused from v2 (`app/`), with small trims (§4). |
| D2 | Azure, on the presenter's Xomnia subscription. Container Apps for the app, a Storage Table for the votes. |
| D3 | Two environments, **dev** and **prod**, from **one root module**. Separate `tfvars` and backend files per env. |
| D4 | The app reaches storage with a **user-assigned managed identity**, created in `bootstrap/` (D10). `shared_access_key_enabled = false`. No keys or secrets anywhere. |
| D5 | **One Terraform workflow**: plan on PR (as a comment), apply on push to `main` and on `workflow_dispatch`. OIDC login. No approval gate. |
| D6 | Every beat is a **one-line change typed live**. No prepared scenario branches, no fallback scripts (one exception in §7). |
| D7 | `bootstrap/` is Terraform, run once by the presenter. Its state is migrated into the container it creates. |
| D8 | Versions: Terraform `~> 1.16`, azurerm `~> 5.8`, the same on the laptop and in CI. |
| D9 | Repo: `JiDarwish/terraform-live-poll-demo`, **public**. Image: `ghcr.io/jidarwish/terraform-live-poll-demo`, public package. |
| D10 | **Every role assignment lives in `bootstrap/`**, including the app identities and their table role. `infra/` grants no roles, so CI needs no right to grant them. Why: Xomnia's Owner role carries a condition that blocks granting Owner, User Access Administrator and RBAC Administrator, so the presenter cannot give CI a role-granting role. Room line: *"Even Owner can't hand out Owner."* |

**Out of scope:** modules (a slide), secrets in state as an act, a second team or root module, drift cron, approval gates, policy as code, HCP Terraform, Log Analytics.

---

## 3. Repository layout

```
terraform-live-poll-demo/
├── README.md                  # what this is, run locally, bootstrap, links
├── SPEC.md                    # this file
├── RUNBOOK.md                 # the presenter's step tables, one per beat
├── app/                       # copied from v2, trimmed (§4)
├── bootstrap/                 # run once: state storage, RGs, identities, every role (§5.1)
├── infra/                     # the root module for dev and prod (§5.2)
│   ├── terraform.tf           # required_version, required_providers, backend "azurerm" {}
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── envs/
│       ├── dev.tfvars    dev.backend.hcl
│       └── prod.tfvars   prod.backend.hcl
├── scripts/reset.sh           # §8
└── .github/workflows/
    ├── terraform.yml          # the one shown in the room (§6)
    └── app-image.yml          # test, build, push. Not shown.
```

**Naming** (`{env}` = `dev` | `prod`):

| Thing | Name |
|---|---|
| Resource groups | `rg-livepoll-tfstate`, `rg-livepoll-dev`, `rg-livepoll-prod` |
| State storage account / container | `stlivepolltf<suffix>` / `tfstate` |
| State keys | `bootstrap.tfstate`, `infra-dev.tfstate`, `infra-prod.tfstate` |
| Vote storage account / table | `stlivepoll{env}<suffix>` (in `tfvars`) / `votes` |
| Container Apps env / app | `cae-livepoll-{env}` / `ca-livepoll-{env}` |
| Identities | `id-livepoll-app-{env}`, `id-livepoll-github` |

---

## 4. The app (copied from v2, then trimmed)

Unchanged: FastAPI, `GET /` (vote), `GET /results` (projector + QR), `POST /api/vote`, `GET /api/results`, `GET /healthz`. `poll_id = sha256(question + options)[:8]`, so a new question starts at zero and old votes come back when the question returns. The app never creates the table.

Trims:

1. **Remove `AUTH_MODE`.** If `STORAGE_CONNECTION_STRING` is set, use it (local Azurite only). Otherwise use `ManagedIdentityCredential(client_id=AZURE_CLIENT_ID)` against `https://{STORAGE_ACCOUNT_NAME}.table.core.windows.net`.
2. **Footer** shows `env · revision`. The auth label goes.
3. **Keep** the 403 retry with backoff and the "Can't reach the vote store" banner. The app's role is granted by bootstrap long before Beat 1, so this is a safety net, not the plan.
4. Update tests to match. `docker compose up` still runs the app against Azurite.

Env vars set by Terraform: `POLL_QUESTION`, `POLL_OPTIONS` (pipe-separated), `POLL_COLOR`, `ENVIRONMENT`, `STORAGE_ACCOUNT_NAME`, `TABLE_NAME`, `AZURE_CLIENT_ID`.

---

## 5. Infrastructure

### 5.1 `bootstrap/` (about 100 lines, never presented)

First run on local state, then `terraform init -migrate-state` into `tfstate/bootstrap.tfstate`.

| Creates | Details |
|---|---|
| `rg-livepoll-tfstate` + state storage account + `tfstate` container | blob versioning, soft delete 7 days, `shared_access_key_enabled = false`, TLS 1.2 |
| `rg-livepoll-dev`, `rg-livepoll-prod` | owned here, so every role below is scoped to one RG, not the subscription |
| `id-livepoll-github` | federated credentials for `repo:JiDarwish/terraform-live-poll-demo:pull_request` and `…:ref:refs/heads/main` |
| `id-livepoll-app-dev`, `id-livepoll-app-prod` | one per env, in that env's RG. `Storage Table Data Contributor` on the env RG (the vote account doesn't exist yet). `infra/` reads them with a `data` source. |
| CI roles | `Contributor` + `Storage Table Data Contributor` on `rg-livepoll-prod`. `Storage Blob Data Contributor` on the `tfstate` container. **No role-granting rights.** |
| Presenter roles (`var.presenter_object_id`) | Already subscription Owner (with Xomnia's condition, D10), so only data roles: `Storage Table Data Contributor` on `rg-livepoll-dev`, `Storage Blob Data Contributor` on `tfstate`. Owner and Contributor grant no data access. |

No GitHub provider. After apply, set three Actions variables once: `gh variable set AZURE_CLIENT_ID / AZURE_TENANT_ID / AZURE_SUBSCRIPTION_ID`.

### 5.2 `infra/` (the code the room reads)

```
data.azurerm_resource_group.this            # owned by bootstrap
data.azurerm_user_assigned_identity.app     # owned by bootstrap, role already granted
azurerm_storage_account.votes               # shared_access_key_enabled = false
azurerm_storage_table.votes                 # "votes", storage_account_id = ...
azurerm_container_app_environment.this
azurerm_container_app.poll                  # identity { type = "UserAssigned" }, min_replicas = 0
```

Rules:

- Provider block: `storage_use_azuread = true`. In azurerm 5.x the table is managed through the data plane, so with keys off Terraform must use Entra ID. One line, one sentence for the room.
- Variables: `environment` (with a `validation` block: `dev` or `prod`), `storage_account_name`, `poll_question`, `poll_options` (`list(string)`, joined with `join("|", …)` for the app), `poll_color`, `app_image_tag`.
- `envs/{env}.tfvars` holds the poll, the colour, the storage account name and the image tag (a git SHA, bumped by hand). Everything else is shared code.
- Backend: partial config. `backend "azurerm" {}` + `-backend-config=envs/{env}.backend.hcl`, `use_azuread_auth = true`.
- Outputs: `poll_url`, `results_url`.
- The subscription comes from `ARM_SUBSCRIPTION_ID` (laptop shell and CI), never from a committed file. The location comes from the resource group.
- `main.tf` + `variables.tf` double as the annotated slides. Together they must show a data source (the app identity from bootstrap), a cross-resource reference (the table → the storage account, the app → the identity), and the `validation` block. One-line comments, like slide callouts.

---

## 6. CI/CD: `.github/workflows/terraform.yml`

| Trigger | Does |
|---|---|
| `pull_request` touching `infra/**` | `fmt -check` → `init` (prod backend) → `validate` → `plan`. Posts or updates **one PR comment**: first line `Plan: X to add, Y to change, Z to destroy`, full plan in a collapsed `<details>`. |
| `push` to `main` touching `infra/**`, and `workflow_dispatch` | same steps, then `plan -out=tfplan` → `apply tfplan` |

- Azure login through OIDC: `ARM_USE_OIDC=true` plus `ARM_CLIENT_ID / ARM_TENANT_ID / ARM_SUBSCRIPTION_ID` from repo variables. No secrets stored.
- `concurrency: terraform-prod`, `cancel-in-progress: false`. CI's own queue, on top of the state lock.
- `permissions`: `id-token: write`, `contents: read`, `pull-requests: write`.
- Forked PRs get no OIDC token, which is why the repo can be public.
- Slide-only talking points: in real life plan uses a read-only identity, prod apply waits for an approval, and a drift check runs on a schedule.

`app-image.yml`: on push to `main` touching `app/**`, run pytest, build `linux/amd64`, push `:<git-sha>` to GHCR.

---

## 7. The session: 5 beats

**Starting state:** bootstrap applied. prod deployed by CI the day before. dev empty. Laptop `init`ed against the dev backend. `infra/` on `main` matches tag `session-start`. Tabs: prod `/results`, the repo, the portal.

| # | Beat | Where | Do | The room sees |
|---|---|---|---|---|
| 0 | Teaser | prod | QR on screen, the room votes. Explain nothing. | their votes on the projector |
| 1 | plan → apply | dev, laptop | `init -backend-config=envs/dev.backend.hcl`, `fmt`, `validate`, `plan -var-file=envs/dev.tfvars`, read it out loud, `apply` | `+ create` becomes a working dev URL, orange `DEV` badge |
| 2 | Remote state + locking | dev | Portal: the `tfstate` container, versioning, keys off. Terminal A: `apply`, stop at `Enter a value:`. Terminal B: `plan` → `Error acquiring the state lock`. Portal: blob is **Leased**. B: `plan -lock-timeout=120s`, A: `yes`. | who holds the lock, and B continuing once A finishes |
| 3 | A PR changes the phones | prod, CI | The room picks a question. Edit `envs/prod.tfvars` on a branch, push, open a PR. Walk through `terraform.yml` while it runs. Merge. | `0 to add, 1 to change, 0 to destroy`, then the phones change |
| 4 | Not all changes are equal | prod, CI | PR: rename the table `votes` → `pollvotes`. Read `-/+ … forces replacement`, `1 to destroy`. **Close it.** PR: add `prevent_destroy` to the account and table. Merge. | one-line diff, data-deleting plan; then the guardrail |
| 5 | Drift | prod | Portal: change `POLL_QUESTION` on the Container App. Then `gh workflow run terraform.yml`. | phones show the new question at zero votes; the plan log shows `~` drift; apply puts the room's question back with its votes |

Notes:

- Beat 2: with the default `-lock-timeout=0s` the second command **fails at once**. It does not wait. Say this correctly. Name `force-unlock` as the dangerous escape hatch.
- Beat 5: *"Why can I even do this? I'm subscription Owner. Real fix: nobody but CI has write on prod."* Fallback if the portal is slow: `az containerapp update -n ca-livepoll-prod -g rg-livepoll-prod --set-env-vars POLL_QUESTION="Is Terraform overrated?"`.
- Rehearsal rule: if Beat 1's apply takes over 5 min, start it before the slide that comes before it.

---

## 8. Reset between sessions

Both routes are documented in `RUNBOOK.md`. Run the day before.

**A. Script (`scripts/reset.sh`), fast:**

1. Restore `infra/` from the `session-start` tag as a normal commit on `main` and push. CI applies prod back to the starting question. No force-push: history is kept, and changes outside `infra/` are never lost.
2. `terraform destroy` dev with the restored code, which has no `prevent_destroy`.
3. Close leftover PRs. Wait for the CI run, then `curl -fsS <prod>/healthz`, and scan the QR yourself.

**B. Through a PR, the "proper" way:** the same `git restore` on a branch, a PR, read the plan, merge. Destroy dev from the laptop as in A.2.

---

## 9. To verify during implementation

1. Renaming `azurerm_storage_table` forces replacement in 5.8 (Beat 4 depends on it).
2. The azurerm backend and provider pick up `ARM_USE_OIDC` in CI without `azure/login`.
3. Container Apps environment creation time (the Beat 1 rehearsal rule).
4. The app gets a token for its identity on the first request after deploy (the banner should not show).

---

## 10. Build order

| # | Milestone | Done when |
|---|---|---|
| M1 | Repo + app | New repo exists, `app/` copied and trimmed, tests pass, `docker compose up` works |
| M2 | bootstrap | Applied, state migrated, Actions variables set |
| M3 | infra on dev | Apply from the laptop → working dev URL, votes stored via managed identity |
| M4 | CI + prod | A PR shows a plan comment. Merge → prod URL works. `workflow_dispatch` reverts a portal edit. |
| M5 | Runbook + reset | `RUNBOOK.md` covers all 5 beats. Both reset routes return to the starting state. |
| M6 | Rehearsal | One full run alone, from reset to Beat 5, timed |

**Definition of done:** the presenter runs one full rehearsal alone, from reset to Beat 5, without help.
