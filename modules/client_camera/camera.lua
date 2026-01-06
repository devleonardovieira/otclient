local OPCODE_SPECTATE = 100

Camera = {}

local gameMapPanel = nil
local spectateLoopEvent = nil
local currentTargetId = nil
local lastKnownPos = nil
local isSpectating = false

-- Forward declaration
local onExtendedJSONOpcode
local onGameStart
local onGameEnd
local spectateLoop

function init()
    connect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    if ProtocolGame and ProtocolGame.registerExtendedJSONOpcode then
        ProtocolGame.registerExtendedJSONOpcode(OPCODE_SPECTATE, onExtendedJSONOpcode)
    else
        print("[Camera] Error: ProtocolGame.registerExtendedJSONOpcode not found.")
    end

    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    disconnect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    if ProtocolGame and ProtocolGame.unregisterExtendedJSONOpcode then
        ProtocolGame.unregisterExtendedJSONOpcode(OPCODE_SPECTATE, onExtendedJSONOpcode)
    end

    Camera.stop()
end

function onGameStart()
    gameMapPanel = modules.game_interface.getMapPanel()
end

function onGameEnd()
    Camera.stop()
    gameMapPanel = nil
end

function onExtendedJSONOpcode(protocol, opcode, json_data)
    if opcode ~= OPCODE_SPECTATE then return end

    local action = json_data.action
    
    if action == "start" then
        Camera.start(json_data.targetId, json_data.pos)
    
    elseif action == "sync" then
        -- Real-time synchronization of position
        if isSpectating and json_data.pos then
            lastKnownPos = {x = json_data.pos.x, y = json_data.pos.y, z = json_data.pos.z}
            -- If we are in fallback mode (not locked on creature), update camera immediately
            if gameMapPanel then
                local currentFollow = gameMapPanel:getCreatureToFollow()
                -- If we are not following anyone, OR we are following the local player (who is hidden), 
                -- we might need to update view if we are using setCameraPosition.
                -- But if we are following LocalPlayer and using 0x65, we don't need this.
                -- However, if 0x65 fails to move LocalPlayer, we need this.
                if not currentFollow or currentFollow == g_game.getLocalPlayer() then
                     -- Only force update if we suspect desync or if not following.
                     -- For now, let's rely on loop, but update lastKnownPos is key.
                end
            end
        end
        
    elseif action == "stop" then
        Camera.stop()
    end
end

function Camera.start(targetId, pos)
    if not gameMapPanel then 
        gameMapPanel = modules.game_interface.getMapPanel()
    end

    if not gameMapPanel then 
        print("[Camera] Error: gameMapPanel is nil")
        return 
    end

    print("[Camera] Starting spectate on target: " .. tostring(targetId))

    isSpectating = true
    currentTargetId = targetId
    
    if pos then
        lastKnownPos = {x = pos.x, y = pos.y, z = pos.z}
    end

    -- Hide Local Player (Fix for Self Ghost)
    local localPlayer = g_game.getLocalPlayer()
    if localPlayer then
        if not Camera.savedOutfit then
            Camera.savedOutfit = localPlayer:getOutfit()
        end
        -- Set invisible outfit (Type 0 is usually empty/invisible)
        localPlayer:setOutfit({type = 0, item = 0, auxiliary = 0})
        -- Ensure we follow the local player (so camera moves with 0x65 packets)
        gameMapPanel:followCreature(localPlayer)
    end

    -- Jump to initial position
    if lastKnownPos then
        gameMapPanel:setCameraPosition(lastKnownPos)
    end

    -- Start Sync Loop
    if spectateLoopEvent then
        removeEvent(spectateLoopEvent)
    end
    spectateLoop()
end

function spectateLoop()
    if not isSpectating or not currentTargetId then return end
    
    if not gameMapPanel then
        gameMapPanel = modules.game_interface.getMapPanel()
    end

    if gameMapPanel then
        local target = g_map.getCreatureById(currentTargetId)
        local currentFollow = gameMapPanel:getCreatureToFollow()
        local localPlayer = g_game.getLocalPlayer()

        -- Priority 1: Follow Target if visible
        if target then
             if currentFollow ~= target then
                 gameMapPanel:followCreature(target)
                 print("[Camera] Sync: Locked onto target.")
             end
             lastKnownPos = target:getPosition()
        
        -- Priority 2: Follow Local Player (if invisible and moving correctly)
        -- We assume Local Player is being moved by 0x65 packets.
        elseif localPlayer then
             -- Check if Local Player is near the sync pos?
             local playerPos = localPlayer:getPosition()
             -- If Local Player is far from lastKnownPos, maybe 0x65 didn't work.
             -- In that case, use setCameraPosition.
             
             -- For now, let's default to setCameraPosition if Target is missing.
             -- Because we can't be sure 0x65 moved the player.
             if currentFollow then
                 gameMapPanel:followCreature(nil)
             end
             
             if lastKnownPos then
                 gameMapPanel:setCameraPosition(lastKnownPos)
             end
        end
    end

    -- Maintain loop
    spectateLoopEvent = scheduleEvent(spectateLoop, 100)
end

function Camera.stop()
    isSpectating = false
    currentTargetId = nil
    lastKnownPos = nil

    if spectateLoopEvent then
        removeEvent(spectateLoopEvent)
        spectateLoopEvent = nil
    end

    if not gameMapPanel then 
        gameMapPanel = modules.game_interface.getMapPanel()
    end
    
    local localPlayer = g_game.getLocalPlayer()
    if localPlayer and Camera.savedOutfit then
        localPlayer:setOutfit(Camera.savedOutfit)
        Camera.savedOutfit = nil
    end

    if gameMapPanel and localPlayer then
        -- Restore camera to Local Player
        gameMapPanel:followCreature(localPlayer)
        print("[Camera] Stopped. Locked to player.")
    end
end
