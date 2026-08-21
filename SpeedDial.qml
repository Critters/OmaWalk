import QtQuick

Item {
  id: root

  property real mph: 0
  property bool live: false
  property color trackColor: "#55ffffff"
  property color fillColor: "#88aaff"
  property color textColor: "#ffffff"
  property color dimColor: "#88ffffff"
  property string fontFamily: ""
  property int textSize: 24
  property int labelSize: 12

  readonly property real t: Math.max(0, Math.min(1, Number(mph) / 2.0))
  readonly property real cx: width / 2
  readonly property real cy: height / 2 + 6
  readonly property real radius: Math.max(8, Math.min(width, height) / 2 - 12)
  readonly property real startDeg: 135
  readonly property real spanDeg: 270
  readonly property int ticks: 68
  readonly property real stroke: 8

  // Capsule ticks around a 270° horseshoe. The fill color follows mph / 2.0.
  Repeater {
    model: root.ticks

    Rectangle {
      required property int index
      readonly property real p: index / Math.max(1, root.ticks - 1)
      readonly property real deg: root.startDeg + root.spanDeg * p
      readonly property real rad: deg * Math.PI / 180
      width: Math.max(root.stroke + 1, (2 * Math.PI * root.radius * (root.spanDeg / 360) / Math.max(1, root.ticks - 1)) + 2)
      height: root.stroke
      radius: height / 2
      antialiasing: true
      color: root.t > 0 && p <= root.t ? root.fillColor : root.trackColor
      x: root.cx + root.radius * Math.cos(rad) - width / 2
      y: root.cy + root.radius * Math.sin(rad) - height / 2
      rotation: deg + 90
    }
  }

  Column {
    z: 2
    anchors.horizontalCenter: parent.horizontalCenter
    y: root.cy - implicitHeight / 2
    spacing: 2

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: (Number(root.mph) || 0).toFixed(1)
      color: root.live ? root.fillColor : root.textColor
      font.family: root.fontFamily
      font.pixelSize: root.textSize
      font.bold: true
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "mph"
      color: root.dimColor
      font.family: root.fontFamily
      font.pixelSize: root.labelSize
    }
  }
}
