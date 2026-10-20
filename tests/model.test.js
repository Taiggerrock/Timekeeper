const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync(new URL('../Model.js', `file://${__filename}`), 'utf8').replace(/^\.pragma library\s*/, '');
const context = vm.createContext({ Math, Number, String, Array, JSON, isFinite });
vm.runInContext(source + '\nthis.Model = { initialState, blankCounter, clampDuration, elapsed, remaining, displayMs, formatTime, formatStopwatchTime, formatStopwatchBarTime, cleanName, restoreState, start, stop, setValue, settleTimer, appendHistory, addCounter, activeReadouts, snapshotState, formatBarTime, panelPlacement, renumberStopwatches, renumberTimers, MAX_TIMER_MS, HISTORY_LIMIT, TITLE_LIMIT };', context);
const M = context.Model;

test('independent counters run concurrently and preserve elapsed value on pause/resume', () => {
  const a = M.blankCounter(0), b = M.blankCounter(0), timer = M.blankCounter(12_000);
  assert.equal(M.start(a, 'stopwatch', 1_000), true);
  assert.equal(M.start(b, 'stopwatch', 1_500), true);
  assert.equal(M.start(timer, 'timer', 2_000), true);
  assert.equal(M.displayMs(a, 'stopwatch', 6_000), 5_000);
  assert.equal(M.displayMs(b, 'stopwatch', 6_000), 4_500);
  assert.equal(M.displayMs(timer, 'timer', 6_000), 8_000);
  M.stop(a, 'stopwatch', 6_000);
  assert.equal(M.displayMs(a, 'stopwatch', 10_000), 5_000);
  M.start(a, 'stopwatch', 10_000);
  assert.equal(M.displayMs(a, 'stopwatch', 13_000), 8_000);
});

test('timestamp recovery includes offline time and clamps backward clock movement', () => {
  const watch = M.blankCounter(2_000);
  M.start(watch, 'stopwatch', 100_000);
  assert.equal(M.displayMs(watch, 'stopwatch', 106_000), 8_000);
  assert.equal(M.displayMs(watch, 'stopwatch', 90_000), 2_000);
  const timer = M.blankCounter(15_000);
  M.start(timer, 'timer', 100_000);
  assert.equal(M.displayMs(timer, 'timer', 106_000), 9_000);
  assert.equal(M.displayMs(timer, 'timer', 130_000), 0);
});

test('stopwatch elapsed precision is retained beyond 99 hours', () => {
  const watch = M.blankCounter(0);
  M.start(watch, 'stopwatch', 1);
  assert.equal(M.stop(watch, 'stopwatch', 400_000_001), true);
  assert.equal(M.formatTime(watch.valueMs), '111:06:40');
});

test('laps and presets are newest-first, bounded at 50, and recall/copy/delete preserve displayed values', () => {
  let laps = [];
  for (let i = 0; i < 51; i++) laps = M.appendHistory(laps, i * 1_000);
  assert.equal(laps.length, 50);
  assert.equal(laps[0].valueMs, 50_000);
  assert.equal(laps.at(-1).valueMs, 1_000);
  const labelForCopy = M.formatTime(laps[0].valueMs);
  assert.equal(labelForCopy, '00:00:50');
  const recalled = M.blankCounter(0);
  assert.equal(M.setValue(recalled, laps[0].valueMs), true);
  assert.equal(M.formatTime(recalled.valueMs), labelForCopy);
  laps = laps.filter((row, index) => index !== 0);
  assert.equal(laps.length, 49);
  assert.equal(laps[0].valueMs, 49_000);
  let presets = [];
  for (let i = 1; i <= 51; i++) presets = M.appendHistory(presets, i * 1_000);
  presets = presets.filter(row => row.valueMs <= M.MAX_TIMER_MS).slice(0, M.HISTORY_LIMIT);
  assert.equal(presets.length, 50);
  assert.equal(presets[0].valueMs, 51_000);
  const recalledPreset = M.blankCounter(0);
  assert.equal(M.setValue(recalledPreset, presets[0].valueMs), true);
  assert.equal(M.formatTime(recalledPreset.valueMs), '00:00:51');
});

test('additional counters restore identity, names, values, running state, and bounded names', () => {
  const state = M.initialState();
  const timer = M.addCounter(state, 'timer');
  const watch = M.addCounter(state, 'stopwatch');
  timer.valueMs = 4_000; timer.running = true; timer.startedAt = 100;
  watch.valueMs = 900_000; watch.running = true; watch.startedAt = 200;
  timer.name = M.cleanName(' A very long title that exceeds the sensible limit ', 'Timer');
  timer.autoName = false;
  const restored = M.restoreState(JSON.stringify(state));
  assert.equal(restored.valid, true);
  assert.equal(restored.state.timers[0].id, timer.id);
  assert.equal(restored.state.timers[0].name.length, M.TITLE_LIMIT);
  assert.equal(restored.state.timers[0].running, true);
  assert.equal(restored.state.stopwatches[0].valueMs, 900_000);
  assert.equal(restored.state.stopwatches[0].running, true);
});

test('corrupt and wrong-version state safely falls back to blank state', () => {
  assert.equal(M.restoreState('{bad json').valid, false);
  assert.equal(M.restoreState(JSON.stringify({ version: 99 })).valid, false);
  assert.equal(M.restoreState('{bad json').state.timers.length, 0);
});

test('completion settles at zero and only returns a notification once per run', () => {
  const timer = M.blankCounter(2_000);
  assert.equal(M.start(timer, 'timer', 10_000), true);
  assert.equal(M.settleTimer(timer, 11_999), false);
  assert.equal(M.settleTimer(timer, 12_000), true);
  assert.equal(timer.valueMs, 0);
  assert.equal(timer.running, false);
  assert.equal(M.settleTimer(timer, 12_500), false);
  assert.equal(M.start(timer, 'timer', 13_000), false);
  assert.equal(M.setValue(timer, 1_000), true);
  assert.equal(M.start(timer, 'timer', 13_200), true);
  assert.equal(M.settleTimer(timer, 14_200), true);
});

test('a timer expired during downtime settles once after state recovery', () => {
  const state = M.initialState();
  state.mainTimer = M.blankCounter(5_000);
  M.start(state.mainTimer, 'timer', 10_000);
  const restored = M.restoreState(JSON.stringify(state)).state;
  assert.equal(M.settleTimer(restored.mainTimer, 15_000), true);
  assert.equal(M.settleTimer(restored.mainTimer, 16_000), false);
  assert.equal(restored.mainTimer.valueMs, 0);
});

test('active readouts follow the counters’ most recent start order', () => {
  const state = M.initialState();
  const extra = M.addCounter(state, 'stopwatch');
  extra.name = 'Second';
  M.start(state.mainStopwatch, 'stopwatch', 1_000, 1);
  M.start(extra, 'stopwatch', 1_001, 2);
  assert.deepEqual(Array.from(M.activeReadouts(state, 2_000), row => row.text), ['Stopwatch: 00:00:01:00', 'Second: 00:00:00:99']);
});

test('stopwatch start, stop, resume, reset, lap save, and lap recall keep histories independent', () => {
  const watch = M.blankCounter(0);
  let laps = [];
  assert.equal(M.start(watch, 'stopwatch', 1_000, 1), true);
  const firstLap = M.displayMs(watch, 'stopwatch', 5_250);
  laps = M.appendHistory(laps, firstLap);
  assert.equal(watch.running, true, 'saving a lap leaves the stopwatch running');
  assert.equal(M.displayMs(watch, 'stopwatch', 7_000), 6_000);
  assert.equal(M.stop(watch, 'stopwatch', 7_000), true);
  assert.equal(watch.valueMs, 6_000);
  assert.equal(M.start(watch, 'stopwatch', 10_000, 2), true);
  assert.equal(M.displayMs(watch, 'stopwatch', 12_000), 8_000);
  assert.equal(M.stop(watch, 'stopwatch', 12_000), true);
  watch.valueMs = 0;
  assert.equal(laps.length, 1, 'reset does not remove laps');
  assert.equal(M.setValue(watch, laps[0].valueMs), true);
  assert.equal(watch.valueMs, 4_250, 'recalling a lap loads its saved total elapsed time');
});


test('paused stopwatches display and restore values above the timer limit', () => {
  const state = M.initialState();
  state.mainStopwatch.valueMs = 400_000_000;
  assert.equal(M.displayMs(state.mainStopwatch, 'stopwatch', 0), 400_000_000);
  const restored = M.restoreState(JSON.stringify(state)).state;
  assert.equal(M.formatTime(M.displayMs(restored.mainStopwatch, 'stopwatch', 1)), '111:06:40');
});

test('snapshot rebases monotonic elapsed time to UTC without mutating live counters', () => {
  const state = M.initialState();
  M.start(state.mainStopwatch, 'stopwatch', 1_000, 1);
  state.mainTimer.valueMs = 20_000;
  M.start(state.mainTimer, 'timer', 1_000, 2);
  const saved = M.snapshotState(state, 6_000, 80_000);
  assert.equal(state.mainStopwatch.startedAt, 1_000);
  assert.equal(saved.mainStopwatch.valueMs, 5_000);
  assert.equal(saved.mainTimer.valueMs, 15_000);
  const restored = M.restoreState(JSON.stringify(saved)).state;
  assert.equal(M.displayMs(restored.mainStopwatch, 'stopwatch', 83_000), 8_000);
  assert.equal(M.displayMs(restored.mainTimer, 'timer', 83_000), 12_000);
});


test('bar time uses minutes and seconds below one hour and hours and minutes above it', () => {
  assert.equal(M.formatBarTime(0), '00:00');
  assert.equal(M.formatBarTime(125_000), '02:05');
  assert.equal(M.formatBarTime(3_599_000), '59:59');
  assert.equal(M.formatBarTime(3_600_000), '01:00');
  assert.equal(M.formatBarTime(7_260_000), '02:01');
});


test('panel anchors the main card to left/center pill left or right pill right', () => {
  assert.equal(M.panelPlacement(400, 430, 1920, 10, 480, 0, 'center').left, 400);
  assert.equal(M.panelPlacement(20, 50, 1920, 10, 480, 0, 'left').left, 20);
  const right = M.panelPlacement(1850, 1880, 1920, 10, 480, 0, 'right');
  assert.equal(right.left + right.width, 1880);
});

test('sidebar grows right when it fits and flips left without moving the main card', () => {
  const initial = M.panelPlacement(900, 930, 1920, 10, 480, 0, 'center');
  const right = M.panelPlacement(900, 930, 1920, 10, 480, 330, 'center');
  assert.equal(right.sidebarOnLeft, false);
  assert.equal(right.mainLeft, initial.mainLeft);
  assert.equal(right.left, initial.left);
  const left = M.panelPlacement(1400, 1430, 1920, 10, 480, 330, 'center');
  assert.equal(left.sidebarOnLeft, true);
  assert.equal(left.left + 330, left.mainLeft);
  assert.equal(left.mainLeft, 1400);
  const rightAnchored = M.panelPlacement(1850, 1880, 1920, 10, 480, 330, 'right');
  assert.equal(rightAnchored.sidebarOnLeft, true);
  assert.equal(rightAnchored.left + rightAnchored.width, 1880);
});

test('oversized panels remain within the available monitor bounds', () => {
  const value = M.panelPlacement(740, 770, 800, 10, 480, 330, 'center');
  assert.ok(value.left >= 10);
  assert.ok(value.left + value.width <= 790);
});


test('default stopwatch numbers follow the current list while identities and custom names persist', () => {
  const state = M.initialState();
  const first = M.addCounter(state, 'stopwatch');
  const second = M.addCounter(state, 'stopwatch');
  const third = M.addCounter(state, 'stopwatch');
  third.name = 'Custom'; third.autoName = false;
  second.valueMs = 12000; M.start(second, 'stopwatch', 1000);
  state.stopwatches = state.stopwatches.filter(row => row.id !== first.id);
  M.renumberStopwatches(state);
  assert.equal(second.name, 'Stopwatch 1');
  assert.equal(second.running, true);
  assert.equal(second.valueMs, 12000);
  assert.equal(third.name, 'Custom');
  assert.equal(M.addCounter(state, 'stopwatch').name, 'Stopwatch 3');
  const restored = M.restoreState(JSON.stringify(state)).state;
  assert.equal(restored.stopwatches[0].id, second.id);
  assert.equal(restored.stopwatches[0].name, 'Stopwatch 1');
  assert.equal(restored.stopwatches[1].name, 'Custom');
});


test('timers use current-list numbering and migrate legacy defaults without changing IDs or running state', () => {
  const state = M.initialState();
  const first = M.addCounter(state, 'timer');
  const second = M.addCounter(state, 'timer');
  second.valueMs = 12000; M.start(second, 'timer', 1000);
  state.timers = state.timers.filter(row => row.id !== first.id);
  M.renumberTimers(state);
  assert.equal(second.name, 'Timer 1');
  assert.equal(second.running, true);
  assert.equal(M.addCounter(state, 'timer').name, 'Timer 2');
  delete state.namingVersion;
  second.autoName = false; second.name = 'Timer 99';
  const restored = M.restoreState(JSON.stringify(state)).state;
  assert.equal(restored.timers[0].name, 'Timer 1');
  assert.equal(restored.timers[0].id, second.id);
  assert.equal(restored.timers[0].running, true);
  second.name = 'Custom'; state.namingVersion = 2;
  assert.equal(M.restoreState(JSON.stringify(state)).state.timers[0].name, 'Custom');
});


test('custom names persist across recovery and renumbering and label compact readouts', () => {
  const state = M.initialState();
  const timer = M.addCounter(state, 'timer');
  timer.name = 'Timer 99'; timer.autoName = false; timer.valueMs = 60000;
  const watch = M.addCounter(state, 'stopwatch');
  watch.name = 'Focus'; watch.autoName = false;
  M.start(timer, 'timer', 1000, 1); M.start(watch, 'stopwatch', 1000, 2);
  const restored = M.restoreState(JSON.stringify(state)).state;
  M.renumberTimers(restored); M.renumberStopwatches(restored);
  assert.equal(restored.timers[0].name, 'Timer 99');
  assert.equal(restored.stopwatches[0].name, 'Focus');
  const rows = M.activeReadouts(restored, 2000);
  assert.equal(rows[0].compactLabel, 'Timer 99 - 00:59');
  assert.equal(rows[1].compactLabel, 'Focus - 00:01:00');
  M.start(restored.mainStopwatch, 'stopwatch', 2000, 3);
  assert.equal(M.activeReadouts(restored, 3000)[2].compactLabel, '00:01:00');
});
