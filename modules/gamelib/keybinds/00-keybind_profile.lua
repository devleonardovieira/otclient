-- chunkname: @/modules/gamelib/keybinds/00-keybind_profile.lua

local _D = false

KeybindProfile = {}

function KeybindProfile:generate(name, config)
	local profile = {}

	self.__index = self

	setmetatable(profile, self)

	profile.name = name
	profile.protected = false
	profile.config = config
	profile.fullpath = KB_PROFILES_PATH .. name .. ".otml"

	if KeybindManager:addProfile(profile) then
		return profile
	end

	return nil
end

function KeybindProfile:getName()
	return self.name
end

function KeybindProfile:getConfig()
	return self.config
end

function KeybindProfile:protect()
	self.protected = true
end

function KeybindProfile:getFullPath()
	return self.fullpath
end

function KeybindProfile:activate(firstActivation)
	if self == KeybindManager.currentProfile then
		if _D then
			print("(KeybindProfile:activate) Profile " .. self.name .. " already active.")
		end

		return
	end

	if _D then
		print("(KeybindProfile:activate) Profile " .. self.name .. " activation begins.")
	end

	for _, category in pairs(KeybindManager:getCategories()) do
		category:remove()
	end

	KeybindManager.categories = {}
	KeybindManager.currentProfile = self

	KeybindManager.config:set("profile", self.name)

	local UserCategories = self.config:getNode("categories")

	if type(UserCategories) == "nil" then
		UserCategories = {}
	end

	if _D then
		print("(KeybindProfile:activate) Creating categories...")
	end

	for userCategoryName, _ in pairs(UserCategories) do
		if not KeybindManager:hasCategoryByName(userCategoryName) then
			KeybindManager:addCategory(KeybindCategory:create(userCategoryName))
		end
	end

	for defaultCatName, defaultCatConfig in pairs(KB_DEFAULTS) do
		if not KeybindManager:hasCategoryByName(defaultCatName) then
			KeybindManager:addCategory(KeybindCategory:create(defaultCatName))
		end
	end

	if _D then
		print("(KeybindProfile:activate) Adding keybinds to categories.")
	end

	local UserKbSettings, UserKbAttribs, DefaultKbSetting, newKeyCombo, newaltKeyCombo, newKeybind
	local compilation = {}
	local existingCategories = table.copy(KeybindManager:getCategories())

	for _, category in pairs(existingCategories) do
		UserKbSettings = UserCategories[category.name]

		if type(UserKbSettings) == "nil" then
			UserKbSettings = {}
		end

		compilation[category.name] = {}

		for UserKbName, UserKbAttribs in pairs(UserKbSettings) do
			compilation[category.name][UserKbName] = {}

			if UserKbAttribs.keyCombo then
				compilation[category.name][UserKbName].keyCombo = UserKbAttribs.keyCombo
			end

			if UserKbAttribs.altKeyCombo then
				compilation[category.name][UserKbName].altKeyCombo = UserKbAttribs.altKeyCombo
			end

			if type(UserKbAttribs.callback) == "string" then
				compilation[category.name][UserKbName].callback = UserKbAttribs.callback
			end
		end
	end

	for defaultCatName, dfCatSett in pairs(KB_DEFAULTS) do
		for defaultKBIndex, defaultKBData in pairs(dfCatSett.content) do
			if type(compilation[defaultCatName][defaultKBData.name]) ~= "table" then
				compilation[defaultCatName][defaultKBData.name] = {}
			end

			local temp = table.copy(defaultKBData)

			table.merge(temp, compilation[defaultCatName][defaultKBData.name])

			compilation[defaultCatName][defaultKBData.name] = table.copy(temp)
			compilation[defaultCatName][defaultKBData.name].defIndex = defaultKBIndex
			compilation[defaultCatName][defaultKBData.name].defKeyCombo = defaultKBData.keyCombo
			compilation[defaultCatName][defaultKBData.name].defaltKeyCombo = defaultKBData.altKeyCombo
		end
	end

	for catName, catContent in pairs(compilation) do
		for kbName, kbSettings in pairs(catContent) do
			if not KeybindManager:getCategoryByName(catName):getKeybindByName(kbName) then
				newKeybind = Keybind:create(kbSettings.defIndex, catName, kbName, kbSettings.keyCombo, kbSettings.altKeyCombo, kbSettings.callback)

				if newKeybind then
					KeybindManager:getCategoryByName(catName):addKeybind(newKeybind)
				else
					if _D then
						print("(KeybindProfile:activate) Skipping keybind '" .. kbName .. "' in category '" .. catName .. "' due to invalid configuration or missing callback.")
					end
				end
			else
				newKeybind = KeybindManager:getCategoryByName(catName):getKeybindByName(kbName)
			end

			if newKeybind then
				newKeybind:setDefaultKeycombo(kbSettings.defKeyCombo, kbSettings.defaltKeyCombo)
				newKeybind:setForbiddenWithModifiers(kbSettings.forbiddenWithModifiers and true or false)
				newKeybind:setMuteResistance(kbSettings.resistsMute and true or false)

				if type(kbSettings.bindFunction) ~= "nil" and type(kbSettings.unbindFunction) ~= "nil" then
					newKeybind:setBindMechanisms(kbSettings.bindFunction, kbSettings.unbindFunction)
				end

				if KeybindManager.rememberedFocusBindings[catName] and KeybindManager.rememberedFocusBindings[catName][kbName] then
					newKeybind:setWidgetToBindTo(KeybindManager.rememberedFocusBindings[catName][kbName])
				end

				if not firstActivation then
					newKeybind:activate()
				end
			end
		end
	end

	self:selectAsOption()
	KeybindManager.config:save()

	if _D then
		print("(KeybindProfile:activate) Profile " .. self.name .. " activation done.")
	end
end

function KeybindProfile:delete()
	if self.protected then
		displayErrorBox(tr("Error"), tr("This profile can not be deleted."))

		return false
	end

	if g_resources.fileExists(KB_PROFILES_PATH .. self.name .. ".otml") then
		g_resources.deleteFile(KB_PROFILES_PATH .. self.name .. ".otml")

		if KeybindManager.profile == self then
			KeybindManager:getProfileByName("Default"):activate()
		end

		KeybindManager:removeProfile(self)
		displayInfoBox(tr("Success"), tr("Profile deleted. Switched to Default."))
	else
		displayErrorBox(tr("Error"), tr("No file matching this profile's name was found. Can not delete."))

		return false
	end

	self = nil

	return true
end

function KeybindProfile:selectAsOption()
	local module = g_modules.getModule("client_options")

	if module and module:isLoaded() then
		local keybindsPanel = modules.client_options.getKeybindsPanel()
		local profilePicker = keybindsPanel.profilesPanel.profilePicker

		profilePicker:disable()
		profilePicker:setCurrentOption(self:getName())
		profilePicker:enable()
	end
end

function KeybindProfile:injectAsOption()
	local module = g_modules.getModule("client_options")

	if module and module:isLoaded() then
		local keybindsPanel = modules.client_options.getKeybindsPanel()
		local profilePicker = keybindsPanel.profilesPanel.profilePicker

		profilePicker:addOption(self:getName(), self:getName())
	end
end
