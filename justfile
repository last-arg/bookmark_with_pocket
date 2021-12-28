release: clean build-css build-js build-ext

clean:
  rm -rf dist/
  mkdir dist

build-js type='release': (build "background" type) (build "options_page" type) (build "content_script" type)

build file='background' d='debug':
  nim js -d:{{d}} src/{{file}}.nim

build-css:
  npx unocss options/options.html src/options_page.nim -o dist/main.css

watch-css:
  npx unocss options/options.html src/options_page.nim src/styles/main.css -o dist/main.css --watch

build-background:
  just build background testing

build-options_page:
  just build options_page testing

build-content_script:
  just build content_script testing

watch-js:
  watchexec -c -w src/content_script.nim 'just build-content_script' &
  watchexec -c -w ./src -e nim -i 'src/{options_page, content_script}.nim' 'just build-background' &
  watchexec -c -w ./src -e nim -i 'src/{background, content_script}.nim' 'just build options_page'

dev:
  just watch-css &
  just watch-js

build_dir := "build"
build-ext file='bookmark_with_pocket.xpi':
  mkdir -p build
  zip {{build_dir}}/{{file}} {manifest.json,*.html,dist/*.js,assets/*}
  @echo "Build location: {{ build_dir }}/{{ file }}"

geckodriver: (build-ext "tmp/extension.xpi")
  nim c --threads:on -d:ssl -r tests/script_get_pocket_access_token.nim
   
watch-geckodriver:
  watchexec -c -r -w tests/ -w src/ -e nim 'just geckodriver'

web-ext $TMPDIR="/tmp":
  web-ext run \
    --keep-profile-changes \
    --watch-files=dist/**/* index.html options/*.html \
    --pref=storage.sqlite.exclusiveLock.enabled=false \
    -u 'about:devtools-toolbox?id=bookmark-with-pocket@mozilla.org&type=extension'

setup-native-messaging:
  # dependencies: sqlite3
  nim c -d:release --opt:speed ./native-messaging/sqlite_update.nim
  cp -f ./bin/sqlite_update $HOME/.mozilla/native-messaging-hosts/sqlite_update
  cp -f ./native-messaging/sqlite_update.json $HOME/.mozilla/native-messaging-hosts/sqlite_update.json
