# Timekeeper

Timekeeper is an Omarchy Quattro `bar-widget` plugin with a countdown timer, a stopwatch, saved timer presets, lap history, and independent additional timers and stopwatches.

## Requirements

- Omarchy Quattro with third-party plugin support and its bundled Quickshell modules.
- `notify-send` for timer-completion notifications.
- `wl-copy` for copying stopwatch times.

Timekeeper runs inside the existing Omarchy shell. It does not start a separate service, use network access, or require elevated privileges or additional packages.

## Install

Install from the public GitHub repository with:

```sh
omarchy plugin add https://github.com/Taiggerrock/Timekeeper.git --enable
```

To install a local checkout for development:

```sh
PLUGIN_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/bone.timekeeper"
mkdir -p "$PLUGIN_DIR"
cp -a manifest.json BarWidget.qml Panel.qml Model.js DurationEditor.qml ListScrollBar.qml remove-data.sh tests "$PLUGIN_DIR/"
omarchy plugin validate "$PLUGIN_DIR"
omarchy plugin enable bone.timekeeper --section right
```

Run the local-checkout commands from the repository root. Local changes do not update the installed copy automatically. After copying updates, use `omarchy-shell bone.timekeeper.diagnostics inspect` to confirm the loaded source path and version. A shell restart may be needed to load changed QML.

## Use

Click the bar widget to open the panel. It has **Timer** and **Stopwatch** tabs; press Escape to close it. Tab and Shift+Tab move keyboard focus, Enter or Space activates a focused control, and Left/Right switch tabs when a tab has focus.

The timer uses an editable `HH:MM:SS` display. Click a field to select its digits; entering two digits advances to the next field. Enter pads a single digit with a leading zero and advances. Start/Stop controls the countdown. Save adds a paused, nonzero duration to presets, and selecting a preset loads it. Reset clears the current timer. Add Timer creates an independent timer.

The stopwatch supports Start/Stop, Reset, Lap, and Copy Time. Lap saves the current elapsed time without stopping the watch. Stopwatch values use `HH:MM:SS:ss`, with centiseconds in the final field. Selecting a saved lap pauses the stopwatch and loads its value. Add Stopwatch creates an independent stopwatch.

Additional counters start paused. Their names are editable and saved. Each counter has independent timing state and controls. Histories retain up to 50 entries. Additional-counter lists have no configured item limit and display five rows at a time with scrolling.

When one or more counters run, the bar shows compact time readouts. Main counters display only time; additional counters display `Name - 00:00`. Timer values use `MM:SS` below one hour and `HH:MM` from one hour onward. Stopwatch compact values use `MM:SS:ss` below one hour and `HH:MM:ss` from one hour onward. The timer uses the normal themed foreground, and stopwatch digits use the theme's urgent color. Hovering or focusing the readout shows full active-counter values. With no active counters, the themed idle icon returns.

## State and timing

Timekeeper stores state at `${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/timekeeper/state.json`. It writes atomically and saves after actions and timer completion, not on every display refresh. Histories are capped at 50 entries. Invalid or unsupported state is ignored safely; counters remain usable if the state directory cannot be written, but changes cannot persist.

Durations are stored in milliseconds. Timers are limited to `99:59:59`; stopwatch hours can exceed two digits. During a live session, elapsed time uses Quickshell's monotonic timer and Linux boot uptime so wall-clock changes do not alter running counters and suspend time is included. On startup, saved timestamps are rebased using UTC; recovery across reboot therefore depends on the system clock. Timer completion sends a low-urgency, silent desktop notification.

Timekeeper reads Linux `/proc/uptime` for suspend-aware timekeeping and stores or modifies user data only in its own state directory. Clipboard and notification commands are invoked with argument arrays; timer names and values are not interpolated into shell commands.

## Remove

To remove saved Timekeeper data as well as the plugin:

```sh
PLUGIN_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/bone.timekeeper"
"$PLUGIN_DIR/remove-data.sh"
omarchy plugin remove bone.timekeeper
```

The cleanup script removes only Timekeeper's state file and matching atomic-write temporary files. It refuses symlinks and unexpected file types and leaves shared Omarchy directories intact. Keep a copy of `remove-data.sh` if the plugin directory has already been removed.

## Development and validation

Run these commands from the repository root:

```sh
node --test tests/*.test.js
omarchy plugin validate .
qmllint -I "$OMARCHY_PATH/shell" BarWidget.qml Panel.qml DurationEditor.qml ListScrollBar.qml
```

The model tests cover timer and stopwatch behavior, independent counters, state recovery, history limits, and edge cases. The panel regression test is opt-in and requires a running Omarchy shell with this version of the plugin installed:

```sh
TIMEKEEPER_RUNTIME_TESTS=1 node --test tests/panel-regression.test.js
```

It creates isolated QML fixtures inside the shell, briefly opens a test panel, and does not read or modify saved Timekeeper state. It exercises controls, first-open layout, bar readouts, scrolling, timing while the panel is closed, and preservation of independent counters. Physical reboot, suspend, and manual theme switching are not simulated.

See [ACCEPTANCE.md](ACCEPTANCE.md) for the latest verification record and known limits.
