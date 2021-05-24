import jsffi, dom, asyncjs, jsconsole
import pocket

proc eventPocketLogin(elem: Element)
proc eventPocketLogout(elem: Element)

proc isLoggedIn*(): bool =
  let access_token = window.localStorage.getItem("access_token")
  return not access_token.isNull()

proc pocketLogout() =
  window.localStorage.removeItem("username")
  window.localStorage.removeItem("access_token")

proc eventPocketLoginAsnyc(elem: Element) {.async.} =
  await pocketLogin()
  console.log "After Pocket login"
  elem.classList.add("hidden")
  let logout_pocket = document.querySelector(".logout-pocket")
  logout_pocket.classList.remove("hidden")
  eventPocketLogout(logout_pocket)

proc eventPocketLogin(elem: Element) =
  console.log "handle login"
  elem.addEventListener("click", proc(_: Event) =
    discard eventPocketLoginAsnyc(elem)
  , AddEventListenerOptions(once: true))

proc eventPocketLogout(elem: Element) =
  elem.addEventListener("click", proc(_: Event) =
    pocketLogout()
    elem.classList.add("hidden")
    let login_pocket = document.querySelector(".login-pocket")
    login_pocket.classList.remove("hidden")
    eventPocketLogin(login_pocket)
  , AddEventListenerOptions(once: true))

proc init*() {.async.} =
  let logout_pocket = document.querySelector(".logout-pocket")
  let login_pocket = document.querySelector(".login-pocket")
  if isLoggedIn():
    logout_pocket.classList.remove("hidden")
    eventPocketLogout(logout_pocket)
  else:
    login_pocket.classList.remove("hidden")
    eventPocketLogin(login_pocket)

when isMainModule:
  console.log "main"
  document.addEventListener("DOMContentLoaded", proc(_: Event) = init())
