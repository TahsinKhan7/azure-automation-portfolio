#!/usr/bin/env bash
# terraform-validate-all.sh - discover every Terraform module and environment root
# and run `terraform init -backend=false` + `terraform validate` in each one.
#
# The same script is used by GitHub Actions (.github/workflows/ci.yml) and the
# Azure DevOps pipeline (azure-devops-pipelines/terraform-plan-apply.yml), so the
# discovery and validation logic lives in exactly one place.
#
# Usage:
#   scripts/ci/terraform-validate-all.sh [--fmt] [DIR ...]
#   scripts/ci/terraform-validate-all.sh --list
#
#   --fmt      also run `terraform fmt -check -recursive` over TF_ROOT first
#   --list     print the discovered directories as a JSON array (for CI matrices) and exit
#   DIR ...    validate only these directories instead of discovering them
#
# Environment:
#   TF_ROOT    repository folder that holds modules/ and environments/ (default: terraform)
set -euo pipefail

TF_ROOT="${TF_ROOT:-terraform}"
run_fmt=false
list_only=false
dirs=()

while [ $# -gt 0 ]; do
  case "$1" in
    --fmt) run_fmt=true ;;
    --list) list_only=true ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) dirs+=("$1") ;;
  esac
  shift
done

discover() {
  # A directory counts as a Terraform configuration when it directly contains a .tf file.
  for parent in "${TF_ROOT}/modules" "${TF_ROOT}/environments"; do
    [ -d "$parent" ] || continue
    find "$parent" -mindepth 1 -maxdepth 1 -type d | sort | while IFS= read -r d; do
      if compgen -G "${d}/*.tf" >/dev/null; then
        echo "$d"
      fi
    done
  done
}

if [ ${#dirs[@]} -eq 0 ]; then
  mapfile -t dirs < <(discover)
fi

if [ "$list_only" = true ]; then
  if [ ${#dirs[@]} -eq 0 ]; then
    echo "[]"
  else
    printf '%s\n' "${dirs[@]}" | python3 -I -c 'import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))'
  fi
  exit 0
fi

if [ "$run_fmt" = true ]; then
  echo "==> terraform fmt -check -recursive ${TF_ROOT}"
  terraform fmt -check -recursive -diff "$TF_ROOT"
fi

if [ ${#dirs[@]} -eq 0 ]; then
  echo "No Terraform configurations found under ${TF_ROOT}/modules or ${TF_ROOT}/environments." >&2
  exit 1
fi

failed=()
for d in "${dirs[@]}"; do
  echo "==> ${d}"
  if terraform -chdir="$d" init -backend=false -input=false -no-color >/dev/null \
     && terraform -chdir="$d" validate -no-color; then
    echo "    ok"
  else
    echo "    FAILED"
    failed+=("$d")
  fi
done

echo
echo "Validated ${#dirs[@]} configuration(s); ${#failed[@]} failed."
if [ ${#failed[@]} -gt 0 ]; then
  printf '  - %s\n' "${failed[@]}"
  exit 1
fi
