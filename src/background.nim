import dom, jsffi, asyncjs
import jsconsole
import web_ext_browser, bookmarks, app_config, app_js_ffi, pocket
import badresults, options, tables
import fusion/matching
{.experimental: "caseStmtMacros".}

when defined(testing):
  var test_data*: JsObject = newJsObject()

type
  Statecb* = proc(param: JsObject): void
  Transition = tuple[next: State, cb: Option[StateCb]]
  StateEvent = tuple[state: State, event: Event]
  Machine* = ref object of JsRoot
    currentState*: State
    data*: StateData
    transitions: TableRef[StateEvent, Transition]


  State* = enum
    InitialLoad
    LoggedIn
    LoggedOut

  Event* = enum
    Login
    Logout

proc newMachine*(currentState = InitialLoad, data = newStateData(), transitions = newTable[
    StateEvent, Transition]()): Machine =
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
    let id_index = find[seq[cstring], cstring](out_data.tag_info.ids, tag.id)
    if id_index == -1:
      r.add(tag.title)
      out_data.tag_info.ids.add(tag.id)
      out_data.tag_info.timestamps.add(tag.dateGroupModified)
      continue

    if tag.dateGroupModified != out_data.tag_info.timestamps[id_index]:
      r.add(tag.title)
      out_data.tag_info.timestamps[id_index] = tag.dateGroupModified

  return r

proc filterTags*(tags: seq[cstring], discard_tags: seq[seq[cstring]]): seq[cstring] =
  var new_tags = newSeq[cstring]()
  if discard_tags.len > 0:
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

proc asyncUpdateTagDates(out_data: StateData): Future[void] {.async.} =
  let tags = await browser.bookmarks.getChildren(tags_folder_id)
  discard updateTagDates(out_data, tags)

proc badgePocketLogin(machine: Machine, id: int) {.async.} =
  let body_result = await authenticate()
  if body_result.isErr():
    console.error("Pocket authentication failed")
    setBadgeNotLoggedIn("fail".cstring)
    return

  var login_data = newJsObject()
  const username = "username"
  const access_token = "access_token"
  login_data[access_token] = body_result.value
  # TODO: get/save username

  if login_data[access_token] == nil:
    console.error("Failed to get access_token form Pocket API response")
    setBadgeNotLoggedIn("fail".cstring)
    return

  discard await browser.storage.local.set(login_data)
  machine.transition(Login)


proc checkAddToPocket(input_tags: seq[cstring], settings: Settings): Option[seq[cstring]] =
  if hasNoAddTag(input_tags, settings.no_add_tags):
    return none[seq[cstring]]()

  if settings.always_add_pocket or hasAddTag(input_tags, settings.add_tags):
    return some(filterTags(input_tags, settings.exclude_tags))

  return none[seq[cstring]]()


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
  let input_tags = updateTagDates(out_data, tags)

  case checkAddToPocket(input_tags, out_data.settings):
    of Some(@tags):
      setBadgeLoading(tab_id)
      let link_result = await addLink(bookmark.url, out_data.pocket_info.access_token, tags)
      if link_result.isErr():
        console.error "Failed to add bookmark to Pocket. Error type: " & $link_result.error()
        setBadgeFailed(tab_id)
      else:
        setBadgeSuccess(tab_id)
        when defined(testing):
          test_data["pocket"] = link_result.unsafeGet()


func newBackgroundMachine(data: StateData): Machine =
  var machine = newMachine(data = data)

  proc onOpenOptionPageEvent(_: Tab) = discard browser.runtime.openOptionsPage()
  proc onCreateBookmarkEvent(_: cstring, bookmark: BookmarkTreeNode) =
    discard onCreateBookmark(machine, bookmark)

  proc initLoggedIn(pocket_info: PocketInfo) =
    discard browser.storage.local.set(toJs(pocket_info))
    machine.data.pocket_info = pocket_info

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
    machine.data.pocket_info.username = empty_string
    machine.data.pocket_info.access_token = empty_string
    setBadgeNotLoggedIn()
    browser.browserAction.onClicked.addListener(clickPocketLoginEvent)
    browser.bookmarks.onCreated.addListener(onCreateUpdateTags)

  proc deinitLoggedOut() =
    browser.browserAction.onClicked.removeListener(clickPocketLoginEvent)
    browser.bookmarks.onCreated.removeListener(onCreateUpdateTags)

  machine.addTransition(InitialLoad, Login, LoggedIn, some[StateCb](proc(param: JsObject) =
    console.log "STATE: InitialLoad -> LoggedIn"
    initLoggedIn(to(param, PocketInfo))
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
    initLoggedIn(to(param, PocketInfo))
  ))

  return machine

proc initBackgroundEvents(machine: Machine) =
  discard asyncUpdateTagDates(machine.data)
  proc onUpdateTagsEvent(id: cstring, obj: JsObject) = discard asyncUpdateTagDates(machine.data)
  proc onMessageCommand(msg: JsObject) =
    let cmd = to(msg.cmd, cstring)
    if machine.currentState == LoggedIn and cmd == "update_tags":
      console.log "COMMAND: update_tags"
      discard asyncUpdateTagDates(machine.data)
    elif cmd == "login":
      console.log "COMMAND: login"
      machine.transition(Login, msg.data)
    elif cmd == "logout":
      console.log "COMMAND: logout"
      machine.transition(Logout)
    elif cmd == "update_settings":
      console.log "COMMAND: update_settings"
      machine.data.settings = to(msg.data, Settings)
    else:
      console.error "Failed to execute command '" & cmd & "'"

  browser.bookmarks.onChanged.addListener(onUpdateTagsEvent)
  browser.bookmarks.onRemoved.addListener(onUpdateTagsEvent)
  browser.runtime.onMessage.addListener(onMessageCommand)

proc initBackground*() {.async.} =
  let storage = await browser.storage.local.get()
  let state_data: StateData =
    newStateData(settings = to(storage, Settings), pocket_info = to(storage, PocketINfo))
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
      discard await browser.storage.local.set(toJs(newSettings()))
      await browser.runtime.openOptionsPage()
    discard install()
)

when isMainModule:
  when defined(release):
    console.log "background.js RELEASE BUILD"
    discard initBackground()

  when defined(testing):
    import balls, jscore
    import test_utils

    console.log "background.js TESTING(DEBUG) BUILD"
    var test_machine: Machine = nil

    proc waitForPocketLink(): Future[bool] =
      let p = newPromise(proc(resolve: proc(resp: bool)) =
        let start = Date.now()
        const max_wait_time = 2000 # milliseconds
        proc checkPocketLink() =
          if not isUndefined(test_data["pocket"]):
            resolve(true)
            return

          let elapsed_seconds = Date.now() - start
          if elapsed_seconds > max_wait_time:
            resolve(false)
            return

          discard setTimeout(checkPocketLink, 50)

        checkPocketLink()
      )

      return p

    proc createTags(tags: seq[cstring]): Future[void] {.async.} =
      for tag in tags:
        let details = newCreateDetails(title = tag, `type` = "folder",
            parentId = tags_folder_id)
        discard await browser.bookmarks.create(details)

    proc getAddedTags(tags: seq[BookmarkTreeNode]): seq[cstring] =
      var r: seq[cstring] = @[]
      for tag in tags:
        let id_index = find[seq[cstring], cstring](test_machine.data.tag_info.ids, tag.id)
        if id_index == -1:
          r.add(tag.title)
        elif tag.dateGroupModified != test_machine.data.tag_info.timestamps[id_index]:
          r.add(tag.title)

      return r

    proc getAddedTagsAsync(): Future[seq[cstring]] {.async.} =
      let tags = await browser.bookmarks.getChildren(tags_folder_id)
      return getAddedTags(tags)

    proc testAddBookMark() {.async.} =
      var created_bk_ids = newSeq[cstring]()
      var sqlite_update: Port
      proc setup() {.async.} =
        await createTags(@[cstring"pocket", "book", "hello", "video", "discard_tag"])
        await asyncUpdateTagDates(test_machine.data)
        sqlite_update = browser.runtime.connectNative("sqlite_update")
        let msg = await sendPortMessage(sqlite_update, "tag_inc|pocket,video,discard_tag")
        check msg != nil, "Can't connnect to sqlite_update native application"
        test_machine.data.settings.exclude_tags = @[@[cstring"discard_tag"], @[cstring"pocket"]]

      proc teardown() =
        sqlite_update.disconnect()
        for id in created_bk_ids:
          discard browser.bookmarks.remove(id)

      proc run() {.async.} =
        # tags that are part of bookmark
        let added_tags = await getAddedTagsAsync()
        check added_tags.len == 3, "Wrong count of added tags"

        # Add bookmark and pocket link
        const url_to_add = "https://google.com"
        let detail = newCreateDetails(title = "Google", url = url_to_add)
        let bk1 = await browser.bookmarks.create(detail)
        created_bk_ids.add(bk1.id)

        let is_pocket_link = await waitForPocketLink()
        check is_pocket_link, "Adding Pocket link failed or took too long"
        let pocket_link = test_data["pocket"]
        let pocket_status = to(pocket_link.status, int)
        check pocket_status == 1, "Added pocket link request returned failed status"

        # Check that link was added to pocket
        let links_result = await retrieveLinks(test_machine.data.pocket_info.access_token, url_to_add)
        check links_result.isOk()
        let links = links_result.value()
        let link_key = to(pocket_link.item.item_id, cstring)
        let has_added_url = links.list.hasOwnProperty(link_key)
        check has_added_url, "Could not find added link '" & url_to_add & "'"

        let link_tags = links.list[link_key].tags
        var tags_len = 0
        for _ in link_tags.keys(): tags_len += 1
        check tags_len == 1
        # NOTE: for some reason get runtime erro when link_tags.hasOwnProperty() is called inside check fn
        let checkVideoTags = link_tags.hasOwnProperty("video")
        check checkVideoTags, "Returned Pocket link doesn't contain 'video' tag"

        # Delete pocket item
        var action = newJsObject()
        action["action"] = "delete".cstring
        action["item_id"] = link_key
        let del_result = await modifyLink(test_machine.data.pocket_info.access_token, action)
        check del_result.isOk()
        let del_value = del_result.value()
        let del_status = to(del_value.status, int)
        check del_status == 1
        let del_results = to(del_value.action_results, seq[bool])
        check del_results[0]

        # Make sure pocket link was deleted
        let links_empty_result = await retrieveLinks(test_machine.data.pocket_info.access_token, url_to_add)
        check links_empty_result.isOk()
        let links_empty = links_empty_result.value()
        let list_empty = to(links_empty.list, seq[JsObject])
        check list_empty.len == 0

      try:
        await setup()
        await run()
      finally:
        teardown()

    proc testCheckAddToPocket() =
      let settings = Settings(
        add_tags: @[@[cstring"video"]],
        no_add_tags: @[@[cstring"no-pocket"]],
        exclude_tags: @[@[cstring"pocket", "discard_tag"]])
      block: # Add link to Pocket 
        let input_tags = @[cstring"video", "discard_tag", "pocket"]
        case checkAddToPocket(input_tags, settings)
          of Some(@tags):
            check tags.len == 1, "Expected 1, got " & $tags.len
            check tags[0] == cstring"video", "expected 'video', got '" & $tags[0] & "'"
          else: fail "got None(), expected Some(..)"
      block: # Don't add link to Pocket
        let input_tags = @[cstring"video", "discard_tag", "no-pocket"]
        let result = checkAddToPocket(input_tags, settings)
        check result.isNone(), "got Some(..), expected None()"

    proc runTestsImpl() {.async.} =
      console.info "TEST: Run"
      suite "background":
        block filter_tags:
          testCheckAddToPocket()

        block pocket_access_token:
          check test_machine.data.pocket_info.access_token.len > 0, "Invalid 'access_token'"

        block add_bookmark:
          # skip()
          await testAddBookMark()

    proc setup() {.async.} =
      console.info "TEST: Setup"
      let tags = await browser.bookmarks.getChildren(tags_folder_id)
      for tag in tags: discard browser.bookmarks.remove(tag.id)
      test_machine = newBackgroundMachine(newStateData())
      initBackgroundEvents(test_machine)
      test_machine.transition(Login, testPocketData())
      # let tabs_opts = TabCreateProps(active: true, url: browser.runtime.getURL("options/options.html"))
      # discard browser.tabs.create(tabs_opts)

    proc cleanup() {.async.} =
      console.info "TEST: Cleanup"

    proc runTestSuite() {.async, discardable.} =
      console.info "TEST: Start"
      await setup()
      try:
        await runTestsImpl()
      finally:
        await cleanup()

    runTestSuite()
