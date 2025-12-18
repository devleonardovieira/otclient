-- Mock Data for Game Market

MockMarket = {}

MockMarket.Config = {
    enabled = true,
    latency = 200 -- ms
}

MockMarket.Offers = {
    page = 1,
    pageSize = 10,
    search = "",
    sortType = 0,
    sortField = "price",
    categoryId = 0,
    data = {
        {
            id = 1,
            clientId = 2160, -- Crystal Coin
            name = "Crystal Coin",
            count = 10,
            price = 100000,
            playerName = "RichPlayer",
            description = "Shiny coins for sale."
        },
        {
            id = 2,
            clientId = 2400, -- Magic Sword (SOV)
            name = "Magic Sword",
            count = 1,
            price = 500000,
            playerName = "KnightMaster",
            description = "Powerful sword."
        },
        {
            id = 3,
            clientId = 2498, -- Royal Helmet
            name = "Royal Helmet",
            count = 1,
            price = 45000,
            playerName = "PaladinStar",
            description = "Protects your head."
        },
        {
            id = 4,
            clientId = 2173, -- Amulet of Loss
            name = "Amulet of Loss",
            count = 5,
            price = 50000,
            playerName = "SorcererSupreme",
            description = "Don't lose your items."
        },
        {
            id = 5,
            clientId = 2195, -- Boots of Haste
            name = "Boots of Haste",
            count = 1,
            price = 30000,
            playerName = "SpeedyGonzales",
            description = "Gotta go fast."
        },
        {
            id = 6,
            clientId = 2160, -- Crystal Coin
            name = "Crystal Coin",
            count = 100,
            price = 1000000,
            playerName = "Banker",
            description = "Bulk sale."
        },
        {
            id = 7,
            clientId = 2152, -- Platinum Coin
            name = "Platinum Coin",
            count = 50,
            price = 5000,
            playerName = "TraderJoe",
            description = "Small change."
        }
    }
}

MockMarket.Sales = {
    {
        id = 101,
        clientId = 2392, -- Fire Sword
        name = "Fire Sword",
        count = 1,
        price = 4000,
        created = 3600, -- 1 hour remaining
        description = "Hot blade."
    },
    {
        id = 102,
        clientId = 2514, -- Mastermind Shield
        name = "Mastermind Shield",
        count = 1,
        price = 60000,
        created = 7200, -- 2 hours remaining
        description = "High defense."
    }
}

MockMarket.Historic = {
    {
        description = "You bought 10 Crystal Coin from RichPlayer for 100000 gold."
    },
    {
        description = "You sold 1 Magic Plate Armor for 150000 gold."
    },
    {
        description = "You cancelled offer for Dragon Scale Mail."
    }
}

MockMarket.ItemRequest = {
    clientId = 2160,
    count = 100,
    fee = 0.01,
    maxFee = 1000,
    description = "Mocked item details."
}

function MockMarket.getOffers(page, search, sortType, sortField, categoryId)
    -- In a real mock, we might filter MockMarket.Offers.data based on params
    -- For now, just return the static list but update metadata
    local result = table.copy(MockMarket.Offers)
    result.page = page or 1
    result.search = search or ""
    result.sortType = sortType
    result.sortField = sortField
    result.categoryId = categoryId
    return result
end
