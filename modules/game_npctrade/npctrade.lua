-- chunkname: @/modules/game_npctrade/npctrade.lua

BUY = 1
SELL = 2
CURRENCY = ""
CURRENCY_PLURAL = ""
CURRENCY_DECIMAL = true
LAST_INVENTORY = 10
npcWindow = nil
itemsPanel = nil
radioTabs = nil
radioItems = nil
searchText = nil
setupPanel = nil
quantity = nil
quantityScroll = nil
nameLabel = nil
priceLabel = nil
moneyLabel = nil
tradeButton = nil
buyTab = nil
sellTab = nil
initialized = false
ignoreEquipped = nil
showAllItems = nil
sellAllButton = nil
playerFreeCapacity = 0
playerMoney = 0
tradeItems = {}
playerItems = {}
selectedItem = nil
cancelNextRelease = nil
sellAllWithDelayEvent = nil
confirmWindow = nil
countWindow = nil

local visibleAmountItem = {
	11396,
	11395,
	11394,
	11393,
	11399,
	11392,
	17322,
	17323
}

function init()
	npcWindow = g_ui.displayUI("npctrade")

	npcWindow:setVisible(false)

	itemsPanel = npcWindow:recursiveGetChildById("itemsPanel")
	searchText = npcWindow:recursiveGetChildById("searchText")
	setupPanel = npcWindow:recursiveGetChildById("setupPanel")
	quantityScroll = setupPanel:getChildById("quantityScroll")
	nameLabel = setupPanel:getChildById("name")
	priceLabel = setupPanel:getChildById("price")
	moneyLabel = npcWindow:getChildById("money")
	tradeButton = npcWindow:recursiveGetChildById("tradeButton")
	showAllItems = npcWindow:recursiveGetChildById("showAllItems")
	sellAllButton = npcWindow:recursiveGetChildById("sellAllButton")
	buyTab = npcWindow:getChildById("buyTab")
	sellTab = npcWindow:getChildById("sellTab")
	radioTabs = UIRadioGroup.create()

	radioTabs:addWidget(buyTab)
	radioTabs:addWidget(sellTab)
	radioTabs:selectWidget(buyTab)

	radioTabs.onSelectionChange = onTradeTypeChange
	cancelNextRelease = false

	if g_game.isOnline() then
		playerFreeCapacity = g_game.getLocalPlayer():getFreeCapacity()
	end

	connect(g_game, {
		onGameEnd = hide,
		onOpenNpcTrade = onOpenNpcTrade,
		onCloseNpcTrade = onCloseNpcTrade,
		onPlayerGoods = onPlayerGoods
	})
	connect(LocalPlayer, {
		onFreeCapacityChange = onFreeCapacityChange,
		onInventoryChange = onInventoryChange
	})

	initialized = true
end

function terminate()
	initialized = false

	npcWindow:destroy()

	if confirmWindow then
		confirmWindow:onVisibilityChange(false)
		confirmWindow:destroy()

		confirmWindow = nil
	end

	if countWindow then
		countWindow:destroy()

		countWindow = nil
	end

	removeEvent(sellAllWithDelayEvent)
	disconnect(g_game, {
		onGameEnd = hide,
		onOpenNpcTrade = onOpenNpcTrade,
		onCloseNpcTrade = onCloseNpcTrade,
		onPlayerGoods = onPlayerGoods
	})
	disconnect(LocalPlayer, {
		onFreeCapacityChange = onFreeCapacityChange,
		onInventoryChange = onInventoryChange
	})
end

function show()
	if g_game.isOnline() then
		if #tradeItems[BUY] > 0 then
			radioTabs:selectWidget(buyTab)
		else
			radioTabs:selectWidget(sellTab)
		end

		npcWindow:show()
		npcWindow:raise()
		npcWindow:focus()
	end
end

function hide()
	removeEvent(sellAllWithDelayEvent)
	npcWindow:hide()

	if confirmWindow then
		confirmWindow:onVisibilityChange(false)
		confirmWindow:destroy()

		confirmWindow = nil
	end

	if countWindow then
		countWindow:onVisibilityChange(false)
		countWindow:destroy()

		countWindow = nil
	end

	local layout = itemsPanel:getLayout()

	layout:disableUpdates()
	clearSelectedItem()
	searchText:clearText()
	setupPanel:disable()
	itemsPanel:destroyChildren()

	if radioItems then
		radioItems:destroy()

		radioItems = nil
	end

	layout:enableUpdates()
	layout:update()
end

function onItemBoxChecked(widget)
	if widget:isChecked() then
		local item = widget.item

		selectedItem = item

		refreshItem(item)
		tradeButton:enable()

		if getCurrentTradeType() == SELL then
			quantityScroll:setValue(quantityScroll:getMaximum())
		end
	end
end

function onQuantityValueChange(quantity)
	if selectedItem then
		priceLabel:setText(formatCurrency(getItemPrice(selectedItem)))
	end
end

function onTradeTypeChange(radioTabs, selected, deselected)
	tradeButton:setText(selected:getText())

	local currentTradeType = getCurrentTradeType()

	showAllItems:setVisible(currentTradeType == SELL)
	sellAllButton:setVisible(currentTradeType == SELL)
	refreshTradeItems()
	refreshPlayerGoods()
end

function buyAndSellItem(item, count)
	if getCurrentTradeType() == BUY then
		g_game.buyItem(item, count, true, false)
	else
		g_game.sellItem(item, count, true)
	end
end

function onQuantityTradeClick()
	if not selectedItem or countWindow then
		return
	end

	npcWindow:hide()

	countWindow = g_ui.createWidget("CountWindow", rootWidget)

	countWindow:onVisibilityChange(true)

	local itembox = countWindow:getChildById("item")
	local scrollbar = countWindow:getChildById("countScrollBar")
	local extraLabel = countWindow:getChildById("extraLabel")

	itembox:setItemId(selectedItem.ptr:getId())
	itembox:setItemCount(1)
	scrollbar:setMaximum(quantityScroll:getMaximum())
	scrollbar:setMinimum(quantityScroll:getMinimum())
	scrollbar:setValue(1)

	local spinbox = countWindow:getChildById("spinBox")

	spinbox:setMaximum(quantityScroll:getMaximum())
	spinbox:setMinimum(quantityScroll:getMinimum())
	spinbox:setValue(quantityScroll:getValue())
	spinbox:hideButtons()
	spinbox:focus()

	spinbox.firstEdit = true

	extraLabel:show()
	countWindow:setText(radioTabs:getSelectedWidget():getText())

	local function extraValueChange(value)
		quantityScroll:setValue(value)
		extraLabel:setText(tr("Total Price") .. ": " .. formatMoney(getItemPrice(selectedItem)))
	end

	extraValueChange(1)

	local function spinBoxValueChange(self, value)
		spinbox.firstEdit = false

		scrollbar:setValue(value)
		extraValueChange(value)
	end

	spinbox.onValueChange = spinBoxValueChange

	local function check()
		if spinbox.firstEdit then
			spinbox:setValue(spinbox:getMaximum())

			spinbox.firstEdit = false
		end
	end

	g_keyboard.bindKeyPress("Up", function()
		check()
		spinbox:setValue(spinbox:getValue() + 10)
	end, spinbox)
	g_keyboard.bindKeyPress("Down", function()
		check()
		spinbox:setValue(spinbox:getValue() - 10)
	end, spinbox)
	g_keyboard.bindKeyPress("Right", function()
		check()
		spinbox:up()
	end, spinbox)
	g_keyboard.bindKeyPress("Left", function()
		check()
		spinbox:down()
	end, spinbox)

	function scrollbar:onValueChange(value)
		itembox:setItemCount(value)

		spinbox.onValueChange = nil

		spinbox:setValue(value)

		spinbox.onValueChange = spinBoxValueChange

		extraValueChange(value)
	end

	local okButton = countWindow:getChildById("buttonOk")

	local function okFunc()
		countWindow:onVisibilityChange(false)
		buyAndSellItem(selectedItem.ptr, itembox:getItemCount())
		okButton:getParent():destroy()

		countWindow = nil

		npcWindow:show()
	end

	local cancelButton = countWindow:getChildById("buttonCancel")

	local function cancelFunc()
		countWindow:onVisibilityChange(true)
		cancelButton:getParent():destroy()

		countWindow = nil

		npcWindow:show()
	end

	countWindow.onEnter = okFunc
	countWindow.onEscape = cancelFunc
	okButton.onClick = okFunc
	cancelButton.onClick = cancelFunc
end

function onTradeClick()
	removeEvent(sellAllWithDelayEvent)

	if isVisibleAmountItem(selectedItem.ptr:getId()) then
		onQuantityTradeClick()
	else
		buyAndSellItem(selectedItem.ptr, 1)
	end
end

function onSearchTextChange()
	refreshPlayerGoods()
end

function itemPopup(self, mousePosition, mouseButton)
	if cancelNextRelease then
		cancelNextRelease = false

		return false
	end

	if mouseButton == MouseRightButton then
		local menu = g_ui.createWidget("PopupMenu")

		menu:setGameMenu(true)
		menu:addOption(tr("Look"), function()
			return g_game.inspectNpcTrade(self:getItem())
		end)
		menu:display(mousePosition)

		return true
	elseif g_mouse.isPressed(MouseLeftButton) and mouseButton == MouseRightButton or g_mouse.isPressed(MouseRightButton) and mouseButton == MouseLeftButton then
		cancelNextRelease = true

		g_game.inspectNpcTrade(self:getItem())

		return true
	end

	return false
end

function onShowAllItemsChange()
	refreshPlayerGoods()
end

function setCurrency(currency, decimal)
	CURRENCY = currency
	CURRENCY_DECIMAL = decimal
end

function clearSelectedItem()
	nameLabel:clearText()
	priceLabel:clearText()
	tradeButton:disable()
	quantityScroll:setMinimum(0)
	quantityScroll:setMaximum(0)

	if selectedItem then
		radioItems:selectWidget(nil)

		selectedItem = nil
	end
end

function getCurrentTradeType()
	if tradeButton:getText() == tr("Buy") then
		return BUY
	else
		return SELL
	end
end

function getItemPrice(item, single)
	local amount = 1
	local single = single or false

	if not single then
		amount = quantityScroll:getValue()
	end

	return item.price * amount
end

function getSellQuantity(item)
	if not item or not playerItems[item:getId()] then
		return 0
	end

	local removeAmount = 0

	return playerItems[item:getId()] - removeAmount
end

function canTradeItem(item)
	if getCurrentTradeType() == BUY then
		return playerMoney >= getItemPrice(item, true)
	else
		return getSellQuantity(item.ptr) > 0
	end
end

function isVisibleAmountItem(itemid)
	return not table.contains(visibleAmountItem, itemid)
end

function refreshItem(item)
	nameLabel:setText(item.name)
	priceLabel:setText(formatCurrency(getItemPrice(item)))

	if getCurrentTradeType() == BUY then
		local priceMaxCount = math.floor(playerMoney / getItemPrice(item, true))
		local finalCount = math.max(0, math.min(getMaxAmount(), priceMaxCount))

		quantityScroll:setMinimum(1)
		quantityScroll:setMaximum(finalCount)
		quantityScroll:setVisible(isVisibleAmountItem(item.ptr:getId()))
	else
		quantityScroll:setMinimum(1)
		quantityScroll:setMaximum(math.max(0, math.min(getMaxAmount(), getSellQuantity(item.ptr))))
	end

	setupPanel:enable()
end

function refreshTradeItems()
	local layout = itemsPanel:getLayout()

	layout:disableUpdates()
	clearSelectedItem()
	searchText:clearText()
	setupPanel:disable()
	itemsPanel:destroyChildren()

	if radioItems then
		radioItems:destroy()
	end

	radioItems = UIRadioGroup.create()

	local currentTradeItems = tradeItems[getCurrentTradeType()]

	for key, item in pairs(currentTradeItems) do
		local itemBox = g_ui.createWidget("NPCItemBox", itemsPanel)

		itemBox.item = item

		local itemWidget = itemBox:getChildById("item")

		itemWidget:setItem(item.ptr)

		itemWidget.onMouseRelease = itemPopup

		local nameWidget = itemBox:getChildById("name")

		nameWidget:setText(item.name)

		local priceWidget = itemBox:getChildById("price")

		priceWidget:setText(formatMoney(item.price))
		radioItems:addWidget(itemBox)
	end

	layout:enableUpdates()
	layout:update()
end

function refreshPlayerGoods()
	if not initialized then
		return
	end

	checkSellAllTooltip()
	moneyLabel:setText(tr("Voc\xEA tem: $ %s", playerMoney > 0 and formatMoney(playerMoney) or 0))

	local currentTradeType = getCurrentTradeType()
	local searchFilter = searchText:getText():lower()
	local foundSelectedItem = false
	local items = itemsPanel:getChildCount()

	for i = 1, items do
		local itemWidget = itemsPanel:getChildByIndex(i)
		local item = itemWidget.item
		local canTrade = canTradeItem(item)

		itemWidget:setOn(canTrade)
		itemWidget:setEnabled(canTrade)

		local searchCondition = searchFilter == "" or searchFilter ~= "" and string.find(item.name:lower(), searchFilter) ~= nil
		local showAllItemsCondition = currentTradeType == BUY or showAllItems:isChecked() or currentTradeType == SELL and not showAllItems:isChecked() and canTrade

		itemWidget:setVisible(searchCondition and showAllItemsCondition)

		if selectedItem == item and itemWidget:isEnabled() and itemWidget:isVisible() then
			foundSelectedItem = true
		end
	end

	if not foundSelectedItem then
		clearSelectedItem()
	end

	if selectedItem then
		refreshItem(selectedItem)
	end

	sellAllButton:setEnabled(not table.empty(playerItems))
end

function onOpenNpcTrade(items)
	hide()

	tradeItems[BUY] = {}
	tradeItems[SELL] = {}

	for key, item in pairs(items) do
		if item[4] > 0 then
			local newItem = {}

			newItem.ptr = item[1]
			newItem.name = item[2]
			newItem.price = item[4]

			table.insert(tradeItems[BUY], newItem)
		end

		if item[5] > 0 then
			local newItem = {}

			newItem.ptr = item[1]
			newItem.name = item[2]
			newItem.price = item[5]

			table.insert(tradeItems[SELL], newItem)
		end
	end

	addEvent(function()
		refreshTradeItems()
		refreshPlayerGoods()
		addEvent(show)
	end)
end

function closeNpcTrade()
	g_game.closeNpcTrade()
	addEvent(hide)
end

function onCloseNpcTrade()
	addEvent(hide)
end

function onPlayerGoods(money, items)
	playerMoney = money
	playerItems = {}

	for key, item in pairs(items) do
		local id = item[1]:getId()

		if not playerItems[id] then
			playerItems[id] = item[2]
		else
			playerItems[id] = playerItems[id] + item[2]
		end
	end

	refreshPlayerGoods()
end

function onFreeCapacityChange(localPlayer, freeCapacity, oldFreeCapacity)
	playerFreeCapacity = freeCapacity

	if npcWindow:isVisible() then
		refreshPlayerGoods()
	end
end

function onInventoryChange(inventory, item, oldItem)
	refreshPlayerGoods()
end

function getTradeItemData(id, type)
	if table.empty(tradeItems[type]) then
		return false
	end

	if type then
		for key, item in pairs(tradeItems[type]) do
			if item.ptr and item.ptr:getId() == id then
				return item
			end
		end
	else
		for _, items in pairs(tradeItems) do
			for key, item in pairs(items) do
				if item.ptr and item.ptr:getId() == id then
					return item
				end
			end
		end
	end

	return false
end

function checkSellAllTooltip()
	local total = 0
	local info = ""
	local first = true

	for key, amount in pairs(playerItems) do
		local data = getTradeItemData(key, SELL)

		if data then
			amount = getSellQuantity(data.ptr)

			if amount > 0 and data and amount > 0 then
				info = info .. (not first and "\n" or "") .. amount .. " " .. data.name .. " (" .. data.price * amount .. " gold)"
				total = total + data.price * amount
				first = first and false
			end
		end
	end

	if info ~= "" then
		info = info .. "\nTotal: " .. total .. " gold"
	end
end

function formatCurrency(amount)
	if CURRENCY_DECIMAL then
		amount = amount / 100

		return string.format("%.02f", amount) .. " " .. (amount ~= 1 and CURRENCY_PLURAL or CURRENCY)
	else
		return amount .. " " .. (amount ~= 1 and CURRENCY_PLURAL or CURRENCY)
	end
end

function getMaxAmount()
	if getCurrentTradeType() == SELL and g_game.getFeature(GameDoubleShopSellAmount) then
		return 10000
	end

	return 10000
end

function confirmSellAll(delayed)
	if not confirmWindow then
		confirmWindow = g_ui.createWidget("ConfirmSellAll", rootWidget)
	end

	local total = 0
	local auxTotal = 0
	local selectItems = {}
	local listItem = confirmWindow.listItem
	local messageLabel = confirmWindow.messageLabel
	local confirmButton = confirmWindow.confirmButton

	npcWindow:hide()
	listItem:destroyChildren()
	confirmWindow:onVisibilityChange(true)

	for _, entry in ipairs(tradeItems[SELL]) do
		local sellQuantity = getSellQuantity(entry.ptr)

		while sellQuantity > 0 do
			local maxAmount = math.min(sellQuantity, getMaxAmount())
			local uiItem = g_ui.createWidget("SellItem", listItem)

			uiItem:setItemId(entry.ptr:getId())
			uiItem:setItemCount(maxAmount)
			uiItem:setTooltip(maxAmount .. " " .. entry.name .. "\n" .. formatCurrency(entry.price * maxAmount))

			local selectItem = {
				entry = entry,
				count = maxAmount
			}

			function uiItem:onClick()
				self:setOn(not self:isOn())
				self.block:setVisible(self:isOn())

				if self:isOn() then
					auxTotal = auxTotal - entry.price * maxAmount

					table.removevalue(selectItems, selectItem)
				else
					auxTotal = auxTotal + entry.price * maxAmount

					table.insert(selectItems, selectItem)
				end

				messageLabel:setText(tr("Are you sure that you want to sell\nall these items for %s?", auxTotal > 0 and formatMoney(auxTotal) or 0))
			end

			table.insert(selectItems, selectItem)

			sellQuantity = sellQuantity - maxAmount
			total = total + entry.price * maxAmount
			auxTotal = total
		end
	end

	confirmWindow:raise()
	confirmWindow:setHeight(math.min(328, confirmWindow:getHeight() + (listItem:getLayout():getNumLines() - 1) * 35))
	messageLabel:setText(tr("Are you sure that you want to sell\nall these items for %s?", auxTotal > 0 and formatMoney(auxTotal) or 0))

	function confirmButton.onClick()
		npcWindow:show()
		sellAll(selectItems, delayed)
		confirmWindow:destroy()

		confirmWindow = nil
	end
end

function sellAll(sellItems, delayed)
	removeEvent(sellAllWithDelayEvent)

	local item = table.remove(sellItems, 1)

	if item then
		g_game.sellItem(item.entry.ptr, item.count, true)

		sellAllWithDelayEvent = scheduleEvent(function()
			sellAll(sellItems, true)
		end, 180)
	end
end
