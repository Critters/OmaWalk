function qmlPath(url) {
  var s = String(url || "")
  if (s.indexOf("file://") === 0) return s.substring(7)
  return s
}

function pythonBin(home) {
  return String(home || "") + "/.local/share/omawalk/venv/bin/python"
}

function statePath(home) {
  return String(home || "") + "/.local/share/omawalk/state.json"
}

function parseJson(raw, fallback) {
  try {
    var parsed = JSON.parse(String(raw || ""))
    return parsed && typeof parsed === "object" ? parsed : fallback
  } catch (e) {
    return fallback
  }
}

function defaultState() {
  return {
    version: 1,
    barDisplay: "none",
    device: null,
    live: { connected: false, walking: false, speedMph: 0, updatedAt: "" },
    days: {}
  }
}

function normalizeState(raw) {
  var state = defaultState()
  if (!raw || typeof raw !== "object") return state
  var bar = String(raw.barDisplay || "none")
  if (bar === "steps" || bar === "distance" || bar === "none") state.barDisplay = bar
  if (raw.device && raw.device.address) {
    state.device = {
      address: String(raw.device.address),
      name: String(raw.device.name || ""),
      adapter: String(raw.device.adapter || "")
    }
  }
  var live = raw.live || {}
  state.live = {
    connected: !!live.connected,
    walking: !!live.walking,
    speedMph: Number(live.speedMph) || 0,
    updatedAt: String(live.updatedAt || "")
  }
  var days = {}
  var src = raw.days || {}
  for (var key in src) {
    if (!src[key] || typeof src[key] !== "object") continue
    days[String(key)] = {
      steps: Math.max(0, parseInt(src[key].steps, 10) || 0),
      distanceMilli: Math.max(0, parseInt(src[key].distanceMilli, 10) || 0)
    }
  }
  state.days = days
  return state
}

function pad2(n) {
  return n < 10 ? "0" + n : String(n)
}

function ymd(d) {
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
}

function startOfDay(d) {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate())
}

function addDays(d, n) {
  var x = startOfDay(d)
  x.setDate(x.getDate() + n)
  return x
}

function mondayOf(d) {
  var x = startOfDay(d)
  var back = (x.getDay() + 6) % 7
  x.setDate(x.getDate() - back)
  return x
}

function monthStart(d) {
  return new Date(d.getFullYear(), d.getMonth(), 1)
}

function addMonths(d, n) {
  return new Date(d.getFullYear(), d.getMonth() + n, 1)
}

function monthNames() {
  return ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
}

function dayTotal(days, key) {
  var row = days && days[key]
  if (!row) return { steps: 0, distanceMilli: 0 }
  return {
    steps: row.steps || 0,
    distanceMilli: row.distanceMilli || 0
  }
}

function sumRange(days, start, endInclusive) {
  var steps = 0
  var distanceMilli = 0
  var cursor = startOfDay(start)
  var last = startOfDay(endInclusive)
  while (cursor.getTime() <= last.getTime()) {
    var row = dayTotal(days, ymd(cursor))
    steps += row.steps
    distanceMilli += row.distanceMilli
    cursor = addDays(cursor, 1)
  }
  return { steps: steps, distanceMilli: distanceMilli }
}

function dayBuckets(days, now) {
  var end = startOfDay(now || new Date())
  var rows = []
  for (var i = 13; i >= 0; i--) {
    var d = addDays(end, -i)
    var tot = dayTotal(days, ymd(d))
    rows.push({
      key: ymd(d),
      label: String(d.getDate()),
      hint: d.toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" }),
      steps: tot.steps,
      distanceMilli: tot.distanceMilli
    })
  }
  return rows
}

function weekBuckets(days, now) {
  var thisMonday = mondayOf(now || new Date())
  var rows = []
  for (var i = 13; i >= 0; i--) {
    var start = addDays(thisMonday, -7 * i)
    var end = addDays(start, 6)
    var tot = sumRange(days, start, end)
    rows.push({
      key: ymd(start),
      label: String(start.getDate()) + " " + monthNames()[start.getMonth()].slice(0, 3),
      hint: start.toLocaleDateString(undefined, { month: "short", day: "numeric" })
        + " – "
        + end.toLocaleDateString(undefined, { month: "short", day: "numeric" }),
      steps: tot.steps,
      distanceMilli: tot.distanceMilli
    })
  }
  return rows
}

function monthBuckets(days, now) {
  var start = monthStart(now || new Date())
  var rows = []
  for (var i = 11; i >= 0; i--) {
    var m = addMonths(start, -i)
    var next = addMonths(m, 1)
    var end = addDays(next, -1)
    var tot = sumRange(days, m, end)
    rows.push({
      key: m.getFullYear() + "-" + pad2(m.getMonth() + 1),
      label: monthNames()[m.getMonth()],
      hint: monthNames()[m.getMonth()] + " " + m.getFullYear(),
      steps: tot.steps,
      distanceMilli: tot.distanceMilli
    })
  }
  return rows
}

function formatSteps(n) {
  var v = Math.max(0, Math.round(Number(n) || 0))
  return v.toLocaleString()
}

function formatMiles(milli) {
  var miles = Math.max(0, (Number(milli) || 0) / 1000)
  return miles.toFixed(2) + " mi"
}

function formatSpeed(mph) {
  var v = Number(mph) || 0
  if (v < 0) v = 0
  return v.toFixed(1)
}

function barChipText(state, vertical) {
  if (vertical) return "󰑮"
  var mode = state && state.barDisplay ? state.barDisplay : "none"
  var today = dayTotal(state && state.days, ymd(new Date()))
  if (mode === "steps") return "󰑮  " + formatSteps(today.steps)
  if (mode === "distance") return "󰑮  " + formatMiles(today.distanceMilli)
  return "󰑮"
}

function walking(state) {
  return !!(state && state.live && state.live.walking && state.live.connected)
}

function connected(state) {
  return !!(state && state.live && state.live.connected)
}

function deviceLabel(state) {
  if (!state || !state.device || !state.device.address) return "No device"
  var name = state.device.name || "Unsit"
  return name + "  ·  " + state.device.address
}

function parseScan(raw) {
  var parsed = parseJson(raw, null)
  if (!parsed || !parsed.devices) return []
  return parsed.devices
}
