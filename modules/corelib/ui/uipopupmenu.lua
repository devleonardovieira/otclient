-- chunkname: @/modules/corelib/ui/uipopupmenu.lua

UIPopupMenu = extends(UIWidget, "UIPopupMenu")

local currentMenu

local function customOnGeometryChange(widget, newRect)
	local parent = widget:getParent()

	if not parent then
		return
	end

	local pos = g_window.getMousePosition()
	local parentSize = parent:getSize()

	pos.x = pos.x + 1
	pos.y = pos.y + 1

	if parentSize.width - (pos.x + newRect.width) < 5 then
		pos.x = pos.x - newRect.width - 3
	else
		pos.x = pos.x + 5
	end

	if parentSize.height - (pos.y + newRect.height) < 5 then
		pos.y = pos.y - newRect.height - 3
	else
		pos.y = pos.y + 5
	end

	widget:setPosition(pos)
end

function UIPopupMenu.create()
	local menu = UIPopupMenu.internalCreate()
	local layout = UIVerticalLayout.create(menu)

	layout:setFitChildren(true)
	menu:setLayout(layout)

	menu.isGameMenu = false

	return menu
end

function UIPopupMenu:display(pos)
	if self:getChildCount() == 0 then
		self:destroy()

		return
	end

	if g_ui.isMouseGrabbed() then
		self:destroy()

		return
	end

	if currentMenu then
		currentMenu:destroy()
	end

	if pos == nil then
		pos = g_window.getMousePosition()
	end

	rootWidget:addChild(self)
	self._prevFocused = rootWidget:getFocusedChild()
	self:setPosition(pos)
	self:grabMouse()
	self:focus()

	currentMenu = self
end

function UIPopupMenu:onGeometryChange(oldRect, newRect)
	local parent = self:getParent()

	if not parent then
		return
	end

	local ymax = parent:getY() + parent:getHeight()
	local xmax = parent:getX() + parent:getWidth()

	if ymax < newRect.y + newRect.height then
		local newy = ymax - newRect.height

		if newy > 0 and ymax > newy + newRect.height then
			self:setY(newy)
		end
	end

	if xmax < newRect.x + newRect.width then
		local newx = xmax - newRect.width

		if newx > 0 and xmax > newx + newRect.width then
			self:setX(newx)
		end
	end

	self:bindRectToParent()
end

function UIPopupMenu:addOption(optionName, optionCallback, shortcut, icon)
	local optionWidget = g_ui.createWidget(self:getStyleName() .. "Button", self)

	function optionWidget.onClick(widget)
		self:destroy()
		optionCallback()
	end

	optionWidget:setText(optionName)

	local width = optionWidget:getTextSize().width + optionWidget:getPaddingLeft() + optionWidget:getPaddingRight() + 15
	local iconWidget

	if icon then
		iconWidget = g_ui.createWidget(self:getStyleName() .. "Icon", optionWidget)

		iconWidget:setImageSource(icon)

		width = width + iconWidget:getWidth() + iconWidget:getMarginLeft() + iconWidget:getMarginRight()
	end

	if shortcut then
		local shortcutLabel = g_ui.createWidget(self:getStyleName() .. "ShortcutLabel", optionWidget)

		shortcutLabel:setText(shortcut)

		if iconWidget then
			shortcutLabel:addAnchor(AnchorRight, iconWidget:getId(), AnchorLeft)
		end

		width = width + shortcutLabel:getTextSize().width + shortcutLabel:getMarginLeft() + shortcutLabel:getMarginRight()
	end

	self:setWidth(math.max(self:getWidth(), width))
end

function UIPopupMenu:addSeparator()
	g_ui.createWidget(self:getStyleName() .. "Separator", self)
end

function UIPopupMenu:setGameMenu(state)
	self.isGameMenu = state
end

function UIPopupMenu:onDestroy()
	if currentMenu == self then
		currentMenu = nil
	end

	self:ungrabMouse()
	if self._prevFocused and not self._prevFocused:isDestroyed() then
		self._prevFocused:focus()
	end
end

function UIPopupMenu:onMousePress(mousePos, mouseButton)
	if not self:containsPoint(mousePos) then
		self:destroy()
	end

	return true
end

function UIPopupMenu:onKeyPress(keyCode, keyboardModifiers)
	if keyCode == KeyEscape then
		self:destroy()

		return true
	end

	return false
end

local function onRootGeometryUpdate()
	if currentMenu then
		currentMenu:destroy()
	end
end

local function onGameEnd()
	if currentMenu and currentMenu.isGameMenu then
		currentMenu:destroy()
	end
end

connect(rootWidget, {
	onGeometryChange = onRootGeometryUpdate
})
connect(g_game, {
	onGameEnd = onGameEnd
})
