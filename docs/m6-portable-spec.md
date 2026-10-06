# M6 spec: anyone can run this demo on their own Azure + GitHub

**Status:** draft for review, 2026-10-06
**Goal:** a colleague **forks this repo** and, with their own Azure subscription and GitHub account, goes from zero to their own working demo (dev + prod + their own CI runs) in **about 45 min**, following one guide, without editing Terraform code.
**Rehearsal:** the old M6 (full rehearsal) becomes **M7**.

---

## 1. Decisions for review

| # | Decision | Recommended | Alternative |
|---|---|---|---|
| P1 | How a presenter gets their own copy | **Decided: fork.** Each presenter forks `JiDarwish/terraform-live-poll-demo` and gets their own deployments, CI runs and PRs. Fork specifics in §5.1. | – |
| P2 | Several presenters in one subscription? | **Yes.** Every name gets the presenter's `suffix`, resource groups included. Xomnia colleagues likely share a subscription, and it lets us test M6 in ours. | One presenter per subscription: no resource group rename, no migration (§6), but two copies in one subscription collide |
| P3 | Which app image | **Our public image by default** (`ghcr.io/jidarwish/terraform-live-poll-demo`), so it works on day 1 with no build. Building your own is an optional section. | Every copy builds its own: an extra workflow run plus a manual "make the package public" step |
| P4 | How owner values get in | **`scripts/setup.sh`** asks for 2 things, looks up the rest, and writes the config files. The presenter reviews `git diff` and commits. | A manual table: edit 6 files by hand (kept in the guide as a fallback) |
| P5 | Definition of done | **A fork into a free GitHub organisation you own** (GitHub doesn't let you fork your own repo into your own account), suffix `t1`, **in our subscription**: setup → bootstrap → dev → PR → prod, then teardown | A colleague forks it and runs it in their own subscription (better proof, depends on someone else) |

Sections 2–7 assume the recommended column.

---

## 2. The rule: Terraform code holds no owner values

After M6, every owner-specific value lives in a **config file**. No `.tf` file and no workflow changes per presenter.

| Value | Today | After M6 | Committed? |
|---|---|---|---|
| Subscription, tenant, your object id | `bootstrap/terraform.tfvars` | same | no (gitignored) |
| `suffix` (e.g. `jd01`) | baked into 5 names | `bootstrap/terraform.tfvars` | no |
| GitHub OIDC subject (owner@id/repo@id) | default in `bootstrap/variables.tf` | `bootstrap/terraform.tfvars` | no |
| State account + resource group | `bootstrap/terraform.tf`, `bootstrap/main.tf`, `infra/terraform.tf` | `bootstrap/backend.hcl`, `infra/envs/{env}.backend.hcl` | yes |
| Env resource group, vote account | name built in `main.tf` / in tfvars | `infra/envs/{env}.tfvars` | yes |
| App image | repo hardcoded in `main.tf`, tag in tfvars | `app_image` (repo + tag) in `infra/envs/{env}.tfvars` | yes |
| Image path in `app-image.yml` | `ghcr.io/jidarwish/…` | `ghcr.io/<this repo, lowercase>` | yes, generic |

Committed config is fine: these are names, not secrets, and CI needs them.

---

## 3. Code changes

### 3.1 Naming (`{s}` = suffix, 2–8 lowercase letters/digits)

| Thing | Name |
|---|---|
| Resource groups | `rg-livepoll-{s}-tfstate`, `rg-livepoll-{s}-dev`, `rg-livepoll-{s}-prod` |
| State account | `stlivepolltf{s}` |
| Vote accounts | `stlivepolldev{s}`, `stlivepollprod{s}` (max 22 chars with an 8-char suffix) |
| Everything else | unchanged. Container Apps, identities and the environment are unique per resource group already |

### 3.2 `bootstrap/`

- `terraform.tf`: `backend "azurerm" {}`, partial config. Values come from `backend.hcl` (written by setup): `terraform init -backend-config=backend.hcl`.
- `variables.tf`: add `suffix` (with a `validation` block). `github_repository` loses its default.
- `main.tf`: names built from `var.suffix`.
- `outputs.tf`: add `state_storage_account_name` and the two env resource group names, for the guide.
- The first-run `local_override.tf` trick stays as it is.

### 3.3 `infra/`

- `terraform.tf`: `backend "azurerm" { use_azuread_auth = true }`. The resource group, account and container move into each `envs/{env}.backend.hcl`, so each file is complete on its own. `init` stays one flag: `-backend-config=envs/dev.backend.hcl`.
- `variables.tf`: add `resource_group_name`. Replace `app_image_tag` with `app_image` (full reference, e.g. `ghcr.io/jidarwish/terraform-live-poll-demo:f77630b…`).
- `main.tf`: `data "azurerm_resource_group" "this" { name = var.resource_group_name }`. The image comes from `var.app_image`. The room-facing code gets simpler: no name building.

### 3.4 Workflows

- `app-image.yml`: the image path is derived from `github.repository`, lowercased, so it works in any copy.
- `terraform.yml`: no change. It already reads everything from repo variables and config files.

---

## 4. `scripts/setup.sh` (~80 lines)

Run once, from the new repo's root, after `az login` and `gh auth login`.

| Step | Does |
|---|---|
| 1. Check | `az`, `gh`, `git`, and Terraform `~> 1.16` installed. Logged in to both. Prints the subscription name and asks "use this one? [y/N]" |
| 2. Ask | `suffix` (validated) and `location` (default `westeurope`) |
| 3. Look up | subscription id, tenant id, your object id (`az`). The repo's OIDC subject (`gh api`). Checks that all 3 storage names are free (`az storage account check-name`). Stops if one is taken. |
| 4. Register | `az provider register` for `Microsoft.App`, `Microsoft.Storage`, `Microsoft.ManagedIdentity` (`--wait`) |
| 5. Write | `bootstrap/terraform.tfvars`, `bootstrap/backend.hcl`, `infra/envs/{dev,prod}.backend.hcl`, the name lines in `infra/envs/{dev,prod}.tfvars` |
| 6. Print | the next commands from `SETUP.md`: bootstrap, `gh variable set`, commit, tag |

It does **not** run Terraform. The presenter runs bootstrap by hand, the first time they meet the code.

Safe to rerun: it overwrites only the files above, and `git diff` shows exactly what changed.

---

## 5. `SETUP.md`: the guide (~45 min)

| # | Step | Time |
|---|---|---|
| 1 | **Prerequisites:** Azure subscription where you are Owner (Xomnia's conditioned Owner is enough). GitHub account. `az`, `gh`, Terraform 1.16, Docker (only for running locally). | – |
| 2 | **Fork** → clone your fork → do the fork steps in §5.1 | 5 min |
| 3 | `scripts/setup.sh` | 5 min |
| 4 | **Bootstrap**, first run: local override → `init` → `apply` → remove the override → `init -migrate-state` | 10 min |
| 5 | **GitHub:** `gh variable set` ×3 from the bootstrap outputs | 2 min |
| 6 | **Commit** the config: `git commit -am "configure for <you>"` → push. CI deploys prod. | 5 min |
| 7 | **Tag** the starting point on *your* commit: `git tag -f session-start && git push -f origin session-start` (`-f` because the fork may have copied our tag) | 1 min |
| 8 | **Check:** prod `/results` works, scan the QR code | 2 min |
| 9 | **Try dev** from the laptop (Beat 1 of the runbook), then `terraform destroy` it | 15 min |

### 5.1 Fork specifics (in `SETUP.md` step 2)

A fork behaves differently from a fresh repo in five ways. Each one needs a step or a guard:

| # | Fork behaviour | What breaks | Step or guard |
|---|---|---|---|
| 1 | Workflows are **disabled** in a new fork | nothing runs on push or PR | Actions tab → "I understand my workflows, go ahead and enable them" |
| 2 | `gh pr create` and the web "Compare & pull request" button default to **our** repo as the base | in Beat 3/4 the presenter opens a PR on *our* repo, live in the room | `gh repo set-default <you>/terraform-live-poll-demo` once. Setup checks it, and the runbook's morning-of checklist checks it again. |
| 3 | Repo variables are **not** copied | CI can't log in | `gh variable set` ×3 (already step 5) |
| 4 | The fork has **its own repo id** | our OIDC subject doesn't match their CI | setup builds the subject from *their* fork with `gh api` |
| 5 | A fork of a public repo is **always public** | – | fine: no secrets anywhere. Say so in the guide. |

Two more things:
- **A guard on our side:** `terraform.yml` skips PRs whose head is in another repo (`if: github.event.pull_request.head.repo.full_name == github.repository`). An accidental PR from a fork to our repo then shows a skipped check instead of a red OIDC failure.
- **Syncing with upstream:** "Sync fork" pulls our improvements. A conflict can only happen on the config lines (tfvars, `backend.hcl`) if we change the same line, e.g. bumping the image tag. Rule in the guide: on a conflict in a config file, keep yours.

Plus three short sections:
- **Build your own image** (optional): enable the workflow, make the GHCR package public, then put the new tag in `app_image`.
- **Remove everything:** `az group delete` the 3 resource groups. Role assignments and federated credentials go with them.
- **Troubleshooting:** `AADSTS700213` (wrong subject), a 403 on `migrate-state` (role propagation, wait 2–5 min), storage name taken (pick another suffix), `MissingSubscriptionRegistration` (rerun setup step 4).

`README.md` gets a "Run your own copy → SETUP.md" line. `RUNBOOK.md` uses `<suffix>` in names (e.g. `stlivepolltf<suffix>`). `gh auth status` checks "your account", not JiDarwish.

---

## 6. Migrating our own deployment (one-time, ~45 min)

P2 renames our resource groups (`rg-livepoll-dev` → `rg-livepoll-jd01-dev`). Azure can't rename a resource group, so our copy is rebuilt with suffix `jd01`:

1. `terraform destroy` infra dev, and prod from the laptop (one-time exception, written down)
2. Move bootstrap state back to local, remove `prevent_destroy`, `terraform destroy` bootstrap
3. Run the new `setup.sh` with suffix `jd01` → bootstrap → `gh variable set` → push → CI deploys prod

Consequences:
- The **prod URL changes**, so any QR code printed so far is dead. None is used yet.
- The storage account names stay `stlivepoll*jd01`. Azure may hold a deleted name for a while before it can be reused. If it does, pick `jd02`.

With P2 = "one per subscription", skip this section entirely.

---

## 7. Definition of done

1. `README.md` opens with "Fork this repo, then follow SETUP.md".
2. Our own copy runs on the new layout (§6): dev, prod, PR plan comment, drift fix.
3. **The portability test (P5):** fork into a free GitHub organisation (e.g. `jidarwish-test`), suffix `t1`, same subscription:
   - the fork steps (§5.1) → `setup.sh` → bootstrap → `gh variable set` → push → prod URL works
   - a PR **inside the fork** shows a plan comment, and nothing appears on our repo
   - dev from the laptop works
   - teardown: 3 resource groups deleted, fork deleted
4. Nothing in `*.tf` or `.github/workflows/` contains `jidarwish`, `jd01` or our GitHub IDs. Verified with `grep`.
5. `SETUP.md` was followed **as written** during step 3. Every deviation is fixed in the guide.

---

## 8. Out of scope

- A web UI, Codespaces or a devcontainer for setup
- Azure DevOps or GitLab CI
- Automating the GitHub side with Terraform (the `github` provider). `gh variable set` ×3 is shorter to explain than a PAT.
- Multiple presenters sharing one *repo*. Each presenter has their own copy.
