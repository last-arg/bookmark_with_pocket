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
  web-ext run -i **/*.nim tmp/ src/ tests/ node_modules nimcache --pref=storage.sqlite.exclusiveLock.enabled=false -u 'about:devtools-toolbox?id=bookmarks-with-pocket%40mozilla.org&type=extension'
