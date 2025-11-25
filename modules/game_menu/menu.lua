Menu = {}
Menu.init = function ()
	g_ui.importStyle("menu.otui")

	Menu.window = g_ui.createWidget("MenuWidget", modules.game_interface.getRootPanel())
	Menu.icon = g_ui.createWidget("MenuIcon", modules.game_interface.getRootPanel())
	Menu.minimizeButton = g_ui.createWidget("MenuMinimizeButton", modules.game_interface.getRootPanel())
    Menu.tooltip = g_ui.createWidget("MenuTooltip", modules.game_interface.getRootPanel())

	-- Ensure layering: panel visible, icon/button above it
	Menu.window:raise()
	Menu.icon:raise()
	Menu.minimizeButton:raise()
	Menu.tooltip:raise()

	connect(g_game, {
		onGameEnd = Menu.onGameEnd
	})

	Menu.lastWindowSize = g_window.getSize()

	Menu.onResize()
	connect(rootWidget, {
		onUIResize = Menu.onResize
	})
	g_keyboard.bindKeyDown("Escape", Menu.tryCloseWindow)

	return 
end
Menu.terminate = function ()
	Menu.window:destroy()
	Menu.icon:destroy()
	Menu.minimizeButton:destroy()
	Menu.tooltip:destroy()
	disconnect(g_game, {
		onGameEnd = Menu.onGameEnd
	})
	disconnect(rootWidget, {
		onUIResize = Menu.onResize
	})
	g_keyboard.unbindKeyDown("Escape")

	return 
end
Menu.setup = function ()
	Menu.modules = {
		{
			name = "Character (%s)",
			shortCut = "X",
			icon = "IconCharacter",
			callback = modules.game_highscore.show,
			window = modules.game_highscore.ui
		},{
			name = "Inventory (%s)",
			shortCut = "I",
			icon = "IconInventory",
			callback = modules.game_inventory.toggle,
			window = modules.game_inventory.ui
		},
	
		--[[ {
			
		{
			name = "Map (M)",
			icon = "IconMap",
			callback = g_worldMap.toggle,
			window = g_worldMap.window
		},
		{
			name = "Professions (P)",
			icon = "IconProfessions",
			callback = modules.game_professions.GameProfessions.toggle,
			window = modules.game_professions.GameProfessions.window
		},
		{
			name = "Quest (L)",
			icon = "IconQuest",
			callback = modules.game_questlog.GameQuestLog.toggle,
			window = modules.game_questlog.GameQuestLog.window
		},
		{
			name = "Reputation (H)",
			icon = "IconReputation",
			callback = modules.game_reputation.GameReputation.toggle,
			window = modules.game_reputation.GameReputation.window
		},
		{
			name = "Settings (O)",
			icon = "IconSettings",
			callback = modules.game_settings.GameSettings.toggle,
			window = modules.game_settings.GameSettings.window
		},
		{
			name = "Skill Tree (K)",
			icon = "IconSkillTree",
			callback = modules.game_spelltree.GameSpellTree.toggle,
			window = modules.game_spelltree.GameSpellTree.window
		},
		{
			name = "Tradepack (T)",
			icon = "IconTradepack",
			callback = modules.game_tradepacks.GameTradepacks.toggle,
			window = modules.game_tradepacks.GameTradepacks.window
		},
		{
			name = "Transport (Y)",
			icon = "IconTransport",
			callback = modules.game_transport.GameTransport.toggle,
			window = modules.game_transport.GameTransport.window
		} ]]
	}

	for _, d in ipairs(Menu.modules) do
		local widget = g_ui.createWidget("MenuWidgetIcon", Menu.window.iconList)

		widget.setId(widget, d.icon)

		local nameText = d.name
		if d.shortCut then
			nameText = string.format(d.name, d.shortCut)
		end
		widget.iconDescription = nameText
		-- Versão colorida: deixa o atalho em verde e o restante branco
		local coloredShortcut = d.shortCut and ("[color=#36f991]" .. d.shortCut .. "[/color]") or nil
		local coloredText = coloredShortcut and string.format(d.name, coloredShortcut) or nameText
		widget.iconDescriptionColored = coloredText

		widget.icon:setImageSource(string.format("/images/ui/windows/menu/%s", d.icon))

        local textureWidth = widget.icon:getImageTextureWidth()
        local textureHeight = widget.icon:getImageTextureHeight()

        widget.setSize(widget, {
            width = math.max(16, textureWidth or 16),
            height = math.max(16, textureHeight or 16)
        })

        -- Também ligamos hover diretamente no ícone para máxima confiabilidade
        widget.icon.onHoverChange = function(_, hovered)
            Menu.onIconHoverChange(widget, hovered)
        end
        widget.icon.onEnter = function()
            Menu.onIconHoverChange(widget, true)
            return true
        end
        widget.icon.onLeave = function()
            Menu.onIconHoverChange(widget, false)
            return true
        end

		widget.onHoverChange = Menu.onIconHoverChange

		-- Show tooltip also on click/press anywhere on the tile
		widget.onMousePress = function(w, mousePos, button)
			Menu.onIconHoverChange(w, true)
			return false
		end

		widget.onMouseRelease = function(w, mousePos, button)
			Menu.onIconHoverChange(w, false)
			return false
		end
		widget.hoverSound = true
		widget.clickSound = true
		widget.onClick = d.callback
	end

	return 
end
Menu.onIconHoverChange = function (widget, hovered)
    if hovered then
        -- Texto com cores: atalho em verde, restante em branco
        if widget.iconDescriptionColored then
            Menu.tooltip:parseColoredText(widget.iconDescriptionColored, "#ffffff")
        else
            Menu.tooltip:setText(widget.iconDescription)
        end

        -- Usar a geometria real do ícone e posicionar com setX/setY no root
        local icon = widget:getChildById('icon')
        local target = icon or widget

        local spacing = 6 -- gap entre topo do ícone e base do tooltip
        Menu.tooltip:show()
        Menu.tooltip:raise()
        addEvent(function()
            local iconCenterX = target:getX() + math.floor(target:getWidth() / 2)
            local tooltipHalf = math.floor(Menu.tooltip:getWidth() / 2)
            local tooltipX = iconCenterX - tooltipHalf
            local tooltipY = target:getY() - spacing - Menu.tooltip:getHeight() - 9
            Menu.tooltip:setX(tooltipX)
            Menu.tooltip:setY(tooltipY)

        end)
    else
        Menu.tooltip:hide()
    end

    return 
end
Menu.onGameEnd = function ()
	for _, data in pairs(Menu.modules) do
		if data.window and data.window:isVisible() then
			data.callback()
		end
	end

	return 
end
Menu.onResize = function ()
	if not Menu.modules then
		return 
	end

	local size = g_window.getSize()

	if Menu.lastWindowSize.width == size.width and Menu.lastWindowSize.height == size.height then
		return 
	end

	Menu.lastWindowSize = size
	local widthScale = size.width/1920
	local heightScale = size.height/1080

	if g_window.isMaximized() and (widthScale == 1 or heightScale == 1) then
		g_app.scale(1)

		return 
	end

	local scale = math.min(1.35, math.min(widthScale, heightScale))
	scale = math.max(0.7, math.ceil(scale*20)/20)

	g_app.scale(scale)

	return 
end
Menu.tryCloseWindow = function ()
	local panel = modules.game_interface.getRootPanel()

	if not panel or not panel.isVisible(panel) then
		return 
	end

	table.sort(Menu.modules, function (a, b)
		return panel:getChildIndex(b.window) < panel:getChildIndex(a.window)
	end)

	for _, data in ipairs(Menu.modules) do
		if data.window and data.window:isVisible() then
			data.callback()

			return 
		end
	end

	return 
end

-- The menu widget is created during Menu.init; define expansion helpers
-- on the Menu table to avoid referencing Menu.window before it exists.
function Menu.expand()
  local self = Menu.window
  if not self or self:isDestroyed() then return end
  -- Cancel ongoing animations
  removeEvent(Menu.slideEvent)
  g_effects.cancelFade(self)

  -- Prepare initial state and show
  self:show()
  self:setOpacity(0)

  -- Hide tooltip during animation
  if Menu.tooltip and not Menu.tooltip:isDestroyed() then
    Menu.tooltip:hide()
  end

  -- Target dimensions: match icon content width (icons + spacing + container margins)
  local list = self.iconList
  local spacing = 11
  local totalW, count = 0, 0
  if list and not list:isDestroyed() then
    local i = 1
    while true do
      local c = list:getChildByIndex(i)
      if not c then break end
      totalW = totalW + c:getWidth()
      count = count + 1
      i = i + 1
    end
  end
  local contentW = totalW + math.max(0, count - 1) * spacing
  local margins = 0
  if list then
    margins = list:getMarginLeft() + list:getMarginRight()
  end
  local targetW = math.max(10, contentW + margins)
  local startW = 10
  local h = self:getHeight()
  self:resize(startW, h)

  -- Run fade + slide in parallel
  local duration = 400
  g_effects.fadeIn(self, duration)
  local elapsed = 0
  local function step()
    elapsed = elapsed + 16
    local p = math.min(elapsed / duration, 1)
    local newW = math.floor(startW + (targetW - startW) * p)
    self:resize(newW, h)
    if p < 1 then
      Menu.slideEvent = scheduleEvent(step, 16)
    else
      Menu.slideEvent = nil
      self:resize(targetW, h)
      if Menu.minimizeButton and not Menu.minimizeButton:isDestroyed() then
        Menu.minimizeButton:setVisible(true)
      end
    end
  end
  Menu.slideEvent = scheduleEvent(step, 0)
end

function Menu.collapse()
  local self = Menu.window
  if not self or self:isDestroyed() then return end
  -- Cancel ongoing animations
  removeEvent(Menu.slideEvent)
  g_effects.cancelFade(self)

  -- Fade out and slide to collapsed width
  local startW = self:getWidth()
  local targetW = 10
  local h = self:getHeight()
  local duration = 400
  g_effects.fadeOut(self, duration)
  local elapsed = 0
  local function step()
    elapsed = elapsed + 16
    local p = math.min(elapsed / duration, 1)
    local newW = math.floor(startW + (targetW - startW) * p)
    self:resize(newW, h)
    if p < 1 then
      Menu.slideEvent = scheduleEvent(step, 16)
    else
      Menu.slideEvent = nil
      self:resize(targetW, h)
      self:hide()
      if Menu.tooltip and not Menu.tooltip:isDestroyed() then
        Menu.tooltip:hide()
      end
      if Menu.minimizeButton and not Menu.minimizeButton:isDestroyed() then
        Menu.minimizeButton:setVisible(false)
      end
    end
  end
  Menu.slideEvent = scheduleEvent(step, 0)
end
