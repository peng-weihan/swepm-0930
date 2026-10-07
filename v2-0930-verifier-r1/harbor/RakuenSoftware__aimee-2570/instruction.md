refactor(delegates): "may this delegate write?" is one answer, composed once

server_compute built this from two halves:

    role_allows_writes && delegate_prompt_allows_writes(prompt)

The role half was already a module rule (stage 10). The prompt half -- a text
scan deciding whether a brief asks for changes -- was still C. So the boolean
that governs whether a delegate gets a WRITABLE MOUNT was assembled in the
caller from one migrated rule and one unmigrated one.

Stage 15 (event 6671) answers it whole. That matters because this is the exact
fact stages 11 and 12 both consume, and #2551 already established it has to be
the caller's composed answer rather than something each side re-derives.
Composing it in the module means there is one place it can be composed wrongly,
and that place has tests.

The prompt rule is ported faithfully -- all four keyword lists match the C
exactly, and the distinction the C encodes is preserved and now tested: a
WHOLE-PROMPT prohibition ("read-only", "analysis only") is never rescued by a
later keyword, because "read-only: fix the typo" is a contradiction and the safe
reading of a contradiction is the one that does not edit the user's files. A
SCOPED prohibition ("do not edit the generated files") only forbids on its own;
alongside a real ask it is a boundary on a task that is still a write task.

The response carries both halves as well as the answer. Not for the decision --
callers must use the composed one -- but because "the delegate could not edit
anything" is otherwise undebuggable: an operator needs to see whether the role
or the brief withheld it.

A C COPY IS DELIBERATELY RETAINED, and this is the part worth reviewing.

delegate_prompt_allows_writes stays for the CLI, which still calls it. The CLI
registers no stage adapters, so a fail-closed seam there would not fail closed
usefully -- it would simply always answer "read-only", breaking `--worktree`
validation.

That is not a hypothetical, and finding it is why the copy stayed:
delegate_role_is_write() is ALREADY a seam with no provider in the CLI. It
returns 0 unconditionally there, so the branch at cmd_agent_delegate.c:1869 that
tests it is dead code today. An earlier migration left it that way silently.
Adding a second seam to the same binary would add a second silent misbehaviour,
not remove a duplicate.

The copy is commented with exactly that, and with what retires it: the CLI being
able to reach the module. Until then it must track PromptAllowsWrites.

The compute test composes the same two C inputs it already links rather than
restating either, so the harness cannot drift from what it stands in for.
