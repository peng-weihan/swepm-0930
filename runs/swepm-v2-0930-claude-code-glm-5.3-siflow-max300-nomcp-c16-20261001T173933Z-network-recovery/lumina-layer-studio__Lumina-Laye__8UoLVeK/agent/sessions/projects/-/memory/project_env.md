---
name: project-env
description: Testbed env quirks — use /opt/venv/bin/python; some test failures are pre-existing environment issues
metadata: 
  node_type: memory
  type: project
  originSessionId: ab172264-0729-4f72-9b95-6d9e08f39ab4
---

The /testbed repo's Python deps (numpy, cv2, fastapi, pytest) live in `/opt/venv`, not the system python. Run tests with `/opt/venv/bin/python -m pytest`.

**Why:** System `python3` has no numpy installed; commands silently fail with ModuleNotFoundError.

**How to apply:** Always use `/opt/venv/bin/python` for running tests or scripts in /testbed. Additionally, `tests/test_worker_pool_unit.py` (all TestSubmit tests) and `tests/test_vector_engine_unit.py::TestParseSvgSubpaths::test_split_multi_subpath_path_into_multiple_polygons` fail even on a clean tree (verified 2026-10-01 via git stash) — don't chase them as regressions.
