import jsffi
# TODO: clean/remove code. Might have some overlap with https://github.com/juancarlospaco/nodejs
# func split*(pattern: cstring; self: cstring): seq[cstring] {.
#     importcpp: "#.split(#)".}
func join*(arr: seq[cstring]; sep: cstring): cstring {.importcpp.}
func filter*[T](arr: seq[T]; fn: proc(it: T): bool {.closure.}): seq[T] {.importcpp.}
func map*[T, S](arr: seq[T]; fn: proc(it: T): S {.closure.}): seq[S] {.importcpp.}
func map*[T, S](arr: seq[T]; fn: proc(it: T, index: int): S {.closure.}): seq[S] {.importcpp: "#.map(#)".}
func concat*[T](seqs: varargs[seq[T]]): seq[T] {.importcpp.}
func toArray*[T](self: seq[T]): seq[T] {.importjs: "Array.from(#)".}
func isArray*(obj: JsObject): bool {.importjs: "Array.isArray(#)".}
