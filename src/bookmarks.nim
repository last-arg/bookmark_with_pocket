import asyncjs, jsffi, dom, jscore
import jsconsole

const tags_folder_id* = "tags________"

type
  BookmarksCreated* = ref BookmarksCreatedObj
  BookmarksCreatedObj {.importjs.} = object

  BookmarksChanged* = ref BookmarksChangedObj
  BookmarksChangedObj {.importjs.} = object

  BookmarksRemoved* = ref BookmarksRemovedObj
  BookmarksRemovedObj {.importjs.} = object

  BookmarksMoved* = ref BookmarksMovedObj
  BookmarksMovedObj {.importjs.} = object

  BookmarksChildrenReordered* = ref BookmarksChildrenReorderedObj
  BookmarksChildrenReorderedObj {.importjs.} = object

  BookmarksEvent* = ref object of RootObj
  # BookmarksEventObj {.importjs.} = object

  Bookmarks* = ref BookmarksObj
  BookmarksObj {.importjs.} = object
    onCreated*: BookmarksEvent
    onRemoved*: BookmarksEvent
    onChanged*: BookmarksEvent

  BookmarksQuery* = ref BookmarksQueryObj
  BookmarksQueryObj {.importjs.} = object
    url*: cstring
    title*: cstring

  CreateDetails* = ref CreateDetailsObj
  CreateDetailsObj {.importjs.} = object
    title*: cstring
    `type`*: cstring
    url*: cstring
    parentId*: cstring

  Changes* = ref ChangesObj
  ChangesObj {.importjs.} = object
    title: cstring
    url: cstring

  BookmarkTreeNode* = ref BookmarkTreeNodeObj
  BookmarkTreeNodeObj {.importjs.} = object of RootObj
    children*: seq[BookmarkTreeNode]
    dateAdded*: int         # ms
    dateGroupModified*: int # ms
    id*: cstring
    index*: int
    parentId*: cstring
    title*: cstring
    `type`*: cstring        # BookmarkTreeNodeType
    unmodifiable*: cstring
    url*: cstring



proc newCreateDetails*(title = "".cstring, `type` = "bookmark".cstring,
    url: cstring = nil, parentId: cstring = nil): CreateDetails =
  CreateDetails(title: title, `type`: `type`, url: url, parentId: parentId)

proc newBookmarksQuery*(title: cstring = nil,
    url: cstring = nil): BookmarksQuery =
  BookMarksQuery(title: title, url: url)

proc newChanges*(title: cstring = nil, url: cstring = nil): Changes =
  Changes(title: title, url: url)

{.push importcpp.}

proc create*(bm: Bookmarks, details: CreateDetails): Future[BookmarkTreeNode]
proc remove*(bm: Bookmarks, id: cstring): Future[void]
proc removeTree*(bm: Bookmarks, id: cstring): Future[void]
proc update*(bm: Bookmarks, id: cstring, changes: Changes): Future[BookmarkTreeNode]
proc getTree*(bm: Bookmarks): Future[seq[BookmarkTreeNode]]
proc getChildren*(bm: Bookmarks, id: cstring): Future[seq[BookmarkTreeNode]]
proc get*(bm: Bookmarks, id: cstring): Future[seq[BookmarkTreeNode]]
proc search*(bm: Bookmarks, query: BookMarksQuery): Future[seq[BookmarkTreeNode]]
proc addListener*(bmc: BookmarksEvent, cb: proc(id: cstring,
    bookmark: BookmarkTreeNode))
proc addListener*(bmc: BookmarksEvent, cb: proc(id: cstring,
    obj: JsObject))
