xremap’s configuration parser should handle modifier aliases consistently across all places where keys are parsed.

Currently, some modifier aliases are accepted only in certain forms, while equivalent aliases are rejected elsewhere. For example, aliases for the Super/Windows modifier such as `WIN` should be recognized as modifier names, and their sided forms should be accepted when a concrete key is required. The parser should consistently support left/right-sided aliases for modifier keys, such as left and right variants of Shift, Ctrl/Control, Alt, and Super/Win/Windows/Command-style names, wherever a physical key name is expected in configuration fields like `modmap.remap` and virtual modifier definitions.

Unsided modifier aliases must not be accepted when the configuration position requires an actual key, because xremap needs to know whether to emit or match the left or right physical modifier key. In those cases, the error message should explicitly explain the problem instead of reporting the alias as an unknown key. For example, parsing this kind of config:

modmap:
  - remap:
      WIN: A

should fail with:

modmap[0].remap: Modifiers must have left/right specified when used as key: 'WIN' at line 3 column 7

Similarly, parsing an unsided modifier alias as a virtual modifier key should produce:

Modifiers must have left/right specified when used as key: 'WIN'

The expected behavior is that valid sided modifier aliases parse successfully, unsided modifier aliases remain usable only where a modifier name is appropriate, and attempts to use an unsided modifier as a key produce the clearer “Modifiers must have left/right specified when used as key” error.

Additional internal API contract covered by the tests: the event-handler test helper API should reflect the same separation used by the implementation. `EventHandler::new` should no longer require a `WMClient`, and `EventHandler::on_events` should accept the mutable `WMClient` reference when processing events, while preserving the modifier-alias parsing behavior described above.
