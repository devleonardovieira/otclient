-- chunkname: @/modules/game_market/market.lua

Market = {}

local protocol = runinsandbox("marketprotocol")
local marketWindow, acceptWindow, sellWindow, messageWindow, mainTabBar, categoryList, pagePanel, searchText, headerOffer, offerList, sellList, historicList, selectedItem
local currentPage = 1
local maxPage = 1
local currentOfferIndex = 1

function refreshOffers(page)
	local sortButton = headerOffer:getFocusedChild()
	local data = {
		page = page or currentPage,
		search = searchText:getText(),
		sortField = sortButton:getId(),
		sortType = sortButton:isOn() and MarketSortType.Desc or MarketSortType.Asc,
		categoryId = categoryList:getCurrentOption().data
	}

	currentOfferIndex = 1

	sendRefreshOffers(data)
end

local function showMarket()
	marketWindow:show()
end

local function hideMarket()
	currentOfferIndex = 1

	marketWindow:hide()
end

local function destroyAcceptWindow()
	if acceptWindow then
		acceptWindow:destroy()

		acceptWindow = nil
	end
end

local function destroySellWindow()
	if sellWindow then
		sellWindow:destroy()

		sellWindow = nil
	end
end

local function destroyMessageWindow()
	if messageWindow then
		messageWindow:destroy()

		messageWindow = nil
	end
end

local function clearEvents()
	for i, child in pairs(sellList:getChildren()) do
		removeEvent(child.created.event)
	end
end

local function clearAllList()
	offerList:destroyChildren()
	sellList:destroyChildren()
	historicList:destroyChildren()
end

local function refreshSell()
	sendRefreshSales()
end

local function refreshHistory()
	sendRefreshHistoric()
end

local function setupConfiguration(page, pageSize)
	currentPage = page
	maxPage = pageSize
end

local function updatePaginationControls()
	local isEnabledLeftButtons = currentPage > 1

	pagePanel.firstButton:setEnabled(isEnabledLeftButtons)
	pagePanel.prevButton:setEnabled(isEnabledLeftButtons)

	local isEnabledRightButtons = currentPage < maxPage

	pagePanel.nextButton:setEnabled(isEnabledRightButtons)
	pagePanel.lastButton:setEnabled(isEnabledRightButtons)
	pagePanel.page:setText(("%s de %s"):format(("%02d"):format(currentPage), ("%02d"):format(maxPage)))
end

local function initInterface()
	mainTabBar = marketWindow.mainTabBar

	mainTabBar:setContentWidget(marketWindow.mainTabContent)

	local offersPanel = g_ui.loadUI("ui/offersPanel")

	mainTabBar:addTab(tr("Buy"), offersPanel, "/images/game/market/icon_buy")

	local sellPanel = g_ui.loadUI("ui/sellPanel")

	mainTabBar:addTab(tr("Sell"), sellPanel, "/images/game/market/icon_sell")

	local historicPanel = g_ui.loadUI("ui/historicPanel")

	mainTabBar:addTab(tr("Historic"), historicPanel)

	pagePanel = offersPanel.pagePanel
	searchText = offersPanel.searchText
	categoryList = offersPanel.categoryList
	headerOffer = offersPanel.headerOffer
	offerList = offersPanel.offerList
	sellList = sellPanel.sellList
	historicList = historicPanel.historicList

	local refresh = {
		offersPanel = refreshOffers,
		sellPanel = refreshSell,
		historicPanel = refreshHistory
	}

	function mainTabBar.onTabChange(widget, tab)
		if marketWindow:isVisible() then
			refresh[tab.tabPanel:getId()]()
		end
	end

	for i = 0, #MarketCategoryStrings do
		categoryList:addOption(tr(MarketCategoryStrings[i]), i)
	end
end

function Market.onMarketOpen()
	mainTabBar:selectTab(mainTabBar:getTab(tr("Buy")))
	headerOffer:focusChild(headerOffer:getFirstChild())
	showMarket()
end

function Market.onMarketOffers(data, page, pageSize, search, sortType, sortField, categoryId)
	offerList:destroyChildren()

	for i, offer in pairs(data) do
		local widget = g_ui.createWidget("MarketOffer", offerList)

		widget:setId(i)

		widget.offer = offer

		addWidget(widget, offer, OffersProps)
	end

	local selectedOffer = offerList:getChildByIndex(currentOfferIndex)

	if selectedOffer then
		offerList:focusChild(selectedOffer)
	end

	setupConfiguration(page, pageSize)
	updatePaginationControls()
end

function Market.onMarketSales(data)
	clearEvents()
	sellList:destroyChildren()

	for i, sale in pairs(data) do
		local widget = g_ui.createWidget("MarketSale", sellList)

		widget.sale = sale

		addWidget(widget, sale, SalesProps)
	end

	sellList.verticalScrollBar:setVisible(#data > 9)
end

function Market.onMarketHistoric(data)
	historicList:destroyChildren()

	for i, historic in pairs(data) do
		local widget = g_ui.createWidget("MarketHistoric", historicList)

		addWidget(widget, historic, HistoricProps)
	end
end

function Market.onMarketMessage(message)
	destroyMessageWindow()

	local function defaultCallback()
		messageWindow:ok()
		showMarket()
	end

	messageWindow = displayGeneralBox(marketWindow:getText(), message, {
		{
			text = "Ok",
			color = "Blue",
			callback = defaultCallback
		}
	}, defaultCallback, defaultCallback)

	messageWindow:show()
	messageWindow:raise()
	messageWindow:focus()
end

function Market.onMarketRequestItem(item)
	if selectedItem == nil then
		return
	end

	destroySellWindow()

	sellWindow = g_ui.createWidget("MarketSellWindow", rootWidget)

	sellWindow:onVisibilityChange(true)

	local scrollBar = sellWindow.count
	local expire = sellWindow.expire
	local spinBox = sellWindow.price
	local cancelButton = sellWindow.cancel

	local function cancelFunc()
		destroySellWindow()
		showMarket()
	end

	local confirmButton = sellWindow.confirm

	local function confirmFunc()
		sendCreateOffer(selectedItem, scrollBar:getValue(), spinBox:getValue(), expire:getCurrentOption().data)
		cancelFunc()
	end

	confirmButton.onClick = confirmFunc
	cancelButton.onClick = cancelFunc

	local function onValueChange(widget, value)
		local totalPrice = scrollBar:getValue() * spinBox:getValue()
		local fee = item.fee > 0 and math.min(item.maxFee, math.max(1, totalPrice * item.fee)) or 0

		sellWindow.fee:setText(formatMoney(fee))
		sellWindow.item:setItemCount(scrollBar:getValue())
		sellWindow.totalPrice:setText(formatMoney(totalPrice))
		sellWindow.priceUnit:setText(formatMoney(spinBox:getValue()))
		sellWindow.expectedProfit:setText(formatMoney(totalPrice - fee))
	end

	spinBox.onValueChange = onValueChange
	scrollBar.onValueChange = onValueChange

	addWidget(sellWindow, item, ItemProps)
end

function init()
	g_ui.importStyle("ui/sellWindow")
	protocol.initProtocol()
	connect(g_game, {
		onGameStart = onGameEnd,
		onGameEnd = onGameEnd
	})
	connect(LocalPlayer, {
		onPositionChange = onMarketPositionChange
	})

	marketWindow = g_ui.displayUI("market")

	initInterface()
end

function terminate()
	protocol.terminateProtocol()
	disconnect(g_game, {
		onGameStart = onGameEnd,
		onGameEnd = onGameEnd
	})
	disconnect(LocalPlayer, {
		onPositionChange = onMarketPositionChange
	})
	onGameEnd()
	marketWindow:destroy()

	Market = nil
end

function onGameEnd()
	categoryList:setCurrentOptionByData(MarketCategory.All, true)
	searchText:clearText()

	selectedItem = nil
	currentPage = 1
	maxPage = 1

	hideMarket()
	clearEvents()
	clearAllList()
	destroySellWindow()
	destroyAcceptWindow()
	destroyMessageWindow()
end

function onMarketPositionChange()
	if marketWindow:isVisible() then
		onGameEnd()
	end
end

function updatePagination(widget)
	local pageButtonsValue = {
		firstButton = 1,
		prevButton = math.max(1, currentPage - 1),
		nextButton = math.min(maxPage, currentPage + 1),
		lastButton = maxPage
	}

	currentPage = pageButtonsValue[widget:getId()]

	refreshOffers()
end

function openAcceptWindow()
	local selectedOffer = offerList:getFocusedChild()

	if not selectedOffer then
		return
	end

	destroyAcceptWindow()
	hideMarket()

	acceptWindow = g_ui.createWidget("CountWindow", rootWidget)

	acceptWindow:setText(tr("Buy"))
	acceptWindow:onVisibilityChange(true)

	local offer = selectedOffer.offer
	local extraLabel = acceptWindow.extraLabel

	extraLabel:show()

	local itemBox = acceptWindow.item

	itemBox:setItem(offer.item)

	local scrollBar = acceptWindow.countScrollBar

	function scrollBar.onValueChange(widget, value)
		extraLabel:setText(tr("Total price") .. ": " .. formatMoney(value * offer.price))
		itemBox:setItemCount(value)
	end

	scrollBar:setRange(1, offer.count)
	scrollBar:setValue(1)

	local cancelButton = acceptWindow.buttonCancel

	local function cancelFunc()
		destroyAcceptWindow()
		showMarket()
	end

	local okButton = acceptWindow.buttonOk

	local function okFunc()
		local sortButton = headerOffer:getFocusedChild()
		local settings = {
			page = currentPage,
			search = searchText:getText(),
			sortField = sortButton:getId(),
			sortType = sortButton:isOn() and MarketSortType.Desc or MarketSortType.Asc,
			categoryId = categoryList:getCurrentOption().data
		}

		currentOfferIndex = tonumber(selectedOffer:getId())

		sendAcceptOffer(offer, scrollBar:getValue(), settings)
		cancelFunc()
	end

	acceptWindow.onEnter = okFunc
	acceptWindow.onEscape = cancelFunc
	okButton.onClick = okFunc
	cancelButton.onClick = cancelFunc
end

function startChooseSellItem()
	local interface = modules.game_interface
	local mouseGrabberWidget = interface.mouseGrabberWidget

	mouseGrabberWidget:grabMouse()
	g_mouse.pushCursor("target")
	hideMarket()

	function mouseGrabberWidget:onMouseRelease(mousePosition, mouseButton)
		if mouseButton == MouseLeftButton then
			local widget = interface.getRootPanel():recursiveGetChildByPos(mousePosition, false)

			if widget and widget:getClassName() == "UIItem" and widget:getItem() then
				selectedItem = widget:getItem()

				sendRequestItem(selectedItem)
			else
				showMarket()
			end
		end

		while g_mouse.isCursorChanged() do
			g_mouse.popCursor("target")
		end

		self:ungrabMouse()

		mouseGrabberWidget.onMouseRelease = nil
		mouseGrabberWidget.onMouseRelease = interface.onMouseGrabberRelease
	end
end

function onDraggingItem(item, mousePos, dragType)
	if not marketWindow or not marketWindow:isVisible() then
		return
	end

	if dragType == "enter" then
		marketWindow.dragArea:show()
	elseif dragType == "leave" then
		local child = rootWidget:recursiveGetChildByPos(mousePos)

		if child and child == marketWindow.dragArea then
			hideMarket()

			selectedItem = item

			sendRequestItem(item)
		end

		marketWindow.dragArea:hide()
	end
end
