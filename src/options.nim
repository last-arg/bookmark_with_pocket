import jsconsole, asyncjs, dom, jsffi
import web_ext_browser, app_config, app_js_ffi

console.log "Options Page"

type
  FormData* = ref FormDataObj
  FormDataObj {.importc.} = object of RootObj

  # TODO: can also return File
  FormDataEntryValue = cstring

# TODO?: use FormElement instead
proc newFormData(elem: Element): FormData {.importcpp: "new FormData(@)".}
proc get(fd: FormData, key: cstring): FormDataEntryValue {.importcpp.}

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

import macros
const form_fields: tuple[bools: seq[cstring], cstrings: seq[
    cstring], tags: seq[cstring]] = block:
  var bools: seq[cstring] = @[]
  var cstrings: seq[cstring] = @[]
  var tags: seq[cstring] = @[]
  # echo "Type declartaion is: ", LocalData.getTypeImpl[0].getTypeImpl.treerepr
  for item in LocalData.getTypeImpl[0].getTypeImpl[2]:
    # echo item[0]
    let field_name = $item[0]
    if item[1].kind == nnkSym:
      if $item[1] == "bool":
        bools.add(field_name)
      elif $item[1] == "cstring":
        cstrings.add(field_name)
      else:
        echo "unknown field type in LocalData -> " & $item[0] & ": " & $item[1]
        # TODO: add somekind of error/exception message
    elif item[1].kind == nnkBracketExpr and item[1].repr == "seq[seq[cstring]]":
      tags.add(field_name)
    else:
      echo "unknown field type in LocalData -> " & $item[0] & ": " & $item[1]
      # TODO: add somekind of error/exception message

  (bools, cstrings, tags)

proc get[T](config: LocalData, key: cstring): T =
  cast[T](cast[JsObject](config)[key])

proc saveOptions(ev: Event) {.async.} =
  ev.preventDefault()
  var config = cast[LocalData](
    await browser.storage.local.get(
      form_fields.bools.concat(form_fields.tags)))
  let options = newFormData(cast[Element](ev.target))
  for key in form_fields.bools:
    cast[JsObject](config)[key] = options.get(key) == "on"

  for key in form_fields.tags:
    cast[JsObject](config)[key] = optionTagToSeq(options.get(key))

  discard await browser.storage.local.set(cast[JsObject](config))

  # Make textarea/input values look uniform/good
  for key in form_fields.tags:
    let elem = ev.target.querySelector("#" & key)
    elem.value = tagOptionsToString(get[seq[seq[cstring]]](config, key))


proc init() {.async.} =
  console.log form_fields
  let storage = await browser.storage.local.get()
  var config = cast[LocalData](storage)

  if storage == jsUndefined or storage["access_token"] == jsUndefined:
    let not_logged_in_elem = document.querySelector(".js-not-logged-in")
    not_logged_in_elem.classList.remove("hidden")
    let login_button_elem = not_logged_in_elem.querySelector(".js-login")
    login_button_elem.addEventListener("click", proc(_: Event) =
      console.log "TODO: login to pocket"
    )
    console.warn("Could not find web extension local config. Generating new config")
    config = newLocalData()

  # TODO?: generate form fields from form_fields variable

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

