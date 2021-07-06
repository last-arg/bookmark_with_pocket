func split*(pattern: cstring; self: cstring): seq[cstring] {.
    importcpp: "#.split(#)".}

