import jsffi, dom, asyncjs, jsconsole
import results
import pocket

proc eventPocketLogin(elem: Element)
proc eventPocketLogout(elem: Element)

proc isLoggedIn*(): bool =
  let access_token = window.localStorage.getItem("access_token")
  return not access_token.isNull()

proc pocketLogin*(): Future[void] {.async.} =
  const user_key = "username"
  const token_key = "access_token"
  var token = window.localStorage.getItem(token_key)

  if token.isNull():
    console.log "Authenticating Pocket"
    let body_result = await authenticate()
    if body_result.isErr():
      console.error("Pocket authentication failed")
      return
    let body = body_result.value
    const key = 0
    const value = 1
    var has_access_token = false
    let kvs = body.split "&"
    for kv_str in kvs:
      let kv = kv_str.split "="
      if kv[key] == token_key:
        has_access_token = true
        token = kv[value]
        window.localStorage.setItem(token_key, token)
      elif kv[key] == user_key:
        window.localStorage.setItem(user_key, kv[value])

    if not has_access_token:
      console.error "Login to Pocket failed. Response body didn't contain access_token field/key"
      return

  console.log token

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
