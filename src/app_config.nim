import jsffi

type
  TagInfo* = ref object
    modified*: int
    title*: cstring

  StateData* = ref object of JsRoot
    tag_ids*: seq[cstring]
    tags*: seq[TagInfo]
    config*: Config

  Config* = ref object of JsRoot
    access_token*: cstring
    username*: cstring
    always_add_tags*: bool
    add_tags*: seq[seq[cstring]]
    no_add_tags*: seq[seq[cstring]]
    enable_allowed_tags*: bool
    allowed_tags*: seq[seq[cstring]]
    enable_discard_tags*: bool
    discard_tags*: seq[seq[cstring]]
    remove_bk_tags*: seq[seq[cstring]]

proc newConfig*(
    access_token: cstring = "",
    username: cstring = "",
    always_add_tags = false,
    add_tags: seq[seq[cstring]] = @[@["pocket".cstring]],
    no_add_tags: seq[seq[cstring]] = @[@["no-pocket".cstring]],
    remove_bk_tags: seq[seq[cstring]] = @[@["only-pocket".cstring]],
    enable_allowed_tags: bool = false,
    allowed_tags: seq[seq[cstring]] = @[],
    enable_discard_tags: bool = false,
    discard_tags: seq[seq[cstring]] = @[],
): Config =
  Config(access_token: "",
      username: username,
      always_add_tags: always_add_tags,
      add_tags: add_tags,
      no_add_tags: no_add_tags,
      remove_bk_tags: remove_bk_tags,
      enable_allowed_tags: enable_allowed_tags,
      allowed_tags: allowed_tags,
      enable_discard_tags: enable_discard_tags,
      discard_tags: discard_tags)

proc newStateData*(
    tag_ids: seq[cstring] = @[],
    tags: seq[TagInfo] = @[],
    config: Config = newConfig()
  ): StateData = StateData(tag_ids: tag_ids, tags: tags, config: config)

proc get*[T](config: Config, key: cstring): T =
  cast[T](cast[JsObject](config)[key])

