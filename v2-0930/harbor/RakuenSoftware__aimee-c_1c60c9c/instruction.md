refactor(delegates): run economics moves into the module

What a coordinated run cost the SUPERVISOR was ~205 lines of C: which rows count
as delegate runs, which tier each sat on, whether its handoff could be believed,
the supervisor-token estimate, and the verdict and advice drawn from all of it.
Every part of that is a judgement, so it is now
server-go/modules/delegates/economics.go on a new stage.

Moving it removed a bus round trip per task. The rule for believing a handoff
already lives in this module, so the report builder calls ValidateHandoff
in-process instead of asking back out through C and over the bus for every row.

Tasks and agent tiers travel IN the request. Only the four fields the rule reads
are sent -- status, claimed_by, files, result -- and the agent tiers come from
the caller's own config, because which seat is dear is its configuration and not
this module's state. Both are read and forgotten.

The verdict's LABELS come back with it. delegate_economics_verdict_text and
delegate_economics_cost_model_label were mappings from a decision to its
caption; a second copy could caption a verdict with a label that disagrees with
it. The module renders both, they ride in the response, and the report struct
carries them for the three call sites that print them. The one literal left in C
is in delegate_economics_add_agent_result_json, which labels a SINGLE agent's
tier and has no report in hand -- a different question, marked as such.

Fails closed as an EMPTY report with an "unclear" verdict, which is exactly what
the rule itself says about a run it cannot judge. Claiming a win or a loss with
no answer would be an unearned statement about how a team spent its attention.

Three test binaries link the object, found from the link graph rather than by
grepping for callers:

  - delegate-economics keeps test_agent_result_json_metadata, which exercises
    the per-result annotation that is still C, and loses five rule tests that
    moved to Go with their cases -- including the tier-0-heavy-BUT-high-manual
    branch, where cheap seats do not buy a win because the supervisor still had
    to step in, and which this file was the only place to cover;
  - coord-jobs was NOT given a fixture provider, because a test that states the
    report it then asserts proves nothing. Its unique value is the layer beneath
    the rule, so it now asserts that a claimed-and-completed job comes back from
    the store with those four fields populated. An empty files or result would
    compute the report over nothing, and the old assertions would still have
    passed;
  - server-compute links the object but never calls it, and is untouched.

Declared in the contract (6664, stage 8), the descriptor, the dispatch table and
the registry-vs-contracts test, with the serve grant regenerated.

Verified against the server LINK, not the default target: ../aimee-server was
deleted and relinked from scratch, alongside ../aimee-kb and
cmd-srcs-compile-check. delegate_economics.c was already in SERVER_SRCS, but
that was checked before building rather than after CI said so.
