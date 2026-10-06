# Runbook: presenting Live Poll

One presenter, five beats, about 75 minutes of demo between the slides.

> **Rule:** one failed command is a teaching moment. Two in a row: switch to the recording.

All commands run from the repo root unless a step says otherwise.

---

## Before the session

### The day before (~15 min)

1. Run `scripts/reset.sh` (see [Reset](#reset)). This leaves prod on the starting question and dev empty.
2. Open prod `/results` and scan the QR code with your own phone. Vote once.

### Morning of (~10 min)

| # | Do | Check |
|---|---|---|
| 1 | `az login` → `az account show --query name` | your subscription |
| 2 | `gh auth status` | logged in as JiDarwish |
| 3 | Open two terminals, **A** and **B**, both in `infra/`, with a big font | |
| 4 | In both: `export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)` | |
| 5 | In A: `terraform init -backend-config=envs/dev.backend.hcl` → `terraform plan -var-file=envs/dev.tfvars` | `4 to add` (dev is empty) |
| 6 | Browser tabs: prod `/results` · repo → Actions · portal → `stlivepolltfjd01` → `tfstate` container · portal → `ca-livepoll-prod` | |
| 7 | `git switch main && git pull` | clean tree |

**One minute before the teaser:** reload prod `/results`. The app scales to zero, and the first request takes 10–20 s.

---

## Beat 0: Teaser · 5 min · prod

| # | Where | Do | Room sees | Say |
|---|---|---|---|---|
| 1 | browser | prod `/results` on the projector | the QR code, empty bars | "Scan it, vote." |
| 2 | | wait for about 20 votes | bars move live | "By the end of the day you'll know how this got here." |

Explain nothing.

---

## Beat 1: plan → apply · 15 min · dev, laptop

| # | Where | Do | Room sees | Say |
|---|---|---|---|---|
| 1 | editor | open `infra/main.tf`, then `variables.tf` | the code | data source, reference, validation (the slide callouts) |
| 2 | A | `terraform fmt -check && terraform validate` | `Success!` | "Syntax and logic, before we talk to Azure." |
| 3 | A | `terraform plan -var-file=envs/dev.tfvars` | `4 to add` | Read it out loud. Count the `+`. Ask: "What will happen?" |
| 4 | A | `terraform apply -var-file=envs/dev.tfvars` → `yes` | resources being created | Fill the wait: portal → `rg-livepoll-dev` fills up. The Container Apps environment is the slow part. |
| 5 | A | `terraform output results_url` → open it | orange **DEV** badge, a different question | "Same app as your phones, different environment." |

**Closing line:** *"The .tf file is what I want. The state file is what Terraform did. Plan is the difference."*

| If it breaks | Cause | Live response |
|---|---|---|
| `Error acquiring the state lock` | terminal B still holds it | Wait for B, or rerun with `-lock-timeout=60s` |
| The dev page shows "Can't reach the vote store" | the identity token is still warming up | Reload after 30 s. It retries on its own. |
| The apply takes more than 5 min | the Container Apps environment is slow | Go to the next slide and come back |

---

## Beat 2: Remote state + locking · 15 min · dev

| # | Where | Do | Room sees | Say |
|---|---|---|---|---|
| 1 | portal | `stlivepolltfjd01` → `tfstate` → `infra-dev.tfstate` | the state file, in Azure | "The same JSON as a local `terraform.tfstate`, but shared, versioned, and only some people can read it." |
| 2 | portal | Data protection: versioning, soft delete. Configuration: account key access **disabled** | the settings | "No keys. You need an Entra ID role to read it." |
| 3 | A | `terraform apply -var-file=envs/dev.tfvars -var 'poll_color=#8e44ad'` → **stop at `Enter a value:`** | the plan, waiting | "I'm holding the lock now." |
| 4 | B | `terraform plan -var-file=envs/dev.tfvars` | `Error acquiring the state lock`, with Who and Created | "It fails **at once**. It doesn't wait. And it tells you who holds the lock." |
| 5 | portal | refresh `infra-dev.tfstate` | **Lease state: Leased** | "The lock is a lease on this blob." |
| 6 | B | `terraform plan -var-file=envs/dev.tfvars -lock-timeout=120s` | waiting… | "Now it waits up to 2 minutes." |
| 7 | A | type `yes` | A applies, then B continues with its plan | The dev page turns purple. |

Mention, don't run: `terraform force-unlock`, the escape hatch for a crashed run. *"If you use it while someone is applying, you corrupt state."*

| If it breaks | Cause | Live response |
|---|---|---|
| B's plan doesn't error | A wasn't at the prompt yet, or A had no changes | Make sure A shows `Enter a value:`. The `-var poll_color` gives it a change. |
| The portal doesn't show Leased | the blob view is stale | Click refresh on the blob properties |

---

## Beat 3: A PR changes the phones · 15 min · prod, CI

| # | Where | Do | Room sees | Say |
|---|---|---|---|---|
| 1 | room | The room picks a new question and 2–4 options | | |
| 2 | A | `git switch main && git pull && git switch -c room-question` | | |
| 3 | editor | change `poll_question` and `poll_options` in `infra/envs/prod.tfvars` | a two-line diff | "I'm not touching prod. I'm proposing a change." |
| 4 | A | `git commit -am "prod: the room's question" && git push -u origin room-question && gh pr create --fill` | the PR | |
| 5 | browser | while CI runs: open `.github/workflows/terraform.yml` | OIDC, `fmt`/`validate`/`plan` | "No secrets. GitHub proves who it is to Azure." |
| 6 | browser | the PR comment | `Plan: 0 to add, 1 to change, 0 to destroy` | Read the `~ value` diff out loud |
| 7 | browser | **Merge** → Actions → the run on `main` | plan + apply | |
| 8 | projector | prod `/results` | **the phones change**, votes at 0 | *"Nobody touched prod. The pipeline did, after a human read the plan."* |
| 9 | A | `git switch main && git pull` | | |

CI from PR to phones takes about 2–3 min (measured: PR plan ~40 s, apply on `main` 1–2 min, then the new revision starts). If the run is slow, fill the time with the workflow walkthrough.

| If it breaks | Cause | Live response |
|---|---|---|
| CI fails at `fmt -check` | a formatting slip in tfvars | `terraform fmt -recursive`, commit, push. *"That's what the check is for."* |
| CI fails at `init` with `AADSTS700213` | the OIDC subject doesn't match | Switch to the recording. Fix afterwards: see `ji_learning.md` §3 |
| The phones show the old question | the new revision is still starting | Wait 30 s. The footer's revision name changes when it's live. |

---

## Beat 4: Not all changes are equal · 15 min · prod, CI

| # | Where | Do | Room sees | Say |
|---|---|---|---|---|
| 1 | A | `git switch main && git pull && git switch -c rename-table` | | |
| 2 | editor | `infra/main.tf`: `azurerm_storage_table.votes` → `name = "pollvotes"` | a one-line diff | "Just a nicer name, right?" |
| 3 | A | `git commit -am "rename votes table" && git push -u origin rename-table && gh pr create --fill` | | |
| 4 | browser | the PR comment | `1 to add, 1 to change, 1 to destroy`, `-/+ … forces replacement` | *"CI just told us this PR deletes every vote you cast today."* |
| 5 | browser | **Close** the PR. Don't merge. | | |
| 6 | A | `git switch main && git switch -c protect-data` | | |
| 7 | editor | add `lifecycle { prevent_destroy = true }` to `azurerm_storage_account.votes` and `azurerm_storage_table.votes` | | |
| 8 | A | `git commit -am "protect the vote store" && git push -u origin protect-data && gh pr create --fill` → merge | `0 to add, 0 to change, 0 to destroy` | "Nothing changes in Azure. It changes what Terraform is *allowed* to do." |
| 9 | browser | optional: **Reopen** the rename PR | CI goes red: `Instance cannot be destroyed` | *"For anything holding data, this one line turns an accident into an error message."* |

Step 9 works because PR checks run on the PR merged with the current `main`, which now has `prevent_destroy`. Close the PR again afterwards.

| If it breaks | Cause | Live response |
|---|---|---|
| The rename plan shows only `~ update` | the provider changed its behaviour | Say so honestly. Show `-/+` in the slides. (Checked in rehearsal M6.) |

---

## Beat 5: Drift · 10 min · prod

| # | Where | Do | Room sees | Say |
|---|---|---|---|---|
| 1 | portal | `ca-livepoll-prod` → Application → Containers → **Edit and deploy** → `poll` → Environment variables → `POLL_QUESTION` = `Is Terraform overrated?` → Save → **Create** | | "A colleague, fixing something in prod at 2am." |
| 2 | projector | prod `/results` | the new question, **0 votes** | "Where did your votes go?" |
| 3 | | | | *"Why can I even do this? I'm subscription Owner. Real fix: nobody but CI has write on prod."* |
| 4 | A | `gh workflow run terraform.yml --ref main` (or Actions → terraform → Run workflow) | | "Run the pipeline. No code change." |
| 5 | browser | the run's **Summary** | `~ value = "Is Terraform overrated?" -> "<the room's question>"` | "Plan shows the drift **before** it fixes it." |
| 6 | projector | prod `/results` | the room's question is back, **with its votes** | *"The code is the truth. A hand change lasts until the next pipeline run."* |

Fallback if the portal is slow:

```sh
az containerapp update -n ca-livepoll-prod -g rg-livepoll-prod --set-env-vars POLL_QUESTION="Is Terraform overrated?"
```

| If it breaks | Cause | Live response |
|---|---|---|
| The plan shows `No changes` | the portal edit didn't save as a new revision | Check the revision list. Use the `az` fallback. |
| The votes don't come back | the options changed too | That's expected: `poll_id` hashes question + options |

---

## Reset

Run the day before every session. Pick one route.

### A. Script (~10 min)

```sh
scripts/reset.sh
```

| Step | What it does |
|---|---|
| 1 | Restores `infra/` from the `session-start` tag as a **normal commit** on `main`. No force-push, so history is kept. CI applies prod back to the starting question. |
| 2 | `terraform destroy` on dev, using the session-start code, which has no `prevent_destroy` |
| 3 | Closes leftover PRs and deletes their branches |
| 4 | Waits for the CI run, then checks prod `/healthz` |

### B. Through a PR (~15 min, the "proper" way)

```sh
git switch main && git pull && git switch -c reset
git restore --source=session-start -- infra/
git commit -m "reset: infra/ back to session-start" && git push -u origin reset
gh pr create --fill          # read the plan: the question goes back, prevent_destroy goes away
# merge in the browser, then destroy dev from the laptop:
cd infra && terraform init -reconfigure -backend-config=envs/dev.backend.hcl
terraform destroy -var-file=envs/dev.tfvars
```

### Moving the starting point

`session-start` is a git tag. If you improve `infra/` for future sessions, move the tag:

```sh
git tag -f session-start main && git push -f origin session-start
```

The tag is the only thing that is force-pushed, and only when you move it on purpose.
