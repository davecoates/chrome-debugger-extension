# Track which tabs are attached
attachedTabs = {}
VERSION = "1.0"

LT =
  host: "http://localhost"
  port: null
  socket: null
window.LT = LT

chrome.runtime.onConnect.addListener (port) ->
  if port.name == "lttools"
    port.onMessage.addListener (msg) ->
      console.log msg
      LT.socket.emit "result", [undefined, "clients.raise-on-object", msg.data]

# Does object script match filename. Checks for matching javascript files or
# original source file (eg. coffeescript). Only matches on filename - further
# path checks are done below to correctly identify the file.
isScriptMatch = (script, filename) ->
  # Don't match scripts that have been flagged as old even if source matches
  return false if script.filename.match /\(old\)$/

  script.filename == filename || filename in script.sources

  
# Handle JS eval
# TODO: Refactor LT specific messages out. They can be handled on LT's end with
# new client
evalJs = (target, message) ->
  {tabId} = target
  [client, command, {name, path, pos, code, meta}] = message
  filename = name?.toLowerCase()
  tabScripts = attachedTabs[tabId].scripts

  scripts = (s for s in tabScripts when isScriptMatch s, filename)
  matchingScript = scripts[0] if scripts.length > 0
  
  if scripts.length > 1
    # Get script that is closest match by comparing directory structure
    parts = path.toLowerCase().replace("/#{filename}", '').split('/').reverse()
    highest = -1
    for script in scripts
      length = 0
      for str, i in script.directory.replace(/\/$/, '').split('/').reverse()
        if str != parts[i] then break else length = length + 1
      if length > highest
        highest = length
        matchingScript = script
    
  # TODO: Handle inserting new scripts
  cb = (data) ->
    data or = {}
    {result} = data
    meta or= {}
    meta.type = result?.type

    if data.wasThrown
      command = "editor.eval.js.exception"
      returnData =
        ex: result?.description
        meta: meta
    else
      # TODO: If we have objectId we should be able to then do
      # Runtime.getProperties if required to inspect object
      command = "editor.eval.js.result"
      returnData =
        result: JSON.stringify(result?.value)
        meta: meta
        "no-inspect": true
    LT.socket.emit "result", [client, command, returnData]

  if meta || not matchingScript
    # Evaluate single expression
    command = "Runtime.evaluate"
    params =
      expression: code
      returnByValue: true
  else
    # Evaluate full file
    command = "Debugger.setScriptSource"
    params =
      scriptId: matchingScript.scriptId
      scriptSource: code
  chrome.debugger.sendCommand target, command, params, cb


# Setup socket and trigger callback when connected
# If socket is already connected triggers callback straight away
initSocket = (target, cb) ->
  if LT.socket?.socket?.connected
    cb()
  else if LT.socket
    LT.socket.socket.options.port = LT.port.toString()
    LT.socket.socket.reconnect()
  else
    LT.socket = socket = io.connect(LT.host + ':' + LT.port.toString())

    errorCb = ->
      LT.port = null
      alert("Could not connect - do you have the right port?")
    socket.on "connect_failed", errorCb
    socket.on "error", errorCb

    socket.on "client.close", -> socket.disconnect()
    socket.on "disconnect", ->
      console.log "disconnect"
      detach {tabId: parseInt(tabId)} for tabId, _ of attachedTabs
    socket.on "reconnect", -> console.log "io.reconnect"
    socket.on "reconnecting", -> console.log "io.reconnecting"
    socket.on "reconnect_failed", -> console.log "io.reconnect_failed"

    socket.on "editor.eval.js", (message) -> evalJs target, message

    onConnect = ->
      cb()
      socket.emit "init", {
      name: window.location.host || window.title || window.location.href
      types: ["js", "css", "html"],
      commands: ["editor.eval.js",
                 "editor.eval.cljs.exec",
                 "editor.eval.html",
                 "editor.eval.css"]
      }

    socket.on "connect", onConnect



# Called when debugger has attached to target
onAttach = (target) ->
  {tabId} = target
  chrome.browserAction.setIcon tabId: tabId, path: "connected.png"
  chrome.browserAction.setTitle tabId: tabId, title:"Disconnect from LT"

  # Inject our tools used for src watching
  chrome.tabs.executeScript(null, {file: "lttools.js"})


# Detach a tab from the debugger
detach = (target) ->
  if LT.socket
    LT.socket.disconnect()
  chrome.debugger.detach target, -> onDetach(target)


# Attach a tab to the debugger
attach = (target) ->
  attachedTabs[target.tabId] or=
    scripts: []
    # This just tracks the id's for each script in scripts - easy lookup
    scriptIds: []

  attachedTabs[target.tabId].status = "attaching"

  chrome.debugger.attach target, VERSION, -> onAttach(target)

  chrome.debugger.sendCommand target, "Console.enable", {}
  chrome.debugger.sendCommand target, "Runtime.enable", {}, ->
    null
    ### Prototype for angularjs watcheres
    chrome.debugger.sendCommand target, "Runtime.evaluate", {
      expression: """window.lttools = {
          watch: function(data) {
            var opts, parts, scopeName;
            console.log(this);
            parts = data.expression.split(".");
            scopeName = parts.shift();
            opts = data.opts;
            this.$watch(parts.join('.'), function (a) { console.log(a); window.postMessage({action: 'lttools.watch', params: { expression: a, opts: opts}}, '*'); }, true);
          }
        };
    """
    }
    ###

  onDebuggerEnabled = -> attachedTabs[target.tabId].status = "enabled"
  chrome.debugger.sendCommand target, "Debugger.enable", {}, onDebuggerEnabled

# Fetch a URL using XHR
getFile = (url, listener) ->
  oReq = new XMLHttpRequest()
  oReq.onload = listener
  oReq.open "get", url, true
  oReq.send()

# Listen for clicks on our icon
chrome.browserAction.onClicked.addListener (tab) ->
  if not LT.port or LT.socket?.socket?.reconnecting
    LT.port = prompt "WebSocket Port (in LT Add Connection -> Ports): ", LT.port
  target = tabId: tab.id

  onInit = () ->
    status = attachedTabs[target.tabId]?.status

    return if status == "attaching"

    if status == "enabled" then detach(target) else attach(target)

  initSocket(target, onInit)



# Called when debugger is detached from target
onDetach = (target) ->
  {tabId} = target
  attachedTabs[tabId].status = "detached"
  chrome.browserAction.setIcon tabId: tabId, path: "disconnected.png"
  chrome.browserAction.setTitle tabId: tabId, title: "Connect to LT"


# Record each script that is parsed
onScriptParsed = (target, params) ->
  {tabId} = target
  {isContentScript, scriptId, url, sourceMapURL} = params

  # Ignore content scripts (extensions etc) or already parsed scripts
  return if isContentScript

  path = url
  if matches = url.match /(http(s)?:\/\/([^/]*\/)|file:\/\/)(.*$)/
    [_, _, _, hostname, path] = matches

  parts = url.split('/')
  filename = parts.pop().toLowerCase()
  baseUrl = parts.join('/')
  scriptData =
    path: path
    directory: path.toLowerCase().replace filename, ''
    filename: filename
    scriptId: scriptId
    url: url
    sources: []

  matchingScriptId = script.scriptId for script in scriptData when script.scriptId is scriptId

  if sourceMapURL
    getFile baseUrl+'/'+sourceMapURL, ->
      return if this.status != 200

      try
        sourceMap = JSON.parse this.response
        scriptData.sources = sourceMap.sources
      catch e
        console.log("Failed to parse source map", e)

  attachedTabs[tabId].scripts.push scriptData
  attachedTabs[tabId].scriptIds.push scriptId


# Reset a target. We do this when page reloads etc.
resetTarget = (target) ->
  # We need to clear all scripts for this target so we can re parse them. This
  # avoids having stale cache due to refresh
  attachedTabs[target.tabId].scripts = []
  attachedTabs[target.tabId].scriptIds = []


# Handle events
onEvent = (target, method, params) ->
  switch method
    when "Debugger.scriptParsed" then onScriptParsed target, params
    when "Debugger.globalObjectCleared" then resetTarget target
    when "Console.messageAdded" then null
    else console.log method


# Setup our listeners
chrome.debugger.onEvent.addListener onEvent
chrome.debugger.onDetach.addListener onDetach
