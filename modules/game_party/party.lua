local window = nil
local partyWindow = nil -- 1. Fix Global Variable Pollution
local rageCost = 0
local rageValue = 0

local BASE_HEIGHT = 110
local PARTY_MEMBER_HEIGHT = 83 -- 9. Magic number

-- Constants for Update Masks
local UPDATE_HEALTH   = 1
local UPDATE_MANA     = 2
local UPDATE_LEVEL    = 4
local UPDATE_VOCATION = 8

-- Constants for Bar Widths
local PARTY_MEMBER_HP_WIDTH = 125
local PARTY_MEMBER_MANA_WIDTH = 104
local PLAYER_HP_WIDTH = 166
local PLAYER_MANA_WIDTH = 139
local PLAYER_SPECIAL_WIDTH = 138

-- Constants for Text
local INVITE_MSG_SIMPLE = '%s convidou você para um grupo.'
local INVITE_MSG_LEVEL  = '%s convidou você para um grupo (Nível %d-%d).'

local incomingInvites = {} -- leaderId -> invite (Invites RECEIVED)
local outgoingInvites = {} -- creatureId -> {name, id} (Invites SENT)

local ui = {} -- 4. UI Cache

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

local currentMembers = {}
local currentMembersById = {} -- Map for quick access and state tracking
local vocTooltipCache = {}

local function getVocTooltip(vocId, level)
    local key = vocId .. "_" .. (level or 0)
    if not vocTooltipCache[key] then
        local vocInfo = vocations[vocId] or vocations[0]
        vocTooltipCache[key] = vocInfo[2] .. (level and (" (Level " .. level .. ")") or "")
    end
    return vocTooltipCache[key]
end

local function updateBar(bar, valueLabel, value, max, width, height)
    if max <= 0 then max = 1 end
    if value > max then max = value end

    local percent = math.floor(value / max * 100)
    valueLabel:setText(value .. "/" .. max)

    local clip = math.ceil(percent / 100 * width)
    bar:setWidth(clip)
    local clipRect = { x = 0, y = 0, width = clip, height = height }
    bar:setImageClip(clipRect)
    bar:setImageRect(clipRect)
end

local function updatePartyMembers()
    if not ui.membersList then return end
    
    local player = g_game.getLocalPlayer()
    local isLeader = player and player:isPartyLeader()
    ui.membersList:destroyChildren()
    local membersCount = #currentMembers

    -- Prepare Invites List
    local sortedInvites = {}
    for _, invite in pairs(outgoingInvites) do
        table.insert(sortedInvites, invite)
    end
    local invitesCount = #sortedInvites

    -- 1. Render Members
    for i, member in ipairs(currentMembers) do
        local row = g_ui.createWidget('PartyListRow', ui.membersList)

        row:setId('member_' .. member.id)
        row.name:setText(member.name)
        row.name:setColor('#FFFFFF') -- Standard color
        
        -- Status Icon (Green for members)
        row.statusIcon:setBackgroundColor('#00ff00')
        
        -- Leader Icon
        row.leaderIcon:setVisible(member.isLeader)
        
        -- Action Button (Kick) - Only for Leader, and not for self
        if isLeader and member.id ~= player:getId() then
            row.actionButton:setVisible(true)
            row.actionButton:setText(tr('Expulsar'))
            row.actionButton.onClick = function()
                g_game.partyRevokeInvitation(member.id)
            end
        else
            row.actionButton:setVisible(false)
        end
    end

    -- 2. Render Outgoing Invites (Gray)
    for i, invite in ipairs(sortedInvites) do
        local row = g_ui.createWidget('PartyListRow', ui.membersList)
        
        row:setId('invite_' .. invite.id)
        row.name:setText(invite.name)
        row.name:setColor('#AAAAAA') -- Gray for invited
        
        -- Status Icon (Gray for invited)
        row.statusIcon:setBackgroundColor('#AAAAAA')
        
        -- Leader Icon (Hidden)
        row.leaderIcon:setVisible(false)
        
        -- Action Button (Revoke) - Always visible for sender
        row.actionButton:setVisible(true)
        row.actionButton:setText(tr('Cancelar'))
        row.actionButton.onClick = function()
            g_game.partyRevokeInvitation(invite.id)
            outgoingInvites[invite.id] = nil
            updatePartyList()
        end
    end
end

-- updatePartyInvites removed (dead code 2a)

function updatePartyList()
    if not partyWindow then return end
    if not ui.membersList then return end
    
    updatePartyMembers()
    -- updatePartyInvites() removed
end

function onPartyInvite(leaderId, leaderName, minLevel, maxLevel)
    if minLevel == 0 and maxLevel == 0 then
        incomingInvites[leaderId] = nil
        
        if partyWindow and ui.invitesList then
            local row = ui.invitesList:getChildById(tostring(leaderId))
            if row then
                row:destroy()
            end

            if ui.invitesList:getChildCount() == 0 and ui.noInvitesLabel then
                ui.noInvitesLabel:setVisible(true)
            end
        end
        return
    end

    incomingInvites[leaderId] = { leaderName = leaderName, minLevel = minLevel, maxLevel = maxLevel }

    if not partyWindow or not ui.invitesList then return end

    if ui.noInvitesLabel then
        ui.noInvitesLabel:setVisible(false)
    end

    local rowId = tostring(leaderId)
    local row = ui.invitesList:getChildById(rowId)
    if not row then
        row = g_ui.createWidget('PartyInviteRow', ui.invitesList)
        row:setId(rowId)
    end

    row.name:setText(tr(INVITE_MSG_LEVEL, leaderName, minLevel, maxLevel))

    row.acceptButton.onClick = function()
        g_game.partyJoin(leaderId)
    end

    row.rejectButton.onClick = function()
        g_game.partyRevokeInvitation(leaderId)
    end
end

function init()
    window = g_ui.loadUI("party", g_ui.getRootWidget())
    -- Hide initially, show onGameStart
    window:hide()

    partyWindow = g_ui.displayUI("party_window")
    if partyWindow then
        partyWindow:hide()
        
        -- 4. UI Cache
        ui.membersList = partyWindow:recursiveGetChildById('membersList')
        ui.invitesPanel = partyWindow:recursiveGetChildById('invitesPanel')
        ui.invitesList = ui.invitesPanel and ui.invitesPanel:recursiveGetChildById('invitesList')
        ui.noInvitesLabel = ui.invitesPanel and ui.invitesPanel:recursiveGetChildById('noInvitesLabel')
        ui.creationPanel = partyWindow:recursiveGetChildById('creationPanel')
        ui.managementPanel = partyWindow:recursiveGetChildById('managementPanel')
        ui.invitePlayerButton = partyWindow:recursiveGetChildById('invitePlayerButton')
    else
        perror("Failed to load party_window.otui")
    end
    
    if window.player and window.player.menuButton then
        window.player.menuButton.onClick = togglePartyWindow
    end

    local settings = g_settings.getNode("partyWindow")
    if settings then
        if settings.pos then
            window:setPosition(settings.pos)
        end
    else
        window:setPosition({x = 217, y = 72})
    end

    connect(g_game, { onGameStart = onStart, onGameEnd = onEnd, onPartyDetailedInfo = onPartyDetailedInfo, onPartyMemberUpdate = onPartyMemberUpdate, onPartyInvite = onPartyInvite, onPartyManageInvite = onPartyManageInvite })
    connect(LocalPlayer, { onHealthChange = onHealthChange, onManaChange = onManaChange, onLevelChange = onLevelChange, onSpecialResourceChange = onSpecialResourceChange, onShieldChange = onShieldChange })
    -- ProtocolGame.registerExtendedOpcode(210, updateUltimateBar) 

    if g_game.isOnline() then
        onStart()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = onStart, onGameEnd = onEnd, onPartyDetailedInfo = onPartyDetailedInfo, onPartyMemberUpdate = onPartyMemberUpdate, onPartyInvite = onPartyInvite, onPartyManageInvite = onPartyManageInvite })
    disconnect(LocalPlayer, { onHealthChange = onHealthChange, onManaChange = onManaChange, onLevelChange = onLevelChange, onSpecialResourceChange = onSpecialResourceChange })

    local settings = { pos = window:getPosition() }
    g_settings.setNode("partyWindow", settings)
    window:destroy()
    if partyWindow then
        partyWindow:destroy()
    end
    ui = {} -- Clear cache
    -- ProtocolGame.unregisterExtendedOpcode(210, updateUltimateBar)
end

function togglePartyWindow()
    if not partyWindow then return end
    
    local player = g_game.getLocalPlayer()
    local hasParty = player and player:isPartyMember()
    updatePartyWindowView(hasParty)

    if partyWindow:isVisible() then
        partyWindow:hide()
    else
        partyWindow:show()
        partyWindow:raise()
        partyWindow:focus()
    end
end

function updatePartyWindowView(hasParty)
    if not partyWindow then return end
    
    local creationPanel = ui.creationPanel
    local managementPanel = ui.managementPanel
    
    if hasParty then
        if creationPanel then creationPanel:setVisible(false) end
        if managementPanel then managementPanel:setVisible(true) end

        -- Handle Leader-Only elements
        local player = g_game.getLocalPlayer()
        local isLeader = player and player:isPartyLeader()
        local invitePlayerButton = ui.invitePlayerButton
        
        if invitePlayerButton then
            invitePlayerButton:setVisible(isLeader)
        end
    else
        if creationPanel then creationPanel:setVisible(true) end
        if managementPanel then managementPanel:setVisible(false) end
    end

    if hasParty then return end

    if not ui.invitesList then return end

    local noInvitesLabel = ui.noInvitesLabel

    for _, child in ipairs(ui.invitesList:getChildren()) do
        child:destroy()
    end

    for leaderId, invite in pairs(incomingInvites) do
        local row = g_ui.createWidget('PartyInviteRow', ui.invitesList)
        row:setId(tostring(leaderId))
        row.name:setText(tr(INVITE_MSG_SIMPLE, invite.leaderName or tostring(leaderId)))

        row.acceptButton.onClick = function()
            g_game.partyJoin(leaderId)
        end

        row.rejectButton.onClick = function()
            g_game.partyRevokeInvitation(leaderId)
        end
    end

    if noInvitesLabel then
        noInvitesLabel:setVisible(ui.invitesList:getChildCount() == 0)
    end
end

function createPrivateParty()
    g_game.partyCreate()
end

function resetPartyState()
    incomingInvites = {}
    outgoingInvites = {}
    currentMembers = {}
    currentMembersById = {}
end


function leaveParty()
    g_game.partyLeave()
    if partyWindow then
        partyWindow:hide()
    end
end

function onEnd()
    -- Do not hide window, just clear party members?
    -- User wants player panel always visible?
    -- Usually onEnd means game ended (logout), so we SHOULD hide or destroy.
    window:hide()
    clearParty()
    resetPartyState()
    updatePartyIcon(false)
    
    if partyWindow and ui.invitesList then
        ui.invitesList:destroyChildren()
        if ui.noInvitesLabel then
            ui.noInvitesLabel:setVisible(true)
        end
    end
    
    vocTooltipCache = {} -- 7. Clear tooltip cache
end

function onStart()
    window:show()
    clearParty()
    updatePartyIcon(false)
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

function updatePartyIcon(hasParty)
    if not window or not window.menuButton then return end
    
    if hasParty then
        window.menuButton:setIcon("/images/profile/icon_party")
    else
        window.menuButton:setIcon("/images/profile/icon_party_create")
    end
end

local function syncPartyState(partyId, leaderId, members)
    currentMembers = members
    currentMembersById = {}
    for _, member in ipairs(members) do
        currentMembersById[member.id] = member
        -- Remove from outgoing invites if accepted
        if outgoingInvites[member.id] then
            outgoingInvites[member.id] = nil
        end
    end
end

local function updateLocalPlayerFromParty(player, members)
    -- Optimize lookup using ID map instead of iterating the list
    local member = currentMembersById[player:getId()]
    if member then
        updatePlayerWidget(player, member.health, member.maxHealth, member.mana, member.maxMana, member.level, member.vocation)
        return true
    end
    return false
end

local function rebuildPartyUI(player, members)
    updatePartyList()
    
    local playerID = player:getId()
    local activeMemberIds = {}
    
    -- Update/Create widgets for current members (excluding self)
    for i, member in ipairs(members) do
        if member.id ~= playerID then
            updatePartyMemberWidget(member)
            activeMemberIds[member.id] = true
        end
    end

    -- Remove widgets for members who left
    if window.contentsPanel then
        local children = window.contentsPanel:getChildren()
        for i, child in ipairs(children) do
             local id = tonumber(child:getId())
             -- If child has no ID or ID is not in active list, destroy it
             if not id or not activeMemberIds[id] then
                 child:destroy()
             end
        end
        
        -- Update Height
        window:setHeight(BASE_HEIGHT + window.contentsPanel:getChildCount() * PARTY_MEMBER_HEIGHT)
    end
end

function onPartyDetailedInfo(partyId, leaderId, members)
    if not window then return end
    
    local player = g_game.getLocalPlayer()
    if not player then return end

    local hasParty = player:isPartyMember() or (#members > 0)
    updatePartyIcon(hasParty)
    updatePartyWindowView(hasParty)

    if hasParty and incomingInvites[leaderId] then
        incomingInvites[leaderId] = nil
        updatePartyList()
    end

    if not hasParty then
        updatePartyIcon(false)
        updatePartyWindowView(false)
        clearParty()
        if partyWindow then partyWindow:hide() end
        outgoingInvites = {}
        return
    end

    -- Update Local Player (Initial state)
    updatePlayerWidget(player, player:getHealth(), player:getMaxHealth(), player:getMana(), player:getMaxMana(), player:getLevel())

    if #members == 0 then
        clearParty() -- Clear UI if no members
        window:hide()
        outgoingInvites = {} -- Clear invites
        return
    end

    window:show()

    -- Sync and Rebuild (Pooling enabled)
    syncPartyState(partyId, leaderId, members)
    updateLocalPlayerFromParty(player, members)
    rebuildPartyUI(player, members)
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

function updatePartyMemberWidget(member)
    local id = tostring(member.id)
    local widget = window.contentsPanel:getChildById(id)
    
    if not widget then
        widget = g_ui.createWidget("PartyMember", window.contentsPanel)
        widget:setId(id)
        widget.onHoverChange = onHoverMember
        widget.onMouseRelease = onMouseRelease
        widget.onTouchRelease = onMouseRelease
        window:setHeight(BASE_HEIGHT + window.contentsPanel:getChildCount() * PARTY_MEMBER_HEIGHT)
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
    widget.hpBar:show()
    updateBar(widget.hpBar, widget.valueHp, member.health, member.maxHealth, PARTY_MEMBER_HP_WIDTH, 22)

    -- Mana
    widget.manaBar:show()
    updateBar(widget.manaBar, widget.valueMana, member.mana, member.maxMana, PARTY_MEMBER_MANA_WIDTH, 20)

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

function onHoverMember(widget, hovered)
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

local function clearPartyMembersUI()
    if window then
        window:setHeight(BASE_HEIGHT)
        if window.contentsPanel then
            window.contentsPanel:destroyChildren()
        end
    end
end

local function clearPartyListUI()
    if ui.membersList then
        ui.membersList:destroyChildren()
    end
end

function clearParty()
    clearPartyMembersUI()
    clearPartyListUI()
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
    window.player.hpBar:show()
    updateBar(window.player.hpBar, window.player.valueHp, health, maxHealth, PLAYER_HP_WIDTH, 29)
end

function onManaChange(localPlayer, mana, maxMana)
    if not window or not window.player then return end
    window.player.manaBar:show()
    updateBar(window.player.manaBar, window.player.valueMana, mana, maxMana, PLAYER_MANA_WIDTH, 26)
end

function onSpecialResourceChange(localPlayer, specialResource, maxSpecialResource)
    if not window or not window.player then return end
    window.player.specialResourceBar:show()
    updateBar(window.player.specialResourceBar, window.player.valueSpecialResource, specialResource, maxSpecialResource, PLAYER_SPECIAL_WIDTH, 17)
end

function onLevelChange(localPlayer, level, percent)
    if not window or not window.player then return end
    
    local vocId = localPlayer:getVocation()
    window.player.icon:setTooltip(getVocTooltip(vocId, level))
end

-- ---------------------------------------------------------
-- Heuristic Fallbacks (REMOVED)
-- ---------------------------------------------------------

function onPartyManageInvite(action, playerId, playerName)
    if action == 2 then -- REVOKE (Received by Target)
        -- playerId is Leader ID
        incomingInvites[playerId] = nil
        
        if partyWindow and ui.invitesList then
            local row = ui.invitesList:getChildById(tostring(playerId))
            if row then
                row:destroy()
            end

            if ui.invitesList:getChildCount() == 0 and ui.noInvitesLabel then
                ui.noInvitesLabel:setVisible(true)
            end
        end

    elseif action == 3 then -- TARGET_REMOVED (Received by Leader)
        -- playerId is Target ID
        outgoingInvites[playerId] = nil
        updatePartyList()

    elseif action == 4 then -- TARGET_ADDED (Received by Leader)
        -- playerId is Target ID
        outgoingInvites[playerId] = { name = playerName, id = playerId }
        updatePartyList()
    end
end

function onShieldChange(player, shield)
    local localPlayer = g_game.getLocalPlayer()
    if not localPlayer or not player then return end

    if player:getId() ~= localPlayer:getId() then return end

    local hasParty = localPlayer:isPartyMember()
    updatePartyIcon(hasParty)
    updatePartyWindowView(hasParty)
    if not hasParty then
        clearParty()
        resetPartyState()
        if partyWindow then
            partyWindow:hide()
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
        if band(mask, UPDATE_VOCATION) ~= 0 or band(mask, UPDATE_LEVEL) ~= 0 then
            local lv = band(mask, UPDATE_LEVEL) ~= 0 and member.level or player:getLevel()
            local vocId = band(mask, UPDATE_VOCATION) ~= 0 and member.vocation or player:getVocation()
            local vocInfo = vocations[vocId] or vocations[0]
            window.player.icon:setIconClip(vocInfo[1])
            window.player.icon:setTooltip(getVocTooltip(vocId, lv))
        end
        else
        -- 1. Update Logical State (Source of Truth)
        local mask = member.mask or 0
        local cachedMember = currentMembersById[member.id]

        if cachedMember then
            if band(mask, UPDATE_HEALTH) ~= 0 then
                cachedMember.health = member.health or cachedMember.health
                cachedMember.maxHealth = member.maxHealth or cachedMember.maxHealth
            end
            if band(mask, UPDATE_MANA) ~= 0 then
                cachedMember.mana = member.mana or cachedMember.mana
                cachedMember.maxMana = member.maxMana or cachedMember.maxMana
            end
            if band(mask, UPDATE_LEVEL) ~= 0 then
                cachedMember.level = member.level or cachedMember.level
            end
            if band(mask, UPDATE_VOCATION) ~= 0 then
                cachedMember.vocation = member.vocation or cachedMember.vocation
            end
        end

        -- 2. Update UI if exists (Read from Logical State)
        local id = tostring(member.id)
        local widget = window.contentsPanel:getChildById(id)
        if widget and cachedMember then
            -- Sync widget properties to Logical State (optional, for consistency)
            widget.health = cachedMember.health
            widget.maxHealth = cachedMember.maxHealth
            widget.mana = cachedMember.mana
            widget.maxMana = cachedMember.maxMana
            widget.level = cachedMember.level
            widget.vocation = cachedMember.vocation

            -- Update Visuals
            if band(mask, UPDATE_VOCATION) ~= 0 or band(mask, UPDATE_LEVEL) ~= 0 then
                local vocInfo = vocations[cachedMember.vocation] or vocations[0]
                widget.icon:setIconClip(vocInfo[1])
                widget.icon:setTooltip(getVocTooltip(cachedMember.vocation, cachedMember.level))
            end

            if band(mask, UPDATE_HEALTH) ~= 0 then
                updateBar(widget.hpBar, widget.valueHp, cachedMember.health, cachedMember.maxHealth, PARTY_MEMBER_HP_WIDTH, 22)
            end

            if band(mask, UPDATE_MANA) ~= 0 then
                updateBar(widget.manaBar, widget.valueMana, cachedMember.mana, cachedMember.maxMana, PARTY_MEMBER_MANA_WIDTH, 20)
            end
        end
    end
end

function toggleMenu()
    if not window then return end
    local optionsPanel = window.optionsPanel
    if not optionsPanel then return end
    
    if optionsPanel:isVisible() then
        optionsPanel:setVisible(false)
        optionsPanel:setWidth(0)
        window:setWidth(256)
    else
        optionsPanel:setVisible(true)
        optionsPanel:setWidth(150)
        window:setWidth(256 + 150)
    end
end

function onToggleMinimap(checked)
    g_logger.info("Minimap party show: " .. tostring(checked))
end

function onToggleLoot(checked)
    g_logger.info("Loot share: " .. tostring(checked))
end

function onToggleExp(checked)
    g_logger.info("Exp share: " .. tostring(checked))
end

function invitePlayer()
    displayTextInputBox(tr('Invite to Party'), tr('Player Name:'), function(name)
        local creature = g_map.getCreatureByName(name)
        if creature then
            local id = creature:getId()
            g_game.partyInvite(id)
            
            -- Track outgoing invite
            outgoingInvites[id] = { name = creature:getName(), id = id }
            updatePartyList()
        else
            modules.game_textmessage.displayGameMessage(tr('Player %s not found.', name))
        end
    end, function() end)
end
