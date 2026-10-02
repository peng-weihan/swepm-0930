# SWEPM v2.1 quality audit

Harbor: 0.23.0
Instances: 82
Valid quality reports: 76
Environment errors: 6

overall_quality: good=16, questionable=59, invalid=1
test_scope: balanced=16, too_narrow=32, too_broad=1, both=26, unclear=1
recommended_action: keep=16, revise_tests=46, revise_instance=12, manual_review=1, drop=1

Files:
- quality_summary.json: full aggregate plus all normalized reports
- quality_summary.csv: compact per-instance table
- reports/: individual quality reports
- harbor_job_result.json: Harbor run metadata and environment exceptions
- PROMPT_TEMPLATE.md: audit rubric supplied to the model
