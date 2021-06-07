import asyncjs, jsffi
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
    storage*: Storage

  Local* = ref object
  StorageOnChanged* = ref object

  Storage* = ref StorageObj
  StorageObj {.importjs.} = object
    local*: Local
    onChanged*: StorageOnChanged

  BrowserAction* = ref BrowserActionObj
  BrowserActionObj {.importjs.} = object
    onClicked*: BrowserActionClicked

  BrowserActionClicked* = ref BrowserActionClickedObj
  BrowserActionClickedObj {.importjs.} = object

  RuntimeOnMessage* = ref object

  Runtime* = ref RuntimeObj
  RuntimeObj {.importjs.} = object
    onMessage*: RuntimeOnMessage

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

proc set*(storage_type: Local, keys: JsObject): Future[jsUndefined]
proc get*(storage_type: Local, keys: JsObject | cstring | seq[cstring]): Future[
    JsObject] # Can return undefined
proc clear*(storage_type: Local): Future[void]

proc addListener*(obj: StorageOnChanged, cb: proc(changes: JsObject,
    area_name: cstring))

proc sendMessage*(r: Runtime, obj: JsObject | cstring): Future[JsObject]
proc sendMessage*(r: Runtime, id: cstring, obj: JsObject | cstring): Future[JsObject]
proc addListener*(r: RuntimeOnMessage, cb: proc(msg: JsObject, sender: JsObject,
    cb: proc(msg: Future[JsObject])))

{.pop importcpp.}
