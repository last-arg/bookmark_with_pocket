release: build-css build-js build-ext

build-js type='release': (build "background" type) (build "options_page" type) (build "content_script" type)

build file='background' d='debug':
  nim js -d:{{d}} src/{{file}}.nim

build-css:
  npx unocss options/options.html src/options_page.nim -o dist/main.css

watch-css:
  npx unocss options/options.html src/options_page.nim src/styles/main.css -o dist/main.css --watch

build-background:
  just build background testing

watch-background:
  watchexec -c -r -w ./src -e nim -i 'src/options_page.nim' 'just build-background'

build-options_page:
  just build options_page

watch-options_page:
  watchexec -c -r -w ./src/options_page.nim 'just build-options_page'

build-content_script:
  nim js -d:testing src/content_script.nim

watch-content_script:
  watchexec -c -r -w ./src -e nim -i 'src/background.nim' -i 'src/options_page.nim' 'just build-content'

watch-js:
  watchexec -c -r -w ./src -e nim -i 'src/{options_page, content_script}.nim' 'just build-background' &
  watchexec -c -r -w ./src -e nim -i 'src/{background, content_script}.nim' 'just build options_page'

dev:
  just watch-css &
  just watch-js

build-ext:
  zip tmp/extension.xpi {manifest.json,*.html,dist/*.js,assests/*}

geckodriver: build-ext
  nim c --threads:on -d:ssl -r tests/script_get_pocket_access_token.nim
   
watch-geckodriver:
  watchexec -c -r -w tests/ -w src/ -e nim 'just build-ext && just geckodriver'

web-ext $TMPDIR="/tmp":
  web-ext run \
    --keep-profile-changes \
    --ignore-files=src/* nimcache/* tmp/* tmp/**/* bin/* native-messaging/* node_modules/* tests/* .direnv/* \
    --pref=storage.sqlite.exclusiveLock.enabled=false \
    -u 'about:devtools-toolbox?id=bookmarks-with-pocket@mozilla.org&type=extension'

setup-native-messaging:
  # dependency: sqlite3
  nim c -d:release --opt:speed ./native-messaging/sqlite_update.nim
  cp -f ./bin/sqlite_update $HOME/.mozilla/native-messaging-hosts/sqlite_update
  cp -f ./native-messaging/sqlite_update.json $HOME/.mozilla/native-messaging-hosts/sqlite_update.json
