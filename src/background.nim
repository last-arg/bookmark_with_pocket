import dom, jsffi, asyncjs
import jsconsole

type
  BrowserAction = ref BrowserActionObj
  BrowserActionObj = object of JsObject

  Tab* = ref TabObj
  TabObj {.importc.} = object of RootObj
    url*: cstring
    title*: cstring

var browserAction* {.importcpp: "browser.browserAction", nodecl.}: BrowserAction
proc onClicked*(ba: BrowserAction, cb: proc(tab: Tab)) {.
    importcpp: "#.onClicked.addListener(#)".}

proc getURL*(path: cstring = ""): cstring {.
    importcpp: "browser.extension.getURL(#)".}

proc tabsCreate*(path: JsObject): Future[Tab] {.
    importcpp: "browser.tabs.create(#)".}

proc init() =
  browserAction.onClicked(proc(tab: Tab) =
    var tabs_options = newJsObject()
    tabs_options["url"] = getURL("index.html")
    discard tabsCreate(tabs_options)
  )

when isMainModule:
  console.log "main: background.js"
  document.addEventListener("DOMContentLoaded", proc(_: Event) = init())
