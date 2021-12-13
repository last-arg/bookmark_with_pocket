import dom, jsffi, asyncjs
import jsconsole
import web_ext_browser, bookmarks, app_config, app_js_ffi, pocket
import badresults, options, tables
import nodejs/[jsstrformat]
# TODO: use case matching
# import fusion/matching
# {.experimental: "caseStmtMacros".}

type
  StateCb* = proc(param: JsObject): void
  Transition = tuple[next: State, cb: Option[StateCb]]
  StateEvent = tuple[state: State, event: Event]
  Machine* = ref object of JsRoot
    currentState*: State
    data*: StateData
    transitions: TableRef[StateEvent, Transition]
    when defined(testing):
      test_data*: JsObject

  State* = enum
    InitialLoad
    LoggedIn
    LoggedOut

  Event* = enum
    Login
    Logout

proc newMachine*(currentState = InitialLoad, data = newStateData(), transitions = newTable[
    StateEvent, Transition]()): Machine =
  when defined(testing):
    Machine(currentState: currentState, data: data, transitions: transitions,
        test_data: newJsObject())
  else:
    Machine(currentState: currentState, data: data, transitions: transitions, )

proc addTransition*(m: Machine, state: State, event: Event, next: State, cb: Option[StateCb] = none[
    StateCb]()) =
  m.transitions[(state, event)] = (next, cb)

proc getTransition*(m: Machine, s: State, e: Event): Option[Transition] =
  let key = (s, e)
  if m.transitions.hasKey(key):
    return some(m.transitions[key])
  else:
    none[Transition]()

proc transition*(m: Machine, event: Event, param: JsObject = nil) =
  let t_opt = m.getTransition(m.currentState, event)
  if t_opt.isSome():
    let t = t_opt.unsafeGet()
    if t.cb.isSome():
      t.cb.unsafeGet()(param)
    m.currentState = t.next
  else:
    console.error "Transition is not defined: State(" & cstring($m.currentState) &
        ") Event(" & cstring($event) & "). Staying in current state: " & cstring($m.currentState)

let badge_empty = newJsObject()
badge_empty["path"] = "./assets/badge_empty.svg".cstring

let badge_grayscale = newJsObject()
badge_grayscale["path"] = "./assets/badge_grayscale.svg".cstring

let badge = newJsObject()
badge["path"] = "./assets/badge.svg".cstring

proc setBadgeLoading*(tab_id: int) =
  let bg_color = newJsObject()
  bg_color["color"] = "#BFDBFE".cstring
  bg_color["tabId"] = tab_id
  browser.browserAction.setBadgeBackgroundColor(bg_color)
  let text_color = newJsObject()
  text_color["color"] = "#000000".cstring
  text_color["tabId"] = tab_id
  browser.browserAction.setBadgeTextColor(text_color)
  let b_text = newJsObject()
  b_text["text"] = "...".cstring
  b_text["tabId"] = tab_id
  browser.browserAction.setBadgeText(b_text)

proc setBadgeFailed*(tab_id: int) =
  let bg_color = newJsObject()
  bg_color["color"] = "#FCA5A5".cstring
  bg_color["tabId"] = tab_id
  browser.browserAction.setBadgeBackgroundColor(bg_color)
  let text_color = newJsObject()
  text_color["color"] = "#000000".cstring
  text_color["tabId"] = tab_id
  browser.browserAction.setBadgeTextColor(text_color)
  let b_text = newJsObject()
  b_text["text"] = "fail".cstring
  b_text["tabId"] = tab_id
  browser.browserAction.setBadgeText(b_text)

proc setBadgeNone*(tab_id: Option[int]) =
  let b_text = newJsObject()
  b_text["text"] = "".cstring
  if isSome(tab_id): b_text["tabId"] = tab_id.unsafeGet()
  browser.browserAction.setBadgeText(b_text)
  let d = newJsObject()
  d["title"] = jsNull
  browser.browserAction.setTitle(d)
  discard browser.browserAction.setIcon(badge_empty)

proc setBadgeSuccess*(tab_id: int) =
  let b_text = newJsObject()
  b_text["text"] = "".cstring
  b_text["tabId"] = tab_id
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

proc updateTagDates*(out_data: StateData, tags: seq[BookmarkTreeNode]): seq[cstring] =
  var r: seq[cstring] = @[]
  for tag in tags:
    let id_index = find[seq[cstring], cstring](out_data.tag_ids, tag.id)
    if id_index == -1:
      r.add(tag.title)
      out_data.tag_ids.add(tag.id)
      out_data.tag_timestamps.add(tag.dateGroupModified)
      continue

    if tag.dateGroupModified != out_data.tag_timestamps[id_index]:
      r.add(tag.title)
      out_data.tag_timestamps[id_index] = tag.dateGroupModified

  return r

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

proc asyncUpdateTagDates(out_data: StateData): Future[JsObject] {.async.} =
  let tags = await browser.bookmarks.getChildren(tags_folder_id)
  discard updateTagDates(out_data, tags)

proc badgePocketLogin(machine: Machine, id: int) {.async.} =
  let body_result = await authenticate()
  if body_result.isErr():
    console.error("Pocket authentication failed")
    setBadgeNotLoggedIn("fail".cstring)
    return
  # Deconstruct urlencoded data
  # let kvs = body_result.value.split("&")
  var login_data = newJsObject()
  const username = "username"
  const access_token = "access_token"
  login_data[access_token] = body_result.value
  # login_data[username] = nil
  # for kv_str in kvs:
  #   let kv = kv_str.split("=")
  #   if kv[0] == access_token:
  #     login_data[access_token] = kv[1]
  #   elif kv[0] == username:
  #     login_data[username] = kv[1]

  if login_data[access_token] == nil:
    console.error("Failed to get access_token form Pocket API response")
    setBadgeNotLoggedIn("fail".cstring)
    return

  discard await browser.storage.local.set(login_data)
  machine.transition(Login)

proc onCreateBookmark*(out_machine: Machine, bookmark: BookmarkTreeNode) {.async.} =
  if bookmark.`type` != "bookmark": return
  let out_data = out_machine.data
  let query_opts = newJsObject()
  query_opts["active"] = true
  query_opts["currentWindow"] = true
  let query_tabs = await browser.tabs.query(query_opts)
  let tab_id = query_tabs[0].id
  setBadgeNone(some(tab_id))

  let tags = await browser.bookmarks.getChildren(tags_folder_id)
  let added_tags = updateTagDates(out_data, tags)

  if hasNoAddTag(added_tags, out_data.config.no_add_tags):
    return

  if out_data.config.always_add_tags or hasAddTag(added_tags,
      out_data.config.add_tags):
    setBadgeLoading(tab_id)
    let filtered_tags = filterTags(added_tags, out_data.config.allowed_tags,
        out_data.config.discard_tags)
    let link_result = await addLink(bookmark.url, out_data.config.access_token, filtered_tags)
    if link_result.isErr():
      console.error "Failed to add bookmark to Pocket. Error type: " &
          cstring($link_result.error())
      setBadgeFailed(tab_id)
      return

    setBadgeSuccess(tab_id)
    when defined(testing):
      out_machine.test_data["pocket"] = link_result.unsafeGet()

func newBackgroundMachine(data: StateData): Machine =
  var machine = newMachine(data = data)

  proc onOpenOptionPageEvent(_: Tab) = discard browser.runtime.openOptionsPage()
  proc onCreateBookmarkEvent(_: cstring, bookmark: BookmarkTreeNode) =
    discard onCreateBookmark(machine, bookmark)

  proc initLoggedIn(param: JsObject) =
    let username = cast[cstring](param.username)
    let access_token = cast[cstring](param.access_token)
    # Set browser local storage
    let login_info = newJsObject()
    login_info.username = username
    login_info.access_token = access_token
    discard browser.storage.local.set(login_info)

    # Set current config
    machine.data.config.username = username
    machine.data.config.access_token = access_token

    setBadgeNone(none[int]())
    browser.browserAction.onClicked.addListener(onOpenOptionPageEvent)
    browser.bookmarks.onCreated.addListener(onCreateBookmarkEvent)

  proc deinitLoggedIn() =
    browser.browserAction.onClicked.removeListener(onOpenOptionPageEvent)
    browser.bookmarks.onCreated.removeListener(onCreateBookmarkEvent)

  proc clickPocketLoginEvent(tab: Tab) = discard badgePocketLogin(machine, tab.id)

  proc onCreateUpdateTags(id: cstring, obj: JsObject) = discard asyncUpdateTagDates(machine.data)
  proc initLoggedOut() =
    const empty_string = "".cstring
    let login_info = newJsObject()
    # Set browser local storage
    login_info.username = empty_string
    login_info.access_token = empty_string
    discard browser.storage.local.set(login_info)
    # Set current config
    machine.data.config.username = empty_string
    machine.data.config.access_token = empty_string
    setBadgeNotLoggedIn()
    browser.browserAction.onClicked.addListener(clickPocketLoginEvent)
    browser.bookmarks.onCreated.addListener(onCreateUpdateTags)

  proc deinitLoggedOut() =
    browser.browserAction.onClicked.removeListener(clickPocketLoginEvent)
    browser.bookmarks.onCreated.removeListener(onCreateUpdateTags)

  machine.addTransition(InitialLoad, Login, LoggedIn, some[StateCb](proc(param: JsObject) =
    console.log "STATE: InitialLoad -> LoggedIn"
    initLoggedIn(param)
  ))
  machine.addTransition(InitialLoad, Logout, LoggedOut, some[StateCb](proc(_: JsObject) =
    console.log "STATE: InitialLoad -> LoggedOut"
    initLoggedOut()
  ))
  machine.addTransition(LoggedIn, Logout, LoggedOut, some[StateCb](proc(_: JsObject) =
    console.log "STATE: LoggedIn -> LoggedOut"
    deinitLoggedIn()
    initLoggedOut()
  ))
  machine.addTransition(LoggedOut, Login, LoggedIn, some[StateCb](proc(param: JsObject) =
    console.log "STATE: LoggedOut -> LoggedIn"
    deinitLoggedOut()
    initLoggedIn(param)
  ))

  return machine

proc initBackgroundEvents(machine: Machine) =
  discard asyncUpdateTagDates(machine.data)
  proc onUpdateTagsEvent(id: cstring, obj: JsObject) = discard asyncUpdateTagDates(machine.data)
  proc onMessageCommand(msg: JsObject) =
    let cmd = cast[cstring](msg.cmd)
    if machine.currentState == LoggedIn and cmd == "update_tags":
      console.log "COMMAND: update_tags"
      discard asyncUpdateTagDates(machine.data)
    elif cmd == "login":
      console.log "COMMAND: login"
      machine.transition(Login, msg.data)
    elif cmd == "logout":
      console.log "COMMAND: logout"
      machine.transition(Logout)

  browser.bookmarks.onChanged.addListener(onUpdateTagsEvent)
  browser.bookmarks.onRemoved.addListener(onUpdateTagsEvent)
  browser.runtime.onMessage.addListener(onMessageCommand)

proc initBackground*() {.async.} =
  let storage = await browser.storage.local.get()
  let state_data: StateData = newStateData(config = cast[Config](storage))
  let machine = newBackgroundMachine(state_data)

  let is_logged_in = not (storage == jsUndefined and storage["access_token"] == jsUndefined)
  # let is_logged_in = true
  if is_logged_in:
    machine.transition(Login, storage)
  else:
    machine.transition(Logout)

  initBackgroundEvents(machine)


browser.runtime.onInstalled.addListener(proc(details: InstalledDetails) =
  if details.reason == "install":
    proc install() {.async.} =
      let local_data = cast[JsObject](newConfig())
      discard await browser.storage.local.set(local_data)
      await browser.runtime.openOptionsPage()
    discard install()
)

when isMainModule:
  when defined(release):
    console.log "background.js RELEASE BUILD"
    discard initBackground()

  when defined(testing):
    import balls, jscore

    console.log "background.js TESTING(DEBUG) BUILD"
    var test_machine: Machine = nil

    proc waitForPocketLink(): Future[bool] =
      let p = newPromise(proc(resolve: proc(resp: bool)) =
        let start = Date.now()
        const max_wait_time = 2000 # milliseconds
        proc checkPocketLink() =
          if not isUndefined(test_machine.test_data["pocket"]):
            resolve(true)
            return

          let elapsed_seconds = Date.now() - start
          if elapsed_seconds > max_wait_time:
            resolve(false)
            return

          discard setTimeout(checkPocketLink, 100)

        checkPocketLink()
      )

      return p

    proc createTags(tags: seq[cstring]): Future[void] {.async.} =
      for tag in tags:
        let details = newCreateDetails(title = tag, `type` = "folder",
            parentId = tags_folder_id)
        let tag = await browser.bookmarks.create(details)

    proc getAddedTags(tags: seq[BookmarkTreeNode]): seq[cstring] =
      var r: seq[cstring] = @[]
      for tag in tags:
        let id_index = find[seq[cstring], cstring](test_machine.data.tag_ids, tag.id)
        if id_index == -1:
          r.add(tag.title)
        elif tag.dateGroupModified != test_machine.data.tag_timestamps[id_index]:
          r.add(tag.title)

      return r

    proc getAddedTagsAsync(): Future[seq[cstring]] {.async.} =
      let tags = await browser.bookmarks.getChildren(tags_folder_id)
      return getAddedTags(tags)

    var created_bk_ids = newSeq[cstring]()
    proc testAddBookMark() {.async.} =
      let p = browser.runtime.connectNative("sqlite_update")
      const url_to_add = "https://google.com"
      let msg = await sendPortMessage(p, "tag_inc|pocket,video,discard_tag")
      check msg != nil, "Can't connnect to sqlite_update native application"

      test_machine.data.config.discard_tags.add(@[@["discard_tag".cstring], @["pocket".cstring]])

      # tags that are part of bookmark
      let added_tags = await getAddedTagsAsync()
      check added_tags.len == 3, "Wrong count of added tags"

      # Add bookmark and pocket link
      let detail = newCreateDetails(title = "Google", url = url_to_add)
      let bk1 = await browser.bookmarks.create(detail)
      created_bk_ids.add(bk1.id)

      let is_pocket_link = await waitForPocketLink()
      check is_pocket_link, "Adding Pocket link failed or took too long"
      let pocket_link = test_machine.test_data["pocket"]
      let pocket_status = cast[int](pocket_link.status)
      check pocket_status == 1, "Added pocket link request returned failed status"

      # Check that link was added to pocket
      let links_result = await retrieveLinks(test_machine.data.config.access_token, url_to_add)
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
      let del_result = await modifyLink(test_machine.data.config.access_token, action)
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
      let links_empty_result = await retrieveLinks(test_machine.data.config.access_token, url_to_add)
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
      console.info "TEST: Run"
      suite "background":
        block filter_tags:
          testFilterTags()

        block pocket_access_token:
          check test_machine.data.config.access_token.len > 0, "'access_token' was not found in extension's local storage"

        block add_bookmark:
          skip()
          await testAddBookMark()

    proc setup() {.async.} =
      await browser.storage.local.clear()
      console.info "TEST: Setup"
      let state_data = newStateData(
        config = newConfig(
          add_tags = @[@["pocket".cstring], @[
              "second".cstring, "third".cstring]]))
      const json_str = staticRead("../tmp/localstorage.json")
      let local_value = cast[JsObject](JSON.parse(json_str))
      discard await browser.storage.local.set(cast[JsObject](state_data.config))
      await createTags(@["pocket".cstring, "book", "hello", "video",
          "discard_tag"])
      test_machine = newBackgroundMachine(state_data)
      initBackgroundEvents(test_machine)
      test_machine.transition(Login, local_value)
      # let tabs_opts = TabCreateProps(active: true, url: browser.runtime.getURL("options/options.html"))
      # discard browser.tabs.create(tabs_opts)

    proc cleanup() {.async.} =
      console.info "TEST: Cleanup"
      for id in test_machine.data.tag_ids:
        discard browser.bookmarks.remove(id)
      for id in created_bk_ids:
        discard browser.bookmarks.remove(id)

    proc runTestSuite() {.async, discardable.} =
      console.info "TEST: Start"
      await setup()
      try:
        await runTestsImpl()
      finally:
        await cleanup()

    runTestSuite()
