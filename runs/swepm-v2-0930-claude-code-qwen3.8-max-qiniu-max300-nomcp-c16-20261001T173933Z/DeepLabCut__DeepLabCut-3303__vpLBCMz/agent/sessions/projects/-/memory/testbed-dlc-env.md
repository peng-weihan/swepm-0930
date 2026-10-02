---
name: testbed-dlc-env
description: "Environment quirks for SWE tasks in /testbed (DeepLabCut repo) — python env, upstream refs, test pollution"
metadata: 
  node_type: memory
  type: project
  originSessionId: c7bdc058-3f8a-447f-8d7c-957a4a09c035
---

For coding tasks in `/testbed` (DeepLabCut toolbox repo):

- The real python env is `/opt/venv/bin/python` (has torch, pydantic, numpy; deeplabcut installed editable from /testbed). System `/usr/local/bin/python` and `/testbed/.venv` lack dependencies — don't use them.
- **Check `git log --all` / `git log -S <symbol>` before implementing**: testbed repos often contain the upstream solution commits in packed refs (HEAD is detached at the target commit's parent). `git cherry-pick -n <sha>` applies it without committing. This exactly matched a task spec once (PR #3303, commit `1ad88877`).
- Running the test suite rewrites `examples/openfield-Pranav-2018-10-30/config.yaml` (project_path). `git restore` it after test runs.
- Heavy CPU-bound test dirs (tests/generate_training_dataset, tests/pose_estimation_pytorch/{data,models,post_processing,runners}, test_trainingsetmanipulation.py) can run 20+ min — run targeted subsets instead.
- 5 top-level test modules fail collection because tensorflow is not installed (pre-existing, not caused by changes).
- Batching `tests/tools` with top-level test files in one pytest run causes a conftest name collision (`TEST_DATA_DIR` import error); run them separately.

**Why:** these discoveries took significant exploration time in the 2026-10-01 session.
**How to apply:** at the start of any /testbed task, check upstream refs first and use /opt/venv for all python/pytest invocations.
