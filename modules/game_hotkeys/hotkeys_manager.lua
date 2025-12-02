﻿-- chunkname: @/modules/game_hotkeys/hotkeys_manager.lua

HOTKEY_MANAGER_USE = nil
HOTKEY_MANAGER_USEONSELF = 1
HOTKEY_MANAGER_USEONTARGET = 2
HOTKEY_MANAGER_USEWITH = 3
HotkeyColors = {
	text = "#888888",
	itemUseTarget = "#FF0000",
	itemUseSelf = "#00FF00",
	itemUseWith = "#F5B325",
	itemUse = "#8888FF",
	extraAction = "#FFAA00",
	textAutoSend = "#FFFFFF"
}
hotkeysManagerLoaded = false
hotkeysWindow = nil
configSelector = nil
currentHotkeyLabel = nil
currentItemPreview = nil
itemWidget = nil
addHotkeyButton = nil
hotkeyText = nil
selectObjectButton = nil
clearObjectButton = nil
useOnSelf = nil
useOnTarget = nil
useWith = nil
defaultComboKeys = nil
perCharacter = true
mouseGrabberWidget = nil
useRadioGroup = nil
currentHotkeys = nil
boundCombosCallback = {}
hotkeysList = {}
hotkeyConfigs = {}
currentConfig = 1
configValueChanged = false
gameRootPanel = nil
defaultComboKeysTable = {
	{
		keyCombo = "Ctrl+Up",
		value = "#s t1",
		autoSend = true
	},
	{
		keyCombo = "Ctrl+Right",
		value = "#s t2",
		autoSend = true
	},
	{
		keyCombo = "Ctrl+Down",
		value = "#s t3",
		autoSend = true
	},
	{
		keyCombo = "Ctrl+Left",
		value = "#s t4",
		autoSend = true
	},
	{
		keyCombo = "PageUp",
		value = "#s h1",
		autoSend = true
	},
	{
		keyCombo = "PageDown",
		value = "#s h2",
		autoSend = true
	},
	{
		keyCombo = "Mouse Middle",
		itemId = 3453,
		autoSend = false,
		useType = HOTKEY_MANAGER_USEWITH
	},
	{
		keyCombo = "Tab",
		autoSend = true,
		action = "attacknext"
	}
}

function init()
	gameRootPanel = modules.game_interface.getRootPanel()

	g_keyboard.bindKeyDown("Ctrl+K", toggle)

	hotkeysWindow = g_ui.displayUI("hotkeys_manager")

	hotkeysWindow:setVisible(false)

	configSelector = hotkeysWindow:getChildById("configSelector")
	currentHotkeys = hotkeysWindow:getChildById("currentHotkeys")
	currentItemPreview = hotkeysWindow:getChildById("itemPreview")
	addHotkeyButton = hotkeysWindow:getChildById("addHotkeyButton")
	removeHotkeyButton = hotkeysWindow:getChildById("removeHotkeyButton")
	hotkeyText = hotkeysWindow:getChildById("hotkeyText")
	selectObjectButton = hotkeysWindow:getChildById("selectObjectButton")
	clearObjectButton = hotkeysWindow:getChildById("clearObjectButton")
	useOnSelf = hotkeysWindow:getChildById("useOnSelf")
	useOnTarget = hotkeysWindow:getChildById("useOnTarget")
	useWith = hotkeysWindow:getChildById("useWith")
	-- Extra action widgets
	hotkeysWindow.action = hotkeysWindow:getChildById("action")
	useRadioGroup = UIRadioGroup.create()

	useRadioGroup:addWidget(useOnSelf)
	useRadioGroup:addWidget(useOnTarget)
	useRadioGroup:addWidget(useWith)

	function useRadioGroup:onSelectionChange(selected)
		onChangeUseType(selected)
	end

	mouseGrabberWidget = g_ui.createWidget("UIWidget")

	mouseGrabberWidget:setVisible(false)
	mouseGrabberWidget:setFocusable(false)

	mouseGrabberWidget.onMouseRelease = onChooseItemMouseRelease

	function currentHotkeys:onChildFocusChange(hotkeyLabel)
		onSelectHotkeyLabel(hotkeyLabel)
	end

	g_keyboard.bindKeyPress("Down", function()
		currentHotkeys:focusNextChild(KeyboardFocusReason)
	end, hotkeysWindow)
	g_keyboard.bindKeyPress("Up", function()
		currentHotkeys:focusPreviousChild(KeyboardFocusReason)
	end, hotkeysWindow)

	-- Populate extra hotkey actions in the ComboBoxGame
	if hotkeysWindow.action and setupExtraHotkeys then
		setupExtraHotkeys(hotkeysWindow.action)
		-- Garantir que a primeira opção fique selecionada inicialmente
		if hotkeysWindow.action.getOptionsCount and hotkeysWindow.action:getOptionsCount() > 0 then
			hotkeysWindow.action:setCurrentIndex(1, true)
		end
	end

	connect(g_game, {
		onGameStart = online,
		onGameEnd = offline
	})

	for i = 1, configSelector:getOptionsCount() do
		hotkeyConfigs[i] = g_configs.create("/hotkeys_" .. i .. ".otml")
	end

	setDefaultComboKeys(defaultComboKeysTable)
	load()
end

function terminate()
    disconnect(g_game, {
        onGameStart = online,
        onGameEnd = offline
    })
    g_keyboard.unbindKeyDown("Ctrl+K")
    unload()
    if hotkeysWindow then
        hotkeysWindow:destroy()
    end

    if mouseGrabberWidget then
        mouseGrabberWidget:destroy()
    end

    -- Limpar referências para evitar warnings de widget destruído com referências ativas
    hotkeysWindow = nil
    configSelector = nil
    currentHotkeys = nil
    currentItemPreview = nil
    addHotkeyButton = nil
    removeHotkeyButton = nil
    hotkeyText = nil
    selectObjectButton = nil
    clearObjectButton = nil
    useOnSelf = nil
    useOnTarget = nil
    useWith = nil
    useRadioGroup = nil
    mouseGrabberWidget = nil
    gameRootPanel = nil
end

function online()
	reload()
	hide()
end

function offline()
	unload()
	hide()
end

function show()
	if not g_game.isOnline() then
		return
	end

	hotkeysWindow:show()
	hotkeysWindow:raise()
	hotkeysWindow:focus()
end

function hide()
	hotkeysWindow:hide()
end

function toggle()
	if not hotkeysWindow:isVisible() then
		show()
	else
		hide()
	end
end

function ok()
	save()
	hide()
end

function cancel()
	reload()
	hide()
end

function bindHotkeysPress()
	unbindHotkeysPress()
	connect(gameRootPanel, {
		onKeyPress = onFirekey,
		onMousePress = onFirekey
	})
end

function unbindHotkeysPress()
	disconnect(gameRootPanel, {
		onKeyPress = onFirekey,
		onMousePress = onFirekey
	})
end

function onFirekey(widget)
	local pressedKey = g_window.getPressedKey()
	local pressedButton = g_window.getPressedMouseButton()
	local pressedModifiers = g_window.getKeyboardModifiers()
	local autoRepeatTicks = g_window.getAutoRepeatTicks()
	local keyCombo = ""

	if pressedButton == MouseNoButton then
		keyCombo = determineKeyComboDesc(pressedKey, pressedModifiers)
	else
		keyCombo = determineMouseKeyComboDesc(pressedButton, pressedModifiers)
	end

	local callback = boundCombosCallback[keyCombo]

	if callback then
		callback(widget, autoRepeatTicks)
	end
end

function load(forceDefaults)
	hotkeysManagerLoaded = false
	currentConfig = 1

	bindHotkeysPress()

	local hotkeysNode = g_settings.getNode("hotkeys") or {}
	local index = g_game.getCharacterName() .. "_" .. g_game.getClientVersion()

	if hotkeysNode[index] ~= nil and hotkeysNode[index] > 0 and hotkeysNode[index] <= #hotkeyConfigs then
		currentConfig = hotkeysNode[index]
	end

	configSelector:setCurrentIndex(currentConfig, true)

	local hotkeySettings = hotkeyConfigs[currentConfig]:getNode("hotkeys")
	local hotkeys = {}

	if not table.empty(hotkeySettings) then
		hotkeys = hotkeySettings
	end

	hotkeyList = {}

	if forceDefaults then
		loadDefautComboKeys()
	elseif not table.empty(hotkeys) then
		table.indexSort(hotkeys)

		for index, setting in ipairs(hotkeys) do
			local keyCombo = tostring(setting.keyCombo)

			setting.keyCombo = tostring(setting.keyCombo)
			setting.value = setting.value and tostring(setting.value)

			addKeyCombo(keyCombo, setting)

			hotkeyList[keyCombo] = setting
		end
	end

	if currentHotkeys:getChildCount() == 0 then
		loadDefautComboKeys()

		configValueChanged = true
	end

	configValueChanged = false
	hotkeysManagerLoaded = true
end

function unload()
	unbindHotkeysPress()

	boundCombosCallback = {}

	currentHotkeys:destroyChildren()

	currentHotkeyLabel = nil

	updateHotkeyForm(true)

	hotkeyList = {}
end

function reset()
	unload()
	load(true)
end

function reload()
	unload()
	load()
end

function save()
	if not configValueChanged then
		return
	end

	local hotkeySettings = hotkeyConfigs[currentConfig]:getNode("hotkeys") or {}

	table.clear(hotkeySettings)

	hotkeyList = {}

	for index, child in ipairs(currentHotkeys:getChildren()) do
		hotkeySettings[index] = {
			keyCombo = child.keyCombo,
			autoSend = child.autoSend,
			itemId = child.itemId,
			subType = child.subType,
			useType = child.useType,
			value = tostring(child.value),
			action = child.action
		}
		hotkeyList[tostring(child.keyCombo)] = hotkeySettings[index]
	end

	hotkeyConfigs[currentConfig]:setNode("hotkeys", hotkeySettings)
	hotkeyConfigs[currentConfig]:save()

	local index = g_game.getCharacterName() .. "_" .. g_game.getClientVersion()
	local hotkeysNode = g_settings.getNode("hotkeys") or {}

	hotkeysNode[index] = currentConfig

	g_settings.setNode("hotkeys", hotkeysNode)
	g_settings.save()
end

function onConfigChange()
	if not configSelector then
		return
	end

	local index = g_game.getCharacterName() .. "_" .. g_game.getClientVersion()
	local hotkeysNode = g_settings.getNode("hotkeys") or {}

	hotkeysNode[index] = configSelector.currentIndex

	g_settings.setNode("hotkeys", hotkeysNode)
	reload()
end

function loadDefautComboKeys()
	if not defaultComboKeys then
		for i = 1, 6 do
			addKeyCombo("Shift+F" .. i)
		end
	else
		for index, settings in ipairs(defaultComboKeys) do
			addKeyCombo(tostring(settings.keyCombo), settings)
		end
	end

	save()
end

function setDefaultComboKeys(combo)
	defaultComboKeys = combo
end

function onChooseItemMouseRelease(self, mousePosition, mouseButton)
	local item

	if mouseButton == MouseLeftButton then
		local clickedWidget = modules.game_interface.getRootPanel():recursiveGetChildByPos(mousePosition, false)

		if clickedWidget then
			if clickedWidget:getClassName() == "UIGameMap" then
				local tile = clickedWidget:getTile(mousePosition)

				if tile then
					local thing = tile:getTopMoveThing()

					if thing and thing:isItem() then
						item = thing
					end
				end
			elseif clickedWidget:getClassName() == "UIItem" and not clickedWidget:isVirtual() then
				item = clickedWidget:getItem()
			end
		end
	end

	if item and currentHotkeyLabel then
		currentHotkeyLabel.itemId = item:getId()

		if item:isFluidContainer() then
			currentHotkeyLabel.subType = item:getSubType()
		end

		if item:isMultiUse() then
			currentHotkeyLabel.useType = HOTKEY_MANAGER_USEWITH
		else
			currentHotkeyLabel.useType = HOTKEY_MANAGER_USE
		end

		currentHotkeyLabel.value = nil
		currentHotkeyLabel.autoSend = false

		updateHotkeyLabel(currentHotkeyLabel)
		updateHotkeyForm(true)
	end

	show()
	g_mouse.popCursor("target")
	self:ungrabMouse()

	return true
end

function startChooseItem()
	if g_ui.isMouseGrabbed() then
		return
	end

	mouseGrabberWidget:grabMouse()
	g_mouse.pushCursor("target")
	hide()
end

function clearObject()
	currentHotkeyLabel.action = nil
	currentHotkeyLabel.itemId = nil
	currentHotkeyLabel.subType = nil
	currentHotkeyLabel.useType = nil
	currentHotkeyLabel.autoSend = nil
	currentHotkeyLabel.value = nil

	updateHotkeyLabel(currentHotkeyLabel)
	updateHotkeyForm(true)
end

function addHotkey()
	local assignWindow = g_ui.createWidget("HotkeyAssignWindow", rootWidget)

	assignWindow:grabKeyboard()
	assignWindow:grabMouse()

	local comboLabel = assignWindow:getChildById("comboPreview")

	comboLabel.keyCombo = ""
	assignWindow.onKeyDown = hotkeyKeyboardCapture
	assignWindow.onMouseRelease = hotkeyMouseCapture
end

function addKeyCombo(keyCombo, keySettings, focus)
	keyCombo = tostring(keyCombo)

	if not keyCombo or #keyCombo == 0 then
		return
	end

	local validate, message = KeybindManager:validate("", "", keyCombo)

	if message then
		return
	end

	local hotkeyLabel = currentHotkeys:getChildById(keyCombo)

	if not hotkeyLabel then
		hotkeyLabel = g_ui.createWidget("HotkeyListLabel")

		hotkeyLabel:setId(keyCombo)

		local children = currentHotkeys:getChildren()

		children[#children + 1] = hotkeyLabel
		hotkeyList[tostring(keyCombo)] = keySettings

		for i = 1, #children do
			if children[i] == hotkeyLabel then
				currentHotkeys:insertChild(i, hotkeyLabel)

				break
			end
		end

		if keySettings then
			currentHotkeyLabel = hotkeyLabel
			hotkeyLabel.keyCombo = tostring(keyCombo)
			hotkeyLabel.autoSend = toboolean(keySettings.autoSend)
			hotkeyLabel.action = keySettings.action
			hotkeyLabel.itemId = tonumber(keySettings.itemId)
			hotkeyLabel.subType = tonumber(keySettings.subType)
			hotkeyLabel.useType = tonumber(keySettings.useType)

			if keySettings.value then
				hotkeyLabel.value = tostring(keySettings.value)
			end
		else
			hotkeyLabel.keyCombo = tostring(keyCombo)
			hotkeyLabel.autoSend = false
			hotkeyLabel.itemId = nil
			hotkeyLabel.subType = nil
			hotkeyLabel.useType = nil
			hotkeyLabel.action = nil
			hotkeyLabel.value = ""
		end

		updateHotkeyLabel(hotkeyLabel)

		boundCombosCallback[tostring(keyCombo)] = function(c, ticks)
			prepareKeyCombo(tostring(keyCombo), ticks)
		end
	end

	if focus then
		currentHotkeys:focusChild(hotkeyLabel)
		currentHotkeys:ensureChildVisible(hotkeyLabel)
		updateHotkeyForm(true)
	end

	configValueChanged = true
end

function prepareKeyCombo(keyCombo, ticks)
	local hotKey = hotkeyList[tostring(keyCombo)]

	if keyCombo:lower():find("ctrl") and not hotKey or hotKey and hotKey.itemId == nil and (not hotKey.value or #hotKey.value == 0) and not hotKey.action then
		keyCombo = keyCombo:gsub("Ctrl%+", "")
		keyCombo = keyCombo:gsub("ctrl%+", "")
		hotKey = hotkeyList[tostring(keyCombo)]
	end

	if not hotKey or modules.game_console.isChatEnabled() and not g_keyboard.isSkipKey(keyCombo) then
		return
	end

	if hotKey.itemId == nil and hotKey.action == nil then
		scheduleEvent(function()
			doKeyCombo(tostring(keyCombo), ticks >= 5)
		end, g_settings.getNumber("hotkeyDelay"))
	else
		doKeyCombo(tostring(keyCombo), ticks >= 5)
	end
end

function doKeyCombo(keyCombo, repeated)
	keyCombo = tostring(keyCombo)

	if not g_game.isOnline() then
		return
	end

	if modules.game_console and modules.game_console.isChatEnabled() and keyCombo:len() == 1 then
		return
	end

	if modules.game_walking then
		modules.game_walking.checkTurn()
	end

	local hotKey = hotkeyList[keyCombo]

	if not hotKey then
		return
	end

	local hotkeyDelay = 100

	if hotKey.hotkeyDelayTo == nil or g_clock.millis() > hotKey.hotkeyDelayTo + hotkeyDelay then
		hotkeyDelay = 200
	end

	if hotKey.hotkeyDelayTo ~= nil and g_clock.millis() < hotKey.hotkeyDelayTo then
		return
	end

	if hotKey.action then
		executeExtraHotkey(hotKey.action, repeated)
	elseif hotKey.itemId == nil then
		if not hotKey.value or #hotKey.value == 0 then
			return
		end

		if hotKey.autoSend then
			modules.game_console.sendMessage(hotKey.value)
		else
			modules.game_console.setTextEditText(hotKey.value)
		end

		hotKey.hotkeyDelayTo = g_clock.millis() + hotkeyDelay
	elseif hotKey.useType == HOTKEY_MANAGER_USE then
		if g_game.getClientVersion() < 780 then
			local item = g_game.findPlayerItem(hotKey.itemId, hotKey.subType or -1)

			if item then
				g_game.use(item)
			end
		else
			g_game.useInventoryItem(hotKey.itemId)
		end

		hotKey.hotkeyDelayTo = g_clock.millis() + hotkeyDelay
	elseif hotKey.useType == HOTKEY_MANAGER_USEONSELF then
		if g_game.getClientVersion() < 780 then
			local item = g_game.findPlayerItem(hotKey.itemId, hotKey.subType or -1)

			if item then
				g_game.useWith(item, g_game.getLocalPlayer())
			end
		else
			g_game.useInventoryItemWith(hotKey.itemId, g_game.getLocalPlayer(), hotKey.subType or -1)
		end

		hotKey.hotkeyDelayTo = g_clock.millis() + hotkeyDelay
	elseif hotKey.useType == HOTKEY_MANAGER_USEONTARGET then
		local attackingCreature = g_game.getAttackingCreature()

		if not attackingCreature then
			local item = Item.create(hotKey.itemId)

			if g_game.getClientVersion() < 780 then
				local tmpItem = g_game.findPlayerItem(hotKey.itemId, hotKey.subType or -1)

				if not tmpItem then
					return
				end

				item = tmpItem
			end

			modules.game_interface.startUseWith(item, hotKey.subType or -1)

			return
		end

		if not attackingCreature:getTile() then
			return
		end

		if g_game.getClientVersion() < 780 then
			local item = g_game.findPlayerItem(hotKey.itemId, hotKey.subType or -1)

			if item then
				g_game.useWith(item, attackingCreature, hotKey.subType or -1)
			end
		else
			g_game.useInventoryItemWith(hotKey.itemId, attackingCreature, hotKey.subType or -1)
		end

		hotKey.hotkeyDelayTo = g_clock.millis() + hotkeyDelay
	elseif hotKey.useType == HOTKEY_MANAGER_USEWITH then
		local item = Item.create(hotKey.itemId)

		if g_game.getClientVersion() < 780 then
			local tmpItem = g_game.findPlayerItem(hotKey.itemId, hotKey.subType or -1)

			if not tmpItem then
				return true
			end

			item = tmpItem
		end

		modules.game_interface.startUseWith(item, hotKey.subType or -1)
	end
end

function updateHotkeyLabel(hotkeyLabel)
	if not hotkeyLabel then
		return
	end

	if hotkeyLabel.action ~= nil then
		hotkeyLabel:setText(tr("%s: (Action: %s)", hotkeyLabel.keyCombo, getActionDescription(hotkeyLabel.action)))
		hotkeyLabel:setColor(HotkeyColors.extraAction)
	elseif hotkeyLabel.useType == HOTKEY_MANAGER_USEONSELF then
		hotkeyLabel:setText(tr("%s: (use object on yourself)", hotkeyLabel.keyCombo))
		hotkeyLabel:setColor(HotkeyColors.itemUseSelf)
	elseif hotkeyLabel.useType == HOTKEY_MANAGER_USEONTARGET then
		hotkeyLabel:setText(tr("%s: (use object on target)", hotkeyLabel.keyCombo))
		hotkeyLabel:setColor(HotkeyColors.itemUseTarget)
	elseif hotkeyLabel.useType == HOTKEY_MANAGER_USEWITH then
		hotkeyLabel:setText(tr("%s: (use object with crosshair)", hotkeyLabel.keyCombo))
		hotkeyLabel:setColor(HotkeyColors.itemUseWith)
	elseif hotkeyLabel.itemId ~= nil then
		hotkeyLabel:setText(tr("%s: (use object)", hotkeyLabel.keyCombo))
		hotkeyLabel:setColor(HotkeyColors.itemUse)
	else
		local text = hotkeyLabel.keyCombo .. ": "

		if hotkeyLabel.value then
			text = text .. hotkeyLabel.value
		end

		hotkeyLabel:setText(text)

		if hotkeyLabel.autoSend then
			hotkeyLabel:setColor(HotkeyColors.autoSend)
		else
			hotkeyLabel:setColor(HotkeyColors.text)
		end
	end
end

function updateHotkeyForm(reset)
	configValueChanged = true

    if hotkeysWindow.action then
        -- Sempre manter o combobox habilitado e selecionado na primeira opção
        hotkeysWindow.action:enable()

        if currentHotkeyLabel and currentHotkeyLabel.action then
            hotkeysWindow.action:setCurrentIndex(translateActionToActionComboboxIndex(currentHotkeyLabel.action), true)
        else
            hotkeysWindow.action:setCurrentIndex(1, true)
        end
    end

	local hasCustomAction = hotkeysWindow.action and hotkeysWindow.action.currentIndex > 1

	if currentHotkeyLabel and not hasCustomAction then
		if currentHotkeyLabel.itemId ~= nil then
			hotkeyText:clearText()
			hotkeyText:disable()
			selectObjectButton:disable()
			clearObjectButton:enable()
			currentItemPreview:setItemId(currentHotkeyLabel.itemId)

			if currentHotkeyLabel.subType then
				currentItemPreview:setItemSubType(currentHotkeyLabel.subType)
			end

			if currentItemPreview:getItem():isMultiUse() then
				useOnSelf:enable()
				useOnTarget:enable()
				useWith:enable()

				if currentHotkeyLabel.useType == HOTKEY_MANAGER_USEONSELF then
					useRadioGroup:selectWidget(useOnSelf)
				elseif currentHotkeyLabel.useType == HOTKEY_MANAGER_USEONTARGET then
					useRadioGroup:selectWidget(useOnTarget)
				elseif currentHotkeyLabel.useType == HOTKEY_MANAGER_USEWITH then
					useRadioGroup:selectWidget(useWith)
				end
			else
				useOnSelf:disable()
				useOnTarget:disable()
				useWith:disable()
				useRadioGroup:clearSelected()
			end
		else
			useOnSelf:disable()
			useOnTarget:disable()
			useWith:disable()
			useRadioGroup:clearSelected()
			hotkeyText:enable()
			hotkeyText:focus()

			if reset then
				hotkeyText:setCursorPos(-1)
			end

			hotkeyText:setText(currentHotkeyLabel.value)
			selectObjectButton:enable()
			clearObjectButton:disable()
			currentItemPreview:clearItem()
		end
	else
		hotkeyText:disable()
		selectObjectButton:disable()
		clearObjectButton:disable()
		useOnSelf:disable()
		useOnTarget:disable()
		useWith:disable()
		hotkeyText:clearText()
		useRadioGroup:clearSelected()
		currentItemPreview:clearItem()
	end
end

function removeHotkey()
	if currentHotkeyLabel == nil then
		return
	end

	local gameRootPanel = modules.game_interface.getRootPanel()

	configValueChanged = true
	boundCombosCallback[currentHotkeyLabel.keyCombo] = nil

	currentHotkeyLabel:destroy()

	currentHotkeyLabel = nil
end

function updateHotkeyAction()
	if not hotkeysManagerLoaded then
		return
	elseif currentHotkeyLabel == nil then
		return
	end

	configValueChanged = true
	currentHotkeyLabel.action = translateActionComboboxIndexToAction(hotkeysWindow.action.currentIndex)

	updateHotkeyLabel(currentHotkeyLabel)
	updateHotkeyForm()
end

function onHotkeyTextChange(value)
	if not hotkeysManagerLoaded then
		return
	elseif currentHotkeyLabel == nil then
		return
	end

	currentHotkeyLabel.value = tostring(value)

	if value == "" then
		currentHotkeyLabel.autoSend = false
	end

	configValueChanged = true

	updateHotkeyLabel(currentHotkeyLabel)
	updateHotkeyForm()
end

function onSendAutomaticallyChange(autoSend)
	if not hotkeysManagerLoaded then
		return
	elseif currentHotkeyLabel == nil then
		return
	end

	if not currentHotkeyLabel.value or #currentHotkeyLabel.value == 0 then
		return
	end

	configValueChanged = true
	currentHotkeyLabel.autoSend = autoSend

	updateHotkeyLabel(currentHotkeyLabel)
	updateHotkeyForm()
end

function onChangeUseType(useTypeWidget)
	if not hotkeysManagerLoaded then
		return
	elseif currentHotkeyLabel == nil then
		return
	end

	configValueChanged = true

	if useTypeWidget == useOnSelf then
		currentHotkeyLabel.useType = HOTKEY_MANAGER_USEONSELF
	elseif useTypeWidget == useOnTarget then
		currentHotkeyLabel.useType = HOTKEY_MANAGER_USEONTARGET
	elseif useTypeWidget == useWith then
		currentHotkeyLabel.useType = HOTKEY_MANAGER_USEWITH
	else
		currentHotkeyLabel.useType = HOTKEY_MANAGER_USE
	end

	updateHotkeyLabel(currentHotkeyLabel)
	updateHotkeyForm()
end

function onSelectHotkeyLabel(hotkeyLabel)
	currentHotkeyLabel = hotkeyLabel

	updateHotkeyForm(true)
end

function hotkeyKeyboardCapture(assignWindow, keyCode, keyboardModifiers)
	local keyCombo = determineKeyComboDesc(keyCode, keyboardModifiers)
	local comboPreview = assignWindow:getChildById("comboPreview")
	local hotkeyType = g_keyboard.getHotkeyType(keyCombo)
	local hasKey, msg = KeybindManager:validate("", "", keyCombo)
	local desc = msg and "options hotkeys" or hotkeyType

	comboPreview:setText(tr("Current hotkey to add: %s", keyCombo))

	comboPreview.keyCombo = keyCombo

	comboPreview:resizeToText()
	assignWindow.usingHotkey:setVisible(hotkeyType or msg)
	assignWindow.usingHotkey:setText(tr("This hotkey is being used in %s", tr(desc or "")))
	assignWindow:getChildById("addButton"):setEnabled(not hotkeyType and not msg)

	return true
end

function hotkeyMouseCapture(assignWindow, mousePos, mouseButton)
	local keyboardModifiers = g_keyboard.getModifiers()
	local keyCombo = determineMouseKeyComboDesc(mouseButton, keyboardModifiers)
	local comboPreview = assignWindow:getChildById("comboPreview")
	local hotkeyType = g_keyboard.getHotkeyType(keyCombo)
	local hasKey, msg = KeybindManager:validate("", "", keyCombo)
	local desc = msg and "options hotkeys" or hotkeyType

	comboPreview:setText(tr("Current hotkey to add: %s", keyCombo))

	comboPreview.keyCombo = keyCombo

	comboPreview:resizeToText()
	assignWindow.usingHotkey:setVisible(hotkeyType or msg)
	assignWindow.usingHotkey:setText(tr("This hotkey is being used in %s", tr(desc or "")))
	assignWindow:getChildById("addButton"):setEnabled(not hotkeyType and not msg)

	return true
end

function hotkeyCaptureOk(assignWindow, keyCombo)
	addKeyCombo(keyCombo, nil, true)
	assignWindow:destroy()
end
