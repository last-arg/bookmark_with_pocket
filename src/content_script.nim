import dom, web_ext_browser, common
import jsconsole

console.log "status", g_status
document.addEventListener("keydown", proc(event: KeyboardEvent) =
  console.log "content_script keydown"
  if event.ctrlKey and event.key == "d":
    console.log "content_script tag update"
    discard browser.runtime.sendMessage("update_tags".cstring)
  )
