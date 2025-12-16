-- chunkname: @/modules/corelib/keyboard.lua

g_keyboard = {}

local hotkeys = {}

function translateKeyCombo(keyCombo)
	if not keyCombo or #keyCombo == 0 then
		return nil
	end

	local keyComboDesc = ""

	for k, v in pairs(keyCombo) do
		local keyDesc = KeyCodeDescs[v]

		if keyDesc == nil then
			return nil
		end

		keyComboDesc = keyComboDesc .. "+" .. keyDesc
	end

	keyComboDesc = keyComboDesc:sub(2)

	return keyComboDesc
end

local function getKeyCode(desc)
	return ReverseKeyCodeDescs[desc]
end

function retranslateKeyComboDesc(keyComboDesc)
	if keyComboDesc == nil then
		error("Unable to translate key combo '" .. keyComboDesc .. "'")
	end

	if type(keyComboDesc) == "number" then
		keyComboDesc = tostring(keyComboDesc)
	end

	local mouseCombo = reverseTranslateMouseKeyCombo(keyComboDesc)

	if mouseCombo then
		return translateMouseKeyCombo(mouseCombo)
	end

	local keyCombo = {}

	for i, currentKeyDesc in ipairs(keyComboDesc:split("+")) do
		for keyCode, keyDesc in pairs(KeyCodeDescs) do
			if keyDesc:lower() == currentKeyDesc:trim():lower() then
				table.insert(keyCombo, keyCode)
			end
		end
	end

	return translateKeyCombo(keyCombo)
end

function determineKeyComboDesc(keyCode, keyboardModifiers)
	local pressedButton = g_window.getPressedMouseButton()

	if pressedButton ~= MouseNoButton then
		local ret = determineMouseKeyComboDesc(pressedButton, g_window.getKeyboardModifiers())

		if ret then
			return ret
		end
	end

	local keyCombo = {}

	if keyCode == KeyCtrl or keyCode == KeyShift or keyCode == KeyAlt then
		table.insert(keyCombo, keyCode)
	elseif KeyCodeDescs[keyCode] ~= nil then
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

		table.insert(keyCombo, keyCode)
	end

	return translateKeyCombo(keyCombo)
end

local function onWidgetKeyDown(widget, keyCode, keyboardModifiers)
	if keyCode == KeyUnknown then
		return false
	end

	local callback = widget.boundAloneKeyDownCombos[determineKeyComboDesc(keyCode, KeyboardNoModifier)]

	signalcall(callback, widget, keyCode)

	callback = widget.boundKeyDownCombos[determineKeyComboDesc(keyCode, keyboardModifiers)]

	return signalcall(callback, widget, keyCode)
end

local function onWidgetKeyUp(widget, keyCode, keyboardModifiers)
	if keyCode == KeyUnknown then
		return false
	end

	local callback = widget.boundAloneKeyUpCombos[determineKeyComboDesc(keyCode, KeyboardNoModifier)]

	signalcall(callback, widget, keyCode)

	callback = widget.boundKeyUpCombos[determineKeyComboDesc(keyCode, keyboardModifiers)]

	return signalcall(callback, widget, keyCode)
end

local function onWidgetKeyPress(widget, keyCode, keyboardModifiers, autoRepeatTicks)
	if keyCode == KeyUnknown then
		return false
	end

	local callback = widget.boundKeyPressCombos[determineKeyComboDesc(keyCode, keyboardModifiers)]

	return signalcall(callback, widget, keyCode, autoRepeatTicks)
end

local function connectKeyDownEvent(widget)
	if widget.boundKeyDownCombos then
		return
	end

	connect(widget, {
		onKeyDown = onWidgetKeyDown
	})

	widget.boundKeyDownCombos = {}
	widget.boundAloneKeyDownCombos = {}
end

local function connectKeyUpEvent(widget)
	if widget.boundKeyUpCombos then
		return
	end

	connect(widget, {
		onKeyUp = onWidgetKeyUp
	})

	widget.boundKeyUpCombos = {}
	widget.boundAloneKeyUpCombos = {}
end

local function connectKeyPressEvent(widget)
	if widget.boundKeyPressCombos then
		return
	end

	connect(widget, {
		onKeyPress = onWidgetKeyPress,
		onMousePress = onWidgetKeyPress
	})

	widget.boundKeyPressCombos = {}
end

function g_keyboard.bindKeyDown(keyComboDesc, callback, widget, alone)
	widget = widget or rootWidget

	connectKeyDownEvent(widget)

	local keyComboDesc = retranslateKeyComboDesc(keyComboDesc)

	if alone then
		connect(widget.boundAloneKeyDownCombos, keyComboDesc, callback)
	else
		connect(widget.boundKeyDownCombos, keyComboDesc, callback)
	end
end

function g_keyboard.bindKeyUp(keyComboDesc, callback, widget, alone)
	widget = widget or rootWidget

	connectKeyUpEvent(widget)

	local keyComboDesc = retranslateKeyComboDesc(keyComboDesc)

	if alone then
		connect(widget.boundAloneKeyUpCombos, keyComboDesc, callback)
	else
		connect(widget.boundKeyUpCombos, keyComboDesc, callback)
	end
end

function g_keyboard.bindKeyPress(keyComboDesc, callback, widget)
	widget = widget or rootWidget

	connectKeyPressEvent(widget)

	local keyComboDesc = retranslateKeyComboDesc(keyComboDesc)

	connect(widget.boundKeyPressCombos, keyComboDesc, callback)
end

local function getUnbindArgs(arg1, arg2)
	local callback, widget

	if type(arg1) == "function" then
		callback = arg1
	elseif type(arg2) == "function" then
		callback = arg2
	end

	if type(arg1) == "userdata" then
		widget = arg1
	elseif type(arg2) == "userdata" then
		widget = arg2
	end

	widget = widget or rootWidget

	return callback, widget
end

function g_keyboard.unbindKeyDown(keyComboDesc, arg1, arg2)
	local callback, widget = getUnbindArgs(arg1, arg2)

	if widget.boundKeyDownCombos == nil then
		return
	end

	local keyComboDesc = retranslateKeyComboDesc(keyComboDesc)

	disconnect(widget.boundKeyDownCombos, keyComboDesc, callback)
end

function g_keyboard.unbindKeyUp(keyComboDesc, arg1, arg2)
	local callback, widget = getUnbindArgs(arg1, arg2)

	if widget.boundKeyUpCombos == nil then
		return
	end

	local keyComboDesc = retranslateKeyComboDesc(keyComboDesc)

	disconnect(widget.boundKeyUpCombos, keyComboDesc, callback)
end

function g_keyboard.unbindKeyPress(keyComboDesc, arg1, arg2)
	local callback, widget = getUnbindArgs(arg1, arg2)

	if widget.boundKeyPressCombos == nil then
		return
	end

	local keyComboDesc = retranslateKeyComboDesc(keyComboDesc)

	disconnect(widget.boundKeyPressCombos, keyComboDesc, callback)
end

function g_keyboard.getModifiers()
	return g_window.getKeyboardModifiers()
end

function g_keyboard.isKeyPressed(key)
	if type(key) == "string" then
		key = getKeyCode(key)
	end

	return g_window.isKeyPressed(key)
end

function g_keyboard.areKeysPressed(keyComboDesc)
	for i, currentKeyDesc in ipairs(keyComboDesc:split("+")) do
		for keyCode, keyDesc in pairs(KeyCodeDescs) do
			if keyDesc:lower() == currentKeyDesc:trim():lower() then
				if keyDesc:lower() == "ctrl" then
					if not g_keyboard.isCtrlPressed() then
						return false
					end
				elseif keyDesc:lower() == "shift" then
					if not g_keyboard.isShiftPressed() then
						return false
					end
				elseif keyDesc:lower() == "alt" then
					if not g_keyboard.isAltPressed() then
						return false
					end
				elseif not g_window.isKeyPressed(keyCode) then
					return false
				end
			end
		end
	end

	return true
end

function g_keyboard.isKeySetPressed(keys, all)
	all = all or false

	local result = {}

	for k, v in pairs(keys) do
		if type(v) == "string" then
			v = getKeyCode(v)
		end

		if g_window.isKeyPressed(v) then
			if not all then
				return true
			end

			table.insert(result, true)
		end
	end

	return #result == #keys
end

function g_keyboard.isInUse()
	for i = FirstKey, LastKey do
		if g_window.isKeyPressed(key) then
			return true
		end
	end

	return false
end

function g_keyboard.isCtrlPressed()
	return bit32.band(g_window.getKeyboardModifiers(), KeyboardCtrlModifier) ~= 0
end

function g_keyboard.isAltPressed()
	return bit32.band(g_window.getKeyboardModifiers(), KeyboardAltModifier) ~= 0
end

function g_keyboard.isShiftPressed()
    return bit32.band(g_window.getKeyboardModifiers(), KeyboardShiftModifier) ~= 0
end

function g_keyboard.setKeyDelay(key, delay)
    if type(delay) ~= 'number' then
        delay = tonumber(delay) or 0
    end
    local code = key
    if type(code) == 'string' then
        code = getKeyCode(code)
    end
    if type(code) ~= 'number' or code == nil then
        return false
    end
    g_window.setKeyDelay(code, math.max(0, math.floor(delay)))
    return true
end

function g_keyboard.bindHotkeyPress(keyComboDesc, callback, widget, hotkeyType)
    widget = widget or rootWidget

	connectKeyPressEvent(widget)

	hotkeys[keyComboDesc] = hotkeyType or ""

	local keyComboDesc = retranslateKeyComboDesc(keyComboDesc)

	connect(widget.boundKeyPressCombos, keyComboDesc, callback)
end

function g_keyboard.unbindHotkeyPress(keyComboDesc, arg1, arg2)
	local callback, widget = getUnbindArgs(arg1, arg2)

	if widget.boundKeyPressCombos == nil then
		return
	end

	hotkeys[keyComboDesc] = nil

	local keyComboDesc = retranslateKeyComboDesc(keyComboDesc)

	disconnect(widget.boundKeyPressCombos, keyComboDesc, callback)
end

function g_keyboard.getHotkeyType(keyComboDesc)
	local t = hotkeys[keyComboDesc]
	if t then return t end
	if modules and modules.game_walk and modules.game_walk.isWalkingCombo and modules.game_walk.isWalkingCombo(keyComboDesc) then
		return "Walking"
	end
	return nil
end

function g_keyboard.isSkipKey(key)
	for i, v in pairs(key:split("+")) do
		if not SkipHotkeys[v] then
			return false
		end
	end

	return true
end

function g_keyboard.isPrintableKeyPressed()
	return g_keyboard.isSkipKey(KeyCodeDescs[g_window.getPressedKey()] or "")
end

function g_keyboard.hasTextEditChange()
	return rootWidget.currentTextEdit:isFocused() and rootWidget.currentTextEdit:isExplicitlyVisible() and rootWidget.currentTextEdit:isVisible() and rootWidget.currentTextEdit:isCursorVisible() and rootWidget.currentTextEdit:isActive() and rootWidget.currentTextEdit:getCursorPos() >= 0 and not g_keyboard.isPrintableKeyPressed()
end

function g_keyboard.isChatEnabled()
	return modules.game_console.isChatEnabled() and not g_keyboard.isPrintableKeyPressed()
end

function g_keyboard.determineKeyComboDescription(keyCode, keyboardModifiers)
	return determineKeyComboDesc(keyCode, keyboardModifiers)
end
-- Polyfill para bit32 (Lua 5.1/LuaJIT)
if not bit32 then
  local ok, bit = pcall(require, 'bit')
  if ok and bit then
    bit32 = {
      band = bit.band,
      bor = bit.bor,
      bxor = bit.bxor,
      lshift = bit.lshift,
      rshift = bit.rshift,
      bnot = bit.bnot
    }
  else
    local function band(a, b)
      a = tonumber(a) or 0
      b = tonumber(b) or 0
      local res, bitpos = 0, 1
      while a > 0 or b > 0 do
        local abit = a % 2
        local bbit = b % 2
        if abit == 1 and bbit == 1 then res = res + bitpos end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        bitpos = bitpos * 2
      end
      return res
    end
    bit32 = { band = band }
  end
end
