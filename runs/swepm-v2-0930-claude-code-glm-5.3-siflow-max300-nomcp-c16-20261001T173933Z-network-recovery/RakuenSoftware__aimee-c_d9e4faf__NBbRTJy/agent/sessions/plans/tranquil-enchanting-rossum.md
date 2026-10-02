# Delegates Process Contract, Server-Log Rotation, Compaction-Corpus Refresh

## Context

The aimee codebase (`/testbed` — C core in `src/`, Go control plane in `server-go/`) has a delegate engine of ~13k lines of C under `src/modules/delegates/`, but the supervised `delegates` Go module process serves only 4 stages (role canonicalization, capability inference, chain depth, named paths — event kinds 6657-6660). Delegate execution and context-paging decisions are "logic" that the architecture says belongs in the module process and is reached over the event bus; today they are scattered through C engine code and the server daemon.

This change splits the delegate execution work into **enforceable module stages with explicit quality baselines**, registered consistently in the process contract, Go, and C; encodes the sandbox invariants (no Docker socket, network-disabled-unless-parent-proxied, read-only vs write role mounts, credentials only via module-side services) into a rendered-stage refusal rather than convention; refreshes the compaction-quality benchmark corpus; and adds server.log rotation with access-log suppression.

**Event kinds are derived, not chosen**: `4096 + principal_ref*256 + stage_ordinal`, delegates principal_ref = 10 → kinds 6661-6669 for stages 5-13. Enforced by `scripts/validate_module_process_contracts.py`.

## Registration ritual (applies to every stage)

1. `src/modules/process-contracts.json` — delegates stages array
2. `server-go/modules/delegates/<stage>.go` — Go handler + pure rule function
3. `server-go/cmd/aimee-module/main.go` — moduleConfig() Stages list (delegates case, line 101)
4. `src/modules/delegates/include/aimee/delegates/module_api.h` — event/stage/magic/len constants + encode/decode inlines (binary stages) or event/stage constants only (JSON stages, git-style "no C mirror" comment)
5. `src/modules/delegates/module_adapter.c` — C parity mirror handler + dispatch (binary stages only)
6. `src/modules/delegates/module.yaml` — go_sources/go_tests entries (ownership-complete latch fails CI on undeclared files)
7. Tests: Go unit test + stage-table test in `delegates_test.go` (model: `server-go/modules/git/git_test.go:102`); C parity in `src/tests/test_process_module_handlers.c` (binary stages)
8. `scripts/export_c_repositories.py` derives `serve=` in grants from the contract automatically — no edit needed
9. Docs: `docs/modules/delegates.md`, `docs/core/event-bus.md`, `docs/DELEGATE_SANDBOX.md`

## Part A — Nine new stages (IDs 5-13, kinds 6661-6669)

All are **pure decisions** — no I/O. Framing: fixed binary for fixed-shape (following module_api.h conventions: little-endian u32, 4-byte magic, byte 4 = wire version, booleans validated 0/1, length-prefixed strings, INVALID_REQUEST for malformed frames, CANCELLED after frame validation); JSON for variable-shaped (precedent: git CI-grade, sandbox module — "a module that returns anything shaped needs a JSON round trip").

| # | Stage name | Kind | Wire | Decision (wraps) | Go file |
|---|---|---|---|---|---|
| 5 | delegate-handoff-validate | 6661 | JSON req/resp | delegate_result_v1 JSON validity, done→partial downgrade, outside-ownership (delegate_prompt.c:198 `delegate_handoff_validate_text`) | handoff.go |
| 6 | delegate-noop-write-detect | 6662 | bin req 20 / resp 12, "DNOQ"/"DNOS" | write-role success-but-no-change branch logic (delegate_run_phases.c:128) | noop.go |
| 7 | delegate-verify-classify | 6663 | bin req 16 / resp 12, "DVFQ"/"DVFS" | exec_rc → PASS/FAILED/INFRA_ERROR + escalation (delegate_verify.c:19,77) | verify.go |
| 8 | delegate-rescue-parse | 6664 | JSON | prose tool-call rescue XML/Qwen/Mistral/JSON (delegate_xml_fallback.c) — Go test consumes committed golden corpus `testdata/xml_fallback_golden.json` | rescue.go |
| 9 | delegate-economics | 6665 | JSON | tier aggregation + verdict + recommendation (delegate_economics.c:230) | economics.go |
| 10 | delegate-patch-coordinate | 6666 | JSON | per-task patch state machine + report (delegate_patch_coordinator.c:261); calls package's own ValidateHandoff so rules can't drift | patch.go |
| 11 | delegate-sandbox-plan | 6667 | bin req 12 / resp 12, "DSXQ"/"DSXS" | own worktree→RW, shared+read-role→RO, writer-no-tree→in-process, detached→no bind (server_compute.c:1648-1699) | sandboxplan.go |
| 12 | delegate-docker-argv | 6668 | JSON | render `docker create` argv + FNV mount fingerprint; **invariants as refusals**: docker.sock mount source → INVALID_REQUEST, `--network none` always, proxy env only via parent UDS, no credential input accepted at all (delegate_backend_docker.c:1035-1105) | dockerargv.go |
| 13 | delegate-isolation-check | 6669 | bin req 12 / resp 12, "DIXQ"/"DIXS" | probed net state + require_isolation → allow/refuse (delegate_backend_docker.c:1119-1158) | isolation.go |

Role policy = existing stage 1; no new stage.

## Part B — Registration edits

1. **process-contracts.json**: append 9 stages to delegates (ids 5-13, kinds 6661-6669, names above). Validate with `python3 scripts/validate_module_process_contracts.py`.
2. **main.go**: extend delegates case Stages list with all 13 entries. Serve all nine (unlike git's declared-unserved split) — every handler is a pure parity-pinned decision.
3. **delegates.go Handle()**: convert if-chain to switch on StageID, default INVALID_REQUEST (mirroring git.go:82).
4. **module.yaml**: go_sources += handoff.go, noop.go, verify.go, rescue.go, economics.go, patch.go, sandboxplan.go, dockerargv.go, isolation.go; go_tests += matching _test.go files. No `tests` changes (parity folds into test_process_module_handlers.c, not descriptor-declared).
5. **module_api.h**: binary-stage constants + inline encode/decode helpers for noop/verify/sandbox-plan/isolation (naming: AIMEE_DELEGATES_EVENT_NOOP 6662u, ..._REQUEST_MAGIC 0x514f4e44u "DNOQ", ..._LEN); JSON stages get event/stage constants with the git-style "no C mirror" comment.
6. **module_adapter.c**: 4 mirror handlers (handle_noop, handle_verify, handle_sandbox_plan, handle_isolation) with the Go rules restated in C; verify's signal ceiling derived via SIGRTMAX/NSIG as delegate_verify.c:11-17 does. Dispatch by stage_id ahead of the invoke branch.
7. **test_process_module_handlers.c**: test_delegates_noop_detect, test_delegates_verify_classify, test_delegates_sandbox_plan, test_delegates_isolation_check (table-driven, encode→handler→decode, one malformed-frame refusal each), called from main(). No new link objects needed.
8. **delegates_test.go**: TestDelegatesStageTableMatchesContract — principalRef=10, 13 dense entries, formula check, unknown-stage refusal.
9. **test_module_runtime.c**: delegates branch of production_contract serves [6657, 6661]; smoke_production_module gains a JSON round trip over 6661 (raw-body call pattern the sandbox branch already uses).

## Part C — Server-side consumption (conservative)

**Live-wire only `delegate-handoff-validate`**: provider seam `delegate_handoff_validator_fn` + `delegate_register_handoff_validator()` in cmd_agent_delegate_impl.h / delegate_prompt.c (model: `delegate_register_paths_provider`); adapter in src/server/module_stage_adapters.c using `aimee_module_json_call(AIMEE_DELEGATES_EVENT_HANDOFF, ...)`; registered in server_module_stage_adapters_configure() (line 550). Fallback to local C rule when module absent/fails — same contract as the existing four delegates seams, which is why unit-test-server-compute and cmd-delegate tests pass without a bus.

**Declared + parity-pinned only** (callers rewired in later slices, per the port ordering in delegate-execution-into-the-module.md): verify-classify, noop-detect, sandbox-plan, docker-argv, isolation-check, rescue-parse, economics, patch-coordinate.

**Grant transition** (else new kinds silently refused on existing installs): add `delegates.grant:serve=6657,6658,6659,6660` to grant_known_historical_default in deploy/container/server-entrypoint.sh (lines 262-275); add delegates row to section 7 of src/tests/test_module_grants.sh: `delegates 10 6657 6657,...,6669`.

## Part D — Server-log rotation

Current: server_main.c:157-173 opens server.log, `platform_server_redirect_stderr` dup2s to fd 2, then fcloses — writes go to raw fd 2, unreopenable. No rotation. Access noise: ~176 LOG_INFO("server.http",...) call sites in server_http.c.

**New src/server/server_log.c + server_log.h**:
- `int server_log_open(path, max_bytes, retention, access_log, target_fd)` — open + initial redirect; server_main.c passes config-derived values; falls back to today's plain fopen/redirect on failure
- `void server_log_close(void)`
- `int server_log_maybe_rotate(void)` — called from aimee_log under log_mutex: at threshold rotate numbered generations (server.log.1..N, unlink oldest, audit_rotate pattern from log.c:96), open fresh file, re-dup2 via new `platform_server_reopen_stderr(FILE*)` (posix + windows server_main.c). Reopen semantics preserved because caller holds log_mutex.
- `int server_log_rotation_count(void)` — test observability

**log.c hooks** (core stays link-clean for CLI/gateway — no hook = byte-identical behavior): `log_set_rotate_hook(void(*)(void))` and `log_set_module_filter(int(*)(log_level_t, const char*))`; aimee_log calls filter before formatting and rotate hook while holding log_mutex. Server installs a filter dropping exactly (LOG_INFO, "server.http") when server_log_access=false — WARN/ERROR still land.

**Config keys**: `server_log_max_mb` (int, default 64, min 1, env AIMEE_SERVER_LOG_MAX_MB), `server_log_retention` (int, default 5, min 0), `server_log_access` (bool, default true) — full chain: config.h struct fields, config_fields.c rows (CFG_INT/CFG_BOOL, RELOAD_HOT, FGROUP_RUNTIME, env names) + defaults table, config.c schema/parse/defaults, regenerate accessors via python3 src/gen_config_accessors.py, then `make -C src docs-gen` (real one-line descriptions) + docs-gen-check.

**Test src/tests/test_server_log_rotation.c**: injectable max_bytes=512, target_fd = a dup'd fd (not fd 2). Asserts: rotation produces server.log.1 with pre-rotation bytes + fresh current; post-rotation writes land in the new file (reopen); generation count ≤ retention with oldest unlinked; access_log=0 suppresses LOG_INFO("server.http") while LOG_WARN("server.http") and LOG_INFO("other") still emit; access_log=1 emits. Register in Rules.mk + CMakeLists.txt (model: test_log.c).

## Part E — Compaction-quality corpus refresh

1. **run_eval.py**: add fourth check `check_value_retention(chains, value)` reading a per-fixture `value_retention` key: `must_retain` markers (facts, decisions, errors, identifiers, structured records) must appear in ≥1 chain stub; `must_drop` markers (chatter) must appear in no stub.
2. **New fixture** `tests/eval/agentic_context_virtualization/fixture_compaction_quality.json` — chains containing a decision marker, an error line, identifiers, a structured record (delegate_result_v1 handoff JSON), and chatter lines present in raw but absent from stub. Add as third `--fixture` in the Makefile `virtual-context-eval-check` target (line 1271). Add `value_retention` keys to the two existing fixtures too.
3. **Conditional build_stub extension** (only if a marker class fails): keep first excerpt + up to two additional short error/decision lines (bounded, same STUB_* caps); regenerate fixture stubs via virtual-context-inspect; unit-test-conversation-context must keep passing.
4. **Baseline artifact** `baseline.json` for the pending proposal compaction-quality-baseline.md: per-fixture + aggregate metrics, commit/config/harness identity, generating command. Add `--baseline PATH` to run_eval.py with deterministic regression thresholds (reduction drop > 0.02 below baseline fails; accuracy regression beyond MAX_REGRESSION fails; value-retention flip fails). Wire `compaction-baseline-check` Make target (model: memory-retrieval-eval-check, line 1265).
5. **Refresh benchmarks/virtual-context/fixtures.json**: replace the SYNTHETIC placeholder with a real anonymized session fixture.

## Part F — Proposal note

Create `docs/proposals/pending/delegates-process-contract.md` (shape per docs/PROPOSALS.md, style of delegate-execution-into-the-module.md): problem/boundary; decision + non-goals (9 pure-decision stages served; handoff live-wired with local fallback; backends + thin client out); owners/dependencies; threat model = the sandbox invariants encoded as refusals (no docker.sock → INVALID_REQUEST, --network none always with parent UDS as sole channel, ro/rw mount semantics, argv spec accepts no credential input); compatibility (6657-6660 unchanged, additive); bounded slices; acceptance checks; State: PENDING. Cross-reference from delegate-execution-into-the-module.md. Proposal checks must pass.

## Part G — Docs

- docs/modules/delegates.md: enumerate all 13 stages, which are live-wired; update declaration counts (go_sources count grows by 9); note "declared ahead of the port" phrasing (avoid "pending"/"TODO" — the doc-contract placeholder regex rejects them)
- docs/core/event-bus.md: add delegates stage expansion to the served-stages prose (lines 59-103)
- docs/DELEGATE_SANDBOX.md: document the 3 sandbox stages as the encoded form of the container-posture list
- docs/gen/configuration.md: regenerated by docs-gen

## Verification

Known pre-existing environment failure (out of scope): full `make unit-tests` fails on db2/vault_operator_status_runtime.c (needs libpq ≥ 17 for PGcancelConn); individual targets build fine.

Baseline first, then after each step:
```
make -C src unit-test-process-module-handlers unit-test-server-compute \
  unit-test-delegate-verify unit-test-delegate-xml-fallback \
  unit-test-delegate-patch-coordinator unit-test-delegate-economics \
  unit-test-delegate-handoff unit-test-delegate-backend-docker \
  unit-test-delegate-context-shed unit-test-conversation-context unit-test-log
cd server-go && go test ./modules/... ./cmd/aimee-module
make -C src module-grants-test virtual-context-eval-check
bash scripts/test_bus_conformance.sh
python3 scripts/validate_module_process_contracts.py
python3 scripts/check_module_test_registration.py
make -C src docs-gen docs-gen-check docs-check proposal-links-check
```
Final: `make -C src lint line-check`; `cd server-go && go test ./...`; new targets `unit-test-server-log-rotation`, `compaction-baseline-check`.

Order of implementation (each step green): contract → Go constants + stage-table test → binary handlers (verify, noop, sandboxplan, isolation) → JSON handlers (handoff, rescue, economics, patch, dockerargv) → main.go serve + bus conformance → C parity + module handlers test → interop smoke → live wiring (handoff) → grant transition → log rotation + config + docs-gen → compaction corpus → proposal + docs → final sweep.
