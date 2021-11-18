import std/[asyncjs, jsffi, jscore, jsfetch, jsheaders]
import std/jsconsole
import badresults
import app_js_ffi

proc getRedirectURL*(): cstring {.importcpp: "browser.identity.getRedirectURL()".}

const pocket_add_folder* = "pocket"
const content_type = "application/json"
let consumer_key*: cstring = "88239-c5239ac90c414b6515d526f4"
# const redirect_uri: cstring = "https://localhost"
let redirect_uri: cstring = getRedirectURL() & "oauth"
let pocket_auth_uri: cstring = "https://getpocket.com/auth/authorize?request_token=$REQUEST_TOKEN&redirect_uri=" & redirect_uri

type
  PocketError* {.pure.} = enum
    WebAuthFlow, InvalidResponseBody
    InvalidStatusCode

  PocketResult*[T] = Result[T, PocketError]

func newRequest*(url: cstring, opts: JsObject): Request {.importjs: "(new Request(#, #))".}
proc replace*(str: cstring, target: cstring, replace: cstring): cstring {.importcpp.}
proc launchWebAuthFlow*(options: JsObject): Future[Response] {.
    importcpp: "browser.identity.launchWebAuthFlow(#)".}


func createPocketRequest*(url: cstring; body: cstring): Request =
  let headers = newHeaders()
  headers.add("Content-Type", content_type & "; charset=UTF-8".cstring)
  headers.add("X-Accept", content_type)
  let req_init = newJsObject()
  req_init["method"] = "POST".cstring
  req_init.headers = headers
  req_init.body = body
  return newRequest(url, req_init)


proc getRequestToken*(): Future[PocketResult[cstring]] {.async.} =
  let req_body: cstring = "consumer_key=" & consumer_key & "&redirect_uri=" &
      redirect_uri

  let req = createPocketRequest("https://getpocket.com/v3/oauth/request", req_body)
  let resp = await fetch(req)

  if resp.status != 200:
    console.error "Failed to get Pocket request token"
    return err(PocketResult[cstring], WebAuthFlow)

  let resp_body = await resp.text()

  let kv = resp_body.split "="
  if kv.len < 2:
    console.error "Invalid Pocket API response body for new request token"
    return err(PocketResult[cstring], InvalidResponseBody)

  return ok(PocketResult[cstring], kv[1])


proc authUrl*(request_token: cstring): cstring =
  let url = replace(pocket_auth_uri, "$REQUEST_TOKEN".cstring, request_token)
  return url


proc oauthAutheticate*(request_token: cstring): Future[PocketResult[void]] {.async.} =
  let url = authUrl(request_token)
  let options = newJsObject()
  options["url"] = url
  options["interactive"] = true
  try:
    discard await launchWebAuthFlow(options)
  except:
    return err(PocketResult[void], WebAuthFlow)
  return ok(PocketResult[void])


proc getAccessToken*(request_token: cstring): Future[PocketResult[cstring]] {.async.} =
  let req_body: cstring = "consumer_key=" & consumer_key & "&code=" & request_token

  let req = createPocketRequest("https://getpocket.com/v3/oauth/authorize", req_body)
  let resp = await fetch(req)

  if resp.status != 200:
    console.error "Failed to get Pocket access token"
    return err(PocketResult[cstring], InvalidStatusCode)

  let resp_body = await resp.text()
  return ok(PocketResult[cstring], resp_body)

proc authenticate*(): Future[PocketResult[cstring]] {.async.} =
  let token_result = await getRequestToken()
  if token_result.isErr(): return err(PocketResult[cstring], token_result.error())
  let code = token_result.value

  let auth_result = await oauthAutheticate(code)
  if auth_result.isErr(): return err(PocketResult[cstring], auth_result.error())
  let token_resp = await getAccessToken(code)
  return token_resp

proc addLink*(url: cstring, access_token: cstring, tags: seq[cstring]): Future[
    PocketResult[JsObject]] {.async.} =
  var params = newJsObject()
  params["url"] = url
  params["consumer_key"] = consumer_key
  params["access_token"] = access_token
  if tags.len > 0:
    params["tags"] = block:
      var tags_str: cstring = tags[0]
      for tag in tags[1..tags.len-1]:
        tags_str.add(",")
        tags_str.add(tag)
      tags_str

  let req_body = JSON.stringify(params)
  let req = createPocketRequest("https://getpocket.com/v3/add", req_body)
  let resp = await fetch(req)

  # TODO: handle other status codes
  if resp.status != 200:
    console.log("Unhandled status code: " & cstring($resp.status))
    return err(PocketResult[JsObject], InvalidStatusCode)

  let resp_json = await resp.json()

  return ok(PocketResult[JsObject], resp_json)

# NOTE: At the moment is only used when testing code
proc retrieveLinks*(access_token: cstring, search_term: cstring): Future[
    PocketResult[JsObject]] {.async.} =
  let params = newJsObject()
  params["consumer_key"] = consumer_key
  params["access_token"] = access_token
  params["search"] = search_term
  params["detailType"] = "complete".cstring
  params["sort"] = "newest".cstring
  params["count"] = 1

  let req_body = JSON.stringify(params)
  let req = createPocketRequest("https://getpocket.com/v3/get", req_body)
  let resp = await fetch(req)

  # TODO: handle other status codes
  if resp.status != 200:
    console.log("Unhandled status code: " & cstring($resp.status))
    return err(PocketResult[JsObject], InvalidStatusCode)

  let resp_json = await resp.json()

  return ok(PocketResult[JsObject], resp_json)

proc modifyLink*(access_token: cstring, action: JsObject): Future[PocketResult[
    JsObject]] {.async.} =

  let params = newJsObject()
  params["consumer_key"] = consumer_key
  params["access_token"] = access_token
  params["actions"] = @[action]

  let req_body = JSON.stringify(params)
  let req = createPocketRequest("https://getpocket.com/v3/send", req_body)
  let resp = await fetch(req)

  # TODO: handle other status codes
  if resp.status != 200:
    console.log("Unhandled status code: " & cstring($resp.status))
    return err(PocketResult[JsObject], InvalidStatusCode)

  let resp_json = await resp.json()

  return ok(PocketResult[JsObject], resp_json)


