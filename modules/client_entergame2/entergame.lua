EnterGameWindow = nil
EnterGame = EnterGame or {}

controller = Controller:new()

function controller:onInit()
  EnterGameWindow = g_ui.loadUI('entergame', rootWidget)
  EnterGameWindow.onEscape = function()
    EnterGameWindow:destroy()
    EnterGameWindow = nil
  end
  g_logger.info('client_entergame2: controller init')
end

function controller:onTerminate()
  if EnterGameWindow then
    EnterGameWindow:destroy()
    EnterGameWindow = nil
  end
end

function controller:toggle()
  if not EnterGameWindow then
    return
  end
  EnterGameWindow:setVisible(not EnterGameWindow:isVisible())
  if EnterGameWindow:isVisible() then
    EnterGameWindow:raise()
    EnterGameWindow:focus()
  end
end

-- Wrapper opcional para chamadas externas: modules.client_entergame2.toggle()
function toggle()
  controller:toggle()
end

local function getChild(id)
  if not EnterGameWindow then return nil end
  return EnterGameWindow:recursiveGetChildById(id)
end

local function parseHostPath(url)
  local host, path = url:match("([^/]+)/([^/].*)")
  if not path then
    path = ""
  else
    path = '/' .. path
  end
  return host, path
end

-- Estado mínimo compartilhado
G = G or {}

function EnterGame.setDefaultServer(host, port, protocol)
  G.host = host
  G.port = port
end

function EnterGame.setHttpLogin(httpLogin)
  G.httpLogin = not not httpLogin
end

function EnterGame.setAccountName(account)
  local text = g_crypt.decrypt(account)
  local edit = getChild('accountNameTextEdit')
  if edit then
    edit:setText(text)
    edit:setCursorPos(-1)
  end
end

function EnterGame.setPassword(password)
  local text = g_crypt.decrypt(password)
  local edit = getChild('passwordTextEdit')
  if edit then
    edit:setText(text)
  end
end

function EnterGame.firstShow()
  if EnterGameWindow and not EnterGameWindow:isVisible() then
    EnterGameWindow:show()
    EnterGameWindow:raise()
    EnterGameWindow:focus()
  end
end

-- Reexibe (ou recria) a janela de login quando necessário
function EnterGame.show()
  if not EnterGameWindow then
    EnterGameWindow = g_ui.loadUI('entergame', rootWidget)
    EnterGameWindow.onEscape = function()
      EnterGameWindow:destroy()
      EnterGameWindow = nil
    end
  end

  EnterGameWindow:show()
  EnterGameWindow:raise()
  EnterGameWindow:focus()
end

function EnterGame.doLogin()
  local emailEdit = getChild('accountNameTextEdit')
  local passEdit = getChild('passwordTextEdit')
  if not emailEdit or not passEdit then
    g_logger.error('client_entergame2: missing login widgets')
    return
  end

  G.account = emailEdit:getText()
  G.password = passEdit:getText()

  -- Preferir Servers_init, senão usar defaults do URL completo em G.host
  if not G.host or not G.port then
    if Servers_init and table.size(Servers_init) > 0 then
      local hostInit, valuesInit = next(Servers_init)
      G.host = hostInit
      G.port = valuesInit.port or 80
      G.httpLogin = valuesInit.httpLogin
      G.protocol = valuesInit.protocol or G.protocol
    else
      G.host = 'http://127.0.0.1/login.php'
      G.port = 80
      G.httpLogin = true
      G.protocol = G.protocol or 1098
    end
  end

  local host, path = parseHostPath(G.host)
  if not host then
    displayErrorBox(tr('Login Error'), tr('Invalid server URL. Configure Servers_init.'))
    return
  end

  if g_game.isOnline() then
    local errorBox = displayErrorBox(tr('Login Error'), tr('Cannot login while already in game.'))
    errorBox.onOk = function()
      if EnterGameWindow then EnterGameWindow:show() end
    end
    return
  end

  -- Ensure client and protocol versions are set before any world login
  if not G.protocol then
    if Servers_init then
      local _, valuesInit = next(Servers_init)
      G.protocol = valuesInit and valuesInit.protocol or 1098
    else
      G.protocol = 1098
    end
  end
  g_game.setClientVersion(tonumber(G.protocol))
  g_game.setProtocolVersion(g_game.getClientProtocolVersion(tonumber(G.protocol)))

  math.randomseed(os.time())
  G.requestId = math.random(1)

  local http = LoginHttp.create()
  -- Hide the login window while connecting; it will only reappear on cancel or when returning from character list
  if EnterGameWindow then EnterGameWindow:hide() end
  EnterGame.loadBox = displayCancelBox(tr('Please wait'), tr('Connecting to login server...'))
  connect(EnterGame.loadBox, {
    onCancel = function()
      if http and http.cancel then http:cancel() end
      if EnterGame.loadBox then EnterGame.loadBox:destroy() EnterGame.loadBox = nil end
      if EnterGameWindow then
        EnterGameWindow:show()
        EnterGameWindow:raise()
        EnterGameWindow:focus()
      end
    end
  })

  http:httpLogin(host, path, G.port, G.account, G.password, G.requestId, true)
end

function EnterGame.destroyLoadBox()
  if EnterGame.loadBox then
    EnterGame.loadBox:destroy()
    EnterGame.loadBox = nil
  end
end

function EnterGame.loginSuccess(requestId, jsonSession, jsonWorlds, jsonCharacters)
  if G.requestId ~= requestId then
    return
  end
  EnterGame.destroyLoadBox()
  if EnterGameWindow then EnterGameWindow:hide() end

  local worlds = {}
  local worldsDecoded = json.decode(jsonWorlds)
  for _, world in ipairs(worldsDecoded) do
    worlds[world.id] = {
      id = world.id,
      name = world.name,
      ip = world.externaladdressprotected,
      port = world.externalportprotected,
      previewState = world.previewstate == 1
    }
  end
  -- Disponibiliza uma lista curta para a UI de criação de personagem
  G.worlds = {}
  for _, w in pairs(worlds) do
    table.insert(G.worlds, { id = w.id, name = w.name, new = w.previewState })
  end

  local characters = {}
  for index, character in ipairs(json.decode(jsonCharacters)) do
    local world = worlds[character.worldid]
    characters[index] = {
      name = character.name,
      level = character.level,
      main = character.ismaincharacter,
      dailyreward = character.dailyrewardstate,
      hidden = character.ishidden,
      vocation = character.vocation,
      outfitid = character.outfitid,
      headcolor = character.headcolor,
      torsocolor = character.torsocolor,
      legscolor = character.legscolor,
      detailcolor = character.detailcolor,
      addonsflags = character.addonsflags,
      worldName = world.name,
      worldIp = world.ip,
      worldPort = world.port,
      previewState = world.previewstate
    }
  end

  local session = json.decode(jsonSession)
  G.sessionKey = session.sessionkey

  local premiumUntil = tonumber(session.premiumuntil)
  local account = {
    status = '',
    premDays = math.floor((premiumUntil - os.time()) / 86400),
    subStatus = premiumUntil > os.time() and SubscriptionStatus.Premium or SubscriptionStatus.Free
  }

  if CharacterList and CharacterList.create then
    CharacterList.create(characters, account)
    if CharacterList.show then CharacterList.show() end
  end
end

function EnterGame.loginFailed(requestId, msg, result)
  if G.requestId ~= requestId then
    return
  end
  EnterGame.destroyLoadBox()
  local box = displayErrorBox(tr('Login Error'), msg)
  function box.onOk()
    if EnterGameWindow then
      EnterGameWindow:show()
      EnterGameWindow:raise()
      EnterGameWindow:focus()
    end
  end
end
