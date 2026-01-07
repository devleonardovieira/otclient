local window = nil
local rageCost = 0
local rageValue = 0

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

function init()
    window = g_ui.loadUI("party", g_ui.getRootWidget())
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
    -- ProtocolGame.registerExtendedOpcode(210, updateUltimateBar) -- Keep if still used, or remove if obsolete

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
    window:hide()
    clearParty()
end

function onStart()
    window:show()
    -- Initial update can be handled when we receive the packet or just clear for now
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
        window.player.ultiBar:setImageRect(clipRect)
    end
end

function onPartyDetailedInfo(partyId, leaderId, members)
    if not window then return end
    
    local player = g_game.getLocalPlayer()
    if not player then return end

    local playerId = player:getId()
    local membersMap = {}
    
    -- Check if we are in the party (members list should contain us if we are)
    local amIMember = false
    for _, member in ipairs(members) do
        if member.id == playerId then
            amIMember = true
            break
        end
    end

    if not amIMember and #members > 0 then
        -- Maybe we just left? Or the list doesn't include us? 
        -- Usually detailed info is sent to members. 
        -- If list is empty, we assume party is disbanded or we left.
    end

    if #members == 0 then
        clearParty()
        return
    end

    window:show()

    -- Process members
    for i, member in ipairs(members) do
        if member.id == playerId then
            -- Update local player widget
            updatePlayerWidget(player, member.health, member.maxHealth, member.mana, member.maxMana, member.level)
        else
            -- Update or add other members
            updatePartyMemberWidget(member, leaderId)
            membersMap[tostring(member.id)] = true
        end
    end

    -- Remove members that are no longer in the list
    local children = window.contentsPanel:getChildren()
    for _, child in pairs(children) do
        if not membersMap[child:getId()] then
            window:setHeight(window:getHeight() - 83)
            child:destroy()
        end
    end
end

function updatePlayerWidget(player, health, maxHealth, mana, maxMana, level)
    if not window or not window.player then return end

    -- Vocation Icon
    local vocId = player:getVocation()
    local vocInfo = vocations[vocId] or vocations[0]
    window.player.icon:setIconClip(vocInfo[1])
    window.player.icon:setTooltip(vocInfo[2] .. (level and (" (Level " .. level .. ")") or ""))

    -- Outfit
    window.player.outfit:setOutfit(player:getOutfit())

    -- Health
    onHealthChange(player, health, maxHealth)
    -- Mana
    onManaChange(player, mana, maxMana)
    -- Special Resource (keep existing logic)
    onSpecialResourceChange(player, player:getSpecialResource(), player:getMaxSpecialResource())
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
        window:setHeight(window:getHeight() + 83)
    end

    -- Name
    widget.name:setText(member.name)

    -- Vocation Icon
    local vocInfo = vocations[member.vocation] or vocations[0]
    widget.icon:setIconClip(vocInfo[1])
    widget.icon:setTooltip(vocInfo[2])

    -- Shield / Leader Status
    -- member.isLeader is from the packet. 
    -- If isLeader is true, show a leader shield/icon?
    -- The old code used 'shield' index. 
    -- Assuming leader has a specific shield index or we just use a generic one.
    -- Shields table: 0=Empty, 1=Yellow Shield? 
    -- Let's use 1 for leader for now, or 0 if not.
    local shieldIndex = member.isLeader and 1 or 0
    local shieldInfo = shields[shieldIndex] or shields[0]
    widget.shield:setIconClip(shieldInfo)

    -- Health
    if member.maxHealth <= 0 then member.maxHealth = 1 end
    local healthPercent = math.floor(member.health / member.maxHealth * 100)
    widget.valueHp:setText(healthPercent .. "%")
    local hpClip = math.ceil(healthPercent / 100 * 125)
    widget.hpBar:show()
    widget.hpBar:setWidth(hpClip)
    local hpRect = { height = 22, x = 0, y = 0, width = hpClip }
    widget.hpBar:setImageClip(hpRect)
    widget.hpBar:setImageRect(hpRect)

    -- Mana
    if member.maxMana <= 0 then member.maxMana = 1 end
    local manaPercent = math.floor(member.mana / member.maxMana * 100)
    widget.valueMana:setText(manaPercent .. "%")
    local manaClip = math.ceil(manaPercent / 100 * 104)
    widget.manaBar:show()
    widget.manaBar:setWidth(manaClip)
    local manaRect = { height = 20, x = 0, y = 0, width = manaClip }
    widget.manaBar:setImageClip(manaRect)
    widget.manaBar:setImageRect(manaRect)

    -- Outfit
    -- Try to get creature from map
    local creature = g_map.getCreatureById(member.id)
    if creature then
        widget.outfit:setOutfit(creature:getOutfit())
        widget.outfit:show()
        widget.nooutfit:hide()
    else
        -- If creature is not known, we can't show outfit.
        -- Show 'nooutfit' image
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

function removemember(id)
    id = tostring(id)
    local member = window.contentsPanel:getChildById(id)
    if member then
        window:setHeight(window:getHeight() - 83)
        member:destroy()
    end
end

function clearParty()
    if window then
        window:setHeight(110)
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
        
        -- Logic for shared exp / leadership could be added here
        -- For now, basic options
        
        local memberId = tonumber(widget:getId())
        
        -- If we are leader, show leadership options
        if g_game.isPartyLeader() then -- Assuming this function exists or we track it
             menu:addOption(tr("Pass leader to %s", widget.name:getText()), function()
                g_game.partyPassLeadership(memberId)
            end)
            
            -- Kick option (standard opcode usually, but old code used custom)
            -- Standard Tibia doesn't have a simple 'kick' function exposed in g_game typically?
            -- g_game.partyLeave() exists.
        end

        menu:addOption(tr("Leave party"), function() g_game.partyLeave() end)
        menu:display(mousePos)
    end
end

function onHealthChange(localPlayer, health, maxHealth)
    if not window or not window.player then return end
    
    if maxHealth <= 0 then
        maxHealth = 1 -- Prevent division by zero
    end
    
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

    if maxMana <= 0 then
        maxMana = 1 -- Prevent division by zero
    end

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

    if maxSpecialResource <= 0 then
        maxSpecialResource = 1 -- Prevent division by zero
    end

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
    local vocInfo = vocations[vocId] or vocations[0]
    window.player.icon:setTooltip(vocInfo[2] .. " (Level " .. level .. ")")
end

function onShieldChange(player, shield)
    -- ShieldNone (0), ShieldWhiteBlue (1), ShieldWhiteYellow (2) mean not in a party
    if shield <= 2 then
        clearParty()
    end
end

function onPartyMemberUpdate(member)
    if not window then return end
    
    local player = g_game.getLocalPlayer()
    if player and player:getId() == member.id then
         updatePlayerWidget(player, member.health, member.maxHealth, member.mana, member.maxMana, member.level)
    else
        local id = tostring(member.id)
        local widget = window.contentsPanel:getChildById(id)
        if widget then
            -- Vocation Icon
            local vocInfo = vocations[member.vocation] or vocations[0]
            widget.icon:setIconClip(vocInfo[1])
            widget.icon:setTooltip(vocInfo[2])

            -- Health
            if member.maxHealth <= 0 then member.maxHealth = 1 end
            local healthPercent = math.floor(member.health / member.maxHealth * 100)
            widget.valueHp:setText(healthPercent .. "%")
            local hpClip = math.ceil(healthPercent / 100 * 125)
            widget.hpBar:setWidth(hpClip)
            local hpRect = { height = 22, x = 0, y = 0, width = hpClip }
            widget.hpBar:setImageClip(hpRect)
            widget.hpBar:setImageRect(hpRect)

            -- Mana
            if member.maxMana <= 0 then member.maxMana = 1 end
            local manaPercent = math.floor(member.mana / member.maxMana * 100)
            widget.valueMana:setText(manaPercent .. "%")
            local manaClip = math.ceil(manaPercent / 100 * 104)
            widget.manaBar:setWidth(manaClip)
            local manaRect = { height = 20, x = 0, y = 0, width = manaClip }
            widget.manaBar:setImageClip(manaRect)
            widget.manaBar:setImageRect(manaRect)
        end
    end
end
