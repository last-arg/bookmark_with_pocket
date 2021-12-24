import dom, web_ext_browser, jsffi
import jsconsole

document.addEventListener("keydown", proc(tmp_event: Event) =
  let event = cast[KeyboardEvent](tmp_event)
  if event.ctrlKey and event.key == "d":
    let msg = newJsObject()
    msg["cmd"] = cstring "update_tags"
    discard browser.runtime.sendMessage(msg)
  )
