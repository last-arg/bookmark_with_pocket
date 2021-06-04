import asyncjs, jsffi, dom
import jsconsole
import balls
import results
import ../src/pocket, ../src/main, ../src/bookmarks, ../src/background

type
  Port* = ref PortObj
  PortObj {.importjs.} = object
    onMessage*: JsObject
    onDisconnect*: JsObject

proc createTag(name: cstring): Future[void] {.async.} =
  let details = newCreateDetails(title = name, `type` = "folder",
      parentId = tags_folder_id)
  let tag = await browser.bookmarks.create(details)

# proc sendNativeMessage(r: Runtime, app: cstring, msg: cstring): Future[
#     JsObject] {.importcpp.}
proc addListener(obj: JsObject, cb: proc(resp: JsObject)) {.importcpp.}
proc connectNative(r: Runtime, app: cstring): Port {.importcpp.}
proc postMessage(port: Port, msg: cstring) {.importcpp.}
proc disconnect(port: Port) {.importcpp.}
proc sendPortMessage*(port: Port, msg: cstring): Future[JsObject] =
  var promise = newPromise(proc(resolve: proc(resp: JsObject)) =
    port.onMessage.addListener(proc(port_resp: JsObject) =
      resolve(port_resp)
    )
    port.onDisconnect.addListener(proc(port_resp: JsObject) =
      console.log port_resp
      resolve(nil)
    )
  )
  port.postMessage(msg)
  return promise

proc getModifiedTags*(tags: seq[BookmarkTreeNode]): seq[cstring] =
  var names: seq[cstring] = @[]
  for tag in tags:
    # 'config' is global value
    let id_index = find[seq[cstring], cstring](config.tag_ids, tag.id)
    if id_index == -1:
      names.add(tag.title)
      continue

    if tag.dateGroupModified != config.tags[id_index].modified:
      names.add(tag.title)

  return names

proc testAddTag(p: Port) {.async.} =
  let msg = await sendPortMessage(p, "tag_inc|pocket,video")
  console.log "changed tag(s) modified date: " & cast[cstring](msg)
  let tags = await browser.bookmarks.getChildren(tags_folder_id)
  let expected_tags = updateTagDates(tags)
  console.log config.tags

  let detail = newCreateDetails(title = "Google",
      url = "https://google.com")
  let bk1 = await browser.bookmarks.create(detail)


proc runTests(): Future[void] {.async.} =
  let tags = await browser.bookmarks.getChildren(tags_folder_id)
  discard updateTagDates(tags)
  let p = browser.runtime.connectNative("sqlite_update")
  await testAddTag(p)

  suite "pocket":
    let token = window.localStorage.getItem("access_token")
    block pocket_access_token:
      assert not token.isNull()

    block add_tag:
      await testAddTag(p)

    # let bk2 = await browser.bookmarks.update(bk1.id, newChanges(
    #     title = "Google Update"))

    # let c = await updateTagDates(tags)
    # console.log "tag to add ", c

  p.disconnect()

proc setup(): Future[void] {.async.} =
  await createTag("book")
  await createTag("hello")
  await createTag("video")
  let tags = await browser.bookmarks.getChildren(tags_folder_id)
  discard updateTagDates(tags)

proc loaded(): Future[void] {.async.} =
  await setup()
  await init()
  await runTests()

discard loaded()
