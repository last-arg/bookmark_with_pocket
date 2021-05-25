build-test-pocket:
  nim js --hints:off tests/test_pocket.nim

build-background:
  nim js --hints:off src/background.nim

geckodriver:
  nim c --threads:on -d:ssl -r tests/script_get_pocket_access_token.nim

build-pocket:
  nim js src/pocket.nim

watch-get-access-token:
  watchexec -c -r -w tests/ -w src/ -w ./ -e nim,js 'zip tmp/extension.xpi {manifest.json,tests/*.js,index.html,dist/*.js} && just build-background && just build-test-pocket && just geckodriver'

  
