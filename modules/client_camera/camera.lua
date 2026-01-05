Camera = {}

local moveEvent = nil
local gameMapPanel = nil

-- Configuration
local SMOOTH_SPEED = 0.1 -- Factor for interpolation (0.0 to 1.0). Higher = faster.
local SNAP_DISTANCE = 0.5 -- Distance in tiles to snap to target

function init()
    connect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    disconnect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })
    Camera.stop()
end

function onGameStart()
    gameMapPanel = modules.game_interface.getMapPanel()
end

function onGameEnd()
    Camera.stop()
    gameMapPanel = nil
end

-- Public Functions

function Camera.stop()
    if moveEvent then
        removeEvent(moveEvent)
        moveEvent = nil
    end
end

function Camera.follow(target)
    if not gameMapPanel then return end
    
    local creature = target
    
    -- Handle string input (name)
    if type(target) == 'string' then
        creature = nil
        local spectators = gameMapPanel:getSpectators()
        for _, spec in ipairs(spectators) do
            if spec:getName():lower() == target:lower() then
                creature = spec
                break
            end
        end
        
        if not creature then
            print("[Camera] Creature not found: " .. target)
            return
        end
    end

    if not creature then return end

    -- Start Smooth Transition
    Camera.stop()
    gameMapPanel:followCreature(nil) -- Unlock camera

    local function updateFollow()
        local camPos = gameMapPanel:getCameraPosition()
        local destPos = creature:getPosition()

        -- Safety check: If creature disappears (out of range/logged out), stop to avoid crash
        if not camPos or not destPos then
            Camera.stop()
            return
        end

        -- Handle Z change: If floor is different, update Z instantly and continue smoothing X/Y
        if camPos.z ~= destPos.z then
             camPos.z = destPos.z
             gameMapPanel:setCameraPosition(camPos)
        end

        -- Interpolate (Ease-Out)
        local dx = destPos.x - camPos.x
        local dy = destPos.y - camPos.y
        local dist = math.sqrt(dx*dx + dy*dy)

        if dist <= SNAP_DISTANCE then
            -- Arrived
            gameMapPanel:followCreature(creature)
            moveEvent = nil
            return
        end

        local nextX = camPos.x + dx * SMOOTH_SPEED
        local nextY = camPos.y + dy * SMOOTH_SPEED

        gameMapPanel:setCameraPosition({x = nextX, y = nextY, z = camPos.z})
        moveEvent = scheduleEvent(updateFollow, 10) -- ~60-100 FPS
    end

    moveEvent = scheduleEvent(updateFollow, 10)
    print("[Camera] Transitioning to " .. creature:getName())
end

function Camera.reset()
    if not gameMapPanel then return end
    local player = g_game.getLocalPlayer()
    if player then
        Camera.follow(player)
        print("[Camera] Resetting to local player")
    end
end

function Camera.moveTo(destPos, speed)
    if not gameMapPanel then return end
    
    Camera.stop()
    gameMapPanel:followCreature(nil)
    
    local currentPos = gameMapPanel:getCameraPosition()
    if not currentPos then return end -- Safety check

    -- Handle Z change instantly for moveTo as well
    if currentPos.z ~= destPos.z then
        currentPos.z = destPos.z
        gameMapPanel:setCameraPosition(currentPos)
    end
    
    speed = speed or 10 -- tiles per second
    
    local interval = 16 -- ~60 FPS
    local totalDistance = math.sqrt(math.pow(destPos.x - currentPos.x, 2) + math.pow(destPos.y - currentPos.y, 2))
    
    if totalDistance == 0 then 
        gameMapPanel:setCameraPosition(destPos)
        return 
    end

    local duration = (totalDistance / speed) * 1000
    local startTime = g_clock.millis()
    local startX = currentPos.x
    local startY = currentPos.y

    local function updateMove()
        local elapsed = g_clock.millis() - startTime
        local progress = math.min(elapsed / duration, 1.0)
        
        local nextX = startX + (destPos.x - startX) * progress
        local nextY = startY + (destPos.y - startY) * progress
        
        gameMapPanel:setCameraPosition({x = nextX, y = nextY, z = destPos.z})
        
        if progress < 1.0 then
            moveEvent = scheduleEvent(updateMove, interval)
        else
            moveEvent = nil
            print("[Camera] Arrived at destination")
        end
    end
    
    moveEvent = scheduleEvent(updateMove, interval)
end

function Camera.teleportTo(destPos)
    if not gameMapPanel then return end
    Camera.stop()
    gameMapPanel:followCreature(nil)
    gameMapPanel:setCameraPosition(destPos)
end
