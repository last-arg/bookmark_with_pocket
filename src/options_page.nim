import jsconsole, asyncjs, dom
import jsffi except `&`
import web_ext_browser, app_config, pocket
import app_js_ffi
import badresults
import nodejs/jscore

proc saveOptions(el: FormElement) {.async.} =
  let localData = newJsObject()
  let rule_sections = el.querySelectorAll("tag-rules")
  var usedNames = newSeq[cstring]()
  for section in rule_sections:
    let name = section.querySelector("[name]").name
    usedNames.add(name)
    localData[name] = block:
      let inputs = section.querySelectorAll("[name=" & name & "]")
      inputs.toArray().map(proc(el: Element): seq[cstring] =
        el.value.split(",")
          .map(proc(val: cstring): cstring = val.strip())
          .filter(proc(val: cstring): bool = val.len > 0)
      )

  let selector_list = usedNames.map(proc(value: cstring): cstring = "[name=" & value & "]").join(",")
  let other_inputs = el.querySelectorAll("[name]:not(" & selector_list & ")")
  for input in other_inputs:
    # NOTE: at the moment rest of inputs should only be checkboxes
    localData[input.name] = input.checked

  let msg = newJsObject()
  msg["cmd"] = cstring "update_settings"
  msg["data"] = localData
  discard browser.runtime.sendMessage(msg)
  discard await browser.storage.local.set(localData)


const event_once_opt = AddEventListenerOptions(once: true, capture: false,
    passive: false)

proc initLogoutButton()
proc initLoginButton() =
  let js_login = document.querySelector(".js-not-logged-in")
  js_login.classList.remove("hidden")
  let login_button_elem = js_login.querySelector(".js-login")
  login_button_elem.addEventListener("click", proc(_: Event) =
    proc asyncCb() {.async.} =
      let pocket_info = await authenticate()
      if pocket_info.isErr():
        console.error("Pocket authentication failed")
        initLoginButton()
        return
      discard browser.storage.local.set(toJs(pocket_info.value()))

      initLogoutButton()
      js_login.classList.add("hidden")
      let msg = newJsObject()
      msg["cmd"] = cstring "login"
      msg["data"] = pocket_info.value()
      discard browser.runtime.sendMessage(msg)
    discard asyncCb()
  , event_once_opt)

proc initLogoutButton() =
  let js_logout = document.querySelector(".js-logout")
  js_logout.classList.remove("hidden")
  js_logout.addEventListener("click", proc(_: Event) =
    const empty_string = cstring ""
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


proc setRuleNodeValues(node: Node, tag_name: cstring, default_value: cstring = "") =
  node.querySelector("label[for]").setAttribute("for", tag_name) 
  let tagsElem = node.querySelector("input[type=text]")
  tagsElem.id = tag_name
  tagsElem.defaultValue = default_value
  tagsElem.value = default_value

proc handleTagRules(ev: Event) =
  let elem = cast[Element](ev.target)
  if elem.nodeName != "BUTTON": return

  if elem.classList.contains("js-new-rule"):
    let custom_elem = elem.closest("tag-rules")
    let ulElem = custom_elem.querySelector("ul")
    if ulElem.classList.contains("hidden"):
      ulElem.classList.remove("hidden")
      ulElem.querySelector("input[type='text']").focus()
    else:
      let liElem = to(toJs(ulElem).lastElementChild, Element)
      let newNode = liElem.cloneNode(true)
      let labelElem = newNode.querySelector("label[for]")
      let new_name = block:
        let name_tmp = labelElem.getAttribute("for")
        let start_index = name_tmp.lastIndexOf(cstring"_") + 1
        let new_index = block:
          let index = parseInt(name_tmp.slice(cint(start_index), cint(name_tmp.len)))
          if isNan(cast[BiggestFloat](index)): 0 else: index + 1
        name_tmp.slice(cint(0), cint(start_index)) & cstring($new_index)
      setRuleNodeValues(newNode, new_name)
      ulElem.appendChild(newNode)
      labelElem.focus()
  elif elem.classList.contains("js-remove-rule"):
    # TODO: where to put focus after element removal?
    let ul_elem = elem.closest("ul")
    if ul_elem.children.len > 1:
      elem.closest("li").remove()
    else:
      ul_elem.classList.add("hidden")
      ul_elem.querySelector("input[type='text']").value = ""
  else:
    console.error "Unhandled button was pressed"


proc renderAll(base_id: cstring, node: Node, rules: seq[seq[cstring]]): DocumentFragment =
  let df = newDocumentFragment()
  for i, tags in rules:
    let tagName = base_id & "_" & cstring($i)
    let newNode = node.cloneNode(true)
    setRuleNodeValues(newNode, tagName, tags.join(", "))
    df.append newNode

  return df


proc tagRulesConnectedCallback(el: Element) {.async.} =
  let baseItem = el.querySelector("ul > li")
  let storageKey = baseItem.querySelector("input[type=text]").name
  let config = await browser.storage.local.get(storageKey)
  let rules = to(config[storageKey], seq[seq[cstring]])
  if not isUndefined(rules) and rules.len > 0:
    let df = renderAll(storageKey, baseItem.cloneNode(true), rules)
    el.querySelector("ul").prepend(df)
    baseItem.remove()
  else:
    let new_name = baseItem.querySelector("label[for]").getAttribute("for") & "_0"
    el.querySelector("ul").classList.add("hidden")
    setRuleNodeValues(baseItem, new_name)


proc init() {.async.} =
  type StoragePocket = object
    access_token: cstring
  let storage = block:
    let promise_result = await browser.storage.local.get(cstring"access_token")
    to(promise_result, StoragePocket)

  if isUndefined(storage) or isUndefined(storage.access_token):
    initLoginButton()
  else:
    initLogoutButton()

  let form_elem = cast[FormElement](document.querySelector(".options"))

  form_elem.addEventListener("submit", proc(ev: Event) =
    ev.preventDefault()
    discard saveOptions(cast[FormElement](ev.target))
  )

{.emit: """
class TagRules extends HTMLElement {
  constructor() {
    super()
    this.addEventListener("click", `handleTagRules`)
  }
  async connectedCallback() {
    `tagRulesConnectedCallback`(this)
  }
}

customElements.define("tag-rules", TagRules);
""".}


when isMainModule:
  document.addEventListener("DOMContentLoaded", proc(_: Event) = discard init())

  # Testing
  when defined(testing) or defined(debug):
    import test_utils

    proc debugInit() {.async.} =
      document.querySelector("#options-page").setAttribute("href", browser.runtime.getURL("options/options.html"))
      let debug_div = document.createElement("div")
      debug_div.classList.add("debug")
      let debug_style = document.createElement("style")
      toJs(debug_style).type = cstring"text/css"
      debug_style.appendChild(document.createTextNode(cstring"""
        .debug {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: 1rem;
        }
        .debug button {
          padding: 6px 8px;
          background: #ddd;
        }
        .debug button:hover {
          background: #ccc;
        }
      """))
      document.head.appendChild(debug_style)
      let debug_p = document.createElement("p")
      debug_p.textContent = "Debug buttons:"
      debug_div.appendChild(debug_p)

      let add_test_data = document.createElement("button")
      add_test_data.textContent = "Add options test data"
      add_test_data.addEventListener("click", proc(_: Event) =
        proc run() {.async.} = discard await browser.storage.local.set(testOptionsData())
        discard run()
      )
      debug_div.appendChild(add_test_data)

      let rm_test_data = document.createElement("button")
      rm_test_data.textContent = "Remove options test data"
      rm_test_data.addEventListener("click", proc(_: Event) =
        proc run() {.async.} = discard await browser.storage.local.remove(Object_keys(testOptionsData()))
        discard run()
      )
      debug_div.appendChild(rm_test_data)

      document.body.insertBefore(debug_div, document.body.firstChild)

      discard await browser.storage.local.set(testPocketData())

    discard debugInit()

