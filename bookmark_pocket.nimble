# Package

version = "0.1.0"
author = "last_arg"
description = "Browser extension. When adding bookmarks can also add link to pocket."
license = "MIT"
srcDir = "src"
binDir = "dist"
bin = @["bookmark_pocket"]
# skipDirs = @["balls"]

backend = "js"

# Dependencies

requires "nim >= 1.4.6"
requires "result"
requires "https://github.com/disruptek/balls >= 2.5.0 & < 3.0.0"
