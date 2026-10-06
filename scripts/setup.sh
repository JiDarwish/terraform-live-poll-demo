#!/usr/bin/env bash
# One-time setup of your fork: checks your tools, asks for a suffix, writes the config files.
# It never runs Terraform. Run it from your fork, after `az login` and `gh auth login`:
#   scripts/setup.sh
# Safe to rerun. `git diff` shows exactly what it wrote. See SETUP.md for the full guide.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

echo "== 1/6 Tools and logins"
for tool in az gh git terraform; do
  command -v "$tool" >/dev/null || { echo "Missing: $tool. See SETUP.md, prerequisites."; exit 1; }
done
terraform version | head -1 | grep -q ' v1\.16\.' || { echo "Terraform 1.16.x is needed: $(terraform version | head -1)"; exit 1; }
az account show >/dev/null 2>&1 || { echo "Run: az login"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Run: gh auth login"; exit 1; }

subscription_name=$(az account show --query name -o tsv)
read -r -p "Use Azure subscription '$subscription_name'? [y/N] " answer
[[ "$answer" == "y" ]] || { echo "Switch with: az account set -s <subscription id>, then rerun."; exit 1; }

# Your fork, from the origin remote: git@github.com:you/repo.git or https://github.com/you/repo.git
repo=$(git remote get-url origin | sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##')
# In a fork, gh and the web UI open PRs against the original repo by default. Point them at yours.
gh repo set-default "$repo"
echo "Your repo: $repo (gh now opens PRs here)"

echo "== 2/6 Your choices"
read -r -p "Suffix, 2-8 lowercase letters/digits (e.g. your initials + 01): " suffix
[[ "$suffix" =~ ^[a-z0-9]{2,8}$ ]] || { echo "Invalid suffix: '$suffix'"; exit 1; }
read -r -p "Azure region [westeurope]: " location
location=${location:-westeurope}

echo "== 3/6 Look up ids and check names"
subscription_id=$(az account show --query id -o tsv)
presenter_object_id=$(az ad signed-in-user show --query id -o tsv)
github_repository=$(gh api "repos/$repo" -q '"\(.owner.login)@\(.owner.id)/\(.name)@\(.id)"')
echo "OIDC subject prefix: repo:$github_repository"

for name in "stlivepolltf$suffix" "stlivepolldev$suffix" "stlivepollprod$suffix"; do
  if [[ "$(az storage account check-name --name "$name" --query nameAvailable -o tsv)" == "true" ]]; then
    echo "  $name: free"
  elif az storage account list --query "[?name=='$name'].id" -o tsv | grep -q .; then
    echo "  $name: already yours (rerun)"
  else
    echo "  $name: taken by someone else in Azure. Rerun with another suffix."; exit 1
  fi
done

echo "== 4/6 Register Azure resource providers (once per subscription, can take a few minutes)"
for provider in Microsoft.App Microsoft.Storage Microsoft.ManagedIdentity; do
  az provider register --namespace "$provider" --wait
  echo "  $provider: registered"
done

echo "== 5/6 Write config files"
cat > bootstrap/terraform.tfvars <<EOF
# Written by scripts/setup.sh. Gitignored: it holds your subscription and object id.
subscription_id     = "$subscription_id"
presenter_object_id = "$presenter_object_id"
suffix              = "$suffix"
location            = "$location"
github_repository   = "$github_repository"
EOF

cat > bootstrap/backend.hcl <<EOF
# Written by scripts/setup.sh.
resource_group_name  = "rg-livepoll-$suffix-tfstate"
storage_account_name = "stlivepolltf$suffix"
container_name       = "tfstate"
key                  = "bootstrap.tfstate"
use_azuread_auth     = true
EOF

for env in dev prod; do
  cat > "infra/envs/$env.backend.hcl" <<EOF
# Written by scripts/setup.sh.
resource_group_name  = "rg-livepoll-$suffix-tfstate"
storage_account_name = "stlivepolltf$suffix"
container_name       = "tfstate"
key                  = "infra-$env.tfstate"
EOF
  # Only the two name lines change. The poll settings stay as they are.
  perl -pi -e "s/^resource_group_name\s*=.*/resource_group_name  = \"rg-livepoll-$suffix-$env\"/;
               s/^storage_account_name\s*=.*/storage_account_name = \"stlivepoll$env$suffix\"/" "infra/envs/$env.tfvars"
done
echo "  bootstrap/terraform.tfvars (gitignored), bootstrap/backend.hcl, infra/envs/{dev,prod}.backend.hcl, infra/envs/{dev,prod}.tfvars"

echo "== 6/6 Next steps"
cat <<EOF

Config written. Review it with:  git diff
Then continue with SETUP.md, step 4 (bootstrap). In short:

  cd bootstrap
  printf 'terraform {\n  backend "local" {}\n}\n' > local_override.tf
  terraform init && terraform apply
  rm local_override.tf && terraform init -migrate-state -backend-config=backend.hcl

Also make sure GitHub Actions is enabled in your fork: https://github.com/$repo/actions
EOF
