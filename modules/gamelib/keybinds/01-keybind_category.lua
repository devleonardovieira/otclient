-- chunkname: @/modules/gamelib/keybinds/01-keybind_category.lua

local _D = false

KeybindCategory = {}

function KeybindCategory:create(name)
	local category = {}

	category.name = name
	category.keybinds = {}
	self.__index = self

	setmetatable(category, self)

	return category
end

function KeybindCategory:getKeybinds()
	return self.keybinds
end

function KeybindCategory:getKeybindByName(name)
	for _, keybind in pairs(self.keybinds) do
		if keybind.name == name then
			return keybind
		end
	end

	return nil
end

function KeybindCategory:removeKeybindByName(name)
	local keybind = self:getKeybindByName(name)

	if keybind then
		keybind:remove()
	end
end

function KeybindCategory:addKeybind(Keybind)
    if type(Keybind) ~= "table" then
        if _D then
            print("(KeybindCategory:addKeybind) Ignoring invalid keybind for category '" .. tostring(self.name) .. "' (value=" .. tostring(Keybind) .. ")")
        end
        return false
    end

    if type(Keybind.defaultIndex) ~= "number" or Keybind.defaultIndex < 1 then
        Keybind.defaultIndex = table.size(self.keybinds) + 1
    end

    if type(self.keybinds[Keybind.defaultIndex]) == "nil" then
        self.keybinds[Keybind.defaultIndex] = Keybind
    else
        table.insert(self.keybinds, Keybind)

        if _D then
            print("(KeybindCategory:addKeybind): Keybind " .. Keybind.name .. " could not be inserted at its preferred index (" .. Keybind.defaultIndex .. ") in the category [" .. self.name .. "] because the index is already taken by another keybind (" .. self.keybinds[Keybind.defaultIndex].name .. "). Added in the bottom-most index (" .. table.size(self.keybinds) .. ").")
        end
    end

    return true
end

function KeybindCategory:remove()
	for i, keybind in pairs(self.keybinds) do
		keybind:remove()
	end

	self.keybinds = {}
end

function KeybindCategory:injectAsOption()
	local module = g_modules.getModule("client_options")

	if module and module:isLoaded() then
		local keybindsPanel = modules.client_options.getKeybindsPanel()
		local section = g_ui.createWidget("HotkeySection", keybindsPanel.content)
		local header = g_ui.createWidget("HotkeyHeader", section)

		header:setText(self.name)
		section:setId(self.name)
	end
end
