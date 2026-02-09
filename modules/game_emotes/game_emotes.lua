local EmoteWheel = {
  widget = nil,
  wheel = nil,
  icons = nil,
  indicator = nil,

  iconWidgets = {},
  iconBases = {},

  hovered = nil,
  
  openTime = 0,
  updateEvent = nil,

  center = { x = 0, y = 0 },
  radius = 0,
  half = 0,
  
  mapPosition = nil,
  previewEffect = nil
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

  -- Register Emote Effects
  local startId = 5000
  for i, emote in pairs(Emotes) do
    if emote.effect and type(emote.effect) == 'string' then
       local id = startId + i
       if not AttachedEffectManager.get(id) then
         AttachedEffectManager.register(id, emote.name or ('Emote'..i), emote.effect, ThingExternalTexture, {
            size = { 100, 100 }, -- Default size, can be adjusted
            duration = emote.duration or 0,
            loop = emote.loop ~= false and -1 or 1
         })
       end
       emote.effectId = id
    end
    
    -- Normalize effect lookup
    emote._resolvedEffectId = emote.effectId or (type(emote.effect) == 'number' and emote.effect) or nil
  end

  g_keyboard.bindKeyDown('Ctrl+G', EmoteWheel.onKeyDown)
  g_keyboard.bindKeyUp('Ctrl+G', EmoteWheel.onKeyUp)

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
  local pos = self.widget:getPosition()
  local size = self.widget:getSize()
  self.center.x = pos.x + size.width / 2
  self.center.y = pos.y + size.height / 2
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
  if not self.hovered then return end

  if self.previewEffect then
    self.previewEffect:remove()
    self.previewEffect = nil
  end

  if self.hovered then
    local base = self.iconBases[self.hovered]
    if base then
        self:applyState(self.hovered, base.size, 0.5)
    end
  end
  self.hovered = nil
  self.indicator:setText("")
end

function EmoteWheel:setHover(index)
  if self.hovered == index then return end
  
  -- Debounce hover to prevent rapid flashing and effect spawning
  if self._pendingHover ~= index then
     self._pendingHover = index
     self._hoverStart = g_clock.millis()
     return
  end
  
  if g_clock.millis() - self._hoverStart < 80 then
     return
  end
  self._pendingHover = nil

  if self.hovered then
    local base = self.iconBases[self.hovered]
    if base then
        self:applyState(self.hovered, base.size, 0.5)
    end
  end

  self.hovered = index

  self:applyState(index, 110, 1)
  self.iconWidgets[index]:raise()
  self.indicator:setText(Emotes[index].name)

  -- Preview Effect on Map
  local emote = Emotes[index]
  if emote and self.mapPosition then
      -- Remove previous preview effect if exists
      if self.previewEffect then
          self.previewEffect:remove()
          self.previewEffect = nil
      end

      local tile = g_map.getTile(self.mapPosition)
      if tile then
          local effectThing = nil
          
          if emote._resolvedEffectId then
              effectThing = g_attachedEffects.getById(emote._resolvedEffectId)
          end
          
          if effectThing then
              local effect = tile:attachEffect(effectThing)
              if effect then
                  effect:setOffset(0, -80)
                  self.previewEffect = effect
              end
          end
      end
  end
end

function EmoteWheel:update()
  local mouse = g_window.getMousePosition()
  if self._lastMouse and mouse.x == self._lastMouse.x and mouse.y == self._lastMouse.y then
    return
  end
  self._lastMouse = mouse

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
  
  -- Capture Map Position
  self.mapPosition = nil
  local player = g_game.getLocalPlayer()
  if player then
      self.mapPosition = player:getPosition() -- Default to player position
  end

  local gameMap = modules.game_interface.getMapPanel()
  if gameMap then
      local mapPos = gameMap:getPosition(mousePos)
      if mapPos then
          self.mapPosition = mapPos
      end
  end
  
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

  if self.hovered then
    local emote = self.hovered
    self:clearHover()
    g_game.useEmote(emote)
  end

  self:hide()
end

function onCreatureEmote(creature, emoteId)
    local config = Emotes[emoteId]
    if not config then return end
    
    local effect = nil
    if config._resolvedEffectId then
        effect = creature:attachEffect(g_attachedEffects.getById(config._resolvedEffectId))
    end

    if effect then
        -- Position based on EmoteWheel map position if available and creature is local player
        if creature:isLocalPlayer() and EmoteWheel.mapPosition then
             local tile = g_map.getTile(EmoteWheel.mapPosition)
             if tile then
                -- Remove the effect from creature and attach to tile instead
                effect:remove()
                
                local newEffect = nil
                if config._resolvedEffectId then
                    newEffect = tile:attachEffect(g_attachedEffects.getById(config._resolvedEffectId))
                end
                
                if newEffect then
                    effect = newEffect -- Update reference
                    effect:setOffset(0, -80)
                end
             else
                effect:setOffset(0, -80)
             end
        else
             -- Default position above player's head
             effect:setOffset(0, -80)
        end

        if config.scale then effect:setScale(config.scale) end
        if config.duration then
            scheduleEvent(function() if effect then effect:remove() end end, config.duration)
        end
    end
    
    if config.sound then
        g_sounds.play(config.sound)
    end
end
