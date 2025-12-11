-- chunkname: @/modules/game_accounts/accounts.lua

local accountPanel, activePanel, emailPanel, charPanel, waitPanel, deletePanel, cancelDeletePanel, changePasswordPanel, recoverPanel, termsPanel, accounts
-- Track last requests to update UI instantly
local lastCreateRequest = nil
local lastDeleteRequest = nil
local lastCancelDeleteRequest = nil

local function onHTTPResult(data, err)
    hideWaitPanel()

    if not data then
        return "", false
    end

    -- Normaliza status vindos da nossa API (string/boolean/numérico)
    if data.status then
        if type(data.status) == 'number' and table.contains({401, 403}, data.status) then
            return "Ocorreu um erro inesperado.\nPor favor, abra um ticket para entrar em contato com a equipe.", false
        end
        if type(data.status) == 'string' then
            local s = data.status:lower()
            if s == 'error' then
                return data.message or "", false
            elseif s == 'success' then
                return data.message or "", true
            end
        end
        if type(data.status) == 'boolean' then
            return (data.message or ""), data.status
        end
    end

	if data.errors then
		for i, errors in pairs(data.errors) do
			return table.concat(errors, ",\n"), false
		end

		return "", false
	end

    if data.message then
        -- Mensagem sem status explícito: assume sucesso
        return data.message, true
    end

    return "", false
end

-- Validação remota: infraestrutura de debounce e helpers
local validationEvents = {
    email = nil,
    confirmEmail = nil,
    password = nil,
    confirmPassword = nil,
    charName = nil
}

local function debounceField(fieldKey, fnc, delay)
    delay = delay or 250
    if validationEvents[fieldKey] then
        removeEvent(validationEvents[fieldKey])
        validationEvents[fieldKey] = nil
    end
    validationEvents[fieldKey] = scheduleEvent(fnc, delay)
end

local function updateHelperFromErrors(helperWidget, fieldKey, data, okText, errDefault)
    if not helperWidget then return end
    if not data then
        return setHelperFeedback(helperWidget, false, nil, errDefault or tr("Ocorreu um erro. Tente novamente."))
    end
    if data.errors and data.errors[fieldKey] and #data.errors[fieldKey] > 0 then
        return setHelperFeedback(helperWidget, false, nil, table.concat(data.errors[fieldKey], ",\n"))
    end
    return setHelperFeedback(helperWidget, true, okText or "", nil)
end

-- Formata tempo em mm:ss para labels de cooldown
local function formatTime(seconds)
    seconds = tonumber(seconds) or 0
    if seconds < 0 then seconds = 0 end
    local m = math.floor(seconds / 60)
    local s = math.floor(seconds % 60)
    return string.format("%02d:%02d", m, s)
end

local function onHTTPActive(data, err)
	local message, status = onHTTPResult(data, err)

	if not status and message:len() > 0 then
		displayInfoBox(tr("Warning"), message)
	end

	if status and message:len() > 0 then
		local display = displayInfoBox(tr("Verification account"), message)

		display.onOk = hideActivePanel
	end
end

local function onHTTPCodeActive(data, err)
	local message, status = onHTTPResult(data, err)

	if not status and message:len() > 0 then
		displayInfoBox(tr("Warning"), message)
	end

	if status and message:len() > 0 then
		displayInfoBox(tr("Verification account"), message)
	end
end

local function onHTTPChangeEmail(data, err)
	local message, status = onHTTPResult(data, err)

	if not status and message:len() > 0 then
		local display = displayInfoBox(tr("Warning"), message)

		display.onOk = hideEmailPanel
	end

	if status and message:len() > 0 then
		local display = displayInfoBox(tr("Change e-mail"), message)

		display.onOk = hideEmailPanel

		if message:find("canceled") then
			G.characterAccount.daysToEmailChange = nil
		else
			G.characterAccount.daysToEmailChange = 15
		end

		modules.client_options.enableAccountPanel()
	end
end

local function onHTTPCreate(data, err)
	local message, status = onHTTPResult(data, err)

	if not status and message:len() > 0 then
		local display = displayInfoBox(tr("Warning"), message)

		function display.onOk()
			accountPanel.window:show()
		end
	end

	if status and message:len() > 0 then
		local display = displayInfoBox(tr("Create account"), message)

		display.onOk = hideCreatePanel
	end
end

local function onHTTPCharacter(data, err)
    local message, status = onHTTPResult(data, err)

	if not status and message:len() > 0 then
		local display = displayInfoBox(tr("Warning"), message)

		function display.onOk()
			charPanel:show()
		end
	end

    if status and message:len() > 0 then
        -- Atualiza imediatamente a lista local sem depender de nova requisição
        if lastCreateRequest and modules.client_entergame2 and modules.client_entergame2.CharacterList and G then
            G.characters = G.characters or {}
            local worldName = nil
            if G.worlds then
                for _, w in ipairs(G.worlds) do
                    if w.id == lastCreateRequest.worldId then
                        worldName = w.name
                        break
                    end
                end
            end
            local info = {
                name = lastCreateRequest.name,
                level = 1,
                worldName = worldName or (G.serverName or ""),
                worldIp = G.defaultWorldHost,
                worldPort = G.defaultWorldPort,
                sex = (tonumber(lastCreateRequest.gender) == 1) and 1 or 0,
                clan = nil,
                daysToDelete = nil
            }
            table.insert(G.characters, info)
            modules.client_entergame2.CharacterList.createList(G.characters)
            lastCreateRequest = nil
        end

        -- Fecha lista antes de exibir mensagem, reabre depois
        if modules.client_entergame2 and modules.client_entergame2.CharacterList and modules.client_entergame2.CharacterList.hide then
            modules.client_entergame2.CharacterList.hide()
        end
        local display = displayInfoBox(tr("Create character"), message)
        function display.onOk()
            hideCharPanel()
            if modules.client_entergame2 and modules.client_entergame2.CharacterList then
                modules.client_entergame2.CharacterList.show()
                modules.client_entergame2.CharacterList.createList(G.characters or {})
            end
        end
    end
end

local function onHTTPDeleteCharacter(data, err)
    local message, status = onHTTPResult(data, err)

	if not status and message:len() > 0 then
		displayInfoBox(tr("Warning"), message)
	end

    if status and message:len() > 0 then
        -- Fecha lista antes de exibir mensagem
        if modules.client_entergame2 and modules.client_entergame2.CharacterList and modules.client_entergame2.CharacterList.hide then
            modules.client_entergame2.CharacterList.hide()
        end
        local display = displayInfoBox(tr("Delete character"), message)
        -- Remove localmente para refletir imediatamente
        if lastDeleteRequest and G and G.characters and modules.client_entergame2 and modules.client_entergame2.CharacterList then
            for i = #G.characters, 1, -1 do
                if G.characters[i].name == lastDeleteRequest then
                    table.remove(G.characters, i)
                    break
                end
            end
            modules.client_entergame2.CharacterList.createList(G.characters)
            lastDeleteRequest = nil
        end
        -- Sincroniza com servidor
        getCharacters()
        -- Ao fechar o aviso, reabrir lista
        function display.onOk()
            if modules.client_entergame2 and modules.client_entergame2.CharacterList then
                modules.client_entergame2.CharacterList.show()
                modules.client_entergame2.CharacterList.createList(G.characters or {})
            end
        end
    end
end

local function onHTTPCancelDeleteCharacter(data, err)
	local message, status = onHTTPResult(data, err)

	if not status and message:len() > 0 then
		displayInfoBox(tr("Warning"), message)
	end

	if status and message:len() > 0 then
		displayInfoBox(tr("Cancel delete character"), message)
		getCharacters()
	end
end

local function onHTTPChangePassword(data, err)
	local message, status = onHTTPResult(data, err)

	if not status and message:len() > 0 then
		local display = displayInfoBox(tr("Warning"), message)

		display.onOk = hidePasswordChangePanel
	end

	if status and message:len() > 0 then
		local display = displayInfoBox(tr("Change password"), message)

		display.onOk = hidePasswordChangePanel
	end
end

local function onHTTPRecoverAccount(data, err)
	local message, status = onHTTPResult(data, err)

	if not status and message:len() > 0 then
		local display = displayInfoBox(tr("Warning"), message)

		display.onOk = hideRecoverPanel
	end

	if status and message:len() > 0 then
		local display = displayInfoBox(tr("Recover account"), message)

		display.onOk = hideRecoverPanel
	end
end

local function onHTTPRecoverCodeAccount(data, err)
	local message, status = onHTTPResult(data, err)

	if not status and message:len() > 0 then
		displayInfoBox(tr("Warning"), message)
	end

	if status and message:len() > 0 then
		displayInfoBox(tr("Recover account"), message)
	end
end

local function onHTTPCharacters(data, err)
	if not data then
		return
	end

    if data.body then
        modules.client_entergame2.CharacterList.createList(data.body)
    end
end

function getCharacters()
	accounts:getCharacters(onHTTPCharacters)
end

function sendActive(key)
	accounts:active(key, onHTTPActive)
end

function sendCodeEmail()
	accounts:sendCodeEmail(onHTTPCodeActive)
end

function sendChangeEmail(email)
	accounts:changeEmail(email, onHTTPChangeEmail)
end

function sendCancelChangeEmail()
	accounts:cancelChangeEmail(onHTTPChangeEmail)
end

function sendCreate(email, password)
	accounts:create(email, password, onHTTPCreate)
end

function sendCreateCharacter(name, gender, worldId)
	accounts:createCharacter(name, gender, worldId, onHTTPCharacter)
end

function sendDeleteCharacter(name)
	accounts:deleteCharacter(name, onHTTPDeleteCharacter)
end

function sendCancelDeleteCharacter(name)
	accounts:cancelDeleteCharacter(name, onHTTPCancelDeleteCharacter)
end

function sendChangePassword(oldPassword, newPassword, repeatPassword)
	accounts:changePassword(oldPassword, newPassword, repeatPassword, onHTTPChangePassword)
end

function sendRecoverAccount(email, code, newPassword, repeatPassword)
	accounts:changeRecoverPassword(email, code, newPassword, repeatPassword, onHTTPRecoverAccount)
end

function sendRecoverCodeEmail(email)
	accounts:recoverCodeEmail(email, onHTTPRecoverCodeAccount)
end

local function hide(widget)
	if widget then
		widget:destroy()

		widget = nil
	end
end

local function show(ui, widget)
	hide(widget)

	return g_ui.createWidget(ui, rootWidget)
end

function init()
	g_ui.importStyle("ui/terms.otui")
	g_ui.importStyle("ui/changeEmail.otui")
	g_ui.importStyle("ui/activeAccount.otui")
	g_ui.importStyle("ui/createAccount.otui")
	g_ui.importStyle("ui/createCharacter.otui")
	g_ui.importStyle("ui/deleteCharacter.otui")
	g_ui.importStyle("ui/changePassword.otui")
	g_ui.importStyle("ui/recoverAccount.otui")

	accounts = modules.game_api.Accounts.new()



	
end

function terminate()
    -- Use the specific hide helpers to destroy and clear references
    hideActivePanel()
    hideEmailPanel()
    hideCreatePanel()
    hideWaitPanel()
    hideCharPanel()
    hideDeletePanel()
    hideCancelDeletePanel()
    hidePasswordChangePanel()
    hideRecoverPanel()
    hideTermsPanel()
end

function showActivePanel()
	activePanel = show("AccountValidationPanel", activePanel)

	local childrens = activePanel.window.panel:getChildren()
	local panel = activePanel.window.panel
	local sendButton = activePanel.window.sendButton

	function activePanel.pasteCode()
		local code = g_window.getClipboardText()

		for i, input in ipairs(childrens) do
			scheduleEvent(function()
				input:setText(string.sub(code, i, i))
			end, i * #code)
		end
	end

	g_keyboard.bindKeyDown("Ctrl+V", activePanel.pasteCode, activePanel)

	for i, input in ipairs(childrens) do
		if i > 1 then
			input:disable()
		end

		function input:onTextChange(text)
			local prevInput = panel:getChildBefore(self)
			local nextInput = panel:getChildAfter(self)
			local textLength = text:trim():len()
				print('textLength', textLength, 'text', text)
			if textLength > 1 then
				self:clearText()

				return
			end

			if nextInput and nextInput:isDisabled() and textLength > 0 then
				nextInput:enable()
				scheduleEvent(function()
					nextInput:focus()
					nextInput:setCursorPos(-1)
				end, 30)
			end

			local enableSendButton = i == #childrens and self:isEnabled() and textLength > 0
			print('enableSendButton', enableSendButton)
			sendButton:setEnabled(enableSendButton)
		end

		function input:onKeyUp(keyCode)
			if keyCode ~= KeyBackspace then
				return
			end

			for j, input2 in ipairs(childrens) do
				local prevInput = panel:getChildBefore(self)

				if j >= i and prevInput then
					input2:disable()
					input2:clearText()
					scheduleEvent(function()
						prevInput:focus()
						prevInput:setCursorPos(-1)
					end, 30)
				end
			end
		end
	end

	panel:focusChild(childrens[1])
end

function showEmailPanel()
	emailPanel = show("AccountChangeEmailPanel", emailPanel)
end

function showAccountPanel()
    accountPanel = show("AccountCreatePanel", accountPanel)

    -- Evita erro se o módulo de login não estiver carregado
    if modules.client_entergame2 and modules.client_entergame2.toggle then
        modules.client_entergame2.toggle()
    end

    -- Inicializa mensagens dos helpers ao abrir o painel
    if accountPanel and accountPanel.window then
        local w = accountPanel.window

        if w.helperEmail then
            setHelperFeedback(w.helperEmail, false, nil, tr("Preencha este campo."))
        end
        if w.helperConfirmEmail then
            setHelperFeedback(w.helperConfirmEmail, false, nil, tr("Preencha este campo."))
        end
        if w.helperPassword then
            setHelperFeedback(w.helperPassword, false, nil, tr("Preencha este campo."))
        end
        if w.helperConfirmPassword then
            setHelperFeedback(w.helperConfirmPassword, false, nil, tr("Preencha este campo."))
        end
    end
end

function showWaitPanel()
	waitPanel = show("WaitPanel", waitPanel)
end

function showCharPanel()
    charPanel = show("CreateCharacterWindow", charPanel)

    -- Reinicializa o grupo de gênero evitando manter referências antigas
    if genderGroup then
        genderGroup:destroy()
        genderGroup = nil
    end

    genderGroup = UIRadioGroup.create()

	for i, panel in pairs(charPanel.genderPanel:getChildren()) do
		genderGroup:addWidget(panel)
	end

    charPanel.worlds:clear()

    if G.worlds and table.size(G.worlds) > 0 then
        for i, world in pairs(G.worlds) do
            charPanel.worlds:addOption(world.name, world.id, nil, world.new and "/images/game/icons/newserv")
        end
    else
        -- Evita falha se mundos ainda no foram carregados
        charPanel.worlds:addOption(tr("Default"), 0)
    end

    if CharacterList and CharacterList.hide then
        CharacterList.hide()
    end
    genderGroup:selectWidget(genderGroup:getFirstWidget())
end

function showDeletePanel(name)
    local title = tr("Delete character")
    local message = tr("Você realmente deseja excluir este personagem?") .. "\n\n" ..
        "{#FFDA2B|" .. tr("Importante: Seu personagem será deletado após 7 dias.") .. "}" .. "\n" ..
        "{#FFDA2B|" .. tr("Caso se arrependa, você poderá cancelar a exclusão do personagem durante este período,") .. "}" .. "\n" ..
        "{#FFDA2B|" .. tr("após o décimo quinto dia o processo se torna irreversível.") .. "}"

    local box

    local function onConfirm()
        lastDeleteRequest = name
        sendDeleteCharacter(name)
        if box then box:ok() end
    end

    local function onCancel()
        if box then box:cancel() end
    end

    local buttons = {
        { color = "Blue", text = tr("Confirm"), callback = onConfirm },
        { color = "Red",  text = tr("Cancel"),  callback = onCancel }
    }

    box = displayGeneralBox(title, message, buttons, onConfirm, onCancel)
end

function showCancelDeletePanel(name, dayToDelete)
    cancelDeletePanel = show("CancelCharacterDeletionWindow", cancelDeletePanel)

	cancelDeletePanel.dayLabel:setText(tr("Restam %d dias para seu personagem ser exclu\xEDdo", dayToDelete))

    function cancelDeletePanel.confirmButton.onClick()
        hideCancelDeletePanel()
        -- Atualização local otimista: limpa flag de exclusão
        lastCancelDeleteRequest = name
        if G and G.characters and modules.client_entergame2 and modules.client_entergame2.CharacterList then
            for i = 1, #G.characters do
                local c = G.characters[i]
                if c.name == name and c.daysToDelete then
                    c.daysToDelete = nil
                    break
                end
            end
            modules.client_entergame2.CharacterList.createList(G.characters)
            lastCancelDeleteRequest = nil
        end
        sendCancelDeleteCharacter(name)
    end
end

function showPasswordPanel()
	changePasswordPanel = show("ChangePasswordPanel", changePasswordPanel)

    -- Conecta validação local + remota (mesma verificação da criação de conta)
    if changePasswordPanel and changePasswordPanel.window then
        local w = changePasswordPanel.window
        if w.passwordInput then
            w.passwordInput.onTextChange = function(self, text)
                -- Validação local
                onInputPassword(self)
                if w.confirmPasswordInput then
                    onInputConfirmPassword(self, w.confirmPasswordInput)
                end
                -- Validação remota (complexidade de senha)
                local txt = self:getText()
                debounceField('password', function()
                    local payload = { password = txt }
                    accounts:validateRegister(payload, function(data, err)
                        updateHelperFromErrors(w.helperPasswordInput, 'password', data, tr("Senha válida"))
                    end)
                end)
            end
        end

        if w.confirmPasswordInput then
            w.confirmPasswordInput.onTextChange = function(self, text)
                -- Validação local
                if w.passwordInput then
                    onInputConfirmPassword(w.passwordInput, self)
                end
                -- Validação remota (senhas coincidem)
                local password = w.passwordInput and w.passwordInput:getText() or ""
                local confirm  = self:getText()
                debounceField('confirmPassword', function()
                    local payload = { password = password, confirmPassword = confirm }
                    accounts:validateRegister(payload, function(data, err)
                        updateHelperFromErrors(w.helperConfirmPasswordInput, 'confirmPassword', data, tr("Senhas coincidem"))
                    end)
                end)
            end
        end
    end
end

function showRecoverPanel()
	recoverPanel = show("RecoverAccountPanel", recoverPanel)

    -- Conecta validação local + remota para senha nova
    if recoverPanel and recoverPanel.window then
        local w = recoverPanel.window
        if w.passwordInput then
            w.passwordInput.onTextChange = function(self, text)
                -- Validação local
                onInputPassword(self)
                if w.confirmPasswordInput then
                    onInputConfirmPassword(self, w.confirmPasswordInput)
                end
                -- Validação remota (complexidade)
                local txt = self:getText()
                debounceField('password', function()
                    local payload = { password = txt }
                    accounts:validateRegister(payload, function(data, err)
                        updateHelperFromErrors(w.helperPasswordInput, 'password', data, tr("Senha válida"))
                    end)
                end)
            end
        end

        if w.confirmPasswordInput then
            w.confirmPasswordInput.onTextChange = function(self, text)
                -- Validação local
                if w.passwordInput then
                    onInputConfirmPassword(w.passwordInput, self)
                end
                -- Validação remota (match)
                local password = w.passwordInput and w.passwordInput:getText() or ""
                local confirm  = self:getText()
                debounceField('confirmPassword', function()
                    local payload = { password = password, confirmPassword = confirm }
                    accounts:validateRegister(payload, function(data, err)
                        updateHelperFromErrors(w.helperConfirmPasswordInput, 'confirmPassword', data, tr("Senhas coincidem"))
                    end)
                end)
            end
        end
    end
end

function showTermsPanel()
	termsPanel = show("TermRules", termsPanel)

	for i, value in pairs(TERMSANDRULES) do
		if value.title then
			local title = g_ui.createWidget("LabelTitleTermRules", termsPanel.list)

			title:setText(value.title)
		end

		if value.text then
			local text = g_ui.createWidget("LabelBodyTermRules", termsPanel.list)

			text:setText(value.text)
		end
	end
end

function hideActivePanel()
    if activePanel then
        -- Unbind shortcut before destroying the widget to avoid dangling references
        g_keyboard.unbindKeyDown("Ctrl+V", activePanel.pasteCode, activePanel)
    end
    hide(activePanel)
    activePanel = nil
end

function hideEmailPanel()
    hideWaitPanel()
    hide(emailPanel)
    emailPanel = nil
end

function hideCreatePanel()
    hideWaitPanel()
    -- Desconecta callbacks e cancela validações pendentes para evitar referências a helpers
    if accountPanel and accountPanel.window then
        local w = accountPanel.window
        if w.emailInput then w.emailInput.onTextChange = nil end
        if w.confirmEmailInput then w.confirmEmailInput.onTextChange = nil end
        if w.passwordInput then w.passwordInput.onTextChange = nil end
        if w.confirmPasswordInput then w.confirmPasswordInput.onTextChange = nil end
        -- Cancela qualquer event associado ao painel
        if accountPanel.event then
            removeEvent(accountPanel.event)
            accountPanel.event = nil
        end
    end
    -- Cancela eventos de debounce usados nas validações remotas
    if validationEvents then
        for k, ev in pairs(validationEvents) do
            if ev then
                removeEvent(ev)
                validationEvents[k] = nil
            end
        end
    end
    hideTermsPanel()
    hide(accountPanel)
    accountPanel = nil
    -- Evita tentar acessar módulo não carregado durante unload
    if modules.client_entergame2 and modules.client_entergame2.toggle then
        modules.client_entergame2.toggle()
    end
end

function hideWaitPanel()
    hide(waitPanel)
    waitPanel = nil
end

function hideCharPanel()
    -- Cancela valida es pendentes para evitar referencias de widgets destrudos
    if validationEvents then
        for k, ev in pairs(validationEvents) do
            if ev then
                removeEvent(ev)
                validationEvents[k] = nil
            end
        end
    end

    -- Limpa foco e referência global se o nameInput estiver ativo
    if charPanel and charPanel.nameInput then
        -- Evita novas validações após esconder
        charPanel.nameInput.onTextChange = nil
        if charPanel.nameInput.clearFocus then
            charPanel.nameInput:clearFocus()
        end
        if rootWidget and rootWidget.currentTextEdit == charPanel.nameInput then
            rootWidget.currentTextEdit = nil
        end
    end

    -- Libera referências do grupo de rádio antes de destruir os widgets filhos
    if genderGroup then
        genderGroup:destroy()
        genderGroup = nil
    end

    hide(charPanel)
    charPanel = nil
    if CharacterList and CharacterList.show then
        CharacterList.show()
    end
end

function hideDeletePanel()
    hide(deletePanel)
    deletePanel = nil
end

function hideCancelDeletePanel()
    hide(cancelDeletePanel)
    cancelDeletePanel = nil
end

function hidePasswordChangePanel()
    hideWaitPanel()
    -- Desconecta callbacks de texto para evitar refer\xEAncias pendentes
    if changePasswordPanel and changePasswordPanel.window then
        local w = changePasswordPanel.window
        if w.passwordInput then w.passwordInput.onTextChange = nil end
        if w.confirmPasswordInput then w.confirmPasswordInput.onTextChange = nil end
        if w.oldPasswordInput then w.oldPasswordInput.onTextChange = nil end
        -- Cancela qualquer event associado aos inputs
        if w.passwordInput and w.passwordInput.event then removeEvent(w.passwordInput.event) w.passwordInput.event = nil end
        if w.confirmPasswordInput and w.confirmPasswordInput.event then removeEvent(w.confirmPasswordInput.event) w.confirmPasswordInput.event = nil end
        if w.oldPasswordInput and w.oldPasswordInput.event then removeEvent(w.oldPasswordInput.event) w.oldPasswordInput.event = nil end
    end
    -- Cancel any pending validation events to avoid dangling widget references
    if validationEvents then
        for k, ev in pairs(validationEvents) do
            if ev then
                removeEvent(ev)
                validationEvents[k] = nil
            end
        end
    end
    -- Cancela cooldown/efeitos pendentes no painel, se houver
    if changePasswordPanel and changePasswordPanel.event then
        removeEvent(changePasswordPanel.event)
        changePasswordPanel.event = nil
    end
    hide(changePasswordPanel)
    changePasswordPanel = nil
end

function hideRecoverPanel()
    -- Desconecta callbacks de texto para evitar refer\xEAncias pendentes
    if recoverPanel and recoverPanel.window then
        local w = recoverPanel.window
        if w.passwordInput then w.passwordInput.onTextChange = nil end
        if w.confirmPasswordInput then w.confirmPasswordInput.onTextChange = nil end
        if w.emailInput then w.emailInput.onTextChange = nil end
        -- Cancela qualquer event associado aos inputs
        if w.passwordInput and w.passwordInput.event then removeEvent(w.passwordInput.event) w.passwordInput.event = nil end
        if w.confirmPasswordInput and w.confirmPasswordInput.event then removeEvent(w.confirmPasswordInput.event) w.confirmPasswordInput.event = nil end
        if w.emailInput and w.emailInput.event then removeEvent(w.emailInput.event) w.emailInput.event = nil end
    end
    -- Cancel any pending validation events before destroying recover panel
    if validationEvents then
        for k, ev in pairs(validationEvents) do
            if ev then
                removeEvent(ev)
                validationEvents[k] = nil
            end
        end
    end
    -- Cancela cooldown/efeitos pendentes no painel (timer)
    if recoverPanel and recoverPanel.event then
        removeEvent(recoverPanel.event)
        recoverPanel.event = nil
    end
    hide(recoverPanel)
    recoverPanel = nil
end

function hideTermsPanel()
    hide(termsPanel)
    termsPanel = nil
end

function onChangeEmail()
	if onInputEmail(emailPanel.window.emailInput) then
		local function onConfirm()
			showWaitPanel()
			sendChangeEmail(emailPanel.window.emailInput:getText())
		end

		local function onCancel()
			emailPanel.window:show()
		end

		emailPanel.window:hide()
		displayConfirmBox(tr("Change e-mail"), tr("Voc\xEA realmente deseja solicitar a altera\xE7\xE3o de e-mail?"), onConfirm, onCancel)
	end
end

function onCancelChangeEmail()
	if not G.characterAccount.daysToEmailChange then
		return displayInfoBox(tr("Cancel change e-mail"), tr("Voc\xEA n\xE3o pode pedir o cancelamento da\ntroca de e-mail, pois nenhuma altera\xE7\xE3o foi solicitada."))
	end

	displayConfirmBox(tr("Cancel change e-mail"), tr("Voc\xEA realmente deseja cancelar a troca de e-mail?"), sendCancelChangeEmail)
end

function onActive()
	local code = ""

	for i, input in ipairs(activePanel.window.panel:getChildren()) do
		code = code .. input:getText()
	end

	if code:len() > 0 then
		sendActive(code)
	end
end

function onCodeEmail()
	local display = displayInfoBox(tr("C\xF3digo reenviado"), tr("Um c\xF3digo foi enviado para o seu e-mail. O c\xF3digo \xE9\nv\xE1lido por apenas 5 minutos."))

	local function onResendCode()
		local params = {
			onStart = function(cooldown)
				activePanel.window.timerLabel:disable()

				return true
			end,
			onExecute = function(cooldown)
				if activePanel.window then
					activePanel.window.timerLabel:setText(tr("Enviar c\xF3digo novamente em %s", formatTime(cooldown)))
				end

				return true
			end,
			onEnd = function(cooldown)
				activePanel.window.timerLabel:enable()
				activePanel.window.timerLabel:setText(tr("Reenviar c\xF3digo"))

				return true
			end
		}

		g_effects.onCooldown(activePanel, 120, params)
	end

	local function onOk()
		onResendCode()
		sendCodeEmail()
		activePanel.window:show()
	end

	display.onOk = onOk

	activePanel.window:hide()
end

function onCreate()
    if not accountPanel or not accountPanel.window then return end
    if not accountPanel.window.acceptTerm:isChecked() then
        return displayInfoBox(tr("Warning"), tr("Primeiro Voc\xEA precisa aceitar o termos e regras."))
    end

    local email = accountPanel.window.emailInput:getText()
    local password = accountPanel.window.passwordInput:getText()
    showWaitPanel()
    accountPanel.window:hide()
    -- A API realizará toda a validação e devolverá erros detalhados
    sendCreate(email, password)
end

-- Última solicitação de criação (para atualizar lista localmente)

function onCreateCharacter()
    local name = charPanel.nameInput:getText()
    local genderId = genderGroup:getSelectedWidget():getId()
    local worldId = charPanel.worlds:getCurrentOption().data
    showWaitPanel()
    charPanel:hide()
    -- Armazena dados para atualizar a lista sem relogar
    lastCreateRequest = { name = name, gender = genderId, worldId = worldId }
    -- Validação final na API
    sendCreateCharacter(name, genderId, worldId)
end

function onChangePassword()
	local canChange = onInputPassword(changePasswordPanel.window.passwordInput) and onInputConfirmPassword(changePasswordPanel.window.passwordInput, changePasswordPanel.window.confirmPasswordInput)

	if canChange then
		local function onConfirm()
			showWaitPanel()
			sendChangePassword(changePasswordPanel.window.oldPasswordInput:getText(), changePasswordPanel.window.passwordInput:getText(), changePasswordPanel.window.confirmPasswordInput:getText())
		end

		local function onCancel()
			changePasswordPanel.window:show()
		end

		changePasswordPanel.window:hide()
		displayConfirmBox(tr("Change password"), tr("Voc\xEA realmente deseja alterar o password?"), onConfirm, onCancel)
	end
end

function onSendRecoverCodeEmail()
	if not onInputEmail(recoverPanel.windowEmail.emailInput) then
		return
	end

	local display = displayInfoBox(tr("C\xF3digo reenviado"), tr("Um c\xF3digo foi enviado para o seu e-mail. O c\xF3digo \xE9\nv\xE1lido por apenas 5 minutos."))

	local function startRecoverCooldown()
		if not recoverPanel or not recoverPanel.window or not recoverPanel.window.timerLabel then return end
		local params = {
			onStart = function(cooldown)
				recoverPanel.window.timerLabel:disable()
				return true
			end,
			onExecute = function(cooldown)
				if recoverPanel and recoverPanel.window then
					recoverPanel.window.timerLabel:setText(tr("Enviar c\xF3digo novamente em %s", formatTime(cooldown)))
				end
				return true
			end,
			onEnd = function(cooldown)
				if recoverPanel and recoverPanel.window then
					recoverPanel.window.timerLabel:enable()
					recoverPanel.window.timerLabel:setText(tr("Enviar c\xF3digo por e-mail"))
				end
				return true
			end
		}
		g_effects.onCooldown(recoverPanel, 60, params)
	end

	local function onOk()
		recoverPanel.window:show()
		sendRecoverCodeEmail(recoverPanel.windowEmail.emailInput:getText())
		recoverPanel.window.emailInput:setText(recoverPanel.windowEmail.emailInput:getText())
		-- Inicia cooldown imediatamente ap\xF3s primeiro envio
		startRecoverCooldown()
	end

	display.onOk = onOk

	recoverPanel.windowEmail:hide()
end

function onRecoverCodeEmail()
	if not onInputEmail(recoverPanel.window.emailInput) then
		return
	end

	local display = displayInfoBox(tr("C\xF3digo reenviado"), tr("Um c\xF3digo foi enviado para o seu e-mail. O c\xF3digo \xE9\nv\xE1lido por apenas 5 minutos."))

	local function startRecoverCooldown()
		if not recoverPanel or not recoverPanel.window or not recoverPanel.window.timerLabel then return end
		local params = {
			onStart = function(cooldown)
				recoverPanel.window.timerLabel:disable()
				return true
			end,
			onExecute = function(cooldown)
				if recoverPanel and recoverPanel.window then
					recoverPanel.window.timerLabel:setText(tr("Enviar c\xF3digo novamente em %s", formatTime(cooldown)))
				end
				return true
			end,
			onEnd = function(cooldown)
				if recoverPanel and recoverPanel.window then
					recoverPanel.window.timerLabel:enable()
					recoverPanel.window.timerLabel:setText(tr("Enviar c\xF3digo por e-mail"))
				end
				return true
			end
		}
		g_effects.onCooldown(recoverPanel, 60, params)
	end

	local function onOk()
		startRecoverCooldown()
		recoverPanel.window:show()
		sendRecoverCodeEmail(recoverPanel.window.emailInput:getText())
	end

	display.onOk = onOk

	recoverPanel.window:hide()
end

function onConfirmRecoverAccount()
	local canRecover = onInputEmail(recoverPanel.window.emailInput) and onInputRequired(recoverPanel.window.codeInput) and onInputPassword(recoverPanel.window.passwordInput) and onInputConfirmPassword(recoverPanel.window.passwordInput, recoverPanel.window.confirmPasswordInput)

	if canRecover then
		sendRecoverAccount(recoverPanel.window.emailInput:getText(), recoverPanel.window.codeInput:getText(), recoverPanel.window.passwordInput:getText(), recoverPanel.window.confirmPasswordInput:getText())
	end
end
-- Atualiza helper label com cor conforme validade
function setHelperFeedback(labelWidget, isValid, successText, errorText)
    if not labelWidget then return end
    if isValid then
        labelWidget:setText(successText or "")
        labelWidget:setColor("#6DFFB0")
    else
        labelWidget:setText(errorText or "")
        labelWidget:setColor("#F83930")
    end
end

-- Handlers de digitação: e-mail
function onEmailTyping(input)
    local txt = input:getText()
    local helper = accountPanel and accountPanel.window and accountPanel.window.helperEmail
    debounceField('email', function()
        local payload = { email = txt }
        accounts:validateRegister(payload, function(data, err)
            updateHelperFromErrors(helper, 'email', data, tr("E-mail v\xE1lido"))
        end)
    end)
end

-- Handlers de digitação: confirmar e-mail
function onConfirmEmailTyping(confirmInput)
    local emailInput = accountPanel and accountPanel.window and accountPanel.window.emailInput
    local helper = accountPanel and accountPanel.window and accountPanel.window.helperConfirmEmail
    if not emailInput then return end
    local email = emailInput:getText()
    local confirm = confirmInput:getText()
    debounceField('confirmEmail', function()
        local payload = { email = email, confirmEmail = confirm }
        accounts:validateRegister(payload, function(data, err)
            updateHelperFromErrors(helper, 'confirmEmail', data, tr("E-mails coincidem"))
        end)
    end)
end

-- Handlers de digitação: senha
function onPasswordTyping(input)
    local txt = input:getText()
    local helper = accountPanel and accountPanel.window and accountPanel.window.helperPassword
    debounceField('password', function()
        local payload = { password = txt }
        accounts:validateRegister(payload, function(data, err)
            if data and data.errors and data.errors.password and #data.errors.password > 0 then
                return setHelperFeedback(helper, false, nil, table.concat(data.errors.password, ",\n"))
            end
            return setHelperFeedback(helper, true, tr("Senha v\xE1lida"))
        end)
    end)
end

-- Handlers de digitação: confirmar senha
function onConfirmPasswordTyping(confirmInput)
    local passwordInput = accountPanel and accountPanel.window and accountPanel.window.passwordInput
    local helper = accountPanel and accountPanel.window and accountPanel.window.helperConfirmPassword
    if not passwordInput then return end
    local password = passwordInput:getText()
    local confirm = confirmInput:getText()
    debounceField('confirmPassword', function()
        local payload = { password = password, confirmPassword = confirm }
        accounts:validateRegister(payload, function(data, err)
            updateHelperFromErrors(helper, 'confirmPassword', data, tr("Senhas coincidem"))
        end)
    end)
end

-- Validação remota do nome do personagem
function onNameTyping(input)
    local txt = input:getText()
    debounceField('charName', function()
        accounts:validateCharacter(txt, function(data, err)
            -- Obtém helper dinamicamente para evitar manter referência após destruir UI
            local helper = charPanel and charPanel.helperNameInput
            if helper then
                updateHelperFromErrors(helper, 'name', data, tr("Nome v\xE1lido"))
            end
        end)
    end)
end
