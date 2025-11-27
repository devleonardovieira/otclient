-- chunkname: @/modules/corelib/ui/uimessagebox.lua

if not UIWindow then
	dofile("uiwindow")
end

UIMessageBox = extends(UIWindow, "UIMessageBox")
UIMessageBox.create = nil

function UIMessageBox.display(title, message, buttons, onEnterCallback, onEscapeCallback)
	local messageBox = UIMessageBox.internalCreate()

	rootWidget:addChild(messageBox)
	messageBox:setStyle("MessageBoxWindow")
	messageBox:setText(title)

	local messageLabel = g_ui.createWidget("MessageBoxLabel", messageBox)

	messageLabel:setMultiColorText(message)

	local buttonHolder = g_ui.createWidget("MessageBoxButtonHolder", messageBox)

	buttonHolder:addAnchor(AnchorHorizontalCenter, "parent", AnchorHorizontalCenter)

    local buttonsWidth = 0
    local buttonsHeight = 0
    -- Fallback para largura base caso o label não calcule corretamente
    local baseWidth = messageLabel:getWidth()
    if baseWidth <= 0 then
        baseWidth = math.max(messageBox:getTextSize().width, 280)
    end

	for i = 1, #buttons do
		local button = messageBox:addButton(buttons[i].text, buttons[i].callback, buttons[i].color)

        if i == 1 and #buttons == 1 then
            button:setWidth(baseWidth + button:getMarginLeft())
        else
            button:setWidth(baseWidth / #buttons)
        end

		if i == 1 then
			button:setMarginLeft(0)
			button:addAnchor(AnchorBottom, "parent", AnchorBottom)
			button:addAnchor(AnchorLeft, "parent", AnchorLeft)

			buttonsHeight = button:getHeight()
		else
			button:addAnchor(AnchorBottom, "prev", AnchorBottom)
			button:addAnchor(AnchorLeft, "prev", AnchorRight)
		end

		buttonsWidth = buttonsWidth + button:getWidth() + button:getMarginLeft()
	end

	buttonHolder:setWidth(buttonsWidth)
	buttonHolder:setHeight(buttonsHeight)

	if onEnterCallback then
		connect(messageBox, {
			onEnter = onEnterCallback
		})
	end

	if onEscapeCallback then
		connect(messageBox, {
			onEscape = onEscapeCallback
		})
	end

    messageBox:setWidth(math.max(baseWidth, messageBox:getTextSize().width, buttonHolder:getWidth()) + messageBox:getPaddingLeft() + messageBox:getPaddingRight())
	messageBox:setHeight(messageLabel:getHeight() + messageLabel:getMarginTop() + messageBox:getPaddingTop() + messageBox:getPaddingBottom() + buttonHolder:getHeight() + buttonHolder:getMarginTop())
	g_effects.moveToMargin(messageBox, MarginBottom, 0, 30, 140, Easing.easeOutBack, function()
		g_effects.moveToMargin(messageBox, MarginBottom, 30, 0, 120, Easing.easeOutBack)
	end)

	return messageBox
end

function displayInfoBox(title, message)
	local messageBox

	local function defaultCallback()
		messageBox:ok()
	end

	messageBox = UIMessageBox.display(title, message, {
		{
			color = "Blue",
			text = "Ok",
			callback = defaultCallback
		}
	}, defaultCallback, defaultCallback)

	return messageBox
end

function displayErrorBox(title, message)
	local messageBox

	local function defaultCallback()
		messageBox:ok()
	end

	messageBox = UIMessageBox.display(title, message, {
		{
			color = "Blue",
			text = "Ok",
			callback = defaultCallback
		}
	}, defaultCallback, defaultCallback)

	return messageBox
end

function displayCancelBox(title, message)
	local messageBox

	local function defaultCallback()
		messageBox:cancel()
	end

	messageBox = UIMessageBox.display(title, message, {
		{
			color = "Red",
			text = "Cancel",
			callback = defaultCallback
		}
	}, defaultCallback, defaultCallback)

	return messageBox
end

function displayGeneralBox(title, message, buttons, onEnterCallback, onEscapeCallback)
	return UIMessageBox.display(title, message, buttons, onEnterCallback, onEscapeCallback)
end

function displayConfirmBox(title, message, onConfirm, onCancel)
	local confirmBox

	local function onDestroy()
		if confirmBox then
			confirmBox:destroy()

			confirmBox = nil
		end
	end

	local function onCancelCallback()
		onDestroy()

		if onCancel then
			onCancel()
		end
	end

	local function onEnterCallback()
		onDestroy()

		if onConfirm then
			onConfirm()
		end
	end

	local buttons = {
		{
			color = "Blue",
			text = tr("Yes"),
			callback = onEnterCallback
		},
		{
			color = "Red",
			text = tr("No"),
			callback = onCancelCallback
		}
	}

	confirmBox = displayGeneralBox(title, message, buttons, onEnterCallback, onCancelCallback)

	confirmBox:raise()
	confirmBox:focus()

	return confirmBox
end

function UIMessageBox:addButton(text, callback, color)
	local buttonHolder = self:getChildById("buttonHolder")
	local button = g_ui.createWidget("MessageBoxButton" .. color, buttonHolder)

	button:setText(text)
	connect(button, {
		onClick = callback
	})

	return button
end

function UIMessageBox:ok()
	signalcall(self.onOk, self)

	self.onOk = nil

	self:destroy()
end

function UIMessageBox:cancel()
	signalcall(self.onCancel, self)

	self.onCancel = nil

	self:destroy()
end
