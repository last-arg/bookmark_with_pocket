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
  RuntimeOnInstalled* = ref object

  Runtime* = ref RuntimeObj
  RuntimeObj {.importjs.} = object
    onMessage*: RuntimeOnMessage
    onInstalled*: RuntimeOnInstalled

  InstalledDetails* = ref InstalledDetailsObj
  InstalledDetailsObj {.importjs.} = object
    id*: cstring              # Optional
    previousVersion*: cstring # Optional
    reason*: cstring # "install" | "update" | "browser_update" | "shared_module_update"
    temporary*: bool

  Tabs* = ref TabsObj
  TabsObj {.importjs.} = object

  Tab* = ref TabObj
  TabObj {.importjs.} = object
    id*: int
    url*: cstring
    title*: cstring

  TabCreateProps* = ref TabCreatePropsObj
  TabCreatePropsObj = object
    active*: bool
    url*: cstring

  TabQuery* = ref TabQueryObj
  TabQueryObj = object
    active*: bool
    currentWindow*: bool
    url*: cstring

  Port* = ref PortObj
  PortObj {.importjs.} = object
    onMessage*: PortEvent
    onDisconnect*: PortEvent

  PortEvent = ref object


var browser* {.importjs, nodecl.}: Browser

{.push importcpp.}

proc create*(tabs: Tabs, props: TabCreateProps): Future[BookmarkTreeNode]

proc getCurrent*(tabs: Tabs): Future[Tab]
proc query*(tabs: Tabs, query_obj: JsObject): Future[seq[Tab]]
proc reload*(tabs: Tabs, id: int, props: JsObject): Future[void]

proc getURL*(runtime: Runtime, url: cstring): cstring
proc addListener*(ba: BrowserActionClicked, cb: proc(tab: Tab))
proc removeListener*(ba: BrowserActionClicked, cb: proc(tab: Tab))

proc setIcon*(ba: BrowserAction, details: JsObject): Future[void]
proc setTitle*(ba: BrowserAction, details: JsObject)
proc setBadgeText*(ba: BrowserAction, details: JsObject)
proc setBadgeBackgroundColor*(ba: BrowserAction, details: JsObject)
proc setBadgeTextColor*(ba: BrowserAction, details: JsObject)

proc set*(storage_type: Local, keys: JsObject): Future[jsUndefined]
proc get*(storage_type: Local, keys: JsObject | cstring | seq[cstring]): Future[
    JsObject] # Can return undefined
proc remove*(storage_type: Local, keys: cstring | seq[cstring]): Future[JsObject]
proc get*(storage_type: Local): Future[JsObject] # Can return undefined
proc clear*(storage_type: Local): Future[void]

proc addListener*(obj: StorageOnChanged, cb: proc(changes: JsObject,
    area_name: cstring))

proc addListener*(r: RuntimeOnInstalled, cb: proc(details: InstalledDetails))
proc addListener*(r: RuntimeOnMessage, cb: proc(msg: cstring))
proc removeListener*(r: RuntimeOnMessage, cb: proc(msg: cstring))
proc sendMessage*(r: Runtime, message: cstring): Future[JsObject]

proc openOptionsPage*(r: Runtime): Future[void]

proc addListener*(obj: PortEvent, cb: proc(resp: JsObject))
proc removeListener*(obj: PortEvent, cb: proc(resp: JsObject))
proc disconnect*(port: Port)
proc connectNative*(r: Runtime, app: cstring): Port
proc postMessage(port: Port, msg: cstring)

{.pop importcpp.}


# Wrapper for postMessage function
proc sendPortMessage*(port: Port, msg: cstring): Future[JsObject] =
  var promise = newPromise(proc(resolve: proc(resp: JsObject)) =
    proc success(resp: JsObject)
    proc failure(resp: JsObject)

    proc success(resp: JsObject) =
      port.onMessage.removeListener(success)
      port.onDisconnect.removeListener(failure)
      resolve(resp)

    proc failure(resp: JsObject) =
      port.onMessage.removeListener(success)
      port.onDisconnect.removeListener(failure)
      resolve(nil)

    port.onMessage.addListener(success)
    port.onDisconnect.addListener(failure)
  )
  port.postMessage(msg)
  return promise


