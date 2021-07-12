import dom, web_ext_browser

document.addEventListener("keydown", proc(event: KeyboardEvent) =
  if event.ctrlKey and event.key == "d":
    discard browser.runtime.sendMessage("update_tags".cstring)
  )
