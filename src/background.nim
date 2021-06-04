import dom, jsffi, asyncjs
import jsconsole
import web_ext_browser, bookmarks
import pocket

type
  TagInfo* = ref object
    modified*: int
    title*: cstring

  Config* = ref object
    tag_ids*: seq[cstring]
    tags*: seq[TagInfo]
    # TODO: add field that contains TAGS that add link to pocket
    pocket_tag_id*: cstring


proc newConfig*(tag_ids: seq[cstring] = @[], tags: seq[TagInfo] = @[],
    pocket_tag_id: cstring = ""): Config =
  Config(tag_ids: tag_ids, tags: tags, pocket_tag_id: pocket_tag_id)

let config* = newConfig()

proc pocketTagId(): Future[cstring] {.async.} =
  let tags = await browser.bookmarks.getChildren(tags_folder_id)
  for tag in tags:
    console.log tag.title
    if tag.title == pocket_add_folder:
      return tag.id

  let details = newCreateDetails(title = pocket_add_folder, `type` = "folder",
      parentId = tags_folder_id)
  let tag = await browser.bookmarks.create(details)
  return tag.id

# proc setTagsModifiedDates*(): Future[void] {.async.} =
#   let tags = await browser.bookmarks.getChildren(tags_folder_id)
#   for tag in tags:
#     discard config.tags.set(tag.id, TagInfo(
#         modified: tag.dateGroupModified, title: tag.title))

proc updateTagDates*(tags: seq[BookmarkTreeNode]): seq[cstring] =
  var r: seq[cstring] = @[]
  for tag in tags:
    let id_index = find[seq[cstring], cstring](config.tag_ids, tag.id)
    if id_index == -1:
      let tag_info = TagInfo(modified: tag.dateGroupModified, title: tag.title)
      r.add(tag.title)
      config.tag_ids.add(tag.id)
      config.tags.add(tag_info)
      continue

    if tag.dateGroupModified != config.tags[id_index].modified:
      r.add(tag.title)
      config.tags[id_index] = TagInfo(modified: tag.dateGroupModified,
          title: tag.title)

  return r

proc asyncUpdateTagDates() {.async.} =
  console.log "Update tags only"
  let tags = await browser.bookmarks.getChildren(tags_folder_id)
  discard updateTagDates(tags)

proc onCreateBookmark(bookmark: BookmarkTreeNode) {.async.} =
  if bookmark.`type` != "bookmark": return
  console.log config.tags
  let tags = await browser.bookmarks.getChildren(tags_folder_id)
  let added_tags = updateTagDates(tags)
  console.log "TODO: add pocket link with tags", added_tags

proc initBackground*() {.async.} =
  console.log "BACKGROUND INIT"
  let pocket_tag_id = await pocketTagId()
  console.log "pocket_tag_id: " & pocket_tag_id

  let tags = await browser.bookmarks.getChildren(tags_folder_id)
  discard updateTagDates(tags)

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
  document.addEventListener("DOMContentLoaded", proc(
      _: Event) = discard initBackground())
