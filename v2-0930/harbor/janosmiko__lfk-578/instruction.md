Implement a context-aware which-key action panel and update the help/keybinding behavior and documentation around it.

The application should support a new `which_key_leader` keybinding, defaulting to `?`, that opens a which-key action panel in the explorer and in fullscreen viewers that have a catalog. `F1` should be the full help key in those contexts. Where no which-key panel exists, such as overlays and exec mode, `?` may still fall through to help. The README, config example, config reference, schema, and keybinding docs should describe this contract accurately.

The which-key panel must list only actions that are actually available in the current context. Availability should match the real key handlers, including resource kind, virtual/synthetic rows, union mode, read-only clusters, selected row level, visual modes, viewer-specific state, duplicate key collisions, and hardcoded viewer keys. It must not advertise a key when pressing that key would silently no-op, be blocked by the handler, or be claimed by a different action. It should also avoid offering two available entries with the same key at the same time.

The panel should be available beyond the main explorer, including the YAML viewer, log viewer, describe viewer, diff viewer, API Explorer, Object Explorer, Log Top, and fullscreen event viewer where applicable. Each viewer’s catalog should reflect that viewer’s actual key dispatch rules. The `?` leader should arm the panel in those modes; `F1` opens the full help screen.

The which-key panel should render as a compact flat list styled similarly to which-key.nvim: entries are sorted, grouped by category by default, use consistent column/key-field geometry, and can switch between grouped/category order and pure key order by pressing the leader key again while the panel is open. This order preference should be persisted in the XDG state directory as `whichkey_prefs.yaml`, defaulting to `~/.local/state/lfk/whichkey_prefs.yaml`. The saved preference should outrank the `which_key_grouped` config setting, but changing `which_key_grouped` should retire an incompatible stale saved preference. Missing, unreadable, or corrupt preference files must not prevent startup.

Add configuration support and documentation for:
`which_key_enabled`, controlling both the `g`-prefix popup and the leader action panel;
`which_key_delay_ms`, for the `g` popup;
`which_key_leader_delay_ms`, for the leader action panel;
`which_key_grouped`, controlling startup ordering;
`which_key_leader`, the keybinding for the action panel.

The panel should color descriptions by action group and show a color legend when colors are enabled. In no-color mode, entries should remain usable but omit color-only category cues. The Actions group should use the normal description color rather than the same accent as the key; no group accent should collide with the key accent in colored mode.

Key rendering should be shared between the which-key panel and the help screen key column. In `nerdfont` icon mode, modifier chords and named keys should render as Nerd Font keycaps, for example `ctrl+d` as a control keycap plus `D`, and `space`, `tab`, `enter`, `esc`, `backspace`, and arrow keys as keycap glyphs. In `unicode` and `emoji` modes, modifier chords should render as Unicode symbols such as `⌃D`, and supported named keys such as `space`, `tab`, `backspace`, and arrows should render as glyphs. In `simple`, `none`, or no-color mode, keys should remain textual, such as `ctrl+d`. The textual keybinding must remain available for search/filter indexing even when the rendered help screen shows glyphs.

The F1 help screen should be reworked so each displayed row corresponds to a real binding, keys are right-aligned in a shared key column, alternative bindings are separated consistently, descriptions use the normal text color, and the overlay clamps to the terminal size. Searching or filtering the help screen for textual chord fragments such as `ctrl` must still match rows whose rendered key column displays symbols like `⌃D`. The resting help hint bar should advertise both search (`/`) and filter (`f`).

Fix the default range-selection binding. A real terminal sends Ctrl+Space as Bubble Tea v2 `KeyPressMsg{Code: KeySpace, Mod: ModCtrl}`, whose string form is `ctrl+space`. The default `select_range` binding must therefore be `ctrl+space`, and pressing a real Ctrl+Space event should trigger range selection. Existing configs that use the legacy spelling `ctrl+@` must continue to work as an alias.

Remove dead configurable keybindings for `restart` and `exec`. These fields were not actually dispatched directly; restart and exec are only reachable via the action menu’s hardcoded quick keys. They should be removed from defaults, schema, docs, and tests, while existing config files containing those keys remain harmless because config loading is non-strict.

Goto chord validation and documentation should require a full goto target key to be `jump_top` plus exactly one keypress, for example `gA` or `gctrl+p`. Chords that do not start with the configured `jump_top`, contain multiple trailing keypresses such as `gAA`, or contain malformed modifier syntax should not be advertised in the goto popup or accepted as reachable targets.

The docs should also accurately describe that the `icons` setting affects how both the which-key panel and help screen draw keys, and the XDG state-file reference should include `whichkey_prefs.yaml`.

Additional UI and helper contracts covered by the tests: the status bar behavior for leader and goto popups must match the documented mode transitions, including the selected-filter chip and the exact visibility of leader/goto hints. Which-key rendering should use deterministic group ordering, modifier tier ordering, column selection, margins, and box sizing compatible with which-key.nvim-style layouts, so helper-level tests can assert stable geometry. Repeated bindings in the same group should be collapsed into contiguous group runs, and sorting should remain stable across direct helper calls and rendered views.
