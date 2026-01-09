local window = nil
local members = {}

function init()
    connect(g_game, {
        onGameStart = onStart,
        onGameEnd = onEnd,
        onPartyDetailedInfo = onPartyDetailedInfo,
        onPartyMemberUpdate = onPartyMemberUpdate
    })
    
    window = g_ui.loadUI("party_system", g_ui.getRootWidget())
    window:hide()

    -- Setup Tab Buttons
    window.sidebar.tabGroup.onClick = function() selectTab("Group") end
    window.sidebar.tabLoot.onClick = function() selectTab("Loot") end
    window.sidebar.tabDetails.onClick = function() selectTab("Details") end
    window.sidebar.tabRecharges.onClick = function() selectTab("Recharges") end
    window.sidebar.tabNewGroup.onClick = function() selectTab("NewGroup") end

    -- Setup Dropdowns
    setupDropdowns()
    
    -- Setup Action Buttons
    window.content.panelGroup.btnAddMember.onClick = function() 
      startPartyInvite()
    end
    window.content.panelGroup.btnLeaveDisband.onClick = function() 
        local player = g_game.getLocalPlayer()
        if player then
            if player:isPartyLeader() then
                g_game.partyLeave() 
            else
                g_game.partyLeave()
            end
        end
    end
    
    window.content.panelNewGroup.btnCreatePrivate.onClick = function()
         g_logger.info("Create Private Group Clicked")
         selectTab("Group")
    end
    
    window.content.panelNewGroup.btnPublicGroups.onClick = function()
         g_logger.info("Open Public Groups Clicked")
         -- Here we would open the Team Finder window
    end
end

function terminate()
    disconnect(g_game, {
        onGameStart = onStart,
        onGameEnd = onEnd,
        onPartyDetailedInfo = onPartyDetailedInfo,
        onPartyMemberUpdate = onPartyMemberUpdate
    })
    if window then window:destroy() end
end

function onStart()
    refresh()
end

function onEnd()
    window:hide()
    clearParty()
end

function toggle()
    if window:isVisible() then
        window:hide()
    else
        window:show()
        refresh()
    end
end

function startPartyInvite()
  -- Logic to start invite, e.g., change cursor or open input
  g_logger.info("Invite button clicked - Not implemented yet")
end

function refresh()
    local player = g_game.getLocalPlayer()
    if not player then return end
    
    if player:isPartyMember() or #members > 0 then
        selectTab("Group")
        window.sidebar.tabGroup:setEnabled(true)
        window.sidebar.tabNewGroup:setEnabled(false)
        
        -- Update Disband/Leave button text
        if player:isPartyLeader() then
             window.content.panelGroup.btnLeaveDisband:setText("Dispersar Grupo")
        else
             window.content.panelGroup.btnLeaveDisband:setText("Sair do Grupo")
        end
    else
        selectTab("NewGroup")
        window.sidebar.tabGroup:setEnabled(false)
        window.sidebar.tabNewGroup:setEnabled(true)
    end
end

function selectTab(tabName)
    if not window then return end
    
    -- Reset all tabs
    window.sidebar.tabGroup:setChecked(false)
    window.sidebar.tabLoot:setChecked(false)
    window.sidebar.tabDetails:setChecked(false)
    window.sidebar.tabRecharges:setChecked(false)
    window.sidebar.tabNewGroup:setChecked(false)
    
    window.content.panelGroup:setVisible(false)
    window.content.panelLoot:setVisible(false)
    window.content.panelDetails:setVisible(false)
    window.content.panelRecharges:setVisible(false)
    window.content.panelNewGroup:setVisible(false)
    
    if tabName == "Group" then
        window.sidebar.tabGroup:setChecked(true)
        window.content.panelGroup:setVisible(true)
    elseif tabName == "NewGroup" then
        window.sidebar.tabNewGroup:setChecked(true)
        window.content.panelNewGroup:setVisible(true)
    elseif tabName == "Loot" then
        window.sidebar.tabLoot:setChecked(true)
        window.content.panelLoot:setVisible(true)
        setupLootPanel()
    elseif tabName == "Details" then
        window.sidebar.tabDetails:setChecked(true)
        window.content.panelDetails:setVisible(true)
        setupDetailsPanel()
    elseif tabName == "Recharges" then
        window.sidebar.tabRecharges:setChecked(true)
        window.content.panelRecharges:setVisible(true)
        setupRechargesPanel()
    end
end

function setupLootPanel()
  local list = window.content.panelLoot.lootList
  list:destroyChildren()

  local loots = {
    { item = "Fire Stone", who = "Ash", time = "10:02" },
    { item = "Water Stone", who = "Misty", time = "10:05" },
    { item = "Leaf Stone", who = "Brock", time = "10:10" },
    { item = "Rare Candy", who = "Ash", time = "10:15" },
    { item = "Full Restore", who = "Gary", time = "10:20" }
  }

  for _, loot in ipairs(loots) do
    local label = g_ui.createWidget("Label", list)
    label:setText(loot.time .. " - " .. loot.who .. " looted " .. loot.item)
    label:setHeight(20)
    label:setMarginLeft(5)
  end
end

function setupDetailsPanel()
  local list = window.content.panelDetails.detailsList
  list:destroyChildren()

  local details = {
    { name = "Ash", level = 50, vocation = "Trainer" },
    { name = "Misty", level = 48, vocation = "Water Master" },
    { name = "Brock", level = 52, vocation = "Breeder" },
    { name = "Gary", level = 55, vocation = "Rival" }
  }

  for _, member in ipairs(details) do
    local widget = g_ui.createWidget("PartyDetailItem", list)
    
    local name = g_ui.createWidget("Label", widget)
    name:setText(member.name)
    name:setWidth(100)
    
    local level = g_ui.createWidget("Label", widget)
    level:setText(tostring(member.level))
    level:setWidth(50)

    local voc = g_ui.createWidget("Label", widget)
    voc:setText(member.vocation)
    voc:setWidth(100)
  end
end

function setupRechargesPanel()
  local list = window.content.panelRecharges.rechargesList
  list:destroyChildren()

  local supplies = {
    { name = "Ash", potions = 10, revives = 5 },
    { name = "Misty", potions = 25, revives = 2 },
    { name = "Brock", potions = 5, revives = 10 }
  }

  for _, sup in ipairs(supplies) do
    local widget = g_ui.createWidget("PartyRechargeItem", list)

    local name = g_ui.createWidget("Label", widget)
    name:setText(sup.name .. ":")
    name:setWidth(80)

    local potions = g_ui.createWidget("Label", widget)
    potions:setText("Pots: " .. sup.potions)
    potions:setWidth(80)
    potions:setColor("#ff5555")

    local revives = g_ui.createWidget("Label", widget)
    revives:setText("Rev: " .. sup.revives)
    revives:setWidth(80)
    revives:setColor("#55ff55")
  end
end

function setupDropdowns()
    local lootCombo = window.content.panelGroup.settingsArea.comboLoot
    lootCombo:addOption("Compartilhado", { type = "loot", value = 1 })
    lootCombo:addOption("Individual", { type = "loot", value = 2 })
    lootCombo:addOption("Aleatório", { type = "loot", value = 3 })
    lootCombo:setOption("Compartilhado")
    lootCombo:setTooltip("Compartilhado: Qualquer membro pode abrir loot e jogar ball.\nIndividual: Apenas maior dano.\nAleatório: Sistema decide.")
    
    local expCombo = window.content.panelGroup.settingsArea.comboExp
    expCombo:addOption("Compartilhado", { type = "exp", value = 1 })
    expCombo:addOption("Individual", { type = "exp", value = 2 })
    expCombo:setOption("Compartilhado")
    expCombo:setTooltip("Compartilhado: Exp dividida com membros próximos.\nIndividual: Exp apenas para quem matou.")
    
    local taskCombo = window.content.panelGroup.settingsArea.comboTask
    taskCombo:addOption("Individual", { type = "task", value = 1 })
    taskCombo:addOption("Aleatório", { type = "task", value = 2 })
    taskCombo:addOption("Sequência", { type = "task", value = 3 })
    taskCombo:addOption("Equilibrado", { type = "task", value = 4 })
    taskCombo:setCurrentIndex(1)
    taskCombo:setTooltip("Opções de distribuição de contagem de tarefas.")
end

function onPartyDetailedInfo(partyId, leaderId, memberList)
    members = memberList
    local player = g_game.getLocalPlayer()
    
    window.content.panelGroup.membersArea:destroyChildren()
    
    for i, member in ipairs(members) do
        addPartyMemberWidget(member)
    end
    
    refresh()
    window:show()
end

function onPartyMemberUpdate(member)
    local widget = window.content.panelGroup.membersArea:getChildById(tostring(member.id))
    if widget then
        if member.health and member.maxHealth then
            local percent = math.floor(member.health / member.maxHealth * 100)
            widget.hpBar:setPercent(percent)
        end
    end
end

function addPartyMemberWidget(member)
    local widget = g_ui.createWidget("PartyMemberAvatar", window.content.panelGroup.membersArea)
    widget:setId(tostring(member.id))
    widget.name:setText(member.name)
    
    local creature = g_map.getCreatureById(member.id)
    if creature then
        widget.outfit:setOutfit(creature:getOutfit())
    else
        widget.outfit:setOutfit({type = 128, head = 0, body = 0, legs = 0, feet = 0})
    end
    
    if member.isLeader then
        widget.leader:setVisible(true)
    else
        widget.leader:setVisible(false)
    end
    
    if member.health and member.maxHealth and member.maxHealth > 0 then
        local percent = math.floor(member.health / member.maxHealth * 100)
        widget.hpBar:setPercent(percent)
    end
    
    widget.status:setImageColor("#00ff00")
end

function clearParty()
    members = {}
    if window then
        window.content.panelGroup.membersArea:destroyChildren()
    end
end
