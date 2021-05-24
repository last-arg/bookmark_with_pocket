import asyncjs, jsffi, dom
import jsconsole
import balls
import ../src/pocket, ../src/main

proc includes*(s: cstring, c: cstring): bool {.importcpp: "#.includes(#)".}

proc create*(obj: JsObject): Future[JsObject] {.
    importcpp: "browser.tabs.create(#)".}

proc asyncFn(): Future[void] {.async.} =
  let login_pocket = document.querySelector(".login-pocket")
  # login_pocket.addEventListener("click", proc(
  #     ev: Event) = discard loginToPocket())

proc loaded(e: Event) =
  discard init()

document.addEventListener("DOMContentLoaded", loaded)

