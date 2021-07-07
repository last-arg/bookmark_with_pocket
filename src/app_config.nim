import jsffi

type
  LocalData* = ref LocalDataObj
  LocalDataObj* {.importc.} = object of RootObj
    access_token*: cstring
    username*: cstring
    always_add*: bool
    add_tags*: seq[seq[cstring]]
    no_add_tags*: seq[seq[cstring]]
    remove_bk_tags*: seq[seq[cstring]]
    enable_allowed_tags*: bool
    allowed_tags*: seq[seq[cstring]]
    enable_discard_tags*: bool
    discard_tags*: seq[seq[cstring]]

proc newLocalData*(
    access_token: cstring = "",
    username: cstring = "",
    always_add = false,
    add_tags: seq[seq[cstring]] = @[@["pocket".cstring]],
    no_add_tags: seq[seq[cstring]] = @[@["no-pocket".cstring]],
    remove_bk_tags: seq[seq[cstring]] = @[@["only-pocket".cstring]],
    enable_allowed_tags: bool = false,
    allowed_tags: seq[seq[cstring]] = @[],
    enable_discard_tags: bool = false,
    discard_tags: seq[seq[cstring]] = @[],
): LocalData =
  LocalData(access_token: "",
      username: username,
      always_add: always_add,
      add_tags: add_tags,
      no_add_tags: no_add_tags,
      remove_bk_tags: remove_bk_tags,
      enable_allowed_tags: enable_allowed_tags,
      allowed_tags: allowed_tags,
      enable_discard_tags: enable_discard_tags,
      discard_tags: discard_tags)

proc get*[T](config: LocalData, key: cstring): T =
  cast[T](cast[JsObject](config)[key])

