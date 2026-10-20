.pragma library

var MAX_TIMER_MS = 359999000;
var HISTORY_LIMIT = 50;
var TITLE_LIMIT = 32;

function blankCounter(valueMs) {
  return { valueMs: clampDuration(valueMs), running: false, startedAt: 0, runId: 0, notifiedRun: -1 };
}

function initialState() {
  return {
    version: 1,
    namingVersion: 2,
    mainTimer: blankCounter(0),
    mainStopwatch: blankCounter(0),
    timers: [],
    stopwatches: [],
    laps: [],
    presets: [],
    nextId: 1,
    startSequence: 1
  };
}

function clampDuration(value) {
  var n = Number(value);
  if (!isFinite(n)) return 0;
  return Math.max(0, Math.min(MAX_TIMER_MS, Math.floor(n)));
}

function clampStopwatch(value) {
  var n = Number(value);
  if (!isFinite(n)) return 0;
  return Math.max(0, Math.min(Number.MAX_SAFE_INTEGER, Math.floor(n)));
}

function elapsed(counter, now) {
  if (!counter || !counter.running) return clampStopwatch(counter ? counter.valueMs : 0);
  var delta = Math.max(0, Number(now) - Number(counter.startedAt));
  return clampStopwatch(counter.valueMs + delta);
}

function remaining(counter, now) {
  if (!counter || !counter.running) return clampDuration(counter ? counter.valueMs : 0);
  var delta = Math.max(0, Number(now) - Number(counter.startedAt));
  return Math.max(0, clampDuration(counter.valueMs) - delta);
}

function displayMs(counter, kind, now) {
  return kind === "timer" ? remaining(counter, now) : elapsed(counter, now);
}

function formatTime(ms) {
  var seconds = Math.floor(Math.max(0, Number(ms) || 0) / 1000);
  var hours = Math.floor(seconds / 3600);
  var minutes = Math.floor((seconds % 3600) / 60);
  var secs = seconds % 60;
  return (hours < 10 ? "0" : "") + hours + ":" +
    (minutes < 10 ? "0" : "") + minutes + ":" +
    (secs < 10 ? "0" : "") + secs;
}

function formatStopwatchTime(ms) {
  var value = clampStopwatch(ms);
  var centiseconds = Math.floor((value % 1000) / 10);
  return formatTime(value) + ":" + (centiseconds < 10 ? "0" : "") + centiseconds;
}

function formatStopwatchBarTime(ms) {
  var value = clampStopwatch(ms);
  var totalSeconds = Math.floor(value / 1000);
  var left = totalSeconds >= 3600 ? Math.floor(totalSeconds / 3600) : Math.floor(totalSeconds / 60);
  var right = totalSeconds >= 3600 ? Math.floor(totalSeconds / 60) % 60 : totalSeconds % 60;
  var centiseconds = Math.floor((value % 1000) / 10);
  return (left < 10 ? "0" : "") + left + ":" + (right < 10 ? "0" : "") + right +
    ":" + (centiseconds < 10 ? "0" : "") + centiseconds;
}

function cleanName(value, fallback) {
  var name = String(value || "").replace(/[\u0000-\u001f\u007f]/g, "").trim().slice(0, TITLE_LIMIT);
  return name || fallback;
}

function normalizeCounter(source, fallbackName, isTimer) {
  var value = source && Number.isFinite(Number(source.valueMs)) ? (isTimer ? clampDuration(source.valueMs) : clampStopwatch(source.valueMs)) : 0;
  var running = !!(source && source.running);
  var startedAt = running && Number.isFinite(Number(source.startedAt)) ? Number(source.startedAt) : 0;
  return {
    id: String(source && source.id || ""),
    name: cleanName(source && source.name, fallbackName),
    autoName: source && typeof source.autoName === "boolean" ? source.autoName : /^(?:Timer|Stopwatch) \d+$/.test(String(source && source.name || fallbackName)),
    valueMs: value,
    running: running && startedAt > 0 && (!isTimer || value > 0),
    startedAt: startedAt,
    startedOrder: Math.max(0, Number(source && source.startedOrder) || 0),
    runId: Math.max(0, Math.floor(Number(source && source.runId) || 0)),
    notifiedRun: Math.floor(Number(source && source.notifiedRun) || -1)
  };
}

function normalizeHistory(value, isTimer) {
  if (!Array.isArray(value)) return [];
  var result = [];
  for (var i = 0; i < value.length && result.length < HISTORY_LIMIT; i++) {
    var row = value[i];
    var duration = row && Number(row.valueMs);
    if (!isFinite(duration) || duration < 0 || duration > (isTimer ? MAX_TIMER_MS : Number.MAX_SAFE_INTEGER)) continue;
    result.push({ valueMs: Math.floor(duration) });
  }
  return result;
}

function restoreState(raw) {
  try {
    var value = typeof raw === "string" ? JSON.parse(raw) : raw;
    if (!value || value.version !== 1 || typeof value !== "object") return { state: initialState(), valid: false };
    var state = initialState();
    state.mainTimer = normalizeCounter(value.mainTimer, "Timer", true);
    state.mainStopwatch = normalizeCounter(value.mainStopwatch, "Stopwatch", false);
    var timers = Array.isArray(value.timers) ? value.timers : [];
    var stopwatches = Array.isArray(value.stopwatches) ? value.stopwatches : [];
    for (var i = 0; i < timers.length; i++) state.timers.push(normalizeCounter(timers[i], "Timer " + (i + 1), true));
    for (var j = 0; j < stopwatches.length; j++) state.stopwatches.push(normalizeCounter(stopwatches[j], "Stopwatch " + (j + 1), false));
    state.laps = normalizeHistory(value.laps, false);
    state.presets = normalizeHistory(value.presets, true);
    if (value.namingVersion !== 2) state.timers.forEach(function(counter) {
      if (/^Timer \d+$/.test(counter.name)) counter.autoName = true;
    });
    renumberTimers(state);
    renumberStopwatches(state);
    state.nextId = Math.max(1, Math.floor(Number(value.nextId) || 1));
    state.startSequence = Math.max(1, Math.floor(Number(value.startSequence) || 1));
    return { state: state, valid: true };
  } catch (e) {
    return { state: initialState(), valid: false };
  }
}

function start(counter, kind, now, order) {
  if (!counter || counter.running) return false;
  if (kind === "timer" && clampDuration(counter.valueMs) <= 0) return false;
  counter.running = true;
  counter.startedAt = Number(now);
  counter.startedOrder = Number(order) || Number(now);
  counter.runId = Math.max(0, Number(counter.runId) || 0) + 1;
  counter.notifiedRun = -1;
  return true;
}

function stop(counter, kind, now) {
  if (!counter || !counter.running) return false;
  counter.valueMs = kind === "timer" ? displayMs(counter, kind, now) : clampStopwatch(displayMs(counter, kind, now));
  counter.running = false;
  counter.startedAt = 0;
  return true;
}

function setValue(counter, valueMs) {
  if (!counter || counter.running) return false;
  counter.valueMs = clampDuration(valueMs);
  counter.startedAt = 0;
  return true;
}

function settleTimer(counter, now) {
  if (!counter || !counter.running || remaining(counter, now) > 0) return false;
  counter.valueMs = 0;
  counter.running = false;
  counter.startedAt = 0;
  if (counter.notifiedRun === counter.runId) return false;
  counter.notifiedRun = counter.runId;
  return true;
}

function appendHistory(history, valueMs) {
  var result = [{ valueMs: clampStopwatch(valueMs) }].concat(history || []);
  return result.slice(0, HISTORY_LIMIT);
}

function addCounter(state, kind) {
  var timer = kind === "timer";
  var index = (timer ? state.timers : state.stopwatches).length + 1;
  var counter = normalizeCounter({ id: "counter-" + state.nextId++, name: (timer ? "Timer " : "Stopwatch ") + index, autoName: true, valueMs: 0 }, "", timer);
  if (timer) { state.timers = state.timers.concat([counter]); renumberTimers(state); }
  else { state.stopwatches = state.stopwatches.concat([counter]); renumberStopwatches(state); }
  return counter;
}

function activeReadouts(state, now) {
  var active = [];
  if (state.mainTimer.running) active.push({ counter: state.mainTimer, kind: "timer", name: "Timer" });
  if (state.mainStopwatch.running) active.push({ counter: state.mainStopwatch, kind: "stopwatch", name: "Stopwatch" });
  [state.timers, state.stopwatches].forEach(function(list, group) {
    for (var i = 0; i < list.length; i++) if (list[i].running)
      active.push({ counter: list[i], kind: group === 0 ? "timer" : "stopwatch", name: list[i].name, isAdditional: true });
  });
  active.sort(function(a, b) { return a.counter.startedOrder - b.counter.startedOrder; });
  return active.map(function(row) {
    var value = displayMs(row.counter, row.kind, now);
    var time = row.kind === "stopwatch" ? formatStopwatchTime(value) : formatTime(value);
    var compact = row.kind === "stopwatch" ? formatStopwatchBarTime(value) : formatBarTime(value);
    return { name: row.name, kind: row.kind, compactLabel: row.isAdditional ? row.name + " - " + compact : compact, text: row.name + ": " + time };
  });
}

// Persist UTC anchors while keeping a monotonic clock in the live process.
function snapshotState(state, sessionNow, wallNow) {
  var snapshot = JSON.parse(JSON.stringify(state));
  function rebase(counter, original, kind) {
    if (!counter.running) return;
    counter.valueMs = displayMs(original, kind, sessionNow);
    counter.startedAt = wallNow;
  }
  rebase(snapshot.mainTimer, state.mainTimer, "timer");
  rebase(snapshot.mainStopwatch, state.mainStopwatch, "stopwatch");
  snapshot.timers.forEach(function(counter, i) { rebase(counter, state.timers[i], "timer"); });
  snapshot.stopwatches.forEach(function(counter, i) { rebase(counter, state.stopwatches[i], "stopwatch"); });
  return snapshot;
}

function formatBarTime(ms) {
  var seconds = Math.floor(Math.max(0, Number(ms) || 0) / 1000);
  var left = seconds >= 3600 ? Math.floor(seconds / 3600) : Math.floor(seconds / 60);
  var right = seconds >= 3600 ? Math.floor(seconds / 60) % 60 : seconds % 60;
  return (left < 10 ? "0" : "") + left + ":" + (right < 10 ? "0" : "") + right;
}

// Keep the main card's chosen edge fixed; grow the sidebar into available space.
function panelPlacement(pillLeft, pillRight, screenWidth, margin, mainWidth, extraWidth, section) {
  var available = Math.max(1, screenWidth - margin * 2);
  mainWidth = Math.min(mainWidth, available);
  var mainLeft = section === "right" ? pillRight - mainWidth : pillLeft;
  mainLeft = Math.max(margin, Math.min(mainLeft, screenWidth - margin - mainWidth));
  var rightSpace = screenWidth - margin - mainLeft - mainWidth;
  var leftSpace = mainLeft - margin;
  var sidebarOnLeft = extraWidth > 0 && (section === "right" || (rightSpace < extraWidth && leftSpace > rightSpace));
  var width = Math.min(available, mainWidth + extraWidth);
  var left = sidebarOnLeft ? mainLeft - extraWidth : mainLeft;
  left = Math.max(margin, Math.min(left, screenWidth - margin - width));
  return { mainLeft: mainLeft, left: left, width: width, sidebarOnLeft: sidebarOnLeft };
}

function renumberStopwatches(state) {
  state.stopwatches.forEach(function(counter, index) {
    if (counter.autoName) counter.name = "Stopwatch " + (index + 1);
  });
}

function renumberTimers(state) {
  state.timers.forEach(function(counter, index) {
    if (counter.autoName) counter.name = "Timer " + (index + 1);
  });
}
