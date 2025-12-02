-- chunkname: @/modules/game_textmessage/textmessage.lua

MessageSettings = {
	none = {},
	consoleRed = {
		consoleTab = "Default",
		color = TextColors.red
	},
	consoleOrange = {
		consoleTab = "Default",
		color = TextColors.orange
	},
	consoleBlue = {
		consoleTab = "Default",
		color = TextColors.blue
	},
	centerRed = {
		screenTarget = "lowCenterLabel",
		consoleTab = "Server Log",
		color = TextColors.red
	},
	centerGreen = {
		screenTarget = "highCenterLabel",
		consoleOption = "showInfoMessagesInConsole",
		consoleTab = "Server Log",
		color = TextColors.green
	},
	centerWhite = {
		screenTarget = "middleCenterLabel",
		consoleOption = "showEventMessagesInConsole",
		consoleTab = "Server Log",
		color = TextColors.white
	},
	bottomWhite = {
		screenTarget = "statusLabel",
		consoleOption = "showEventMessagesInConsole",
		consoleTab = "Server Log",
		color = TextColors.white
	},
	status = {
		screenTarget = "statusLabel",
		consoleOption = "showStatusMessagesInConsole",
		consoleTab = "Server Log",
		color = TextColors.white
	},
	statusSmall = {
		screenTarget = "statusLabel",
		color = TextColors.white
	},
	private = {
		screenTarget = "privateLabel",
		color = TextColors.lightblue
	}
}
MessageTypes = {
	[MessageModes.MonsterSay] = MessageSettings.consoleOrange,
	[MessageModes.MonsterYell] = MessageSettings.consoleOrange,
	[MessageModes.BarkLow] = MessageSettings.consoleOrange,
	[MessageModes.BarkLoud] = MessageSettings.consoleOrange,
	[MessageModes.Failure] = MessageSettings.statusSmall,
	[MessageModes.Login] = MessageSettings.bottomWhite,
	[MessageModes.Game] = MessageSettings.centerWhite,
	[MessageModes.Status] = MessageSettings.status,
	[MessageModes.Warning] = MessageSettings.centerRed,
	[MessageModes.Look] = MessageSettings.centerGreen,
	[MessageModes.Loot] = MessageSettings.centerGreen,
	[MessageModes.Red] = MessageSettings.consoleRed,
	[MessageModes.Blue] = MessageSettings.consoleBlue,
	[MessageModes.PrivateFrom] = MessageSettings.consoleBlue,
	[MessageModes.GamemasterBroadcast] = MessageSettings.consoleRed,
	[MessageModes.DamageDealed] = MessageSettings.status,
	[MessageModes.DamageReceived] = MessageSettings.status,
	[MessageModes.Heal] = MessageSettings.status,
	[MessageModes.Exp] = MessageSettings.status,
	[MessageModes.DamageOthers] = MessageSettings.none,
	[MessageModes.HealOthers] = MessageSettings.none,
	[MessageModes.ExpOthers] = MessageSettings.none,
	[MessageModes.TradeNpc] = MessageSettings.centerWhite,
	[MessageModes.Guild] = MessageSettings.centerWhite,
	[MessageModes.Party] = MessageSettings.centerGreen,
	[MessageModes.PartyManagement] = MessageSettings.centerWhite,
	[MessageModes.TutorialHint] = MessageSettings.centerWhite,
	[MessageModes.BeyondLast] = MessageSettings.centerWhite,
	[MessageModes.Report] = MessageSettings.consoleRed,
	[MessageModes.HotkeyUse] = MessageSettings.centerGreen,
	[MessageModes.BoostedCreature] = MessageSettings.centerWhite,
	[254] = MessageSettings.private
}
messagesPanel = nil

function init()
	for messageMode, _ in pairs(MessageTypes) do
		registerMessageMode(messageMode, displayMessage)
	end

	connect(g_game, "onGameEnd", clearMessages)

	messagesPanel = g_ui.loadUI("textmessage", modules.game_interface.getRootPanel())
end

function terminate()
	for messageMode, _ in pairs(MessageTypes) do
		unregisterMessageMode(messageMode, displayMessage)
	end

	disconnect(g_game, "onGameEnd", clearMessages)
	clearMessages()
	messagesPanel:destroy()
end

function calculateVisibleTime(text)
	return math.max(#text * 50, 3000)
end

function displayMessage(mode, text)
	if not g_game.isOnline() then
		return
	end

local msgtype = MessageTypes[mode]

	if not msgtype then
		return
	end

	if msgtype == MessageSettings.none then
		return
	end

	if msgtype.consoleTab ~= nil and (msgtype.consoleOption == nil or modules.client_options.getOption(msgtype.consoleOption)) then
	--	modules.game_console.addText(text, msgtype, tr(msgtype.consoleTab))
	end

  if msgtype.screenTarget and mode ~= MessageModes.Failure then
    local label = messagesPanel:recursiveGetChildById(msgtype.screenTarget)
    label:setMarginBottom(2)
    label:setMultiColorText(text, msgtype.color)
    label:setColor(msgtype.color)
    label:setVisible(true)
    removeEvent(label.hideEvent)
    label.hideEvent = scheduleEvent(function()
      label:setVisible(false)
    end, calculateVisibleTime(text))
  elseif mode == MessageModes.Failure then
    -- Mostrar como "bolha" com barra de progresso (cooldown)
    local bubble = messagesPanel:recursiveGetChildById('statusBubble')
    local bar = bubble and bubble:getChildById('cooldownBar') or nil
    local txt = bubble and bubble:getChildById('bubbleText') or nil
    if not bubble or not bar or not txt then return end

    txt:setText(text)
    txt:setColor(msgtype.color or TextColors.white)
    bubble:setVisible(true)
    bubble:raise()

    local duration = calculateVisibleTime(text)
    if bar.setPercent then bar:setPercent(100) end
    removeEvent(bubble._progressEvent)
    bubble._remainingMs = duration
    local interval = 50
    bubble._progressEvent = cycleEvent(function()
      if not bubble or bubble:isDestroyed() then return end
      bubble._remainingMs = math.max(0, bubble._remainingMs - interval)
      if bar and bar.setPercent then
        local p = math.floor((bubble._remainingMs / duration) * 100)
        bar:setPercent(p)
      end
      if bubble._remainingMs <= 0 then
        removeEvent(bubble._progressEvent)
        bubble._progressEvent = nil
        bubble:setVisible(false)
      end
    end, interval)
    bubble.onDestroy = function()
      if bubble and bubble._progressEvent then
        removeEvent(bubble._progressEvent)
        bubble._progressEvent = nil
      end
    end
  end
end

function displayPrivateMessage(text)
	displayMessage(254, text)
end

function displayStatusMessage(text)
	displayMessage(MessageModes.Status, text)
end

function displayFailureMessage(text)
	displayMessage(MessageModes.Failure, text)
end

function displayGameMessage(text)
	displayMessage(MessageModes.Game, text)
end

function displayBroadcastMessage(text)
	displayMessage(MessageModes.Warning, text)
end

function clearMessages()
	for _i, child in pairs(messagesPanel:recursiveGetChildren()) do
		if child:getId():match("Label") then
			child:hide()
			removeEvent(child.hideEvent)
		end
	end
end

function LocalPlayer:onAutoWalkFail(player)
	modules.game_textmessage.displayFailureMessage(tr("There is no way."))
end
