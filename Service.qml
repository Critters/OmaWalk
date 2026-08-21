import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string pythonBin: Model.pythonBin(Quickshell.env("HOME"))
  readonly property string helper: Model.qmlPath(Qt.resolvedUrl("omawalkd.py"))
  readonly property string stateFilePath: Model.statePath(Quickshell.env("HOME"))

  property var state: Model.defaultState()
  property var scanResults: []
  property bool scanning: false
  property string scanError: ""
  property bool persisting: false

  readonly property bool hasDevice: !!(state.device && state.device.address)
  readonly property bool connected: Model.connected(state)
  readonly property bool walking: Model.walking(state)
  readonly property real speedMph: state.live ? Number(state.live.speedMph) || 0 : 0
  readonly property string barDisplay: state.barDisplay || "none"

  function loadState(raw) {
    state = Model.normalizeState(Model.parseJson(raw, null))
    persisting = false
  }

  function reloadState() {
    stateFile.reload()
  }

  function startRun() {
    if (!helper || runProc.running) return
    runProc.command = [pythonBin, helper, "run"]
    runProc.running = true
  }

  function scan(seconds) {
    if (!helper || scanProc.running) return
    scanning = true
    scanError = ""
    scanResults = []
    if (runProc.running) runProc.running = false
    scanProc.command = [pythonBin, helper, "scan", "--seconds", String(seconds || 12)]
    scanProc.running = true
  }

  function pickDevice(row) {
    if (!helper || !row || !row.address) return
    pickProc.command = [pythonBin, helper, "set-device", row.address, "--name", String(row.name || ""), "--adapter", String(row.adapter || "")]
    pickProc.running = true
  }

  function forgetDevice() {
    if (!helper) return
    forgetProc.command = [pythonBin, helper, "forget"]
    forgetProc.running = true
  }

  function setBarDisplay(value) {
    if (!helper) return
    barProc.command = [pythonBin, helper, "set-bar", String(value)]
    barProc.running = true
  }

  FileView {
    id: stateFile
    path: root.stateFilePath
    watchChanges: true
    printErrors: false
    onFileChanged: if (!root.persisting) reload()
    onLoaded: root.loadState(text())
    onLoadFailed: root.loadState("")
  }

  function onHelperLine(line) {
    var ev = Model.parseJson(line, null)
    if (!ev || !ev.event) return
    if (ev.event === "packet" || ev.event === "connected" || ev.event === "disconnected")
      stateFile.reload()
  }

  Process {
    id: runProc
    stdout: SplitParser {
      onRead: function(line) { root.onHelperLine(line) }
    }
    stderr: SplitParser {
      onRead: function(line) { console.log("omawalkd:", line) }
    }
    onExited: function() {
      runRestart.restart()
    }
  }

  Timer {
    id: runRestart
    interval: 1500
    onTriggered: {
      if (!root.scanProcRunning)
        root.startRun()
    }
  }

  readonly property bool scanProcRunning: scanProc.running

  Process {
    id: scanProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.scanResults = Model.parseScan(text)
        if (root.scanResults.length === 0)
          root.scanError = "No treadmill found. Walk, close the phone app, and try again."
      }
    }
    stderr: SplitParser {
      onRead: function(line) { console.log("omawalk scan:", line) }
    }
    onExited: function() {
      root.scanning = false
      root.startRun()
    }
  }

  Process {
    id: pickProc
    stdout: StdioCollector { waitForEnd: true }
    onExited: function() {
      stateFile.reload()
      root.startRun()
    }
  }

  Process {
    id: forgetProc
    stdout: StdioCollector { waitForEnd: true }
    onExited: function() {
      root.scanResults = []
      root.scanError = ""
      stateFile.reload()
    }
  }

  Process {
    id: barProc
    stdout: StdioCollector { waitForEnd: true }
    onExited: function() { stateFile.reload() }
  }

  Component.onCompleted: {
    console.log("omawalk service 0.1.0")
    stateFile.reload()
    startRun()
  }
}
