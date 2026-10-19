# ADR 0004: Keep ARM JSON templates alongside Bicep (and Terraform)

Status: accepted

## Context

Many enterprise Azure estates still standardise on ARM JSON: existing Template Specs, ARM-TTK gates in their pipelines, change-management processes that sign off what-if output, and operators who read JSON rather than Bicep. Others have moved to Bicep, and platform teams frequently choose Terraform. A portfolio that showed only one would not reflect the decision a real team has to make.

## Decision

Maintain three expressions of the same platform design, each complete and independently validated:

- [`arm-templates/`](../../arm-templates/): linked ARM JSON modules published as a Template Spec, validated by ARM-TTK, offline parity checks, `Test-AzResourceGroupDeployment` and what-if, wrapped in a documented release process ([`docs/release-management`](../release-management/)).
- [`arm-bicep/`](../../arm-bicep/): a `main.bicep` composition with an environment sizing map, `.bicepparam` per environment and linter rules at `error` for secret handling.
- [`terraform/`](../../terraform/): the primary toolchain for multi-cloud-literate platform teams, with native tests.

Naming, environment semantics and hardening switches are kept identical across the three so the choice is purely about toolchain.

## Consequences

- A hiring team can evaluate the toolchain they actually run.
- Three copies of the design must be kept in step; the shared naming contract and the environment matrix are the anchors, and the CI jobs (`arm-ttk`, `bicep-build`, `terraform-validate`) each fail independently.
- ARM JSON is verbose, but it shows `copy` loops, `condition`-gated resources, `secureObject` handling and nested `expressionEvaluationOptions`, which are exactly the features reviewers of legacy estates care about.
- In a real engagement only one toolchain would be chosen; this ADR documents why the repository deliberately does not.
