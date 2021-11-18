import std/[asyncjs, jsffi, jscore, jsfetch, jsheaders, jsconsole]
import badresults
import app_js_ffi

type
  PocketError* {.pure.} = enum
    FailedWebAuthFlow, InvalidStatusCode, UserRejectedCode
    StatusForbidden, InvalidAccessToken, InvalidRequestToken

  PocketResult*[T] = Result[T, PocketError]

func newRequest*(url: cstring, opts: JsObject): Request {.importjs: "(new Request(#, #))".}
proc replace*(str: cstring, target: cstring, replace: cstring): cstring {.importcpp.}
proc getRedirectURL*(): cstring {.importjs: "browser.identity.getRedirectURL()".}
proc launchWebAuthFlow*(options: JsObject): Future[Response] {.
    importjs: "browser.identity.launchWebAuthFlow(#)".}


const pocket_add_folder* = "pocket"
const content_type = "application/json"
let consumer_key*: cstring = "88239-c5239ac90c414b6515d526f4"
# const redirect_uri: cstring = "https://localhost"
let redirect_uri: cstring = getRedirectURL() & "oauth"
let pocket_auth_uri: cstring = "https://getpocket.com/auth/authorize?request_token=$REQUEST_TOKEN&redirect_uri=" & redirect_uri


func createPocketRequest*(url: cstring; body: cstring): Request =
  let headers = newHeaders()
  headers.add("Content-Type", content_type & "; charset=UTF-8".cstring)
  headers.add("X-Accept", content_type)
  let req_init = newJsObject()
  req_init["method"] = "POST".cstring
  req_init.headers = headers
  req_init.body = body
  return newRequest(url, req_init)


type TokenResponse = ref object
  code: cstring

proc getRequestToken*(): Future[PocketResult[cstring]] {.async.} =
  let body_json = newJsObject()
  body_json["consumer_key"] = consumer_key
  body_json["redirect_uri"] = redirect_uri

  let req = createPocketRequest("https://getpocket.com/v3/oauth/request", JSON.stringify(body_json))
  let resp = await fetch(req)

  return case resp.status:
    of 200:
      let body = cast[TokenResponse](await resp.json())
      if isUndefined(body.code) or isNull(body.code) or body.code.len == 0:
        err(PocketResult[cstring], InvalidRequestToken)
      else:
        ok(PocketResult[cstring], body.code)
    else:
      err(PocketResult[cstring], FailedWebAuthFlow)


proc oauthAutheticate*(request_token: cstring): Future[PocketResult[void]] {.async.} =
  let url = replace(pocket_auth_uri, "$REQUEST_TOKEN".cstring, request_token)
  let options = newJsObject()
  options["url"] = url
  options["interactive"] = true
  try:
    discard await launchWebAuthFlow(options)
  except:
    return err(PocketResult[void], FailedWebAuthFlow)
  return ok(PocketResult[void])


type AccessTokenResponse = ref object
  access_token: cstring
  username: cstring

proc getAccessToken*(request_token: cstring): Future[PocketResult[cstring]] {.async.} =
  let body_json = newJsObject()
  body_json["consumer_key"] = consumer_key
  body_json["code"] = request_token

  let req = createPocketRequest("https://getpocket.com/v3/oauth/authorize", JSON.stringify(body_json))
  let resp = await fetch(req)

  return case resp.status:
    of 200:
      let body = cast[AccessTokenResponse](await resp.json())
      if isUndefined(body.access_token) or isNull(body.access_token) or body.access_token.len == 0:
        err(PocketResult[cstring], InvalidAccessToken)
      else:
        ok(PocketResult[cstring], body.access_token)
    of 403:
      if resp.headers["X-Error"] == "User rejected code.":
        err(PocketResult[cstring], UserRejectedCode)
      else:
        err(PocketResult[cstring], StatusForbidden)
    else:
      err(PocketResult[cstring], InvalidStatusCode)

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


