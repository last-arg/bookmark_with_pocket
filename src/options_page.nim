import jsconsole, asyncjs, dom
import jsffi except `&`
import web_ext_browser, app_config, pocket
import app_js_ffi
import badresults
import nodejs/[jsstrformat]
import nodejs/jscore
import jscore as stdjscore

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


proc setRuleNodeValues(node: Node, tag_name: cstring, default_value: cstring = "") =
  node.querySelector("label[for]").setAttribute("for", tag_name) 
  let tagsElem = node.querySelector("input[type=text]")
  tagsElem.id = tag_name
  tagsElem.defaultValue = default_value
  tagsElem.value = default_value

proc createRuleId(rule_prefix: cstring, index: int): cstring = rule_prefix & "_tags" & "_" & $index

proc handleTagRules(ev: Event) =
  let elem = cast[Element](ev.target)
  if elem.nodeName != "BUTTON": return

  if elem.classList.contains("js-new-rule"):
    let fieldSetElem = elem.closest("tag-rules")
    let rulesName = fieldSetElem.getAttribute("rules-prefix")
    let ulElem = fieldSetElem.querySelector("ul")
    let liElem = cast[Element](cast[JsObject](ulElem).lastElementChild)
    let newNode = liElem.cloneNode(true)
    let next_index = block:
      let values = newNode.querySelector("label[for]").getAttribute("for").split("_")
      var result = 0
      if values.len == 3:
        let int_val = parseInt(values[2])
        if not isNan(cast[BiggestFloat](int_val)):
          result = int_val + 1
      result 
    setRuleNodeValues(newNode, createRuleId(rulesName, next_index))
    ulElem.appendChild(newNode)
  elif elem.classList.contains("js-remove-rule"):
    elem.closest("li").remove()
  else:
    console.error "Unhandled button was pressed"


proc renderAll(base_id: cstring, node: Node, rules: seq[seq[cstring]]): DocumentFragment =
  let df = newDocumentFragment()
  for i, tags in rules:
    let tagName = base_id & "_" & $i
    let newNode = node.cloneNode(true)
    setRuleNodeValues(newNode, tagName, tags.join(", "))
    df.append newNode

  return df


proc tagRulesConnectedCallback(el: Element) {.async.} =
  let rulesName = el.getAttribute("rules-prefix")
  if isNull(rulesName):
    console.error("Custom element 'tag-rules' is missing attribute 'rules-prefix'")
    return
  let baseItem = el.querySelector("ul > li")
  let storageKey = baseItem.querySelector("input[type=text]").name
  let config = await browser.storage.local.get(storageKey)
  let rules = cast[seq[seq[cstring]]](config[storageKey])
  if rules.len > 0:
    let df = renderAll(storageKey, baseItem.cloneNode(true), rules)
    el.querySelector("ul").prepend(df)
    baseItem.remove()
  else:
    setRuleNodeValues(baseItem, createRuleId(rulesName, 0))


proc init() {.async.} =
  let storage = await browser.storage.local.get()
  var config = cast[Config](storage)

  if storage == jsUndefined and storage["access_token"] == jsUndefined:
    initLoginButton()
    console.warn("Could not find web extension local config. Generating new config")
    config = newConfig()
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
    proc testAddRules() {.async, discardable.} =
      let test_data = newJsObject()
      test_data.add_tags = toJs(@[
        @[cstring"tag1", "t2", "hello", "world"],
        @[cstring"tag2", "t3"]
      ])
      test_data.add_remove_tags = toJs(@[false, true])
      discard await browser.storage.local.set(test_data)

    proc testRules() {.async, discardable.} =
      let test_data = newJsObject()
      test_data.ignore_tags = toJs(@[
        @[cstring"rem_tag1", "remove", "me"],
        @[cstring"dont", "add", "me"]
      ])
      discard await browser.storage.local.set(test_data)

    proc addRemoveStorageBtn(rule_name: cstring, add_cb: proc(): Future[void]): array[2, Element] =
      let add_rule_btn = document.createElement("button")
      add_rule_btn.textContent = "Add '" & rule_name & "' test data"
      add_rule_btn.addEventListener("click", proc(_: Event) = discard add_cb())

      let remove_rule_btn = document.createElement("button")
      remove_rule_btn.textContent = "Remove '" & rule_name & "' test data"
      remove_rule_btn.addEventListener("click", proc(_: Event) =
        discard browser.storage.local.remove(rule_name))

      return [add_rule_btn, remove_rule_btn]

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

      for btn in addRemoveStorageBtn("add_tags", testAddRules):
        debug_div.appendChild(btn)

      for btn in addRemoveStorageBtn("ignore_tags", testRules):
        debug_div.appendChild(btn)

      document.body.insertBefore(debug_div, document.body.firstChild)
      block:
        const json_str = staticRead("../tmp/localstorage.json")
        let local_value = toJs(stdjscore.JSON.parse(json_str))
        discard await browser.storage.local.set(toJs(local_value))

      # discard setTimeout(proc() =
      #   let form_elem = cast[FormElement](document.querySelector(".options"))
      #   discard saveOptions(form_elem)
      # , 50)

    discard debugInit()

