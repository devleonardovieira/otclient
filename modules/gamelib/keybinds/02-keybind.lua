-- chunkname: @/modules/gamelib/keybinds/02-keybind.lua

local _D = false

Keybind = {}

function Keybind:create(defaultIndex, category, name, keyCombo, altKeyCombo, callback, ...)
	local kbind = {}

	kbind.category = category
	kbind.name = name
	kbind.keyCombo = "<none>"
	kbind.altKeyCombo = "<none>"
	kbind.callback = callback
	kbind.callbackName = nil
	kbind.args = {
		...
	}
	kbind.active = false
	kbind.bindFunction = g_keyboard.bindKeyPress
	kbind.unbindFunction = g_keyboard.unbindKeyPress
	kbind.bindToWidget = nil
	kbind.defaultKeyCombo = "<none>"
	kbind.defaultaltKeyCombo = "<none>"
	kbind.defaultIndex = 1
	kbind.forbiddenWithModifiers = false
	kbind.resistsMute = false
	self.__index = self

	setmetatable(kbind, self)

	if type(defaultIndex) == "number" and defaultIndex > 0 then
		kbind.defaultIndex = defaultIndex
	end

	if type(callback) == "string" then
		if type(KB_CALLBACKS[callback]) ~= "nil" then
			kbind.callbackName = callback
			kbind.callback = KB_CALLBACKS[callback]
		else
			perror("(Keybind:Create) Could not create keybind because the callback provided was a string that could not be converted into a function because no function with that name exists in KB_CALLBACKS. KB_CALLBACKS are case-sensitive in their naming, could that be the issue here?")

			return nil
		end
	end

	-- normalize empty strings to '<none>' before validation
	if type(keyCombo) == "string" and keyCombo:len() == 0 then
		keyCombo = "<none>"
	end
	if type(altKeyCombo) == "string" and altKeyCombo:len() == 0 then
		altKeyCombo = "<none>"
	end

	if kbind:validate(keyCombo, altKeyCombo) then
		kbind.keyCombo = keyCombo
		kbind.altKeyCombo = altKeyCombo

		kbind:updateWidgets()
		kbind:cache()

		if _D then
			print("(Keybind:Create) Created: [" .. name .. "] (" .. keyCombo .. " | " .. altKeyCombo .. ").")
		end

		return kbind
	end

	return nil
end

function Keybind:validate(regularKey, altKey)
	if type(regularKey) ~= "string" and type(regularKey) ~= "number" then
		if _D then
			print("(Keybind:update: validation) Can not update keybind, keyCombo is not a string but: " .. type(regularKey))
		end

		return false
	end

	if type(altKey) ~= "string" and type(altKey) ~= "number" then
		if _D then
			print("(Keybind:update: validation) Can not update keybind, keyCombo is not a string but: " .. type(altKey))
		end

		return false
	end

	if self.forbiddenWithModifiers then
		local cantPass = false

		if string.lower(regularKey):find("shift") or string.lower(regularKey):find("ctrl") or string.lower(regularKey):find("alt") then
			regularKey = "<none>"

			displayErrorBox(tr("Warning"), tr("Keybind [%s] does not accept modified keyboard keys as input.\nDo not use the Control, Shift or Alt keys for this keybind. The keybind has been set to <none> until you change it again.", self.name))

			cantPass = true
		end

		if string.lower(altKey):find("shift") or string.lower(altKey):find("ctrl") or string.lower(altKey):find("alt") then
			altKey = "<none>"

			displayErrorBox(tr("Warning"), tr("Keybind [%s] does not accept modified keyboard keys as input.\nDo not use the Control, Shift or Alt keys for this keybind. The keybind has been set to <none> until you change it again.", self.name))

			cantPass = true
		end

		if cantPass then
			return false
		end
	end

	for _, category in pairs(KeybindManager:getCategories()) do
		for _, keybind in pairs(category.keybinds) do
			if keybind.name ~= self.name or keybind.category ~= self.category then
				if (keybind.keyCombo == regularKey or keybind.keyCombo == altKey) and regularKey ~= "<none>" then
					keybind:update("<none>", keybind.altKeyCombo)
				end

				if (keybind.altKeyCombo == altKey or keybind.altKeyCombo == regularKey) and altKey ~= "<none>" then
					keybind:update(keybind.keyCombo, "<none>")
				end
			end
		end
	end

	return true
end

function Keybind:update(regularKey, altKey)
	if self.keyCombo ~= regularKey or self.altKeyCombo ~= altKey then
		if not self:validate(regularKey, altKey) then
			return false
		end

		if self.keyCombo ~= regularKey then
			if self.active then
				self:unbind(KEYCOMBO_PRIMARY)
			end

			self.keyCombo = regularKey

			if self.active and self.keyCombo ~= "<none>" then
				self:bind(KEYCOMBO_PRIMARY)
			end
		end

		if self.altKeyCombo ~= altKey then
			if self.active then
				self:unbind(KEYCOMBO_SECONDARY)
			end

			self.altKeyCombo = altKey

			if self.active and self.altKeyCombo ~= "<none>" then
				self:bind(KEYCOMBO_SECONDARY)
			end
		end

		self:updateWidgets()
		self:cache()
	end

	return true
end

function Keybind:reset(mode)
	local regKey = self.defaultKeyCombo
	local altKey = self.defaultaltKeyCombo

	if mode == KEYCOMBO_PRIMARY then
		altKey = self.altKeyCombo
	end

	if mode == KEYCOMBO_SECONDARY then
		regKey = self.keyCombo
	end

	self:update(regKey, altKey)
end

function Keybind:clear(mode)
	if mode == KEYCOMBO_PRIMARY then
		self:update("<none>", self.altKeyCombo)
	elseif mode == KEYCOMBO_SECONDARY then
		self:update(self.keyCombo, "<none>")
	else
		self:update("<none>", "<none>")
	end
end

function Keybind:updateWidgets(removed)
	signalcall(KeybindManager.onUpdateHotkey, self.category, self.name, self.keyCombo, self.altKeyCombo)

	if type(KeybindManager.keybindToWidgetAssociations[self.category]) == "nil" then
		return
	end

	if type(KeybindManager.keybindToWidgetAssociations[self.category][self.name]) == "nil" then
		return
	end

	for _, widget in pairs(KeybindManager.keybindToWidgetAssociations[self.category][self.name]) do
		local keyComboLabel = widget.keyCombo
		local altKeyComboLabel = widget.altKeyCombo

		if type(keyComboLabel) == "nil" and type(altKeyComboLabel) == "nil" then
			if _D then
				print("(Keybind:updateWidgets()) Could not update widget of keybind [" .. self.name .. "] - its keyCombo or altKeyCombo child is missing. Tip: It must be a DIRECT child of the widget associated with the keycombo!")
			end

			return
		end

		if keyComboLabel and keyComboLabel:getText() ~= self.keyCombo then
			keyComboLabel:setText(type(removed) == "nil" and self.keyCombo or "??")
		end

		if altKeyComboLabel and altKeyComboLabel:getText() ~= self.altKeyCombo then
			altKeyComboLabel:setText(type(removed) == "nil" and self.altKeyCombo or "??")
		end
	end
end

function Keybind:getDefaultKeycombo()
	return {
		keyCombo = self.defaultKeyCombo,
		altKeyCombo = self.defaultaltKeyCombo
	}
end

function Keybind:setDefaultKeycombo(keyCombo, altKeyCombo)
	if type(keyCombo) ~= "string" and type(keyCombo) ~= "number" then
		if _D then
			print("(Keybind:setDefaultKeycombo: validation) Setting empty keyCombo because, keyCombo is not a string but: " .. type(keyCombo))
		end

		self.defaultKeyCombo = "<none>"
	else
		self.defaultKeyCombo = keyCombo
	end

	if type(altKeyCombo) ~= "string" and type(altKeyCombo) ~= "number" then
		if _D then
			print("(Keybind:setDefaultKeycombo: validation) Setting empty altKeyCombo because, altKeyCombo is not a string but: " .. type(keyCombo))
		end

		self.defaultaltKeyCombo = "<none>"
	else
		self.defaultaltKeyCombo = altKeyCombo
	end
end

function Keybind:setBindMechanisms(bindfunc, unbindfunc)
	if type(bindfunc) == "function" and type(unbindfunc) == "function" then
		self.bindFunction = bindfunc
		self.unbindFunction = unbindfunc
	end
end

function Keybind:setWidgetToBindTo(widget)
	if _D then
		print("[" .. self.name .. "]: Set widget to bind to: " .. (widget and widget:getId() or "nil"))
	end

	self.bindToWidget = widget

	KeybindManager:rememberFocusBindingFor(self)
end

function Keybind:setForbiddenWithModifiers(state)
	self.forbiddenWithModifiers = state
end

function Keybind:setMuteResistance(state)
	self.resistsMute = state
end

function Keybind:activate()
	if not self.active then
		if self.category ~= "" then
			self:bind()

			self.active = true
		else
			perror("(Keybind:activate): Can not activate a keybind which is not installed into a KeybindCategory.")
		end
	end
end

function Keybind:deactivate()
	if self.active then
		self:unbind()

		self.active = false
	end
end

function Keybind:remove(decache)
	self:unbind()
	self:updateWidgets(true)

	if decache then
		self:decache(true)
	end

	self = nil
end

function Keybind:decache(save)
	local UserKeybindSettings = KeybindManager.currentProfile:getConfig()
	local UserCatDetails = UserKeybindSettings:getNode("categories")

	if UserCatDetails then
		if next(UserCatDetails[self.category]) ~= "nil" and next(UserCatDetails[self.category][self.name]) ~= "nil" then
			UserCatDetails[self.category][self.name] = nil

			KeybindManager.currentProfile:getConfig():setNode("categories", UserCatDetails)
		end

		if save then
			KeybindManager.currentProfile:getConfig():save()
		end
	end
end

function Keybind:cache()
	local UserKeybindSettings = KeybindManager.currentProfile:getConfig()
	local UserCatDetails = UserKeybindSettings:getNode("categories")

	if type(UserCatDetails) == "nil" then
		UserCatDetails = {}
	end

	if type(UserCatDetails[self.category]) == "nil" then
		UserCatDetails[self.category] = {}
	end

	if type(UserCatDetails[self.category][self.name]) == "nil" then
		UserCatDetails[self.category][self.name] = {}
	end

	local UserThisKeybindSetting = UserCatDetails[self.category][self.name]

	if self.keyCombo == "" then
		UserThisKeybindSetting.keyCombo = nil
	else
		UserThisKeybindSetting.keyCombo = self.keyCombo
	end

	if self.altKeyCombo == "" then
		UserThisKeybindSetting.altKeyCombo = nil
	else
		UserThisKeybindSetting.altKeyCombo = self.altKeyCombo
	end

	if next(UserThisKeybindSetting) == nil then
		UserCatDetails[self.category][self.name] = nil

		if next(UserCatDetails[self.category]) == nil then
			UserCatDetails[self.category] = nil
		end
	end

	UserKeybindSettings:setNode("categories", UserCatDetails)
	UserKeybindSettings:save()
end

function Keybind:bind(mode)
	self.lastExecution = 0

	local function bindCallback()
		if KeybindManager.keybindsMuted and not self.resistsMute then
			return
		end

		if g_game.isOnline() and (g_keyboard.isChatEnabled() or g_keyboard.hasTextEditChange()) then
			return
		elseif self.lastExecution + KeybindManager.hotkeyDelay >= g_clock.millis() then
			return
		end

		self.lastExecution = g_clock.millis()

		return self.callback()
	end

	if type(mode) == "number" then
		if mode == KEYCOMBO_PRIMARY then
			if self.keyCombo ~= "<none>" then
				self.bindFunction(tostring(self.keyCombo), bindCallback, self.bindToWidget)
			end
		elseif mode == KEYCOMBO_SECONDARY and self.altKeyCombo ~= "<none>" then
			self.bindFunction(tostring(self.altKeyCombo), bindCallback, self.bindToWidget)
		end
	else
		if self.keyCombo ~= "<none>" then
			self.bindFunction(tostring(self.keyCombo), bindCallback, self.bindToWidget)
		end

		if self.altKeyCombo ~= "<none>" then
			self.bindFunction(tostring(self.altKeyCombo), bindCallback, self.bindToWidget)
		end
	end

	if _D then
		print("(Keybind:bind(): [" .. self.category .. "] -> [" .. self.name .. "] with key combos (" .. self.keyCombo .. " | " .. self.altKeyCombo .. ") to widget: " .. (self.bindToWidget and self.bindToWidget:getId() or "nil"))
	end
end

function Keybind:unbind(mode)
	if type(mode) == "number" then
		if mode == KEYCOMBO_PRIMARY then
			if self.keyCombo ~= "<none>" then
				self.unbindFunction(self.keyCombo, self.bindToWidget)
			end
		elseif mode == KEYCOMBO_SECONDARY and self.altKeyCombo ~= "<none>" then
			self.unbindFunction(self.altKeyCombo, self.bindToWidget)
		end
	else
		if self.altKeyCombo ~= "<none>" then
			self.unbindFunction(self.altKeyCombo, self.bindToWidget)
		end

		if self.keyCombo ~= "<none>" then
			self.unbindFunction(self.keyCombo, self.bindToWidget)
		end
	end

	if _D then
		print("(Keybind:unbind()): [" .. self.category .. "] -> [" .. self.name .. "]")
	end
end

function Keybind:capture(mode)
	local keybind = KeybindManager:getKeybindByName(self.name, self.category)
	local context = {
		keybind = keybind,
		mode = mode,
		description = tr("Please, press the key you wish to add:\nCurrently: {%s|%s}", "#e2bb5b", mode == KEYCOMBO_PRIMARY and keybind.keyCombo or keybind.altKeyCombo)
	}

	local function callbackConfirm(capturedKeyCombo)
		if capturedKeyCombo then
			local regKey = mode == KEYCOMBO_PRIMARY and capturedKeyCombo or keybind.keyCombo
			local altKey = mode == KEYCOMBO_SECONDARY and capturedKeyCombo or keybind.altKeyCombo

			keybind:update(regKey, altKey)
		else
			keybind:clear(mode)
		end
	end

	local function callbackReset()
		keybind:reset(mode)
	end

	KeybindManager:createCapturer(context, callbackConfirm, nil, callbackReset)
end

function Keybind:injectAsOption()
	local module = g_modules.getModule("client_options")

	if module and module:isLoaded() then
		local keybindsPanel = modules.client_options.getKeybindsPanel()
		local hotkeyNode = g_ui.createWidget("HotkeyContent", keybindsPanel.content[self.category])
		local middleCompartment = hotkeyNode.middleCompartment

		hotkeyNode.leftCompartment.hotkeyName:setText(self.name)
		KeybindManager:setAssociationBetween(self, middleCompartment)
		self:updateWidgets()

		function middleCompartment.keyCombo.onClick()
			self:capture(KEYCOMBO_PRIMARY)
		end

		function middleCompartment.altKeyCombo.onClick()
			self:capture(KEYCOMBO_SECONDARY)
		end
	end
end

function Keybind.new(category, name, keyCombo, altKeyCombo, forbiddenWithModifiers)
  local cat = KeybindManager:getCategoryByName(category)
  if not cat then
    KeybindManager:addCategory(KeybindCategory:create(category))
    cat = KeybindManager:getCategoryByName(category)
  end
  local defIndex = (cat and table.size(cat:getKeybinds()) or 0) + 1
  local kc = type(keyCombo) == 'string' and keyCombo or '<none>'
  local ak = type(altKeyCombo) == 'string' and altKeyCombo or '<none>'
  if kc == '' then kc = '<none>' end
  if ak == '' then ak = '<none>' end
  local kb = Keybind:create(defIndex, category, name, kc, ak, nil)
  if not kb then return nil end
  kb:setDefaultKeycombo(kc, ak)
  if forbiddenWithModifiers then
    kb:setForbiddenWithModifiers(true)
  end
  cat:addKeybind(kb)
  return kb
end

function Keybind.bind(category, name, bindings, widget)
  local kb = KeybindManager:getKeybindByName(name, category)
  if not kb then return false end
  local def = bindings
  if type(bindings) == 'table' and bindings[1] then
    def = bindings[1]
  end
  if def and def.type == KEY_DOWN then
    kb:setBindMechanisms(g_keyboard.bindKeyDown, g_keyboard.unbindKeyDown)
  else
    kb:setBindMechanisms(g_keyboard.bindKeyPress, g_keyboard.unbindKeyPress)
  end
  if def and type(def.callback) == 'function' then
    kb.callback = def.callback
  end
  if widget then
    kb:setWidgetToBindTo(widget)
  end
  kb:activate()
  return true
end

function Keybind.delete(category, name)
  local cat = KeybindManager:getCategoryByName(category)
  if not cat then return false end
  cat:removeKeybindByName(name)
  return true
end
