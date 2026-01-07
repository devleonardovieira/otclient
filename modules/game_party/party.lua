local window = nil
local rageCost = 0
local rageValue = 0

local BASE_HEIGHT = 110

local shields = {
    [0] = "0 0 1 1", -- Transparente/Vazio
    "0 0 11 11",
    "0 11 11 11",
    "0 22 11 11",
    "0 33 11 11",
    "0 44 11 11",
    "0 55 11 11",
    "0 77 11 11",
    "0 66 11 11",
    "0 77 11 11",
    "0 66 11 11"
}

local vocations = {
    [0] = { "0 0 28 28", "No Vocation" },
    { "0 0 28 28", "Sorcerer" },
    { "0 28 28 28", "Druid" },
    { "0 56 28 28", "Archer" },
    { "0 84 28 28", "Knight" },
    [5] = { "0 0 28 28", "Master Sorcerer" },
    [9] = { "0 0 28 28", "Wizard" },
    [13] = { "0 0 28 28", "Soul Wizard" },
    [6] = { "0 28 28 28", "Elder Druid" },
    [10] = { "0 28 28 28", "Shaman" },
    [14] = { "0 28 28 28", "Ancient Shaman" },
    [7] = { "0 56 28 28", "Swift Archer" },
    [11] = { "0 56 28 28", "Sniper" },
    [15] = { "0 56 28 28", "Deadly Sniper" },
    [8] = { "0 84 28 28", "Elite Knight" },
    [12] = { "0 84 28 28", "Warrior" },
    [16] = { "0 84 28 28", "Slayer" },
    [17] = { "0 112 28 28", "Paladin" },
    [18] = { "0 112 28 28", "Royal Paladin" },
    [19] = { "0 112 28 28", "Holy Paladin" },
    [20] = { "0 112 28 28", "Saint Paladin" },
    [21] = { "0 140 28 28", "Shadow" },
    [22] = { "0 140 28 28", "Hidden Shadow" },
    [23] = { "0 140 28 28", "Dark Shadow" },
    [24] = { "0 140 28 28", "Void Shadow" }
}

local function band(m, b)
    if _G.bit and _G.bit.band then return _G.bit.band(m, b) end
    if _G.bit32 and _G.bit32.band then return _G.bit32.band(m, b) end
    return (m % (b + b) >= b) and b or 0
end

local function getVocTooltip(vocId, level)
    local vocInfo = vocations[vocId] or vocations[0]
    return vocInfo[2] .. (level and (" (Level " .. level .. ")") or "")
end

function init()
    window = g_ui.loadUI("party", g_ui.getRootWidget())
    -- Hide initially, show onGameStart
    window:hide()

    local settings = g_settings.getNode("partyWindow")
    if settings then
        if settings.pos then
            window:setPosition(settings.pos)
        end
    else
        window:setPosition({x = 217, y = 72})
    end

    connect(g_game, { onGameStart = onStart, onGameEnd = onEnd, onPartyDetailedInfo = onPartyDetailedInfo, onPartyMemberUpdate = onPartyMemberUpdate })
    connect(LocalPlayer, { onHealthChange = onHealthChange, onManaChange = onManaChange, onLevelChange = onLevelChange, onSpecialResourceChange = onSpecialResourceChange, onShieldChange = onShieldChange })
    -- ProtocolGame.registerExtendedOpcode(210, updateUltimateBar) 

    if g_game.isOnline() then
        onStart()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = onStart, onGameEnd = onEnd, onPartyDetailedInfo = onPartyDetailedInfo, onPartyMemberUpdate = onPartyMemberUpdate })
    disconnect(LocalPlayer, { onHealthChange = onHealthChange, onManaChange = onManaChange, onLevelChange = onLevelChange, onSpecialResourceChange = onSpecialResourceChange, onShieldChange = onShieldChange })

    local settings = { pos = window:getPosition() }
    g_settings.setNode("partyWindow", settings)
    window:destroy()
    -- ProtocolGame.unregisterExtendedOpcode(210, updateUltimateBar)
end

function onEnd()
    -- Do not hide window, just clear party members?
    -- User wants player panel always visible?
    -- Usually onEnd means game ended (logout), so we SHOULD hide or destroy.
    window:hide()
    clearParty()
end

function onStart()
    window:show()
    clearParty()
    local player = g_game.getLocalPlayer()
    if player then
        updatePlayerWidget(player, player:getHealth(), player:getMaxHealth(), player:getMana(), player:getMaxMana(), player:getLevel())
    end
end

function updateUltimateBar(protocol, code, buffer)
    local status, data = pcall(function() return json.decode(buffer) end)
    if not status then return end

    if data.info then
        rageCost = data.info.required
        rageValue = data.info.rage
        window.player.valueUlti:setText(data.info.rage .. " / 10")
        
        local clip = (data.info.rage * 10 - 5) / 100 * 138
        clip = math.ceil(clip)
        
        window.player.ultiBar:show()
        window.player.ultiBar:setWidth(clip)
        
        local clipRect = { height = 17, x = 0, y = 0, width = clip }
        window.player.ultiBar:setImageClip(clipRect)
    end
end

function onPartyDetailedInfo(partyId, leaderId, members)
    if not window then return end
    
    local player = g_game.getLocalPlayer()
    if not player then return end

    -- 1. Full Sync: Clear everything first
    clearParty()

    -- 2. Update Local Player (Initial state)
    updatePlayerWidget(player, player:getHealth(), player:getMaxHealth(), player:getMana(), player:getMaxMana(), player:getLevel())

    if #members == 0 then
        return
    end

    window:show()

    -- 3. Rebuild Members (Create new widgets)
    for i, member in ipairs(members) do
        if member.id == player:getId() then
            -- Update local player with packet data
            updatePlayerWidget(player, member.health, member.maxHealth, member.mana, member.maxMana, member.level, member.vocation)
        else
            -- Create widget for other members
            -- Since we cleared, this will always create a new widget
            updatePartyMemberWidget(member, leaderId)
        end
    end
end

function updatePlayerWidget(player, health, maxHealth, mana, maxMana, level, vocation)
    if not window or not window.player then return end

    -- Vocation Icon
    local vocId = vocation or player:getVocation()
    local vocInfo = vocations[vocId] or vocations[0]
    window.player.icon:setIconClip(vocInfo[1])
    window.player.icon:setTooltip(getVocTooltip(vocId, level))

    -- Outfit
    window.player.outfit:setOutfit(player:getOutfit())

    -- Health
    onHealthChange(player, health, maxHealth)
    -- Mana
    onManaChange(player, mana, maxMana)
    -- Special Resource
    if window.player.specialResourceBar:isVisible() then
        onSpecialResourceChange(player, player:getSpecialResource(), player:getMaxSpecialResource())
    end
end

function updatePartyMemberWidget(member, leaderId)
    local id = tostring(member.id)
    local widget = window.contentsPanel:getChildById(id)
    
    if not widget then
        widget = g_ui.createWidget("PartyMember", window.contentsPanel)
        widget:setId(id)
        widget.onHoverChange = onHovermember
        widget.onMouseRelease = onMouseRelease
        widget.onTouchRelease = onMouseRelease
        window:setHeight(BASE_HEIGHT + window.contentsPanel:getChildCount() * 83)
    end

    -- Store values for partial updates
    widget.health = member.health
    widget.maxHealth = member.maxHealth
    widget.mana = member.mana
    widget.maxMana = member.maxMana
    widget.level = member.level
    widget.vocation = member.vocation
    widget.nameStr = member.name -- Avoid name collision with widget.name

    -- Name
    widget.isLeader = member.isLeader
    local displayName = member.name .. (member.isLeader and " (Leader)" or "")
    widget.name:setText(displayName)
    if widget.isLeader then
        widget.name:setColor('#FFD700')
    else
        widget.name:setColor('#FFFFFF')
    end

    -- Vocation Icon + Level no tooltip
    local vocInfo = vocations[member.vocation] or vocations[0]
    widget.icon:setIconClip(vocInfo[1])
    widget.icon:setTooltip(getVocTooltip(member.vocation, member.level))

    -- Shield / Leader Status
    local shieldIndex = member.isLeader and 1 or 0
    local shieldInfo = shields[shieldIndex] or shields[0]
    widget.shield:setIconClip(shieldInfo)

    -- Health
    if member.maxHealth <= 0 then member.maxHealth = 1 end
    local healthPercent = math.floor(member.health / member.maxHealth * 100)
    widget.valueHp:setText(member.health .. "/" .. member.maxHealth)
    local hpClip = math.ceil(healthPercent / 100 * 125)
    widget.hpBar:show()
    widget.hpBar:setWidth(hpClip)
    local hpRect = { height = 22, x = 0, y = 0, width = hpClip }
    widget.hpBar:setImageClip(hpRect)

    -- Mana
    if member.maxMana <= 0 then member.maxMana = 1 end
    local manaPercent = math.floor(member.mana / member.maxMana * 100)
    widget.valueMana:setText(member.mana .. " / " .. member.maxMana)
    local manaClip = math.ceil(manaPercent / 100 * 104)
    widget.manaBar:show()
    widget.manaBar:setWidth(manaClip)
    local manaRect = { height = 20, x = 0, y = 0, width = manaClip }
    widget.manaBar:setImageClip(manaRect)

    -- Outfit
    local creature = g_map.getCreatureById(member.id)
    if creature then
        widget.outfit:setOutfit(creature:getOutfit())
        widget.outfit:show()
        widget.nooutfit:hide()
    else
        widget.outfit:hide()
        widget.nooutfit:show()
    end
end

function onHovermember(widget, hovered)
    if hovered then
        window:setBackgroundColor("#ffffff54")
        window:setBorderColor("black")
        if widget.circle then
            widget.circle:setImageColor("#cb5e00")
        end
        g_tooltip.display(widget.tooltip)
    else
        window:setBackgroundColor("alpha")
        window:setBorderColor("alpha")
        if widget.circle then
            widget.circle:setImageColor("black")
        end
        g_tooltip.hide()
    end
end


function clearParty()
    if window then
        window:setHeight(BASE_HEIGHT)
        window.contentsPanel:destroyChildren()
    end
end

function onMouseRelease(widget, mousePos, mouseButton)
    if mouseButton == MouseTouch then return end

    if mouseButton == MouseRightButton then
        local menu = g_ui.createWidget("PopupMenu")
        menu:setGameMenu(true)

        local player = g_game.getLocalPlayer()
        if not player then return end
        
        local memberId = tonumber(widget:getId())
        
        if g_game.isPartyLeader() then 
             menu:addOption(tr("Pass leader to %s", widget.nameStr), function()
                g_game.partyPassLeadership(memberId)
            end)
        end

        menu:addOption(tr("Leave party"), function() g_game.partyLeave() end)
        menu:display(mousePos)
    end
end

function onHealthChange(localPlayer, health, maxHealth)
    if not window or not window.player then return end
    
    if maxHealth <= 0 then maxHealth = 1 end
    
    if maxHealth < health then maxHealth = health end
    local percentHealth = math.floor(health / maxHealth * 100)
    window.player.valueHp:setText(health .. "/" .. maxHealth)

    local clip = math.ceil(percentHealth / 100 * 166)
    window.player.hpBar:show()
    window.player.hpBar:setWidth(clip)
    
    local clipRect = { height = 29, x = 0, y = 0, width = clip }
    window.player.hpBar:setImageClip(clipRect)
    window.player.hpBar:setImageRect(clipRect)
end

function onManaChange(localPlayer, mana, maxMana)
    if not window or not window.player then return end

    if maxMana <= 0 then maxMana = 1 end

    if maxMana < mana then maxMana = mana end
    local percentMana = math.floor(mana / maxMana * 100)
    window.player.valueMana:setText(mana .. " / " .. maxMana)

    local clip = math.ceil(percentMana / 100 * 139)
    window.player.manaBar:show()
    window.player.manaBar:setWidth(clip)
    
    local clipRect = { height = 26, x = 0, y = 0, width = clip }
    window.player.manaBar:setImageClip(clipRect)
    window.player.manaBar:setImageRect(clipRect)
end

function onSpecialResourceChange(localPlayer, specialResource, maxSpecialResource)
    if not window or not window.player then return end

    if maxSpecialResource <= 0 then maxSpecialResource = 1 end

    if maxSpecialResource < specialResource then maxSpecialResource = specialResource end
    local percentSpecialResource = math.floor(specialResource / maxSpecialResource * 100)
    window.player.valueSpecialResource:setText(specialResource .. " / " .. maxSpecialResource)

    local clip = math.ceil(percentSpecialResource / 100 * 138)
    window.player.specialResourceBar:show()
    window.player.specialResourceBar:setWidth(clip)
    
    local clipRect = { height = 17, x = 0, y = 0, width = clip }
    window.player.specialResourceBar:setImageClip(clipRect)
    window.player.specialResourceBar:setImageRect(clipRect)
end

function onLevelChange(localPlayer, level, percent)
    if not window or not window.player then return end
    
    local vocId = localPlayer:getVocation()
    window.player.icon:setTooltip(getVocTooltip(vocId, level))
end

function onShieldChange(player, shield)
    -- ShieldNone (0), ShieldWhiteBlue (1), ShieldWhiteYellow (2) mean not in a party
    if shield <= 2 and window.contentsPanel:getChildCount() > 0 then
        clearParty()
        -- Ensure window stays visible for local player
        window:show()
        local lp = g_game.getLocalPlayer()
        if lp then
            updatePlayerWidget(lp, lp:getHealth(), lp:getMaxHealth(), lp:getMana(), lp:getMaxMana(), lp:getLevel())
        end
    end
end

function onPartyMemberUpdate(member)
    if not window then return end
    
    local player = g_game.getLocalPlayer()
    if player and player:getId() == member.id then
         -- Local player update
         local mask = member.mask or 0

         -- For local player, mostly rely on LocalPlayer events.
         -- But handle Vocation if needed
        if band(mask, 8) ~= 0 or band(mask, 4) ~= 0 then
            local lv = band(mask, 4) ~= 0 and member.level or player:getLevel()
            local vocId = band(mask, 8) ~= 0 and member.vocation or player:getVocation()
            local vocInfo = vocations[vocId] or vocations[0]
            window.player.icon:setIconClip(vocInfo[1])
            window.player.icon:setTooltip(getVocTooltip(vocId, lv))
        end
    else
        local id = tostring(member.id)
        local widget = window.contentsPanel:getChildById(id)
        if widget then
            -- Partial Update Logic
            local mask = member.mask or 0

            -- Update cached values (Canary flags)
            if band(mask, 1) ~= 0 then
                widget.health = member.health or widget.health or 0
                widget.maxHealth = member.maxHealth or widget.maxHealth or 1
            end
            if band(mask, 2) ~= 0 then
                widget.mana = member.mana or widget.mana or 0
                widget.maxMana = member.maxMana or widget.maxMana or 1
            end
            if band(mask, 4) ~= 0 then widget.level = member.level or widget.level or 0 end
            if band(mask, 8) ~= 0 then widget.vocation = member.vocation or widget.vocation or 0 end
            
            -- Update UI
            if band(mask, 8) ~= 0 or band(mask, 4) ~= 0 then -- Vocation or Level
                local vocInfo = vocations[widget.vocation] or vocations[0]
                widget.icon:setIconClip(vocInfo[1])
                widget.icon:setTooltip(getVocTooltip(widget.vocation, widget.level))
            end

            -- Health (flag 1 includes both current and max)
            if band(mask, 1) ~= 0 then
                local hp = widget.health or 0
                local maxHp = widget.maxHealth or 1
                if maxHp <= 0 then maxHp = 1 end
                local healthPercent = math.floor(hp / maxHp * 100)
                widget.valueHp:setText(hp .. "/" .. maxHp)
                local hpClip = math.ceil(healthPercent / 100 * 125)
                widget.hpBar:setWidth(hpClip)
                local hpRect = { height = 22, x = 0, y = 0, width = hpClip }
                widget.hpBar:setImageClip(hpRect)
                widget.hpBar:setImageRect(hpRect)
            end

            -- Mana (flag 2 includes both current and max)
            if band(mask, 2) ~= 0 then
                local mn = widget.mana or 0
                local maxMn = widget.maxMana or 1
                if maxMn <= 0 then maxMn = 1 end
                local manaPercent = math.floor(mn / maxMn * 100)
                widget.valueMana:setText(mn .. " / " .. maxMn)
                local manaClip = math.ceil(manaPercent / 100 * 104)
                widget.manaBar:setWidth(manaClip)
                local manaRect = { height = 20, x = 0, y = 0, width = manaClip }
                widget.manaBar:setImageClip(manaRect)
                widget.manaBar:setImageRect(manaRect)
            end
        end
    end
end
