# Runbook: Live Poll

**75 min of demo · 5 beats · you're alone · follow the numbers.**

> One failed command = a teaching moment. Two in a row = play the recording.

Each step reads: ▶ **do** · 👀 **the room sees** · 🗣 **say**.

---

## At a glance

| Clock | Beat | Where | The one thing the room must get |
|---|---|---|---|
| 0:00 | **0** Teaser | prod | "You're voting on something Terraform built." |
| 0:05 | **1** plan → apply | dev · laptop | Plan shows what will happen *before* it happens. |
| 0:20 | **2** State + locking | dev | State lives in Azure. One writer at a time. |
| 0:35 | **3** A PR changes the phones | prod · CI | Only the pipeline changes prod. |
| 0:50 | **4** Not all changes are equal | prod · CI | `-/+` in a plan can delete data. |
| 1:05 | **5** Drift | prod | The code is the truth. |
| 1:15 | done | | |

The clock counts demo minutes only. Slides in between come on top.

---

## Before: the day before · 15 min

- [ ] Run `scripts/reset.sh`. This leaves prod on the starting question and dev empty. See [Reset](#after-reset).
- [ ] Scan the prod QR code with your own phone and vote once.

## Before: the morning of · 10 min

**Terminals**

- [ ] `az login`, then `az account show --query name` → shows your subscription
- [ ] `gh auth status` → shows JiDarwish
- [ ] Open terminals **A** and **B**, both in `infra/`, with a big font. In both:
  ```sh
  export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
  ```
- [ ] In A:
  ```sh
  terraform init -backend-config=envs/dev.backend.hcl
  terraform plan -var-file=envs/dev.tfvars      # expect: 4 to add (dev is empty)
  ```
- [ ] `git switch main && git pull` → clean tree

**Browser tabs, left to right**

1. prod `/results`
2. repo → Actions
3. portal → `stlivepolltfjd01` → `tfstate` container
4. portal → `ca-livepoll-prod`

- [ ] **1 min before the teaser:** reload prod `/results`. The app scales to zero, and the first request takes 10–20 s.

---

## Beat 0 · Teaser · 5 min · prod

**Goal:** the room votes. Explain nothing.

1. ▶ prod `/results` on the projector\
   🗣 "Scan it, vote."
2. ▶ Wait for about 20 votes\
   👀 the bars move live\
   🗣 "By the end of the day you'll know how this got here."

---

## Beat 1 · plan → apply · 15 min · dev · terminal A

**Goal:** plan shows what will happen before it happens.

1. ▶ Show `infra/main.tf`, then `variables.tf`\
   🗣 Point at the data source, a reference, and the validation block.
2. ▶ `terraform fmt -check && terraform validate`\
   👀 `Success!`\
   🗣 "Syntax and logic, before we talk to Azure."
3. ▶ `terraform plan -var-file=envs/dev.tfvars`\
   👀 `4 to add`\
   🗣 Read it out loud. Count the `+`. Ask: "What will happen?"
4. ▶ `terraform apply -var-file=envs/dev.tfvars` → `yes`\
   👀 portal → `rg-livepoll-dev` fills up while it waits\
   🗣 "The Container Apps environment is the slow one."
5. ▶ `terraform output results_url` → open it\
   👀 orange **DEV** badge, a different question\
   🗣 "Same app as your phones, different environment."

🎤 **Close:** *"The .tf file is what I want. The state file is what Terraform did. Plan is the difference."*

**If it breaks**

- `Error acquiring the state lock` → terminal B holds it. Wait, or add `-lock-timeout=60s`.
- "Can't reach the vote store" → the identity token is still warming up. Reload after 30 s.
- The apply takes over 5 min → go to the next slide and come back.

---

## Beat 2 · State + locking · 15 min · dev

**Goal:** state lives in Azure. Only one writer at a time.

### 2a · Where state lives (portal)

1. ▶ `stlivepolltfjd01` → `tfstate` → `infra-dev.tfstate`\
   🗣 "The same JSON as a local `terraform.tfstate`. But it's shared, versioned, and only some people can read it."
2. ▶ Data protection (versioning, soft delete), then Configuration (account key access **disabled**)\
   🗣 "No keys. You need an Entra ID role to read it."

### 2b · Hold the lock (two terminals)

1. ▶ **A:**
   ```sh
   terraform apply -var-file=envs/dev.tfvars -var 'poll_color=#8e44ad'
   ```
   **Stop at `Enter a value:`.**\
   🗣 "I'm holding the lock now."
2. ▶ **B:** `terraform plan -var-file=envs/dev.tfvars`\
   👀 `Error acquiring the state lock`, with Who and Created\
   🗣 "It fails **at once**. It doesn't wait. And it tells you who holds the lock."
3. ▶ Portal: refresh `infra-dev.tfstate`\
   👀 **Lease state: Leased**\
   🗣 "The lock is a lease on this blob."
4. ▶ **B:** `terraform plan -var-file=envs/dev.tfvars -lock-timeout=120s`\
   🗣 "Now it waits, up to 2 minutes."
5. ▶ **A:** type `yes`\
   👀 A applies, B continues, and the dev page turns purple

🗣 Mention, don't run: `terraform force-unlock`. *"It's for a crashed run. Use it while someone is applying and you corrupt state."*

**If it breaks**

- B doesn't error → A wasn't at `Enter a value:` yet. The `-var poll_color` is what gives A a change to wait on.
- The portal doesn't show Leased → click refresh on the blob properties.

---

## Beat 3 · A PR changes the phones · 15 min · prod · CI

**Goal:** nobody touches prod. The pipeline does, after a human reads the plan.

### 3a · Propose

1. ▶ The room picks a new question and 2–4 options
2. ▶ **A:** `git switch main && git pull && git switch -c room-question`
3. ▶ Edit `poll_question` and `poll_options` in `infra/envs/prod.tfvars`\
   🗣 "I'm not touching prod. I'm proposing a change."
4. ▶ **A:**
   ```sh
   git commit -am "prod: the room's question"
   git push -u origin room-question
   gh pr create --fill
   ```

### 3b · Review and ship · CI takes about 2–3 min

1. ▶ While CI runs: open `.github/workflows/terraform.yml`\
   🗣 "No secrets. GitHub proves who it is to Azure."
2. ▶ The PR comment\
   👀 `Plan: 0 to add, 1 to change, 0 to destroy`\
   🗣 Read the `~ value` line out loud.
3. ▶ **Merge** → Actions → the run on `main`
4. ▶ Projector: prod `/results`\
   👀 **the phones change**, votes at 0
5. ▶ **A:** `git switch main && git pull`

🎤 **Close:** *"Nobody touched prod. The pipeline did, after a human read the plan."*

**If it breaks**

- CI fails at `fmt -check` → run `terraform fmt -recursive`, commit, push. 🗣 "That's what the check is for."
- CI fails at `init` with `AADSTS700213` → the OIDC subject doesn't match. Play the recording, and fix it afterwards (`ji_learning.md` §3).
- The phones still show the old question → the new revision is starting. Wait 30 s; the footer's revision name changes when it's live.

---

## Beat 4 · Not all changes are equal · 15 min · prod · CI

**Goal:** a one-line diff can delete data. Read the plan.

### 4a · The dangerous PR

1. ▶ **A:** `git switch main && git pull && git switch -c rename-table`
2. ▶ `infra/main.tf`, in `azurerm_storage_table.votes`: `name = "pollvotes"`\
   🗣 "Just a nicer name, right?"
3. ▶ **A:**
   ```sh
   git commit -am "rename votes table"
   git push -u origin rename-table
   gh pr create --fill
   ```
4. ▶ Read the PR comment\
   👀 `1 to add, 1 to change, 1 to destroy` and `-/+ … forces replacement`\
   🗣 *"CI just told us this PR deletes every vote you cast today."*
5. ▶ **Close** the PR. Do not merge.

### 4b · The guardrail

1. ▶ **A:** `git switch main && git switch -c protect-data`
2. ▶ Add to **both** `azurerm_storage_account.votes` and `azurerm_storage_table.votes`:
   ```hcl
   lifecycle {
     prevent_destroy = true
   }
   ```
3. ▶ **A:** commit, push, `gh pr create --fill`, then **merge**\
   👀 `0 to add, 0 to change, 0 to destroy`\
   🗣 "Nothing changes in Azure. It changes what Terraform is *allowed* to do."

### 4c · Optional: prove it

1. ▶ **Reopen** the rename PR\
   👀 CI goes red: `Instance cannot be destroyed`\
   🗣 *"For anything holding data, this one line turns an accident into an error message."*
2. ▶ Close it again.

This works because PR checks run on the PR merged with the current `main`, which now has `prevent_destroy`.

**If it breaks**

- The rename plan shows only `~ update` → the provider changed its behaviour. Say so honestly, and show `-/+` on the slide. (Checked in rehearsal M6.)

---

## Beat 5 · Drift · 10 min · prod

**Goal:** the code is the truth. A hand change lasts until the next pipeline run.

1. ▶ Portal → `ca-livepoll-prod` → Application → Containers → **Edit and deploy** → `poll` → Environment variables → `POLL_QUESTION` = `Is Terraform overrated?` → Save → **Create**\
   🗣 "A colleague, fixing something in prod at 2am."
2. ▶ Projector: prod `/results`\
   👀 the new question, **0 votes**\
   🗣 "Where did your votes go? And why can I even do this? I'm subscription Owner. Real fix: nobody but CI has write on prod."
3. ▶ **A:** `gh workflow run terraform.yml --ref main`\
   🗣 "Run the pipeline. No code change."
4. ▶ The run's **Summary** page\
   👀 `~ value = "Is Terraform overrated?" -> "<the room's question>"`\
   🗣 "Plan shows the drift **before** it fixes it."
5. ▶ Projector: prod `/results`\
   👀 the room's question is back, **with its votes**

🎤 **Close:** *"The code is the truth. A hand change lasts until the next pipeline run."*

**Fallback if the portal is slow** (replaces step 1):

```sh
az containerapp update -n ca-livepoll-prod -g rg-livepoll-prod --set-env-vars POLL_QUESTION="Is Terraform overrated?"
```

**If it breaks**

- The plan says `No changes` → the portal edit didn't save as a new revision. Use the fallback.
- The votes don't come back → the options changed too. That's expected: `poll_id` hashes question + options.

---

## After: reset

Do this the day before the next session. Pick **one** route.

### Route A · Script · ~10 min

```sh
scripts/reset.sh
```

What it does:

1. Restores `infra/` from the `session-start` tag as a **normal commit** on `main`, so no force-push. CI applies prod back to the starting question.
2. Runs `terraform destroy` on dev, with the session-start code (no `prevent_destroy`).
3. Closes leftover PRs and deletes their branches.
4. Waits for CI, then checks prod `/healthz`.

### Route B · Through a PR · ~15 min

```sh
git switch main && git pull && git switch -c reset
git restore --source=session-start -- infra/
git commit -m "reset: infra/ back to session-start" && git push -u origin reset
gh pr create --fill     # read the plan: the question goes back, prevent_destroy goes away
```

Merge in the browser, then destroy dev from the laptop:

```sh
cd infra && terraform init -reconfigure -backend-config=envs/dev.backend.hcl
terraform destroy -var-file=envs/dev.tfvars
```

### Moving the starting point

If you improve `infra/` for future sessions, move the tag:

```sh
git tag -f session-start main && git push -f origin session-start
```

This is the only force-push, and only when you move the tag on purpose.
