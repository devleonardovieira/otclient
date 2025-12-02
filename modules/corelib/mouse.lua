-- chunkname: @/modules/corelib/mouse.lua

function g_mouse.bindAutoPress(widget, callback, delay, button)
	local button = button or MouseLeftButton

	connect(widget, {
		onMousePress = function(widget, mousePos, mouseButton)
			if mouseButton ~= button then
				return false
			end

			local startTime = g_clock.millis()

			callback(widget, mousePos, mouseButton, 0)
			periodicalEvent(function()
				callback(widget, g_window.getMousePosition(), mouseButton, g_clock.millis() - startTime)
			end, function()
				return g_mouse.isPressed(mouseButton)
			end, 30, delay)

			return true
		end
	})
end

function g_mouse.bindPressMove(widget, callback)
	connect(widget, {
		onMouseMove = function(widget, mousePos, mouseMoved)
			if widget:isPressed() then
				callback(mousePos, mouseMoved)

				return true
			end
		end
	})
end

function g_mouse.bindPress(widget, callback, button)
	connect(widget, {
		onMousePress = function(widget, mousePos, mouseButton)
			if not button or button == mouseButton then
				callback(mousePos, mouseButton)

				return true
			end

			return false
		end
	})
end

function g_mouse.isComboPressed(keyComboDesc)
	local keyCombo = reverseTranslateMouseKeyCombo(keyComboDesc)

	if not keyCombo then
		return false
	end

	local last = #keyCombo
	local keyboardModifiers = 0

	for i, keyCode in ipairs(keyCombo) do
		if i == last then
			if not g_mouse.isPressed(keyCode) then
				return false
			end
		elseif keyCode == KeyCtrl then
			keyboardModifiers = keyboardModifiers + KeyboardCtrlModifier
		elseif keyCode == KeyAlt then
			keyboardModifiers = keyboardModifiers + KeyboardAltModifier
		elseif currentCode == KeyShift then
			keyboardModifiers = keyboardModifiers + KeyboardShiftModifier
		else
			return false
		end
	end

	return g_window.getKeyboardModifiers() == keyboardModifiers
end

function isMouseCombo(keyCombo)
	if keyCombo == nil or type(keyCombo) ~= "string" then
		return false
	end

	local slipt = keyCombo:split("+")
	local lastKey = split[#split]:trim():lower()

	return ReverseMouseButtonDescs[lastKey] ~= nil
end

function translateMouseKeyCombo(keyCombo)
	if not keyCombo or #keyCombo == 0 then
		return nil
	end

	local keyComboDesc = ""
	local last = #keyCombo

	for k, key in ipairs(keyCombo) do
		local keyDesc

		if k == last then
			keyDesc = MouseButtonDescs[key]
		else
			keyDesc = KeyCodeDescs[key]
		end

		if keyDesc == nil then
			return nil
		end

		keyComboDesc = keyComboDesc .. "+" .. keyDesc
	end

	keyComboDesc = keyComboDesc:sub(2)

	return keyComboDesc
end

function reverseTranslateMouseKeyCombo(keyCombo)
	if keyCombo == nil or type(keyCombo) ~= "string" then
		return nil
	end

	local reversedKeyCombo = {}
	local combo = keyCombo:split("+")
	local last = #combo

	for i, key in pairs(combo) do
		if i == last then
			local reversedMouse = ReverseMouseButtonDescs[key]

			if reversedMouse then
				table.insert(reversedKeyCombo, reversedMouse)
			else
				return nil
			end
		else
			local reversedKeyboard = ReverseKeyCodeDescs[key]

			if reversedKeyboard then
				table.insert(reversedKeyCombo, reversedKeyboard)
			end
		end
	end

	return reversedKeyCombo
end

function determineMouseKeyComboDesc(mouseButton, keyboardModifiers)
	local keyCombo = {}

	if MouseButtonDescs[mouseButton] ~= nil then
		if keyboardModifiers == KeyboardCtrlModifier then
			table.insert(keyCombo, KeyCtrl)
		elseif keyboardModifiers == KeyboardAltModifier then
			table.insert(keyCombo, KeyAlt)
		elseif keyboardModifiers == KeyboardCtrlAltModifier then
			table.insert(keyCombo, KeyCtrl)
			table.insert(keyCombo, KeyAlt)
		elseif keyboardModifiers == KeyboardShiftModifier then
			table.insert(keyCombo, KeyShift)
		elseif keyboardModifiers == KeyboardCtrlShiftModifier then
			table.insert(keyCombo, KeyCtrl)
			table.insert(keyCombo, KeyShift)
		elseif keyboardModifiers == KeyboardAltShiftModifier then
			table.insert(keyCombo, KeyAlt)
			table.insert(keyCombo, KeyShift)
		elseif keyboardModifiers == KeyboardCtrlAltShiftModifier then
			table.insert(keyCombo, KeyCtrl)
			table.insert(keyCombo, KeyAlt)
			table.insert(keyCombo, KeyShift)
		end

		table.insert(keyCombo, mouseButton)
	end

	return translateMouseKeyCombo(keyCombo)
end
