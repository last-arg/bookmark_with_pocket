import jsffi, jscore

proc testOptionsData*(): JsObject =
  let data = newJsObject()
  data.always_add_pocket = false
  data.add_tags = toJs(@[
    @[cstring"tag1", "t2", "hello", "world"],
    @[cstring"tag2", "t3"]
  ])
  data.ignore_tags = toJs(@[
    @[cstring"rem_tag1", "remove", "me"],
    @[cstring"dont", "add", "me"]
  ])
  data.exclude_tags = toJs(newSeq[seq[cstring]]())
  return data

proc testPocketData*(): JsObject =
  const json_str = staticRead("../tmp/localstorage.json")
  return toJs(JSON.parse(json_str))

