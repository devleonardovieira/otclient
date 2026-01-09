local EmoteWheel = {
  widget = nil,
  wheel = nil,
  icons = nil,
  indicator = nil,

  iconWidgets = {},
  iconBases = {},

  hovered = nil,
  lastEmote = nil,

  openTime = 0,
  updateEvent = nil,

  center = { x = 0, y = 0 },
  radius = 0,
  half = 0
}

function EmoteWheel.onKeyDown()
  EmoteWheel:show()
end

function EmoteWheel.onKeyUp()
  EmoteWheel:confirm()
end

function init()
  g_ui.importStyle('game_emotes')
  
  EmoteWheel.widget = g_ui.createWidget('EmoteWheel', modules.game_interface.getRootPanel())
  if not EmoteWheel.widget then return end
  
  EmoteWheel.widget:hide()
  
  EmoteWheel.wheel = EmoteWheel.widget:getChildById('wheel')
  EmoteWheel.icons = EmoteWheel.wheel:getChildById('icons')
  EmoteWheel.indicator = EmoteWheel.widget:getChildById('indicator')

  EmoteWheel:createIcons()

  g_keyboard.bindKeyDown('G', EmoteWheel.onKeyDown)
  g_keyboard.bindKeyUp('G', EmoteWheel.onKeyUp)

  Creature.onEmote = onCreatureEmote
end

function terminate()
  g_keyboard.unbindKeyDown('G', EmoteWheel.onKeyDown)
  g_keyboard.unbindKeyUp('G', EmoteWheel.onKeyUp)

  if EmoteWheel.updateEvent then
    EmoteWheel.updateEvent:cancel()
    EmoteWheel.updateEvent = nil
  end

  if EmoteWheel.widget then
    EmoteWheel.widget:destroy()
    EmoteWheel.widget = nil
  end

  Creature.onEmote = nil
end

function EmoteWheel:createIcons()
  if self._pendingCreate then return end

  local size = self.wheel:getSize()
  if size.width == 0 or size.height == 0 then
    self._pendingCreate = true
    scheduleEvent(function() 
      self._pendingCreate = nil 
      self:createIcons() 
    end, 50)
    return
  end

  self.icons:destroyChildren()
  self.iconWidgets = {}
  self.iconBases = {}

  local cx, cy = size.width / 2, size.height / 2
  self.half = math.min(size.width, size.height) / 2
  self.radius = math.floor(self.half * 0.62)

  local step = 360 / 8
  local iconSize = 88

  for i = 1, 8 do
    local emote = Emotes[i]
    if emote and emote.icon then
      local w = g_ui.createWidget('UIImageView', self.icons)
      w:setId('emote_' .. i)
      w:setSize({ width = iconSize, height = iconSize })
      w:setImageSource(emote.icon)
      w:setOpacity(0.5)

      local rad = math.rad((i - 1) * step - 90 + 22.5)
      local cxIcon = cx + math.cos(rad) * self.radius
      local cyIcon = cy + math.sin(rad) * self.radius

      w:addAnchor(AnchorLeft, 'parent', AnchorLeft)
      w:addAnchor(AnchorTop, 'parent', AnchorTop)
      w:setMarginLeft(cxIcon - iconSize / 2)
      w:setMarginTop(cyIcon - iconSize / 2)

      self.iconWidgets[i] = w
      self.iconBases[i] = {
        cx = cxIcon,
        cy = cyIcon,
        size = iconSize
      }
    end
  end
end

function EmoteWheel:updateCenter()
  local rect = self.wheel:getRect()
  self.center.x = rect.x + rect.width / 2
  self.center.y = rect.y + rect.height / 2
end

function EmoteWheel:applyState(index, size, opacity)
  local w = self.iconWidgets[index]
  local base = self.iconBases[index]
  if not w or not base then return end

  if w:getOpacity() ~= opacity then
    w:setOpacity(opacity)
  end

  if w:getWidth() ~= size then
    w:setSize({ width = size, height = size })
    w:setMarginLeft(base.cx - size / 2)
    w:setMarginTop(base.cy - size / 2)
  end
end

function EmoteWheel:clearHover()
  if self.hovered then
    local base = self.iconBases[self.hovered]
    if base then
        self:applyState(self.hovered, base.size, 0.5)
    end
  end
  self.hovered = nil
  self.lastEmote = nil
  self.indicator:setText("")
end

function EmoteWheel:setHover(index)
  if self.hovered == index then return end

  if self.hovered then
    local base = self.iconBases[self.hovered]
    self:applyState(self.hovered, base.size, 0.5)
  end

  self.hovered = index
  self.lastEmote = index

  self:applyState(index, 110, 1)
  self.iconWidgets[index]:raise()
  self.indicator:setText(Emotes[index].name)
end

function EmoteWheel:update()
  local mouse = g_window.getMousePosition()

  local dx = mouse.x - self.center.x
  local dy = mouse.y - self.center.y

  local dist2 = dx*dx + dy*dy
  local min = self.half * 0.22
  local max = self.half * 0.95

  if dist2 < min*min or dist2 > max*max then
    if self.hovered then self:clearHover() end
    return
  end

  local angle = math.deg(math.atan2(dy, dx))
  if angle < 0 then angle = angle + 360 end

  local index = ((math.floor((angle + 90) / 45)) % 8) + 1

  if not self.iconWidgets[index] then
    if self.hovered then self:clearHover() end
    return
  end

  self:setHover(index)
end

function EmoteWheel:show()
  if not g_game.isOnline() then return end
  if self.widget:isVisible() then return end

  self.widget:show()
  self.widget:raise()

  self.widget:breakAnchors()
  local mousePos = g_window.getMousePosition()
  local size = self.widget:getSize()
  local parent = self.widget:getParent()
  local parentSize = parent:getSize()

  local x = math.max(0, math.min(mousePos.x - size.width / 2, parentSize.width - size.width))
  local y = math.max(0, math.min(mousePos.y - size.height / 2, parentSize.height - size.height))

  self.widget:setPosition({x = x, y = y})
  self:updateCenter()

  self.openTime = g_clock.millis()
  self:clearHover()

  if self.updateEvent then self.updateEvent:cancel() end
  self.updateEvent = cycleEvent(function() self:update() end, 30)
end

function EmoteWheel:hide()
  if not self.widget then return end
  if not self.widget:isVisible() then return end

  self.widget:hide()
  if self.updateEvent then
    self.updateEvent:cancel()
    self.updateEvent = nil
  end
  self:clearHover()
end

function EmoteWheel:confirm()
  if not self.widget:isVisible() then return end

  if g_clock.millis() - self.openTime < 250 then
    return
  end

  if self.lastEmote then
    local emote = self.lastEmote
    self:clearHover()
    g_game.useEmote(emote)
  end

  self:hide()
end

function onCreatureEmote(creature, emoteId)
    local config = Emotes[emoteId]
    if not config then return end
    
    if config.effect then
        local effect = creature:attachEffect(config.effect)
        if effect then
            if config.scale then effect:setScale(config.scale) end
            if config.duration then
                scheduleEvent(function() if effect then effect:remove() end end, config.duration)
            end
        end
    end
    
    if config.sound then
        g_sounds.play(config.sound)
    end
end
