build-background:
  nim js src/background.nim

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
  
watch-geckodriver:
  watchexec -c -r -w tests/ -w src/ -w ./ -e nim 'just build-ext && just geckodriver'

web-ext:
  web-ext run -i **/*.nim tmp/ src/ tests/ node_modules/ nimcache/ native-messaging/ --pref=storage.sqlite.exclusiveLock.enabled=false --bc
  # -u 'about:devtools-toolbox?id=bookmarks-with-pocket@mozilla.org&type=extension'

setup-native-messaging:
  # requires sqlite3
  nim c -d:release --opt:speed ./native-messaging/sqlite_update.nim
  cp -f ./bin/sqlite_update $HOME/.mozilla/native-messaging-hosts/sqlite_update
  cp -f ./native-messaging/sqlite_update.json $HOME/.mozilla/native-messaging-hosts/sqlite_update.json
