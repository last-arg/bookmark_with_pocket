import jsffi, asyncjs
import jsconsole
import web_ext_browser, bookmarks, app_config, app_js_ffi, pocket
import results

var status* = newStatus()
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
  browser.browserAction.setBadgeBackgroundColor(
    BadgeBgColor(color: "#BFDBFE", tabId: tab_id))
  browser.browserAction.setBadgeTextColor(
    BadgeTextColor(color: "#000000", tabId: tab_id))
  browser.browserAction.setBadgeText(BadgeText(text: "...", tabId: tab_id))

proc setBadgeFailed*(tab_id: int) =
  browser.browserAction.setBadgeBackgroundColor(
    BadgeBgColor(color: "#FCA5A5", tabId: tab_id))
  browser.browserAction.setBadgeTextColor(
    BadgeTextColor(color: "#000000", tabId: tab_id))
  browser.browserAction.setBadgeText(BadgeText(text: "fail", tabId: tab_id))

proc setBadgeNone*(tab_id: int) =
  let text_detail = BadgeText(text: "", tabId: tab_id)
  browser.browserAction.setBadgeText(text_detail)
  badge["tabId"] = tab_id
  let d = newJsObject()
  d["title"] = jsNull
  browser.browserAction.setTitle(d)
  discard browser.browserAction.setIcon(badge_empty)

proc setBadgeSuccess*(tab_id: int) =
  let text_detail = BadgeText(text: "", tabId: tab_id)
  browser.browserAction.setBadgeText(text_detail)
  badge["tabId"] = tab_id
  discard browser.browserAction.setIcon(badge)

proc setBadgeNotLoggedIn*(tab_id: int, text: cstring = "") =
  browser.browserAction.setBadgeBackgroundColor(
    BadgeBgColor(color: "#FCA5A5", tabId: tab_id))
  browser.browserAction.setBadgeTextColor(
    BadgeTextColor(color: "#000000", tabId: tab_id))
  let text_detail = BadgeText(text: text, tabId: tab_id)
  browser.browserAction.setBadgeText(text_detail)
  badge["tabId"] = tab_id
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
    let id_index = find[seq[cstring], cstring](status.tag_ids, tag.id)
    if id_index == -1:
      let tag_info = TagInfo(modified: tag.dateGroupModified,
          title: tag.title)
      r.add(tag.title)
      status.tag_ids.add(tag.id)
      status.tags.add(tag_info)
      continue

    if tag.dateGroupModified != status.tags[id_index].modified:
      r.add(tag.title)
      status.tags[id_index] = TagInfo(modified: tag.dateGroupModified,
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
  setBadgeNone(tab_id)

  let tags = await browser.bookmarks.getChildren(tags_folder_id)
  let added_tags = updateTagDates(tags)

  if hasNoAddTag(added_tags, status.config.no_add_tags):
    return

  if status.config.always_add_tags or hasAddTag(added_tags,
      status.config.add_tags):
    setBadgeLoading(tab_id)
    let filtered_tags = filterTags(added_tags, status.config.allowed_tags,
        status.config.discard_tags)
    let link_result = await addLink(bookmark.url,
        status.config.access_token, filtered_tags)
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
proc onMessageCommand(msg: cstring) =
  if msg == "update_tags": discard asyncUpdateTagDates()

proc deinitLoggedIn*(id: int) =
  setBadgeNotLoggedIn(id)
  browser.browserAction.onClicked.removeListener(onOpenOptionPageEvent)
  browser.bookmarks.onCreated.removeListener(onCreateBookmarkEvent)
  browser.bookmarks.onChanged.removeListener(onUpdateTagsEvent)
  browser.bookmarks.onRemoved.removeListener(onUpdateTagsEvent)
  browser.runtime.onMessage.removeListener(onMessageCommand)

proc initLoggedIn*(tab_id: int) =
  setBadgeNone(tab_id)
  discard asyncUpdateTagDates()
  browser.browserAction.onClicked.addListener(onOpenOptionPageEvent)
  browser.bookmarks.onCreated.addListener(onCreateBookmarkEvent)
  browser.bookmarks.onChanged.addListener(onUpdateTagsEvent)
  browser.bookmarks.onRemoved.addListener(onUpdateTagsEvent)
  browser.runtime.onMessage.addListener(onMessageCommand)


