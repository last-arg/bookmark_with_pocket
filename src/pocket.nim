import asyncjs, jsffi, jsconsole, dom
import results

proc getRedirectURL*(): cstring {.importcpp: "browser.identity.getRedirectURL()".}

let consumer_key*: cstring = "88239-c5239ac90c414b6515d526f4"
proc getConsumerKey*(): cstring = consumer_key
# const redirect_uri: cstring = "https://localhost"
let redirect_uri: cstring = getRedirectURL() & "oauth"
let pocket_auth_uri: cstring = "https://getpocket.com/auth/authorize?request_token=$REQUEST_TOKEN&redirect_uri=" & $redirect_uri

type
  FetchOptions* = ref object of JsRoot
    keepalive*: bool
    metod* {.importcpp: "method".}: cstring
    body*, integrity*, referrer*, mode*, credentials*, cache*, redirect*,
        referrerPolicy*: cstring

  Body* = ref object of JsRoot ## https://developer.mozilla.org/en-US/docs/Web/API/Body
    bodyUsed*: bool

  Response* = ref object of JsRoot ## https://developer.mozilla.org/en-US/docs/Web/API/Response
    bodyUsed*, ok*, redirected*: bool
    typ* {.importcpp: "type".}: cstring
    url*, statusText*: cstring
    status*: cint
    headers*: JsObject
    body*: Body

  Request* = ref object of JsRoot ## https://developer.mozilla.org/en-US/docs/Web/API/Request
    bodyUsed*, ok*, redirected*: bool
    typ* {.importcpp: "type".}: cstring
    url*, statusText*: cstring
    status*: cint
    headers*: JsObject
    body*: Body

  PocketError* = enum
    WebAuthFlow, InvalidBody
    InvalidStatusCode

  PocketResult*[T] = Result[T, PocketError]

proc launchWebAuthFlow*(options: JsObject): Future[Response] {.
    importcpp: "browser.identity.launchWebAuthFlow(#)".}

proc fetch*(url: Request, opts: JsObject): Future[Response] {.
    importcpp: "$1(#)".}

func newRequest*(url: cstring; opts: JsObject = newJsObject()): Request {.
    importcpp: "(new Request(#, #))".}

proc text*(self: Response): Future[cstring] {.importcpp: "#.$1()".}

func split*(pattern: cstring; self: cstring): seq[cstring] {.
    importcpp: "#.split(#)".}

func createPocketRequest*(url: cstring; body: cstring): Request =
  var headers = newJsObject()
  headers["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8".cstring
  headers["X-Accept"] = "application/x-www-form-urlencoded".cstring
  headers["Access-Control-Allow-Origin"] = "*".cstring
  headers["Access-Control-Allow-Credentials"] = "true".cstring
  headers["Access-Control-Allow-Headers"] = "*".cstring
  headers["Access-Control-Allow-Methods"] = "*".cstring
  headers["Access-Control-Expose-Headers"] = "*".cstring

  var req_opts = newJsObject()
  req_opts["method"] = "POST".cstring
  req_opts.headers = headers
  req_opts.body = body
  return newRequest(url, req_opts)


proc getRequestToken*(): Future[PocketResult[cstring]] {.async.} =
  let req_body: cstring = "consumer_key=" & consumer_key & "&redirect_uri=" &
      redirect_uri

  let req = createPocketRequest("https://getpocket.com/v3/oauth/request", req_body)

  var opts = newJsObject()
  opts.cors = "no-cors".cstring
  # opts.credentials = "omit".cstring
  let resp = await fetch(req, opts)

  if resp.status != 200:
    console.error "Failed to get Pocket request token"
    return err(PocketResult[cstring], WebAuthFlow)

  let resp_body = await resp.text()

  let kv = resp_body.split "="
  if kv.len < 2:
    console.error "Invalid Pocket API response body for new request token"
    return err(PocketResult[cstring], InvalidBody)

  return ok(PocketResult[cstring], kv[1])

proc replace*(str: cstring, target: cstring, replace: cstring): cstring {.importcpp.}
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
  let req_body: cstring = "consumer_key=" & consumer_key & "&code=" &
      request_token

  let req = createPocketRequest("https://getpocket.com/v3/oauth/authorize", req_body)
  var opts = newJsObject()
  # TODO: test without no-cors
  opts.cors = "no-cors".cstring
  # opts.credentials = "omit".cstring
  let resp = await fetch(req, opts)

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

proc pocketLogin*(): Future[void] {.async.} =
  const user_key = "username"
  const token_key = "access_token"
  var token = window.localStorage.getItem(token_key)

  if token.isNull():
    console.log "Authenticating Pocket"
    let body_result = await authenticate()
    if body_result.isErr():
      console.error("Pocket authentication failed")
      return
    let body = body_result.value
    const key = 0
    const value = 1
    var has_access_token = false
    let kvs = body.split "&"
    for kv_str in kvs:
      let kv = kv_str.split "="
      if kv[key] == token_key:
        has_access_token = true
        token = kv[value]
        window.localStorage.setItem(token_key, token)
      elif kv[key] == user_key:
        window.localStorage.setItem(user_key, kv[value])

    if not has_access_token:
      console.error "Login to Pocket failed. Response body didn't contain access_token field/key"
      return

  console.log token


