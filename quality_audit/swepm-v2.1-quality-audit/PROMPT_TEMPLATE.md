You are auditing the quality of SWE benchmark instance `{{INSTANCE_ID}}`.

Do not solve the issue and do not edit the repository. Inspect the repository at `/testbed` and the benchmark materials in `/audit_tasks/{{INSTANCE_ID}}`:

- `instruction.md`: original issue statement
- `solution/solve.sh`: reference/gold patch
- `tests/eval.sh` and `tests/test.sh`: verifier logic and test patch
- `task.toml`: timeouts and resource metadata

Assess whether the instance is valid and whether its tests are appropriately scoped. Pay special attention to:

1. Whether the gold patch actually addresses the stated issue.
2. Whether the verifier accepts the gold patch and rejects the unmodified base in principle.
3. Tests that are too narrow: missing core requirements, accepting partial/no-op implementations, checking only one example, or failing to cover important edge cases.
4. Tests that are too broad: requiring unrelated behavior, entire-suite regressions beyond the issue, flaky/network/external-data requirements, excessive performance assumptions, or rejecting reasonable alternative implementations.
5. Tests coupled to the gold implementation rather than observable behavior.
6. Mismatches among issue text, repository revision, gold patch, test patch, and test commands.
7. Environment risks that can make verification fail independently of a candidate solution.

You may inspect files and run non-mutating discovery commands. Do not run `solution/solve.sh`, `tests/eval.sh`, or commands that apply patches. Do not modify `/testbed`.

Write a valid JSON object to `/logs/agent/quality_report.json` with this exact top-level structure:

{
  "instance_id": "{{INSTANCE_ID}}",
  "overall_quality": "good|questionable|invalid",
  "test_scope": "balanced|too_narrow|too_broad|both|unclear",
  "confidence": 0.0,
  "gold_patch_assessment": "...",
  "base_vs_gold_expectation": "...",
  "too_narrow_risks": ["..."],
  "too_broad_risks": ["..."],
  "implementation_coupling": ["..."],
  "environment_risks": ["..."],
  "mismatches": ["..."],
  "evidence": [{"file": "...", "detail": "..."}],
  "recommended_action": "keep|revise_tests|revise_instance|drop|manual_review",
  "summary": "..."
}

Use an empty list when no risk is found. Confidence must be between 0 and 1. After writing the file, print the same JSON as your final response.
