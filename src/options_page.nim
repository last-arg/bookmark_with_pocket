import jsconsole, asyncjs, dom
import jsffi except `&`
import web_ext_browser, app_config, pocket
import app_js_ffi
import badresults
import nodejs/[jsstrformat, jscore]

type
  DocumentFragment {.importc.} = ref object of Node

proc newDocumentFragment*(): DocumentFragment {.importcpp: "new DocumentFragment()", constructor.}
proc append(df: DocumentFragment, node: Node | cstring) {.importcpp.}
proc closest*(elem: Element, selector: cstring): Element {.importcpp.}

proc saveOptions(el: FormElement) {.async.} = jsFmt:
  var add_rules: seq[AddRule] = @[]
  let elems = el.querySelectorAll("[name=add_tags], [name=add_ignore_tags]")
  assert(elems.len mod 2 == 0, "Rules: add Pocket link must contain even number of fields")
  let half_len = elems.len div 2
  for i in 0..<half_len:
    let i_tags = i * 2 
    let i_ignore_tags = i_tags + 1
    let tags_elem {.exportc.} = elems[i_tags]
    let checkbox_elem {.exportc.} = elems[i_ignore_tags]
    assert tags_elem.name == "add_tags",
      $fmt"Unexpected field name '${tags_elem.name}'. Expected field name 'add_tags'"
    assert(checkbox_elem.name == "add_ignore_tags",
      $fmt"Unexpected field name '${checkbox_elem.name}'. Expected field name 'add_ignore_tags'")

    let tags = tags_elem.value.split(",")
      .map(proc(val: cstring): cstring = val.strip())
      .filter(proc(val: cstring): bool = val.len > 0)
    # Don't add rules with no tags
    if tags.len == 0: continue
    add_rules.add AddRule(tags: tags, ignore_tags: checkbox_elem.checked)

  let config = newJsObject()
  config.add_rules = toJs(add_rules)
  discard await browser.storage.local.set(config)


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


proc addRuleNodeReset(rules_name: cstring, index: int, node: Node) =
  let tagName = rules_name & "_tags" & "_" & $index
  node.querySelector("label[for]").setAttribute("for", tagName) 
  let tagsElem = node.querySelector("textarea")
  tagsElem.id = tagName
  tagsElem.defaultValue = ""
  tagsElem.value = ""
  if rules_name == "add":
    let checkboxElem = node.querySelector("input[type=checkbox]")
    checkboxElem.defaultChecked = false
    checkboxElem.checked = false


proc handleTagRules(ev: Event) =
  let elem = cast[Element](ev.target)
  if elem.nodeName != "BUTTON": return

  if elem.classList.contains("js-new-rule"):
    let fieldSetElem = elem.closest("fieldset")
    let ulElem = fieldSetElem.querySelector("ul")
    let rulesName = fieldSetElem.getAttribute("rules-name")
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
    addRuleNodeReset(rulesName, next_index, newNode)
    ulElem.appendChild(newNode)
  elif elem.classList.contains("js-remove-rule"):
    elem.closest("li").remove()
  else:
    console.error "Unhandled button was pressed"

proc renderAll(name: cstring, node: Node, rules: seq[AddRule]): DocumentFragment =
  let tagNameBase = name & "_tags"
  let ignoreTagsNameBase = name & "_ignore_tags"

  let df = newDocumentFragment()
  for i, rule in rules:
    let tagName = tagNameBase & "_" & $i
    let newNode = node.cloneNode(true)
    newNode.querySelector("label[for]").setAttribute("for", tagName) 
    let tagsElem = newNode.querySelector("textarea")
    tagsElem.id = tagName
    tagsElem.defaultValue = rule.tags.join ", "
    if name == "add":
      newNode.querySelector("input[type=checkbox]").defaultChecked = rule.ignore_tags

    df.append newNode

  return df



proc init() {.async.} =
  let storage = await browser.storage.local.get()
  console.log "storage", storage
  var config = cast[Config](storage)

  if storage == jsUndefined and storage["access_token"] == jsUndefined:
    initLoginButton()
    console.warn("Could not find web extension local config. Generating new config")
    config = newConfig()
  else:
    initLogoutButton()

  let form_elem = cast[FormElement](document.querySelector(".options"))

  # for key in form_fields.bools:
  #   let elem = form_elem.querySelector("#" & key)
  #   elem.checked = get[bool](config, key)

  # for key in form_fields.tags:
  #   let elem = form_elem.querySelector("#" & key)
  #   elem.value = tagOptionsToString(get[seq[seq[cstring]]](config, key))

  form_elem.addEventListener("submit", proc(ev: Event) =
    ev.preventDefault()
    discard saveOptions(cast[FormElement](ev.target))
  )

  # block:
    # # @debug
    # let test = newJsObject()
    # test.add_rules = toJs(@[
    #   AddRule(tags: @[cstring"tag1", "t2", "hello", "world"], ignore_tags: true),
    #   AddRule(tags: @[cstring"tag2", "t3"], ignore_tags: false)
    # ])
    # discard await browser.storage.local.set(test)

  {.emit: """
  class TagRules extends HTMLFieldSetElement {
    constructor() {
      super()
      this.addEventListener("click", `handleTagRules`)
    }

    async connectedCallback() {
      const rulesName = this.getAttribute("rules-name")
      if (!rulesName) {
        console.error("Extended custom element tag-rules is missing attribute rules-name")
        return
      }
      const rulesKey = rulesName + "_rules"
      const config = await browser.storage.local.get(rulesKey)
      const baseItem = this.querySelector("ul > li")
      const df = `renderAll`(rulesName, baseItem.cloneNode(true), config.add_rules)
      if (df.children.length) {
        baseItem.remove()
      } else {
        `addRuleNodeReset`(rulesName, df.children.length, baseItem)
      }
      this.querySelector("ul").prepend(df)
    }
  }

  customElements.define("tag-rules", TagRules, {extends: "fieldset"});
  """.}



when isMainModule:
  document.addEventListener("DOMContentLoaded", proc(_: Event) = discard init())
  when defined(testing) or defined(debug):
    document.querySelector("#options-page").setAttribute("href", browser.runtime.getURL("options/options.html"))


