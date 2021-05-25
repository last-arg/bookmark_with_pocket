import asyncjs, jsffi, dom
import jsconsole
import balls
import results
import ../src/pocket, ../src/main

proc includes*(s: cstring, c: cstring): bool {.importcpp: "#.includes(#)".}

proc create*(obj: JsObject): Future[JsObject] {.
    importcpp: "browser.tabs.create(#)".}

proc initTest(): Future[void] {.async.} =
  suite "pocket":
    let token = window.localStorage.getItem("access_token")
    block pocket_access_token:
      assert not token.isNull()

    let link_result = await addLink("https://google.com", token)

    block pocket_add_link:
      assert link_result.isOk()
      console.log link_result.value()


proc loaded(e: Event) =
  discard init()
  discard initTest()


document.addEventListener("DOMContentLoaded", loaded)

