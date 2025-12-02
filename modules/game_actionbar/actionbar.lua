-- chunkname: @/modules/game_actionbar/actionbar.lua

actionPanel1 = nil
mouseGrabberWidget = nil
actionBottomPanel = nil
actionBalance = nil

local actionConfig, hotkeyAssignWindow
local actionButtonsInPanel = 20
local extraAction = {
	"pokedex",
	"fishing",
	"autoloot",
	"order"
}

ActionTypes = {
	EQUIP = 5,
	USE_POKEMON = 4,
	USE_WITH = 3,
	USE_TARGET = 2,
	USE_SELF = 1,
	USE = 0
}
ActionColors = {
	itemUseTarget = "#FF000088",
	text = "#00000033",
	itemUseSelf = "#00FF0088",
	itemUseWith = "#F5B32588",
	itemUse = "#8888FF88",
	itemUsePokemon = "#00FFD4",
	empty = "#00000033",
	itemEquip = "#FFFFFF88"
}

function translateHotkeyDesc(text)
	if not text then
		return ""
	end

	local values = {
		{
			"Shift",
			"S"
		},
		{
			"Ctrl",
			"C"
		},
		{
			"PageUp",
			"PgUp"
		},
		{
			"PageDown",
			"PgDown"
		},
		{
			"Enter",
			"Return"
		},
		{
			"Insert",
			"Ins"
		},
		{
			"Delete",
			"Del"
		},
		{
			"Escape",
			"Esc"
		},
		{
			"Alt",
			"A"
		}
	}

	if type(text) == "string" then
		for i, v in pairs(values) do
			text = text:gsub(v[1], v[2])
		end

		if text:len() >= 6 then
			text = text:sub(text:len() - 3, text:len())
			text = "..." .. text
		end
	end

	return text
end

function init()
  g_ui.importStyle("actionbar")

  actionBottomPanel = g_ui.createWidget("ActionBottomPanel", modules.game_interface.getRootPanel())
  actionPanel1 = g_ui.createWidget("ActionBarPanel", actionBottomPanel)

	actionPanel1:setId("actionPanel1")
	actionPanel1:addAnchor(AnchorRight, "parent", AnchorRight)
	actionPanel1:addAnchor(AnchorLeft, "order", AnchorRight)
	actionPanel1:addAnchor(AnchorBottom, "fishing", AnchorBottom)

	mouseGrabberWidget = g_ui.createWidget("UIWidget")

	mouseGrabberWidget:setVisible(false)
	mouseGrabberWidget:setFocusable(false)

  mouseGrabberWidget.onMouseRelease = onChooseItemMouseRelease
  actionConfig = g_configs.create("/u_actionbar.otml")

  -- apply persisted state even when offline
  local initialState = g_settings.getBoolean("actionBar1", false)
  actionBottomPanel:setOn(initialState)
  actionPanel1.arrow:setOn(initialState)

  -- ensure centered layout and width respects side panels
  updateActionbarWidth()

  connect(g_game, {
    onGameStart = online,
    onGameEnd = offline
  })
	connect(LocalPlayer, {
		onExtraSkillChange = onExtraSkillChange
	})

  if g_game.isOnline() then
    online()
  end

  -- toggle bottom panel by arrow button regardless of online state
  function actionPanel1.arrow.onClick()
    local newState = not actionBottomPanel:isOn()
    actionBottomPanel:setOn(newState)
    actionPanel1.arrow:setOn(newState)
    g_settings.set("actionBar1", newState)
    updateActionbarWidth()
  end
end

function terminate()
	disconnect(g_game, {
		onGameStart = online,
		onGameEnd = offline
	})
	disconnect(LocalPlayer, {
		onExtraSkillChange = onExtraSkillChange
	})

	if actionPanel1.tabBar:getChildCount() > 0 then
		offline()
	end

	actionPanel1:destroy()
	mouseGrabberWidget:destroy()
end

function show()
	if not g_game.isOnline() then
		return
	end

	local state = g_settings.getBoolean("actionBar1", false)

	actionPanel1:setOn(true)
	actionBottomPanel:setOn(state)
	actionPanel1.arrow:setOn(state)
end

function hide()
	actionPanel1:setOn(false)
end

function switchMode(newMode)
  if newMode then
    local rootPanel = modules.game_interface.getRootPanel()

    actionBottomPanel:setParent(rootPanel)
    actionBottomPanel:addAnchor(AnchorBottom, "gameBottomPanel", AnchorBottom)
    actionBottomPanel:addAnchor(AnchorHorizontalCenter, "parent", AnchorHorizontalCenter)
    updateActionbarWidth()
  else
    local bottomPanel = modules.game_console.consolePanel

    actionBottomPanel:addAnchor(AnchorBottom, bottomPanel:getId(), AnchorTop)
  end
end

-- Center and clamp the actionbar width to avoid overlapping side menus
function updateActionbarWidth()
  if not actionBottomPanel then return end
  local root = modules.game_interface.getRootPanel()
  if not root then return end

  local leftPanel = root:getChildById('gameLeftPanel')
  local rightPanel = root:getChildById('gameRightPanel')

  local gap = 8
  local leftWidth = leftPanel and leftPanel:getWidth() or 0
  local rightWidth = rightPanel and rightPanel:getWidth() or 0

  local maxAllowed = math.max(0, root:getWidth() - leftWidth - rightWidth - (gap * 2))
  local desired = g_settings.getNumber('actionBarWidth', 920)
  local width = math.max(420, math.min(desired, maxAllowed))

  actionBottomPanel:setWidth(width)
  actionBottomPanel:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
end

function online()
	setupActionPanel(1, actionPanel1)
	setupExtraAction()
	show()
end

function offline()
	hide()

	if hotkeyAssignWindow then
		hotkeyAssignWindow:destroy()

		hotkeyAssignWindow = nil
	end

	local gameRootPanel = modules.game_interface.getRootPanel()

	for index, panel in ipairs({
		actionPanel1
	}) do
		local config = {}

		for i, child in ipairs(panel.tabBar:getChildren()) do
			if child.config then
				table.insert(config, child.config)

				if type(child.config.hotkey) == "string" and child.config.hotkey:len() > 0 then
					g_keyboard.unbindHotkeyPress(child.config.hotkey, child.callback, gameRootPanel)
				end
			else
				table.insert(config, {})
			end

			if child.cooldownEvent then
				removeEvent(child.cooldownEvent)
			end
		end

		actionConfig:setNode("actions_" .. index, config)
		panel.tabBar:destroyChildren()
	end

	actionConfig:save()
end

function onExtraSkillChange(player, id, params)
	if id == Skill.AutoLoot then
		player:setEnableAutoLoot(params)

		if player:isPremium() then
			actionBottomPanel.autoloot.button:setOn(params)
			actionBottomPanel.autoloot.button:setTooltip(tr("Auto-loot %s", player:isEnabledAutoLoot() and "{#4bdf8f|ON}" or "{#df4b4b|OFF}"))
		else
			actionBottomPanel.autoloot.button:setOn(false)
			actionBottomPanel.autoloot.button:setTooltip(tr("Auto-loot"))
		end
	end
end

function setupExtraAction()
	local inventoryHotkeys = modules.game_inventory.getInventoryHotkeys()

	for i, name in pairs(extraAction) do
		actionBottomPanel[name].hotkeyLabel:setText(translateHotkeyDesc(inventoryHotkeys[name].keyCombo))

		actionBottomPanel[name].button.onClick = inventoryHotkeys[name].callback
		actionBottomPanel[name].onMouseRelease = extraActionOnMouseRelease
		actionBottomPanel[name].onTouchRelease = extraActionOnMouseRelease
	end
end

function setupActionPanel(index, panel)
	local rawConfig = actionConfig:getNode("actions_" .. index) or {}
	local config = {}

	for i, buttonConfig in pairs(rawConfig) do
		config[tonumber(i)] = buttonConfig
	end

	for i = 1, actionButtonsInPanel do
		local action = g_ui.createWidget("ActionButton", panel.tabBar)

		action.config = config[i] or {}

		setupAction(action)
	end

	function panel.nextButton.onClick()
		panel.tabBar:moveChildToIndex(panel.tabBar:getFirstChild(), panel.tabBar:getChildCount())
	end

	function panel.prevButton.onClick()
		panel.tabBar:moveChildToIndex(panel.tabBar:getLastChild(), 1)
	end
end

function setupAction(action)
  local config = action.config

	action.item:setShowCount(false)

	action.onMouseRelease = actionOnMouseRelease
	action.onTouchRelease = actionOnMouseRelease

	function action.callback(k, c, ticks)
		executeAction(action, ticks)
	end

	action.item.onItemChange = nil

	if config then
		if type(config.text) == "number" then
			config.text = tostring(config.text)
		end

		if type(config.hotkey) == "number" then
			config.hotkey = tostring(config.hotkey)
		end

		if type(config.hotkey) == "string" and config.hotkey:len() > 0 then
			local gameRootPanel = modules.game_interface.getRootPanel()

			action.hotkeyLabel:setText(translateHotkeyDesc(config.hotkey))
			g_keyboard.bindHotkeyPress(config.hotkey, action.callback, gameRootPanel, "Action Bar")
		else
			action.hotkeyLabel:setText("")
		end

		action.text:setImageSource("")

		action.cooldownTill = 0
		action.cooldownStart = 0

		if type(config.text) == "string" and config.text:len() > 0 then
			action.text:setText(config.text)
			action.item:setBorderColor(ActionColors.text)
			action.item:setOn(true)
			action.item:setItemId(0)

			if Spells then
				local spell, profile = Spells.getSpellByWords(config.text:lower())

				action.spell = spell

				if action.spell and action.spell.icon and profile then
					action.text:setImageSource(SpelllistSettings[profile].iconFile)
					action.text:setImageClip(Spells.getImageClip(SpellIcons[action.spell.icon][1], profile))
					action.text:setText("")
				end
			end
		else
			action.text:setText("")

			action.spell = nil

			if type(config.item) == "number" and config.item > 100 then
				action.item:setOn(true)
				action.item:setItemId(config.item)
				action.item:setItemCount(config.count or 1)
				setupActionType(action, config.actionType)
			else
				action.item:setItemId(0)
				action.item:setOn(false)
				action.item:setBorderColor(ActionColors.empty)
			end
		end
	end

  action.item.onItemChange = actionOnItemChange

  -- Ensure proper cleanup to avoid leftover references warnings
  function action.onDestroy(widget)
    -- Unbind hotkey if still bound
    local cfg = widget.config
    if cfg and type(cfg.hotkey) == "string" and cfg.hotkey:len() > 0 then
      local gameRootPanel = modules.game_interface.getRootPanel()
      pcall(function()
        g_keyboard.unbindHotkeyPress(cfg.hotkey, widget.callback, gameRootPanel)
      end)
    end

    -- Cancel cooldown update event
    if widget.cooldownEvent then
      removeEvent(widget.cooldownEvent)
      widget.cooldownEvent = nil
    end

    -- Clear item change handler and other callbacks
    if widget.item then
      widget.item.onItemChange = nil
    end
    widget.onMouseRelease = nil
    widget.onTouchRelease = nil
    widget.callback = nil

    -- Drop strong references to children
    widget.text = nil
    widget.hotkeyLabel = nil
    widget.cooldown = nil
  end
end

function setupActionType(action, actionType)
	local item = action.item:getItem()

	if action.item:getItem():isMultiUse() then
		if not actionType or actionType <= ActionTypes.USE then
			actionType = ActionTypes.USE_WITH
		end
	elseif g_game.getClientVersion() >= 910 then
		if actionType ~= ActionTypes.USE and actionType ~= ActionTypes.EQUIP then
			actionType = ActionTypes.USE
		end
	else
		actionType = ActionTypes.USE
	end

	action.config.actionType = actionType

	if action.config.actionType == ActionTypes.USE then
		action.item:setBorderColor(ActionColors.itemUse)
	elseif action.config.actionType == ActionTypes.USE_SELF then
		action.item:setBorderColor(ActionColors.itemUseSelf)
	elseif action.config.actionType == ActionTypes.USE_TARGET then
		action.item:setBorderColor(ActionColors.itemUseTarget)
	elseif action.config.actionType == ActionTypes.USE_WITH then
		action.item:setBorderColor(ActionColors.itemUseWith)
	elseif action.config.actionType == ActionTypes.USE_POKEMON then
		action.item:setBorderColor(ActionColors.itemUsePokemon)
	elseif action.config.actionType == ActionTypes.EQUIP then
		action.item:setBorderColor(ActionColors.itemEquip)
	end
end

function updateAction(action, newConfig)
	local config = action.config

	if type(config.hotkey) == "string" and config.hotkey:len() > 0 then
		local gameRootPanel = modules.game_interface.getRootPanel()

		g_keyboard.unbindHotkeyPress(config.hotkey, action.callback, gameRootPanel)
	end

	for key, val in pairs(newConfig) do
		action.config[key] = val
	end

	setupAction(action)
end

function actionOnMouseRelease(action, mousePosition, mouseButton)
	if mouseButton == MouseTouch then
		return
	end

	if mouseButton == MouseRightButton or not action.item:isOn() then
		local menu = g_ui.createWidget("PopupMenu")

		menu:setGameMenu(true)

		if action.item:getItemId() > 0 then
			if action.item:getItem():isMultiUse() then
				menu:addOption(tr("Use on yourself"), function()
					return setupActionType(action, ActionTypes.USE_SELF)
				end)
				menu:addOption(tr("Use on target"), function()
					return setupActionType(action, ActionTypes.USE_TARGET)
				end)
				menu:addOption(tr("Use on pokemon"), function()
					return setupActionType(action, ActionTypes.USE_POKEMON)
				end)
				menu:addOption(tr("With crosshair"), function()
					return setupActionType(action, ActionTypes.USE_WITH)
				end)
			end

			if g_game.getClientVersion() >= 910 then
				if not action.item:getItem():isMultiUse() then
					menu:addOption(tr("Use"), function()
						return setupActionType(action, ActionTypes.USE)
					end)
				end

				menu:addOption(tr("Equip"), function()
					return setupActionType(action, ActionTypes.EQUIP)
				end)
			end
		else
			menu:addOption(tr("Select object"), function()
				return startChooseItem(action.item)
			end)
		end

		menu:addSeparator()

		local player = g_game.getLocalPlayer()

		if player then
			menu:addOption(tr("Set text"), function()
				modules.client_textedit.singlelineEditor(action.config.text or "", function(newText)
					updateAction(action, {
						item = 0,
						text = newText
					})
				end)
			end)
		end

		menu:addOption(tr("Set hotkey"), function()
			showSetupHotkey(function(hotkey)
				updateAction(action, {
					hotkey = hotkey
				})
			end)
		end)
		menu:addSeparator()
		menu:addOption(tr("Clear"), function()
			updateAction(action, {
				text = "",
				hotkey = "",
				item = 0,
				count = 1
			})
		end)
		menu:display(mousePosition)

		return true
	elseif mouseButton == MouseLeftButton or mouseButton == MouseTouch2 or mouseButton == MouseTouch3 then
		action.callback()

		return true
	end

	return false
end

function actionOnItemChange(widget)
	updateAction(widget:getParent(), {
		text = "",
		item = widget:getItemId(),
		count = widget:getItemCountOrSubType()
	})
end

function startCooldown(action, duration)
	if type(action.cooldownTill) == "number" and action.cooldownTill > g_clock.millis() + duration then
		return
	end

	action.cooldownStart = g_clock.millis()
	action.cooldownTill = g_clock.millis() + duration

	updateCooldown(action)
end

function updateCooldown(action)
	if not action or not action.cooldownTill then
		return
	end

	local timeleft = action.cooldownTill - g_clock.millis()

	if timeleft <= 30 then
		action.cooldown:setPercent(100)

		action.cooldownEvent = nil

		action.cooldown:setText("")

		return
	end

	local duration = action.cooldownTill - action.cooldownStart
	local formattedText

	if timeleft > 60000 then
		formattedText = math.floor(timeleft / 60000) .. "m"
	else
		formattedText = timeleft / 1000
		formattedText = math.floor(formattedText * 10) / 10
		formattedText = math.floor(formattedText) .. "." .. math.floor(formattedText * 10) % 10
	end

	action.cooldown:setText(formattedText)
	action.cooldown:setPercent(100 - math.floor(100 * timeleft / duration))

	action.cooldownEvent = scheduleEvent(function()
		updateCooldown(action)
	end, 30)
end

function executeAction(action, ticks)
	if not action.config or modules.game_console.isChatEnabled() and not g_keyboard.isSkipKey(action.config.hotkey) then
		return
	end

	if type(ticks) ~= "number" then
		ticks = 0
	end

	local actionDelay = 500

	if ticks == 0 then
		actionDelay = 500
	elseif action.actionDelayTo ~= nil and g_clock.millis() < action.actionDelayTo then
		return
	end

	local actionType = action.config.actionType

	if type(action.config.text) == "string" and action.config.text:len() > 0 then
		if g_platform.isMobile() then
			local target = g_game.getAttackingCreature()

			if target then
				local pos = g_game.getLocalPlayer():getPosition()
				local tpos = target:getPosition()

				if pos and tpos then
					local offx = tpos.x - pos.x
					local offy = tpos.y - pos.y

					if offy < 0 and offx <= 0 and math.abs(offx) < math.abs(offy) then
						g_game.turn(Directions.North)
					elseif offy > 0 and offx >= 0 and math.abs(offx) < math.abs(offy) then
						g_game.turn(Directions.South)
					elseif offx < 0 and offy <= 0 and math.abs(offx) > math.abs(offy) then
						g_game.turn(Directions.West)
					elseif offx > 0 and offy >= 0 and math.abs(offx) > math.abs(offy) then
						g_game.turn(Directions.East)
					end
				end
			end
		end

		if modules.game_interface.isChatVisible() then
			modules.game_console.sendMessage(action.config.text)
		else
			g_game.talk(action.config.text)
		end

		action.actionDelayTo = g_clock.millis() + actionDelay
	elseif action.item:getItemId() > 0 then
		if actionType == ActionTypes.USE then
			if g_game.getClientVersion() < 780 then
				local item = g_game.findPlayerItem(action.item:getItemId(), action.item:getItemSubType() or -1)

				if item then
					if item:canConfirmUse() then
						modules.game_interface.displayItemUseConfirmationWindow(item, tr("You really want to use this item?"), "useItem")
					else
						g_game.use(item)
					end
				end
			elseif action.item:getItem():canConfirmUse() then
				modules.game_interface.displayItemUseConfirmationWindow(action.item:getItem(), tr("You really want to use this item?"), "useItem", function(item)
					g_game.useInventoryItem(item:getItemId())
				end)
			else
				g_game.useInventoryItem(action.item:getItemId())
			end

			action.actionDelayTo = g_clock.millis() + actionDelay
		elseif actionType == ActionTypes.USE_SELF then
			if g_game.getClientVersion() < 780 then
				local item = g_game.findPlayerItem(action.item:getItemId(), action.item:getItemSubType() or -1)

				if item then
					g_game.useWith(item, g_game.getLocalPlayer())
				end
			else
				g_game.useInventoryItemWith(action.item:getItemId(), g_game.getLocalPlayer(), action.item:getItemSubType() or -1)
			end

			action.actionDelayTo = g_clock.millis() + actionDelay
		elseif actionType == ActionTypes.USE_TARGET then
			local attackingCreature = g_game.getAttackingCreature()

			if not attackingCreature then
				local item = Item.create(action.item:getItemId())

				if g_game.getClientVersion() < 780 then
					local tmpItem = g_game.findPlayerItem(action.item:getItemId(), action.item:getItemSubType() or -1)

					if not tmpItem then
						return
					end

					item = tmpItem
				end

				modules.game_interface.startUseWith(item, action.item:getItemSubType() or -1)

				return
			end

			if not attackingCreature:getTile() then
				return
			end

			if g_game.getClientVersion() < 780 then
				local item = g_game.findPlayerItem(action.item:getItemId(), action.item:getItemSubType() or -1)

				if item then
					g_game.useWith(item, attackingCreature, action.item:getItemSubType() or -1)
				end
			else
				g_game.useInventoryItemWith(action.item:getItemId(), attackingCreature, action.item:getItemSubType() or -1)
			end

			action.actionDelayTo = g_clock.millis() + actionDelay
		elseif actionType == ActionTypes.USE_POKEMON then
			if g_game.getProtocolVersion() < 780 then
				local item = g_game.findPlayerItem(action.item:getItemId(), action.item:getItemSubType() or -1)

				if item then
					local pos = g_game.getLocalPlayer():getPosition()

					if pos then
						for i, creature in ipairs(g_map.getSpectators(pos, false)) do
							if creature:isSummon() then
								g_game.useWith(item, creature)
							end
						end
					end
				end
			else
				local pos = g_game.getLocalPlayer():getPosition()

				if pos then
					for i, creature in ipairs(g_map.getSpectators(pos, false)) do
						if creature:isSummon() then
							g_game.useInventoryItemWith(action.item:getItemId(), creature, action.item:getItemSubType() or -1)
						end
					end
				end
			end

			action.actionDelayTo = g_clock.millis() + actionDelay
		elseif actionType == ActionTypes.USE_WITH then
			local item = Item.create(action.item:getItemId())

			if g_game.getClientVersion() < 780 then
				local tmpItem = g_game.findPlayerItem(action.item:getItemId(), action.item:getItemSubType() or -1)

				if not tmpItem then
					return true
				end

				item = tmpItem
			end

			modules.game_interface.startUseWith(item, action.item:getItemSubType() or -1)
		elseif actionType == ActionTypes.EQUIP and g_game.getClientVersion() >= 910 then
			local item = Item.create(action.item:getItemId())

			g_game.equipItem(item)

			action.actionDelayTo = g_clock.millis() + actionDelay
		end
	end
end

function startChooseItem(itemWidget)
	if g_ui.isMouseGrabbed() then
		return
	end

	mouseGrabberWidget:grabMouse()
	g_mouse.pushCursor("target")

	mouseGrabberWidget.item = itemWidget
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

					if thing and thing:isItem() and thing:isPickupable() then
						item = thing
					end
				end
			elseif clickedWidget:getClassName() == "UIItem" and not clickedWidget:isVirtual() then
				item = clickedWidget:getItem()
			end
		end
	end

	if item then
		mouseGrabberWidget.item:setItem(item)
	end

	g_mouse.popCursor("target")
	self:ungrabMouse()

	return true
end

function showSetupHotkey(callback)
	if hotkeyAssignWindow then
		hotkeyAssignWindow:destroy()
	end

	local assignWindow = g_ui.createWidget("ActionAssignWindow", rootWidget)

	assignWindow:onVisibilityChange(true)
	assignWindow:grabKeyboard()

	assignWindow.comboPreview.keyCombo = ""

	function assignWindow.onKeyDown(assignWindow, keyCode, keyboardModifiers)
		local keyCombo = determineKeyComboDesc(keyCode, keyboardModifiers)
		local hotkeyType = g_keyboard.getHotkeyType(keyCombo) or modules.game_hotkeys.boundCombosCallback[keyCombo] and tr("Hotkeys")
		local hasKey, msg = KeybindManager:validate("", "", keyCombo)
		local desc = msg and "options hotkeys" or hotkeyType

		assignWindow.comboPreview:setText(tr("Current action hotkey: %s", keyCombo))

		assignWindow.comboPreview.keyCombo = keyCombo

		assignWindow.comboPreview:resizeToText()
		assignWindow.usingHotkey:setVisible(hotkeyType or msg)
		assignWindow.addButton:setEnabled(not hotkeyType and not msg)
		assignWindow.usingHotkey:setText(tr("This hotkey is being used in %s", tr(desc or "")))

		return true
	end

	function assignWindow.onMouseRelease(assignWindow, mousePos, mouseButton)
		local keyboardModifiers = g_keyboard.getModifiers()
		local keyCombo = determineMouseKeyComboDesc(mouseButton, keyboardModifiers)
		local comboPreview = assignWindow:getChildById("comboPreview")
		local hotkeyType = g_keyboard.getHotkeyType(keyCombo) or modules.game_hotkeys.boundCombosCallback[keyCombo] and tr("Hotkeys")
		local hasKey, msg = KeybindManager:validate("", "", keyCombo)
		local desc = msg and "options hotkeys" or hotkeyType

		comboPreview:setText(tr("Current hotkey to add: %s", keyCombo))

		comboPreview.keyCombo = keyCombo

		comboPreview:resizeToText()
		assignWindow.usingHotkey:setVisible(hotkeyType or msg)
		assignWindow.addButton:setEnabled(not hotkeyType and not msg)
		assignWindow.usingHotkey:setText(tr("This hotkey is being used in %s", tr(desc or "")))

		return true
	end

	function assignWindow.onDestroy(widget)
		if widget == hotkeyAssignWindow then
			hotkeyAssignWindow = nil
		end
	end

	function assignWindow.addButton.onClick()
		local text = tostring(assignWindow.comboPreview.keyCombo)

		callback(text)
		assignWindow:destroy()
	end

	hotkeyAssignWindow = assignWindow
end

function extraActionOnMouseRelease(widget, mousePosition, mouseButton)
	if mouseButton == MouseTouch then
		return
	end

	if mouseButton == MouseRightButton then
		local menu = g_ui.createWidget("PopupMenu")

		menu:setGameMenu(true)
		menu:addOption(tr("Set hotkey"), function()
			modules.game_actionbar.showSetupHotkey(function(hotkey)
				modules.game_inventory.updateInventoryHotkey(widget:getId(), hotkey)
				widget.hotkeyLabel:setText(translateHotkeyDesc(hotkey))
			end)
		end)
		menu:display(mousePosition)

		return true
	end

	return false
end
