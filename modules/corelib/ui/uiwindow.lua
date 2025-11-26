-- chunkname: @/modules/corelib/ui/uiwindow.lua

UIWindow = extends(UIWidget, "UIWindow")

function UIWindow.create()
	local window = UIWindow.internalCreate()

	window:setTextAlign(AlignTopCenter)
	window:setDraggable(true)
	window:setAutoFocusPolicy(AutoFocusFirst)
	addEvent(function()
		if window.closeButton then
			function window.closeButton.onClick()
				window:close()
			end
		end
	end)

	return window
end

function UIWindow:close()
	self:hide()
	signalcall(self.onClose, self)
end

function UIWindow:onKeyDown(keyCode, keyboardModifiers)
	if keyboardModifiers == KeyboardNoModifier then
		if keyCode == KeyEnter then
			signalcall(self.onEnter, self)
		elseif keyCode == KeyEscape then
			signalcall(self.onEscape, self)
		end
	end
end

function UIWindow:onFocusChange(focused)
	if focused then
		self:raise()
	end
end

function UIWindow:onDragEnter(mousePos)
	if self.static then
		return false
	end

	self:breakAnchors()

	self.movingReference = {
		x = mousePos.x - self:getX(),
		y = mousePos.y - self:getY()
	}

	return true
end

function UIWindow:onDragLeave(droppedWidget, mousePos)
	return
end

function UIWindow:onDragMove(mousePos, mouseMoved)
	if self.static then
		return
	end

	local pos = {
		x = mousePos.x - self.movingReference.x,
		y = mousePos.y - self.movingReference.y
	}

	self:setPosition(pos)
	self:bindRectToParent()
end

function UIWindow:onVisibilityChange(visible)
	 if visible and self.animation then 
		self:breakAnchors()

		local fromPosition = self:getPosition()
		local toPosition = {
			x = fromPosition.x,
			y = fromPosition.y - 30
		}

		g_effects.moveToPosition(self, fromPosition, toPosition, 140, Easing.easeOutBack, function()
			g_effects.moveToPosition(self, toPosition, fromPosition, 120, Easing.easeOutBack)
		end)
	 end 
end
