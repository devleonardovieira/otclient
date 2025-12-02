-- chunkname: @/modules/gamelib/keybinds/03-keybind_manager.lua

local _D = false
local _keybindManager = {}

function _keybindManager:create()
	local manager = {}

	manager.categories = {}
	manager.profiles = {}
	manager.capturer = nil
	manager.config = g_configs.create("/keybinds.otml")
	manager.keyComboMode = manager.config:getNumber("selectedKeyComboMode", KEYCOMBO_PRIMARY)
	manager.autoProfileSwitching = manager.config:getBoolean("autoProfileSwitching", false)
	manager.currentProfile = nil
	manager.defaultProfile = nil
	manager.keybindToWidgetAssociations = {}
	manager.rememberedFocusBindings = {}
	manager.keybindsMuted = false
	manager.hotkeyDelay = 150
	self.__index = self

	setmetatable(manager, self)

	return manager
end

function _keybindManager:initialize()
	if not g_resources.directoryExists("/profiles") then
		g_resources.makeDir("/profiles")

		if _D then
			print("Couldn't find /profiles. Created it.")
		end
	end

	if not g_resources.directoryExists(KB_PROFILES_PATH) then
		g_resources.makeDir("/profiles/keybinds")

		if _D then
			print("Couldn't find /profiles/keybinds. Created it.")
		end
	end

	self:createDefaultProfile()

	local detectedProfiles = {}

	for _, filename in pairs(g_resources.listDirectoryFiles(KB_PROFILES_PATH)) do
		local f = filename:gsub("%.otml", "")

		table.insert(detectedProfiles, f)
	end

	for _, name in pairs(detectedProfiles) do
		if string.lower(name) ~= "default" then
			local cfg = g_configs.create(KB_PROFILES_PATH .. name .. ".otml")

			if type(cfg) == "userdata" then
				KeybindProfile:generate(name, cfg)
			else
				perror("(Keybind Manager: Initialize) Unable to load profile for " .. name .. ", a proper configuration object could not be initialized based on " .. g_resources.getUserDir() .. KB_PROFILES_PATH .. name .. ".otml. The file may be corrupt or completely empty. If this issue persists, it could be resolved by removing the file. If saving this configuration is important to you, you may submit the file to the staff for an analysis.")
			end
		end
	end

	local profileToLoad = self.config:getString("profile")
	local profile = self:getProfileByName(profileToLoad)

	if type(profile) == "nil" then
		profile = self:getProfileByName("Default")
	end

	profile:activate(true)
end

function _keybindManager:createProfile(name)
	local contentToCopy, nameTemp

	if g_resources.fileExists(self.currentProfile:getFullPath()) then
		contentToCopy = g_resources.readFileContents(self.currentProfile:getFullPath())
	else
		displayErrorBox(tr("Error"), tr("Could not copy over your current profile. The file likely went missing or corrupt. Copying from the default profile instead."))

		if self.defaultProfile then
			contentToCopy = g_resources.readFileContents(self.defaultProfile:getFullPath())
		else
			displayErrorBox(tr("Warning"), "Unable to locate Default keybind profile. Something has gone terribly wrong. We will create the Default profile again for you. Report this incident to if related errors persist.")
			self:createDefaultProfile()

			return self:createProfile(name)
		end

		return
	end

	if _D then
		print("Working on creating " .. name .. " profile. Copied from " .. (g_resources.fileExists(self.currentProfile:getFullPath()) and self.currentProfile.name or "DEFAULT"))
	end

	g_configs.create(KB_PROFILES_PATH .. name .. ".otml")
	g_resources.writeFileContents(KB_PROFILES_PATH .. name .. ".otml", contentToCopy)

	local newProfile = KeybindProfile:generate(name, g_configs.get(KB_PROFILES_PATH .. name .. ".otml"))

	if newProfile then
		return newProfile
	end
end

function _keybindManager:createDefaultProfile()
	self.defaultProfile = KeybindProfile:generate("Default", g_configs.create(KB_PROFILES_PATH .. "default.otml"))

	self.defaultProfile:protect()
end

function _keybindManager:getProfileByName(name)
    if type(name) ~= "string" then
        return nil
    end

    for _, v in pairs(self.profiles) do
        if type(v.name) == "string" and string.lower(v.name) == string.lower(name) then
            return v
        end
    end
end

function _keybindManager:addProfile(profile)
	for _, prof in pairs(self.profiles) do
		if prof.name == profile.name then
			if _D then
				print("(KeybindManager:addProfile) Can not register profile " .. profile.name .. ". Another with the same name exists.")
			end

			return false
		end
	end

	table.insert(self.profiles, profile)

	if _D then
		print("(KeybindManager:addProfile): Profile " .. profile.name .. " registered.")
	end

	profile:injectAsOption()

	return true
end

function _keybindManager:removeProfile(profile)
	local indexFound

	for i, v in pairs(self.profiles) do
		if v.name == profile.name then
			indexFound = i
		end
	end

	if indexFound then
		self.profiles[indexFound] = nil
	end
end

function _keybindManager:getCategories()
	return self.categories
end

function _keybindManager:getProfiles()
	return self.profiles
end

function _keybindManager:hasCategoryByName(name)
	for _, category in pairs(self.categories) do
		if name == category.name then
			return true
		end
	end

	return false
end

function _keybindManager:getCategoryByName(name)
    if type(name) ~= "string" then
        return nil
    end

    for _, category in pairs(self.categories) do
        if type(category.name) == "string" and name:lower() == category.name:lower() then
            return category
        end
    end

    return nil
end

function _keybindManager:addCategory(KeybindCategoryObject)
	local prefIndex = table.find(KB_CATEGORY_LOAD_ORDER, KeybindCategoryObject.name)

	if type(prefIndex) == "number" and type(self.categories[prefIndex]) ~= "table" then
		self.categories[prefIndex] = KeybindCategoryObject
	else
		table.insert(self.categories, KeybindCategoryObject)
	end
end

function _keybindManager:getKeybindByName(name, categoryName)
    if type(categoryName) ~= "string" or type(name) ~= "string" then
        if _D then
            print("(KeybindManager:getKeybindByName) Invalid inputs: categoryName=" .. tostring(categoryName) .. ", name=" .. tostring(name))
        end
        return nil
    end

    local category = self:getCategoryByName(categoryName)

    if category then
        for _, keybind in pairs(category.keybinds) do
            if type(keybind.name) == "string" and string.lower(name) == string.lower(keybind.name) then
                return keybind
            end
        end

		if _D then
			print("(KeybindManager:getKeybindByName(" .. name .. "," .. categoryName .. ")): Not found.")
		end
	elseif _D then
		print("(KeybindManager:getKeybindByName(" .. name .. "," .. categoryName .. ")): Invalid category.")
	end

	if _D then
		print("(KeybindManager:getKeybindByName(" .. name .. "," .. categoryName .. ")): Returned nil.")
	end

	return nil
end

function _keybindManager:getKeyComboMode()
	return self.keyComboMode
end

function _keybindManager:resetToDefaults()
	for _, category in pairs(self:getCategories()) do
		for _, keybind in pairs(category:getKeybinds()) do
			keybind:reset()
		end
	end
end

function _keybindManager:toggleAutoProfileSwitching()
	self.autoProfileSwitching = not self.autoProfileSwitching

	self.config:set("autoProfileSwitching", self.autoProfileSwitching)
	self.config:save()
end

function _keybindManager:propagate()
	for _, category in pairs(self:getCategories()) do
		for _, keybind in pairs(category:getKeybinds()) do
			if keybind.keyCombo ~= keybind.altKeyCombo then
				keybind:deactivate()
				keybind:activate()
			end

			keybind:updateWidgets()
		end
	end
end

function _keybindManager:rememberFocusBindingFor(Keybind)
	if type(self.rememberedFocusBindings[Keybind.category]) ~= "table" then
		self.rememberedFocusBindings[Keybind.category] = {}
	end

	self.rememberedFocusBindings[Keybind.category][Keybind.name] = Keybind.bindToWidget
end

function _keybindManager:setAssociationBetween(Keybind, widget)
	if type(widget:recursiveGetChildById("keyCombo")) == "nil" and type(widget:recursiveGetChildById("altKeyCombo")) == "nil" then
		if _D then
			perror("(KeybindManager:setAssociationBetween(" .. Keybind.name .. " | " .. widget:getId() .. ")) Can not associate because the widget is missing a direct child with ID 'keyCombo' OR 'altKeyCombo'. Needs both.")
		end

		return
	end

	if type(self.keybindToWidgetAssociations[Keybind.category]) ~= "table" then
		self.keybindToWidgetAssociations[Keybind.category] = {}
	end

	if type(self.keybindToWidgetAssociations[Keybind.category][Keybind.name]) ~= "table" then
		self.keybindToWidgetAssociations[Keybind.category][Keybind.name] = {}
	end

	local widgets = self.keybindToWidgetAssociations[Keybind.category][Keybind.name]

	widgets[table.size(widgets) + 1] = widget
end

function _keybindManager:validate(categoryName, keybindName, keyCombo)
	for _, category in pairs(self:getCategories()) do
		for _, keybind in pairs(category.keybinds) do
			local hasKeyCombo = (keybind.altKeyCombo == keyCombo or keybind.keyCombo == keyCombo) and keyCombo ~= "<none>"

			if keybind.category == categoryName and keybind.name == keybindName and hasKeyCombo then
				return false, tr("This shortcut key is already configured for action {%s|%s}", "#e2bb5b", keybind.name)
			elseif hasKeyCombo then
				return true, tr(" {%s|%s} is already being used for {%s|%s}.\nIf you replace this shortcut, be sure to add a new one for it.", "#e2bb5b", keyCombo, "#e2bb5b", keybind.name)
			end
		end
	end

	return true
end

function _keybindManager:createCapturer(context, callbackConfirm, callbackCancel, callbackReset)
	local function defaultCancel()
		self.capturer:destroy()

		self.capturer = nil
	end

	local function defaultConfirm()
		defaultCancel()
	end

	local function defaultReset()
		defaultCancel()

		if type(callbackReset) == "function" then
			callbackReset()
		end
	end

	if type(callbackConfirm) ~= "function" then
		callbackConfirm = defaultConfirm
	end

	if type(callbackCancel) ~= "function" then
		callbackCancel = defaultCancel
	end

	if self.capturer then
		defaultCancel()
	end

	self.capturer = g_ui.createWidget("KeybindAssignWindow", rootWidget)

	self.capturer:setText(tr("Add shortcut") .. ": " .. (context.keybind.name:len() > 12 and string.sub(context.keybind.name, 1, #context.keybind.name - 8) .. "..." or context.keybind.name))
	self.capturer:onVisibilityChange(true)
	self.capturer.context:setMultiColorText(context.description)
	self.capturer:grabKeyboard()

	local capturePreview = self.capturer.capturePreview

	capturePreview:resizeToText()

	local function capture(thisWindow, keyCode, keyboardModifiers)
		local keyCombo = g_keyboard.determineKeyComboDescription(keyCode, keyboardModifiers)

		if keyCombo == "Escape" then
			callbackCancel()

			return
		end

		capturePreview:setText(keyCombo)

		capturePreview.keyCombo = keyCombo

		capturePreview:resizeToText()

		local validate, message = self:validate(context.keybind.category, context.keybind.name, keyCombo)

		if type(message) == "string" then
			thisWindow.extra:setMultiColorText(message)
			thisWindow:setHeight(210 + thisWindow.extra:getTextSize().height)
		else
			thisWindow.extra:clearText()
			thisWindow:setHeight(210)
		end

		thisWindow.confirmButton:setEnabled(validate)

		return true
	end

	self.capturer.cancelButton.onClick = defaultCancel
	self.capturer.onKeyDown = capture
	self.capturer.onMouseRelease = capture

	function self.capturer.confirmButton.onClick()
		callbackConfirm(capturePreview.keyCombo)
		self.capturer:destroy()

		self.capturer = nil
	end

	local canResetKeyCombo = context.mode == KEYCOMBO_PRIMARY and context.keybind.keyCombo ~= context.keybind.defaultKeyCombo or context.mode == KEYCOMBO_SECONDARY and context.keybind.altKeyCombo ~= context.keybind.defaultaltKeyCombo

	self.capturer.resetButton:setVisible(canResetKeyCombo)

	self.capturer.resetButton.onClick = defaultReset

	self.capturer:raise()

	return self.capturer
end

KeybindManager = _keybindManager:create()

KeybindManager:initialize()
