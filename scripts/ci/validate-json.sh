#!/usr/bin/env bash
# validate-json.sh - parse every *.json file under the given paths (default: repo root)
# with Python's json module and report any file that is not valid JSON.
#
# Used by .github/workflows/ci.yml (job: arm-ttk) and the Azure DevOps pipelines.
# Emits GitHub Actions or Azure Pipelines error annotations when run inside CI.
#
# Usage: scripts/ci/validate-json.sh [PATH ...]
set -euo pipefail

paths=("$@")
if [ ${#paths[@]} -eq 0 ]; then
  paths=(".")
fi

# Directories that are generated, vendored or cloned in CI and must not be linted.
prune=(
  -path '*/.git' -o
  -path '*/node_modules' -o
  -path '*/.terraform' -o
  -path '*/arm-ttk' -o
  -path '*/.venv' -o
  -path '*/venv' -o
  -path '*/dist' -o
  -path '*/build' -o
  -path '*/.databricks' -o
  -path '*/.vscode'
)

annotate() {
  local file="$1" message="$2"
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "::error file=${file}::${message}"
  elif [ -n "${TF_BUILD:-}" ]; then
    echo "##vso[task.logissue type=error;sourcepath=${file}]${message}"
  fi
  echo "ERROR ${file}: ${message}" >&2
}

total=0
failed=0
while IFS= read -r -d '' file; do
  total=$((total + 1))
  # -I runs Python in isolated mode so a stray module next to the data cannot be imported.
  if ! err=$(python3 -I -m json.tool "$file" 2>&1 >/dev/null); then
    failed=$((failed + 1))
    annotate "$file" "$(echo "$err" | tail -n 1)"
  fi
done < <(find "${paths[@]}" \( "${prune[@]}" \) -prune -o -type f -name '*.json' -print0 | sort -z)

echo "Checked ${total} JSON file(s); ${failed} invalid."
[ "$failed" -eq 0 ]
