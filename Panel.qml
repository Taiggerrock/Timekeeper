pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons as Commons
import qs.Ui as Ui

import "Model.js" as Model

Ui.Panel {
  id: root
  moduleName: "bone.timekeeper"
  manageIpc: false
  property var anchorItem: null
  property var hostWidget: null
  property var stateOwner: null
  property int selectedTab: 0
  readonly property var state: {
    if (!stateOwner) return Model.initialState()
    stateOwner.revision
    return stateOwner.state
  }
  readonly property var sideCounters: {
    if (!stateOwner) return []
    stateOwner.revision
    return selectedTab === 0 ? state.timers : state.stopwatches
  }
  readonly property bool hasSidebar: sideCounters.length > 0
  readonly property real additionalActionSize: Commons.Style.space(68) * 0.8
  readonly property real savedTimeSize: Commons.Style.font.displayLarge * 2 * 0.576
  readonly property int historyRowHeight: Math.ceil(Math.max(mainDurationEditor.timeHeight * 0.64, additionalActionSize) + Commons.Style.space(8))
  readonly property int sidebarWidth: Math.ceil(Math.max(mainDurationEditor.clockWidth * 0.64, additionalStopwatchMetrics.advanceWidth("00:00:00:00")) + additionalActionSize * 2 + Commons.Style.space(40))
  // Keep the default card five percent narrower than its original width; retain controlInset.
  readonly property int bodyWidth: Math.max(Commons.Style.space(314), Math.min(
    Math.round((Commons.Style.space(455) + cardInsets) * 0.945 - cardInsets),
    (popup.availableCardWidth > 0 ? popup.availableCardWidth : Commons.Style.space(900)) - cardInsets))
  readonly property int defaultBodyHeight: Math.round(Commons.Style.space(512) * 1.1025)
  readonly property int bodyHeight: Math.max(Commons.Style.space(120), Math.min(defaultBodyHeight, popup.availableCardHeight > 0 ? popup.availableCardHeight - Commons.Style.space(92) : defaultBodyHeight))
  readonly property real cardInsets: popup.padding * 2 + Commons.Border.left(popup.borderSpec) + Commons.Border.right(popup.borderSpec)
  readonly property real sidebarExpansion: hasSidebar ? sidebarWidth + rowGap * 2 + 1 : 0
  property real frozenPillLeft: 0
  property real frozenPillRight: 0
  property string anchorSection: "center"
  readonly property var realAnchorWindow: anchorItem ? anchorItem.QsWindow.window : null
  TransformWatcher {
    id: pillWatcher
    a: root.realAnchorWindow ? root.realAnchorWindow.contentItem : null
    b: root.anchorItem
  }
  readonly property point livePillPosition: {
    pillWatcher.transform
    return anchorItem && realAnchorWindow ? anchorItem.mapToItem(realAnchorWindow.contentItem, 0, 0) : Qt.point(0, 0)
  }
  readonly property var placement: Model.panelPlacement(frozenPillLeft, frozenPillRight,
    popup.screenW > 0 ? popup.screenW : 1920, popup.margin, bodyWidth + cardInsets, sidebarExpansion, anchorSection)
  readonly property bool sidebarOnLeft: placement.sidebarOnLeft
  function captureAnchor() {
    frozenPillLeft = livePillPosition.x
    frozenPillRight = frozenPillLeft + (anchorItem ? anchorItem.width : 0)
    var sections = bar && bar.layoutConfig ? bar.layoutConfig : ({})
    anchorSection = "center"
    for (var section of ["left", "center", "right"]) {
      var entries = sections[section] || []
      if (entries.some(function(entry) { return (typeof entry === "string" ? entry : entry.id) === root.moduleName })) {
        anchorSection = section
        return
      }
    }
    if (popup.screenW > 0 && frozenPillLeft > popup.screenW * 0.75) anchorSection = "right"
  }
  // KeyboardPanel normally centers on its anchor. Give it a virtual card-sized
  // anchor, offset against the live pill, so the frozen corner stays in place.
  Item {
    id: placementAnchor
    parent: root.anchorItem
    x: root.placement.left - root.livePillPosition.x
    y: 0
    width: popup.contentWidth
    height: root.anchorItem ? root.anchorItem.height : 0
    visible: false
  }
  readonly property int controlInset: Commons.Style.space(4)
  readonly property int rowGap: Commons.Style.space(12)
  FontMetrics {
    id: additionalStopwatchMetrics
    font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
    font.pixelSize: Commons.Style.font.displayLarge * 2 * 0.64
    font.bold: true
    font.kerning: false
  }

  function currentTime() { return stateOwner ? stateOwner.currentTime() : Date.now() }
  function changed() { if (stateOwner) stateOwner.saveChanged() }
  function selectTab(tab) { selectedTab = tab }
  function counterRunning(counter) {
    if (stateOwner) stateOwner.revision
    return counter.running
  }
  function counterValue(counter, kind) { return Model.displayMs(counter, kind, stateOwner ? stateOwner.now : root.currentTime()) }
  function editMainTimer(value) {
    if (Model.setValue(state.mainTimer, value)) changed()
  }
  function counterById(counterId) {
    return state.timers.concat(state.stopwatches).find(function(counter) { return counter.id === counterId }) || null
  }
  function editCounterTimer(counterId, value) {
    var current = counterById(counterId)
    if (current && Model.setValue(current, value)) changed()
  }
  function mainTimerAction() {
    if (state.mainTimer.running) Model.stop(state.mainTimer, "timer", root.currentTime())
    else Model.start(state.mainTimer, "timer", root.currentTime(), state.startSequence++)
    changed()
  }
  function mainStopwatchAction() {
    if (state.mainStopwatch.running) Model.stop(state.mainStopwatch, "stopwatch", root.currentTime())
    else Model.start(state.mainStopwatch, "stopwatch", root.currentTime(), state.startSequence++)
    changed()
  }
  function resetStopwatch() {
    Model.stop(state.mainStopwatch, "stopwatch", root.currentTime())
    state.mainStopwatch.valueMs = 0
    changed()
  }
  function recordLap() {
    var value = Model.displayMs(state.mainStopwatch, "stopwatch", root.currentTime())
    state.laps = Model.appendHistory(state.laps, value)
    changed()
  }
  function savePreset() {
    state.presets = Model.appendHistory(state.presets, state.mainTimer.valueMs).filter(function(row) { return row.valueMs <= Model.MAX_TIMER_MS }).slice(0, Model.HISTORY_LIMIT)
    changed()
  }
  function recallTimer(value) {
    Model.stop(state.mainTimer, "timer", root.currentTime())
    state.mainTimer.valueMs = Model.clampDuration(value)
    state.mainTimer.startedAt = 0
    changed()
  }
  function recallLap(value) {
    Model.stop(state.mainStopwatch, "stopwatch", root.currentTime())
    state.mainStopwatch.valueMs = Math.max(0, Math.floor(value))
    changed()
  }
  function addCounter(kind) {
    Model.addCounter(state, kind)
    changed()
  }
  function deleteCounter(kind, id) {
    if (kind === "timer") {
      state.timers = state.timers.filter(function(row) { return row.id !== id })
      Model.renumberTimers(state)
    }
    else {
      state.stopwatches = state.stopwatches.filter(function(row) { return row.id !== id })
      Model.renumberStopwatches(state)
    }
    changed()
  }
  function renameCounter(counterId, value) {
    var counter = counterById(counterId)
    if (!counter) return
    counter.name = Model.cleanName(value, selectedTab === 0 ? "Timer" : "Stopwatch")
    counter.autoName = false
    changed()
  }
  function toggleCounter(counterId, kind) {
    var counter = counterById(counterId)
    if (!counter) return
    if (counter.running) Model.stop(counter, kind, root.currentTime())
    else Model.start(counter, kind, root.currentTime(), state.startSequence++)
    changed()
  }

  function moveFocus(direction) {
    var candidates = []
    collectFocus(keyCatcher, candidates)
    var index = -1
    for (var i = 0; i < candidates.length; i++) if (candidates[i].activeFocus) index = i
    if (index < 0) index = direction > 0 ? -1 : 0
    var next = (index + direction + candidates.length) % candidates.length
    if (candidates[next]) candidates[next].forceActiveFocus()
  }
  function collectFocus(item, result) {
    if (!item || item.visible === false || item.enabled === false) return
    if (item.activeFocusOnTab === true) result.push(item)
    var children = item.children || []
    for (var i = 0; i < children.length; i++) collectFocus(children[i], result)
  }
  function hasDescendantFocus(item) {
    var children = item ? item.children || [] : []
    for (var i = 0; i < children.length; i++) {
      if (children[i].activeFocus || hasDescendantFocus(children[i])) return true
    }
    return false
  }
  function open() { if (!opened) captureAnchor(); controller.show() }
  function close() { controller.hide() }
  function toggle() { opened ? close() : open() }

  Ui.KeyboardPanel {
    id: popup
    objectName: "timekeeperPopup"
    anchorItem: placementAnchor
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(root.bodyWidth + root.sidebarExpansion + root.cardInsets)
    contentHeight: popup.fittedContentHeight(layout.implicitHeight)

    Ui.PanelKeyCatcher {
      id: keyCatcher
      objectName: "timekeeperKeyCatcher"
      Keys.onEscapePressed: function(event) { root.close(); event.accepted = true }
      anchors.fill: parent
      blocked: root.hasDescendantFocus(keyCatcher)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.moveFocus(direction) }

      Rectangle {
        objectName: "fullHeightDivider"
        visible: root.hasSidebar
        z: 1
        x: (root.sidebarOnLeft ? root.sidebarWidth + root.rowGap : root.bodyWidth + root.rowGap) - combinedScroll.contentX
        y: -popup.padding - Commons.Border.top(popup.borderSpec)
        width: 1
        height: popup.contentHeight
        color: Commons.Color.popups.border
        opacity: 0.5
      }

      Column {
        id: layout
        objectName: "timekeeperLayout"
        width: parent.width
        spacing: Commons.Style.space(10)

        Row {
          id: tabRow
          objectName: "tabRow"
          x: (root.sidebarOnLeft ? root.sidebarExpansion : 0) + root.controlInset
          width: root.bodyWidth - root.controlInset * 2
          spacing: Commons.Style.space(8)
          Ui.Button {
            objectName: "timerTabButton"
            width: (tabRow.width - tabRow.spacing) / 2
            text: "TIMER"; focusable: true; selected: root.selectedTab === 0; bordered: true
            onClicked: root.selectTab(0)
            Accessible.name: "TIMER TAB"
            Keys.onRightPressed: function(event) { root.selectTab(1); event.accepted = true }
          }
          Ui.Button {
            objectName: "stopwatchTabButton"
            width: (tabRow.width - tabRow.spacing) / 2
            text: "STOPWATCH"; focusable: true; selected: root.selectedTab === 1; bordered: true
            onClicked: root.selectTab(1)
            Accessible.name: "STOPWATCH TAB"
            Keys.onLeftPressed: function(event) { root.selectTab(0); event.accepted = true }
          }
        }

        Flickable {
          id: combinedScroll
          Controls.ScrollBar.horizontal: ListScrollBar {}
          width: parent.width
          height: root.bodyHeight
          contentWidth: root.bodyWidth + root.sidebarExpansion
          contentHeight: height
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          Row {
          objectName: "counterColumns"
          layoutDirection: root.sidebarOnLeft ? Qt.RightToLeft : Qt.LeftToRight
          width: combinedScroll.contentWidth
          height: combinedScroll.height
          spacing: root.rowGap

          Flickable {
            id: mainScroll
            Controls.ScrollBar.vertical: ListScrollBar {}
            objectName: "mainCounterScroll"
            width: root.bodyWidth
            height: root.bodyHeight
            clip: true
            contentWidth: width
            contentHeight: root.selectedTab === 0 ? timerColumn.implicitHeight : watchColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: timerColumn
              x: root.controlInset
              objectName: "timerColumn"
              width: mainScroll.width - root.controlInset * 2 - (mainScroll.contentHeight > mainScroll.height ? Commons.Style.space(12) : 0)
              spacing: Commons.Style.space(12)
              visible: root.selectedTab === 0

              DurationEditor {
                id: mainDurationEditor
                startButton: mainTimerStartButton
                objectName: "mainDurationEditor"
                width: parent.width
                height: implicitHeight
                largeDisplay: true
                valueMs: root.counterValue(root.state.mainTimer, "timer")
                editingEnabled: !root.state.mainTimer.running
                foreground: root.barForeground
                fontFamily: root.bar ? root.bar.fontFamily : Commons.Style.font.family
                accent: Commons.Color.accent
                onValueAccepted: function(value) { root.editMainTimer(value) }
              }
              GridLayout {
                width: parent.width
                columns: 2
                uniformCellWidths: true
                height: implicitHeight
                columnSpacing: Commons.Style.space(8)
                rowSpacing: Commons.Style.space(7)
                Ui.Button {
                  Layout.fillWidth: true
                  id: mainTimerStartButton
                  objectName: "timerStartButton"
                  text: root.state.mainTimer.running ? "STOP" : "START"
                  focusable: true
                  enabled: root.state.mainTimer.running || root.counterValue(root.state.mainTimer, "timer") > 0
                  bordered: true
                  onClicked: root.mainTimerAction()
                }
                Ui.Button {
                  Layout.fillWidth: true
                  text: "RESET"
                  focusable: true
                  enabled: root.counterValue(root.state.mainTimer, "timer") > 0
                  bordered: true
                  onClicked: { Model.stop(root.state.mainTimer, "timer", root.currentTime()); root.state.mainTimer.valueMs = 0; root.changed() }
                }
                Ui.Button {
                  Layout.fillWidth: true
                  text: "SAVE"
                  focusable: true
                  enabled: root.counterValue(root.state.mainTimer, "timer") > 0 && !root.state.mainTimer.running
                  bordered: true
                  onClicked: root.savePreset()
                }
                Ui.Button { Layout.fillWidth: true; objectName: "addTimerButton"; text: "ADD TIMER"; focusable: true; bordered: true; onClicked: root.addCounter("timer") }
              }
              Rectangle { width: parent.width; height: Math.max(1, Commons.Style.space(1)); color: Commons.Color.popups.border; opacity: 0.5 }
              Text { text: "SAVED PRESETS"; color: Commons.Color.muted; font.family: Commons.Style.font.family; font.pixelSize: Commons.Style.font.bodySmall }
              Flickable {
                id: presetScroll
                objectName: "presetScroll"
                Controls.ScrollBar.vertical: ListScrollBar {}
                width: parent.width
                height: Math.max(Commons.Style.space(40), Math.min(5, root.state.presets.length) * (root.historyRowHeight + Commons.Style.space(4)) - Commons.Style.space(4))
                contentWidth: width
                contentHeight: presetRows.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
              Column {
                id: presetRows
                width: presetScroll.width - (presetScroll.contentHeight > presetScroll.height ? Commons.Style.space(14) : 0)
                spacing: Commons.Style.space(4)
                Repeater {
                  model: { root.stateOwner ? root.stateOwner.revision : 0; root.state.presets }
                  delegate: Item {
                    required property int index
                    required property var modelData
                    objectName: "historyRow"
                    width: parent.width; height: root.historyRowHeight
                    activeFocusOnTab: true
                    Accessible.name: "Preset " + Model.formatTime(modelData.valueMs)
                    Keys.onReturnPressed: root.recallTimer(modelData.valueMs)
                    Keys.onEnterPressed: root.recallTimer(modelData.valueMs)
                    Keys.onSpacePressed: root.recallTimer(modelData.valueMs)
                    Rectangle { anchors.fill: parent; radius: Commons.Style.cornerRadius; color: historyMouse.containsMouse || parent.activeFocus ? Commons.Style.hoverFillFor(root.barForeground, Commons.Color.accent) : "transparent"; border.width: parent.activeFocus ? Math.max(1, Commons.Style.space(1)) : 0; border.color: Commons.Color.accent }
                    MouseArea { id: historyMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.recallTimer(modelData.valueMs) }
                    Text { objectName: "presetTimeText"; width: parent.width - root.additionalActionSize - Commons.Style.space(21); elide: Text.ElideRight; anchors.left: parent.left; anchors.leftMargin: Commons.Style.space(12); anchors.verticalCenter: parent.verticalCenter; text: Model.formatTime(modelData.valueMs); color: root.barForeground; font.family: Commons.Style.font.family; font.pixelSize: root.savedTimeSize; font.bold: true; font.kerning: false }
                    Ui.Button {
                      width: root.additionalActionSize; height: root.additionalActionSize; fontSize: Commons.Style.font.body * 2; anchors.right: parent.right; anchors.rightMargin: Commons.Style.space(3); anchors.verticalCenter: parent.verticalCenter
                      objectName: "presetDeleteButton"; text: "󰆴"; iconText: ""; focusable: true; tooltipText: "DELETE PRESET"; Accessible.name: "DELETE PRESET " + Model.formatTime(modelData.valueMs)
                      onClicked: { root.state.presets = root.state.presets.filter(function(_, i) { return i !== index }); root.changed() }
                    }
                  }
                }
                Text { visible: root.state.presets.length === 0; text: "No saved presets"; color: Commons.Color.muted; font.family: Commons.Style.font.family; font.pixelSize: Commons.Style.font.bodySmall; padding: Commons.Style.space(8) }
              }
              }
            }

            Column {
              id: watchColumn
              x: root.controlInset
              objectName: "watchColumn"
              width: mainScroll.width - root.controlInset * 2 - (mainScroll.contentHeight > mainScroll.height ? Commons.Style.space(12) : 0)
              spacing: Commons.Style.space(12)
              visible: root.selectedTab === 1

              DurationEditor {
                id: mainStopwatchClock
                objectName: "stopwatchClock"
                width: parent.width
                height: implicitHeight
                largeDisplay: true
                showSubseconds: true
                editingEnabled: false
                valueMs: root.counterValue(root.state.mainStopwatch, "stopwatch")
                foreground: root.barForeground
                fontFamily: root.bar ? root.bar.fontFamily : Commons.Style.font.family
              }
              GridLayout {
                width: parent.width
                columns: 2
                uniformCellWidths: true
                height: implicitHeight
                columnSpacing: Commons.Style.space(8)
                rowSpacing: Commons.Style.space(7)
                Ui.Button {
                  Layout.fillWidth: true
                  objectName: "stopwatchStartButton"
                  text: root.state.mainStopwatch.running ? "STOP" : "START"
                  focusable: true; bordered: true
                  onClicked: root.mainStopwatchAction()
                }
                Ui.Button {
                  Layout.fillWidth: true
                  objectName: "stopwatchLapButton"
                  text: root.state.mainStopwatch.running ? "LAP" : "RESET"
                  focusable: true; bordered: true
                  onClicked: root.state.mainStopwatch.running ? root.recordLap() : root.resetStopwatch()
                }
                Ui.Button {
                  Layout.fillWidth: true
                  objectName: "copyTimeButton"
                  text: "COPY TIME"
                  focusable: true; bordered: true
                  Accessible.name: "COPY TIME"
                  onClicked: root.stateOwner.copyText(Model.formatStopwatchTime(root.counterValue(root.state.mainStopwatch, "stopwatch")))
                }
                Ui.Button {
                  Layout.fillWidth: true
                  objectName: "addStopwatchButton"
                  text: "ADD STOPWATCH"
                  focusable: true; bordered: true
                  onClicked: root.addCounter("stopwatch")
                }
              }
              Rectangle { width: parent.width; height: Math.max(1, Commons.Style.space(1)); color: Commons.Color.popups.border; opacity: 0.5 }
              Text { text: "LAPS"; color: Commons.Color.muted; font.family: Commons.Style.font.family; font.pixelSize: Commons.Style.font.bodySmall }
              Flickable {
                id: lapScroll
                objectName: "lapScroll"
                Controls.ScrollBar.vertical: ListScrollBar {}
                width: parent.width
                height: Math.max(Commons.Style.space(40), Math.min(5, root.state.laps.length) * (root.historyRowHeight + Commons.Style.space(4)) - Commons.Style.space(4))
                contentWidth: width
                contentHeight: lapRows.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
              Column {
                id: lapRows
                width: lapScroll.width - (lapScroll.contentHeight > lapScroll.height ? Commons.Style.space(14) : 0)
                spacing: Commons.Style.space(4)
                Repeater {
                  model: { root.stateOwner ? root.stateOwner.revision : 0; root.state.laps }
                  delegate: Item {
                    required property int index
                    required property var modelData
                    objectName: "historyRow"
                    width: parent.width; height: root.historyRowHeight
                    activeFocusOnTab: true
                    Accessible.name: "Lap " + Model.formatStopwatchTime(modelData.valueMs)
                    Keys.onReturnPressed: root.recallLap(modelData.valueMs)
                    Keys.onEnterPressed: root.recallLap(modelData.valueMs)
                    Keys.onSpacePressed: root.recallLap(modelData.valueMs)
                    Rectangle { anchors.fill: parent; radius: Commons.Style.cornerRadius; color: lapMouse.containsMouse || parent.activeFocus ? Commons.Style.hoverFillFor(root.barForeground, Commons.Color.accent) : "transparent"; border.width: parent.activeFocus ? Math.max(1, Commons.Style.space(1)) : 0; border.color: Commons.Color.accent }
                    MouseArea { id: lapMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.recallLap(modelData.valueMs) }
                    Text { objectName: "lapTimeText"; width: parent.width - root.additionalActionSize * 2 - Commons.Style.space(24); elide: Text.ElideRight; anchors.left: parent.left; anchors.leftMargin: Commons.Style.space(12); anchors.verticalCenter: parent.verticalCenter; text: Model.formatStopwatchTime(modelData.valueMs); color: root.barForeground; font.family: Commons.Style.font.family; font.pixelSize: root.savedTimeSize; font.bold: true; font.kerning: false }
                    Row {
                      anchors.right: parent.right; anchors.rightMargin: Commons.Style.space(3); anchors.verticalCenter: parent.verticalCenter; spacing: Commons.Style.space(3)
                      Ui.Button { width: root.additionalActionSize; height: root.additionalActionSize; fontSize: Commons.Style.font.body * 2; text: "󰆏"; iconText: ""; focusable: true; tooltipText: "COPY LAP TIME"; Accessible.name: "COPY LAP " + Model.formatStopwatchTime(modelData.valueMs); onClicked: root.stateOwner.copyText(Model.formatStopwatchTime(modelData.valueMs)) }
                      Ui.Button { width: root.additionalActionSize; height: root.additionalActionSize; fontSize: Commons.Style.font.body * 2; objectName: "lapDeleteButton"; text: "󰆴"; iconText: ""; focusable: true; tooltipText: "DELETE LAP"; Accessible.name: "DELETE LAP " + Model.formatStopwatchTime(modelData.valueMs); onClicked: { root.state.laps = root.state.laps.filter(function(_, i) { return i !== index }); root.changed() } }
                    }
                  }
                }
                Text { visible: root.state.laps.length === 0; text: "No laps yet"; color: Commons.Color.muted; font.family: Commons.Style.font.family; font.pixelSize: Commons.Style.font.bodySmall; padding: Commons.Style.space(8) }
              }
              }
            }
          }

          Rectangle {
            visible: root.hasSidebar
            width: Math.max(1, Commons.Style.space(1))
            height: root.bodyHeight
            color: "transparent"
          }

          Flickable {
            id: sideScroll
            Controls.ScrollBar.vertical: ListScrollBar {}
            objectName: "additionalCounterScroll"
            visible: root.hasSidebar
            width: root.sidebarWidth
            height: root.bodyHeight
            clip: true
            contentWidth: width
            contentHeight: sideColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            Column {
              id: sideColumn
              width: sideScroll.width - (sideScroll.contentHeight > sideScroll.height ? Commons.Style.space(14) : 0)
              spacing: Commons.Style.space(9)
              Text { text: root.selectedTab === 0 ? "TIMERS" : "STOPWATCHES"; color: Commons.Color.muted; font.family: Commons.Style.font.family; font.pixelSize: Commons.Style.font.bodySmall }
              Repeater {
                model: root.sideCounters
                delegate: Item {
                  id: extraRow
                  required property var modelData
                  property string counterId: ""
                  property string counterKind: ""
                  readonly property real controlsHeight: Math.max(extraTimeEditor.implicitHeight, root.additionalActionSize)
                  // Repeater modelData can be a snapshot; resolve mutable state by ID.
                  readonly property var counter: {
                    if (root.stateOwner) root.stateOwner.revision
                    return root.counterById(counterId || modelData.id) || modelData
                  }
                  Component.onCompleted: { counterId = modelData.id; counterKind = root.selectedTab === 0 ? "timer" : "stopwatch" }
                  objectName: "additionalCounter"
                  width: parent.width; height: extraRow.controlsHeight + Commons.Style.space(49)
                  Rectangle { anchors.fill: parent; radius: Commons.Style.cornerRadius; color: Commons.Style.hoverFillFor(root.barForeground, Commons.Color.accent); opacity: 0.26 }
                  Column {
                    anchors.fill: parent; anchors.margins: Commons.Style.space(7); spacing: Commons.Style.space(5)
                    Row {
                      width: parent.width; height: Commons.Style.space(30); spacing: Commons.Style.space(4)
                      TextInput {
                        id: titleField
                        objectName: "additionalTitleField"
                        property bool userEdited: false
                        onTextEdited: {
                          userEdited = true
                          // Save edits as they happen; list rebuilds must not lose a custom name.
                          root.renameCounter(extraRow.counterId, text)
                        }
                        onActiveFocusChanged: if (activeFocus) {
                          text = extraRow.counter.name
                          selectAll()
                        }
                        width: parent.width; height: parent.height
                        text: extraRow.counter.name
                        color: root.barForeground
                        font.family: Commons.Style.font.family; font.pixelSize: Commons.Style.font.body * 1.2
                        verticalAlignment: TextInput.AlignVCenter
                        maximumLength: Model.TITLE_LIMIT
                        activeFocusOnTab: true
                        selectByMouse: true
                        onEditingFinished: {
                          if (userEdited) {
                            userEdited = false
                            root.renameCounter(extraRow.counterId, text)
                            text = Qt.binding(function() { return extraRow.counter.name })
                          }
                        }
                        Accessible.name: "Counter name"
                      }
                    }
                    Row {
                      width: parent.width; height: extraRow.controlsHeight
                      spacing: Commons.Style.space(5)
                      DurationEditor {
                        id: extraTimeEditor
                        startButton: extraStartButton
                        objectName: "additionalDurationEditor"
                        largeDisplay: true
                        sizeScale: 0.64
                        visible: root.selectedTab === 0
                        width: parent.width - root.additionalActionSize * 2 - Commons.Style.space(10); height: parent.height
                        valueMs: root.counterValue(extraRow.counter, "timer")
                        editingEnabled: !root.counterRunning(extraRow.counter)
                        foreground: root.barForeground; accent: Commons.Color.accent
                        fontFamily: root.bar ? root.bar.fontFamily : Commons.Style.font.family
                        onValueAccepted: function(value) { root.editCounterTimer(extraRow.counterId, value) }
                      }
                      DurationEditor {
                        objectName: "additionalStopwatchClock"
                        visible: root.selectedTab === 1
                        width: parent.width - root.additionalActionSize * 2 - Commons.Style.space(10)
                        height: parent.height
                        largeDisplay: true
                        sizeScale: 0.64
                        showSubseconds: true
                        editingEnabled: false
                        valueMs: root.counterValue(extraRow.counter, "stopwatch")
                        foreground: root.barForeground
                        fontFamily: root.bar ? root.bar.fontFamily : Commons.Style.font.family
                      }
                      Ui.Button {
                        id: extraStartButton
                        objectName: "additionalStartButton"
                        width: root.additionalActionSize; height: root.additionalActionSize; anchors.verticalCenter: parent.verticalCenter
                        fontSize: Commons.Style.font.body * 2
                        text: root.counterRunning(extraRow.counter) ? "󰓛" : "󰐊"; iconText: ""; focusable: true
                        enabled: root.counterRunning(extraRow.counter) || root.selectedTab === 1 || root.counterValue(extraRow.counter, extraRow.counterKind) > 0
                        tooltipText: root.counterRunning(extraRow.counter) ? "STOP" : "START"
                        Accessible.name: (root.counterRunning(extraRow.counter) ? "STOP " : "START ") + extraRow.counter.name
                        onClicked: root.toggleCounter(extraRow.counterId, extraRow.counterKind)
                      }
                      Ui.Button {
                        width: root.additionalActionSize; height: root.additionalActionSize; anchors.verticalCenter: parent.verticalCenter
                        fontSize: Commons.Style.font.body * 2
                        text: "󰆴"; iconText: ""; focusable: true; objectName: "deleteCounterButton"; tooltipText: "DELETE COUNTER"
                        Accessible.name: "DELETE " + extraRow.counter.name
                        onClicked: root.deleteCounter(extraRow.counterKind, extraRow.counterId)
                      }
                    }
                  }
                }
              }
              Text { visible: root.sideCounters.length === 0; text: "No additional counters"; color: Commons.Color.muted; font.family: Commons.Style.font.family; font.pixelSize: Commons.Style.font.bodySmall }
            }
          }
        }
        }
      }
    }
  }
}
