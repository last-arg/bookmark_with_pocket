import asyncjs, jsffi, dom, jscore
import bookmarks

when not defined(js):
  {.error: "This module only works on the JavaScript platform".}

type
  Browser* = ref BrowserObj
  BrowserObj {.importjs.} = object
    bookmarks*: Bookmarks
    browserAction*: BrowserAction
    runtime*: Runtime
    tabs*: Tabs

  BrowserAction* = ref BrowserActionObj
  BrowserActionObj {.importjs.} = object
    onClicked*: BrowserActionClicked

  BrowserActionClicked* = ref BrowserActionClickedObj
  BrowserActionClickedObj {.importjs.} = object

  Runtime* = ref RuntimeObj
  RuntimeObj {.importjs.} = object

  Tabs* = ref TabsObj
  TabsObj {.importjs.} = object

  Tab* = ref TabObj
  TabObj {.importjs.} = object
    url*: cstring
    title*: cstring

  TabCreateProps* = ref TabCreatePropsObj
  TabCreatePropsObj = object
    url*: cstring

var browser* {.importjs, nodecl.}: Browser

{.push importcpp.}

proc create*(tabs: Tabs, props: TabCreateProps): Future[BookmarkTreeNode]
proc getURL*(runtime: Runtime, url: cstring): cstring
proc addListener*(ba: BrowserActionClicked, cb: proc(tab: Tab))

{.pop importcpp.}
