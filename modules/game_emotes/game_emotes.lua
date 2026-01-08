local emoteWheel = nil
local wheel = nil
local icons = nil
local indicator = nil
local lastEmoteId = nil
local centerPos = nil
local mousePos = nil
local openTime = 0
local updateEvent = nil
local iconWidgets = {}
local iconBases = {}
local hoveredIndex = nil

function init()
  g_ui.importStyle('game_emotes')

  emoteWheel = g_ui.createWidget('EmoteWheel', modules.game_interface.getRootPanel())
  
  if not emoteWheel then
      g_logger.error('Failed to create EmoteWheel widget.')
      return
  end
  
  emoteWheel:hide()

  wheel = emoteWheel:getChildById('wheel')
icons = wheel:getChildById('icons')
  indicator = emoteWheel:getChildById('indicator')

  createEmoteWidgets()

  g_keyboard.bindKeyDown('G', show)
  g_keyboard.bindKeyUp('G', confirm)

  Creature.onEmote = onCreatureEmote
end

function createEmoteWidgets()
  if not icons then return end
  icons:destroyChildren()
  iconWidgets = {}
  iconBases = {}

  local count = #Emotes
  if count == 0 then return end

  local size = wheel:getSize()
  local cx = size.width / 2
  local cy = size.height / 2
  local half = math.min(size.width, size.height) / 2
  local radius = math.floor(half * 0.62)
  local step = 360 / 8
  local iconSize = 88

  for i = 1, 8 do
    local emote = Emotes[i]
    if emote and emote.icon then
      print('Emote: ' .. emote.name .. ' Icon: ' .. emote.icon)

      local w = g_ui.createWidget('UIImageView', icons)
      w:setId('emoteWidget_' .. i)
      w:setSize({width = iconSize, height = iconSize})
      w:setImageSource(emote.icon)
      w:setOpacity(0.7)
 

      local deg = (i - 1) * step
      local rad = math.rad(deg - 90)
      local centerX = cx + math.cos(rad) * radius
      local centerY = cy + math.sin(rad) * radius
      local x = math.floor(centerX - (iconSize / 2))
      local y = math.floor(centerY - (iconSize / 2))
      print('Created emote widget:', w, 'pos:', x, y)
      w:addAnchor(AnchorLeft, 'parent', AnchorLeft)
      w:addAnchor(AnchorTop, 'parent', AnchorTop)
      w:setMarginLeft(x)
      w:setMarginTop(y)
      iconWidgets[i] = w
      iconBases[i] = { cx = centerX, cy = centerY, size = iconSize }
    end
  end
end

local function applyIconState(index, size, opacity)
  local w = iconWidgets[index]
  local base = iconBases[index]
  if not w or not base then return end
  w:setOpacity(opacity)
  w:setSize({ width = size, height = size })
  local x = math.floor(base.cx - (size / 2))
  local y = math.floor(base.cy - (size / 2))
  w:setMarginLeft(x)
  w:setMarginTop(y)
end

local function clearHover()
  if hoveredIndex then
    local base = iconBases[hoveredIndex]
    if base then
      applyIconState(hoveredIndex, base.size, 0.7)
    end
  end
  hoveredIndex = nil
  lastEmoteId = nil
  indicator:setText("")
end

local function setHover(index)
  if hoveredIndex == index then return end
  if hoveredIndex then
    local base = iconBases[hoveredIndex]
    if base then
      applyIconState(hoveredIndex, base.size, 0.7)
    end
  end
  hoveredIndex = index
  lastEmoteId = index
  applyIconState(index, 64, 1.0)
  if iconWidgets[index] then
    iconWidgets[index]:raise()
  end
  indicator:setText(Emotes[index].name)
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
  clearHover()

  if updateEvent then updateEvent:cancel() end
  updateEvent = cycleEvent(updateWheel, 30)
end

function hide()
    emoteWheel:hide()
    if updateEvent then
        updateEvent:cancel()
        updateEvent = nil
    end
    clearHover()
end

function confirm()
    if not emoteWheel:isVisible() then return end
    
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
  if not wheel then return end

  local mouse = g_window.getMousePosition()
  local basePos = emoteWheel:getPosition()
  local wheelPos = wheel:getPosition()
  local cx = basePos.x + wheelPos.x + wheel:getWidth() / 2
  local cy = basePos.y + wheelPos.y + wheel:getHeight() / 2

  local dx = mouse.x - cx
  local dy = mouse.y - cy

  local dist = math.sqrt(dx * dx + dy * dy)
  local half = math.min(wheel:getWidth(), wheel:getHeight()) / 2
  if dist < (half * 0.22) or dist > (half * 0.95) then
    if hoveredIndex then clearHover() end
    return
  end

  local angle = math.deg(math.atan2(dy, dx))
  if angle < 0 then angle = angle + 360 end

  local visual = angle + 90
  if visual >= 360 then visual = visual - 360 end

  local index = (math.floor((visual + 22.5) / 45) % 8) + 1
  if not Emotes[index] or not iconWidgets[index] then
    if hoveredIndex then clearHover() end
    return
  end

  setHover(index)
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
