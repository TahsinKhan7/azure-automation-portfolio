#!/usr/bin/env python3
"""Static checks for the ARM templates that run before anything touches Azure.

Checks performed:
  1. Every JSON file under templates/ and parameters/ parses.
  2. Every parameter file declares the same set of parameters (environment parity).
  3. Every parameter in a parameter file exists in main.json, and every main.json
     parameter without a default is supplied by every parameter file.
  4. Every nested deployment in main.json passes only parameters the linked module
     declares, and supplies every module parameter that has no default.
  5. Every module parameter and variable is referenced at least once.

Exit code is non-zero when any check fails, so the pipeline step fails fast.

Usage:
  python3 arm-templates/tests/check_templates.py [--root arm-templates]
"""
import argparse
import json
import pathlib
import re
import sys

PARAM_RE = re.compile(r"parameters\('([^']+)'\)")
VAR_RE = re.compile(r"variables\('([^']+)'\)")


def load(path: pathlib.Path):
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", default=pathlib.Path(__file__).resolve().parent.parent, type=pathlib.Path)
    args = parser.parse_args()

    root: pathlib.Path = args.root
    templates_dir = root / "templates"
    parameters_dir = root / "parameters"
    failures: list[str] = []

    def fail(message: str) -> None:
        failures.append(message)
        print(f"FAIL  {message}")

    # 1. Parse everything.
    documents = {}
    for path in sorted(list(templates_dir.rglob("*.json")) + list(parameters_dir.glob("*.json"))):
        try:
            documents[path] = load(path)
            print(f"ok    {path.relative_to(root)} parses")
        except json.JSONDecodeError as exc:
            fail(f"{path.relative_to(root)} is not valid JSON: {exc}")
    if failures:
        return 1

    main_path = templates_dir / "main.json"
    main_doc = documents[main_path]
    main_params = main_doc.get("parameters", {})
    main_required = {name for name, spec in main_params.items() if "defaultValue" not in spec}

    # 2 and 3. Parameter files.
    param_files = sorted(parameters_dir.glob("main.*.parameters.json"))
    key_sets = {}
    for path in param_files:
        keys = set(documents[path].get("parameters", {}).keys())
        key_sets[path.name] = keys
        unknown = keys - set(main_params)
        missing = main_required - keys
        if unknown:
            fail(f"{path.name} sets parameters main.json does not declare: {sorted(unknown)}")
        if missing:
            fail(f"{path.name} is missing required parameters: {sorted(missing)}")
        env_value = documents[path]["parameters"].get("environment", {}).get("value")
        expected_env = path.name.split(".")[1]
        if env_value != expected_env:
            fail(f"{path.name} has environment '{env_value}' but the file name says '{expected_env}'")
    if key_sets:
        baseline_name, baseline = next(iter(key_sets.items()))
        for name, keys in key_sets.items():
            if keys != baseline:
                fail(f"{name} parameter set differs from {baseline_name}: {sorted(keys ^ baseline)}")
        if not failures:
            print(f"ok    {len(key_sets)} parameter files share the same {len(baseline)} parameters")

    # 4. Nested deployments versus module contracts.
    for resource in main_doc.get("resources", []):
        if resource.get("type") != "Microsoft.Resources/deployments":
            continue
        props = resource.get("properties", {})
        supplied = set(props.get("parameters", {}).keys())
        if "templateLink" in props:
            rel = props["templateLink"].get("relativePath")
            module_path = templates_dir / rel
            if module_path not in documents:
                fail(f"main.json links '{rel}' but the file does not exist")
                continue
            module_doc = documents[module_path]
            label = rel
        else:
            module_doc = props.get("template", {})
            label = f"inline template '{resource.get('name')}'"
        declared = module_doc.get("parameters", {})
        required = {n for n, s in declared.items() if "defaultValue" not in s}
        unknown = supplied - set(declared)
        missing = required - supplied
        if unknown:
            fail(f"main.json passes parameters {sorted(unknown)} that {label} does not declare")
        if missing:
            fail(f"main.json does not supply required parameters {sorted(missing)} for {label}")
        if not unknown and not missing:
            print(f"ok    {label}: {len(supplied)} parameters match the module contract")

    # 5. Unreferenced parameters and variables (the ARM-TTK rules, checked early).
    for path, doc in documents.items():
        if path.parent == parameters_dir:
            continue
        body_without_params = json.dumps({k: v for k, v in doc.items() if k != "parameters"})
        body_without_vars = json.dumps({k: v for k, v in doc.items() if k != "variables"})
        for name in doc.get("parameters", {}):
            if name not in PARAM_RE.findall(body_without_params):
                fail(f"{path.relative_to(root)} declares parameter '{name}' but never references it")
        for name in doc.get("variables", {}):
            if name == "copy":
                continue
            if name not in VAR_RE.findall(body_without_vars) and name not in VAR_RE.findall(json.dumps(doc.get("variables", {}))):
                fail(f"{path.relative_to(root)} declares variable '{name}' but never references it")

    print()
    if failures:
        print(f"{len(failures)} check(s) failed")
        return 1
    print("All template checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
