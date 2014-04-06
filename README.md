Chrome Debugger Extension
=========================

Chrome extension to facilitate remote debugging (currently only from LightTable).

Clone this repo and then visit chrome://extensions/ in chrome and click 'Load unpacked extension'.

To connect to LightTable click the LT icon and then enter the WebSockets port for LightTable (get this from  Add Connection -> Ports).

The main purpose of this is to use [setScriptSource](https://developers.google.com/chrome-developer-tools/docs/protocol/1.1/debugger?hl=ro#command-setScriptSource) where possible rather than doing a window.eval which is what the current LightTable remote browser option does. I'm not sure about the built in browser... it looks like it will sometimes use setScriptSource but haven't looked into it further. I prefer having the browser window separate to the editor when using multiple monitors.

Javascript watchers don't currently work, [CoffeeScript](https://github.com/davecoates/lt-coffeescript) ones do (though sometimes it crashes the tab :). I'll be changing how these work soon.

It's probably pretty buggy right now and my testing thus far has been contrived and not much on real projects - beware!
