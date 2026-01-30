local window = nil
local partyWindow = nil -- 1. Fix Global Variable Pollution

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
local publicGroups = {}
local publicGroupsOpen = false
local publicGroupPublished = false

local updatePublicGroupButton

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
local baseWidth = nil

local function getVocTooltip(vocId, level)
    local key = vocId .. "_" .. (level or 0)
    if not vocTooltipCache[key] then
        local vocInfo = vocations[vocId] or vocations[0]
        vocTooltipCache[key] = vocInfo[2] .. (level and (" (Level " .. level .. ")") or "")
    end
    return vocTooltipCache[key]
end

local function updateBar(bar, valueLabel, value, max, width, height)
    if not bar then return end
    if max <= 0 then max = 1 end
    value = math.min(value, max)

    local percent = math.floor(value / max * 100)
    if valueLabel then valueLabel:setText(value .. "/" .. max) end

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
    local localId = player and player:getId()

    -- Prepare Invites List
    local sortedInvites = {}
    for _, invite in pairs(outgoingInvites) do
        table.insert(sortedInvites, invite)
    end
    table.sort(sortedInvites, function(a, b)
        local an = a.name or tostring(a.id or "")
        local bn = b.name or tostring(b.id or "")
        return an < bn
    end)
    local desired = {}
    local ordered = {}

    -- 1. Render Members
    for i, member in ipairs(currentMembers) do
        local rowId = 'member_' .. member.id
        desired[rowId] = true
        local row = ui.membersList:getChildById(rowId)
        if not row then
            row = g_ui.createWidget('PartyListRow', ui.membersList)
            row:setId(rowId)
        end
        row.name:setText(member.name)
        row.name:setColor('#FFFFFF') -- Standard color

        -- Status Icon (Green for members)
        row.statusIcon:setBackgroundColor('#00ff00')

        -- Leader Icon
        row.leaderIcon:setVisible(member.isLeader)

        if isLeader and member.id ~= localId then
            row.actionButton:setVisible(true)
            row.actionButton:setText(tr('Expulsar'))
            row.actionButton.onClick = function()
                g_game.partyKick(member.id)
            end
        else
            row.actionButton:setVisible(false)
        end
        ordered[#ordered + 1] = row
    end

    -- 2. Render Outgoing Invites (Gray)
    for i, invite in ipairs(sortedInvites) do
        local rowId = 'invite_' .. invite.id
        desired[rowId] = true
        local row = ui.membersList:getChildById(rowId)
        if not row then
            row = g_ui.createWidget('PartyListRow', ui.membersList)
            row:setId(rowId)
        end
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
        ordered[#ordered + 1] = row
    end

    local total = ui.membersList:getChildCount()
    if ui.membersList.reorderChildren and total == #ordered then
        ui.membersList:reorderChildren(ordered)
    else
        if ui.membersList.moveChildToIndex then
            local baseIndex = 1
            local children = ui.membersList:getChildren()
            for i, c in ipairs(children) do
                local cid = c:getId()
                if cid and (string.sub(cid, 1, 7) == 'member_' or string.sub(cid, 1, 7) == 'invite_') then
                    baseIndex = i
                    break
                end
            end
            for i, child in ipairs(ordered) do
                ui.membersList:moveChildToIndex(child, baseIndex + i - 1)
            end
        else
            local children = ui.membersList:getChildren()
            for _, c in ipairs(children) do
                local cid = c:getId()
                if cid and (string.sub(cid, 1, 7) == 'member_' or string.sub(cid, 1, 7) == 'invite_') then
                    c:destroy()
                end
            end
            for i, member in ipairs(currentMembers) do
                local rowId = 'member_' .. member.id
                local row = g_ui.createWidget('PartyListRow', ui.membersList)
                row:setId(rowId)
                row.name:setText(member.name)
                row.name:setColor('#FFFFFF')
                row.statusIcon:setBackgroundColor('#00ff00')
                row.leaderIcon:setVisible(member.isLeader)
                if isLeader and member.id ~= localId then
                    row.actionButton:setVisible(true)
                    row.actionButton:setText(tr('Expulsar'))
                    row.actionButton.onClick = function()
                        g_game.partyKick(member.id)
                    end
                else
                    row.actionButton:setVisible(false)
                end
            end
            for i, invite in ipairs(sortedInvites) do
                local rowId = 'invite_' .. invite.id
                local row = g_ui.createWidget('PartyListRow', ui.membersList)
                row:setId(rowId)
                row.name:setText(invite.name)
                row.name:setColor('#AAAAAA')
                row.statusIcon:setBackgroundColor('#AAAAAA')
                row.leaderIcon:setVisible(false)
                row.actionButton:setVisible(true)
                row.actionButton:setText(tr('Cancelar'))
                row.actionButton.onClick = function()
                    g_game.partyRevokeInvitation(invite.id)
                    outgoingInvites[invite.id] = nil
                    updatePartyList()
                end
            end
        end
    end

    -- Only destroy party rows (member_/invite_) that are no longer desired.
    for _, child in ipairs(ui.membersList:getChildren()) do
        local id = child:getId()
        local isPartyRow = id and (string.sub(id, 1, 7) == 'member_' or string.sub(id, 1, 7) == 'invite_')
        if isPartyRow and not desired[id] then
            child:destroy()
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

    local hasLevels = (minLevel and maxLevel) and ((minLevel ~= 0) or (maxLevel ~= 0))
    if hasLevels then
        row.name:setText(tr(INVITE_MSG_LEVEL, leaderName or tostring(leaderId), minLevel, maxLevel))
    else
        row.name:setText(tr(INVITE_MSG_SIMPLE, leaderName or tostring(leaderId)))
    end

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
        ui.publicGroupsButton = partyWindow:recursiveGetChildById('publicGroupsButton')
        ui.publicGroupsPanel = partyWindow:recursiveGetChildById('publicGroupsPanel')
        ui.publicGroupsList = ui.publicGroupsPanel and ui.publicGroupsPanel:recursiveGetChildById('publicGroupsList')
        ui.noPublicGroupsLabel = ui.publicGroupsPanel and ui.publicGroupsPanel:recursiveGetChildById('noPublicGroupsLabel')
        ui.refreshPublicGroupsButton = ui.publicGroupsPanel and ui.publicGroupsPanel:recursiveGetChildById('refreshPublicGroupsButton')
        ui.closePublicGroupsButton = ui.publicGroupsPanel and ui.publicGroupsPanel:recursiveGetChildById('closePublicGroupsButton')
        ui.publicGroupButton = partyWindow:recursiveGetChildById('publicGroupButton')
    else
        perror("Failed to load party_window.otui")
    end

    if ui.publicGroupsButton then
        ui.publicGroupsButton.onClick = openPublicGroups
    end
    if ui.refreshPublicGroupsButton then
        ui.refreshPublicGroupsButton.onClick = requestPublicGroups
    end
    if ui.closePublicGroupsButton then
        ui.closePublicGroupsButton.onClick = closePublicGroups
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

    connect(g_game, { onGameStart = onStart, onGameEnd = onEnd, onPartyDetailedInfo = onPartyDetailedInfo, onPartyMemberUpdate = onPartyMemberUpdate, onPartyInvite = onPartyInvite, onPartyManageInvite = onPartyManageInvite, onPublicGroupsList = onPublicGroupsList, onPublicGroupLeaderInfo = onPublicGroupLeaderInfo, onPublicGroupLeaderReset = onPublicGroupLeaderReset })
    connect(LocalPlayer, { onHealthChange = onHealthChange, onManaChange = onManaChange, onLevelChange = onLevelChange, onSpecialResourceChange = onSpecialResourceChange, onShieldChange = onShieldChange })
    -- removed dead code: updateUltimateBar registration

    if g_game.isOnline() then
        onStart()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = onStart, onGameEnd = onEnd, onPartyDetailedInfo = onPartyDetailedInfo, onPartyMemberUpdate = onPartyMemberUpdate, onPartyInvite = onPartyInvite, onPartyManageInvite = onPartyManageInvite, onPublicGroupsList = onPublicGroupsList, onPublicGroupLeaderInfo = onPublicGroupLeaderInfo, onPublicGroupLeaderReset = onPublicGroupLeaderReset })
    disconnect(LocalPlayer, { onHealthChange = onHealthChange, onManaChange = onManaChange, onLevelChange = onLevelChange, onSpecialResourceChange = onSpecialResourceChange, onShieldChange = onShieldChange })

    local settings = { pos = window:getPosition() }
    g_settings.setNode("partyWindow", settings)
    window:destroy()
    if partyWindow then
        partyWindow:destroy()
    end
    ui = {} -- Clear cache
    -- removed dead code: updateUltimateBar unregistration
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
        if ui.publicGroupButton then
            ui.publicGroupButton:setVisible(isLeader)
        end
        updatePublicGroupButton()
    else
        if creationPanel then creationPanel:setVisible(true) end
        if managementPanel then managementPanel:setVisible(false) end
    end

    if hasParty then return end

    if publicGroupsOpen then
        if ui.invitesPanel then ui.invitesPanel:setVisible(false) end
        if ui.publicGroupsPanel then ui.publicGroupsPanel:setVisible(true) end
        return
    end

    if not ui.invitesList then return end

    local noInvitesLabel = ui.noInvitesLabel

    for _, child in ipairs(ui.invitesList:getChildren()) do
        child:destroy()
    end

    local sortedInvites = {}
    for leaderId, invite in pairs(incomingInvites) do
        sortedInvites[#sortedInvites + 1] = { id = leaderId, invite = invite }
    end
    table.sort(sortedInvites, function(a, b)
        local an = a.invite.leaderName and a.invite.leaderName or tostring(a.id)
        local bn = b.invite.leaderName and b.invite.leaderName or tostring(b.id)
        return an < bn
    end)
    for i, entry in ipairs(sortedInvites) do
        local leaderId = entry.id
        local invite = entry.invite
        local row = g_ui.createWidget('PartyInviteRow', ui.invitesList)
        row:setId(tostring(leaderId))
        local hasLevels = (invite.minLevel and invite.maxLevel) and (invite.minLevel ~= 0 or invite.maxLevel ~= 0)
        if hasLevels then
            row.name:setText(tr(INVITE_MSG_LEVEL, invite.leaderName or tostring(leaderId), invite.minLevel, invite.maxLevel))
        else
            row.name:setText(tr(INVITE_MSG_SIMPLE, invite.leaderName or tostring(leaderId)))
        end
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

function openPublicGroups()
    if not partyWindow then return end
    publicGroupsOpen = true
    if ui.invitesPanel then ui.invitesPanel:setVisible(false) end
    if ui.publicGroupsPanel then ui.publicGroupsPanel:setVisible(true) end
    requestPublicGroups()
end

function closePublicGroups()
    publicGroupsOpen = false
    if ui.publicGroupsPanel then ui.publicGroupsPanel:setVisible(false) end
    if ui.invitesPanel then ui.invitesPanel:setVisible(true) end
end

function requestPublicGroups()
    if not g_game.isOnline() then return end
    g_game.publicGroupsRequestList()
end

local function updatePublicGroupsUI()
    if not ui.publicGroupsList then return end

    ui.publicGroupsList:destroyChildren()

    if not publicGroups or #publicGroups == 0 then
        if ui.noPublicGroupsLabel then ui.noPublicGroupsLabel:setVisible(true) end
        return
    end

    if ui.noPublicGroupsLabel then ui.noPublicGroupsLabel:setVisible(false) end

    for _, group in ipairs(publicGroups) do
        local row = g_ui.createWidget('PublicGroupRow', ui.publicGroupsList)
        row:setId(tostring(group.leaderId or 0))

        local name = group.leaderName or tostring(group.leaderId or "")
        local slots = ""
        if group.teamSlots and group.teamSlots > 0 then
            slots = " (" .. tostring(group.membersCount or 0) .. "/" .. tostring(group.teamSlots) .. ")"
        else
            slots = " (" .. tostring(group.membersCount or 0) .. ")"
        end

        local rangeText = ""
        if (group.minLevel and group.maxLevel) and (group.minLevel ~= 0 or group.maxLevel ~= 0) then
            rangeText = " Lv " .. tostring(group.minLevel) .. "-" .. tostring(group.maxLevel)
        end

        row.name:setText(name .. slots .. rangeText)

        local status = group.status or 0
        if status == 0 then
            row.actionButton:setText(tr("Solicitar"))
            row.actionButton.onClick = function()
                g_game.publicGroupsRequestJoin(group.leaderId)
            end
        else
            row.actionButton:setText(tr("Cancelar"))
            row.actionButton.onClick = function()
                g_game.publicGroupsCancelRequest(group.leaderId)
            end
        end
    end
end

function onPublicGroupsList(exceeded, groups)
    publicGroups = groups or {}
    updatePublicGroupsUI()
    if exceeded then
        g_logger.warn("Public groups list exceeded rate limit.")
    end
end

updatePublicGroupButton = function()
    if ui.publicGroupButton then
        if publicGroupPublished then
            ui.publicGroupButton:setText(tr("Remover Publico"))
        else
            ui.publicGroupButton:setText(tr("Publicar Grupo"))
        end
    end
end

function togglePublicGroup()
    local player = g_game.getLocalPlayer()
    if not player or not player:isPartyLeader() then return end

    if publicGroupPublished then
        g_game.publicGroupUnpublish()
        publicGroupPublished = false
        updatePublicGroupButton()
        return
    end

    local partySize = #currentMembers
    if partySize < 1 then
        partySize = 1
    end

    local teamSlots = math.max(partySize, 5)
    local freeSlots = math.max(0, teamSlots - partySize)
    local timestamp = os.time()

    g_game.publicGroupPublish(0, 0, 0, teamSlots, freeSlots, true, timestamp, 0, 0, 0, 0, 0)
    publicGroupPublished = true
    updatePublicGroupButton()
end

function onPublicGroupLeaderInfo(info, members)
    publicGroupPublished = true
    updatePublicGroupButton()
end

function onPublicGroupLeaderReset()
    publicGroupPublished = false
    updatePublicGroupButton()
end

function createPrivateParty()
    g_game.partyCreate()
end

function resetPartyState()
    if table and table.clear then
        table.clear(incomingInvites)
        table.clear(outgoingInvites)
        table.clear(currentMembers)
        table.clear(currentMembersById)
        table.clear(publicGroups)
    else
        incomingInvites = {}
        outgoingInvites = {}
        currentMembers = {}
        currentMembersById = {}
        publicGroups = {}
    end
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

    publicGroupsOpen = false
    publicGroups = {}
    publicGroupPublished = false
    if ui.publicGroupsPanel then
        ui.publicGroupsPanel:setVisible(false)
    end
    if ui.publicGroupsList then
        ui.publicGroupsList:destroyChildren()
    end
    if ui.noPublicGroupsLabel then
        ui.noPublicGroupsLabel:setVisible(true)
    end
    updatePublicGroupButton()

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

function updatePartyIcon(hasParty)
    if not window or not window.player or not window.player.menuButton then return end

    if hasParty then
        window.player.menuButton:setIcon("/images/profile/icon_party")
    else
        window.player.menuButton:setIcon("/images/profile/icon_party_create")
    end
end

local function syncPartyState(partyId, leaderId, members)
    if table and table.clear then
        table.clear(currentMembers)
        table.clear(currentMembersById)
    else
        for k in pairs(currentMembers) do
            currentMembers[k] = nil
        end
        for k in pairs(currentMembersById) do
            currentMembersById[k] = nil
        end
    end
    for _, member in ipairs(members) do
        local copy = {
            id = member.id,
            name = member.name,
            level = member.level,
            vocation = member.vocation,
            health = member.health,
            maxHealth = member.maxHealth,
            mana = member.mana,
            maxMana = member.maxMana,
            isLeader = member.isLeader
        }
        currentMembers[#currentMembers + 1] = copy
        currentMembersById[copy.id] = copy
        -- Remove from outgoing invites if accepted
        if outgoingInvites[copy.id] then
            outgoingInvites[copy.id] = nil
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
    for i, member in ipairs(currentMembers) do
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

        local totalHeight = 0
        local currentChildren = window.contentsPanel:getChildren()
        for i, child in ipairs(currentChildren) do
            if child:isVisible() then
                totalHeight = totalHeight + child:getHeight()
            end
        end
        window:setHeight(BASE_HEIGHT + totalHeight)
    end
end

function onPartyDetailedInfo(partyId, leaderId, members)
    if not window then return end

    local player = g_game.getLocalPlayer()
    if not player then return end

    local hasParty = player:isPartyMember()
    updatePartyIcon(hasParty)
    updatePartyWindowView(hasParty)

    if hasParty then
        incomingInvites[leaderId] = nil
        if ui.invitesList then
            local row = ui.invitesList:getChildById(tostring(leaderId))
            if row then
                row:destroy()
            end
            if ui.invitesList:getChildCount() == 0 and ui.noInvitesLabel then
                ui.noInvitesLabel:setVisible(true)
            end
        end
        updatePartyList()
    end

    if hasParty and publicGroupsOpen then
        publicGroupsOpen = false
        if ui.publicGroupsPanel then ui.publicGroupsPanel:setVisible(false) end
        if ui.invitesPanel then ui.invitesPanel:setVisible(true) end
    end

    if not hasParty then
        updatePartyIcon(false)
        updatePartyWindowView(false)
        clearParty()
        if partyWindow then partyWindow:hide() end
        if table and table.clear then
            table.clear(outgoingInvites)
        else
            outgoingInvites = {}
        end
        return
    end

    -- Update Local Player (Initial state)
    updatePlayerWidget(player, player:getHealth(), player:getMaxHealth(), player:getMana(), player:getMaxMana(), player:getLevel())

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
    local srb = window.player.specialResourceBar
    if srb and srb:isVisible() then
        onSpecialResourceChange(player, player:getSpecialResource(), player:getMaxSpecialResource())
    end
end

function updatePartyMemberWidget(member)
    if not window or not window.contentsPanel then return end
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
    local cached = currentMembersById[member.id] or member

    -- Name
    widget.isLeader = cached.isLeader
    local displayName = cached.name .. (cached.isLeader and " (Leader)" or "")
    widget.name:setText(displayName)
    if widget.isLeader then
        widget.name:setColor('#FFD700')
    else
        widget.name:setColor('#FFFFFF')
    end

    -- Vocation Icon + Level no tooltip
    local vocInfo = vocations[cached.vocation] or vocations[0]
    widget.icon:setIconClip(vocInfo[1])
    widget.icon:setTooltip(getVocTooltip(cached.vocation, cached.level))

    -- Shield / Leader Status
    local shieldIndex = cached.isLeader and 1 or 0
    local shieldInfo = shields[shieldIndex] or shields[0]
    widget.shield:setIconClip(shieldInfo)

    -- Health
    widget.hpBar:show()
    updateBar(widget.hpBar, widget.valueHp, cached.health, cached.maxHealth, PARTY_MEMBER_HP_WIDTH, 22)

    -- Mana
    widget.manaBar:show()
    updateBar(widget.manaBar, widget.valueMana, cached.mana, cached.maxMana, PARTY_MEMBER_MANA_WIDTH, 20)

    -- Outfit
    local creature = g_map.getCreatureById(member.id)
    local outfitWidget = widget.outfit
    local noOutfitWidget = widget.nooutfit
    if creature then
        if outfitWidget then
            outfitWidget:setOutfit(creature:getOutfit())
            outfitWidget:show()
        end
        if noOutfitWidget then
            noOutfitWidget:hide()
        end
    else
        if outfitWidget then
            outfitWidget:hide()
        end
        if noOutfitWidget then
            noOutfitWidget:show()
        end
    end
end

function onHoverMember(widget, hovered)
    if hovered then
        window:setBackgroundColor("#ffffff54")
        window:setBorderColor("black")
        if widget.circle then
            widget.circle:setImageColor("#cb5e00")
        end
        local tip = widget:getTooltip()
        if not tip and widget.icon then
            tip = widget.icon:getTooltip()
        end
        if tip then
            g_tooltip.display(tip)
        end
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

        if player:isPartyLeader() and currentMembersById[memberId] then
            local displayName = currentMembersById[memberId] and currentMembersById[memberId].name or widget.name:getText()
            menu:addOption(tr("Pass leader to %s", displayName), function()
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
    local bar = window.player.specialResourceBar
    if not bar then return end
    bar:show()
    local w = bar.getWidth and bar:getWidth() or PLAYER_SPECIAL_WIDTH
    local h = bar.getHeight and bar:getHeight() or 17
    updateBar(bar, window.player.valueSpecialResource, specialResource, maxSpecialResource, w, h)
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
        if not window or not window.contentsPanel then return end
        local widget = window.contentsPanel:getChildById(id)
        if widget and cachedMember then
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

    local panelW = optionsPanel:getWidth()
    if not baseWidth then
        if optionsPanel:isVisible() then
            baseWidth = window:getWidth() - panelW
        else
            baseWidth = window:getWidth()
        end
    end

    if optionsPanel:isVisible() then
        optionsPanel:setVisible(false)
        window:setWidth(baseWidth)
    else
        optionsPanel:setVisible(true)
        panelW = optionsPanel:getWidth()
        window:setWidth(baseWidth + panelW)
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
        local trimmed = (name and name:match("^%s*(.-)%s*$")) or ""
        if trimmed == "" then return end
        g_game.partyInviteByName(trimmed)
        local creature = g_map.getCreatureByName(trimmed)
        if creature then
            local id = creature:getId()
            if id then
                outgoingInvites[id] = { name = trimmed, id = id }
                updatePartyList()
            end
        end
    end, function() end)
end
