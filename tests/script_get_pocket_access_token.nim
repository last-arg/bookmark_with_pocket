import options, os, strformat, strtabs
import halonium
import json
import tables
import options, strutils
# import httpclient, uri

type InvalidAccessToken* = object of ValueError ## is raised for a JSON error

proc saveLocalStorage(session: Session, file: File) =
  # Save localStorage data to file
  var max_msec = 3000
  let interval = 100
  while max_msec > 0:
    let local_data = session.executeScript(
      """
        let username = localStorage.getItem("username")
        let access_token = localStorage.getItem("access_token")
        return {access_token: access_token,  username: username}
      """)
    if local_data["access_token"].getStr().len > 0:
      if file.reopen("tmp/localstorage.json", mode = fmWrite):
        file.writeLine(local_data)
      else:
        echo "ERR: Failed to open 'localstorage.json' in write mode"
      break
    sleep(interval)
    max_msec -= interval

proc authPocket(session: Session, config: Table[string, string]) =
  let base_len = session.windows().len
  block find_window:
    while true:
      if (session.windows().len > base_len):
        let wins = session.windows()
        for win in wins[base_len..^1]:
          session.switchToWindow(win)
          if session.currentUrl().contains("getpocket.com/auth/authorize"):
            break find_window
      sleep(100)


  # TODO: make into args
  let user = session.waitForElement("#feed_id", timeout = 1000).get()
  user.sendKeys(config["username"])

  let pass = session.waitForElement("#login_password", timeout = 100).get()
  pass.sendKeys(config["password"])

  let btn_auth = session.waitForElement(".btn-authorize", timeout = 100).get()
  btn_auth.click()


proc main() =
  let filename = "tmp/.pocket_auth"
  let pocket_auth_file = open(filename)
  defer: pocket_auth_file.close()
  var config = initTable[string, string]()
  var line = ""
  while pocket_auth_file.readLine(line):
    if line.len > 0 and line.contains("="):
      let kv = line.split("=")
      config[kv[0]] = kv[1]

  if not config.hasKey("username") or not config.hasKey("password"):
    echo fmt"ERR: missing key/value pair username or/and password in file '{filename}'"
    return

  let profiles_rel_loc = getCurrentDir() & "/tmp/gecko_profiles"
  removeDir(profiles_rel_loc)
  createDir(profiles_rel_loc)

  var session_envs = newStringTable()
  for key, val in envPairs():
    session_envs[key] = val

  session_envs["TMPDIR"] = profiles_rel_loc

  let caps = %*{
    "browserName": "firefox",
    "acceptInsecureCerts": true,
  }

  var firefox_opts = firefoxOptions(
    pageLoadStrategy = some(PageLoadStrategy.plsEager),
    logLevel = some("trace"),
    # args = @["--headless"],

      # https://bugzilla.mozilla.org/show_bug.cgi?id=1421766
    # args = @["-profile", tmp_firefox_profile],
    additionalCapabilities = caps
  )

  firefox_opts["moz:firefoxOptions"]["prefs"] = %*{
    "xpinstall.signatures.required": false,
    "browser.aboutConfig.showWarning": false,
    "storage.sqlite.exclusiveLock.enabled": false,
  }

  echo $firefox_opts

  # hideDriverConsoleWindow and headless give a completely background execution on Windows
  let session = createSession(
    Firefox,
    browserOptions = firefox_opts,
    env = session_envs,
    # port = 2828,
      # port = 13366,
    hideDriverConsoleWindow = true,
    # logLevel = "debug",
    logPath = getCurrentDir() & "/tmp/geckodriver.log"
  )

  let ext_path = getCurrentDir() & "/tmp/extension.xpi"
  let addon_id = session.firefoxInstallAddon(ext_path, false)

  # session.navigate(fmt"about:config")
  # let addons_json_str = session.executeScript(
  #   """
  #     document.getElementById("about-config-search").value = arguments[0];
  #     filterPrefs();
  #     // view.selection.currentIndex = 0;
  #     // var value = view.getCellText(0, {id:"valueCol"});
  #     let result = document.querySelector("#prefs .cell-value").textContent;
  #     return result;
  #   """,
  # "extensions.webextensions.uuids").getStr()

  # let addons = parseJson(addons_json_str)
  # let uuid = addons{addon_id}.getStr()
  # if uuid == "":
  #   echo fmt"ERR: Couldn't find key '{addon_id}' in uuids json"
  #   session.quit()
  #   return

  session.navigate(fmt"about:devtools-toolbox?id={addon_id}&type=extension")

  # let tab = session.newWindow(WindowKind.wkTab)
  # session.switchToWindow(tab)
  # session.navigate(fmt"moz-extension://{uuid}/blank.html")

  # var do_pocket_login = false
  # let localstorage_file = open("tmp/localstorage.json", mode = fmRead)
  # defer: localstorage_file.close()
  # let content = localstorage_file.readAll()
  # try:
  #   let local = parseJson(content)
  #   let access_token = local["access_token"].getStr()
  #   if access_token.len == 0:
  #     raise newException(InvalidAccessToken, "Invalid Pocket access token")

  #   discard session.executeScript(
  #     """
  #     (async function init(username, access_token) {
  #       browser.storage.local.set({
  #         "username": username,
  #         "access_token": access_token
  #       });
  #       localStorage.setItem("username", username);
  #       localStorage.setItem("access_token", access_token);
  #     })(arguments[0], arguments[1])
  #     """,
  #   local["username"].getStr(), access_token)
  #   # session.refresh()
  # except JsonParsingError, InvalidAccessToken:
  #   do_pocket_login = true

  # session.navigate(fmt"moz-extension://{uuid}/index.html")

  # if do_pocket_login:
  #   echo "Do Pocket login"
  #   let pocket_login = session.waitForElement(".login-pocket",
  #       timeout = 100).get()
  #   pocket_login.click()
  #   let main_win = session.currentwindow()
  #   authPocket(session, config)
  #   session.switchToWindow(main_win)
  #   saveLocalStorage(session, localstorage_file)

  echo "DONE"

  # session.quit()

main()
