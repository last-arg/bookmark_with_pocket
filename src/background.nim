import dom, jsffi, asyncjs
import jsconsole
import web_ext_browser, bookmarks, app_config, app_js_ffi, pocket, common
import results

proc initBackground*() {.async.} =
  console.log "BACKGROUND"

  when defined(testing):
    # await browser.runtime.openOptionsPage()
    let query_opts = newJsObject()
    query_opts["url"] = "moz-extension://*/options/options.html".cstring
    let query_tabs = await browser.tabs.query(query_opts)
    if query_tabs.len > 0:
      discard browser.tabs.reload(query_tabs[0].id, newJsObject())

  let storage = await browser.storage.local.get()
  g_status.config = cast[Config](storage)

  # let is_logged_in = not (storage == jsUndefined and storage["access_token"] == jsUndefined)
  let is_logged_in = false
  if is_logged_in:
    initLoggedIn()
  else:
    initLoggedOut()

browser.runtime.onInstalled.addListener(proc(details: InstalledDetails) =
  console.log "ONINSTALLED EVENT"
  if details.reason == "install":
    proc install() {.async.} =
      let local_data = cast[JsObject](newConfig())
      discard await browser.storage.local.set(local_data)
      console.log "set storage.local"
      await browser.runtime.openOptionsPage()
    discard install()
)

when isMainModule:
  when defined(release):
    console.log "BACKGROUND RELEASE BUILD"
    discard initBackground()

  when defined(testing):
    import balls, jscore, web_ext_browser

    # IMPORTANT: Test functions use global variable 'g_status'
    console.log "BACKGROUND TESTING(DEBUG) BUILD"

    proc createTags(tags: seq[cstring]): Future[void] {.async.} =
      for tag in tags:
        let details = newCreateDetails(title = tag, `type` = "folder",
            parentId = tags_folder_id)
        let tag = await browser.bookmarks.create(details)

    proc getAddedTags(tags: seq[BookmarkTreeNode]): seq[cstring] =
      var r: seq[cstring] = @[]
      for tag in tags:
        let id_index = find[seq[cstring], cstring](g_status.tag_ids, tag.id)
        if id_index == -1:
          r.add(tag.title)
        elif tag.dateGroupModified != g_status.tags[id_index].modified:
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

      g_status.config.discard_tags.add(@[@["discard_tag".cstring], @[
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
      let pocket_status = cast[int](pocket_link.g_status)
      check pocket_status == 1, "pocket_link g_status failed"

      # Check that link was added to pocket
      let links_result = await retrieveLinks(g_status.config.access_token,
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
      let del_result = await modifyLink(g_status.config.access_token, action)
      check del_result.isOk()
      let del_value = del_result.value()
      let del_status = cast[int](del_value.g_status)
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
          g_status.config.access_token, url_to_add)
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
          skip()
          check g_status.config.access_token.len > 0, "'access_token' was not found in extension local storage"

        block add_bookmark:
          skip()
          await testAddBookMark()


    proc setup() {.async.} =
      await browser.storage.local.clear()
      console.info "Tests setup"
      g_status = newStatus(
        config = newConfig(
          add_tags = @[@["pocket".cstring], @[
              "second".cstring, "third".cstring]]))
      const json_str = staticRead("../tmp/localstorage.json")
      let local_value = cast[JsObject](JSON.parse(json_str))
      g_status.config.access_token = cast[cstring](local_value.access_token)
      g_status.config.username = cast[cstring](local_value.username)
      discard await browser.storage.local.set(cast[JsObject](g_status.config))
      await createTags(@["pocket".cstring, "book", "hello", "video",
          "discard_tag"])
      let tabs_opts = TabCreateProps(url: browser.runtime.getURL("options/options.html"))
      discard browser.tabs.create(tabs_opts)

    proc cleanup() {.async.} =
      console.info "Tests cleanup"
      for id in g_status.tag_ids:
        await browser.bookmarks.remove(id)
      for id in created_bk_ids:
        await browser.bookmarks.remove(id)

    proc runTestSuite() {.async, discardable.} =
      console.info "Start test suite"
      await setup()
      await initBackground()
      # document.addEventListener("DOMContentLoaded", proc(
      #     _: Event) = console.log "content loaded"; discard initBackground())
      try:
        await runTestsImpl()
      finally:
        await cleanup()

    runTestSuite()
