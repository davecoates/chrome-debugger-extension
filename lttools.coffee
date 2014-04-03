port = chrome.runtime.connect({name: "lttools"})

# Taken from LightTable ws.js
cache = []
replacer = (key, value) ->
  return if cache.length > 20

  if window.jQuery and value instanceof jQuery
    return "[jQuery $(" + value.selector + ")]"
  
  if value instanceof Element
    return "[Element " + value.tagName.toLowerCase() + (value.id != "" ? "#" : "") + value.id + "]"

  if typeof(value) == "object"
    if cache.indexOf(value) > -1
      return "circular"
    cache.push(value)
    return value

  if typeof value == "function"
    return "[function]"
  return value

safeStringify = (res) ->
  cache = []
  return JSON.stringify(res, replacer)

window.addEventListener "message", (event) ->
  console.log event
  {data: {action, params}} = event
  if action == "lttools.watch"
    meta = params.opts
    {expression, opts: {ev, id, obj}} = params
    if ev == "editor.eval.cljs.watch"
      final = cljs.core.pr_str(expression)
    else
      meta["no-inspect"] = true
      final = safeStringify(expression)
    console.log "result", final
    console.log "lol"
    port.postMessage { data: [obj, ev, {result: final, meta: meta}]}
