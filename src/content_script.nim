import dom, web_ext_browser
import jsconsole

console.log "CONTENT SCRIPT"
document.addEventListener("keydown", proc(event: KeyboardEvent) =
  console.log "content_script keydown"
  if event.ctrlKey and event.key == "d":
    console.log "content_script tag update"
    discard browser.runtime.sendMessage("update_tags".cstring)
  )
