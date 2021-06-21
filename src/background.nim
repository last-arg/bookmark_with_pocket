import dom, jsffi, asyncjs
import jsconsole
import web_ext_browser, bookmarks
import results
import pocket

type
  TagInfo* = ref object
    modified*: int
    title*: cstring

  Config* = ref ConfigObj
  ConfigObj = object
    tag_ids*: seq[cstring]
    tags*: seq[TagInfo]
    local: LocalData

  LocalData* = ref object
    access_token*: cstring
    username*: cstring
    always_add: bool
    add_tags*: seq[seq[cstring]]
    no_add_tags*: seq[seq[cstring]]
    allowed_tags*: seq[seq[cstring]]
    discard_tags*: seq[seq[cstring]]

proc newConfig*(
    access_token: cstring = "",
    username: cstring = "",
    tag_ids: seq[cstring] = @[],
    tags: seq[TagInfo] = @[],
    always_add = false,
    add_tags: seq[seq[cstring]] = @[@["pocket".cstring]],
    no_add_tags: seq[seq[cstring]] = @[@["no-pocket".cstring]],
    allowed_tags: seq[seq[cstring]] = @[],
    discard_tags: seq[seq[cstring]] = @[],
  ): Config =
  let local = LocalData(access_token: "",
      username: username,
      always_add: always_add,
      add_tags: add_tags,
      no_add_tags: no_add_tags,
      allowed_tags: allowed_tags,
      discard_tags: discard_tags)
  Config(tag_ids: tag_ids, tags: tags, local: local)

var config = newConfig()
when defined(testing):
  var pocket_link: JsObject = nil

let empty_badge = newJsObject()
empty_badge["path"] = "./assets/badge_empty.svg".cstring

let badge = newJsObject()
badge["path"] = "./assets/badge.svg".cstring

proc filter*[T](arr: seq[T], fn: (proc(item: T): bool)): seq[T] {.
    importjs: "#.filter(#)".}
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

proc updateTagDates*(tags: seq[BookmarkTreeNode]): seq[cstring] =
  var r: seq[cstring] = @[]
  for tag in tags:
    let id_index = find[seq[cstring], cstring](config.tag_ids, tag.id)
    if id_index == -1:
      let tag_info = TagInfo(modified: tag.dateGroupModified,
          title: tag.title)
      r.add(tag.title)
      config.tag_ids.add(tag.id)
      config.tags.add(tag_info)
      continue

    if tag.dateGroupModified != config.tags[id_index].modified:
      r.add(tag.title)
      config.tags[id_index] = TagInfo(modified: tag.dateGroupModified,
          title: tag.title)

  return r

proc asyncUpdateTagDates(): Future[jsUndefined] {.async.} =
  let tags = await browser.bookmarks.getChildren(tags_folder_id)
  discard updateTagDates(tags)

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

proc setBadgeLoading(tab_id: int) =
  browser.browserAction.setBadgeBackgroundColor(
    BadgeBgColor(color: "#BFDBFE", tabId: tab_id))
  browser.browserAction.setBadgeTextColor(
    BadgeTextColor(color: "#000000", tabId: tab_id))
  browser.browserAction.setBadgeText(BadgeText(text: "...", tabId: tab_id))

proc setBadgeFailed(tab_id: int) =
  browser.browserAction.setBadgeBackgroundColor(
    BadgeBgColor(color: "#FCA5A5", tabId: tab_id))
  browser.browserAction.setBadgeTextColor(
    BadgeTextColor(color: "#000000", tabId: tab_id))
  browser.browserAction.setBadgeText(BadgeText(text: "fail", tabId: tab_id))

proc setBadgeNone(tab_id: int) =
  let text_detail = BadgeText(text: "", tabId: tab_id)
  browser.browserAction.setBadgeText(text_detail)
  badge["tabId"] = tab_id
  discard browser.browserAction.setIcon(empty_badge)

proc setBadgeSuccess(tab_id: int) =
  let text_detail = BadgeText(text: "", tabId: tab_id)
  browser.browserAction.setBadgeText(text_detail)
  badge["tabId"] = tab_id
  discard browser.browserAction.setIcon(badge)

proc onCreateBookmark(bookmark: BookmarkTreeNode) {.async.} =
  if bookmark.`type` != "bookmark": return
  let query_tabs = await browser.tabs.query(
    TabQuery(active: true, currentWindow: true))
  let tab_id = query_tabs[0].id
  setBadgeNone(tab_id)

  let tags = await browser.bookmarks.getChildren(tags_folder_id)
  let added_tags = updateTagDates(tags)

  if hasNoAddTag(added_tags, config.local.no_add_tags):
    return

  if config.local.always_add or hasAddTag(added_tags,
      config.local.add_tags):
    setBadgeLoading(tab_id)
    let filtered_tags = filterTags(added_tags, config.local.allowed_tags,
        config.local.discard_tags)
    let link_result = await addLink(bookmark.url,
        config.local.access_token, filtered_tags)
    if link_result.isErr():
      console.error "Failed to add bookmark to Pocket. Error type: " &
          $link_result.error()
      setBadgeFailed(tab_id)
      return

    setBadgeSuccess(tab_id)

    when defined(testing):
      pocket_link = link_result.value()

proc initBackground*() {.async.} =
  discard browser.browserAction.setIcon(empty_badge)
  discard await asyncUpdateTagDates()

  let storage = await browser.storage.local.get("local".cstring)
  if storage.hasOwnProperty("local"):
    let local = cast[LocalData](storage["local"])
    if not isUndefined(local.access_token) and
        local.access_token.len > 0:
      config.local.access_token = local.access_token
      config.local.username = local.username
    else:
      console.warn "No 'access_token' found"
  else:
    console.warn "No 'local' in browser.storage.local"


  browser.browserAction.onClicked.addListener(proc(tab: Tab) =
    let tabs_opts = TabCreateProps(url: browser.runtime.getURL("index.html"))
    discard browser.tabs.create(tabs_opts)
  )

  browser.bookmarks.onCreated.addListener(
    proc(id: cstring, bookmark: BookmarkTreeNode) = discard onCreateBookmark(bookmark))

  browser.bookmarks.onChanged.addListener(
    proc(id: cstring, obj: JsObject) = discard asyncUpdateTagDates())

  browser.bookmarks.onRemoved.addListener(
    proc(id: cstring, obj: JsObject) = discard asyncUpdateTagDates())

  return

when isMainModule:


  when defined(release):
    console.log "BACKGROUND RELEASE BUILD"
    discard initBackground()

  when defined(testing):
    import balls, jscore, web_ext_browser

    # IMPORTANT: Test functions use global variable 'config'
    console.log "BACKGROUND TESTING(DEBUG) BUILD"

    proc createTags(tags: seq[cstring]): Future[void] {.async.} =
      for tag in tags:
        let details = newCreateDetails(title = tag, `type` = "folder",
            parentId = tags_folder_id)
        let tag = await browser.bookmarks.create(details)

    proc getAddedTags(tags: seq[BookmarkTreeNode]): seq[cstring] =
      var r: seq[cstring] = @[]
      for tag in tags:
        let id_index = find[seq[cstring], cstring](config.tag_ids, tag.id)
        if id_index == -1:
          r.add(tag.title)
        elif tag.dateGroupModified != config.tags[id_index].modified:
          r.add(tag.title)

      return r

    proc getAddedTagsAsync(): Future[seq[cstring]] {.async.} =
      let tags = await browser.bookmarks.getChildren(tags_folder_id)
      return getAddedTags(tags)

    proc waitForPocketLink(): Future[bool] =
      let p = newPromise(proc(resolve: proc(resp: bool)) =
        let start = Date.now()
        const max_wait_time = 2000 # milliseconds
        proc checkPocketLink()
        proc checkPocketLink() =
          let elapsed_seconds = Date.now() - start
          if not isNull(pocket_link):
            resolve(true)
            return

          if elapsed_seconds > max_wait_time:
            resolve(false)
            return

          discard setTimeout(checkPocketLink, 100)

        checkPocketLink()
      )

      return p

    var created_bk_ids = newSeq[cstring]()
    proc testAddBookMark() {.async.} =
      let p = browser.runtime.connectNative("sqlite_update")
      const url_to_add = "https://google.com"
      let msg = await sendPortMessage(p, "tag_inc|pocket,video,discard_tag")
      check msg != nil, "Can't connnect to sqlite_update native application"

      config.local.discard_tags.add(@[@["discard_tag".cstring], @[
          "pocket".cstring]])

      # tags that are part of bookmark
      let added_tags = await getAddedTagsAsync()
      check added_tags.len == 3, "Wrong count of added tags"

      # Add bookmark and pocket link
      let detail = newCreateDetails(title = "Google",
          url = url_to_add)
      let bk1 = await browser.bookmarks.create(detail)
      created_bk_ids.add(bk1.id)

      let link_added = await waitForPocketLink()
      check link_added, "Could not get added pocket link. Either test timed out because adding link was taking too long or adding link failed on pocket side."
      let status = cast[int](pocket_link.status)
      check status == 1, "pocket_link status failed"

      # Check that link was added to pocket
      let links_result = await retrieveLinks(config.local.access_token,
          url_to_add)
      check links_result.isOk()
      let links = links_result.value()
      let link_key = cast[cstring](pocket_link.item.item_id)
      let has_added_url = links.list.hasOwnProperty(link_key)
      check has_added_url, "Could not find added link '" & url_to_add & "'"

      let link_tags = links.list[link_key].tags
      var tags_len = 0
      for _ in link_tags.keys(): tags_len += 1
      check tags_len == 1
      check link_tags.hasOwnProperty("video")

      # Delete pocket item
      var action = newJsObject()
      action["action"] = "delete".cstring
      action["item_id"] = link_key
      let del_result = await modifyLink(config.local.access_token, action)
      check del_result.isOk()
      let del_value = del_result.value()
      let del_status = cast[int](del_value.status)
      check del_status == 1
      let del_results = cast[seq[bool]](del_value.action_results)
      check del_results[0]

      # Add bookmark only (no pocket link)
      discard await sendPortMessage(p, "tag_inc|music,book,no-pocket")
      let bk2 = await browser.bookmarks.create(
        newCreateDetails(title = "Google", url = url_to_add))
      created_bk_ids.add(bk2.id)

      # Make sure pocket link was deleted
      let links_empty_result = await retrieveLinks(
          config.local.access_token, url_to_add)
      check links_empty_result.isOk()
      let links_empty = links_empty_result.value()
      let list_empty = cast[seq[JsObject]](links_empty.list)
      check list_empty.len == 0

      p.disconnect()

    proc testFilterTags() =
      let added_tags: seq[cstring] = @["pocket".cstring, "video".cstring,
          "music".cstring, "book".cstring]
      let filter_tags: seq[seq[cstring]] = @[@["video".cstring,
          "pocket".cstring], @["book".cstring]]
      var pocket_tags = filterTags(added_tags, filter_tags, @[])
      check pocket_tags.len == 3, "Wrong number of pocket_tags returned"
      for t in pocket_tags:
        check (filter_tags[0].contains(t) or filter_tags[1].contains(t))

      pocket_tags = filterTags(added_tags, @[], filter_tags)
      check "music" == pocket_tags[0]


    proc runTestsImpl() {.async.} =

      console.info "Run tests"
      suite "background":
        block filter_tags:
          testFilterTags()

        block pocket_access_token:
          check config.local.access_token.len > 0, "'access_token' was not found in extension local storage"

        block add_bookmark:
          # skip()
          await testAddBookMark()


    proc setup() {.async.} =
      console.info "Tests setup"
      config = newConfig()
      const json_str = staticRead("../tmp/localstorage.json")
      let local_value = cast[JsObject](JSON.parse(json_str))
      let local_obj = newJsObject()
      local_obj.local = local_value
      discard await browser.storage.local.set(local_obj)
      await createTags(@["pocket".cstring, "book", "hello", "video",
          "discard_tag"])

    proc cleanup() {.async.} =
      console.info "Tests cleanup"
      for id in config.tag_ids:
        await browser.bookmarks.remove(id)
      for id in created_bk_ids:
        await browser.bookmarks.remove(id)
      await browser.storage.local.clear()

    proc runTestSuite() {.async, discardable.} =
      console.info "Start test suite"
      await setup()
      await initBackground()
      try:
        await runTestsImpl()
      finally:
        await cleanup()

    runTestSuite()
