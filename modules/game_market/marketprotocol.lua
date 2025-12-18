-- chunkname: @/modules/game_market/marketprotocol.lua

local protocol
local MarketOpcode = 88

-- Mock handling
function handleMockAction(action, data)
    if not MockMarket or not MockMarket.Config.enabled then return false end

    local latency = MockMarket.Config.latency or 100
    
    scheduleEvent(function()
        if action == MarketRequest.Offers then
            local result = MockMarket.getOffers(data.page, data.search, data.sortType, data.sortField, data.categoryId)
            parseOffers(result)
        
        elseif action == MarketRequest.Sales then
            parseSales(MockMarket.Sales)
            
        elseif action == MarketRequest.Historic then
            parseHistoric(MockMarket.Historic)
            
        elseif action == MarketRequest.Item then
            -- We need to pass back the item data requested + fee info
            local result = table.copy(MockMarket.ItemRequest)
            -- Merge with request data to keep context if needed
            result.spriteId = data.spriteId
            parseItem(result)
            
        elseif action == MarketRequest.CreateOffer then
            parseMessage("Offer created successfully (Mock).")
            -- Optionally refresh lists
            parseSales(MockMarket.Sales)
            
        elseif action == MarketRequest.AcceptOffer then
            parseMessage("Offer accepted successfully (Mock).")
            -- Refresh offers/history
            parseHistoric(MockMarket.Historic)
            
        elseif action == MarketRequest.CancelOffer then
            parseMessage("Offer cancelled (Mock).")
            parseSales(MockMarket.Sales)
        end
    end, latency)

    return true
end

local function sendAction(action, data)
    if handleMockAction(action, data) then
        return
    end

	if protocol then
		protocol:sendExtendedJSONOpcode(MarketOpcode, {
			action = action,
			data = data
		})
	end
end

local function parseOpen()
	signalcall(Market.onMarketOpen)
end

local function parseOffers(data)
	local offersList = {}

	for i, offer in pairs(data.data) do
		local tmpItem = Item.create(offer.clientId, offer.count)

		tmpItem:setTooltip(offer.description)

		offer.idx = i
		offer.item = tmpItem
		offersList[#offersList + 1] = offer
	end

	signalcall(Market.onMarketOffers, offersList, data.page, data.pageSize, data.search, data.sortType, data.sortField, data.categoryId)
end

local function parseSales(offers)
	local offersSale = {}

	for i, sale in pairs(offers) do
		local tmpItem = Item.create(sale.clientId, sale.count)

		tmpItem:setTooltip(sale.description)

		sale.idx = i
		sale.item = tmpItem
		offersSale[#offersSale + 1] = sale
	end

	signalcall(Market.onMarketSales, offersSale)
end

local function parseHistoric(historic)
	signalcall(Market.onMarketHistoric, historic)
end

local function parseItem(item)
	local tmpItem = Item.create(item.clientId, item.count)

	tmpItem:setTooltip(item.description)

	item.item = tmpItem

	signalcall(Market.onMarketRequestItem, item)
end

local function parseMessage(message)
	signalcall(Market.onMarketMessage, message)
end

local parseMarketOpcodes = {
	[MarketParse.Open] = parseOpen,
	[MarketParse.Offers] = parseOffers,
	[MarketParse.Sales] = parseSales,
	[MarketParse.Historic] = parseHistoric,
	[MarketParse.Item] = parseItem,
	[MarketParse.Message] = parseMessage
}

local function parseMarket(protocol, opcode, json_data)
	local executeAction = parseMarketOpcodes[json_data.action]

	if executeAction then
		executeAction(json_data.data)
	end
end

function initProtocol()
	connect(g_game, {
		onGameStart = registerProtocol,
		onGameEnd = unregisterProtocol
	})

	if g_game.isOnline() then
		registerProtocol()
	end
end

function terminateProtocol()
	disconnect(g_game, {
		onGameStart = registerProtocol,
		onGameEnd = unregisterProtocol
	})
end

function updateProtocol(_protocol)
	protocol = _protocol
end

function registerProtocol()
	ProtocolGame.registerExtendedJSONOpcode(MarketOpcode, parseMarket)
	updateProtocol(g_game.getProtocolGame())
end

function unregisterProtocol()
	ProtocolGame.unregisterExtendedJSONOpcode(MarketOpcode)
	updateProtocol(nil)
end

-- Mock handling
local function handleMockAction(action, data)
    if not MockMarket or not MockMarket.Config.enabled then return false end

    local latency = MockMarket.Config.latency or 100
    
    scheduleEvent(function()
        if action == MarketRequest.Offers then
            local result = MockMarket.getOffers(data.page, data.search, data.sortType, data.sortField, data.categoryId)
            parseOffers(result)
        
        elseif action == MarketRequest.Sales then
            parseSales(MockMarket.Sales)
            
        elseif action == MarketRequest.Historic then
            parseHistoric(MockMarket.Historic)
            
        elseif action == MarketRequest.Item then
            -- We need to pass back the item data requested + fee info
            local result = table.copy(MockMarket.ItemRequest)
            -- Merge with request data to keep context if needed
            result.spriteId = data.spriteId
            parseItem(result)
            
        elseif action == MarketRequest.CreateOffer then
            parseMessage("Offer created successfully (Mock).")
            -- Optionally refresh lists
            parseSales(MockMarket.Sales)
            
        elseif action == MarketRequest.AcceptOffer then
            parseMessage("Offer accepted successfully (Mock).")
            -- Refresh offers/history
            parseHistoric(MockMarket.Historic)
            
        elseif action == MarketRequest.CancelOffer then
            parseMessage("Offer cancelled (Mock).")
            parseSales(MockMarket.Sales)
        end
    end, latency)

    return true
end

local function sendAction(action, data)
    if handleMockAction(action, data) then
        return
    end

	if protocol then
		protocol:sendExtendedJSONOpcode(MarketOpcode, {
			action = action,
			data = data
		})
	end
end

function sendCancelOffer(offer)
	local data = {
		offerId = offer.id
	}

	sendAction(MarketRequest.CancelOffer, data)
end

function sendAcceptOffer(offer, count, settings)
	local data = {
		offerId = offer.id,
		count = count,
		settings = settings
	}

	sendAction(MarketRequest.AcceptOffer, data)
end

function sendCreateOffer(item, count, price, expire)
	local data = {
		spriteId = item:getId(),
		position = item:getPosition(),
		stackpos = item:getStackPos(),
		count = count,
		price = price,
		expire = expire
	}

	sendAction(MarketRequest.CreateOffer, data)
end

function sendRequestItem(item)
	local data = {
		spriteId = item:getId(),
		position = item:getPosition(),
		stackpos = item:getStackPos()
	}

	sendAction(MarketRequest.Item, data)
end

function sendRefreshOffers(data)
	sendAction(MarketRequest.Offers, data)
end

function sendRefreshSales()
	local data = {}

	sendAction(MarketRequest.Sales, data)
end

function sendRefreshHistoric()
	local data = {}

	sendAction(MarketRequest.Historic, data)
end
