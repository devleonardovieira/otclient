-- chunkname: @/modules/game_console/console.lua

SpeakTypesSettings = {
	none = {},
	say = {
		color = "#FFFF00",
		speakType = MessageModes.Say
	},
	whisper = {
		color = "#FFFF00",
		speakType = MessageModes.Whisper
	},
	yell = {
		color = "#FFFF00",
		speakType = MessageModes.Yell
	},
	broadcast = {
		color = "#F55E5E",
		speakType = MessageModes.GamemasterBroadcast
	},
	private = {
		color = "#5FF7F7",
		private = true,
		speakType = MessageModes.PrivateTo
	},
	privateRed = {
		color = "#F55E5E",
		private = true,
		speakType = MessageModes.GamemasterTo
	},
	privatePlayerToPlayer = {
		color = "#9F9DFD",
		private = true,
		speakType = MessageModes.PrivateTo
	},
	privatePlayerToNpc = {
		color = "#9F9DFD",
		npcChat = true,
		private = true,
		speakType = MessageModes.NpcTo
	},
	privateNpcToPlayer = {
		color = "#5FF7F7",
		npcChat = true,
		private = true,
		speakType = MessageModes.NpcFrom
	},
	channelYellow = {
		color = "#FFFF00",
		speakType = MessageModes.Channel
	},
	channelWhite = {
		color = "#FFFFFF",
		speakType = MessageModes.ChannelManagement
	},
	channelRed = {
		color = "#F55E5E",
		speakType = MessageModes.GamemasterChannel
	},
	channelOrange = {
		color = "#F6A731",
		speakType = MessageModes.ChannelHighlight
	},
	monsterSay = {
		color = "#FE6500",
		hideInConsole = true,
		speakType = MessageModes.MonsterSay
	},
	monsterYell = {
		color = "#FE6500",
		hideInConsole = true,
		speakType = MessageModes.MonsterYell
	},
	rvrAnswerFrom = {
		color = "#FE6500",
		speakType = MessageModes.RVRAnswer
	},
	rvrAnswerTo = {
		color = "#FE6500",
		speakType = MessageModes.RVRAnswer
	},
	rvrContinue = {
		color = "#FFFF00",
		speakType = MessageModes.RVRContinue
	}
}
SpeakTypes = {
	[MessageModes.Say] = SpeakTypesSettings.say,
	[MessageModes.Whisper] = SpeakTypesSettings.whisper,
	[MessageModes.Yell] = SpeakTypesSettings.yell,
	[MessageModes.GamemasterBroadcast] = SpeakTypesSettings.broadcast,
	[MessageModes.PrivateFrom] = SpeakTypesSettings.private,
	[MessageModes.GamemasterPrivateFrom] = SpeakTypesSettings.privateRed,
	[MessageModes.NpcTo] = SpeakTypesSettings.privatePlayerToNpc,
	[MessageModes.NpcFrom] = SpeakTypesSettings.privateNpcToPlayer,
	[MessageModes.Channel] = SpeakTypesSettings.channelYellow,
	[MessageModes.ChannelManagement] = SpeakTypesSettings.channelWhite,
	[MessageModes.GamemasterChannel] = SpeakTypesSettings.channelRed,
	[MessageModes.ChannelHighlight] = SpeakTypesSettings.channelOrange,
	[MessageModes.MonsterSay] = SpeakTypesSettings.monsterSay,
	[MessageModes.MonsterYell] = SpeakTypesSettings.monsterYell,
	[MessageModes.RVRChannel] = SpeakTypesSettings.channelWhite,
	[MessageModes.RVRContinue] = SpeakTypesSettings.rvrContinue,
	[MessageModes.RVRAnswer] = SpeakTypesSettings.rvrAnswerFrom,
	[MessageModes.NpcFromStartBlock] = SpeakTypesSettings.privateNpcToPlayer,
	[MessageModes.Spell] = SpeakTypesSettings.none,
	[MessageModes.BarkLow] = SpeakTypesSettings.none,
	[MessageModes.BarkLoud] = SpeakTypesSettings.none
}
SayModes = {
	{
		icon = "/images/game/console/whisper",
		speakTypeDesc = "whisper"
	},
	{
		icon = "/images/game/console/say",
		speakTypeDesc = "say"
	},
	{
		icon = "/images/game/console/yell",
		speakTypeDesc = "yell"
	}
}
ChannelEventFormats = {
	[ChannelEvent.Join] = "%s joined the channel.",
	[ChannelEvent.Leave] = "%s left the channel.",
	[ChannelEvent.Invite] = "%s has been invited to the channel.",
	[ChannelEvent.Exclude] = "%s has been removed from the channel."
}
MAX_HISTORY = 500
MAX_LINES = 100
HELP_CHANNEL = 9
MAX_LINES_CONSOLE_PHANTOM = 7
TIME_FADE_CONSOLE_PHANTOM = 2200
consolePanel = nil
consoleContentPanel = nil
consoleTabBar = nil
consoleTextEdit = nil
consoleToggleChat = nil
channels = nil
channelsWindow = nil
communicationWindow = nil
ownPrivateName = nil
messageHistory = {}
currentMessageIndex = 0
ignoreNpcMessages = false
defaultTab = nil
serverTab = nil
violationsChannelId = nil
violationWindow = nil
violationReportTab = nil
ignoredChannels = {}
filters = {}
floatingMode = false

local communicationSettings = {
	yelling = false,
	privateMessages = false,
	useWhiteList = true,
	useIgnoreList = true,
	allowVIPs = false,
	ignoredPlayers = {},
	whitelistedPlayers = {}
}

function init()
	connect(g_game, {
		onTalk = onTalk,
		onChannelList = onChannelList,
		onOpenChannel = onOpenChannel,
		onCloseChannel = onCloseChannel,
		onChannelEvent = onChannelEvent,
		onOpenPrivateChannel = onOpenPrivateChannel,
		onOpenOwnPrivateChannel = onOpenOwnPrivateChannel,
		onRuleViolationChannel = onRuleViolationChannel,
		onRuleViolationRemove = onRuleViolationRemove,
		onRuleViolationCancel = onRuleViolationCancel,
		onRuleViolationLock = onRuleViolationLock,
		onGameStart = online,
		onGameEnd = offline
	})
	g_ui.importStyle("communicationwindow.otui")

	consolePanel = g_ui.loadUI("console", modules.game_interface.getRootPanel())
	consoleTextEdit = consolePanel:getChildById("consoleTextEdit")
	consoleContentPanel = consolePanel:getChildById("consoleContentPanel")
	consoleTabBar = consolePanel:getChildById("consoleTabBar")

	consoleTabBar:setContentWidget(consoleContentPanel)

	channels = {}
	consolePanel.onDragEnter = onDragEnter
	consolePanel.onDragLeave = onDragLeave
	consolePanel.onDragMove = onDragMove

	function consolePanel:onKeyPress(keyCode, keyboardModifiers)
		if keyboardModifiers ~= KeyboardCtrlModifier or keyCode ~= KeyC then
			return false
		end

		local tab = consoleTabBar:getCurrentTab()

		if not tab then
			return false
		end

		local selection = tab.tabPanel:getChildById("consoleBuffer").selectionText

		if not selection then
			return false
		end

		g_window.setClipboardText(selection)

		return true
	end

	g_keyboard.bindKeyPress("Shift+Up", function()
		navigateMessageHistory(1)
	end, consolePanel)
	g_keyboard.bindKeyPress("Shift+Down", function()
		navigateMessageHistory(-1)
	end, consolePanel)
	g_keyboard.bindKeyPress("Tab", function()
		consoleTabBar:selectNextTab()
	end, consolePanel)
	g_keyboard.bindKeyPress("Shift+Tab", function()
		consoleTabBar:selectPrevTab()
	end, consolePanel)
	g_keyboard.bindKeyDown("Enter", sendCurrentMessage, consolePanel)
	g_keyboard.bindKeyPress("Ctrl+A", function()
		consoleTextEdit:clearText()
	end, consolePanel)
	consoleTabBar:setNavigation(consolePanel:getChildById("prevChannelButton"), consolePanel:getChildById("nextChannelButton"))

	consoleTabBar.onTabChange = onTabChange

	local gameRootPanel = modules.game_interface.getRootPanel()

	g_keyboard.bindKeyDown("Ctrl+O", g_game.requestChannels, gameRootPanel)
	g_keyboard.bindKeyDown("Ctrl+E", removeCurrentTab, gameRootPanel)
	g_keyboard.bindKeyDown("Ctrl+H", openHelp, gameRootPanel)

	consoleToggleChat = consolePanel:getChildById("toggleChat")

	load()

	if g_game.isOnline() then
		online()
	end
end

function clearSelection(consoleBuffer)
	for _, label in pairs(consoleBuffer:getChildren()) do
		label:clearSelection()
	end

	consoleBuffer.selectionText = nil
	consoleBuffer.selection = nil
end

function addConsolePhatomLine(text, color)
	local consolePhantom = consolePanel.consolePhantom
	local childCount = consolePhantom:getChildCount()

	if childCount > MAX_LINES then
		local child = consolePhantom:getFirstChild()

		removeEvent(child.event)
		child:destroy()
	end

	local tmpLabel = g_ui.createWidget("ConsolePhantomLabel", consolePhantom)

	if type(text) == "string" and text:find("{") then
		tmpLabel:setColoredText(text)
	else
		tmpLabel:setText(text)
		if color then
			tmpLabel:setColor(color)
		end
	end

	local function destroyCallback()
		tmpLabel:destroy()
	end

	local function fadeOutCallback()
		g_effects.fadeOut(tmpLabel, 300, 0, destroyCallback)
	end

	local maxLine = childCount > MAX_LINES_CONSOLE_PHANTOM and MAX_LINES_CONSOLE_PHANTOM or childCount

	g_effects.fadeIn(tmpLabel)
	removeEvent(tmpLabel.event)

	tmpLabel.event = scheduleEvent(fadeOutCallback, TIME_FADE_CONSOLE_PHANTOM + maxLine * TIME_FADE_CONSOLE_PHANTOM)
end

function selectAll(consoleBuffer)
	clearSelection(consoleBuffer)

	if consoleBuffer:getChildCount() > 0 then
		local text = {}

		for _, label in pairs(consoleBuffer:getChildren()) do
			label:selectAll()
			table.insert(text, label:getSelection())
		end

		consoleBuffer.selectionText = table.concat(text, "\n")
		consoleBuffer.selection = {
			first = consoleBuffer:getChildIndex(consoleBuffer:getFirstChild()),
			last = consoleBuffer:getChildIndex(consoleBuffer:getLastChild())
		}
	end
end

function toggleChat()
	if consoleToggleChat:isChecked() then
		disableChat()
	else
		enableChat()
	end
end

function visibleConsolePanel(state)
	if not g_game.isOnline() then
		return
	end

	addEvent(function()
		for i, child in pairs(consolePanel:getChildren()) do
			child:setVisible(state)
		end

		consolePanel.toggleChat:show()
		consolePanel:setPhantom(not state)
		consolePanel.consolePhantom:setVisible(not state)
		getCurrentTab().tabPanel:getChildById("consoleBuffer"):setOn(state)
		getCurrentTab().tabPanel:getChildById("consoleScrollBar"):setVisible(state)
	end)
	
end

function enableChat(temporarily)
	  if g_platform.isMobile() then
		return
	end

	if consoleToggleChat:isChecked() then
		return consoleToggleChat:setChecked(false)
	end

	visibleConsolePanel(true)
	consoleTextEdit:setVisible(true)
	consoleTextEdit:setText("")
	consoleTextEdit:focus()
	consolePanel:focus()

	local gameRootPanel = modules.game_interface.getRootPanel()

	g_keyboard.unbindKeyDown("Enter", gameRootPanel)

	if temporarily then
		local function quickFunc()
			if not g_game.isOnline() then
				return
			end

			g_keyboard.unbindKeyDown("Enter", gameRootPanel)
			g_keyboard.unbindKeyDown("Escape", gameRootPanel)
			disableChat(temporarily)
		end

		g_keyboard.bindKeyDown("Enter", quickFunc, gameRootPanel)
		g_keyboard.bindKeyDown("Escape", quickFunc, gameRootPanel)
	end

	modules.game_walk.disableWSAD()
	consoleToggleChat:setTooltip(tr("Disable chat mode, allow to walk using ASDW"))
end

function disableChat(temporarily)
	  if g_platform.isMobile() then
		return
	end

	if not consoleToggleChat:isChecked() then
		return consoleToggleChat:setChecked(true)
	end

	if not temporarily then
		modules.client_options.setOption("wsadWalking", true)
	end

	consoleTextEdit:setVisible(false)
	consoleTextEdit:setText("")

	local function quickFunc()
		if not g_game.isOnline() then
			return
		end

		if consoleToggleChat:isChecked() then
			consoleToggleChat:setChecked(false)
		end

		enableChat(true)
	end

	local gameRootPanel = modules.game_interface.getRootPanel()

	g_keyboard.bindKeyDown("Enter", quickFunc, gameRootPanel)

	visibleConsolePanel(false)

	modules.game_walk.enableWSAD()
	consoleToggleChat:setTooltip(tr("Enable chat mode"))
end

function isChatEnabled()
	return consoleTextEdit:isVisible()
end

function terminate()
	save()
	disconnect(g_game, {
		onTalk = onTalk,
		onChannelList = onChannelList,
		onOpenChannel = onOpenChannel,
		onOpenPrivateChannel = onOpenPrivateChannel,
		onOpenOwnPrivateChannel = onOpenPrivateChannel,
		onCloseChannel = onCloseChannel,
		onRuleViolationChannel = onRuleViolationChannel,
		onRuleViolationRemove = onRuleViolationRemove,
		onRuleViolationCancel = onRuleViolationCancel,
		onRuleViolationLock = onRuleViolationLock,
		onGameStart = online,
		onGameEnd = offline,
		onChannelEvent = onChannelEvent
	})

	if g_game.isOnline() then
		clear()
	end

	local gameRootPanel = modules.game_interface.getRootPanel()

	g_keyboard.unbindKeyDown("Ctrl+O", gameRootPanel)
	g_keyboard.unbindKeyDown("Ctrl+E", gameRootPanel)
	g_keyboard.unbindKeyDown("Ctrl+H", gameRootPanel)
	saveCommunicationSettings()

	if channelsWindow then
		channelsWindow:destroy()
	end

	if communicationWindow then
		communicationWindow:destroy()
	end

	if violationWindow then
		violationWindow:destroy()
	end

	consoleTabBar = nil
	consoleContentPanel = nil
	consoleToggleChat = nil
	consoleTextEdit = nil

	-- destruir widgets filhos
	consolePanel:destroyChildren()
	consoleContentPanel:destroyChildren()

	consolePanel:destroy()

	consolePanel = nil
	ownPrivateName = nil
	Console = nil
end

function save()
	local settings = {}

	settings.messageHistory = messageHistory

	g_settings.setNode("game_console", settings)
end

function load()
	local settings = g_settings.getNode("game_console")

	if settings then
		messageHistory = settings.messageHistory or {}
	end

	loadCommunicationSettings()
end

function onTabChange(tabBar, tab)
	if tab == defaultTab or tab == serverTab then
		consolePanel:getChildById("closeChannelButton"):disable()
	else
		consolePanel:getChildById("closeChannelButton"):enable()
	end

	if not g_game.isOnline() then
		return
	end

	addEvent(function()
		getCurrentTab().tabPanel:getChildById("consoleBuffer"):setOn(isChatEnabled())
		getCurrentTab().tabPanel:getChildById("consoleScrollBar"):setVisible(isChatEnabled())
	end)
end

function clear()
	local lastChannelsOpen = g_settings.getNode("lastChannelsOpen") or {}
	local configChat = g_settings.getNode("configChat") or {}
	local playerName = g_game.getCharacterName()
	local savedChannels = {}
	local set = false

	for channelId, channelName in pairs(channels) do
		if type(channelId) == "number" then
			savedChannels[channelName] = channelId
			set = true
		end
	end

	if set then
		lastChannelsOpen[playerName] = savedChannels
	else
		lastChannelsOpen[playerName] = nil
	end

	configChat[playerName] = {
		savePos = pointtostring(consolePanel:getPosition()),
		saveWidth = consolePanel:getWidth(),
		saveHeight = consolePanel:getHeight(),
		toggleChat = consoleToggleChat:isChecked()
	}

	g_settings.setNode("lastChannelsOpen", lastChannelsOpen)
	g_settings.setNode("configChat", configChat)

	for _, channelName in pairs(channels) do
		local tab = consoleTabBar:getTab(channelName)

		consoleTabBar:removeTab(tab)
	end

	channels = {}

	consoleTabBar:removeTab(defaultTab)

	defaultTab = nil

	consoleTabBar:removeTab(serverTab)

	serverTab = nil

	local npcTab = consoleTabBar:getTab("NPCs")

	if npcTab then
		consoleTabBar:removeTab(npcTab)

		npcTab = nil
	end

	if violationReportTab then
		consoleTabBar:removeTab(violationReportTab)

		violationReportTab = nil
	end

	consoleTextEdit:clearText()

	if violationWindow then
		violationWindow:destroy()

		violationWindow = nil
	end

	if channelsWindow then
		channelsWindow:destroy()

		channelsWindow = nil
	end
end

function switchMode(newView)
	floatingMode = newView

	consolePanel:raise()
	consolePanel:breakAnchors()
	consolePanel:setDraggable(newView)
	consolePanel:setPhantom(not newView)
	consolePanel.rightResizeBorder:setEnabled(newView)
	consolePanel.bottomResizeBorder:setEnabled(newView)
	consolePanel.rightResizeBorder:setVisible(newView)
	consolePanel.bottomResizeBorder:setVisible(newView)
	modules.game_interface.getBottomSplitter():setVisible(not newView)

	if newView then
		if consoleToggleChat:isChecked() then
			visibleConsolePanel(false)
		end

		consolePanel:setHeight(consolePanel.saveHeight)
		consolePanel:setWidth(consolePanel.saveWidth)
		consolePanel:setPosition(consolePanel.savePos)
	else
		addEvent(function()
			visibleConsolePanel(true)
			scheduleEvent(function()
				consoleTextEdit:setVisible(not consoleToggleChat:isChecked())
			end, 20)
			modules.game_interface.getBottomSplitter():raise()
			consolePanel:addAnchor(AnchorBottom, "parent", AnchorBottom)
			consolePanel:addAnchor(AnchorTop, "gameActionPanel", AnchorBottom)
			consolePanel:addAnchor(AnchorLeft, "gameActionPanel", AnchorLeft)
			consolePanel:addAnchor(AnchorRight, "gameActionPanel", AnchorRight)
		end)
	end
end

function onDragEnter(widget, mousePos)
	widget:breakAnchors()

	widget.movingReference = {
		x = mousePos.x - widget:getX(),
		y = mousePos.y - widget:getY()
	}

	return floatingMode
end

function onDragMove(widget, mousePos, moved)
	if not floatingMode then
		return
	end

	local pos = {
		x = mousePos.x - widget.movingReference.x,
		y = mousePos.y - widget.movingReference.y
	}

	widget:setPosition(pos)
	widget:bindRectToParent()

	return true
end

function onDragLeave(widget, pos)
	widget.savePos = widget:getPosition()

	return floatingMode
end

function clearChannel(consoleTabBar)
	consoleTabBar:getCurrentTab().tabPanel:getChildById("consoleBuffer"):destroyChildren()
end

function setTextEditText(text)
	consoleTextEdit:setText(text)
	consoleTextEdit:setCursorPos(-1)
end

function openHelp()
	local helpChannel = 9

	if g_game.getClientVersion() <= 810 then
		helpChannel = 8
	end

	g_game.joinChannel(helpChannel)
end

function openPlayerReportRuleViolationWindow()
	if violationWindow or violationReportTab then
		return
	end

	violationWindow = g_ui.loadUI("violationwindow", rootWidget)

	function violationWindow.onEscape()
		violationWindow:destroy()

		violationWindow = nil
	end

	function violationWindow.onEnter()
		local text = violationWindow:getChildById("text"):getText()

		g_game.talkChannel(MessageModes.RVRChannel, 0, text)

		violationReportTab = addTab(tr("Report Rule") .. "...", true)

		addTabText(tr("Please wait patiently for a gamemaster to reply") .. ".", SpeakTypesSettings.privateRed, violationReportTab)
		addTabText(applyMessagePrefixies(g_game.getCharacterName(), 0, text), SpeakTypesSettings.say, violationReportTab, g_game.getCharacterName())

		violationReportTab.locked = true

		violationWindow:destroy()

		violationWindow = nil
	end
end

function addTab(name, focus)
	local tab = getTab(name)

	if tab then
		if not focus then
			focus = true
		end
	else
		tab = consoleTabBar:addTab(name, nil, processChannelTabMenu)
		tab:setColor("#1fbf6e")
	end

	if focus then
		consoleTabBar:selectTab(tab)
	end

	return tab
end

function removeTab(tab)
	if type(tab) == "string" then
		tab = consoleTabBar:getTab(tab)
	end

	if tab == defaultTab or tab == serverTab then
		return
	end

	if tab == violationReportTab then
		g_game.cancelRuleViolation()

		violationReportTab = nil
	elseif tab.violationChatName then
		g_game.closeRuleViolation(tab.violationChatName)
	elseif tab.channelId then
		for k, v in pairs(channels) do
			if k == tab.channelId then
				channels[k] = nil
			end
		end

		g_game.leaveChannel(tab.channelId)
	elseif tab:getText() == "NPCs" then
		g_game.closeNpcChannel()
	end

	if getCurrentTab() == tab then
		consoleTabBar:selectTab(defaultTab)
	end

	consoleTabBar:removeTab(tab)
end

function removeCurrentTab()
	removeTab(consoleTabBar:getCurrentTab())
end

function getTab(name)
	return consoleTabBar:getTab(name)
end

function getChannelTab(channelId)
	local channel = channels[channelId]

	if channel then
		return getTab(channel)
	end

	return nil
end

function getRuleViolationsTab()
	if violationsChannelId then
		return getChannelTab(violationsChannelId)
	end

	return nil
end

function getCurrentTab()
	return consoleTabBar:getCurrentTab()
end

function addChannel(name, id)
	channels[id] = name

	local focus = not table.find(ignoredChannels, id)
	local tab = addTab(name, focus)

	tab.channelId = id

	return tab
end

function addPrivateChannel(receiver)
	channels[receiver] = receiver

	return addTab(receiver, true)
end

function addPrivateText(text, speaktype, name, isPrivateCommand, creatureName)
	if speaktype.npcChat then
		return
	end

	local focus = false

	if speaktype.npcChat then
		name = "NPCs"
		focus = true
	end

	local privateTab = getTab(name)

	if privateTab == nil then
		if modules.client_options.getOption("showPrivateMessagesInConsole") and not focus or isPrivateCommand and not privateTab then
			privateTab = defaultTab
		else
			privateTab = addTab(name, focus)
			channels[name] = name
		end

		privateTab.npcChat = speaktype.npcChat
	elseif focus then
		consoleTabBar:selectTab(privateTab)
	end

	addTabText(text, speaktype, privateTab, creatureName)
end

function addText(text, speaktype, tabName, creatureName)
	local tab = getTab(tabName)

	if tab == nil then
		pdebug(string.format('[Console] Tab "%s" not found; creating.', tostring(tabName)))
		tab = addTab(tabName, false)
	end
	if tab then
		addTabText(text, speaktype, tab, creatureName)
		else
		pwarning(string.format('[Console] Failed to log text; tab "%s" unavailable.', tostring(tabName)))
	end
end

local letterWidth = {
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	1,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	1,
	3,
	6,
	8,
	7,
	13,
	9,
	3,
	5,
	5,
	6,
	8,
	4,
	5,
	3,
	8,
	7,
	6,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	3,
	4,
	8,
	8,
	8,
	6,
	10,
	9,
	7,
	7,
	8,
	7,
	7,
	8,
	8,
	5,
	5,
	7,
	7,
	9,
	8,
	8,
	7,
	8,
	8,
	7,
	8,
	8,
	8,
	12,
	8,
	8,
	7,
	5,
	8,
	5,
	9,
	8,
	5,
	7,
	7,
	6,
	7,
	7,
	5,
	7,
	7,
	3,
	4,
	7,
	3,
	11,
	7,
	7,
	7,
	7,
	6,
	6,
	5,
	7,
	8,
	10,
	8,
	8,
	6,
	7,
	4,
	7,
	8,
	1,
	7,
	6,
	3,
	7,
	6,
	11,
	7,
	7,
	7,
	13,
	7,
	4,
	11,
	6,
	6,
	6,
	6,
	4,
	3,
	7,
	6,
	6,
	7,
	10,
	7,
	10,
	6,
	5,
	11,
	6,
	6,
	8,
	4,
	3,
	7,
	7,
	7,
	8,
	4,
	7,
	6,
	10,
	6,
	8,
	8,
	16,
	10,
	8,
	5,
	8,
	5,
	5,
	6,
	7,
	7,
	3,
	5,
	6,
	6,
	8,
	12,
	12,
	12,
	6,
	9,
	9,
	9,
	9,
	9,
	9,
	11,
	7,
	7,
	7,
	7,
	7,
	5,
	5,
	6,
	5,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	11,
	6,
	7,
	7,
	7,
	7,
	3,
	4,
	4,
	4,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	9,
	7,
	7,
	7,
	7,
	7,
	8,
	7,
	8
}

function getNewHighlightedText(text, color, highlightColor)
	local tmpData = {}

	for i, part in ipairs(text:split("{")) do
		if i == 1 then
			table.insert(tmpData, part)
			table.insert(tmpData, color)
		else
			for j, part2 in ipairs(part:split("}")) do
				if j == 1 then
					table.insert(tmpData, part2)
					table.insert(tmpData, highlightColor)
				else
					table.insert(tmpData, part2)
					table.insert(tmpData, color)
				end
			end
		end
	end

	return tmpData
end

function addTabText(text, speaktype, tab, creatureName)
	if not tab or tab.locked or not text or #text == 0 then
		return
	end

	if modules.client_options.getOption("showTimestampsInConsole") then
		text = os.date("%H:%M") .. " " .. text
	end

	local panel = consoleTabBar:getTabPanel(tab)
	local consoleBuffer = panel:getChildById("consoleBuffer")
	local label

	if consoleBuffer:getChildCount() > MAX_LINES then
		label = consoleBuffer:getFirstChild()

		consoleBuffer:moveChildToIndex(label, consoleBuffer:getChildCount())
	end

	label = label or g_ui.createWidget("ConsoleLabel", consoleBuffer)

	label:setId("consoleLabel" .. consoleBuffer:getChildCount())
	local tabText = tab:getText()
	-- Cor padrão para nome do canal
	local channelColor = "#1fbf6e"
	local ts, rest = text:match("^(%d%d:%d%d)%s+(.*)$")
	rest = rest or text
	-- Linha visível (sem prefixo do canal)
	local coloredStr = ""
	if ts then
		coloredStr = coloredStr .. "{" .. ts .. " " .. ", " .. "#FFFFFF" .. "}"
	end
	local namePart, body = rest:match("^(.-):%s*(.*)$")
	if namePart then
		local nOnly, lvl = namePart:match("^(.-)%s*%((%d+)%)$")
		if not lvl then
			nOnly, lvl = namePart:match("^(.-)%s*%[(%d+)%]$")
		end
		if nOnly and lvl then
			coloredStr = coloredStr .. "{" .. nOnly .. ", " .. "#1fbf6e" .. "}"
			coloredStr = coloredStr .. "{" .. " (" .. lvl .. "): " .. ", " .. "#FFFFFF" .. "}"
		else
			coloredStr = coloredStr .. "{" .. namePart .. ": " .. ", " .. "#1fbf6e" .. "}"
		end
		coloredStr = coloredStr .. "{" .. body .. ", " .. "#FFFFFF" .. "}"
	else
		coloredStr = coloredStr .. "{" .. rest .. ", " .. "#FFFFFF" .. "}"
	end
	label:setColoredText(coloredStr)
	consoleTabBar:blinkTab(tab)

	if table.contains({
		4,
		5,
		6
	}, tab.channelId) then
		local playerName = g_game.getCharacterName():gsub("[%[%]]", "%%%0")

		if string.find(text:lower(), tr("@%s", playerName:lower())) then
			label:setPadding(3)
			label:setImageBorder(10)
			label:setImageColor("#1fbf6e")
			label:setImageSource("/images/ui/panel_rounded_solid")
		end
	end

	if speaktype.npcChat and (g_game.getCharacterName() ~= creatureName or g_game.getCharacterName() == "Account Manager") then
		local highlightData = getNewHighlightedText(text, speaktype.color, "#1fbf6e")

		if #highlightData > 2 then
			label:setColoredText(highlightData)
		end
	end

	-- Linha no phantom (com prefixo do canal em verde)
	local phantomStr = ""
	phantomStr = phantomStr .. "{" .. "(" .. tabText .. ") " .. ", " .. channelColor .. "}"
	if ts then
		phantomStr = phantomStr .. "{" .. ts .. " " .. ", " .. "#FFFFFF" .. "}"
	end
	if namePart then
		local nOnly, lvl = namePart:match("^(.-)%s*%((%d+)%)$")
		if not lvl then
			nOnly, lvl = namePart:match("^(.-)%s*%[(%d+)%]$")
		end
		if nOnly and lvl then
			phantomStr = phantomStr .. "{" .. nOnly .. ", " .. "#1fbf6e" .. "}"
			phantomStr = phantomStr .. "{" .. " (" .. lvl .. "): " .. ", " .. "#FFFFFF" .. "}"
		else
			phantomStr = phantomStr .. "{" .. namePart .. ": " .. ", " .. "#1fbf6e" .. "}"
		end
		phantomStr = phantomStr .. "{" .. body .. ", " .. "#FFFFFF" .. "}"
	else
		phantomStr = phantomStr .. "{" .. rest .. ", " .. "#FFFFFF" .. "}"
	end
	addConsolePhatomLine(phantomStr, speaktype.color)

	label.name = creatureName

	function consoleBuffer:onMouseRelease(mousePos, mouseButton)
		processMessageMenu(mousePos, mouseButton, nil, nil, nil, tab)
	end

	function label:onMouseRelease(mousePos, mouseButton)
		processMessageMenu(mousePos, mouseButton, creatureName, text, self, tab)
	end

	function label:onMousePress(mousePos, button)
		if button == MouseLeftButton then
			clearSelection(consoleBuffer)
		end
	end

	function label:onDragEnter(mousePos)
		clearSelection(consoleBuffer)

		return true
	end

	function label:onDragLeave(droppedWidget, mousePos)
		local text = {}

		for selectionChild = consoleBuffer.selection.first, consoleBuffer.selection.last do
			local label = self:getParent():getChildByIndex(selectionChild)

			table.insert(text, label:getSelection())
		end

		consoleBuffer.selectionText = table.concat(text, "\n")

		return true
	end

	function label:onDragMove(mousePos, mouseMoved)
		local parent = self:getParent()
		local parentRect = parent:getPaddingRect()
		local selfIndex = parent:getChildIndex(self)
		local child = parent:getChildByPos(mousePos)

		if not child then
			if mousePos.y < self:getY() then
				for index = selfIndex - 1, 1, -1 do
					local label = parent:getChildByIndex(index)

					if label:getY() + label:getHeight() > parentRect.y then
						if mousePos.y >= label:getY() and mousePos.y <= label:getY() + label:getHeight() or index == 1 then
							child = label

							break
						end
					else
						child = parent:getChildByIndex(index + 1)

						break
					end
				end
			elseif mousePos.y > self:getY() + self:getHeight() then
				for index = selfIndex + 1, parent:getChildCount() do
					local label = parent:getChildByIndex(index)

					if label:getY() < parentRect.y + parentRect.height then
						if mousePos.y >= label:getY() and mousePos.y <= label:getY() + label:getHeight() or index == parent:getChildCount() then
							child = label

							break
						end
					else
						child = parent:getChildByIndex(index - 1)

						break
					end
				end
			else
				child = self
			end
		end

		if not child then
			return false
		end

		local childIndex = parent:getChildIndex(child)

		clearSelection(consoleBuffer)

		local textBegin = self:getTextPos(self:getLastClickPosition())
		local textPos = self:getTextPos(mousePos)

		self:setSelection(textBegin, textPos)

		consoleBuffer.selection = {
			first = math.min(selfIndex, childIndex),
			last = math.max(selfIndex, childIndex)
		}

		if child ~= self then
			for selectionChild = consoleBuffer.selection.first + 1, consoleBuffer.selection.last - 1 do
				parent:getChildByIndex(selectionChild):selectAll()
			end

			local textPos = child:getTextPos(mousePos)

			if selfIndex < childIndex then
				child:setSelection(0, textPos)
			else
				child:setSelection(string.len(child:getText()), textPos)
			end
		end

		return true
	end
end

function removeTabLabelByName(tab, name)
	local panel = consoleTabBar:getTabPanel(tab)
	local consoleBuffer = panel:getChildById("consoleBuffer")

	for _, label in pairs(consoleBuffer:getChildren()) do
		if label.name == name then
			label:destroy()
		end
	end
end

function processChannelTabMenu(tab, mousePos, mouseButton)
	local menu = g_ui.createWidget("PopupMenu")

	menu:setGameMenu(true)

	local worldName = g_game.getWorldName()
	local characterName = g_game.getCharacterName()

	channelName = tab:getText()

	if tab ~= defaultTab and tab ~= serverTab then
		menu:addOption(tr("Close"), function()
			removeTab(channelName)
		end)
		menu:addSeparator()
	end

	if consoleTabBar:getCurrentTab() == tab then
		menu:addOption(tr("Clear Messages"), function()
			clearChannel(consoleTabBar)
		end)
		menu:addOption(tr("Save Messages"), function()
			local panel = consoleTabBar:getTabPanel(tab)
			local consoleBuffer = panel:getChildById("consoleBuffer")
			local lines = {}

			for _, label in pairs(consoleBuffer:getChildren()) do
				table.insert(lines, label:getText())
			end

			local filename = worldName .. " - " .. characterName .. " - " .. channelName .. ".txt"
			local filepath = "/user_dir/" .. filename

			table.insert(lines, 1, os.date("\nChannel saved at %a %b %d %H:%M:%S %Y"))

			if g_resources.fileExists(filepath) then
				table.insert(lines, 1, protectedcall(g_resources.readFileContents, filepath) or "")
			end

			g_resources.writeFileContents(filepath, table.concat(lines, "\n"))
			modules.game_textmessage.displayStatusMessage(tr("Channel appended to %s", filename))
		end)
	end

	menu:display(mousePos)
end

function processMessageMenu(mousePos, mouseButton, creatureName, text, label, tab)
	if mouseButton == MouseRightButton then
		local menu = g_ui.createWidget("PopupMenu")

		menu:setGameMenu(true)

		if creatureName and #creatureName > 0 then
			if creatureName ~= g_game.getCharacterName() then
				menu:addOption(tr("Message to " .. creatureName), function()
					g_game.openPrivateChannel(creatureName)
				end)

				if not g_game.getLocalPlayer():hasVip(creatureName) then
					menu:addOption(tr("Add to VIP list"), function()
						g_game.addVip(creatureName)
					end)
				end

				if modules.game_console.getOwnPrivateTab() then
					menu:addSeparator()
					menu:addOption(tr("Invite to private chat"), function()
						g_game.inviteToOwnChannel(creatureName)
					end)
					menu:addOption(tr("Exclude from private chat"), function()
						g_game.excludeFromOwnChannel(creatureName)
					end)
				end

				if isIgnored(creatureName) then
					menu:addOption(tr("Unignore") .. " " .. creatureName, function()
						removeIgnoredPlayer(creatureName)
					end)
				else
					menu:addOption(tr("Ignore") .. " " .. creatureName, function()
						addIgnoredPlayer(creatureName)
					end)
				end

				menu:addSeparator()
			end

			if modules.game_ruleviolation.hasWindowAccess() then
				menu:addOption(tr("Rule Violation"), function()
					modules.game_ruleviolation.show(creatureName, text:match(".+%:%s(.+)"))
				end)
				menu:addSeparator()
			end

			menu:addOption(tr("Copy name"), function()
				g_window.setClipboardText(creatureName)
			end)
		end

		local selection = tab.tabPanel:getChildById("consoleBuffer").selectionText

		if selection and #selection > 0 then
			menu:addOption(tr("Copy"), function()
				g_window.setClipboardText(selection)
			end, "(Ctrl+C)")
		end

		if text then
			menu:addOption(tr("Copy message"), function()
				g_window.setClipboardText(text)
			end)
		end

		if table.contains({
			4,
			5,
			6
		}, tab.channelId) and creatureName ~= g_game.getLocalPlayer():getName() then
			menu:addOption(tr("Responder Jogador"), function()
				setTextEditText(tr("@%s ", creatureName))
			end)
		end

		menu:addOption(tr("Select all"), function()
			selectAll(tab.tabPanel:getChildById("consoleBuffer"))
		end)

		if tab.violations and creatureName then
			menu:addSeparator()
			menu:addOption(tr("Process") .. " " .. creatureName, function()
				processViolation(creatureName, text)
			end)
			menu:addOption(tr("Remove") .. " " .. creatureName, function()
				g_game.closeRuleViolation(creatureName)
			end)
		end

		menu:display(mousePos)
	end
end

function sendCurrentMessage()
	local message = consoleTextEdit:getText()

	if #message == 0 then
		return
	end

	if not isChatEnabled() then
		return
	end

	consoleTextEdit:clearText()
	sendMessage(message)
end

function addFilter(filter)
	table.insert(filters, filter)
end

function removeFilter(filter)
	table.removevalue(filters, filter)
end

function sendMessage(message, tab)
	local tab = tab or getCurrentTab()

	if not tab then
		return
	end

	for k, func in pairs(filters) do
		if func(message) then
			return true
		end
	end

	local name = tab:getText()

	if tab == serverTab or tab == getRuleViolationsTab() then
        tab = defaultTab or tab
        name = (defaultTab and defaultTab.getText and defaultTab:getText()) or (tab and tab.getText and tab:getText()) or tr("Default")
    end

	local channel = tab.channelId
	local originalMessage = message
	local chatCommandSayMode, chatCommandPrivate, chatCommandPrivateReady, chatCommandMessage

	chatCommandMessage = message:match("^%#[y|Y] (.*)")

	if chatCommandMessage ~= nil then
		chatCommandSayMode = "yell"
		channel = 0
		message = chatCommandMessage
	end

	chatCommandMessage = message:match("^%#[w|W] (.*)")

	if chatCommandMessage ~= nil then
		chatCommandSayMode = "whisper"
		message = chatCommandMessage
		channel = 0
	end

	chatCommandMessage = message:match("^%#[s|S] (.*)")

	if chatCommandMessage ~= nil then
		chatCommandSayMode = "say"
		message = chatCommandMessage
		channel = 0
	end

	chatCommandMessage = message:match("^%#[c|C] (.*)")

	if chatCommandMessage ~= nil then
		chatCommandSayMode = "channelRed"
		message = chatCommandMessage
	end

	chatCommandMessage = message:match("^%#[b|B] (.*)")

	if chatCommandMessage ~= nil then
		chatCommandSayMode = "broadcast"
		message = chatCommandMessage
		channel = 0
	end

	local findIni, findEnd, chatCommandInitial, chatCommandPrivate, chatCommandEnd, chatCommandMessage = message:find("([%*%@])(.+)([%*%@])(.*)")

	if findIni ~= nil and findIni == 1 and chatCommandInitial == chatCommandEnd then
		chatCommandPrivateRepeat = false

		if chatCommandInitial == "*" then
			setTextEditText("*" .. chatCommandPrivate .. "* ")
		end

		message = chatCommandMessage:trim()
		chatCommandPrivateReady = true
	end

	message = message:gsub("^(%s*)(.*)", "%2")

	if #message == 0 then
		return
	end

	currentMessageIndex = 0

	if #messageHistory == 0 or messageHistory[#messageHistory] ~= originalMessage then
		table.insert(messageHistory, originalMessage)

		if #messageHistory > MAX_HISTORY then
			table.remove(messageHistory, 1)
		end
	end

	local speaktypedesc

	 if (channel or tab == defaultTab) and not chatCommandPrivateReady then
        if tab == defaultTab then
            local sayButton = consolePanel and consolePanel:getChildById("sayModeButton")
            local sayMode = (sayButton and sayButton.sayMode) or 2 -- default index for "say"
            local sayEntry = SayModes[sayMode]
            speaktypedesc = chatCommandSayMode or (sayEntry and sayEntry.speakTypeDesc) or "say"

			if speaktypedesc ~= "say" then
				sayModeChange(2)
			end
		else
			speaktypedesc = chatCommandSayMode or "channelYellow"
		end

		local speaktype = SpeakTypesSettings[speaktypedesc]
        if speaktype and speaktype.speakType then
            g_game.talkChannel(speaktype.speakType, channel, message)
        else
            g_game.talkChannel(MessageModes.Say, channel or 0, message)
            speaktype = SpeakTypesSettings.say
        end

		return
	else
		local isPrivateCommand = false
		local priv = true
		local tabname = name
		local dontAdd = false

		if chatCommandPrivateReady then
			speaktypedesc = "privatePlayerToPlayer"
			name = chatCommandPrivate
			isPrivateCommand = true
		elseif tab.npcChat then
			speaktypedesc = "privatePlayerToNpc"
		elseif tab == violationReportTab then
			if violationReportTab.locked then
				modules.game_textmessage.displayFailureMessage("Wait for a gamemaster reply.")

				dontAdd = true
			else
				speaktypedesc = "rvrContinue"
				tabname = tr("Report Rule") .. "..."
			end
		elseif tab.violationChatName then
			speaktypedesc = "rvrAnswerTo"
			name = tab.violationChatName
			tabname = tab.violationChatName .. "'..."
		else
			speaktypedesc = "privatePlayerToPlayer"
		end

		 local speaktype = SpeakTypesSettings[speaktypedesc] or SpeakTypesSettings.privatePlayerToPlayer
		local player = g_game.getLocalPlayer()

		g_game.talkPrivate(speaktype.speakType, name, message)

		if not dontAdd then
			message = applyMessagePrefixies(g_game.getCharacterName(), player:getLevel(), message)

			addPrivateText(message, speaktype, tabname, isPrivateCommand, g_game.getCharacterName())
		end
	end
end

function sayModeChange(sayMode)
	local buttom = consolePanel:getChildById("sayModeButton")

	if sayMode == nil then
		sayMode = buttom.sayMode + 1
	end

	if sayMode > #SayModes then
		sayMode = 1
	end

	buttom:setIcon(SayModes[sayMode].icon)

	buttom.sayMode = sayMode
end

function getOwnPrivateTab()
	if not ownPrivateName then
		return
	end

	return getTab(ownPrivateName)
end

function setIgnoreNpcMessages(ignore)
	ignoreNpcMessages = ignore
end

function navigateMessageHistory(step)
	if not isChatEnabled() then
		return
	end

	local numCommands = #messageHistory

	if numCommands > 0 then
		currentMessageIndex = math.min(math.max(currentMessageIndex + step, 0), numCommands)

		if currentMessageIndex > 0 then
			local command = messageHistory[numCommands - currentMessageIndex + 1]

			setTextEditText(command)
		else
			consoleTextEdit:clearText()
		end
	end

	local player = g_game.getLocalPlayer()

	if player then
		player:lockWalk(200)
	end
end

function applyMessagePrefixies(name, level, message)
	if name and #name > 0 then
		if modules.client_options.getOption("showLevelsInConsole") and level > 0 then
			message = name .. " [" .. level .. "]: " .. message
		else
			message = name .. ": " .. message
		end
	end

	return message
end

function onTalk(name, level, mode, message, channelId, creaturePos)
	if mode == MessageModes.GamemasterBroadcast then
		modules.game_textmessage.displayBroadcastMessage(name .. ": " .. message)

		return
	end

	local isNpcMode = mode == MessageModes.NpcFromStartBlock or mode == MessageModes.NpcFrom

	if ignoreNpcMessages and isNpcMode then
		return
	end

	speaktype = SpeakTypes[mode]

	if not speaktype then
		perror("unhandled onTalk message mode " .. mode .. ": " .. message)

		return
	end

	local localPlayer = g_game.getLocalPlayer()

	if name ~= g_game.getCharacterName() and isUsingIgnoreList() and not isUsingWhiteList() or isUsingWhiteList() and not isWhitelisted(name) and (not isAllowingVIPs() or not localPlayer:hasVip(name)) then
		if mode == MessageModes.Yell and isIgnoringYelling() then
			return
		elseif speaktype.private and isIgnoringPrivate() and not isNpcMode then
			return
		elseif isIgnored(name) then
			return
		end
	end

	if mode == MessageModes.RVRChannel then
		channelId = violationsChannelId
	end

	if (mode == MessageModes.Say or mode == MessageModes.Whisper or mode == MessageModes.Yell or mode == MessageModes.Spell or mode == MessageModes.MonsterSay or mode == MessageModes.MonsterYell or mode == MessageModes.NpcFrom or mode == MessageModes.BarkLow or mode == MessageModes.BarkLoud or mode == MessageModes.NpcFromStartBlock) and creaturePos then
		local staticText = StaticText.create()
		local staticMessage = message

		if isNpcMode then
			staticText:addMessage(name, mode, staticMessage)
			staticText:setColor(speaktype.color)
		else
			staticText:addMessage(name, mode, staticMessage)
			--[[ g_map.addStaticText(staticText, creaturePos) ]]
		end

		g_map.addThing(staticText, creaturePos, -1)
	end

	local defaultMessage = mode <= 3 and true or false

	if speaktype == SpeakTypesSettings.none then
		return
	end

	if speaktype.hideInConsole then
		return
	end

	local composedMessage = applyMessagePrefixies(name, level, message)

	if mode == MessageModes.RVRAnswer then
		violationReportTab.locked = false

		addTabText(composedMessage, speaktype, violationReportTab, name)
	elseif mode == MessageModes.RVRContinue then
		addText(composedMessage, speaktype, name .. "'...", name)
	elseif speaktype.private then
		addPrivateText(composedMessage, speaktype, name, false, name)

		if modules.client_options.getOption("showPrivateMessagesOnScreen") and speaktype ~= SpeakTypesSettings.privateNpcToPlayer then
			modules.game_textmessage.displayPrivateMessage(name .. ":\n" .. message)
		end
	else
		local channel = tr("Default")

		if not defaultMessage then
			channel = channels[channelId]
		end

		if channel then
			addText(composedMessage, speaktype, channel, name)
		else
			if serverTab then
				addTabText(composedMessage, speaktype, serverTab, name)
			else
				addText(composedMessage, speaktype, tr("Server Log"), name)
			end
		end
	end
end

function onOpenChannel(channelId, channelName)
	addChannel(channelName, channelId)
end

function onOpenPrivateChannel(receiver)
	addPrivateChannel(receiver)
end

function onOpenOwnPrivateChannel(channelId, channelName)
	local privateTab = getTab(channelName)

	if privateTab == nil then
		addChannel(channelName, channelId)
	end

	ownPrivateName = channelName
end

function onCloseChannel(channelId)
	local channel = channels[channelId]

	if channel then
		local tab = getTab(channel)

		if tab then
			consoleTabBar:removeTab(tab)
			consoleTabBar:selectTab(defaultTab)
		end
		for k, v in pairs(channels) do
			if k == tab.channelId then
				channels[k] = nil
			end
		end
	end
end

function processViolation(name, text)
	local tabname = name .. "'..."
	local tab = addTab(tabname, true)

	channels[tabname] = tabname
	tab.violationChatName = name

	g_game.openRuleViolation(name)
	addTabText(text, SpeakTypesSettings.say, tab, name)
end

function onRuleViolationChannel(channelId)
	violationsChannelId = channelId

	local tab = addChannel(tr("Rule Violations"), channelId)

	tab.violations = true
end

function onRuleViolationRemove(name)
	local tab = getRuleViolationsTab()

	if not tab then
		return
	end

	removeTabLabelByName(tab, name)
end

function onRuleViolationCancel(name)
	local tab = getTab(name .. "'...")

	if not tab then
		return
	end

	addTabText(tr("%s has finished the request", name) .. ".", SpeakTypesSettings.privateRed, tab)

	tab.locked = true
end

function onRuleViolationLock()
	if not violationReportTab then
		return
	end

	violationReportTab.locked = false

	addTabText(tr("Your request has been closed") .. ".", SpeakTypesSettings.privateRed, violationReportTab)

	violationReportTab.locked = true
end

function doChannelListSubmit()
	local channelListPanel = channelsWindow:getChildById("channelList")
	local openPrivateChannelWith = channelsWindow:getChildById("openPrivateChannelWith"):getText()

	if openPrivateChannelWith ~= "" then
		if openPrivateChannelWith:lower() ~= g_game.getCharacterName():lower() then
			g_game.openPrivateChannel(openPrivateChannelWith)
		else
			modules.game_textmessage.displayFailureMessage("You cannot create a private chat channel with yourself.")
		end
	else
		local selectedChannelLabel = channelListPanel:getFocusedChild()

		if not selectedChannelLabel then
			return
		end

		if selectedChannelLabel.channelId == 65535 then
			g_game.openOwnChannel()
		else
			g_game.leaveChannel(selectedChannelLabel.channelId)
			g_game.joinChannel(selectedChannelLabel.channelId)
		end
	end

	channelsWindow:destroy()
end

function onChannelList(channelList)
	if channelsWindow then
		channelsWindow:destroy()
	end

	channelsWindow = g_ui.displayUI("channelswindow")

	local channelListPanel = channelsWindow:getChildById("channelList")

	channelsWindow.onEnter = doChannelListSubmit

	function channelsWindow.onDestroy()
		channelsWindow = nil
	end

	g_keyboard.bindKeyPress("Down", function()
		channelListPanel:focusNextChild(KeyboardFocusReason)
	end, channelsWindow)
	g_keyboard.bindKeyPress("Up", function()
		channelListPanel:focusPreviousChild(KeyboardFocusReason)
	end, channelsWindow)

	for k, v in pairs(channelList) do
		local channelId = v[1]
		local channelName = v[2]

		if #channelName > 0 then
			local label = g_ui.createWidget("ChannelListLabel", channelListPanel)

			label.channelId = channelId

			label:setText(channelName)
			label:setPhantom(false)

			label.onDoubleClick = doChannelListSubmit
		end
	end
end

function loadCommunicationSettings()
	communicationSettings.whitelistedPlayers = {}
	communicationSettings.ignoredPlayers = {}

	local ignoreNode = g_settings.getNode("IgnorePlayers")

	if ignoreNode then
		for _, player in pairs(ignoreNode) do
			table.insert(communicationSettings.ignoredPlayers, player)
		end
	end

	local whitelistNode = g_settings.getNode("WhitelistedPlayers")

	if whitelistNode then
		for _, player in pairs(whitelistNode) do
			table.insert(communicationSettings.whitelistedPlayers, player)
		end
	end

	communicationSettings.useIgnoreList = g_settings.getBoolean("UseIgnoreList")
	communicationSettings.useWhiteList = g_settings.getBoolean("UseWhiteList")
	communicationSettings.privateMessages = g_settings.getBoolean("IgnorePrivateMessages")
	communicationSettings.yelling = g_settings.getBoolean("IgnoreYelling")
	communicationSettings.allowVIPs = g_settings.getBoolean("AllowVIPs")
end

function saveCommunicationSettings()
	local tmpIgnoreList = {}
	local ignoredPlayers = getIgnoredPlayers()

	for i = 1, #ignoredPlayers do
		table.insert(tmpIgnoreList, ignoredPlayers[i])
	end

	local tmpWhiteList = {}
	local whitelistedPlayers = getWhitelistedPlayers()

	for i = 1, #whitelistedPlayers do
		table.insert(tmpWhiteList, whitelistedPlayers[i])
	end

	g_settings.set("UseIgnoreList", communicationSettings.useIgnoreList)
	g_settings.set("UseWhiteList", communicationSettings.useWhiteList)
	g_settings.set("IgnorePrivateMessages", communicationSettings.privateMessages)
	g_settings.set("IgnoreYelling", communicationSettings.yelling)
	g_settings.setNode("IgnorePlayers", tmpIgnoreList)
	g_settings.setNode("WhitelistedPlayers", tmpWhiteList)
end

function getIgnoredPlayers()
	return communicationSettings.ignoredPlayers
end

function getWhitelistedPlayers()
	return communicationSettings.whitelistedPlayers
end

function isUsingIgnoreList()
	return communicationSettings.useIgnoreList
end

function isUsingWhiteList()
	return communicationSettings.useWhiteList
end

function isIgnored(name)
	return table.find(communicationSettings.ignoredPlayers, name, true)
end

function addIgnoredPlayer(name)
	if isIgnored(name) then
		return
	end

	addIgnoreListPanel(name)
	table.insert(communicationSettings.ignoredPlayers, name)

	communicationSettings.useIgnoreList = true
end

function removeIgnoredPlayer(name)
	removeIgnoreListPanel(name)
	table.removevalue(communicationSettings.ignoredPlayers, name)
end

function isWhitelisted(name)
	return table.find(communicationSettings.whitelistedPlayers, name, true)
end

function addWhitelistedPlayer(name)
	if isWhitelisted(name) then
		return
	end

	table.insert(communicationSettings.whitelistedPlayers, name)
end

function removeWhitelistedPlayer(name)
	table.removevalue(communicationSettings.whitelistedPlayers, name)
end

function isIgnoringPrivate()
	return communicationSettings.privateMessages
end

function isIgnoringYelling()
	return communicationSettings.yelling
end

function isAllowingVIPs()
	return communicationSettings.allowVIPs
end

function onClickIgnoreButton()
	if communicationWindow then
		communicationWindow:destroy()
	else
		communicationWindow = g_ui.createWidget("CommunicationWindow", modules.game_interface.getRootPanel())

		local ignoreListPanel = communicationWindow:getChildById("ignoreList")
		local whiteListPanel = communicationWindow:getChildById("whiteList")

		function communicationWindow.onDestroy()
			communicationWindow = nil
		end

		local useIgnoreListBox = communicationWindow:getChildById("checkboxUseIgnoreList")

		useIgnoreListBox:setChecked(communicationSettings.useIgnoreList)

		local useWhiteListBox = communicationWindow:getChildById("checkboxUseWhiteList")

		useWhiteListBox:setChecked(communicationSettings.useWhiteList)

		local removeWhitelistButton = communicationWindow:getChildById("buttonWhitelistRemove")

		removeWhitelistButton:disable()

		function whiteListPanel.onChildFocusChange()
			removeWhitelistButton:enable()
		end

		function removeWhitelistButton.onClick()
			local selection = whiteListPanel:getFocusedChild()

			if selection then
				whiteListPanel:removeChild(selection)
				selection:destroy()
			end

			removeWhitelistButton:disable()
		end

		local newlyIgnoredPlayers = {}
		local addIgnoreName = communicationWindow:getChildById("ignoreNameEdit")
		local addIgnoreButton = communicationWindow:getChildById("buttonIgnoreAdd")

		local function addIgnoreFunction()
			local newEntry = addIgnoreName:getText()

			if newEntry == "" then
				return
			end

			if table.find(getIgnoredPlayers(), newEntry) then
				return
			end

			if table.find(newlyIgnoredPlayers, newEntry) then
				return
			end

			addIgnoreListPanel(newEntry)
			table.insert(newlyIgnoredPlayers, newEntry)
			addIgnoreName:setText("")
		end

		addIgnoreButton.onClick = addIgnoreFunction

		local newlyWhitelistedPlayers = {}
		local addWhitelistName = communicationWindow:getChildById("whitelistNameEdit")
		local addWhitelistButton = communicationWindow:getChildById("buttonWhitelistAdd")

		local function addWhitelistFunction()
			local newEntry = addWhitelistName:getText()

			if newEntry == "" then
				return
			end

			if table.find(getWhitelistedPlayers(), newEntry) then
				return
			end

			if table.find(newlyWhitelistedPlayers, newEntry) then
				return
			end

			local label = g_ui.createWidget("WhiteListLabel", whiteListPanel)

			label:setText(newEntry)
			table.insert(newlyWhitelistedPlayers, newEntry)
			addWhitelistName:setText("")
		end

		addWhitelistButton.onClick = addWhitelistFunction

		function communicationWindow.onEnter()
			if addWhitelistName:isFocused() then
				addWhitelistFunction()
			elseif addIgnoreName:isFocused() then
				addIgnoreFunction()
			end
		end

		local ignorePrivateMessageBox = communicationWindow:getChildById("checkboxIgnorePrivateMessages")

		ignorePrivateMessageBox:setChecked(communicationSettings.privateMessages)

		local ignoreYellingBox = communicationWindow:getChildById("checkboxIgnoreYelling")

		ignoreYellingBox:setChecked(communicationSettings.yelling)

		local allowVIPsBox = communicationWindow:getChildById("checkboxAllowVIPs")

		allowVIPsBox:setChecked(communicationSettings.allowVIPs)

		local saveButton = communicationWindow:recursiveGetChildById("buttonSave")

		function saveButton.onClick()
			communicationSettings.ignoredPlayers = {}

			for i = 1, ignoreListPanel:getChildCount() do
				addIgnoredPlayer(ignoreListPanel:getChildByIndex(i):getText())
			end

			communicationSettings.whitelistedPlayers = {}

			for i = 1, whiteListPanel:getChildCount() do
				addWhitelistedPlayer(whiteListPanel:getChildByIndex(i):getText())
			end

			communicationSettings.useIgnoreList = useIgnoreListBox:isChecked()
			communicationSettings.useWhiteList = useWhiteListBox:isChecked()
			communicationSettings.yelling = ignoreYellingBox:isChecked()
			communicationSettings.privateMessages = ignorePrivateMessageBox:isChecked()
			communicationSettings.allowVIPs = allowVIPsBox:isChecked()

			communicationWindow:destroy()
		end

		local cancelButton = communicationWindow:recursiveGetChildById("buttonCancel")

		function cancelButton.onClick()
			communicationWindow:destroy()
		end

		local removeIgnoreButton = communicationWindow:getChildById("buttonIgnoreRemove")

		removeIgnoreButton:disable()

		function ignoreListPanel.onChildFocusChange()
			removeIgnoreButton:enable()
		end

		function removeIgnoreButton.onClick()
			local selection = ignoreListPanel:getFocusedChild()

			if selection then
				ignoreListPanel:removeChild(selection)
				selection:destroy()
			end

			removeIgnoreButton:disable()
			saveButton.onClick()
		end

		local ignoredPlayers = getIgnoredPlayers()

		for i = 1, #ignoredPlayers do
			addIgnoreListPanel(ignoredPlayers[i])
		end

		local whitelistedPlayers = getWhitelistedPlayers()

		for i = 1, #whitelistedPlayers do
			local label = g_ui.createWidget("WhiteListLabel", whiteListPanel)

			label:setText(whitelistedPlayers[i])
		end
	end
end

function addIgnorePlayers()
	modules.client_textedit.edit("", {
		title = tr("Add Ignore Players")
	}, function(newText)
		addIgnoredPlayer(newText)
	end)
end

function addIgnoreListPanel(name)
	if not communicationWindow then
		return
	end

	local label = g_ui.createWidget("IgnoreListLabel", communicationWindow.ignoreList)
	local removeIgnoreButton = label.removeIgnoreButton

	label:setId(name)
	label:setText(name)

	function removeIgnoreButton.onClick()
		local selection = communicationWindow.ignoreList:getFocusedChild()

		if selection then
			communicationWindow.ignoreList:removeChild(selection)
			selection:destroy()
		end
	end
end

function removeIgnoreListPanel(name)
	if not communicationWindow then
		return
	end

	local label = communicationWindow.ignoreList[name]

	if label then
		label:destroy()
	end
end

function online()
	defaultTab = addTab(tr("Default"), true)
	serverTab = addTab(tr("Server Log"), false)

	if g_game.getClientVersion() >= 820 then
		-- block empty
	end

	local lastChannelsOpen = g_settings.getNode("lastChannelsOpen")

	if lastChannelsOpen then
		local savedChannels = lastChannelsOpen[g_game.getCharacterName()]

		if savedChannels then
			for channelName, channelId in pairs(savedChannels) do
				channelId = tonumber(channelId)

				if channelId ~= -1 and channelId < 100 and not table.find(channels, channelId) then
					g_game.joinChannel(channelId)
					table.insert(ignoredChannels, channelId)
				end
			end
		end
	end

	local configChat = g_settings.getNode("configChat")

	if configChat then
		local savedConfigChat = configChat[g_game.getCharacterName()]

		if savedConfigChat then
			consolePanel:breakAnchors()

			consolePanel.savePos = topoint(savedConfigChat.savePos)
			consolePanel.saveHeight = savedConfigChat.saveHeight
			consolePanel.saveWidth = savedConfigChat.saveWidth

			consolePanel:setPosition(consolePanel.savePos)
			consolePanel:setWidth(consolePanel.saveWidth)
			consolePanel:setHeight(consolePanel.saveHeight)
			consoleToggleChat:setChecked(savedConfigChat.toggleChat)
		end
	end

	scheduleEvent(function()
		consoleTabBar:selectTab(defaultTab)
	end, 500)
	scheduleEvent(function()
		ignoredChannels = {}
	end, 3000)
end

function offline()
	clear()
end

function onChannelEvent(channelId, name, type)
	local fmt = ChannelEventFormats[type]

	if not fmt then
		print(("Unknown channel event type (%d)."):format(type))

		return
	end

	local channel = channels[channelId]

	if channel then
		local tab = getTab(channel)

		if tab then
			addTabText(fmt:format(name), SpeakTypesSettings.channelOrange, tab)
		end
	end
end
