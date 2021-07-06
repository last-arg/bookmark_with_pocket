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

  BadgeText* = ref BadgeTextObj
  BadgeTextObj = object
    text*: cstring
    tabId*: int

  BadgeBgColor* = ref BadgeBgColorObj
  BadgeBgColorObj = object
    color*: cstring
    tabId*: int

  BadgeTextColor* = ref BadgeTextColorObj
  BadgeTextColorObj = object
    color*: cstring
    tabId*: int

  PortEvent = ref object


var browser* {.importjs, nodecl.}: Browser

{.push importcpp.}

proc create*(tabs: Tabs, props: TabCreateProps): Future[BookmarkTreeNode]

proc getCurrent*(tabs: Tabs): Future[Tab]
proc query*(tabs: Tabs, query_obj: JsObject): Future[seq[Tab]]
proc reload*(tabs: Tabs, id: int, props: JsObject): Future[void]

proc getURL*(runtime: Runtime, url: cstring): cstring
proc addListener*(ba: BrowserActionClicked, cb: proc(tab: Tab))

proc setIcon*(ba: BrowserAction, details: JsObject): Future[void]
proc setBadgeText*(ba: BrowserAction, details: BadgeText)
proc setBadgeBackgroundColor*(ba: BrowserAction, details: BadgeBgColor)
proc setBadgeTextColor*(ba: BrowserAction, details: BadgeTextColor)

proc set*(storage_type: Local, keys: JsObject): Future[jsUndefined]
proc get*(storage_type: Local, keys: JsObject | cstring | seq[cstring]): Future[
    JsObject] # Can return undefined
proc get*(storage_type: Local): Future[JsObject] # Can return undefined
proc clear*(storage_type: Local): Future[void]

proc addListener*(obj: StorageOnChanged, cb: proc(changes: JsObject,
    area_name: cstring))

proc addListener*(r: RuntimeOnInstalled, cb: proc(details: InstalledDetails))
proc sendMessage*(r: Runtime, obj: JsObject | cstring): Future[JsObject]
proc sendMessage*(r: Runtime, id: cstring, obj: JsObject | cstring): Future[JsObject]
proc addListener*(r: RuntimeOnMessage, cb: proc(msg: JsObject, sender: JsObject,
    cb: proc(msg: Future[JsObject])))
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


