#!/usr/bin/env python3
"""Convert split SWE-Cascade v2 records into native Harbor tasks."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path


def toml_string(value: str) -> str:
    # JSON strings are valid TOML basic strings and handle quotes/newlines safely.
    return json.dumps(value, ensure_ascii=False)


def resource_limits(language: str) -> tuple[int, int]:
    """Use 32 GiB RAM for every task, retaining language-specific disk budgets."""
    language = language.lower()
    if language in {"c", "c++", "cpp", "java", "kotlin", "scala"}:
        return 32768, 40960
    if language in {"rust"}:
        return 32768, 30720
    return 32768, 20480


def solution_script(patch: str) -> str:
    delimiter = "__SWEPMV2_GOLD_PATCH_EOF__"
    if delimiter in patch:
        raise ValueError(f"patch contains reserved delimiter {delimiter}")
    patch_payload = patch if patch.endswith("\n") else patch + "\n"
    return f"""#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'{delimiter}'
{patch_payload}{delimiter}
git apply --verbose --whitespace=nowarn /tmp/gold.patch
"""


def verifier_script(instance_id: str) -> str:
    return f"""#!/bin/bash
set -euo pipefail
mkdir -p /logs/verifier

set +e
bash /tests/eval.sh \\
  > >(tee /logs/verifier/eval-stdout.txt) \\
  2> >(tee /logs/verifier/eval-stderr.txt >&2)
raw_exit_code=$?
set -e

reported_exit_code="$(
  (grep -hoE 'OMNIGRIL_EXIT_CODE=[0-9]+' \\
    /logs/verifier/eval-stdout.txt \\
    /logs/verifier/eval-stderr.txt || true) | tail -n 1 | cut -d '=' -f 2
)"
effective_exit_code="${{reported_exit_code:-${{raw_exit_code}}}}"
printf '%s\n' "${{raw_exit_code}}" > /logs/verifier/raw-eval-exit-code.txt
printf '%s\n' "${{effective_exit_code}}" > /logs/verifier/eval-exit-code.txt
printf '%s\n' {toml_string(instance_id)} > /logs/verifier/instance-id.txt

if [ "${{effective_exit_code}}" -eq 0 ]; then
  echo 1 > /logs/verifier/reward.txt
else
  echo 0 > /logs/verifier/reward.txt
fi
exit "${{effective_exit_code}}"
"""


def convert_one(record: dict, evaluation: dict, output: Path) -> None:
    instance_id = record["instance_id"]
    if evaluation["instance_id"] != instance_id:
        raise ValueError(f"evaluation mismatch for {instance_id}")
    if evaluation.get("setup_scripts"):
        raise ValueError(f"unsupported non-empty setup_scripts for {instance_id}")
    working_dir = record["working_dir"]
    if not isinstance(working_dir, str) or not working_dir.startswith("/"):
        raise ValueError(f"working_dir must be an absolute path for {instance_id}")

    task_dir = output / instance_id
    # Harbor requires the directory even when docker_image replaces Dockerfile.
    (task_dir / "environment").mkdir(parents=True, exist_ok=True)
    (task_dir / "tests").mkdir(parents=True, exist_ok=True)
    (task_dir / "solution").mkdir(parents=True, exist_ok=True)
    (task_dir / "environment" / "Dockerfile").write_text(
        f"FROM {record['image_name']}\n"
    )
    memory_mb, storage_mb = resource_limits(record["language"])
    task_toml = f"""schema_version = "1.0"

[metadata]
benchmark = "swepmv2"
instance_id = {toml_string(instance_id)}
repository = {toml_string(record["repo"])}
language = {toml_string(record["language"])}
base_commit = {toml_string(record["base_commit"])}
category = "debugging"

[verifier]
timeout_sec = 3600.0

[agent]
timeout_sec = 7200.0

[environment]
build_timeout_sec = 1800.0
docker_image = {toml_string(record["image_name"])}
workdir = {toml_string(working_dir)}
cpus = 4
memory_mb = {memory_mb}
storage_mb = {storage_mb}
gpus = 0
"""
    (task_dir / "task.toml").write_text(task_toml)
    (task_dir / "instruction.md").write_text(record["problem_statement"].rstrip() + "\n")
    (task_dir / "tests" / "eval.sh").write_text(
        evaluation["eval_script"].rstrip() + "\n"
    )
    (task_dir / "tests" / "test.sh").write_text(verifier_script(instance_id))
    (task_dir / "solution" / "solve.sh").write_text(solution_script(record["patch"]))
    for script in (
        task_dir / "tests" / "eval.sh",
        task_dir / "tests" / "test.sh",
        task_dir / "solution" / "solve.sh",
    ):
        os.chmod(script, 0o755)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--swe", type=Path, required=True)
    parser.add_argument("--eval", dest="evaluation", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--instance-id", action="append", required=True)
    args = parser.parse_args()

    records = {r["instance_id"]: r for r in json.loads(args.swe.read_text())}
    evaluations = json.loads(args.evaluation.read_text())
    missing = [i for i in args.instance_id if i not in records or i not in evaluations]
    if missing:
        raise SystemExit(f"missing instance ids: {', '.join(missing)}")
    args.output.mkdir(parents=True, exist_ok=True)
    for instance_id in args.instance_id:
        convert_one(records[instance_id], evaluations[instance_id], args.output)
        print(f"converted {instance_id} -> {args.output / instance_id}")


if __name__ == "__main__":
    main()
