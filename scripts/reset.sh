#!/usr/bin/env bash
# Puts the demo back to its starting state: prod runs the session-start code, dev is empty.
# Run the day before a session, from anywhere in the repo:  scripts/reset.sh
#
# No force-push: infra/ is restored from the session-start tag as a normal commit on main,
# so history is kept and changes outside infra/ (runbook, app) are never lost.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)

read -r -p "This destroys dev and resets prod to session-start. Continue? [y/N] " answer
[[ "$answer" == "y" ]] || exit 1

echo "== 1/4 infra/ back to the session-start tag"
git switch main
git pull --ff-only
git restore --source=session-start -- infra/
if git diff --quiet -- infra/; then
  echo "infra/ already matches session-start. Running the workflow anyway, to undo any drift."
  gh workflow run terraform.yml --ref main
else
  git commit -m "reset: infra/ back to session-start" -- infra/
  git push # a push to main touching infra/ makes CI plan + apply prod
fi

echo "== 2/4 destroy dev (session-start code has no prevent_destroy)"
terraform -chdir=infra init -input=false -reconfigure -backend-config=envs/dev.backend.hcl
terraform -chdir=infra destroy -input=false -auto-approve -var-file=envs/dev.tfvars

echo "== 3/4 close leftover PRs"
for pr in $(gh pr list --state open --json number -q '.[].number'); do
  gh pr close "$pr" --delete-branch
done

echo "== 4/4 wait for CI to apply prod, then check it"
sleep 10 # give GitHub a moment to register the run
run_id=$(gh run list --workflow terraform.yml --branch main -L 1 --json databaseId -q '.[0].databaseId')
gh run watch "$run_id" --exit-status
prod_rg=$(sed -nE 's/^resource_group_name *= *"(.*)"/\1/p' infra/envs/prod.tfvars)
fqdn=$(az containerapp show -n ca-livepoll-prod -g "$prod_rg" --query properties.configuration.ingress.fqdn -o tsv)
curl -fsS "https://$fqdn/healthz" && echo
echo "Done. Open https://$fqdn/results and scan the QR code with your own phone."
