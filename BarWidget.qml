pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons
import qs.Ui as Ui

import "Model.js" as Model

Ui.BarWidget {
  id: root
  moduleName: "bone.timekeeper"

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")
  readonly property string dataDirectory: stateHome + "/omarchy/timekeeper"
  readonly property string statePath: dataDirectory + "/state.json"
  // Tests can instantiate the real widget without touching user state.
  property bool persistenceEnabled: true
  readonly property color barForeground: barButton.foreground
  property var state: Model.initialState()
  property int revision: 0
  property real now: Date.now()
  property real wallOrigin: Date.now()

  property real bootOrigin: -1
  property real bootSample: 0
  property real elapsedSample: 0
  function currentTime() {
    return bootOrigin >= 0
      ? bootOrigin + bootSample + monotonic.elapsedMs() - elapsedSample
      : wallOrigin + monotonic.elapsedMs()
  }
  FileView {
    id: uptimeFile
    path: "/proc/uptime"
    printErrors: false
    onLoaded: {
      var uptime = Number(text().trim().split(" ")[0]) * 1000
      if (!isFinite(uptime) || uptime < 0) return
      if (root.bootOrigin < 0) root.bootOrigin = Date.now() - uptime
      root.bootSample = uptime
      root.elapsedSample = monotonic.elapsedMs()
    }
  }

  ElapsedTimer { id: monotonic }
  property bool storageReady: false
  property bool writeInFlight: false
  property bool saveRequested: false
  property var pendingCompletionNotifications: []

  readonly property var activeRows: {
    revision
    return Model.activeReadouts(state, now)
  }
  // PluginBarApi deliberately has no width. Read the actual bar window.
  readonly property var barWindow: barButton.QsWindow.window
  readonly property real readoutLimit: Math.max(Commons.Style.space(80), Math.min(Commons.Style.space(390),
    (barWindow && barWindow.width > 0 ? barWindow.width : 1920) * 0.20))
  // Tests can impose a tight budget without inventing host API properties.
  property real readoutBudgetOverride: -1
  readonly property real readoutBudget: readoutBudgetOverride > 0 ? readoutBudgetOverride : readoutLimit
  FontMetrics {
    id: compactMetrics
    font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
    font.pixelSize: Commons.Style.font.bodySmall
  }
  function compactWidth(row) { return Math.ceil(compactMetrics.advanceWidth(row.compactLabel)) + Commons.Style.space(8) }
  readonly property real overflowBadgeWidth: Math.ceil(compactMetrics.advanceWidth("+" + activeRows.length)) + Commons.Style.space(8)
  readonly property int maxVisibleReadouts: {
    var used = 0, count = 0
    for (var index = 0; index < activeRows.length; index++) {
      used += (index > 0 ? Commons.Style.space(5) : 0) + compactWidth(activeRows[index])
      var required = used + (index < activeRows.length - 1 ? overflowBadgeWidth + Commons.Style.space(5) : 0)
      if (required > readoutBudget && index > 0) break
      count++
      if (required > readoutBudget) break
    }
    return Math.max(1, count)
  }
  readonly property var visibleRows: activeRows.slice(0, maxVisibleReadouts)
  readonly property int hiddenCount: Math.max(0, activeRows.length - visibleRows.length)
  function visibleWidth(row) {
    return Math.min(compactWidth(row), Math.max(1, readoutBudget - (hiddenCount > 0 ? overflowBadgeWidth + Commons.Style.space(5) : 0)))
  }
  readonly property real barWidgetWidth: activeRows.length === 0 ? idleIcon.tightWidth * 2
    : visibleRows.reduce(function(sum, row) { return sum + visibleWidth(row) }, 0)
      + (hiddenCount > 0 ? overflowBadgeWidth + Commons.Style.space(5) : 0)
      + Commons.Style.space(5) * Math.max(0, visibleRows.length - 1)
  readonly property string allActiveTooltip: activeRows.length ? activeRows.map(function(row) { return row.text }).join("\n") : "Open Timekeeper"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = barButton
    panelLoader.item.hostWidget = root
    panelLoader.item.stateOwner = root
  }
  function panelItem() { return panelLoader.item }

  // Explicitly invoked diagnostics exercise separate, non-persistent fixtures.
  property var regressionHarness: null
  property var regressionResults: ({ status: "not run" })
  IpcHandler {
    enabled: root.persistenceEnabled
    target: root.persistenceEnabled ? root.moduleName + ".diagnostics" : ""
    function inspect(): string {
      return JSON.stringify({ source: Qt.resolvedUrl("BarWidget.qml").toString(),
        foreground: root.barForeground.toString(), hostForeground: root.bar ? root.bar.barForeground.toString() : null,
        width: root.width, height: root.height, readoutBudget: root.readoutBudget, version: "1.0.21", active: root.activeRows, opened: root.opened,
        checks: root.regressionResults })
    }
    function runChecks(): string {
      if (root.regressionHarness) return "already running"
      var component = Qt.createComponent(Qt.resolvedUrl("tests/RuntimeChecks.qml"))
      if (component.status !== Component.Ready) return component.errorString()
      root.regressionResults = ({ status: "running" })
      root.regressionHarness = component.createObject(root, { host: root })
      return root.regressionHarness ? "started" : component.errorString()
    }
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function changed() {
    state = Object.assign({}, state)
    revision++
    now = currentTime()
  }

  function save() {
    if (!persistenceEnabled || !storageReady) return
    saveRequested = true
    writeLatestState()
  }

  function writeLatestState() {
    if (!storageReady || writeInFlight || !saveRequested) return
    saveRequested = false
    writeInFlight = true
    stateFile.setText(JSON.stringify(Model.snapshotState(state, currentTime(), Date.now())))
  }

  function writeFinished() {
    writeInFlight = false
    if (saveRequested) {
      writeLatestState()
      return
    }
    flushNotifications()
  }

  function flushNotifications() {
    var pending = pendingCompletionNotifications.slice()
    pendingCompletionNotifications = []
    for (var i = 0; i < pending.length; i++) notifyCompletion(pending[i])
  }

  function saveChanged() {
    changed()
    save()
  }

  function load(raw) {
    var restored = Model.restoreState(raw)
    state = restored.state
    // Reconcile downtime against UTC once, then use the monotonic session clock.
    wallOrigin = Date.now() - monotonic.elapsedMs()
    now = currentTime()
    var completions = []
    if (Model.settleTimer(state.mainTimer, now)) completions.push("Timer")
    for (var i = 0; i < state.timers.length; i++) {
      var timer = state.timers[i]
      if (Model.settleTimer(timer, now)) completions.push(timer.name)
    }
    storageReady = true
    changed()
    if (completions.length > 0) {
      pendingCompletionNotifications = pendingCompletionNotifications.concat(completions)
      save()
    }
  }

  function notifyCompletion(label) {
    Quickshell.execDetached(["notify-send", "--app-name=Timekeeper", "--urgency=low", "--expire-time=0", "--hint=boolean:suppress-sound:true", "Timer complete", label + " has finished"])
  }

  function copyText(value) {
    Quickshell.execDetached(["wl-copy", String(value)])
  }

  function settleRunningTimers() {
    var completions = []
    var nowValue = currentTime()
    if (Model.settleTimer(state.mainTimer, nowValue)) {
      completions.push("Timer")
    }
    for (var i = 0; i < state.timers.length; i++) {
      var timer = state.timers[i]
      if (Model.settleTimer(timer, nowValue)) {
        completions.push(timer.name)
      }
    }
    if (completions.length > 0) {
      pendingCompletionNotifications = pendingCompletionNotifications.concat(completions)
      save()
    }
    now = nowValue
    if (completions.length > 0) changed()
  }

  onBarChanged: injectPanel()

  Process {
    id: directoryProcess
    command: ["mkdir", "-p", root.dataDirectory]
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.storageReady = true
        stateFile.reload()
      } else {
        console.warn("Timekeeper: could not create state directory")
      }
    }
  }

  FileView {
    id: stateFile
    path: root.persistenceEnabled ? root.statePath : ""
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.load(text())
    onSaved: root.writeFinished()
    onSaveFailed: {
      root.writeInFlight = false
      root.saveRequested = true
      console.warn("Timekeeper: state save failed; pending completions retained until a successful save")
    }
    onLoadFailed: {
      if (!root.persistenceEnabled) return
      root.state = Model.initialState()
      root.storageReady = true
      root.changed()
    }
  }

  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: { uptimeFile.reload(); root.settleRunningTimers() }
  }

  Component.onCompleted: if (persistenceEnabled) directoryProcess.running = true

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    onLoaded: root.injectPanel()
  }

  implicitWidth: barButton.implicitWidth
  implicitHeight: barButton.implicitHeight

  Ui.WidgetButton {
    id: barButton
    bar: root.bar
    anchors.fill: parent
    text: ""
    objectName: "timekeeperBarButton"
    labelVisible: false
    tooltipText: root.allActiveTooltip
    activeFocusOnTab: true
    Accessible.name: root.activeRows.length ? root.allActiveTooltip : "Open Timekeeper"
    Accessible.description: root.allActiveTooltip
    hasVisualContent: true
    fixedWidth: root.barWidgetWidth
    onPressed: function(buttonCode) { if (buttonCode === Qt.LeftButton) root.toggle() }

    Row {
      objectName: "barReadoutRow"
      visible: root.activeRows.length > 0
      anchors.centerIn: parent
      height: barButton.height
      width: root.barWidgetWidth
      spacing: Commons.Style.space(5)
      Repeater {
        model: root.visibleRows
        delegate: Item {
          id: readoutRow
          required property var modelData
          objectName: "activeReadout"
          width: root.visibleWidth(readoutRow.modelData)
          height: barButton.height
          Text {
            objectName: "activeReadoutText"
            anchors.centerIn: parent
            width: Math.max(1, readoutRow.width - Commons.Style.space(8))
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideLeft
            text: readoutRow.modelData.compactLabel
            textFormat: Text.PlainText
            color: readoutRow.modelData.kind === "stopwatch" ? (root.bar ? root.bar.urgent : Commons.Color.urgent) : root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
            font.pixelSize: Commons.Style.font.bodySmall
          }
        }
      }

      Text {
        visible: root.hiddenCount > 0
        width: root.overflowBadgeWidth
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
        text: "+" + root.hiddenCount
        color: root.barForeground
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: Commons.Style.font.bodySmall
      }

    }
    Ui.OpticalGlyph {
      id: idleIcon
      objectName: "idleIcon"
      anchors.centerIn: parent
      width: tightWidth
      height: barButton.height
      visible: root.activeRows.length === 0
      text: "󰥔"
      color: root.barForeground
      fontFamily: root.bar ? root.bar.fontFamily : Commons.Style.font.family
      fontSize: Commons.Style.font.icon
    }

  }
}
