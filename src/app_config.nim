import jsffi

type
  StateData* = ref object
    tag_info*: TagInfo
    pocket_info*: PocketInfo
    settings*: Settings

  TagInfo* = ref object
    ids*: seq[cstring]
    timestamps*: seq[int]

  PocketInfo* = ref object
    access_token*: cstring
    username*: cstring

  Settings* = ref object
    always_add_pocket*: bool # Default: false
    add_tags*: seq[seq[cstring]] # Default [["pocket"]]
    no_add_tags*: seq[seq[cstring]] # Default [["no-pocket"]]
    exclude_tags*: seq[seq[cstring]] # Default [["pocket"]]


proc newPocketInfo*(access_token: string = "", username: cstring = ""): PocketInfo =
  PocketInfo(access_token: access_token, username: username)

proc newSettings*(
  always_add_pocket: bool = false,
  add_tags: seq[seq[cstring]] = @[@[cstring"pocket"]],
  no_add_tags: seq[seq[cstring]] = @[@[cstring"no-pocket"]],
  exclude_tags: seq[seq[cstring]] = @[@[cstring"pocket"]],
): Settings = Settings(
    always_add_pocket: always_add_pocket,
    add_tags: add_tags,
    no_add_tags: no_add_tags,
    exclude_tags: exclude_tags,
  )

proc newStateData*(
    tag_info = TagInfo(ids: newSeq[cstring](), timestamps: newSeq[int]()),
    settings = newSettings(),
    pocket_info = newPocketInfo(),
  ): StateData = StateData(tag_info: tag_info, settings: settings, pocket_info: pocket_info)

