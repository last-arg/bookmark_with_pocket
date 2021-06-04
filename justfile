build-test-pocket:
  nim js --hints:off tests/test_pocket.nim

build-background:
  nim js src/background.nim

geckodriver:
  nim c --threads:on -d:ssl -r tests/script_get_pocket_access_token.nim

build-pocket:
  nim js src/pocket.nim

build-ext:
  just build-background && just build-test-pocket && zip tmp/extension.xpi {manifest.json,tests/*.js,*.html,dist/*.js}

watch-build-ext:
  watchexec -c -r -w tests/ -w src/ -w ./ -e nim 'just build-ext'
  
watch-geckodriver:
  watchexec -c -r -w tests/ -w src/ -w ./ -e nim 'just build-ext && just geckodriver'

  
