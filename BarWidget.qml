import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "omawalk"

  readonly property var omawalk: bar && bar.shell && bar.shell.serviceFor
    ? bar.shell.serviceFor("omawalk") : null

  readonly property string barSection: {
    var b = root.bar
    if (!b || !b.moduleSlots) return "right"
    for (var i = 0; i < b.moduleSlots.length; i++) {
      var slot = b.moduleSlots[i]
      if (slot && slot.activeItem === root && slot.region)
        return slot.region
    }
    return "right"
  }

  readonly property string edgeAlign: {
    if (root.barSection === "left") return "start"
    if (root.barSection === "center") return "center"
    return "end"
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
    target.omawalk = root.omawalk
    target.edgeAlign = root.edgeAlign
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  readonly property var pluginState: omawalk ? omawalk.state : Model.defaultState()
  readonly property bool walking: omawalk ? omawalk.walking : false
  readonly property string chipText: Model.barChipText(pluginState, root.vertical)

  function open() {
    root.injectPanel()
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onOmawalkChanged: injectPanel()
  onEdgeAlignChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.chipText
    labelVisible: true
    hasVisualContent: true
    horizontalMargin: root.vertical ? 8.5 : (pluginState.barDisplay === "none" ? 8.5 : 10)
    active: root.walking
    activeColor: Color.accent
    dimmed: !root.walking
    tooltipText: root.walking ? "Walking" : (omawalk && omawalk.connected ? "Connected" : "OmaWalk")
    onPressed: function(b) { root.toggle() }
  }
}
