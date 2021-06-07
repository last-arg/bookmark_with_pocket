import dom, jsffi, asyncjs
import jsconsole
import web_ext_browser, bookmarks
import pocket

type
  TagInfo* = ref object
    modified*: int
    title*: cstring

  Config* = ref ConfigObj
  ConfigObj = object
    tag_ids*: seq[cstring]
    tags*: seq[TagInfo]
    add_to_pocket_tags*: seq[cstring]
    # TODO: add field that contains TAGS that add link to pocket

proc newConfig*(tag_ids: seq[cstring] = @[], tags: seq[TagInfo] = @[],
    add_to_pocket_tags: seq[cstring] = @[]): Config =
  Config(tag_ids: tag_ids, tags: tags, add_to_pocket_tags: add_to_pocket_tags)

var config = newConfig()

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
  console.log "create bk"
  if bookmark.`type` != "bookmark": return
  let tags = await browser.bookmarks.getChildren(tags_folder_id)
  let added_tags = updateTagDates(tags)
  console.log "TODO: add pocket link with tags", added_tags
  # TODO: add link to pocket
  # TODO: check if any tags need to be added

const config_fields = block:
  var fields: seq[cstring] = @["no".cstring]
  for c, t in ConfigObj().fieldPairs():
    fields.add(c)
  fields

proc initBackground*() {.async.} =
  discard await asyncUpdateTagDates()

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

    var created_bk_ids = newSeq[cstring]()
    proc runTestsImpl() {.async.} =
      console.info "Run tests"
      let p = browser.runtime.connectNative("sqlite_update")

      suite "pocket":
        let storage_obj = await browser.storage.local.get(
            "access_token".cstring)
        block pocket_access_token:
          check storage_obj.hasOwnProperty("access_token"), "'access_token' was not found in extension local storage"

        block add_bookmark:
          let msg = await sendPortMessage(p, "tag_inc|pocket,video")
          check msg != nil, "Can't connnect to sqlite_update native application"

          let added_tags = await getAddedTagsAsync()
          check added_tags.len == 2, "Wrong count of added tags"
          check "pocket" in added_tags, "'pocket' tag was not found in added tags"
          check "video" in added_tags, "'video' tag was not found in added tags"

          let detail = newCreateDetails(title = "Google",
              url = "https://google.com")
          let bk1 = await browser.bookmarks.create(detail)
          created_bk_ids.add(bk1.id)

          # TODO: check that link was added to pocket

      p.disconnect()

    proc setup() {.async.} =

      console.info "Tests setup"
      config = newConfig()
      const json_str = staticRead("../tmp/localstorage.json")
      let local_data = cast[JsObject](JSON.parse(json_str))
      discard await browser.storage.local.set(local_data)
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

    proc runTestSuite() {.async.} =
      console.info "Start test suite"
      console.info "Start test suite"
      await setup()
      await initBackground()
      try:
        await runTestsImpl()
      finally:
        await cleanup()

    discard runTestSuite()
