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
    local_data: LocalData
  LocalData* = ref object
    access_token*: cstring
    username*: cstring
    # TODO: discard_tags
    # TODO: allowed_tags
    add_tags*: seq[cstring]
    # TODO: no_add_tags

proc newConfig*(access_token: cstring = "", tag_ids: seq[cstring] = @[],
    tags: seq[TagInfo] = @[]): Config =
  let local_data = LocalData(access_token: "", add_tags: @["pocket".cstring])
  Config(tag_ids: tag_ids, tags: tags, local_data: local_data)

var config = newConfig()
when not defined(release):
  var pocket_link: JsObject = nil

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

proc onCreateBookmark(bookmark: BookmarkTreeNode) {.async.} =
  if bookmark.`type` != "bookmark": return
  # TODO?: indicate link addin to Pocket
  let tags = await browser.bookmarks.getChildren(tags_folder_id)
  let added_tags = updateTagDates(tags)
  console.log "TODO: add pocket link with tags", added_tags
  console.log bookmark
  let link_result = await addLink(bookmark.url, config.local_data.access_token, added_tags)
  if link_result.isErr():
    console.log "Failed to add bookmark to Pocket. Error type: " &
        $link_result.error()
    # TODO: indicate failure in extension badge
    return
  # console.log link_result.value()
  # TODO: indicate success in extension badge

  when not defined(release):
    pocket_link = link_result.value()

const default_add_to_pocket_tag = "pocket".cstring
proc initBackground*() {.async.} =
  discard await asyncUpdateTagDates()

  let storage = await browser.storage.local.get("local_data".cstring)
  if storage.hasOwnProperty("local_data"):
    let local_data = cast[LocalData](storage["local_data"])
    if not isUndefined(local_data.access_token) and
        local_data.access_token.len > 0:
      config.local_data = local_data
    else:
      console.warn "No 'access_token' found"
  else:
    console.warn "No 'local_data' in browser.storage.local"


  browser.browserAction.onClicked.addListener(proc(tab: Tab) =
    let tabs_opts = TabCreateProps(url: browser.runtime.getURL("index.html"))
    discard browser.tabs.create(tabs_opts)
  )

  browser.bookmarks.onCreated.addListener(proc(id: cstring,
      bookmark: BookmarkTreeNode) = discard onCreateBookmark(bookmark)
  )

  browser.bookmarks.onChanged.addListener(proc(id: cstring,
      obj: JsObject) = discard asyncUpdateTagDates())

  browser.bookmarks.onRemoved.addListener(proc(id: cstring,
      obj: JsObject) = discard asyncUpdateTagDates())

  return

when isMainModule:
  when defined(release):
    console.log "BACKGROUND RELEASE BUILD"
    discard initBackground()

  when not defined(release):
    import balls, jscore

    # IMPORTANT: Test functions use global variable 'config'

    console.log "BACKGROUND DEBUG BUILD"

    # TODO: move Port and its functions
    type
      Port* = ref PortObj
      PortObj {.importjs.} = object
        onMessage*: PortEvent
        onDisconnect*: PortEvent

      PortEvent = ref object

    proc addListener(obj: PortEvent, cb: proc(resp: JsObject)) {.importcpp.}
    proc removeListener(obj: PortEvent, cb: proc(resp: JsObject)) {.importcpp.}
    proc disconnect(port: Port) {.importcpp.}
    proc connectNative(r: Runtime, app: cstring): Port {.importcpp.}
    proc postMessage(port: Port, msg: cstring) {.importcpp.}
    proc sendPortMessage*(port: Port, msg: cstring): Future[JsObject] =
      var promise = newPromise(proc(resolve: proc(resp: JsObject)) =
        proc success(resp: JsObject)
        proc failure(resp: JsObject)

        proc success(resp: JsObject) =
          port.onMessage.removeListener(success)
          port.onDisconnect.removeListener(failure)
          resolve(resp)

        proc failure(resp: JsObject) =
          console.error "PORT DISCONNECT", resp
          port.onMessage.removeListener(success)
          port.onDisconnect.removeListener(failure)
          resolve(nil)

        port.onMessage.addListener(success)
        port.onDisconnect.addListener(failure)
      )
      port.postMessage(msg)
      return promise


    proc createTag(name: cstring): Future[void] {.async.} =
      let details = newCreateDetails(title = name, `type` = "folder",
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
        const max_wait_time = 3 # seconds
        proc checkPocketLink()
        proc checkPocketLink() =
          let elapsed_seconds = start - Date.now()
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
    proc runTestsImpl() {.async.} =
      console.info "Run tests"
      let p = browser.runtime.connectNative("sqlite_update")

      suite "pocket":
        block pocket_access_token:
          check config.local_data.access_token.len > 0, "'access_token' was not found in extension local storage"

        block add_bookmark:
          const url_to_add = "https://google.com"
          let msg = await sendPortMessage(p, "tag_inc|pocket,video")
          check msg != nil, "Can't connnect to sqlite_update native application"

          # tags that are going to be added
          let added_tags = await getAddedTagsAsync()
          check added_tags.len == 2, "Wrong count of added tags"
          check "pocket" in added_tags, "'pocket' tag was not found in added tags"
          check "video" in added_tags, "'video' tag was not found in added tags"

          # Add bookmark and pocket link
          let detail = newCreateDetails(title = "Google",
              url = url_to_add)
          let bk1 = await browser.bookmarks.create(detail)
          created_bk_ids.add(bk1.id)

          let link_added = await waitForPocketLink()
          check link_added
          let status = cast[int](pocket_link.status)
          check status == 1, "pocket_link status failed"

          # Check that link was added to pocket
          let links_result = await retrieveLinks(config.local_data.access_token,
              url_to_add)
          check links_result.isOk()
          let links = links_result.value()
          let link_key = cast[cstring](pocket_link.item.item_id)
          let has_added_url = links.list.hasOwnProperty(link_key)
          check has_added_url, "Could not find added link '" & url_to_add & "'"

          var link_tags: seq[cstring] = @[]
          for tag_key in links.list[link_key].tags.keys():
            link_tags.add(tag_key)
          check "pocket" in link_tags
          check "video" in link_tags

          # Delete pocket item
          const link_id = "2148956".cstring
          var action = newJsObject()
          action["action"] = "delete".cstring
          action["item_id"] = link_id
          let del_result = await modifyLink(config.local_data.access_token, action)
          check del_result.isOk()
          let del_value = del_result.value()
          let del_status = cast[int](del_value.status)
          check del_status == 1
          let del_results = cast[seq[bool]](del_value.action_results)
          check del_results[0]

          # Make sure pocket link was deleted
          let links_empty_result = await retrieveLinks(
              config.local_data.access_token, url_to_add)
          check links_empty_result.isOk()
          let links_empty = links_empty_result.value()
          let list_empty = cast[seq[JsObject]](links_empty.list)
          check list_empty.len == 0

      p.disconnect()

    proc setup() {.async.} =
      console.info "Tests setup"
      config = newConfig()
      const json_str = staticRead("../tmp/localstorage.json")
      let local_value = cast[JsObject](JSON.parse(json_str))
      let local_obj = newJsObject()
      local_obj["local_data"] = local_value
      discard await browser.storage.local.set(local_obj)
      await createTag("pocket")
      await createTag("book")
      await createTag("hello")
      await createTag("video")

    proc cleanup() {.async.} =
      console.info "Tests cleanup"
      for id in config.tag_ids:
        await browser.bookmarks.remove(id)
      for id in created_bk_ids:
        await browser.bookmarks.remove(id)
      await browser.storage.local.clear()

    proc runTestSuite() {.async.} =
      console.info "Start test suite"
      await setup()
      await initBackground()
      try:
        await runTestsImpl()
      finally:
        await cleanup()

    discard runTestSuite()
