build-test-pocket:
  nim js --hints:off tests/test_pocket.nim

build-background:
  nim js --hints:off src/background.nim

get-access-token:
  nim c --outdir:tests --threads:on -d:ssl -r tests/script_get_pocket_access_token.nim

build-pocket:
  nim js src/pocket.nim

watch-get-access-token:
  watchexec -c -r -w tests/ -w src/ -w ./ -e nim,js 'zip tmp/extension.xpi {manifest.json,tests/*,index.html,dist/*} && just build-background && just build-test-pocket && just get-access-token'

  
