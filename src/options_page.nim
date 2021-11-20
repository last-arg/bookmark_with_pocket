import jsconsole, asyncjs, dom, jsffi, std/jsformdata
import web_ext_browser, app_config, app_js_ffi, pocket
import badresults

# NOTE: std/jsformdata doesn't have version with FormElement
proc newFormData(elem: FormElement): FormData {.importcpp: "new FormData(@)".}
# Can return null if key doesn't exist
# Use std/jsformdata function `[]`
proc get(self: FormData; name: cstring): cstring = self[name]

proc tagOptionsToString(tags: seq[seq[cstring]]): cstring =
  return tags.map(
    proc(it: seq[cstring]): cstring = it.join(", ")
  ).join("\n")

proc optionTagToSeq(s: cstring): seq[seq[cstring]] =
  return s.split("\n")
    .map(proc(it: cstring): seq[cstring] =
      it.split(",")
      .map(proc(val: cstring): cstring = val.trim())
      .filter(proc(val: cstring): bool = val.len > 0))
    .filter(proc(row: seq[cstring]): bool = row.len > 0)

import macros, os
const form_fields: tuple[bools: seq[cstring]; tags: seq[cstring]] = block:
  var bools: seq[cstring] = @[]
  var tags: seq[cstring] = @[]
  # echo "Type declartaion is: ", Config.getTypeImpl[0].getTypeImpl.treerepr
  for item in Config.getTypeImpl[0].getTypeImpl[2]:
    let field_name = $item[0]
    let config_type = item[1]
    if config_type.kind == nnkSym:
      if $config_type == "bool":
        bools.add(field_name)
      elif $config_type == "cstring":
        # cstring fields aren't used in html form
        continue
      else:
        raise newException(ValueError, "[WARN] unknown field type in Config -> " &
            $field_name & ": " & $config_type)
    elif config_type.kind == nnkBracketExpr and config_type.repr == "seq[seq[cstring]]":
      tags.add(field_name)
    else:
        raise newException(ValueError, "[WARN] unknown field type in Config -> " &
            $field_name & ": " & $config_type)

  (bools, tags)

proc saveOptions(ev: Event) {.async.} =
  ev.preventDefault()
  var config = cast[Config](
    await browser.storage.local.get(
      form_fields.bools.concat(form_fields.tags)))
  let options = newFormData(cast[FormElement](ev.target))
  for key in form_fields.bools:
    cast[JsObject](config)[key] = options.get(key) == "on"

  for key in form_fields.tags:
    cast[JsObject](config)[key] = optionTagToSeq(options.get(key))

  discard await browser.storage.local.set(cast[JsObject](config))

  # Make textarea/input values look uniform/good
  for key in form_fields.tags:
    let elem = ev.target.querySelector("#" & key)
    elem.value = tagOptionsToString(get[seq[seq[cstring]]](config, key))


const event_once_opt = AddEventListenerOptions(once: true, capture: false,
    passive: false)

proc initLogoutButton()
proc initLoginButton() =
  let js_login = document.querySelector(".js-not-logged-in")
  js_login.classList.remove("hidden")
  let login_button_elem = js_login.querySelector(".js-login")
  login_button_elem.addEventListener("click", proc(_: Event) =
    proc asyncCb() {.async.} =
      let body_result = await authenticate()
      if body_result.isErr():
        console.error("Pocket authentication failed")
        initLoginButton()
        return
      # Deconstruct urlencoded data
      let kvs = body_result.value.split("&")
      var login_data = newJsObject()
      const username = "username"
      const access_token = "access_token"
      login_data[access_token] = nil
      login_data[username] = nil
      for kv_str in kvs:
        let kv = kv_str.split("=")
        if kv[0] == access_token:
          login_data[access_token] = kv[1]
        elif kv[0] == username:
          login_data[username] = kv[1]

      if login_data[access_token] == nil:
        console.error("Failed to get access_token form Pocket API response")
        initLoginButton()
        return

      initLogoutButton()
      js_login.classList.add("hidden")
      let msg = newJsObject()
      msg["cmd"] = "login".cstring
      msg["data"] = login_data
      discard browser.runtime.sendMessage(msg)
    discard asyncCb()
  , event_once_opt)

proc initLogoutButton() =
  let js_logout = document.querySelector(".js-logout")
  js_logout.classList.remove("hidden")
  js_logout.addEventListener("click", proc(_: Event) =
    const empty_string = "".cstring
    let login_info = newJsObject()
    login_info.username = empty_string
    login_info.access_token = empty_string
    discard browser.storage.local.set(login_info)
    initLoginButton()
    js_logout.classList.add("hidden")
    let msg = newJsObject()
    msg["cmd"] = "logout".cstring
    discard browser.runtime.sendMessage(msg)
  , event_once_opt)

proc init() {.async.} =
  console.log form_fields
  let storage = await browser.storage.local.get()
  console.log storage
  var config = cast[Config](storage)

  if storage == jsUndefined and storage["access_token"] == jsUndefined:
    initLoginButton()
    console.warn("Could not find web extension local config. Generating new config")
    config = newConfig()
  else:
    initLogoutButton()

  let form_elem = document.querySelector(".options")

  for key in form_fields.bools:
    let elem = form_elem.querySelector("#" & key)
    elem.checked = get[bool](config, key)

  for key in form_fields.tags:
    let elem = form_elem.querySelector("#" & key)
    elem.value = tagOptionsToString(get[seq[seq[cstring]]](config, key))

  form_elem.addEventListener("submit", proc(ev: Event) =
    ev.preventDefault()
    discard saveOptions(ev)
  )

when isMainModule:
  document.addEventListener("DOMContentLoaded", proc(_: Event) = discard init())
