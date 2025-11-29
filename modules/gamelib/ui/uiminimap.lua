-- chunkname: @/modules/gamelib/ui/uiminimap.lua

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
		self:setCrossPosition(self.cross.pos)
	end
end

function UIMinimap:hideFloor()
	self.floorUpWidget:hide()
	self.floorDownWidget:hide()
end

function UIMinimap:hideZoom()
	self.zoomInWidget:hide()
	self.zoomOutWidget:hide()
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

		self:setZoom(settings.zoom)
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

function UIMinimap:setCrossPosition(pos)
	local cross = self.cross

	if not self.cross then
		cross = g_ui.createWidget("MinimapCross", self)

		cross:setIcon("/images/game/minimap/cross")

		self.cross = cross
	end

	pos.z = self:getCameraPosition().z
	cross.pos = pos

	if pos then
		self:centerInPosition(cross, pos)
	else
		cross:breakAnchors()
	end
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

function UIMinimap:addAlternativeWidget(widget, pos, maxZoom)
	widget.pos = pos
	widget.maxZoom = maxZoom or 0
	widget.minZoom = minZoom

	table.insert(self.alternatives, widget)
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

function UIMinimap:onZoomChange(zoom)
	if self.fullView then
		for _, widget in pairs(self.alternatives) do
			if (not widget.minZoom or zoom <= widget.minZoom) and zoom >= widget.maxZoom then
				widget:show()
			else
				widget:hide()
			end
		end
	end
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
	self:setZoom(2)

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
		self:addFlag(pos, flagRadioGroup:getSelectedWidget().icon, description:getText(), false, flagRadioGroup:getSelectedWidget():getIconColor())
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
