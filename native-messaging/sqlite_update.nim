# import jsony
import streams
import strutils
import os
import db_sqlite
import json

# IMPORTANT NOTE:
# Have to make separate env for nim compiler to find sqlite
# In terminal run:
# nix-shell -p sqlite
# Inside nix-shell run:
# watchexec -r -w sqlite_update.nim 'nim c sqlite_update.nim'

proc main() =
  var msg = "failed"
  var profiles_dir = ""
  var sqlite_file = ""

  for key, val in envPairs():
    # Linux only
    if key == "TMPDIR":
      profiles_dir = val
      break

  for file in walkFiles(profiles_dir & "/*/places.sqlite"):
    # TODO: find the newest file
    sqlite_file = file
    break

  if profiles_dir.len == 0 and sqlite_file.len == 0:
    quit()

  var s_in = newFileStream(stdin)
  let db = open(sqlite_file, "", "", "")
  while true:
    let l = cast[int](s_in.readUint32())
    let content = unescape(s_in.readStr(l))
    let parts = content.split("|")
    if parts[0] == "tag_inc":
      db.exec(sql"BEGIN")

      let tags = parts[1].split(",")
      for tag in tags:
        # increment lastModified value by 1 second
        db.exec(sql"update moz_bookmarks set lastModified = (lastModified+1000) where title = ?", tag)

      db.exec(sql"COMMIT")

      msg = "success"

    msg = escapeJson(msg)
    let len_bytes = cast[array[4, uint8]](msg.len)
    discard stdout.writeBytes(len_bytes, 0, len_bytes.len)
    stdout.write(msg)
    stdout.flushFile()

  db.close()
  s_in.close()

main()
