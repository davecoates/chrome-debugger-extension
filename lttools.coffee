port = chrome.runtime.connect({name: "lttools"})

window.addEventListener "message", (event) ->
  console.log "Message!", event
  {data: {action, params}} = event
  if action == "lttools.watch"
    console.log "post message!!"
    port.postMessage { data: params}
