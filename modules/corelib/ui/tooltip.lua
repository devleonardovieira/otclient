-- chunkname: @/modules/corelib/ui/tooltip.lua

g_tooltip = {}

local toolTipLabel, currentHoveredWidget, lastHoveredWidget

local function moveToolTip(first)
	if not first and (not toolTipLabel:isVisible() or toolTipLabel:getOpacity() < 0.1) then
		return
	end

	if currentHoveredWidget and not lastHoveredWidget and not g_keyboard.isShiftPressed() then
		g_tooltip.hide()

		currentHoveredWidget = nil

		return
	end

	if currentHoveredWidget and g_keyboard.isShiftPressed() then
		return
	end

	local pos = g_window.getMousePosition()
	local windowSize = g_window.getSize()
	local labelSize = toolTipLabel:getSize()

	pos.x = pos.x + 1
	pos.y = pos.y + 1

	if windowSize.width - (pos.x + labelSize.width) < 10 then
		pos.x = pos.x - labelSize.width - 3
	else
		pos.x = pos.x + 10
	end

	if windowSize.height - (pos.y + labelSize.height) < 40 then
		pos.y = pos.y - labelSize.height
	else
		pos.y = pos.y + 10
	end

	toolTipLabel:setPosition(pos)
end

local function onWidgetHoverChange(widget, hovered)
	if hovered then
		if widget.tooltip and not g_mouse.isPressed() and not currentHoveredWidget then
			g_tooltip.display(widget.tooltip)

			currentHoveredWidget = widget
			lastHoveredWidget = true
		end
	else
		if widget == currentHoveredWidget then
			lastHoveredWidget = false
		end

		if widget == currentHoveredWidget and not g_keyboard.isShiftPressed() then
			g_tooltip.hide()

			currentHoveredWidget = nil
		end
	end
end

local function onWidgetStyleApply(widget, styleName, styleNode)
	if styleNode.tooltip then
		widget.tooltip = styleNode.tooltip
	end
end

function g_tooltip.init()
	connect(UIWidget, {
		onStyleApply = onWidgetStyleApply,
		onHoverChange = onWidgetHoverChange
	})
	addEvent(function()
		toolTipLabel = g_ui.createWidget("TooltipLabel", rootWidget)

		toolTipLabel:setId("toolTip")
		toolTipLabel:setTextAlign(AlignCenter)
		toolTipLabel:hide()
	end)
end

function g_tooltip.terminate()
	disconnect(UIWidget, {
		onStyleApply = onWidgetStyleApply,
		onHoverChange = onWidgetHoverChange
	})

	currentHoveredWidget = nil

	toolTipLabel:destroy()

	toolTipLabel = nil
	g_tooltip = nil
end

function g_tooltip.display(text)
	if text == nil or text:len() == 0 then
		return
	end

	if not toolTipLabel then
		return
	end

	toolTipLabel:setMultiColorText(text)
	toolTipLabel:resizeToText()
	toolTipLabel:resize(toolTipLabel:getWidth() + 14, toolTipLabel:getHeight() + 12)
	toolTipLabel:show()
	toolTipLabel:raise()
	toolTipLabel:enable()
	g_effects.fadeIn(toolTipLabel, 100)
	moveToolTip(true)
	connect(rootWidget, {
		onMouseMove = moveToolTip
	})
end

function g_tooltip.hide()
	g_effects.fadeOut(toolTipLabel, 100)
	disconnect(rootWidget, {
		onMouseMove = moveToolTip
	})
end

function UIWidget:setTooltip(text)
	self.tooltip = text
end

function UIWidget:removeTooltip()
	self.tooltip = nil
end

function UIWidget:getTooltip()
	return self.tooltip
end

g_tooltip.init()
connect(g_app, {
	onTerminate = g_tooltip.terminate
})
