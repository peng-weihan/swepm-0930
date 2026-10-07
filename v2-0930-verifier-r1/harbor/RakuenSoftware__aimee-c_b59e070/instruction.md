refactor: extract the roundtable panel into a self-contained package

The roundtable ran inside internal/engine, but it has to run as a module
process on the event bus, and a module's sources must build on their own. So
the review domain -- panel resolution, seat fan-out, discussion, chairing, and
the verdict itself -- moves to server-go/modules/roundtable/panel, which now
imports nothing from internal/.

Two seams make that possible, and both put knowledge where it already lives:

  panel.Delegates is the resource plane a panel convenes over. The panel
  describes the seat it wants and reads back a failure category it never has to
  parse an error to obtain. Classifying a delegate failure, and redacting
  credentials out of its diagnostic, stay in internal/engine next to the errors
  and the redaction table they name -- a second copy of either in the panel
  would be one more thing to keep in step.

  RunResult now carries Status, PauseReason and Detail. The panel deliberately
  does not know what a workflow step is; it reports what the review concluded
  and the engine maps that onto a step. These are on the wire because a park
  that arrives as a bare failure loses the reason a human needs to act on it.

wfe.Finding and wfe.ReviewFeedback become aliases to the panel's types rather
than copies, so there is one definition and no conversion at the boundary.

The engine's copy of the analysis phase was left unreachable by this and is
deleted along with its helpers. Its tests move to the panel, where they now
exercise the implementation that actually runs instead of a duplicate that no
longer does. Their doubles gained what the old shared harness had supplied for
free: the run/artifact identity a seat echoes back, and a distinct participant
per seat -- without the first every ballot is discarded as belonging to another
run, and without the second no seat is ever eligible for its repair attempt.

Two properties the panel can no longer assert, because they became the
adapter's, are covered by new tests there: that every seat declares its inline
artifact, and that concurrent seats divide one reservation rather than each
receiving the whole of it.

No behaviour change. Transport comes next.
