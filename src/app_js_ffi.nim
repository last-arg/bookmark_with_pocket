func split*(pattern: cstring; self: cstring): seq[cstring] {.
    importcpp: "#.split(#)".}
func join*(arr: seq[cstring]; sep: cstring): cstring {.importcpp.}
func filter*[T](arr: seq[T]; fn: proc(it: T): bool {.closure.}): seq[T] {.importcpp.}
func map*[T, S](arr: seq[T]; fn: proc(it: T): S {.closure.}): seq[S] {.importcpp.}
func concat*[T](seqs: varargs[seq[T]]): seq[T] {.importcpp.}
func trim*(s: cstring): cstring {.importcpp.}

