-- chunkname: @/modules/client_entergame/characterlist.lua

CharacterList = {}

local charactersWindow, loadBox, characterList, errorBox, waitingWindow, updateWaitEvent, resendWaitEvent, loginEvent
local lastLogout = 0
local infoPanel
local favorites = {}
local iconsClan = {
	"icon_valor_20px",
	"icon_mystic_20px",
	"icon_instinct_20px"
}

local function tryLogin(charInfo, tries)
	tries = tries or 1

	if tries > 50 then
		return
	end

	if g_game.isOnline() then
		if tries == 1 then
			g_game.safeLogout()
		end

		loginEvent = scheduleEvent(function()
			tryLogin(charInfo, tries + 1)
		end, 100)

		return
	end

	CharacterList.hide()
	g_game.loginWorld(G.account, G.password, charInfo.worldName, charInfo.worldHost, charInfo.worldPort, charInfo.characterName, G.authenticatorToken, G.sessionKey)

	loadBox = displayCancelBox(tr("Please wait"), tr("Connecting to game server..."))

	connect(loadBox, {
		onCancel = function()
			loadBox = nil

			g_game.cancelLogin()
			CharacterList.show()
		end
	})
	g_settings.set("last-used-character", charInfo.characterName)
	g_settings.set("last-used-world", charInfo.worldName)
end

local function updateWait(timeStart, timeEnd)
	if waitingWindow then
		local time = g_clock.seconds()

		if time <= timeEnd then
			local percent = (time - timeStart) / (timeEnd - timeStart) * 100
			local timeStr = string.format("%.0f", timeEnd - time)
			local progressBar = waitingWindow:getChildById("progressBar")

			progressBar:setPercent(percent)

			local label = waitingWindow:getChildById("timeLabel")

			label:setText(tr("Trying to reconnect in %s seconds.", timeStr))

			updateWaitEvent = scheduleEvent(function()
				updateWait(timeStart, timeEnd)
			end, 1000 * progressBar:getPercentPixels() / 100 * (timeEnd - timeStart))

			return true
		end
	end

	if updateWaitEvent then
		updateWaitEvent:cancel()

		updateWaitEvent = nil
	end
end

local function resendWait()
	if waitingWindow then
		waitingWindow:destroy()

		waitingWindow = nil

		if updateWaitEvent then
			updateWaitEvent:cancel()

			updateWaitEvent = nil
		end

		if charactersWindow then
			local selected = characterList:getFocusedChild()

			if selected then
				local charInfo = {
					worldHost = selected.worldHost,
					worldPort = selected.worldPort,
					worldName = selected.worldName,
					characterName = selected.characterName
				}

				tryLogin(charInfo)
			end
		end
	end
end

local function onLoginWait(message, time)
	CharacterList.destroyLoadBox()

	waitingWindow = g_ui.displayUI("waitinglist")

	local label = waitingWindow:getChildById("infoLabel")

	label:setText(message)

	updateWaitEvent = scheduleEvent(function()
		updateWait(g_clock.seconds(), g_clock.seconds() + time)
	end, 0)
	resendWaitEvent = scheduleEvent(resendWait, time * 1000)
end

function onGameLoginError(message)
	CharacterList.destroyLoadBox()

	errorBox = displayErrorBox(tr("Login Error"), message)

	function errorBox.onOk()
		errorBox = nil

		CharacterList.showAgain()
	end
end

function onGameLoginToken(unknown)
	CharacterList.destroyLoadBox()

	errorBox = displayErrorBox(tr("Two-Factor Authentification"), "A new authentification token is required.\nPlease login again.")

	function errorBox.onOk()
		errorBox = nil

		EnterGame.show()
	end
end

function onGameConnectionError(message, code)
	CharacterList.destroyLoadBox()

	if (not g_game.isOnline() or code ~= 2) and not errorBox then
		local text = translateNetworkError(code, g_game.getProtocolGame() and g_game.getProtocolGame():isConnecting(), message)

		errorBox = displayErrorBox(tr("Connection Error"), text)

		function errorBox.onOk()
			errorBox = nil

			CharacterList.showAgain()
		end
	end
end

function onGameUpdateNeeded(signature)
	CharacterList.destroyLoadBox()

	errorBox = displayErrorBox(tr("Update needed"), tr("Enter with your account again to update your client."))

	function errorBox.onOk()
		errorBox = nil

		CharacterList.showAgain()
	end
end

function onGameEnd()
	CharacterList.showAgain()
end

function onLogout()
	lastLogout = g_clock.millis()
end

function CharacterList.init()
	if USE_NEW_ENERGAME then
		return
	end

	connect(g_game, {
		onLoginError = onGameLoginError
	})
	connect(g_game, {
		onLoginToken = onGameLoginToken
	})
	connect(g_game, {
		onUpdateNeeded = onGameUpdateNeeded
	})
	connect(g_game, {
		onConnectionError = onGameConnectionError
	})
	-- Ao iniciar o jogo, esconda completamente a lista de personagens
	local function onGameStartHide()
		CharacterList.destroyLoadBox()
		CharacterList.hide(false)
	end
	connect(g_game, {
		onGameStart = onGameStartHide
	})
	connect(g_game, {
		onLoginWait = onLoginWait
	})
	connect(g_game, {
		onGameEnd = onGameEnd
	})
	connect(g_game, {
		onLogout = onLogout
	})

    -- Carregar favoritos antes de criar a lista para aplicar ordenação
    favorites = g_settings.getNode("favoritesCharacterList") or {}

    if G.characters then
        CharacterList.create(G.characters, G.characterAccount)
    end
end

function CharacterList.terminate()
	if USE_NEW_ENERGAME then
		return
	end

	disconnect(g_game, {
		onLoginError = onGameLoginError
	})
	disconnect(g_game, {
		onLoginToken = onGameLoginToken
	})
	disconnect(g_game, {
		onUpdateNeeded = onGameUpdateNeeded
	})
	disconnect(g_game, {
		onConnectionError = onGameConnectionError
	})
	disconnect(g_game, {
		onGameStart = CharacterList.destroyLoadBox
	})
	disconnect(g_game, {
		onLoginWait = onLoginWait
	})
	disconnect(g_game, {
		onGameEnd = onGameEnd
	})
	disconnect(g_game, {
		onLogout = onLogout
	})
	g_settings.setNode("favoritesCharacterList", favorites)

	if infoPanel then
		infoPanel:destroy()

		infoPanel = nil
	end

	if charactersWindow then
		characterList = nil

		charactersWindow:destroy()

		charactersWindow = nil
	end

	if loadBox then
		g_game.cancelLogin()
		loadBox:destroy()

		loadBox = nil
	end

	if waitingWindow then
		waitingWindow:destroy()

		waitingWindow = nil
	end

	if updateWaitEvent then
		removeEvent(updateWaitEvent)

		updateWaitEvent = nil
	end

	if resendWaitEvent then
		removeEvent(resendWaitEvent)

		resendWaitEvent = nil
	end

	if loginEvent then
		removeEvent(loginEvent)

		loginEvent = nil
	end

	CharacterList = nil
end

function CharacterList.createList(characters)
    characterList = charactersWindow:getChildById("characters")
    G.characters = characters

    characterList:destroyChildren()

    local focusLabel
    -- Pré-ordenar: favoritos primeiro (por newIndex), depois não favoritos na ordem original
    local favs, nonfavs = {}, {}
    for _, info in ipairs(characters) do
        if favorites[info.name] then
            table.insert(favs, info)
        else
            table.insert(nonfavs, info)
        end
    end
    table.sort(favs, function(a, b)
        local fa = favorites[a.name]
        local fb = favorites[b.name]
        local ia = (fa and fa.newIndex) or 1
        local ib = (fb and fb.newIndex) or 1
        if ia ~= ib then return ia < ib end
        return tostring(a.name) < tostring(b.name)
    end)
    local sorted = {}
    for _, info in ipairs(favs) do table.insert(sorted, info) end
    for _, info in ipairs(nonfavs) do table.insert(sorted, info) end

    for i, info in ipairs(sorted) do
        local widget = g_ui.createWidget("CharacterBox", characterList)
        local favoriteChar = favorites[info.name]
        if favoriteChar then widget.favorite:setOn(true) end

        widget:setId(info.name)

		widget.characterName = info.name
		widget.worldName = info.worldName
		widget.worldHost = info.worldIp
		widget.worldPort = info.worldPort

		local charName = info.name and tostring(info.name) or ''
		if charName == '' then
		charName = tr('Unknown')
		end
		widget.name:setText(charName or tr("Default"))
		widget.name:setVisible(true)
		widget.name:setHeight(24)
		widget.name:setWidth(260)
		widget.name:setColor('#FFFFFF')
        widget.level:setText(tr("Nv. %d", info.level or 1))
        -- Garantir que o nome do mundo seja exibido corretamente
        widget.world:setText(info.worldName or tr("Default"))
        widget.world:setVisible(true)
        widget.world:setHeight(20)
        widget.world:setColor('#FFFFFF')
		widget:setImageSource("/images/game/characters/" .. (info.sex == 0 and "female" or "male"))
		widget.clan:setImageSource("/images/game/icons/" .. (info.clan and iconsClan[tonumber(math.floor(info.clan))] or "icon_no_clan_20px"))
		connect(widget, {
			onDoubleClick = function()
				CharacterList.doLogin()
				return true
			end
		})

		if info.daysToDelete then
			local deleteMsg = info.daysToDelete > 0 and tr("em %d dias", info.daysToDelete) or tr("hoje")

			widget.cancel:setTooltip(tr("Seu personagem ser\xE1 exclu\xEDdo %s.\nClique aqui para cancelar o processo de exclus\xE3o.", deleteMsg))
		end

		widget.cancel:setVisible(info.daysToDelete)
		widget.delete:setVisible(not info.daysToDelete)

		function widget.delete.onClick()
			modules.game_accounts.showDeletePanel(info.name)
		end

		function widget.cancel.onClick()
			modules.game_accounts.showCancelDeletePanel(info.name, info.daysToDelete)
		end

        function widget.favorite:onClick()
            local favoriteChar = favorites[info.name]

            if favoriteChar then
                self:setOn(false)

                favorites[info.name] = nil

                local desired = favoriteChar.oldIndex or characterList:getChildIndex(widget)
                local count = characterList:getChildCount()
                if desired < 1 then desired = 1 end
                if desired > count then desired = count end
                characterList:moveChildToIndex(widget, desired)
            else
                favorites[info.name] = {
                    newIndex = 1,
                    oldIndex = characterList:getChildIndex(widget)
                }

                characterList:moveChildToIndex(widget, 1)
                self:setOn(true)
            end

            -- Renumera favoritos conforme ordem visível na UI (determinístico)
            local idx = 1
            for i = 1, characterList:getChildCount() do
                local child = characterList:getChildByIndex(i)
                if child and child.favorite and child.favorite:isOn() then
                    local name = child:getId()
                    if favorites[name] then
                        favorites[name].newIndex = idx
                    else
                        favorites[name] = { newIndex = idx, oldIndex = i }
                    end
                    idx = idx + 1
                end
            end

            -- Persiste imediatamente as preferências de favoritos
            g_settings.setNode("favoritesCharacterList", favorites)
        end

		if i == 1 or g_settings.get("last-used-character") == widget.characterName and g_settings.get("last-used-world") == widget.worldName then
			focusLabel = widget
		end
	end

	g_ui.createWidget("CharacterBoxCreate", characterList)

    if focusLabel then
        characterList:focusChild(focusLabel, KeyboardFocusReason)
        local labelId = focusLabel:getId()
        addEvent(function()
            local w = characterList:getChildById(labelId)
            if w then
                characterList:ensureChildVisible(w)
            end
        end)
    end
end

function CharacterList.create(characters, account, otui)
	otui = otui or "characterlist"

	if charactersWindow then
		charactersWindow:destroy()
	end

	charactersWindow = g_ui.displayUI(otui)
	G.characterAccount = account

	if not infoPanel then
		infoPanel = g_ui.createWidget("InfoCharacterPanel", rootWidget)

		infoPanel:addAnchor(AnchorTop, charactersWindow:getId(), AnchorTop)
		infoPanel:addAnchor(AnchorLeft, charactersWindow:getId(), AnchorRight)
	end

	CharacterList.createList(characters)

	local status = ""

	if account.status == AccountStatus.Frozen then
		status = tr(" (Frozen)")
	elseif account.status == AccountStatus.Suspended then
		status = tr(" (Suspended)")
	end

	infoPanel.warning:setVisible(account.daysToEmailChange)

	if account.daysToEmailChange then
		infoPanel.warning:setTooltip(tr("Restam %d dias para o seu e-mail ser trocado.", account.daysToEmailChange))
	end

	if account.subStatus == SubscriptionStatus.Free and account.premDays < 1 then
		infoPanel.accountStatus.image:setImageSource("/images/game/icons/icon_default_32px")
		infoPanel.accountStatus.status:setText(("%s%s"):format(tr("Free Account"), status))
	elseif account.premDays == 0 or account.premDays == 65535 then
		infoPanel.accountStatus.image:setIcon("/images/game/icons/icon_default_32px")
		infoPanel.accountStatus.status:setText(("%s%s"):format(tr("Gratis Vip Account"), status))
	else
		infoPanel.accountStatus.image:setIcon("/images/game/icons/icon_vip_32px")
		infoPanel.accountStatus.status:setText(("%d %s%s"):format(account.premDays, tr("Days of vip"), status))
	end
end

function CharacterList.destroy()
	CharacterList.hide(true)

	if charactersWindow then
		characterList = nil

		charactersWindow:destroy()

		charactersWindow = nil
	end

	if infoPanel then
		infoPanel:destroy()

		infoPanel = nil
	end
end

function CharacterList.show()
  if loadBox or errorBox or not charactersWindow then
    return
  end

  charactersWindow:show()
  charactersWindow:raise()
  charactersWindow:focus()
  CharacterList.showInfoPanel()
  -- Mostrar botão de logout somente enquanto a lista de personagens está visível
  local bg = modules.client_background.getBackground()
  if bg then
    local logoutButton = bg:getChildById('logoutButton')
    if logoutButton then logoutButton:show() end
  end
end

function CharacterList.hide(showLogin)
  showLogin = showLogin or false

  charactersWindow:hide()
  CharacterList.hideInfoPanel()
  modules.game_accounts.hideDeletePanel()
  modules.game_accounts.hideCancelDeletePanel()
  -- Oculta botão de logout quando sair da lista de personagens
  local bg = modules.client_background.getBackground()
  if bg then
    local logoutButton = bg:getChildById('logoutButton')
    if logoutButton then logoutButton:hide() end
  end

	if showLogin and EnterGame and not g_game.isOnline() then
		EnterGame.show()
	end
end

function CharacterList.showAgain()
	if characterList and characterList:hasChildren() then
		CharacterList.show()
	end
end

function CharacterList.isVisible()
	if charactersWindow and charactersWindow:isVisible() then
		return true
	end

	return false
end

function CharacterList.doLogin()
	local selected = characterList:getFocusedChild()

	if selected and not selected.createCharacter then
		local charInfo = {
			worldHost = selected.worldHost,
			worldPort = selected.worldPort,
			worldName = selected.worldName,
			characterName = selected.characterName
		}

		charactersWindow:hide()

		if loginEvent then
			removeEvent(loginEvent)

			loginEvent = nil
		end

		tryLogin(charInfo)
	elseif selected and selected.createCharacter then
		modules.game_accounts.showCharPanel()
	else
		displayErrorBox(tr("Error"), tr("You must select a character to login!"))
	end
end

function CharacterList.destroyLoadBox()
	if loadBox then
		loadBox:destroy()

		loadBox = nil
	end
end

function CharacterList.cancelWait()
	if waitingWindow then
		waitingWindow:destroy()

		waitingWindow = nil
	end

	if updateWaitEvent then
		removeEvent(updateWaitEvent)

		updateWaitEvent = nil
	end

	if resendWaitEvent then
		removeEvent(resendWaitEvent)

		resendWaitEvent = nil
	end

	CharacterList.destroyLoadBox()
	CharacterList.showAgain()
end

function CharacterList.hideInfoPanel()
	if infoPanel then
		infoPanel:hide()
	end
end

function CharacterList.showInfoPanel()
	if infoPanel then
		infoPanel:show()
	end
end
