import jsffi, dom

type
  DocumentFragment* {.importc.} = ref object of Node

proc newDocumentFragment*(): DocumentFragment {.importcpp: "new DocumentFragment()", constructor.}
proc append*(df: DocumentFragment, node: Node | cstring) {.importcpp.}
proc closest*(elem: Element, selector: cstring): Element {.importcpp.}
proc Object_keys*(obj: JsObject): seq[cstring] {.importcpp: "Object.keys(#)".}
func toArray*[T](self: seq[T]): seq[T] {.importjs: "Array.from(#)".}
func isArray*(obj: JsObject): bool {.importjs: "Array.isArray(#)".}

func join*(arr: seq[cstring]; sep: cstring): cstring {.importcpp.}
func filter*[T](arr: seq[T]; fn: proc(it: T): bool {.closure.}): seq[T] {.importcpp.}
func map*[T, S](arr: seq[T]; fn: proc(it: T): S {.closure.}): seq[S] {.importcpp.}
func map*[T, S](arr: seq[T]; fn: proc(it: T, index: int): S {.closure.}): seq[S] {.importcpp: "#.map(#)".}

