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

-- Opcode Dispatch Table
local OpcodeHandlers = {}

-- StreamReader Class to mimic NetworkMessage reading from string buffer
local StreamReader = {}
StreamReader.__index = StreamReader

function StreamReader.new(buffer)
    return setmetatable({buffer = buffer, pos = 1}, StreamReader)
end

function StreamReader:getU8()
    if self.pos > #self.buffer then return 0 end
    local b = string.byte(self.buffer, self.pos)
    self.pos = self.pos + 1
    return b
end

function StreamReader:getU16()
    if self.pos + 1 > #self.buffer then return 0 end
    local b1 = string.byte(self.buffer, self.pos)
    local b2 = string.byte(self.buffer, self.pos + 1)
    self.pos = self.pos + 2
    return b1 + b2 * 256
end

function StreamReader:getU32()
    if self.pos + 3 > #self.buffer then return 0 end
    local b1 = string.byte(self.buffer, self.pos)
    local b2 = string.byte(self.buffer, self.pos + 1)
    local b3 = string.byte(self.buffer, self.pos + 2)
    local b4 = string.byte(self.buffer, self.pos + 3)
    self.pos = self.pos + 4
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

function StreamReader:getString()
    local len = self:getU16()
    if len == 0 then return "" end
    if self.pos + len - 1 > #self.buffer then return "" end
    local str = string.sub(self.buffer, self.pos, self.pos + len - 1)
    self.pos = self.pos + len
    return str
end

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

    connect(g_game, { onGameStart = onStart, onGameEnd = onEnd })
    connect(LocalPlayer, { onHealthChange = onHealthChange, onManaChange = onManaChange, onSpecialResourceChange = onSpecialResourceChange })
    ProtocolGame.registerExtendedOpcode(139, creatureUpdate)
    ProtocolGame.registerExtendedOpcode(210, updateUltimateBar)

    if g_game.isOnline() then
        onStart()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = onStart, onGameEnd = onEnd })
    disconnect(LocalPlayer, { onHealthChange = onHealthChange, onManaChange = onManaChange, onSpecialResourceChange = onSpecialResourceChange })

    local settings = { pos = window:getPosition() }
    g_settings.setNode("partyWindow", settings)
    window:destroy()
    ProtocolGame.unregisterExtendedOpcode(139, creatureUpdate)
    ProtocolGame.unregisterExtendedOpcode(210, updateUltimateBar)
end

function onEnd()
    clearParty()
    window:hide()
end

function onStart()
    scheduleEvent(function()
        if g_game.isOnline() then
            window:show()
            g_effects.fadeIn(window, 250)

            local player = g_game.getLocalPlayer()
            if player then
                local vocId = player:getVocation()
                local vocInfo = vocations[vocId] or vocations[0]

                window.player.icon:setIconClip(vocInfo[1])
                window.player.icon:setTooltip(vocInfo[2])
                onHealthChange(player, player:getHealth(), player:getMaxHealth())
                onManaChange(player, player:getMana(), player:getMaxMana())
                onSpecialResourceChange(player, player:getSpecialResource(), player:getMaxSpecialResource())
                window.player.outfit:setOutfit(player:getOutfit())

                if player:getShield() > 0 then
                    local protocolGame = g_game.getProtocolGame()
                    if protocolGame then
                        protocolGame:sendExtendedOpcode(112, json.encode({action = "PARTY"}))
                        protocolGame:sendExtendedOpcode(222, json.encode({action = "UPDATE"}))
                    end
                end
            end
        end
    end, 1000)
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

-- Packet Handlers
OpcodeHandlers[1] = function(msg) -- Health Update
    local cid = msg:getU32()
    local hp = msg:getU8()
    changeHealth(cid, hp)
end

OpcodeHandlers[2] = function(msg) -- Mana Update
    local cid = msg:getU32()
    local mana = msg:getU8()
    changeMana(cid, mana)
end

OpcodeHandlers[3] = function(msg) -- Update Status
    local cid = msg:getU32()
    local status = msg:getU8()
    updatemember(cid, status)
end

OpcodeHandlers[4] = function(msg) -- Add Member
print('printou addssddddddddd member')
    local cid = msg:getU32()
    local voc = msg:getU8()
    local shield = msg:getU8()
    local name = msg:getString()
    
    local outfit = {}
    outfit.lookHead = msg:getU8()
    outfit.lookBody = msg:getU8()
    outfit.lookLegs = msg:getU8()
    outfit.lookFeet = msg:getU8()
    outfit.lookAddons = msg:getU8()
    outfit.lookType = msg:getU16()
    outfit.lookWings = msg:getU16()
    outfit.lookAura = msg:getU16()
    
    addmember(cid, name, outfit, voc, shield)
end

OpcodeHandlers[5] = function(msg) -- Remove Member
    local cid = msg:getU32()
    removemember(cid)
end

OpcodeHandlers[6] = function(msg) -- Clear Party
    clearParty()
end

OpcodeHandlers[7] = function(msg) -- Update Shield
    local cid = msg:getU32()
    local shield = msg:getU8()
    updateShield(cid, shield)
end

function creatureUpdate(protocol, opcode, buffer)
    local msg = StreamReader.new(buffer)
    local func = msg:getU8()
    local handler = OpcodeHandlers[func]
    
    if handler then
        handler(msg)
    else
        print("[Party] Opcode 139 received unknown func:", func)
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
        
        local shield = player:getShield()
        
        if shield == 4 or shield == 6 or shield == 10 then
            if player:isPartySharedExperienceActive() then
                menu:addOption(tr("Disable shared experience"), function() g_game.partyShareExperience(false) end)
            else
                menu:addOption(tr("Enable shared experience"), function() g_game.partyShareExperience(true) end)
            end

            menu:addOption(tr("Pass leader to %s", widget.name:getText()), function()
                g_game.partyPassLeadership(tonumber(widget:getId()))
            end)
            
            menu:addOption(tr("Kick %s", widget.name:getText()), function()
                local protocolGame = g_game.getProtocolGame()
                if protocolGame then
                    local msg = OutputMessage.create()
                    msg:addU8(174) -- Kick Opcode
                    msg:addU32(tonumber(widget:getId()))
                    protocolGame:send(msg)
                end
            end)
            menu:addSeparator()
        end

        menu:addOption(tr("Leave party"), function() g_game.partyLeave() end)
        menu:display(mousePos)
    end
end

function addmember(id, name, outfit, voc, shield)
	   print('addmember : ', id, name, outfit, voc, shield)
    id = tostring(id)
    local member = g_ui.createWidget("PartyMember", window.contentsPanel)
    member:setId(id)
    member.name:setText(name)
    member.onHoverChange = onHovermember

    window:show()
    window:setHeight(window:getHeight() + 83)
    
    local vocInfo = vocations[voc] or vocations[0]
    member.icon:setIconClip(vocInfo[1])
    member.icon:setTooltip(vocInfo[2])
    
    local shieldInfo = shields[shield] or shields[0]
    member.shield:setIconClip(shieldInfo)

    member.onMouseRelease = onMouseRelease
    member.onTouchRelease = onMouseRelease
    member.outfit:setOutfit(outfit)
end

function updateShield(id, shield)
    id = tostring(id)
    local member = window.contentsPanel:getChildById(id)
    if member then
        local shieldInfo = shields[shield] or shields[0]
        member.shield:setIconClip(shieldInfo)
    end
end

function updatemember(id, status)
    id = tostring(id)
    local member = window.contentsPanel:getChildById(id)
    if member then
        if status == 1 then
            if not member.outfit:isVisible() then
                member.outfit:show()
                member.nooutfit:hide()
                member.hpBar:show()
                member.manaBar:show()
            end
        elseif member.outfit:isVisible() then
            member.outfit:hide()
            member.nooutfit:show()
            member.hpBar:hide()
            member.valueHp:setText("??? / ???")
            member.manaBar:hide()
            member.valueMana:setText("??? / ???")
        end
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

function changeHealth(id, health)
    id = tostring(id)
    local member = window.contentsPanel:getChildById(id)
    if member then
        member.valueHp:setText(health .. "%")
        local clip = math.ceil(health / 100 * 125)
        member.hpBar:show()
        member.hpBar:setWidth(clip)
        
        local clipRect = { height = 22, x = 0, y = 0, width = clip }
        member.hpBar:setImageClip(clipRect)
        member.hpBar:setImageRect(clipRect)
    end
end

function changeMana(id, mana)
    id = tostring(id)
    local member = window.contentsPanel:getChildById(id)
    if member then
        member.valueMana:setText(mana .. "%")
        local clip = math.ceil(mana / 100 * 104)
        member.manaBar:setWidth(clip)
        member.manaBar:show()
        
        local clipRect = { height = 20, x = 0, y = 0, width = clip }
        member.manaBar:setImageClip(clipRect)
        member.manaBar:setImageRect(clipRect)
    end
end