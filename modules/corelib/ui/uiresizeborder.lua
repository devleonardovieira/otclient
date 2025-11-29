-- chunkname: @/modules/corelib/ui/uiresizeborder.lua

UIResizeBorder = extends(UIWidget, "UIResizeBorder")

function UIResizeBorder.create()
	local resizeborder = UIResizeBorder.internalCreate()

	resizeborder:setFocusable(false)

	resizeborder.minimum = 0
	resizeborder.maximum = 1000

	return resizeborder
end

function UIResizeBorder:onSetup()
	-- Only auto-detect orientation if not explicitly set via style
	if type(self.vertical) ~= 'boolean' then
		if self:getWidth() > self:getHeight() then
			self.vertical = true
		else
			self.vertical = false
		end
	end
end

function UIResizeBorder:onDestroy()
	if self.hovering then
		g_mouse.popCursor(self.cursortype)
	end
end

function UIResizeBorder:onHoverChange(hovered)
	if hovered then
		if g_mouse.isCursorChanged() or g_mouse.isPressed() then
			return
		end

		-- Respect explicit orientation if provided; otherwise infer
		if type(self.vertical) ~= 'boolean' then
			if self:getWidth() > self:getHeight() then
				self.vertical = true
				self.cursortype = "vertical"
			else
				self.vertical = false
				self.cursortype = "horizontal"
			end
		else
			self.cursortype = self.vertical and "vertical" or "horizontal"
		end

		g_mouse.pushCursor(self.cursortype)

		self.hovering = true

		if not self:isPressed() then
			g_effects.fadeIn(self)
		end
	elseif not self:isPressed() and self.hovering then
		g_mouse.popCursor(self.cursortype)
		g_effects.fadeOut(self)

		self.hovering = false
	end
end

function UIResizeBorder:onMouseMove(mousePos, mouseMoved)
	if self:isPressed() then
		local parent = self:getParent()
		local newSize = 0
		local newX = 0
		local newY = 0

		if not self.inverted then
			if self.vertical then
				local delta = mousePos.y - self:getY() - self:getHeight() / 2

				newSize = math.min(math.max(parent:getHeight() + delta, self.minimum), self.maximum)

				parent:setHeight(newSize)
			else
				local delta = mousePos.x - self:getX() - self:getWidth() / 2

				newSize = math.min(math.max(parent:getWidth() + delta, self.minimum), self.maximum)

				parent:setWidth(newSize)
			end
		elseif self.vertical then
			local delta = mousePos.y - self:getY() - self:getHeight() / 2

			newSize = math.min(math.max(parent:getHeight() - delta, self.minimum), self.maximum)

			parent:setY(parent:getY() + (parent:getHeight() - newSize))
			parent:setHeight(newSize)
		else
			local delta = mousePos.x - self:getX() - self:getWidth() / 2

			newSize = math.min(math.max(parent:getWidth() - delta, self.minimum), self.maximum)

			parent:setX(parent:getX() + (parent:getWidth() - newSize))
			parent:setWidth(newSize)
		end

		self:onUpdateSize(newSize)
		self:checkBoundary(newSize)

		return true
	end
end

function UIResizeBorder:onMouseRelease(mousePos, mouseButton)
	if not self:isHovered() then
		g_mouse.popCursor(self.cursortype)
		g_effects.fadeOut(self)

		self.hovering = false
	end
end

function UIResizeBorder:onStyleApply(styleName, styleNode)
	for name, value in pairs(styleNode) do
		if name == "maximum" then
			self:setMaximum(tonumber(value))
		elseif name == "minimum" then
			self:setMinimum(tonumber(value))
		elseif name == "inverted" then
			self.inverted = (value == true) or (value == 'true')
		elseif name == "vertical" then
			self.vertical = (value == true) or (value == 'true')
		elseif name == "orientation" then
			local v = tostring(value)
			if v == 'vertical' then
				self.vertical = true
			elseif v == 'horizontal' then
				self.vertical = false
			end
		end
	end
end

function UIResizeBorder:onVisibilityChange(visible)
	if visible and self.maximum == self.minimum then
		self:hide()
	end
end

function UIResizeBorder:setMaximum(maximum)
	self.maximum = maximum

	self:checkBoundary()
end

function UIResizeBorder:setMinimum(minimum)
	self.minimum = minimum

	self:checkBoundary()
end

function UIResizeBorder:getMaximum()
	return self.maximum
end

function UIResizeBorder:getMinimum()
	return self.minimum
end

function UIResizeBorder:setParentSize(size)
	local parent = self:getParent()

	if self.vertical then
		parent:setHeight(size)
	else
		parent:setWidth(size)
	end

	self:checkBoundary(size)
end

function UIResizeBorder:getParentSize()
	local parent = self:getParent()

	if self.vertical then
		return parent:getHeight()
	else
		return parent:getWidth()
	end
end

function UIResizeBorder:checkBoundary(size)
	size = size or self:getParentSize()

	if self.maximum == self.minimum and size == self.maximum then
		self:hide()
	else
		self:show()
	end
end

function UIResizeBorder:onUpdateSize(newSize)
	return newSize
end
