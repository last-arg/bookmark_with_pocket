# Package

version = "0.1.0"
author = "last_arg"
description = "Browser extension. When adding bookmarks can also add link to pocket."
license = "MIT"
srcDir = "src"
binDir = "dist"
bin = @["bookmark_with_pocket"]
skipDirs = @["balls"]

# backend = "js"

# Dependencies

requires "nim >= 1.6.0"
requires "fusion#head"
requires "https://github.com/disruptek/badresults >= 2.1.0"
requires "https://github.com/disruptek/balls >= 3.0.0"
