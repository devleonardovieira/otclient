EnterGameWindow = nil
EnterGame = EnterGame or {}
local LOCAL_API_KEY = "6f8d9c2a1b7e4d3f9a0c5e7b2d6f1a3c8e9b0d4f2a6c7e5b1d3f9a2c4e6b8d0f"
controller = Controller:new()
local function isLoaderActive()
  local ok, loader = pcall(function() return modules.client_loader and modules.client_loader.Loader end)
  if not ok or not loader or not loader.isActive then return false end
  local ok2, active = pcall(loader.isActive)
  return ok2 and active or false
end

function controller:onInit()
  EnterGameWindow = g_ui.loadUI('entergame', rootWidget)
  EnterGameWindow.onEscape = function()
    EnterGameWindow:hide()
  end
  -- Initialize remember email checkbox and prefill state
  local rememberBox = EnterGameWindow and EnterGameWindow:recursiveGetChildById('rememberEmailBox') or nil
  if rememberBox then
    g_settings.setDefault('rememberEmail', false)
    local remember = g_settings.getBoolean('rememberEmail', false)
    rememberBox:setChecked(remember)
    local emailEdit = EnterGameWindow:recursiveGetChildById('accountNameTextEdit')
    if remember and emailEdit then
      local savedEmail = g_settings.getString('savedEmail') or ''
      if savedEmail and savedEmail ~= '' then
        emailEdit:setText(savedEmail)
        emailEdit:setCursorPos(-1)
      end
    end
    connect(rememberBox, {
      onCheckChange = function(widget, checked)
        g_settings.set('rememberEmail', checked)
        g_settings.save()
        if not checked then
          g_settings.remove('savedEmail')
          g_settings.save()
        end
      end
    })
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
  if isLoaderActive() then
    G.deferShowLogin = true
    return
  end
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
      EnterGameWindow:hide()
    end
  end
  if isLoaderActive() then
    G.deferShowLogin = true
    return
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

  -- Persist email if checkbox is checked; never persist password
  local rememberBox = getChild('rememberEmailBox')
  local remember = rememberBox and rememberBox:isChecked() or g_settings.getBoolean('rememberEmail', false)
  g_settings.set('rememberEmail', remember)
  if remember then
    g_settings.set('savedEmail', G.account)
  else
    g_settings.remove('savedEmail')
  end
  g_settings.save()

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
  -- Cria imediatamente o loading para evitar corrida com o retorno do login
  if EnterGame.loadBox then EnterGame.destroyLoadBox() end
  EnterGame.loadBox = displayCancelBox(tr('Please wait'), tr('Connecting to login server...'))
  connect(EnterGame.loadBox, {
    onCancel = function()
      if http and http.cancel then http:cancel() end
      EnterGame.destroyLoadBox()
      if EnterGameWindow then
        EnterGameWindow:show()
        EnterGameWindow:raise()
        EnterGameWindow:focus()
      end
    end
  })
  -- Anima saída da janela de login para a esquerda em paralelo ao loading
  if EnterGameWindow and EnterGameWindow:isVisible() then
    local w = EnterGameWindow
    local finalPos = w:getPosition()
    w:breakAnchors()
    g_effects.moveToPosition(w, finalPos, { x = -w:getWidth(), y = finalPos.y }, 220, Easing.easeIn, function()
      w:hide()
    end)
  end

  -- Definir apiKey apenas quando SITE_API_KEY não estiver presente no ambiente
  local envApiKey = (os and os.getenv) and os.getenv('SITE_API_KEY') or nil
  if envApiKey and envApiKey ~= '' then
    -- Deixe G.apiKey vazio para que o cliente use SITE_API_KEY via fallback interno
    G.apiKey = ''
  else
    if not G.apiKey or G.apiKey == '' then
      G.apiKey = LOCAL_API_KEY
    end
  end

  -- Dispara apenas uma chamada de login HTTP; evitar duplicidade que causa caixas de erro duplas
  http:httpLogin(host, path, G.port, G.account, G.password, G.apiKey, G.requestId, true)
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
  -- Guarda host/porta padrão do primeiro mundo para uso em atualizações locais
  if worldsDecoded and #worldsDecoded > 0 then
    local w0 = worldsDecoded[1]
    G.defaultWorldHost = w0.externaladdressprotected or w0.externaladdress or w0.externaladdressunprotected
    G.defaultWorldPort = w0.externalportprotected or w0.externalport or w0.externalportunprotected
  end
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
    local worldName = (world and world.name) or (worldsDecoded and worldsDecoded[1] and worldsDecoded[1].name) or tr("Default")
    local worldIp   = (world and world.ip)   or G.defaultWorldHost or ""
    local worldPort = (world and world.port) or G.defaultWorldPort or 0
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
      worldName = worldName,
      worldIp = worldIp,
      worldPort = worldPort,
      previewState = (world and world.previewstate) or false
    }
  end

  local session = json.decode(jsonSession)
  G.sessionKey = session.sessionkey
  -- Captura o token de sessão curto para chamadas do site (login.php)
  if session.sessiontoken then
    G.sessionToken = session.sessiontoken
    G.sessionTokenExpires = session.sessionexpires or 0
  end
  -- Recarrega apiKey de configuração, mantendo fallback
  do
    local envApiKey = (os and os.getenv) and os.getenv('SITE_API_KEY') or nil
    if envApiKey and envApiKey ~= '' then
      G.apiKey = ''
    else
      G.apiKey = G.apiKey or LOCAL_API_KEY
    end
  end

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
  box.onOk = function()
    -- Deixe o sistema fechar a caixa; apenas restaure a janela
    if EnterGameWindow then
      EnterGameWindow:show()
      EnterGameWindow:raise()
      EnterGameWindow:focus()
    end
  end
end
