The v1 API and bundled examples/configuration need to be brought in line with the current public contract.

Tasks should use `prompt` as the opening user prompt field, not `instruction`. Code that constructs or reads `vf.Task` and task subclasses using `instruction=...` or `trace.task.instruction` should fail or behave incorrectly after the API rename. All bundled v1 tasksets, fixtures, harness code, tests, and documentation comments should use `prompt=...` and `trace.task.prompt` instead. This includes string prompts, message-list prompts such as `list[vf.Message]`, and tasks that intentionally have no opening prompt (`prompt=None`). Be careful not to accidentally overwrite the initial prompt in multi-turn user-simulator task generation; for example, the alphabet sort task’s first `user_turns` entry must remain the initial “Sort these names…” prompt, followed by any follow-up prompts.

The per-task resource model has also been renamed. Any task construction that uses `vf.Resources(...)` for task resource requirements should use `vf.TaskResources(...)` instead.

The default harness should no longer expose an `enable_bash` option. Local shell access is provided by a dedicated built-in harness with id `"bash"`. Config files and examples that previously used:

`[harness]`
`id = "default"`
`enable_bash = true`

should instead use:

`[harness]`
`id = "bash"`

while preserving the runtime configuration such as `runtime = { type = "docker" }`. Agentic end-to-end fixtures that require a shell tool should run against the `"bash"` harness rather than `"default"` with bash enabled.

The eval CLI modules have been moved under the `verifiers.v1.cli.eval` package. Imports of the runner should resolve from `verifiers.v1.cli.eval.runner`, including `run_eval` and `run_eval_server`.

Trace serialization should round-trip through normal pydantic dumping and validation. `Trace.model_dump()` / `Trace.model_dump_json()` output must not include derived values such as `reward`, `error`, `is_truncated`, or timing span `duration`; these should be recomputed as properties after validation. A dumped bare `vf.Trace(task=vf.Task(idx=3, prompt="hello"))` should validate back into `vf.Trace` with the same task data, zero turns/branches, reward `0.0`, and no errors. A parameterized trace such as `vf.Trace[CustomTask, CustomState]` should preserve custom task fields when validating back into the same parameterization, but runtime-only `state` must be excluded from the dump. A taskset-agnostic dumped trace should validate with `vf.WireTrace.model_validate(...)`; unknown task-specific fields should be accepted and preserved on `WireTask.model_extra`, while branch parent links, rewards, stop condition, and info should survive and derived properties like `num_branches`, `num_turns`, and `reward` should recompute correctly.

The routed-experts and graph tests should also be able to validate traces using `type(trace).model_validate(trace.model_dump())`; any old `trace.to_wire()`/`Trace.from_wire()` style API should no longer be required for this round-trip.
