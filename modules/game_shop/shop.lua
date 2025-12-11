-- chunkname: @/modules/game_shop/shop.lua

local SHOP_EXTENTED_OPCODE = 201

shop = nil

local otcv8shop = false
local shopButton, msgWindow
local browsingHistory = false
local pixWindow, qrCodeWindow, pix
local storeUrl = ""
local coinsPacketSize = 0
local CATEGORIES = {}
local HISTORY = {}
local STATUS = {}
local AD = {}
local selectedOffer = {}
local IMAGE_PATH = "/images/game/shop/categories/"
local IMAGE_CATEGORY = {
	Accounts = IMAGE_PATH .. "conta",
	Items = IMAGE_PATH .. "itens",
	Teams = IMAGE_PATH .. "teams",
	Outfits = IMAGE_PATH .. "outfits",
	Addons = IMAGE_PATH .. "addons",
	Packs = IMAGE_PATH .. "destaque",
	Streamers = IMAGE_PATH .. "streamers"
}

-- Flag para habilitar dados mockados do Shop (somente interface)
local USE_MOCK_SHOP = true

local function buildMockStatus()
    return {
        points = "P-Bucks: 9999",
        ad = {
            text = "Promoção: Itens com 50% de desconto nesta semana!",
            url = nil,
            image = nil
        },
        buyUrl = nil
    }
end

local function buildMockCategories()
    -- Helper para criar ofertas simples
    local function itemOffer(id, name, price, desc)
        return {
            id = id,
            item = id,
            name = name,
            price = price,
            description = desc or ("Pacote contendo o item " .. tostring(id))
        }
    end

    local function imageOffer(id, name, price, desc)
        return {
            id = id,
            image = "/images/ui/windows/menu/IconInventory", -- usa um ícone genérico disponível
            name = name,
            price = price,
            description = desc or name
        }
    end

    local function outfitOffer(id, name, price, outfit)
        return {
            id = id,
            outfit = outfit,
            name = name,
            price = price,
            description = name
        }
    end

    local categories = {
        { name = "Accounts", offers = {
            imageOffer(1001, "Change Name", 50, "Altere o nome do personagem."),
            imageOffer(1002, "Change Sex", 30, "Altere o sexo do personagem."),
            imageOffer(1003, "Character Slot", 100, "Desbloqueia 1 novo slot de personagem."),
            imageOffer(1004, "Premium 30d", 300, "Premium por 30 dias.")
        }},
        { name = "Items", offers = {
            itemOffer(2160, "Crystal Coin x10", 25, "10 moedas cristal."),
            itemOffer(2379, "Magic Sword", 120, "Espada mágica + crit."),
            itemOffer(2393, "Giant Sword", 95, "Espada gigante."),
            itemOffer(2195, "Boots of Haste", 80, "Aumenta velocidade.")
        }},
        { name = "Teams", offers = {
            imageOffer(2001, "Team Banner: Wolves", 60, "Estandarte temático do time Wolves."),
            imageOffer(2002, "Team Banner: Dragons", 60, "Estandarte temático do time Dragons."),
            imageOffer(2003, "Team Emote Pack", 45, "Pacote com 10 emotes.")
        }},
        { name = "Outfits", offers = {
            outfitOffer(3001, "Outfit: Citizen", 70, { type = 128, addons = 3, head = 78, body = 69, legs = 58, feet = 76 }),
            outfitOffer(3002, "Outfit: Hunter", 90, { type = 129, addons = 3, head = 94, body = 86, legs = 66, feet = 75 }),
            outfitOffer(3003, "Outfit: Mage", 110, { type = 130, addons = 3, head = 95, body = 87, legs = 67, feet = 77 })
        }},
        { name = "Addons", offers = {
            imageOffer(4001, "Addon: Wings", 55, "Adiciona asas ao seu outfit."),
            imageOffer(4002, "Addon: Aura", 65, "Adiciona aura brilhante."),
            imageOffer(4003, "Addon: Cape", 45, "Adiciona capa estilosa.")
        }},
        { name = "Packs", offers = {
            imageOffer(5001, "Starter Pack", 150, "Pacote inicial com recursos úteis."),
            imageOffer(5002, "PvP Pack", 220, "Itens focados em PvP."),
            imageOffer(5003, "Farmer Pack", 130, "Recursos para hunts.")
        }},
        { name = "Streamers", offers = {
            imageOffer(6001, "Support Streamer A", 20, "Apoie nosso streamer A."),
            imageOffer(6002, "Support Streamer B", 20, "Apoie nosso streamer B."),
            imageOffer(6003, "Support Streamer C", 20, "Apoie nosso streamer C.")
        }},
    }

    return categories
end

local function loadMockData()
    otcv8shop = true
    createShop()
    processStatus(buildMockStatus())
    processCategories(buildMockCategories())
    -- histórico mock opcional
    processHistory({
        {
            image = "/images/ui/windows/menu/IconInventory",
            id = 9999,
            name = "Compra teste",
            description = "Entrada de histórico mock",
            price = 123
        }
    })
end

local function sendAction(action, data)
	if not g_game.getFeature(GameExtendedOpcode) then
		return
	end

	local protocolGame = g_game.getProtocolGame()

	if data == nil then
		data = {}
	end

	if protocolGame then
		protocolGame:sendExtendedJSONOpcode(SHOP_EXTENTED_OPCODE, {
			action = action,
			data = data
		})
	end
end

local function onHTTPResult(data, err)
	if not data then
		return
	end

	function qrCodeWindow.copyPix.onClick()
		local label = g_ui.createWidget("Label-13px-Bold", qrCodeWindow)

		g_window.setClipboardText(data.text)
		label:addAnchor(AnchorLeft, qrCodeWindow.copyPix:getId(), AnchorLeft)
		label:addAnchor(AnchorVerticalCenter, qrCodeWindow.copyPix:getId(), AnchorVerticalCenter)
		label:setText("C\xF3digo do Pix copiado!")
		label:setTextAutoResize(true)
		g_effects.fadeOut(label, 1650)
		g_effects.moveToMargin(label, MarginBottom, 0, 35, 2200, Easing.easeOut, function()
			label:destroy()
		end)
	end

	qrCodeWindow.loading:hide()
	qrCodeWindow.pixInput:setText(data.text)
	HTTP.downloadImage(data.href, function(path, err)
		if err then
			return
		end

		qrCodeWindow.image:clearText()
		qrCodeWindow.image:setImageSource(path)
	end)
end

function init()
	g_ui.importStyle("pix.otui")
	connect(g_game, {
		onGameStart = check,
		onGameEnd = hide,
		onStoreInit = onStoreInit,
		onStoreCategories = onStoreCategories,
		onStoreOffers = onStoreOffers,
		onStoreTransactionHistory = onStoreTransactionHistory,
		onStorePurchase = onStorePurchase,
		onStoreError = onStoreError,
		onCoinBalance = onCoinBalance
	})
	ProtocolGame.registerExtendedJSONOpcode(SHOP_EXTENTED_OPCODE, onExtendedJSONOpcode)

	if g_game.isOnline() then
		check()
	end
end

function terminate()
	disconnect(g_game, {
		onGameStart = check,
		onGameEnd = hide,
		onStoreInit = onStoreInit,
		onStoreCategories = onStoreCategories,
		onStoreOffers = onStoreOffers,
		onStoreTransactionHistory = onStoreTransactionHistory,
		onStorePurchase = onStorePurchase,
		onStoreError = onStoreError,
		onCoinBalance = onCoinBalance
	})
	ProtocolGame.unregisterExtendedJSONOpcode(SHOP_EXTENTED_OPCODE, onExtendedJSONOpcode)

--[[ 	if shopButton then
		shopButton:destroy()

		shopButton = nil
	end ]]

	if shop then
		disconnect(shop.categories, {
			onChildFocusChange = changeCategory
		})
		shop:destroy()

		shop = nil
	end

	if msgWindow then
		msgWindow:destroy()
	end
end

function check()
    if USE_MOCK_SHOP then
        loadMockData()
        return
    end
    otcv8shop = false
    sendAction("init")
end

function hide()
	if not shop then
		return
	end

	hidePixWindow()
	hideQrCodeWindow()
	shop:hide()
	--[[ shopButton:setOn(false) ]]
end

function show()
	if not shop --[[ or not shopButton  ]]then
		return
	end

	if g_game.getFeature(GameIngameStore) then
		g_game.openStore(0)
	end

	shop:show()
	shop:raise()
	shop:focus()
	--[[ shopButton:setOn(true) ]]
end

function toggle()
	if not shop then
		return
	end

	if shop:isVisible() then
		return hide()
	end

	show()
	check()
end

function createShop()
	if shop then
		return
	end

	shop = g_ui.displayUI("shop")
	pix = modules.game_api.Pix.new()

	shop:hide()

	--[[ shopButton = modules.client_topmenu.addRightButton("shopButton", tr("Shop"), "/images/topbuttons/icon_store", toggle, false, 9)

	shopButton:setOn(false) ]]
	connect(shop.categories, {
		onChildFocusChange = changeCategory
	})
end

function onStoreInit(url, coins)
	if otcv8shop then
		return
	end

	storeUrl = url

	if storeUrl:len() > 0 then
		if storeUrl:sub(storeUrl:len(), storeUrl:len()) ~= "/" then
			storeUrl = storeUrl .. "/"
		end

		storeUrl = storeUrl .. "64/"

		if storeUrl:sub(1, 4):lower() ~= "http" then
			storeUrl = "http://" .. storeUrl
		end
	end

	coinsPacketSize = coins

	createShop()
end

function onStoreCategories(categories)
	if not shop or otcv8shop then
		return
	end

	local correctCategories = {}

	for i, category in ipairs(categories) do
		table.insert(correctCategories, {
			type = "image",
			image = storeUrl .. category.icon,
			name = category.name,
			offers = {}
		})
	end

	processCategories(correctCategories)
end

function onStoreOffers(categoryName, offers)
	if not shop or otcv8shop then
		return
	end

	local updated = false

	for i, category in ipairs(CATEGORIES) do
		if category.name == categoryName then
			if #category.offers ~= #offers then
				updated = true
			end

			for i = 1, #category.offers do
				if category.offers[i].title ~= offers[i].name or category.offers[i].id ~= offers[i].id or category.offers[i].cost ~= offers[i].price then
					updated = true
				end
			end

			if updated then
				for offer in pairs(category.offers) do
					category.offers[offer] = nil
				end

				for i, offer in ipairs(offers) do
					table.insert(category.offers, {
						type = "image",
						id = offer.id,
						image = storeUrl .. offer.icon,
						cost = offer.price,
						title = offer.name,
						description = offer.description
					})
				end
			end
		end
	end

	if not updated then
		return
	end

	local activeCategory = shop.categories:getFocusedChild()

	changeCategory(activeCategory, activeCategory)
end

function onStoreTransactionHistory(currentPage, hasNextPage, offers)
	if not shop or otcv8shop then
		return
	end

	HISTORY = {}

	for i, offer in ipairs(offers) do
		table.insert(HISTORY, {
			type = "image",
			id = offer.id,
			image = storeUrl .. offer.icon,
			cost = offer.price,
			title = offer.name,
			description = offer.description
		})
	end

	if not browsingHistory then
		return
	end

	clearOffers()
	shop.categories:focusChild(nil)

	for i, transaction in ipairs(HISTORY) do
		addOffer(0, transaction)
	end
end

function onStorePurchase(message)
	if not shop or otcv8shop then
		return
	end

	processMessage({
		title = "Successful shop purchase",
		msg = message
	})
end

function onStoreError(errorType, message)
	if not shop or otcv8shop then
		return
	end

	processMessage({
		title = "Shop error",
		msg = message
	})
end

function onCoinBalance(coins, transferableCoins)
	if not shop or otcv8shop then
		return
	end

	shop.infoPanel.points:setText(tr("P-Bucks:") .. " " .. coins)
	shop.infoPanel.buy:hide()
end

function onExtendedJSONOpcode(protocol, code, json_data)
	createShop()

	local action = json_data.action
	local data = json_data.data

	if not action or not data then
		return false
	end

	otcv8shop = true

	if action == "categories" then
		processCategories(data)
	elseif action == "history" then
		processHistory(data)
	elseif action == "message" then
		processMessage(data)
	elseif action == "status" then
		processStatus(data)
	end
end

function clearOffers()
	while shop.offers:getChildCount() > 0 do
		local child = shop.offers:getLastChild()

		shop.offers:destroyChildren(child)
	end
end

function clearCategories()
	CATEGORIES = {}

	clearOffers()

	while shop.categories:getChildCount() > 0 do
		local child = shop.categories:getLastChild()

		shop.categories:destroyChildren(child)
	end
end

function clearHistory()
	HISTORY = {}

	if browsingHistory then
		clearOffers()
	end
end

function processCategories(data)
	if table.equal(CATEGORIES, data) then
		return
	end

	clearCategories()

	CATEGORIES = data

	for i, category in ipairs(data) do
		addCategory(category)
	end

	if not browsingHistory then
		local firstCategory = shop.categories:getChildByIndex(1)

		if firstCategory then
			firstCategory:focus()
		end
	end
end

function processHistory(data)
	if table.equal(HISTORY, data) then
		return
	end

	HISTORY = data

	if browsingHistory then
		showHistory(true)
	end
end

function processMessage(data)
	if msgWindow then
		msgWindow:destroy()
	end

	local title = tr(data.title)
	local msg = data.msg

	msgWindow = displayInfoBox(title, msg)

	function msgWindow.onDestroy(widget)
		if widget == msgWindow then
			msgWindow = nil
		end
	end

	msgWindow:show()
	msgWindow:raise()
	msgWindow:focus()
end

function processStatus(data)
	if table.equal(STATUS, data) then
		return
	end

	STATUS = data

	if data.ad then
		processAd(data.ad)
	end

	if data.points then
		shop.infoPanel.points:setText(data.points)
	end

	if data.buyUrl and data.buyUrl:sub(1, 4):lower() == "http" then
		function shop.infoPanel.buy.onMouseRelease()
			scheduleEvent(function()
				g_platform.openUrl(data.buyUrl)
			end, 50)
		end
	else
		shop.infoPanel.buy:hide()
	end
end

function processAd(data)
	if table.equal(AD, data) then
		return
	end

	AD = data

	if data.image and data.image:sub(1, 4):lower() == "http" then
		HTTP.downloadImage(data.image, function(path, err)
			if err then
				g_logger.warning("HTTP error: " .. err)

				return
			end

			shop.adPanel:setHeight(shop.infoPanel:getHeight())
			shop.adPanel.ad:setText("")
			shop.adPanel.ad:setImageSource(path)
			shop.adPanel.ad:setImageFixedRatio(true)
			shop.adPanel.ad:setImageAutoResize(true)
			shop.adPanel.ad:setHeight(shop.infoPanel:getHeight())
		end)
	elseif data.text and data.text:len() > 0 then
		shop.adPanel:setHeight(shop.infoPanel:getHeight())
		shop.adPanel.ad:setText(data.text)
		shop.adPanel.ad:setHeight(shop.infoPanel:getHeight())
	else
		shop.adPanel:setHeight(0)
	end

	if data.url and data.url:sub(1, 4):lower() == "http" then
		function shop.adPanel.ad.onMouseRelease()
			scheduleEvent(function()
				g_platform.openUrl(data.url)
			end, 50)
		end
	else
		shop.adPanel.ad.onMouseRelease = nil
	end
end

function addCategory(data)
	local category = g_ui.createWidget("ShopCategory", shop.categories)

	category:setId("category_" .. shop.categories:getChildCount())
	category:setText(data.name)
	category:setImageSource(IMAGE_CATEGORY[data.name])
end

function showWithdrawWindow()
	shop.withdrawWindow:show()
	shop.withdrawWindow.withdrawTextEdit:clearText()
end

function requestWithdraw()
	local withdrawCount = tonumber(shop.withdrawWindow.withdrawTextEdit:getText())

	shop.withdrawWindow:hide()

	if withdrawCount == 0 then
		return
	end

	local requestData = {
		count = withdrawCount
	}

	sendAction("withdraw", requestData)
end

function showHistory(force)
	if browsingHistory and not force then
		return
	end

	if g_game.getFeature(GameIngameStore) and not otcv8shop then
		g_game.openTransactionHistory(100)
	end

	sendAction("history")

	browsingHistory = true

	clearOffers()
	shop.categories:focusChild(nil)

	for i, transaction in ipairs(HISTORY) do
		addOffer(0, transaction, true)
	end
end

function addOffer(category, data, isHistoric)
	local offer

	if data.item then
		offer = g_ui.createWidget("ShopOfferItem", shop.offers)

		if data.image and data.image:len() > 1 and g_resources.fileExists(data.image) then
			offer.item:hide()
			offer.image:setImageSource(data.image)
		else
			offer.image:hide()
			offer.item:setItemId(data.item)
		end
	elseif data.outfit then
		offer = g_ui.createWidget("ShopOfferCreature", shop.offers)

		if data.image and data.image:len() > 1 and g_resources.fileExists(data.image) then
			offer.creature:hide()
			offer.image:setImageSource(data.image)
		else
			offer.image:hide()
			offer.creature:setOutfit(data.outfit)
		end
	elseif data.image then
		offer = g_ui.createWidget("ShopOfferImage", shop.offers)

		if data.image:sub(1, 4):lower() == "http" then
			HTTP.downloadImage(data.image, function(path, err)
				if err then
					g_logger.warning("HTTP error: " .. err .. " - " .. data.image)

					return
				end

				if not offer.image then
					return
				end

				offer.image:setImageSource(path)
			end)
		elseif data.image:len() > 1 then
			offer.image:setImageSource(data.image)
		end
	else
		g_logger.error("Invalid shop offer categoryId: " .. tostring(data.categoryId))

		return
	end

	offer.id = "offer_" .. category .. "_" .. shop.offers:getChildCount()

	offer:setId(data.name)
	offer.title:setText(data.name)
	offer:setTooltip(data.description)
	offer.description:setText(data.description)
	offer.buy:setText(tr("%s - %s P-Bucks", tr("Buy"), data.price))
	offer.buy:setVisible(not isHistoric)

	offer.offerId = data.id

	if category ~= 0 then
		function offer.buy.onClick()
			buyOffer(offer)
		end
	end
end

function changeCategory(widget, newCategory)
	if not newCategory then
		return
	end

	if g_game.getFeature(GameIngameStore) and widget ~= newCategory and not otcv8shop then
		g_game.requestStoreOffers(newCategory.name:getText())
	end

	browsingHistory = false

	local id = tonumber(newCategory:getId():split("_")[2])

	clearOffers()

	for i, offer in ipairs(CATEGORIES[id].offers) do
		addOffer(id, offer)
	end
end

function buyOffer(widget)
	if not widget then
		return
	end

	local split = widget.id:split("_")

	if #split ~= 3 then
		return
	end

	local category = tonumber(split[2])
	local offer = tonumber(split[3])
	local item = CATEGORIES[category].offers[offer]

	if not item then
		return
	end

	selectedOffer = {
		category = category,
		offer = offer,
		name = item.name,
		price = item.price,
		id = widget.offerId
	}

	scheduleEvent(function()
		if msgWindow then
			msgWindow:destroy()
		end

		local title = tr("Buying from shop")
		local msg = tr("Do you want to buy {%s|%s} for %s P-Bucks?", "#e2bb5b", item.name, item.price)

		msgWindow = displayGeneralBox(title, msg, {
			{
				color = "Blue",
				text = tr("Yes"),
				callback = buyConfirmed
			},
			{
				color = "Red",
				text = tr("No"),
				callback = buyCanceled
			},
			anchor = AnchorHorizontalCenter
		}, buyConfirmed, buyCanceled)

		msgWindow:show()
		msgWindow:raise()
		msgWindow:focus()
		msgWindow:raise()
	end, 50)
end

function buyConfirmed()
	msgWindow:destroy()

	msgWindow = nil

	if selectedOffer.name == "Change Name" then
		modules.client_textedit.edit("", {
			title = tr("Change Name")
		}, function(newName)
			if not isRequired(newName) then
				return displayErrorBox(tr("Change Name"), "O nome n\xE3o pode estar em branco!")
			end

			local strValidName = isValidName(newName)

			if strValidName:len() > 0 then
				return displayErrorBox(tr("Change Name"), strValidName)
			end

			selectedOffer.newName = newName

			sendAction("buy", selectedOffer)
		end)
	else
		sendAction("buy", selectedOffer)
	end
end

function buyCanceled()
	msgWindow:destroy()

	msgWindow = nil
	selectedOffer = {}
end

function searchShopOffer(searchValue)
	for i, child in pairs(shop.offers:getChildren()) do
		local searchCondition = searchValue == "" or searchValue ~= "" and string.find(child.title:getText():lower(), searchValue:lower()) ~= nil

		child:setVisible(searchCondition)
	end
end

function sendDonate(cpf, amount)
	pix:donate(cpf, amount, onHTTPResult)
end

function hidePixWindow()
	if pixWindow then
		pixWindow:destroy()

		pixWindow = nil
	end
end

function hideQrCodeWindow()
	if qrCodeWindow then
		qrCodeWindow:destroy()

		qrCodeWindow = nil
	end
end

function showPixWindow()
	hidePixWindow()

	pixWindow = g_ui.createWidget("PixWindow", rootWidget)
end

function showQrCodeWindow()
	hideQrCodeWindow()

	qrCodeWindow = g_ui.createWidget("PixQRCodeWindow", rootWidget)

	qrCodeWindow:raise()
	qrCodeWindow:focus()
end

function onConfirm()
    local canDonate = onInputCPF(pixWindow.cpfInput) and onInputAmount(pixWindow.amountInput, 10, 10000)

    if not canDonate then
        return
    end

    local cpf = pixWindow.cpfInput:getText()
    local amount = pixWindow.amountInput:getText()

    pixWindow:hide()

    local function onConfirm()
        showQrCodeWindow()
        sendDonate(cpf, amount)
    end

    local function onCancel()
        pixWindow:show()
        pixWindow:raise()
    end

    displayConfirmBox(tr("Confirm"), tr("Estas informa\xE7\xF5es est\xE3o corretas?\nCPF: %s\nQuantidade: %s", cpf, amount), onConfirm, onCancel)
end
