build-background:
  nim js -d:testing src/background.nim

build-options:
  nim js -d:testing src/options.nim

geckodriver: build-ext
  nim c --threads:on -d:ssl -r tests/script_get_pocket_access_token.nim

build-pocket:
  nim js src/pocket.nim

build-ext:
  just build-background && zip tmp/extension.xpi {manifest.json,tests/*.js,*.html,dist/*.js}

watch-build-ext:
  watchexec -c -r -w tests/ -w src/ -w ./ -e nim 'just build-ext'

watch-build-background:
  watchexec -c -r -w src/ -w ./ -e nim 'just build-background'

watch-build-options:
  watchexec -c -r -w src/ -w ./ -e nim -i 'src/background.nim' 'just build-options'
  
watch-geckodriver:
  watchexec -c -r -w tests/ -w src/ -w ./ -e nim 'just build-ext && just geckodriver'

web-ext: build-background build-options
  web-ext run --ignore-files=src/* nimcache/* tmp/* tmp/**/* bin/* native-messaging/* node_modules/* tests/* --pref=storage.sqlite.exclusiveLock.enabled=false -u 'about:devtools-toolbox?id=bookmarks-with-pocket@mozilla.org&type=extension'

setup-native-messaging:
  # requires sqlite3
  nim c -d:release --opt:speed ./native-messaging/sqlite_update.nim
  cp -f ./bin/sqlite_update $HOME/.mozilla/native-messaging-hosts/sqlite_update
  cp -f ./native-messaging/sqlite_update.json $HOME/.mozilla/native-messaging-hosts/sqlite_update.json
