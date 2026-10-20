import QtQuick
import QtQuick.Controls as Controls
import qs.Commons as Commons

Controls.ScrollBar {
  id: root
  objectName: "listScrollBar"
  active: true
  policy: size < 1 ? Controls.ScrollBar.AlwaysOn : Controls.ScrollBar.AlwaysOff
  implicitWidth: Commons.Style.space(8)
  implicitHeight: Commons.Style.space(8)
  minimumSize: 0.08
  contentItem: Rectangle {
    implicitWidth: Commons.Style.space(6)
    implicitHeight: Commons.Style.space(6)
    radius: Commons.Style.space(3)
    color: Commons.Color.foreground
    opacity: root.pressed ? 1 : 0.7
  }
  background: Rectangle {
    color: Commons.Color.muted
    opacity: 0.18
    radius: Commons.Style.space(3)
  }
}
