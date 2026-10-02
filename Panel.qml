import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "omawalk"
  ipcTarget: "omawalk"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var omawalk: null
  property bool openedFromHotkey: false
  property bool settingsOpen: false
  property string range: "day"
  property string metric: "steps"
  property string hoverHint: ""
  property string edgeAlign: "end"

  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function service() {
    if (bar && bar.shell && typeof bar.shell.serviceFor === "function")
      return bar.shell.serviceFor("omawalk")
    return omawalk
  }

  readonly property var pluginState: (service() ? service().state : null) || Model.defaultState()
  readonly property bool hasDevice: !!(pluginState.device && pluginState.device.address)
  readonly property bool scanning: service() ? service().scanning : false
  readonly property var scanResults: service() ? (service().scanResults || []) : []
  readonly property string scanError: service() ? (service().scanError || "") : ""
  readonly property bool walking: service() ? service().walking : false
  readonly property real speedMph: service() ? Number(service().speedMph) || 0 : 0
  readonly property var today: Model.dayTotal(pluginState.days, Model.ymd(new Date()))
  readonly property var buckets: {
    if (root.range === "week") return Model.weekBuckets(pluginState.days)
    if (root.range === "month") return Model.monthBuckets(pluginState.days)
    return Model.dayBuckets(pluginState.days)
  }
  readonly property int bucketMax: {
    var max = 1
    for (var i = 0; i < buckets.length; i++) {
      var v = root.metric === "distance" ? buckets[i].distanceMilli : buckets[i].steps
      if (v > max) max = v
    }
    return max
  }
  readonly property string page: {
    if (root.settingsOpen) return "settings"
    if (!root.hasDevice) return "scan"
    return "graphs"
  }

  function open() {
    openedFromHotkey = false
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    // Hide even if the hover flag throws. That write used to abort this
    // function, so the popup stayed up.
    try {
      setCenterHoverRevealSuppressed(false)
      root.settingsOpen = false
    } catch (e) {}
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Third-party widgets get PluginBarApi, whose centerHoverRevealSuppressed
  // is read-only. Assigning it throws and used to abort close() before hide().
  // The shell stores the working callback on the API object. A first-party
  // bar has a writable property and no callback.
  function setCenterHoverRevealSuppressed(value) {
    var bar = root.bar
    if (!bar) return
    var suppressed = !!value
    var hook = bar._setCenterHoverRevealSuppressed
    if (typeof hook === "function") {
      hook(suppressed)
      return
    }
    try {
      if (typeof bar.setCenterHoverRevealSuppressed === "function") {
        bar.setCenterHoverRevealSuppressed(suppressed)
        return
      }
    } catch (e) {}
    try {
      if ("centerHoverRevealSuppressed" in bar)
        bar.centerHoverRevealSuppressed = suppressed
    } catch (e) {}
  }

  function startScan() {
    var s = root.service()
    if (s) s.scan(12)
  }

  function pickDevice(row) {
    var s = root.service()
    if (s) s.pickDevice(row)
    root.settingsOpen = false
  }

  function rescan() {
    var s = root.service()
    if (s) s.forgetDevice()
    root.settingsOpen = false
    root.startScan()
  }

  function setBarDisplay(value) {
    var s = root.service()
    if (s) s.setBarDisplay(value)
  }

  Timer {
    interval: 400
    running: root.opened
    repeat: true
    onTriggered: {
      var s = root.service()
      if (s && s.reloadState) s.reloadState()
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function show(): void { root.openFromHotkey() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  AnchoredPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    edgeAlign: root.edgeAlign
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(body.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "," || t === ".") root.settingsOpen = !root.settingsOpen
        else if (t === "r" || t === "R") root.startScan()
      }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: body
          width: parent.width
          spacing: Style.space(14)

          PanelHero {
            width: parent.width
            title: root.page === "settings" ? "Settings" : "OmaWalk"
            meta: root.page === "scan"
              ? (root.scanning ? "Scanning…" : "Find treadmill")
              : (root.walking ? "Walking  ·  " + Model.formatSpeed(root.speedMph) + " mph" : (service() && service().connected ? "Connected" : "Idle"))
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Text {
              text: "󰑮"
              color: root.walking ? root.accent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
            trailingControl: Button {
              text: ""
              iconText: "󰒓"
              tooltipText: "Settings"
              bordered: true
              selected: root.settingsOpen
              foreground: root.foreground
              accent: root.accent
              onClicked: root.settingsOpen = !root.settingsOpen
            }
          }

          PanelSeparator { foreground: root.foreground }

          // ---- Scan ----
          Column {
            width: parent.width
            spacing: Style.space(12)
            visible: root.page === "scan"

            Text {
              width: parent.width
              text: "Power the Unsit on, close the phone app, stand on the belt and walk, then scan. Only one device can be connected at a time."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
              lineHeight: 1.35
            }

            Button {
              width: parent.width
              text: root.scanning ? "Scanning…" : "Scan"
              foreground: root.foreground
              accent: root.accent
              bordered: true
              enabled: !root.scanning
              onClicked: root.startScan()
            }

            Text {
              width: parent.width
              visible: root.scanError !== "" && root.scanResults.length === 0
              text: root.scanError
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Repeater {
              model: root.scanResults
              delegate: Button {
                required property var modelData
                width: body.width
                text: (modelData.name || "Unsit") + "  ·  " + modelData.address + "  (" + modelData.rssi + " dBm)"
                leftAlign: true
                bordered: true
                foreground: root.foreground
                accent: root.accent
                onClicked: root.pickDevice(modelData)
              }
            }
          }

          // ---- Graphs ----
          Column {
            width: parent.width
            spacing: Style.space(12)
            visible: root.page === "graphs"

            Row {
              width: parent.width
              spacing: Style.space(8)

              ButtonGroup {
                width: (parent.width - parent.spacing) / 2
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                value: root.range
                options: [
                  { value: "day", label: "Day" },
                  { value: "week", label: "Week" },
                  { value: "month", label: "Month" }
                ]
                onChanged: function(v) { root.range = v; root.hoverHint = "" }
              }

              ButtonGroup {
                width: (parent.width - parent.spacing) / 2
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                value: root.metric
                options: [
                  { value: "steps", label: "Steps" },
                  { value: "distance", label: "Distance" }
                ]
                onChanged: function(v) { root.metric = v; root.hoverHint = "" }
              }
            }

            Item {
              width: parent.width
              height: Style.space(160)

              Row {
                id: barRow
                anchors.fill: parent
                spacing: 4

                Repeater {
                  model: root.buckets

                  Item {
                    required property var modelData
                    required property int index
                    width: Math.max(4, (barRow.width - (root.buckets.length - 1) * barRow.spacing) / Math.max(1, root.buckets.length))
                    height: barRow.height

                    readonly property int value: root.metric === "distance" ? modelData.distanceMilli : modelData.steps
                    readonly property real ratio: root.bucketMax > 0 ? value / root.bucketMax : 0

                    Rectangle {
                      anchors.bottom: label.top
                      anchors.bottomMargin: 4
                      anchors.horizontalCenter: parent.horizontalCenter
                      width: Math.max(3, parent.width - 2)
                      height: Math.max(3, (parent.height - label.height - 6) * Math.max(0.02, ratio))
                      radius: 2
                      color: root.accent
                      opacity: value > 0 ? 1 : 0.28
                    }

                    Text {
                      id: label
                      anchors.bottom: parent.bottom
                      anchors.horizontalCenter: parent.horizontalCenter
                      width: parent.width
                      text: modelData.label
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      elide: Text.ElideRight
                      horizontalAlignment: Text.AlignHCenter
                    }

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      onEntered: {
                        var amount = root.metric === "distance"
                          ? Model.formatMiles(modelData.distanceMilli)
                          : Model.formatSteps(modelData.steps) + " steps"
                        root.hoverHint = modelData.hint + "  ·  " + amount
                      }
                      onExited: root.hoverHint = ""
                    }
                  }
                }
              }
            }

            Text {
              width: parent.width
              height: Style.space(18)
              text: root.hoverHint
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            Row {
              width: parent.width
              Text {
                width: parent.width * 0.28
                text: "Today"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Text {
                width: parent.width * 0.36
                text: Model.formatSteps(root.today.steps) + " steps"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
              Text {
                width: parent.width * 0.36
                text: Model.formatMiles(root.today.distanceMilli)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                horizontalAlignment: Text.AlignRight
              }
            }

            SpeedDial {
              width: parent.width
              height: Style.space(150)
              mph: root.walking ? root.speedMph : 0
              live: root.walking
              trackColor: Qt.rgba(root.dim.r, root.dim.g, root.dim.b, 0.45)
              fillColor: root.accent
              textColor: root.foreground
              dimColor: root.dim
              fontFamily: root.fontFamily
              textSize: Style.font.display
              labelSize: Style.font.body
            }
          }

          // ---- Settings ----
          Column {
            width: parent.width
            spacing: Style.space(14)
            visible: root.page === "settings"

            Text {
              text: "Bar"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            ButtonGroup {
              width: parent.width
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              value: pluginState.barDisplay || "none"
              options: [
                { value: "none", label: "Nothing" },
                { value: "steps", label: "Steps" },
                { value: "distance", label: "Distance" }
              ]
              onChanged: function(v) { root.setBarDisplay(v) }
            }

            PanelSeparator { foreground: root.foreground }

            Text {
              text: "Treadmill"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Text {
              width: parent.width
              text: Model.deviceLabel(pluginState)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Button {
              width: parent.width
              text: "Rescan"
              tooltipText: "Forget this treadmill and scan again"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              onClicked: root.rescan()
            }
          }
        }
      }
    }
  }
}
