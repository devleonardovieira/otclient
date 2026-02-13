Loader = {}

local loaderWindow
local scheduledEvent
local loadFn
local startMillis = 0
local minDisplayMs = 500 -- tempo mínimo de exibição da tela de loading
local hiddenWidgets = {}
local rootConn
local bgConn

local steps = {}
local currentStep = 0

local function preloadMinimap()
  g_modules.ensureModuleLoaded('game_minimap')

  local ok, err = pcall(function()
    if modules and modules.game_minimap and modules.game_minimap.preload then
      modules.game_minimap.preload()
    end
  end)

  if not ok then
    g_logger.warning('Failed to preload minimap: ' .. tostring(err))
  end
end

local function setProgress(p, statusText)
  if not loaderWindow then return end
  -- Buscar widgets recursivamente, pois agora estão dentro de painéis
  local progress = loaderWindow:recursiveGetChildById('mainProgress')
  local percentLabel = loaderWindow:recursiveGetChildById('percent')
  local statusLabel = loaderWindow:recursiveGetChildById('status')

  if progress then progress:setPercent(p) end
  if percentLabel then percentLabel:setText(string.format('%d%%', p)) end
  if statusText and statusLabel then statusLabel:setText(statusText) end
end

local function finalizeStartup()
  -- finalizar após respeitar tempo mínimo
  local elapsed = g_clock.millis() - startMillis
  local remaining = math.max(minDisplayMs - elapsed, 0)
  local function finish()
    setProgress(100, tr('Finished'))
    if scheduledEvent then
      removeEvent(scheduledEvent)
      scheduledEvent = nil
    end
    if loaderWindow then
      -- ensure no input is grabbed and cleanly destroy
      pcall(function() loaderWindow:ungrabMouse() end)
      pcall(function() loaderWindow:ungrabKeyboard() end)
      loaderWindow:destroy()
      loaderWindow = nil
    end
    -- disconnect root hook
    local root = g_ui.getRootWidget()
    if rootConn then
      pcall(function() disconnect(root, rootConn) end)
      rootConn = nil
    end
    if bgConn then
      local background = root:recursiveGetChildById('background')
      pcall(function() if background then disconnect(background, bgConn) end end)
      bgConn = nil
    end
    steps = {}
    currentStep = 0
    loadFn = nil
    -- Restaurar widgets ocultados
    for _, w in ipairs(hiddenWidgets) do
      if w and not w:isDestroyed() then
        w:show()
      end
    end
    hiddenWidgets = {}
    local script = '/' .. g_app.getCompactName() .. 'rc.lua'
    if g_resources.fileExists(script) then
      local ok, err = pcall(dofile, script)
      if not ok then g_logger.warning('rc.lua error: ' .. tostring(err)) end
    end
    g_modules.enableAutoReload()
    -- Se o login foi adiado durante o loader, exibe agora
    local okEnter, _ = pcall(function()
      if EnterGame and EnterGame.show then
        -- Se foi adiado, limpa o flag; caso não, apenas exibe.
        if G and G.deferShowLogin then G.deferShowLogin = false end
        EnterGame.show()
      end
    end)
  end
  if remaining > 0 then
    scheduledEvent = scheduleEvent(finish, remaining)
  else
    finish()
  end
end

local function nextStep()
  currentStep = currentStep + 1
  local step = steps[currentStep]
  if not step then
    -- finish respecting minimum display time
    finalizeStartup()
    return
  end
  -- run step and schedule next
  local ok, err = pcall(step.run)
  if not ok then
    -- even on error, try to continue to avoid a stuck UI
    g_logger.warning('Loader step error: ' .. tostring(err))
  end
  setProgress(step.percent, step.status)
  scheduledEvent = scheduleEvent(nextStep, step.delay or 50)
end

function Loader.init(loadModulesFunc)
  loadFn = loadModulesFunc
  local ok, win = pcall(g_ui.displayUI, 'loader')
  if ok and win then
    loaderWindow = win
    loaderWindow:show()
    loaderWindow:focus()
    loaderWindow:raise()
    -- Lock input to avoid user interaction during startup
    pcall(function() loaderWindow:grabMouse() end)
    pcall(function() loaderWindow:grabKeyboard() end)
    -- Ocultar todos os widgets visíveis, exceto o background e o próprio loader
    local root = g_ui.getRootWidget()
    hiddenWidgets = {}
    for _, child in ipairs(root:getChildren()) do
      local cid = child:getId() or ''
      if child ~= loaderWindow and cid ~= 'background' then
        if child:isVisible() then
          table.insert(hiddenWidgets, child)
          child:hide()
        end
      end
    end
    -- Ocultar também os filhos do background (botões, labels, etc.)
    local background = root:recursiveGetChildById('background')
    if background then
      for _, ch in ipairs(background:getChildren()) do
        if ch:isVisible() then
          table.insert(hiddenWidgets, ch)
          ch:hide()
        end
      end
      -- Esconder quaisquer novos filhos adicionados ao background durante o loader
      bgConn = {
        onChildAdded = function(parent, child)
          if not loaderWindow then return end
          table.insert(hiddenWidgets, child)
          child:hide()
        end
      }
      connect(background, bgConn)
    end
    -- Também oculte novos widgets adicionados enquanto o loader estiver ativo
    rootConn = {
      onChildAdded = function(parent, child)
        if not loaderWindow then return end
        local cid = child:getId() or ''
        -- Se o background for adicionado durante o loader, esconda seus filhos e conecte o hook
        if cid == 'background' then
          for _, ch in ipairs(child:getChildren()) do
            if ch:isVisible() then
              table.insert(hiddenWidgets, ch)
              ch:hide()
            end
          end
          if not bgConn then
            bgConn = {
              onChildAdded = function(p, ch)
                if not loaderWindow then return end
                table.insert(hiddenWidgets, ch)
                ch:hide()
              end
            }
            connect(child, bgConn)
          end
          return
        end
        if child ~= loaderWindow and cid ~= 'background' then
          table.insert(hiddenWidgets, child)
          child:hide()
        end
      end
    }
    connect(root, rootConn)
  else
    g_logger.warning('Failed to load loader UI; proceeding without UI')
  end
  startMillis = g_clock.millis()

  -- Define staged loading mirroring init.lua loadModules
  steps = {}

  local modules = g_modules.getModules()
  local autoModules = {}
  for _, m in pairs(modules) do
    if m:isAutoLoad() then table.insert(autoModules, m) end
  end
  table.sort(autoModules, function(a, b)
    if a:getAutoLoadPriority() == b:getAutoLoadPriority() then
      return a:getName() < b:getName()
    end
    return a:getAutoLoadPriority() < b:getAutoLoadPriority()
  end)

  -- Debug logs to verify loaded modules
  print(string.format("[Loader] Found %d autoload modules to load.", #autoModules))
  for i, m in ipairs(autoModules) do
    print(string.format("[Loader]   %02d. Priority: %d | Module: %s", i, m:getAutoLoadPriority(), m:getName()))
  end

  local function addModuleSteps(minP, maxP, startPct, endPct)
    local subset = {}
    for _, m in ipairs(autoModules) do
      local p = m:getAutoLoadPriority()
      if p > minP and p <= maxP then
        table.insert(subset, m)
      end
    end
    local count = #subset
    if count == 0 then return end
    for i, m in ipairs(subset) do
      local module = m
      local p = startPct + math.floor((i / count) * (endPct - startPct))
      table.insert(steps, {
        percent = p,
        status = tr('Loading module: %s', module:getName()),
        delay = 150,
        run = function() module:load() end
      })
    end
  end

  addModuleSteps(-999999, 499, 5, 25)

  table.insert(steps, {
    percent = 25,
    status = tr('Initializing client...'),
    delay = 150,
    run = function() g_modules.ensureModuleLoaded('client') end
  })

  addModuleSteps(499, 999, 25, 60)

  table.insert(steps, {
    percent = 65,
    status = tr('Preparing game interface...'),
    delay = 150,
    run = function() g_modules.ensureModuleLoaded('game_interface') end
  })

  addModuleSteps(999, 9999, 65, 90)

  table.insert(steps, {
    percent = 85,
    status = tr('Preloading minimap...'),
    delay = 150,
    run = preloadMinimap
  })

  table.insert(steps, {
    percent = 95,
    status = tr('Initializing mods...'),
    delay = 150,
    run = function() g_modules.ensureModuleLoaded('client_mods') end
  })

  setProgress(0, tr('Starting...'))
  currentStep = 0
  scheduledEvent = scheduleEvent(nextStep, 50)
end

function Loader.isActive()
  return loaderWindow ~= nil
end

function Loader.abort()
  removeEvent(scheduledEvent)
  if loaderWindow then
    pcall(function() loaderWindow:ungrabMouse() end)
    pcall(function() loaderWindow:ungrabKeyboard() end)
    loaderWindow:destroy()
    loaderWindow = nil
  end
  -- Desconecta hook de novos widgets
  local root = g_ui.getRootWidget()
  if rootConn then
    pcall(function() disconnect(root, rootConn) end)
    rootConn = nil
  end
  if bgConn then
    local background = root:recursiveGetChildById('background')
    pcall(function() if background then disconnect(background, bgConn) end end)
    bgConn = nil
  end
  -- Restaurar widgets ocultados
  for _, w in ipairs(hiddenWidgets) do
    if w and not w:isDestroyed() then
      w:show()
    end
  end
  hiddenWidgets = {}
  steps = {}
  currentStep = 0
  loadFn = nil
  -- Fallback: perform synchronous loading quickly
  g_modules.autoLoadModules(499)
  g_modules.ensureModuleLoaded('client')
  g_modules.autoLoadModules(999)
  g_modules.ensureModuleLoaded('game_interface')
  preloadMinimap()
  g_modules.autoLoadModules(9999)
  g_modules.ensureModuleLoaded('client_mods')
  local script = '/' .. g_app.getCompactName() .. 'rc.lua'
  if g_resources.fileExists(script) then
    local ok, err = pcall(dofile, script)
    if not ok then g_logger.warning('rc.lua error: ' .. tostring(err)) end
  end
  g_modules.enableAutoReload()
end

function Loader.setMinimumDisplay(ms)
  minDisplayMs = math.max(0, tonumber(ms) or minDisplayMs)
end

function init()
  -- no-op; the module will be triggered from init.lua
end

function terminate()
  removeEvent(scheduledEvent)
  if loaderWindow then
    pcall(function() loaderWindow:ungrabMouse() end)
    pcall(function() loaderWindow:ungrabKeyboard() end)
    loaderWindow:destroy()
    loaderWindow = nil
  end
  steps = {}
  currentStep = 0
  loadFn = nil
end
