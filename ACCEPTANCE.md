# Acceptance and verification

Last verified: 2026-10-20, with Timekeeper 1.0.21 loaded in the Omarchy shell.

## Current checks

| Check | Result | Evidence |
|---|---|---|
| Manifest schema and entry point | Pass | `omarchy plugin validate .` exits 0 |
| Model behavior | Pass | `node --test tests/model.test.js` exits 0 |
| Live panel and bar behavior | Pass | 119 QML interaction assertions passed against the running shell |
| Installed plugin enabled | Pass | `omarchy plugin list --json` reports `bone.timekeeper` enabled |
| Loaded installed entry point | Pass | Runtime diagnostics report the installed `bone.timekeeper/BarWidget.qml` entry point, version 1.0.21 |
| Workspace matches installed main files | Pass | SHA-256 hashes match for the manifest and primary QML components |
| QML lint | Pass with warnings | No syntax, import-resolution, missing-property, unresolved-type, or incompatible-type errors; unqualified-access warnings remain |
| Safe state cleanup | Pass | Cleanup checks confirm owned-file removal, preservation of unrelated state, and refusal to traverse symlinks |

The live suite verified first-open controls, immediate additional-counter display, keyboard editing, stopwatch start/stop/lap/reset behavior, simultaneous counters, compact readouts and overflow summary, foreground binding, scrolling, fixed panel placement, and preservation of other counters after deletion. The suite uses isolated fixtures and leaves the panel closed with no active test counters.

## Limits

Physical reboot and suspend recovery were not exercised. Manual desktop theme switching was not performed; reactive theme bindings were exercised by the QML fixture. Clipboard integration and notification delivery were not manually tested. QML lint still reports `unqualified` access warnings that do not prevent loading or the runtime checks.

## Run the checks

```sh
node --test tests/*.test.js
omarchy plugin validate .
qmllint -I "$OMARCHY_PATH/shell" BarWidget.qml Panel.qml DurationEditor.qml ListScrollBar.qml
TIMEKEEPER_RUNTIME_TESTS=1 node --test tests/panel-regression.test.js
```

The runtime test requires the matching plugin installed and an active Omarchy shell. It temporarily opens its isolated test panel inside that shell.
