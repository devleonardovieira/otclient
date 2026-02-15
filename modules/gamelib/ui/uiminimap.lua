-- chunkname: @/modules/gamelib/ui/uiminimap.lua

local DEFAULT_MINIMAP_ZOOM_MAX = 5
local CROSS_WALK_TICK_MS = 16

local function cancelCrossAnimation(widget)
	if not widget then
		return
	end

	if widget.crossMoveEvent then
		removeEvent(widget.crossMoveEvent)
		widget.crossMoveEvent = nil
	end

	if widget.crossWalkEvent then
		removeEvent(widget.crossWalkEvent)
		widget.crossWalkEvent = nil
	end
end

local function forceWidgetRepaint(widget)
	if not widget or widget:isDestroyed() then
		return
	end

	if widget.repaint then
		widget:repaint()
	end
end

local function setCrossScreenPosition(widget, cross, target)
	local snapped = {
		x = math.floor(target.x + 0.5),
		y = math.floor(target.y + 0.5)
	}

	local current = cross:getPosition()
	if current and current.x == snapped.x and current.y == snapped.y then
		return false
	end

	cross:setPosition(snapped)
	forceWidgetRepaint(widget)
	return true
end

local function getCrossTarget(widget, cross, pos)
	local cameraPos = widget:getCameraPosition()
	local followCentered = not widget.fullView and not widget:isDragging() and cameraPos
		and cameraPos.x == pos.x and cameraPos.y == pos.y and cameraPos.z == pos.z
	if followCentered then
		local rect = widget:getPaddingRect()
		if rect and rect.width and rect.height then
			return {
				x = rect.x + rect.width / 2 - cross:getWidth() / 2,
				y = rect.y + rect.height / 2 - cross:getHeight() / 2
			}
		end
	end

	local screenPos = nil
	local player = g_game.getLocalPlayer()
	local hasWalkSegment = widget.crossWalkFromPos and widget.crossWalkToPos

	if hasWalkSegment and player and player.isWalking and player.getStepProgress and player:isWalking() then
		local fromTile = widget:getTilePoint(widget.crossWalkFromPos)
		local toTile = widget:getTilePoint(widget.crossWalkToPos)
		if fromTile and toTile and fromTile.x >= 0 and fromTile.y >= 0 and toTile.x >= 0 and toTile.y >= 0 then
			local t = math.max(0, math.min(player:getStepProgress(), 1))
			screenPos = {
				x = fromTile.x + (toTile.x - fromTile.x) * t,
				y = fromTile.y + (toTile.y - fromTile.y) * t
			}
		end
	end

	if not screenPos then
		screenPos = widget:getTilePoint(pos)
	end

	if not screenPos or screenPos.x < 0 or screenPos.y < 0 then
		return nil
	end

	return {
		x = screenPos.x - cross:getWidth() / 2,
		y = screenPos.y - cross:getHeight() / 2
	}
end

local function startCrossWalkLoop(widget)
	if not widget or widget.crossWalkEvent then
		return
	end

	local function tick()
		if not widget or widget:isDestroyed() then
			return
		end

		local cross = widget.cross
		if not cross or cross:isDestroyed() or not cross.pos then
			widget.crossWalkEvent = nil
			return
		end

		local target = getCrossTarget(widget, cross, cross.pos)
		if target then
			setCrossScreenPosition(widget, cross, target)
		end

		local player = g_game.getLocalPlayer()
		if player and player.isWalking and player:isWalking() and widget.crossWalkFromPos and widget.crossWalkToPos then
			widget.crossWalkEvent = scheduleEvent(tick, CROSS_WALK_TICK_MS)
		else
			widget.crossWalkEvent = nil
			widget.crossWalkFromPos = nil
			widget.crossWalkToPos = nil
		end
	end

	tick()
end

local function getMinimapZoomMin(widget)
	if widget and widget.getMaxZoom then
		local maxZoom = widget:getMaxZoom()
		if type(maxZoom) == 'number' then
			return maxZoom - 1
		end
	end

	return DEFAULT_MINIMAP_ZOOM_MAX - 1
end

local function getMinimapZoomMax(widget)
	if widget and widget.getMaxZoom then
		local maxZoom = widget:getMaxZoom()
		if type(maxZoom) == 'number' then
			return maxZoom
		end
	end

	return DEFAULT_MINIMAP_ZOOM_MAX
end

local function clampMinimapZoom(widget, zoom)
	local minZoom = getMinimapZoomMin(widget)
	local maxZoom = getMinimapZoomMax(widget)
	zoom = tonumber(zoom) or minZoom
	if zoom < minZoom then return minZoom end
	if zoom > maxZoom then return maxZoom end
	return zoom
end

function UIMinimap:onCreate()
	self.autowalk = true
	-- Garantir estado inicial: não está em modo fullView
	self.fullView = false
	-- Inicializa estruturas para evitar nil em chamadas precoces
	self.alternatives = {}
	self.flags = {}
end

function UIMinimap:onSetup()
	self.flagWindow = nil
	self.flags = {}
	self.alternatives = {}

	function self.onAddAutomapFlag(pos, icon, description)
		self:addFlag(pos, icon, description)
	end

	function self.onRemoveAutomapFlag(pos, icon, description)
		self:removeFlag(pos, icon, description)
	end

	connect(g_game, {
		onAddAutomapFlag = self.onAddAutomapFlag,
		onRemoveAutomapFlag = self.onRemoveAutomapFlag
	})

	-- Garantir que o painel de controles do fullmap inicie oculto em miniwindow
	local panelControls = self:getChildById('panelControls')
	if panelControls then panelControls:hide() end
	self.fullView = false
	-- Evitar widgets alternativos visíveis fora do fullmap
	if self.setAlternativeWidgetsVisible then
		self:setAlternativeWidgetsVisible(false)
	end
end

function UIMinimap:onDestroy()
	cancelCrossAnimation(self)
	if self.dragRestoreHDMode ~= nil and g_minimap and g_minimap.setHDMode then
		g_minimap:setHDMode(self.dragRestoreHDMode)
		self.dragRestoreHDMode = nil
	end

	for _, widget in pairs(self.alternatives) do
		widget:destroy()
	end

	self.alternatives = {}

	disconnect(g_game, {
		onAddAutomapFlag = self.onAddAutomapFlag,
		onRemoveAutomapFlag = self.onRemoveAutomapFlag
	})
	self:destroyFlagWindow()

	self.flags = {}
end

function UIMinimap:onVisibilityChange()
	if not self:isVisible() then
		self:destroyFlagWindow()
	end

	-- Sincroniza a visibilidade do painel de controles do fullmap com o estado fullView
	local panelControls = self:getChildById('panelControls')
	if panelControls then
		if self.fullView then
			panelControls:show()
		else
			panelControls:hide()
		end
	end
end

function UIMinimap:onCameraPositionChange(cameraPos)
	if self.cross then
		self:setCrossPosition(self.cross.pos, true)
	end
end

function UIMinimap:hideFloor()
	if self.floorUpWidget then self.floorUpWidget:hide() end
	if self.floorDownWidget then self.floorDownWidget:hide() end
end

function UIMinimap:hideZoom()
	if self.zoomInWidget then self.zoomInWidget:hide() end
	if self.zoomOutWidget then self.zoomOutWidget:hide() end
end

function UIMinimap:disableAutoWalk()
	self.autowalk = false
end

function UIMinimap:load()
	local settings = g_settings.getNode("Minimap")

	if settings then
		if settings.flags then
			for _, flag in pairs(settings.flags) do
				self:addFlag(flag.position, flag.icon, flag.description, flag.temporary, tocolor(flag.color))
			end
		end

		self:setZoom(clampMinimapZoom(self, settings.zoom))
	end
end

function UIMinimap:save()
	local settings = {
		flags = {}
	}

	for _, flag in pairs(self.flags) do
		if not flag.temporary then
			table.insert(settings.flags, {
				position = flag.pos,
				icon = flag.icon,
				description = flag.description,
				color = colortostring(flag.color)
			})
		end
	end

	settings.zoom = self:getZoom()

	g_settings.setNode("Minimap", settings)
end

local function onFlagMouseRelease(widget, pos, button)
	if button == MouseRightButton then
		local menu = g_ui.createWidget("PopupMenu")

		menu:setGameMenu(true)
		menu:addOption(tr("Delete mark"), function()
			widget:destroy()
		end)
		menu:display(pos)

		return true
	end

	return false
end

function UIMinimap:setCrossPosition(pos, instant)
	local cross = self.cross

	if not self.cross then
		cross = g_ui.createWidget("MinimapCross", self)

		if cross.setImageSource then
			cross:setImageSource("/images/game/minimap/cross_white")
		else
			cross:setIcon("/images/game/minimap/cross_white")
		end
		if cross.setImageColor then
			cross:setImageColor("green")
		elseif cross.setIconColor then
			cross:setIconColor("green")
		end

		self.cross = cross
	end

	if not pos then
		cancelCrossAnimation(self)
		cross.pos = nil
		self.crossWalkFromPos = nil
		self.crossWalkToPos = nil
		if not self.crossUsesManualPosition then
			cross:breakAnchors()
			self.crossUsesManualPosition = true
		end
		return
	end

	pos = {
		x = pos.x,
		y = pos.y,
		z = self:getCameraPosition().z
	}

	if not instant and cross.pos and cross.pos.x == pos.x and cross.pos.y == pos.y and cross.pos.z == pos.z then
		local player = g_game.getLocalPlayer()
		if player and player.isWalking and player:isWalking() and self.crossWalkFromPos and self.crossWalkToPos then
			startCrossWalkLoop(self)
		end
		return
	end

	local previousPos = self.crossLastPos
	cross.pos = pos

	if not self.crossUsesManualPosition then
		cross:breakAnchors()
		self.crossUsesManualPosition = true
	end

	self.crossWalkFromPos = nil
	self.crossWalkToPos = nil
	local cameraPos = self:getCameraPosition()
	local followCentered = not self.fullView and not self:isDragging() and cameraPos
		and cameraPos.x == pos.x and cameraPos.y == pos.y and cameraPos.z == pos.z
	if not followCentered and previousPos and previousPos.z == pos.z then
		local walkDx = math.abs(pos.x - previousPos.x)
		local walkDy = math.abs(pos.y - previousPos.y)
		if walkDx <= 1 and walkDy <= 1 and (walkDx + walkDy) > 0 then
			self.crossWalkFromPos = previousPos
			self.crossWalkToPos = pos
		end
	end

	local target = getCrossTarget(self, cross, pos)
	if not target then
		cancelCrossAnimation(self)
		cross:breakAnchors()
		return
	end

	setCrossScreenPosition(self, cross, target)

	local player = g_game.getLocalPlayer()
	if player and player.isWalking and player:isWalking() and self.crossWalkFromPos and self.crossWalkToPos then
		startCrossWalkLoop(self)
	elseif self.crossWalkEvent then
		removeEvent(self.crossWalkEvent)
		self.crossWalkEvent = nil
	end

	self.crossLastPos = pos
end

function UIMinimap:addFlag(pos, icon, description, temporary, color)
	if not pos or not icon then
		return
	end

	local flag = self:getFlag(pos, icon, description)

	if flag or not icon then
		return
	end

	temporary = temporary or false
	color = color or "white"
	flag = g_ui.createWidget("MinimapFlag")

	self:insertChild(1, flag)

	flag.pos = pos
	flag.description = description
	flag.icon = icon
	flag.temporary = temporary
	flag.color = color

	if type(tonumber(icon)) == "number" then
		flag:setIcon("/images/game/minimap/flag" .. icon)
	else
		flag:setIcon(resolvepath(icon, 1))
	end

	flag:setIconColor(color)
	flag:setTooltip(description)

	flag.onMouseRelease = onFlagMouseRelease

	function flag.onDestroy()
		table.removevalue(self.flags, flag)
	end

	table.insert(self.flags, flag)
	self:centerInPosition(flag, pos)
end

function UIMinimap:addAlternativeWidget(widget, pos, minZoom, maxZoom)
	widget.pos = pos
	widget.minZoom = minZoom
	widget.maxZoom = maxZoom or getMinimapZoomMax(self)
	table.insert(self.alternatives, widget)
end

function UIMinimap:onZoomChange(zoom)
	local clampedZoom = clampMinimapZoom(self, zoom)
	if clampedZoom ~= zoom then
		self:setZoom(clampedZoom)
		return
	end

	if self.cross and self.cross.pos then
		self:setCrossPosition(self.cross.pos, true)
	end

	if self.fullView then
		for _, widget in pairs(self.alternatives) do
			local minZ = widget.minZoom or getMinimapZoomMin(self)
			local maxZ = widget.maxZoom or getMinimapZoomMax(self)
			if zoom >= minZ and zoom <= maxZ then
				widget:show()
			else
				widget:hide()
			end
		end
	end
end

function UIMinimap:setAlternativeWidgetsVisible(show)
	-- Proteção: evita erro se alternativas ainda não estiver inicializado
	if not self.alternatives or type(self.alternatives) ~= 'table' then
		self.alternatives = {}
		return
	end

	for _, widget in pairs(self.alternatives) do
		if show then
			widget:show()
		else
			widget:hide()
		end
	end
end

function UIMinimap:zoomIn()
	self:setZoom(clampMinimapZoom(self, self:getZoom() + 1))
end

function UIMinimap:zoomOut()
	self:setZoom(clampMinimapZoom(self, self:getZoom() - 1))
end

function UIMinimap:getFlag(pos)
	for _, flag in pairs(self.flags) do
		if flag.pos.x == pos.x and flag.pos.y == pos.y and flag.pos.z == pos.z then
			return flag
		end
	end

	return nil
end

function UIMinimap:removeFlag(pos, icon, description)
	local flag = self:getFlag(pos)

	if flag then
		flag:destroy()
	end
end

function UIMinimap:reset()
	self:setZoom(getMinimapZoomMin(self))

	if self.cross then
		self:setCameraPosition(self.cross.pos)
	end
end

function UIMinimap:move(x, y)
	local cameraPos = self:getCameraPosition()
	local scale = self:getScale()

	if scale > 1 then
		scale = 1
	end

	local dx = x / scale
	local dy = y / scale
	local pos = {
		x = cameraPos.x - dx,
		y = cameraPos.y - dy,
		z = cameraPos.z
	}

	self:setCameraPosition(pos)
end

function UIMinimap:onMouseWheel(mousePos, direction)
	local keyboardModifiers = g_keyboard.getModifiers()

	if direction == MouseWheelUp and keyboardModifiers == KeyboardNoModifier then
		self:zoomIn()
	elseif direction == MouseWheelDown and keyboardModifiers == KeyboardNoModifier then
		self:zoomOut()
	elseif direction == MouseWheelDown and keyboardModifiers == KeyboardCtrlModifier then
		self:onFloorUp(1)
	elseif direction == MouseWheelUp and keyboardModifiers == KeyboardCtrlModifier then
		self:onFloorDown(1)
	end
end

function UIMinimap:onFloorUp(value)
	self:floorUp(value)
	signalcall(g_minimap.onFloorChange, self:getCameraPosition().z)
end

function UIMinimap:onFloorDown(value)
	self:floorDown(value)
	signalcall(g_minimap.onFloorChange, self:getCameraPosition().z)
end

function UIMinimap:onMousePress(pos, button)
	if not self:isDragging() then
		self.allowNextRelease = true
	end
end

function UIMinimap:onMouseRelease(pos, button)
	if not self.allowNextRelease then
		return true
	end

	self.allowNextRelease = false

	local mapPos = self:getTilePosition(pos)

	if not mapPos then
		return
	end

	if button == MouseLeftButton then
		local player = g_game.getLocalPlayer()

		-- Reativa o autowalk ao clicar no minimapa/fullmap.
		-- Faz checagens seguras para evitar erro caso o módulo de minigame não exista.
		local canAutoWalk = true
		if modules and modules.game_minigame and type(modules.game_minigame.isPlaying) == 'function' then
			canAutoWalk = not modules.game_minigame.isPlaying()
		end

		if self.autowalk and canAutoWalk then
			player:autoWalk(mapPos)
		end

		return true
	elseif button == MouseRightButton then
		local menu = g_ui.createWidget("PopupMenu")

		menu:setGameMenu(true)
		menu:addOption(tr("Create mark"), function()
			self:createFlagWindow(mapPos)
		end)
		menu:display(pos)

		return true
	end

	return false
end

function UIMinimap:onDragEnter(pos)
	if self.fullView and g_minimap and g_minimap.setHDMode and g_minimap.isHDMode then
		self.dragRestoreHDMode = g_minimap:isHDMode()
		if self.dragRestoreHDMode then
			g_minimap:setHDMode(false)
		end
	end

	self.dragReference = pos
	self.dragCameraReference = self:getCameraPosition()

	return true
end

function UIMinimap:onDragMove(pos, moved)
	local scale = self:getScale()
	local dx = (self.dragReference.x - pos.x) / scale
	local dy = (self.dragReference.y - pos.y) / scale
	local pos = {
		x = self.dragCameraReference.x + dx,
		y = self.dragCameraReference.y + dy,
		z = self.dragCameraReference.z
	}

	self:setCameraPosition(pos)

	return true
end

function UIMinimap:onDragLeave(widget, pos)
	if self.dragRestoreHDMode ~= nil and g_minimap and g_minimap.setHDMode then
		g_minimap:setHDMode(self.dragRestoreHDMode)
		self.dragRestoreHDMode = nil
	end

	return true
end

function UIMinimap:onStyleApply(styleName, styleNode)
	for name, value in pairs(styleNode) do
		if name == "autowalk" then
			self.autowalk = value
		end
	end
end

function UIMinimap:createFlagWindow(pos)
	if self.flagWindow then
		return
	end

	if not pos then
		return
	end

	self.flagWindow = g_ui.createWidget("MinimapFlagWindow", rootWidget)

	self.flagWindow:onVisibilityChange(true)

	local positionLabel = self.flagWindow.position
	local description = self.flagWindow.description
	local okButton = self.flagWindow.okButton
	local cancelButton = self.flagWindow.cancelButton
	local copyButton = self.flagWindow.copyButton

	positionLabel:setText(string.format("%i, %i, %i", pos.x, pos.y, pos.z))

	local flagRadioGroup = UIRadioGroup.create()

	for i = 0, 20 do
		local checkbox = self.flagWindow:getChildById("flag" .. i)

		checkbox.icon = i

		flagRadioGroup:addWidget(checkbox)
	end

	flagRadioGroup:selectWidget(flagRadioGroup:getFirstWidget())

	local flagColorRadioGroup = UIRadioGroup.create()

	for i = 0, 6 do
		local checkboxColor = self.flagWindow:getChildById("flagColor" .. i)

		checkboxColor.color = checkboxColor:getBackgroundColor()

		flagColorRadioGroup:addWidget(checkboxColor)
	end

	flagColorRadioGroup:selectWidget(flagColorRadioGroup:getFirstWidget())

	function flagColorRadioGroup:onSelectionChange(selectWidget)
		flagRadioGroup:getSelectedWidget():setIconColor(selectWidget.color)
	end

	local function successFunc()
		self:addFlag(pos, flagRadioGroup:getSelectedWidget().icon, description:getText(), false,
			flagRadioGroup:getSelectedWidget():getIconColor())
		self:destroyFlagWindow()
	end

	local function cancelFunc()
		self:destroyFlagWindow()
	end

	local function copyFunc()
		local label = g_ui.createWidget("Label-12px-Regular", self.flagWindow)

		g_window.setClipboardText(positionLabel:getText())
		label:addAnchor(AnchorLeft, copyButton:getId(), AnchorLeft)
		label:addAnchor(AnchorVerticalCenter, copyButton:getId(), AnchorVerticalCenter)
		label:setText("Posi\xE7\xE3o copiada")
		g_effects.fadeOut(label, 1550)
		g_effects.moveToMargin(label, MarginBottom, 0, 30, 2200, Easing.easeOut, function()
			label:destroy()
		end)
	end

	okButton.onClick = successFunc
	cancelButton.onClick = cancelFunc
	copyButton.onClick = copyFunc
	self.flagWindow.onEnter = successFunc
	self.flagWindow.onEscape = cancelFunc

	function self.flagWindow.onDestroy()
		flagRadioGroup:destroy()
	end
end

function UIMinimap:destroyFlagWindow()
	if self.flagWindow then
		if not self.flagWindow:isDestroyed() then
			self.flagWindow:destroy()
		end

		self.flagWindow = nil
	end
end
