build-css:
  npx unocss options/options.html src/options_page.nim -o dist/main.css

watch-css:
  npx unocss options/options.html src/options_page.nim -o dist/main.css --watch

build file='background' d='debug':
  nim js -d:{{d}} src/{{file}}.nim

build-background:
  nim js -d:testing src/background.nim

build-options_page:
  nim js -d:testing src/options_page.nim

build-content:
  nim js -d:testing src/content_script.nim

watch-js-content:
  watchexec -c -r -w ./src -e nim -i 'src/background.nim' -i 'src/options_page.nim' 'just build-content'

watch-js:
  watchexec -c -r -w ./src -e nim -i 'src/options_page.nim' -i 'src/content_script.nim' 'just build background testing' &
  # watchexec -c -r -w ./src -e nim -i 'src/background.nim' -i 'src/content_script.nim' 'just build options_page'
build-ext: build-background build-options_page
  zip tmp/extension.xpi {manifest.json,tests/*.js,*.html,dist/*.js}

watch-build-ext:
  watchexec -c -r -w tests/ -w src/ -w ./ -e nim 'just build-ext'

geckodriver: build-ext
  nim c --threads:on -d:ssl -r tests/script_get_pocket_access_token.nim
   
watch-geckodriver:
  watchexec -c -r -w tests/ -w src/ -e nim 'just build-ext && just geckodriver'

web-ext $TMPDIR="/tmp": build-background build-options_page
  web-ext run \
    --keep-profile-changes \
    --ignore-files=src/* nimcache/* tmp/* tmp/**/* bin/* native-messaging/* node_modules/* tests/* .direnv/* \
    --pref=storage.sqlite.exclusiveLock.enabled=false \
    -u 'about:devtools-toolbox?id=bookmarks-with-pocket@mozilla.org&type=extension'

setup-native-messaging:
  # requires sqlite3
  nim c -d:release --opt:speed ./native-messaging/sqlite_update.nim
  cp -f ./bin/sqlite_update $HOME/.mozilla/native-messaging-hosts/sqlite_update
  cp -f ./native-messaging/sqlite_update.json $HOME/.mozilla/native-messaging-hosts/sqlite_update.json
