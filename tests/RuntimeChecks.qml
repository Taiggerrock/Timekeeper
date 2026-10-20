import QtQuick
import QtTest 1.2
import qs.Commons as Commons
import "../Model.js" as Model

// Runs in the existing shell, on real plugin components with isolated state.
Item {
  id: root
  required property var host
  property var fixture: null
  property var panel: fixture ? fixture.panelItem() : null
  property var results: []
  property int step: 0
  property int ticks: 0
  property int extraTicks: 0
  property real stableMainLeft: 0
  property real savedElapsed: 0
  property var preservedTimer: null
  property var preservedWatch: null
  property string customTimerId: ""
  property string originalColor: ""

  TestEvent { id: events }
  TestResult { id: finder }
  QtObject {
    id: testBar
    property color barForeground: root.host.bar.barForeground
    property string fontFamily: root.host.bar.fontFamily
    property bool foregroundAnimationEnabled: true
    property color urgent: Qt.rgba(0.8, 0.2, 0.2, 1)
    property bool vertical: false
    property int barSize: root.host.bar.barSize
    property string position: root.host.bar.position
    property var layoutConfig: ({ center: [{ id: "bone.timekeeper" }] })
    property var activePopout: null
    property var clickTargets: []
    function registerClickTarget(item) {}
    function unregisterClickTarget(item) {}
    function showTooltip(item, text) {}
    function hideTooltip(item) {}
    function requestPopout(item) { activePopout = item }
    function releasePopout(item) { if (activePopout === item) activePopout = null }
  }

  function find(name, parent) {
    var item = parent || fixture
    var match = finder.findChild(item, name)
    if (match) return match
    // Repeater delegates can have different QObject and visual parents.
    function visualChild(node) {
      if (node.objectName === name) return node
      var children = node.children || []
      for (var i = 0; i < children.length; i++) {
        var child = visualChild(children[i])
        if (child) return child
      }
      return null
    }
    var content = finder.findChild(fixture, "timekeeperKeyCatcher")
    return visualChild(item) || (content ? visualChild(content) : null)
  }
  function check(condition, message) {
    if (!condition) throw new Error(message)
    results.push(message)
  }
  function click(name) {
    var button = find(name)
    check(!!button && button.visible && button.enabled && button.width > 0 && button.height > 0, name + " is visible, enabled, and sized")
    check(events.mouseClick(button, button.width / 2, button.height / 2, Qt.LeftButton, Qt.NoModifier, 0), name + " receives a mouse click")
  }
  function finish(error) {
    tick.stop()
    if (fixture) { fixture.close(); fixture.destroy() }
    host.regressionResults = { status: error ? "failed" : "passed", assertions: results.length, checks: results, error: error || "" }
    host.regressionHarness = null
    root.destroy()
  }
  Component.onCompleted: {
    var component = Qt.createComponent(Qt.resolvedUrl("../BarWidget.qml"))
    if (component.status !== Component.Ready) { finish(component.errorString()); return }
    fixture = component.createObject(host, { persistenceEnabled: false, bar: testBar, opacity: 0 })
    if (!fixture) { finish(component.errorString()); return }
    fixture.width = Qt.binding(function() { return fixture.implicitWidth })
    fixture.height = Qt.binding(function() { return fixture.implicitHeight })
    tick.start()
  }
  Timer {
    id: tick
    interval: 250
    repeat: true
    onTriggered: {
      try {
        if (!root.panel) { if (++root.ticks > 20) throw new Error("panel failed to load"); return }
        switch (root.step) {
        case 0:
          root.fixture.open()
          break
        case 1:
          var icon = root.find("idleIcon")
          root.check(Math.abs(root.fixture.width - icon.tightWidth * 2) < 1, "idle glyph has half its painted width as padding on each side")
          root.check(Math.abs(icon.x + icon.paintedCenterX - root.fixture.width / 2) < 1, "idle glyph is optically centered in the pill")
          root.stableMainLeft = root.find("timekeeperPopup").cardOrigin.x
          root.check(Math.abs(root.stableMainLeft - root.panel.frozenPillLeft) < 1, "center section panel starts under the pill's left edge")
          var tabs = root.find("tabRow")
          root.check(Math.abs(root.find("timerTabButton").width - root.find("stopwatchTabButton").width) < 1, "tabs share the original column equally")
          root.check(Math.abs(root.find("timerTabButton").width * 2 + tabs.spacing - tabs.width) < 1, "tabs span the full main column")
          var button = root.find("addTimerButton"), viewport = root.find("mainCounterScroll")
          var position = button.mapToItem(viewport, 0, 0)
          root.check(position.x >= 0 && position.x + button.width <= viewport.width, "control edges fit inside their viewport")
          root.check(Math.abs(root.panel.bodyWidth + root.panel.cardInsets - (Commons.Style.space(455) + root.panel.cardInsets) * 0.945) <= 1, "default-open card is five percent wider than the previous version")
          root.check(!root.find("durationArrowButton", root.find("mainDurationEditor")), "main timer has no arrow controls")
          root.check(root.panel.selectedTab === 0, "timer is the initial tab")
          root.check(root.find("timekeeperPopup").contentHeight > 100, "first-open card has content height")
          root.check(root.find("addTimerButton").visible, "add timer is visible before any tab switch")
          root.check(root.find("addTimerButton").text === "ADD TIMER", "timer button uses uppercase label")
          root.check(root.find("mainDurationEditor").height > 0, "unified main timer editor has height")
          root.click("addTimerButton")
          break
        case 2:
          root.check(Math.abs(root.find("timekeeperPopup").cardOrigin.x + (root.panel.sidebarOnLeft ? root.panel.sidebarExpansion : 0) - root.stableMainLeft) < 1, "adding a timer preserves the main panel anchor")
          root.check(root.panel.sideCounters.length === 1 && root.panel.hasSidebar, "new timer appears immediately without switching tabs")
          root.check(root.find("additionalCounterScroll").visible, "sidebar is visible immediately")
          root.check(root.find("additionalCounterScroll").height === root.find("mainCounterScroll").height, "sidebar uses the available viewport height")
          root.check(root.find("additionalDurationEditor").displaySize === root.find("mainDurationEditor").displaySize * 0.64, "additional timer clock is twenty percent smaller than v1.0.8")
          root.check(root.find("fullHeightDivider").height === root.find("timekeeperPopup").contentHeight && root.find("fullHeightDivider").y < 0, "divider extends through the header to the card's top edge")
          root.check(root.find("additionalStartButton").width === Commons.Style.space(68) * 0.8 && root.find("additionalStartButton").height === Commons.Style.space(68) * 0.8 && root.find("deleteCounterButton").width === Commons.Style.space(68) * 0.8, "additional Start and Delete buttons are twenty percent smaller")
          root.check(root.find("additionalStartButton").fontSize === Commons.Style.font.body * 2 && root.find("deleteCounterButton").fontSize === Commons.Style.font.body * 2, "additional action icons keep their previous size")
          root.check(!root.find("durationArrowButton", root.find("additionalDurationEditor")), "additional timer has no visible arrow controls")
          var input = root.find("durationField", root.find("additionalDurationEditor"))
          root.check(events.mouseClick(input, input.width / 2, input.height / 2, Qt.LeftButton, Qt.NoModifier, 0), "additional timer hours field receives a click")
          input.forceActiveFocus()
          events.keyClick(Qt.Key_A, Qt.ControlModifier, 0)
          events.keyClickChar("1", Qt.NoModifier, 0)
          root.check(root.fixture.state.timers[0].valueMs === 3600000, "typing a duration commits before leaving the field")
          root.click("additionalStartButton")
          root.check(root.fixture.state.timers[0].running && root.find("additionalStartButton").tooltipText === "STOP", "additional timer Start click starts its own countdown and updates its button")
          root.panel.editMainTimer(120000)
          root.click("timerStartButton")
          break
        case 3:
          root.check(root.find("additionalDurationEditor").valueMs < 3600000 && !root.find("additionalDurationEditor").editingEnabled, "additional timer display counts down in the panel and becomes read-only")
          root.click("additionalStartButton")
          root.check(!root.fixture.state.timers[0].running && root.find("additionalStartButton").tooltipText === "START", "additional timer Stop click pauses and restores Start")
          root.panel.selectTab(1)
          root.check(Math.abs(root.find("timekeeperPopup").cardOrigin.x - root.stableMainLeft) < 1, "timer start and tab changes do not move the panel")
          root.check(root.find("addStopwatchButton").visible && root.find("addStopwatchButton").text === "ADD STOPWATCH", "add stopwatch is visible on first entry with uppercase label")
          root.click("stopwatchStartButton")
          break
        case 4:
          if (++root.ticks < 5) return
          root.check(root.fixture.state.mainStopwatch.running, "mouse click starts stopwatch")
          root.check(root.find("stopwatchStartButton").text === "STOP", "stopwatch immediately changes start to stop")
          root.check(root.find("stopwatchLapButton").text === "LAP", "running stopwatch exposes lap")
          root.check(Model.displayMs(root.fixture.state.mainStopwatch, "stopwatch", root.fixture.now) >= 1000, "stopwatch visibly advances")
          root.check(root.fixture.activeRows.length === 2, "timer and stopwatch both produce bar readouts")
          root.check(root.find("activeReadoutText").height > 0 && root.find("activeReadoutText").width > 0, "active readout has drawable geometry")
          root.check(/^\d{2}:\d{2}$/.test(root.find("activeReadoutText").text) || /^\d{2}:\d{2}:\d{2}$/.test(root.find("activeReadoutText").text), "bar renders compact time with a host API that has no width")
          var compactRows = root.find("barReadoutRow").children.filter(function(item) { return item.objectName === "activeReadout" })
          root.check(compactRows.every(function(item) { return item.children.length === 1 && (item.modelData.kind === "stopwatch" ? /^\d{2}:\d{2}:\d{2}$/.test(item.children[0].text) : /^\d{2}:\d{2}$/.test(item.children[0].text)) }), "compact mode contains only numeric times without names or icons")
          var compactWatch = compactRows.find(function(item) { return item.modelData.kind === "stopwatch" })
          var compactTimer = compactRows.find(function(item) { return item.modelData.kind === "timer" })
          root.check(compactWatch.children[0].color.toString() === testBar.urgent.toString() && compactTimer.children[0].color.toString() === testBar.barForeground.toString(), "compact stopwatch numbers are theme red while timer numbers use regular foreground")
          root.check(root.find("barReadoutRow").height > 0, "bar content has nonzero height")
          root.fixture.x = -60
          root.click("stopwatchLapButton")
          break
        case 5:
          root.check(Math.abs(root.find("timekeeperPopup").cardOrigin.x - root.stableMainLeft) < 1, "panel stays fixed when the live pill moves after stopwatch start")
          root.check(root.fixture.state.laps.length === 1 && root.fixture.state.mainStopwatch.running, "lap saves immediately without stopping")
          root.click("stopwatchStartButton")
          root.savedElapsed = root.fixture.state.mainStopwatch.valueMs
          break
        case 6:
          root.check(!root.fixture.state.mainStopwatch.running && root.find("stopwatchStartButton").text === "START" && root.find("stopwatchLapButton").text === "RESET", "stop preserves elapsed and restores exact labels")
          root.check(root.savedElapsed > 0, "paused stopwatch preserves elapsed time")
          root.click("stopwatchStartButton")
          root.click("addStopwatchButton")
          break
        case 7:
          root.check(root.panel.sideCounters.length === 1 && root.panel.hasSidebar, "new stopwatch appears immediately")
          root.check(root.find("additionalStopwatchClock").displaySize === root.find("stopwatchClock").displaySize * 0.64, "additional stopwatch clock is twenty percent smaller than v1.0.8")
          const watch = root.fixture.state.stopwatches[0]
          root.panel.renameCounter(watch.id, "Runtime fixture")
          root.click("additionalStartButton")
          root.check(watch.running && root.find("additionalStartButton").tooltipText === "STOP", "additional stopwatch Start click starts its own counter and updates its button")
          root.extraTicks = 0
          root.originalColor = testBar.barForeground.toString()
          testBar.barForeground = Qt.rgba(0.2, 0.7, 0.8, 1)
          break
        case 8:
          if (++root.extraTicks < 5) return
          root.check(root.find("additionalStopwatchClock").formattedValue === Model.formatStopwatchTime(Model.displayMs(root.fixture.state.stopwatches[0], "stopwatch", root.fixture.now)) && root.find("additionalStopwatchClock").formattedValue !== "00:00:00:00", "additional stopwatch time advances in its panel as well as compact mode")
          root.click("additionalStartButton")
          root.check(!root.fixture.state.stopwatches[0].running && root.find("additionalStartButton").tooltipText === "START", "additional stopwatch Stop click pauses the panel counter")
          root.click("additionalStartButton")
          root.check(root.fixture.state.stopwatches[0].running && root.find("additionalStartButton").tooltipText === "STOP", "additional stopwatch Start click resumes the panel counter")
          root.check(Math.abs(root.find("timekeeperPopup").cardOrigin.x + (root.panel.sidebarOnLeft ? root.panel.sidebarExpansion : 0) - root.stableMainLeft) < 1, "adding a stopwatch preserves the main panel anchor")
          root.check(root.fixture.activeRows.length === 3, "additional stopwatch appears in concurrent bar readouts")
          root.check(root.fixture.activeRows[2].text.indexOf("Runtime fixture: ") === 0, "named readout appends to the right")
          root.check(root.fixture.activeRows[2].compactLabel.indexOf("Runtime fixture - ") === 0, "custom-named stopwatch uses unbracketed compact format")
          root.check(root.find("activeReadoutText").color.toString() === testBar.barForeground.toString(), "readout follows reactive native bar foreground")
          testBar.barForeground = root.originalColor
          root.fixture.readoutBudgetOverride = 100
          root.panel.close()
          root.savedElapsed = Model.displayMs(root.fixture.state.mainStopwatch, "stopwatch", root.fixture.now)
          break
        case 9:
          root.check(root.fixture.hiddenCount > 0 && root.fixture.allActiveTooltip.indexOf("Runtime fixture") >= 0, "overflow summary includes hidden active counters")
          root.check(Model.displayMs(root.fixture.state.mainStopwatch, "stopwatch", root.fixture.now) > root.savedElapsed, "counters continue with panel closed")
          root.panel.selectTab(0)
          root.panel.open()
          break
        case 10:
          root.check(root.find("addTimerButton").visible, "controls remain visible after reopen")
          root.panel.selectTab(1)
          root.panel.mainStopwatchAction()
          root.panel.resetStopwatch()
          root.check(root.fixture.state.mainStopwatch.valueMs === 0 && root.fixture.state.laps.length === 1, "reset preserves saved laps")
          root.panel.recallLap(root.fixture.state.laps[0].valueMs)
          root.check(root.fixture.state.mainStopwatch.valueMs > 0 && !root.fixture.state.mainStopwatch.running, "lap selection pauses and loads its value")
          root.panel.selectTab(0)
          root.panel.addCounter("timer")
          root.fixture.state.timers[0].valueMs = 60000
          root.fixture.state.timers[1].valueMs = 125000
          root.panel.renameCounter(root.fixture.state.timers[1].id, "Keep Timer")
          root.fixture.changed()
          break
        case 11:
          var survivor = root.fixture.state.timers[1]
          root.savedElapsed = survivor.valueMs
          var survivorRow = root.find("additionalCounterScroll")
          root.click("deleteCounterButton")
          break
        case 12:
          root.check(root.fixture.state.timers.length === 1 && root.fixture.state.timers[0].valueMs === root.savedElapsed && root.fixture.state.timers[0].name === "Keep Timer", "deleting a timer preserves the other timer's value and name after delegates rebuild")
          root.panel.addCounter("timer")
          root.panel.toggleCounter(root.fixture.state.timers[0].id, "timer")
          root.panel.selectTab(1)
          root.panel.addCounter("stopwatch")
          root.fixture.state.stopwatches[0].valueMs = 12000
          root.fixture.state.stopwatches[1].valueMs = 45000
          root.panel.renameCounter(root.fixture.state.stopwatches[1].id, "Keep Stopwatch")
          root.fixture.changed()
          root.panel.deleteCounter("stopwatch", root.fixture.state.stopwatches[0].id)
          break
        case 13:
          root.check(root.fixture.state.stopwatches.length === 1 && root.fixture.state.stopwatches[0].valueMs === 45000 && root.fixture.state.stopwatches[0].name === "Keep Stopwatch", "deleting a stopwatch preserves the other stopwatch's state")
          root.panel.toggleCounter(root.fixture.state.stopwatches[0].id, "stopwatch")
          var restored = Model.restoreState(JSON.stringify(Model.snapshotState(root.fixture.state, root.fixture.now, Date.now()))).state
          root.check(restored.timers[0].running && restored.timers[0].name === "Keep Timer" && restored.stopwatches[0].running && restored.stopwatches[0].name === "Keep Stopwatch", "surviving timer and stopwatch retain independent state through persistence recovery")
          for (var entry = 0; entry < 8; entry++) {
            root.fixture.state.laps = Model.appendHistory(root.fixture.state.laps, entry * 1000)
            root.fixture.state.presets = Model.appendHistory(root.fixture.state.presets, entry * 1000)
            root.panel.addCounter("stopwatch")
          }
          root.fixture.changed()
          break
        case 14:
          var lapScroll = root.find("lapScroll")
          root.check(root.find("lapTimeText").font.pixelSize === Math.round(Commons.Style.font.displayLarge * 2 * 0.576), "lap times are ten percent smaller than additional clocks")
          root.check(root.find("lapDeleteButton").width === root.find("additionalStartButton").width && root.find("lapDeleteButton").fontSize === root.find("additionalStartButton").fontSize, "lap delete action matches additional button and icon size")
          root.check(lapScroll.contentHeight > lapScroll.height && root.find("listScrollBar", lapScroll).visible, "lap list exposes a scrollbar above five entries")
          var sideScroll = root.find("additionalCounterScroll")
          root.check(sideScroll.contentHeight > sideScroll.height && root.find("listScrollBar", sideScroll).visible, "additional counters expose a scrollbar when overflowing")
          root.panel.selectTab(0)
          break
        case 15:
          var presetScroll = root.find("presetScroll")
          root.check(root.find("presetTimeText").font.pixelSize === Math.round(Commons.Style.font.displayLarge * 2 * 0.576), "saved times are ten percent smaller than additional clocks")
          root.check(root.find("presetDeleteButton").width === root.find("additionalStartButton").width && root.find("presetDeleteButton").fontSize === root.find("additionalStartButton").fontSize, "preset delete action matches additional button and icon size")
          root.check(presetScroll.contentHeight > presetScroll.height && root.find("listScrollBar", presetScroll).visible, "preset list exposes a scrollbar above five entries")
          root.check(root.find("stopwatchClock").fieldWidth === root.find("mainDurationEditor").fieldWidth && root.find("stopwatchClock").colonWidth === root.find("mainDurationEditor").colonWidth, "timer and stopwatch use identical digit and colon spacing")
          root.preservedTimer = JSON.parse(JSON.stringify(root.fixture.state.timers[0]))
          root.preservedWatch = JSON.parse(JSON.stringify(root.fixture.state.stopwatches[0]))
          root.panel.deleteCounter("timer", root.fixture.state.timers[1].id)
          root.panel.deleteCounter("stopwatch", root.fixture.state.stopwatches[1].id)
          break
        case 16:
          root.check(root.fixture.state.timers[0].running && root.fixture.state.timers[0].startedAt === root.preservedTimer.startedAt && root.fixture.state.timers[0].valueMs === root.preservedTimer.valueMs, "deleting another timer does not restart or reset a running timer")
          root.check(root.fixture.state.stopwatches[0].running && root.fixture.state.stopwatches[0].startedAt === root.preservedWatch.startedAt && root.fixture.state.stopwatches[0].valueMs === root.preservedWatch.valueMs, "deleting another stopwatch does not restart or reset a running stopwatch")
          root.fixture.close()
          testBar.layoutConfig = ({ right: [{ id: "bone.timekeeper" }] })
          root.fixture.open()
          break
        case 17:
          var popup = root.find("timekeeperPopup")
          root.check(root.panel.sidebarOnLeft, "right-anchored panel expands additional counters to the left")
          root.check(Math.abs(popup.cardOrigin.x + popup.contentWidth - root.panel.frozenPillRight) < 1, "right section panel keeps its top-right corner under the pill's right edge")
          root.check(root.find("additionalCounterScroll").x < root.find("mainCounterScroll").x, "sidebar is physically rendered to the left of the main counter")
          root.check(popup.cardOrigin.x >= popup.margin && popup.cardOrigin.x + popup.contentWidth <= popup.screenW - popup.margin, "expanded panel stays inside its monitor bounds")
          root.panel.deleteCounter("stopwatch", root.fixture.state.stopwatches[1].id)
          break
        case 18:
          root.check(root.fixture.state.stopwatches.every(function(counter, index) { return !counter.autoName || counter.name === "Stopwatch " + (index + 1) }), "default stopwatch numbers renumber to the current list after deletion")
          root.panel.addCounter("stopwatch")
          root.check(root.fixture.state.stopwatches[root.fixture.state.stopwatches.length - 1].name === "Stopwatch " + root.fixture.state.stopwatches.length, "new stopwatch number uses the current count rather than persistent history")
          root.panel.selectTab(0)
          if (root.fixture.state.mainTimer.running) root.panel.mainTimerAction()
          root.panel.editMainTimer(0)
          var hours = root.find("mainDurationEditor").fieldEditor(0)
          events.mouseClick(hours, hours.width / 2, hours.height / 2, Qt.LeftButton, Qt.NoModifier, 0)
          root.check(hours.selectedText === "00", "clicking main timer field selects both digits")
          events.keyClickChar("1", Qt.NoModifier, 0)
          events.keyClickChar("2", Qt.NoModifier, 0)
          break
        case 19:
          var main = root.find("mainDurationEditor")
          root.check(main.fieldEditor(1).activeFocus && main.fieldEditor(0).text === "12", "two typed digits advance main timer focus automatically")
          events.keyClickChar("3", Qt.NoModifier, 0)
          events.keyClick(Qt.Key_Return, Qt.NoModifier, 0)
          break
        case 20:
          var main = root.find("mainDurationEditor")
          root.check(main.fieldEditor(1).text === "03" && main.fieldEditor(2).activeFocus, "Enter pads a single main-timer digit and advances")
          events.keyClickChar("4", Qt.NoModifier, 0)
          events.keyClick(Qt.Key_Return, Qt.NoModifier, 0)
          break
        case 21:
          root.check(root.find("timerStartButton").activeFocus && root.find("mainDurationEditor").fieldEditor(2).text === "04", "Enter pads main timer seconds and focuses Start")
          root.panel.addCounter("timer")
          if (root.fixture.state.timers[0].running) root.panel.toggleCounter(root.fixture.state.timers[0].id, "timer")
          root.panel.editCounterTimer(root.fixture.state.timers[0].id, 0)
          break
        case 22:
          var hours = root.find("additionalDurationEditor").fieldEditor(0)
          events.mouseClick(hours, hours.width / 2, hours.height / 2, Qt.LeftButton, Qt.NoModifier, 0)
          root.check(hours.selectedText === "00", "clicking additional timer field selects both digits")
          events.keyClickChar("0", Qt.NoModifier, 0)
          events.keyClick(Qt.Key_Return, Qt.NoModifier, 0)
          break
        case 23:
          var extra = root.find("additionalDurationEditor")
          root.check(extra.fieldEditor(1).activeFocus && extra.fieldEditor(0).text === "00", "Enter pads additional timer hours and advances")
          events.keyClickChar("0", Qt.NoModifier, 0)
          events.keyClickChar("5", Qt.NoModifier, 0)
          break
        case 24:
          root.check(root.find("additionalDurationEditor").fieldEditor(2).activeFocus, "two typed additional-timer digits advance to seconds")
          events.keyClickChar("9", Qt.NoModifier, 0)
          events.keyClick(Qt.Key_Return, Qt.NoModifier, 0)
          break
        case 25:
          root.check(root.find("additionalStartButton").activeFocus && root.find("additionalDurationEditor").fieldEditor(2).text === "09", "Enter pads additional timer seconds and focuses its Start button")
          root.check(root.fixture.state.timers[0].valueMs === 309000, "additional keyboard editing commits the exact HH:MM:SS duration")
          root.check(root.fixture.state.timers.every(function(counter, index) { return !counter.autoName || counter.name === "Timer " + (index + 1) }), "timer numbering follows current instances while custom names survive")
          var title = root.find("additionalTitleField")
          root.customTimerId = root.fixture.state.timers[0].id
          root.check(title.font.pixelSize === Math.round(Commons.Style.font.body * 1.2), "additional names are twenty percent larger")
          events.mouseClick(title, title.width / 2, title.height / 2, Qt.LeftButton, Qt.NoModifier, 0)
          title.forceActiveFocus()
          events.keyClick(Qt.Key_A, Qt.ControlModifier, 0)
          for (var character of "Deep Work") events.keyClickChar(character, Qt.NoModifier, 0)
          root.check(root.panel.counterById(root.customTimerId).name === "Deep Work" && !root.panel.counterById(root.customTimerId).autoName, "real title typing immediately saves a custom name")
          root.panel.addCounter("timer")
          break
        case 26:
          root.check(root.panel.counterById(root.customTimerId).name === "Deep Work", "custom name survives rebuilding the additional-instance list")
          var restored = Model.restoreState(JSON.stringify(root.fixture.state)).state
          root.check(restored.timers.find(function(counter) { return counter.id === root.customTimerId }).name === "Deep Work", "custom name survives persistent state recovery")
          root.fixture.readoutBudgetOverride = -1
          root.panel.toggleCounter(root.customTimerId, "timer")
          break
        case 27:
          var compactRow = root.find("barReadoutRow").children.find(function(item) { return item.objectName === "activeReadout" && item.modelData.name === "Deep Work" })
          root.check(!!compactRow && /^Deep Work - \d{2}:\d{2}$/.test(compactRow.children[0].text), "custom timer name renders as Name - 00:00 with spaces around the dash in compact mode")
          root.finish("")
          return
        }
        root.step++
      } catch (error) { root.finish(String(error) + " at step " + root.step) }
    }
  }
}
