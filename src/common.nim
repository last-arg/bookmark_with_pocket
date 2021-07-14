import jsffi, asyncjs
import jsconsole
import web_ext_browser, bookmarks, app_config, app_js_ffi, pocket
import results, options, tables

# TODO?: move state machine to background.nim?
type
  StateCb = proc(): void
  Transition = tuple[next: State, cb: Option[StateCb]]
  StateEvent = tuple[state: State, event: Event]
  Machine* = ref object of RootObj
    currentState: State
    data: StateData
    transitions: TableRef[StateEvent, Transition]

  State* = enum
    InitialLoad
    LoggedIn
    LoggedOut

  Event* = enum
    Login
    Logout

proc newMachine*(currentState = InitialLoad, data = newStateData(),
    transitions = newTable[StateEvent, Transition]()): Machine =
  Machine(currentState: currentState, data: data, transitions: transitions)

proc addTransition*(m: Machine, state: State, event: Event, next: State,
    cb: Option[StateCb] = none[StateCb]()) =
  m.transitions[(state, event)] = (next, cb)

proc getTransition*(m: Machine, s: State, e: Event): Transition =
  let key = (s, e)
  if m.transitions.hasKey(key):
    return m.transitions[key]
  else: console.error "Transition is not defined: Event(" & $e & ") State(" & $s & ")"

proc transition*(m: Machine, event: Event) =
  let t = m.getTransition(m.currentState, event)
  if t.cb.isSome():
    t.cb.unsafeGet()()
  m.currentState = t.next

# TODO: Try to move this to background.nim
var g_status*: StateData = nil
  # TODO: try improve testing code
  # Try to remove global variables like 'pocket_link'
when defined(testing):
  var pocket_link*: JsObject = nil

let badge_empty = newJsObject()
badge_empty["path"] = "./assets/badge_empty.svg".cstring

let badge_grayscale = newJsObject()
badge_grayscale["path"] = "./assets/badge_grayscale.svg".cstring

let badge = newJsObject()
badge["path"] = "./assets/badge.svg".cstring

proc setBadgeLoading*(tab_id: int) =
  let bg_color = newJsObject()
  bg_color["color"] = "#BFDBFE".cstring
  bg_color["tab_id"] = tab_id
  browser.browserAction.setBadgeBackgroundColor(bg_color)
  let text_color = newJsObject()
  text_color["color"] = "#000000".cstring
  text_color["tab_id"] = tab_id
  browser.browserAction.setBadgeTextColor(text_color)
  let b_text = newJsObject()
  b_text["text"] = "...".cstring
  b_text["tab_id"] = tab_id
  browser.browserAction.setBadgeText(b_text)

proc setBadgeFailed*(tab_id: int) =
  let bg_color = newJsObject()
  bg_color["color"] = "#FCA5A5".cstring
  bg_color["tab_id"] = tab_id
  browser.browserAction.setBadgeBackgroundColor(bg_color)
  let text_color = newJsObject()
  text_color["color"] = "#000000".cstring
  text_color["tab_id"] = tab_id
  browser.browserAction.setBadgeTextColor(text_color)
  let b_text = newJsObject()
  b_text["text"] = "fail".cstring
  b_text["tab_id"] = tab_id
  browser.browserAction.setBadgeText(b_text)

proc setBadgeNone*(tab_id: Option[int]) =
  let b_text = newJsObject()
  b_text["text"] = "".cstring
  if isSome(tab_id): b_text["tab_id"] = tab_id.unsafeGet()
  browser.browserAction.setBadgeText(b_text)
  let d = newJsObject()
  d["title"] = jsNull
  browser.browserAction.setTitle(d)
  discard browser.browserAction.setIcon(badge_empty)

proc setBadgeSuccess*(tab_id: int) =
  let b_text = newJsObject()
  b_text["text"] = "".cstring
  b_text["tab_id"] = tab_id
  browser.browserAction.setBadgeText(b_text)
  badge["tabId"] = tab_id
  discard browser.browserAction.setIcon(badge)

proc setBadgeNotLoggedIn*(text: cstring = "") =
  let bg_color = newJsObject()
  bg_color["color"] = "#FCA5A5".cstring
  browser.browserAction.setBadgeBackgroundColor(bg_color)
  let text_color = newJsObject()
  text_color["color"] = "#000000".cstring
  browser.browserAction.setBadgeTextColor(text_color)
  let text_detail = newJsObject()
  text_detail["text"] = text
  browser.browserAction.setBadgeText(text_detail)
  let ba_details = newJsObject()
  ba_details["title"] = "Click to login to Pocket".cstring
  browser.browserAction.setTitle(ba_details)
  discard browser.browserAction.setIcon(badge_grayscale)

proc getCurrentTabId*(): Future[int] {.async.} =
  let query_opts = newJsObject()
  query_opts["active"] = true
  query_opts["currentWindow"] = true
  let query_tabs = await browser.tabs.query(query_opts)
  return query_tabs[0].id


proc updateTagDates*(tags: seq[BookmarkTreeNode]): seq[cstring] =
  var r: seq[cstring] = @[]
  for tag in tags:
    let id_index = find[seq[cstring], cstring](g_status.tag_ids, tag.id)
    if id_index == -1:
      let tag_info = TagInfo(modified: tag.dateGroupModified,
          title: tag.title)
      r.add(tag.title)
      g_status.tag_ids.add(tag.id)
      g_status.tags.add(tag_info)
      continue

    if tag.dateGroupModified != g_status.tags[id_index].modified:
      r.add(tag.title)
      g_status.tags[id_index] = TagInfo(modified: tag.dateGroupModified,
          title: tag.title)

  return r

proc asyncUpdateTagDates*(): Future[jsUndefined] {.async.} =
  let tags = await browser.bookmarks.getChildren(tags_folder_id)
  discard updateTagDates(tags)

proc filterTags*(tags: seq[cstring], allowed_tags, discard_tags: seq[
    seq[cstring]]): seq[cstring] =
  var new_tags = newSeq[cstring]()

  if allowed_tags.len > 0:
    for row in allowed_tags:
      var has_tags = true
      for item in row:
        has_tags = has_tags and (item in tags)
      if has_tags: new_tags.add(row)
  elif discard_tags.len > 0:
    var rem_tags = newSeq[cstring]()
    for row in discard_tags:
      var has_tags = true
      for item in row:
        has_tags = has_tags and (item in tags)
      if has_tags: rem_tags.add(row)
    new_tags = filter(tags, proc(item: cstring): bool = item notin rem_tags)
  return new_tags

proc hasNoAddTag*(tags: seq[cstring], no_add_tags: seq[seq[cstring]]): bool =
  for row in no_add_tags:
    var no_add = true
    for item in row:
      no_add = no_add and tags.contains(item)
    if no_add: return true
  return false

proc hasAddTag*(tags: seq[cstring], add_tags: seq[seq[cstring]]): bool =
  for row in add_tags:
    var add = true
    for item in row:
      add = add and tags.contains(item)
    if add: return true
  return false


proc onCreateBookmark*(bookmark: BookmarkTreeNode) {.async.} =
  if bookmark.`type` != "bookmark": return
  let query_opts = newJsObject()
  query_opts["active"] = true
  query_opts["currentWindow"] = true
  let query_tabs = await browser.tabs.query(query_opts)
  let tab_id = query_tabs[0].id
  setBadgeNone(some(tab_id))

  let tags = await browser.bookmarks.getChildren(tags_folder_id)
  let added_tags = updateTagDates(tags)

  if hasNoAddTag(added_tags, g_status.config.no_add_tags):
    return

  if g_status.config.always_add_tags or hasAddTag(added_tags,
      g_status.config.add_tags):
    setBadgeLoading(tab_id)
    let filtered_tags = filterTags(added_tags, g_status.config.allowed_tags,
        g_status.config.discard_tags)
    let link_result = await addLink(bookmark.url,
        g_status.config.access_token, filtered_tags)
    if link_result.isErr():
      console.error "Failed to add bookmark to Pocket. Error type: " &
          $link_result.error()
      setBadgeFailed(tab_id)
      return

    setBadgeSuccess(tab_id)

    when defined(testing):
      pocket_link = link_result.value()

proc onUpdateTagsEvent(id: cstring, obj: JsObject) = discard asyncUpdateTagDates()
proc onOpenOptionPageEvent(_: Tab) = discard browser.runtime.openOptionsPage()
proc onCreateBookmarkEvent(_: cstring, bookmark: BookmarkTreeNode) = discard onCreateBookmark(bookmark)

proc onMessageCommand*(msg: cstring)
proc deinitLoggedIn*() =
  browser.browserAction.onClicked.removeListener(onOpenOptionPageEvent)
  browser.bookmarks.onCreated.removeListener(onCreateBookmarkEvent)
  browser.bookmarks.onChanged.removeListener(onUpdateTagsEvent)
  browser.bookmarks.onRemoved.removeListener(onUpdateTagsEvent)

proc initLoggedIn*() =
  setBadgeNone(none[int]())
  discard asyncUpdateTagDates()
  browser.browserAction.onClicked.addListener(onOpenOptionPageEvent)
  browser.bookmarks.onCreated.addListener(onCreateBookmarkEvent)
  browser.bookmarks.onChanged.addListener(onUpdateTagsEvent)
  browser.bookmarks.onRemoved.addListener(onUpdateTagsEvent)

proc deinitLoggedOut*()
proc badgePocketLogin(id: int) {.async.} =
  let body_result = await authenticate()
  if body_result.isErr():
    console.error("Pocket authentication failed")
    setBadgeNotLoggedIn("fail".cstring)
    return
  # Deconstruct urlencoded data
  let kvs = body_result.value.split("&")
  var login_data = newJsObject()
  const username = "username"
  const access_token = "access_token"
  login_data[access_token] = nil
  login_data[username] = nil
  for kv_str in kvs:
    let kv = kv_str.split("=")
    if kv[0] == access_token:
      login_data[access_token] = kv[1]
    elif kv[0] == username:
      login_data[username] = kv[1]

  if login_data[access_token] == nil:
    console.error("Failed to get access_token form Pocket API response")
    setBadgeNotLoggedIn("fail".cstring)
    return

  discard await browser.storage.local.set(login_data)
  deinitLoggedOut()
  initLoggedIn()

proc clickPocketLoginEvent(tab: Tab) =
  discard badgePocketLogin(tab.id)

proc initLoggedOut*() =
  setBadgeNotLoggedIn()
  browser.browserAction.onClicked.addListener(clickPocketLoginEvent)

proc deinitLoggedOut*() =
  browser.browserAction.onClicked.removeListener(clickPocketLoginEvent)

proc onMessageCommand*(msg: cstring) =
  console.log "command"
  if msg == "update_tags":
    discard asyncUpdateTagDates()
  elif msg == "login":
    deinitLoggedOut()
    initLoggedIn()
  elif msg == "logout":
    deinitLoggedIn()
    initLoggedOut()
