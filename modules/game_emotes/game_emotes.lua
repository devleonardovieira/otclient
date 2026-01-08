local emoteWheel = nil
local wheel = nil
local slices = nil
local icons = nil
local indicator = nil
local lastEmoteId = nil
local centerPos = nil
local mousePos = nil
local openTime = 0

function init()
  g_ui.importStyle('game_emotes')

  emoteWheel = g_ui.createWidget('EmoteWheel', modules.game_interface.getRootPanel())
  
  if not emoteWheel then
      g_logger.error('Failed to create EmoteWheel widget.')
      return
  end
  
  emoteWheel:hide()

  wheel = emoteWheel:getChildById('wheel')
  slices = wheel:getChildById('slices')
  icons = wheel:getChildById('icons')
  indicator = emoteWheel:getChildById('indicator')

  createSlices()
  createEmoteWidgets()

  g_keyboard.bindKeyDown('G', show)
  g_keyboard.bindKeyUp('G', confirm)

  Creature.onEmote = onCreatureEmote
end

function createSlices()
  if not slices then return end
  slices:destroyChildren()
  wheel.slices = {}
  for i = 1, 8 do
    local s = g_ui.createWidget('EmoteSlice', slices)
    s:setRotation((i - 1) * 45)
    wheel.slices[i] = s
  end
end

function createEmoteWidgets()
  if not icons then return end
  icons:destroyChildren()

  local count = #Emotes
  if count == 0 then return end

  local size = wheel:getSize()
  local cx = size.width / 2
  local cy = size.height / 2
  local radius = math.floor(math.min(size.width, size.height) * 0.39)
  local step = 45

  for i, emote in ipairs(Emotes) do
    if i > 8 then break end

    local w = g_ui.createWidget('UIWidget', icons)
    w:setId('emoteWidget_' .. i)
    w:setSize({width = 48, height = 48})
    w:setImageSource(emote.icon)
    w:setOpacity(1.0)
    w:setPhantom(true)

    local deg = (i - 1) * step + (step / 2)
    local rad = math.rad(deg)
    local x = cx + math.cos(rad) * radius - 24
    local y = cy + math.sin(rad) * radius - 24

    w:setPosition({x = x, y = y})
  end
end


function terminate()
    g_keyboard.unbindKeyDown('G')
    g_keyboard.unbindKeyUp('G')
    
    if emoteWheel then
        emoteWheel:destroy()
        emoteWheel = nil
    end
    
    Creature.onEmote = nil
end

function show()
  if not g_game.isOnline() then return end
  if emoteWheel:isVisible() then return end

  emoteWheel:show()
  emoteWheel:raise()
  openTime = g_clock.millis()

  createEmoteWidgets()

  if updateEvent then updateEvent:cancel() end
  updateEvent = cycleEvent(updateWheel, 30)
end

function hide()
    emoteWheel:hide()
    if updateEvent then
        updateEvent:cancel()
        updateEvent = nil
    end
    indicator:setText("")
    if wheel and wheel.slices then
      for i = 1, 8 do
        if wheel.slices[i] then
          wheel.slices[i]:setOpacity(0)
        end
      end
    end
    lastEmoteId = nil
end

function confirm()
    if not emoteWheel:isVisible() then return end
    
    -- If key press was short (tap), keep the wheel open (toggle mode)
    if g_clock.millis() - openTime < 250 then
        return
    end
    
    if lastEmoteId then
        g_game.useEmote(lastEmoteId)
    end
    
    hide()
end

function updateWheel()
  if not emoteWheel:isVisible() then return end
  if not wheel or not wheel.slices then return end

  local mouse = g_window.getMousePosition()
  local pos = wheel:getPosition()
  local cx = pos.x + wheel:getWidth() / 2
  local cy = pos.y + wheel:getHeight() / 2

  local dx = mouse.x - cx
  local dy = mouse.y - cy

  local angle = math.deg(math.atan2(dy, dx))
  if angle < 0 then angle = angle + 360 end

  local index = math.floor(angle / 45) + 1
  if index < 1 or index > 8 then return end
  if not Emotes[index] then return end

  if lastEmoteId ~= index then
    for i = 1, 8 do
      if wheel.slices[i] then
        wheel.slices[i]:setOpacity(0)
      end
    end
    if wheel.slices[index] then
      wheel.slices[index]:setOpacity(1.0)
    end
  end

  lastEmoteId = index
  indicator:setText(Emotes[index].name)
end

function onCreatureEmote(creature, emoteId)
    local config = Emotes[emoteId]
    if not config then return end
    
    if config.effect then
        local effect = creature:attachEffect(config.effect)
        if effect then
            if config.scale then effect:setScale(config.scale) end
            if config.duration then
                scheduleEvent(function() effect:remove() end, config.duration)
            end
        end
    end
    
    if config.sound then
        g_sounds.play(config.sound)
    end
end
