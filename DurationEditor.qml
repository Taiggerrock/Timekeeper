pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons as Commons

Item {
  id: root
  property int valueMs: 0
  property bool editingEnabled: true
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property bool largeDisplay: false
  property bool showSubseconds: false
  property var startButton: null
  property real sizeScale: 1
  signal valueAccepted(int value)

  property string fontFamily: Commons.Style.font.family
  implicitHeight: timeHeight
  implicitWidth: clockWidth
  readonly property real displaySize: (largeDisplay ? Commons.Style.font.displayLarge * 2 : Commons.Style.font.heading) * sizeScale
  readonly property real fieldWidth: clockMetrics.advanceWidth("00")
  readonly property real colonWidth: clockMetrics.advanceWidth(":")
  readonly property real clockWidth: fieldWidth * (showSubseconds ? 4 : 3) + colonWidth * (showSubseconds ? 3 : 2)
  readonly property real timeHeight: Math.ceil(clockMetrics.height) + Commons.Style.space(4) * sizeScale
  readonly property int totalSeconds: Math.floor(valueMs / 1000)
  readonly property string hoursText: pad(Math.floor(totalSeconds / 3600))
  readonly property string minutesText: pad(Math.floor(totalSeconds / 60) % 60)
  readonly property string secondsText: pad(totalSeconds % 60)
  readonly property string subsecondsText: pad(Math.floor((Math.max(0, valueMs) % 1000) / 10))
  readonly property string formattedValue: hoursText + ":" + minutesText + ":" + secondsText + (showSubseconds ? ":" + subsecondsText : "")

  FontMetrics {
    id: clockMetrics
    font.family: root.fontFamily
    font.pixelSize: root.displaySize
    font.bold: root.largeDisplay
    font.kerning: false
  }

  function pad(value) { return value < 10 ? "0" + value : String(value) }
  function partValue(field) { return field === 0 ? Math.floor(totalSeconds / 3600) : (field === 1 ? Math.floor(totalSeconds / 60) % 60 : totalSeconds % 60) }
  function acceptPart(field, input) {
    var text = String(input)
    if (!/^\d{1,2}$/.test(text)) return false
    var number = Number(text)
    if (field === 0 && number > 99 || field !== 0 && number > 59) return false
    var h = field === 0 ? number : Math.floor(totalSeconds / 3600)
    var m = field === 1 ? number : Math.floor(totalSeconds / 60) % 60
    var s = field === 2 ? number : totalSeconds % 60
    valueAccepted(((h * 3600) + (m * 60) + s) * 1000)
    return true
  }
  function fieldEditor(field) {
    var segment = partRepeater.itemAt(field * 2)
    if (!segment) return null
    var children = segment.children
    for (var index = 0; index < children.length; index++) {
      if (children[index].objectName === "durationField") return children[index]
    }
    return null
  }
  function focusField(field) {
    var editor = fieldEditor(field)
    if (!editingEnabled || !editor) return
    editor.forceActiveFocus()
    editor.selectAll()
  }
  function finishField(field) {
    if (!editingEnabled) return
    var editor = fieldEditor(field)
    if (!editor) return
    if (!acceptPart(field, editor.text || "0")) { editor.selectAll(); return }
    editor.userEdited = false
    editor.text = Qt.binding(function() { return root.pad(root.partValue(field)) })
    Qt.callLater(function() {
      if (!root.editingEnabled) return
      if (field < 2) root.focusField(field + 1)
      else if (root.startButton && root.startButton.enabled) root.startButton.forceActiveFocus()
    })
  }

  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    width: root.clockWidth
    height: root.timeHeight
    spacing: 0
    Repeater {
      id: partRepeater
      model: root.showSubseconds ? 7 : 5
      delegate: Item {
        id: segment
        objectName: "durationSegment"
        required property int index
        readonly property bool separator: index === 1 || index === 3 || index === 5
        readonly property int field: index === 0 ? 0 : index === 2 ? 1 : index === 4 ? 2 : 3
        width: separator ? root.colonWidth : root.fieldWidth
        height: root.timeHeight

        Text {
          anchors.centerIn: parent
          visible: segment.separator
          text: ":"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: root.displaySize
          font.bold: root.largeDisplay
          font.kerning: false
        }

        TextInput {
          id: fieldInput
          objectName: "durationField"
          property bool userEdited: false
          anchors.fill: parent
          visible: !segment.separator
          onTextEdited: {
            userEdited = true
            if (!root.editingEnabled) return
            if (text.length === 2) root.finishField(segment.field)
            else root.acceptPart(segment.field, text)
          }
          text: segment.field === 0 ? root.hoursText
            : segment.field === 1 ? root.minutesText
            : segment.field === 2 ? root.secondsText : root.subsecondsText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: root.displaySize
          font.bold: root.largeDisplay
          font.kerning: false
          horizontalAlignment: TextInput.AlignHCenter
          verticalAlignment: TextInput.AlignVCenter
          selectByMouse: true
          activeFocusOnTab: root.editingEnabled
          readOnly: !root.editingEnabled
          validator: RegularExpressionValidator { regularExpression: /\d{0,2}/ }
          onEditingFinished: {
            if (!root.editingEnabled) return
            if (userEdited) {
              userEdited = false
              root.acceptPart(segment.field, text)
            }
            fieldInput.text = Qt.binding(function() { return root.pad(root.partValue(segment.field)) })
          }
          onActiveFocusChanged: if (activeFocus) {
            fieldInput.text = root.pad(root.partValue(segment.field))
            fieldInput.selectAll()
          }
          TapHandler {
            onTapped: if (root.editingEnabled) { fieldInput.forceActiveFocus(); fieldInput.selectAll() }
          }
          Keys.onReturnPressed: function(event) { root.finishField(segment.field); event.accepted = true }
          Keys.onEnterPressed: function(event) { root.finishField(segment.field); event.accepted = true }
          Accessible.name: segment.field === 0 ? "Hours" : segment.field === 1 ? "Minutes" : segment.field === 2 ? "Seconds" : "Centiseconds"
          Rectangle {
            anchors.fill: parent
            color: Commons.Style.focusFillFor(root.foreground, root.accent)
            opacity: fieldInput.activeFocus ? 0.3 : 0
            border.width: fieldInput.activeFocus ? Math.max(1, Commons.Style.space(1)) : 0
            border.color: root.accent
            radius: Commons.Style.cornerRadius
          }
        }
      }
    }
  }
}
