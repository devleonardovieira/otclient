Camera = {}

local moveEvent = nil
local gameMapPanel = nil
local lastValidCamPos = nil -- Armazena a última posição válida conhecida da câmera

-- Configuration
local SMOOTH_SPEED = 1.0 -- Instant snap (was 0.1)
local SNAP_DISTANCE = 30.0 -- Always snap if visible (was 0.5)

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
    lastValidCamPos = nil
end

-- Public Functions

function Camera.stop()
    if moveEvent then
        removeEvent(moveEvent)
        moveEvent = nil
    end
    
    -- [NOVO] Avisa o servidor para parar de espectar (retorna o char para posição original)
    local protocolGame = g_game.getProtocolGame()
    if protocolGame then
        protocolGame:sendExtendedOpcode(100, json.encode({action = "stop"}))
    end
end

function Camera.follow(target)
    if not gameMapPanel then return end
    
    local targetName = nil
    local creature = target
    
    -- Lógica para buscar pelo nome
    if type(target) == 'string' then
        targetName = target
        creature = nil
        local spectators = gameMapPanel:getSpectators()
        for _, spec in ipairs(spectators) do
            if spec:getName():lower() == target:lower() then
                creature = spec
                break
            end
        end
    elseif target then
        targetName = target:getName()
    end

    -- [NOVO] Envia solicitação ao servidor
    -- O servidor vai registrar o espectador e enviar os dados do mapa (remote view).
    if targetName then
        local protocolGame = g_game.getProtocolGame()
        if protocolGame then
            -- Verifica se é o próprio jogador para enviar "stop" em vez de "start"
            local localPlayer = g_game.getLocalPlayer()
            if localPlayer and targetName:lower() == localPlayer:getName():lower() then
                 protocolGame:sendExtendedOpcode(100, json.encode({action = "stop"}))
            else
                 protocolGame:sendExtendedOpcode(100, json.encode({action = "start", target = targetName}))
            end
        end
    end
    
    -- Se a criatura não está na tela ainda (longe), esperamos o servidor teleportar
    if not creature then
        if type(target) == 'string' then
            -- Tenta focar novamente em 500ms (tempo para o teleporte ocorrer)
            scheduleEvent(function() 
                local specs = gameMapPanel:getSpectators()
                for _, spec in ipairs(specs) do
                    if spec:getName():lower() == target:lower() then
                        Camera.follow(spec) -- Chama recursivamente agora com o objeto criatura
                        break
                    end
                end
            end, 500)
        end
        return 
    end

    -- Inicia a transição suave da câmera (Código original mantido para suavidade)
    if moveEvent then
        removeEvent(moveEvent)
        moveEvent = nil
    end
    gameMapPanel:followCreature(nil) -- Solta a câmera do player local

    local function updateFollow()
        local camPos = gameMapPanel:getCameraPosition()
        local destPos = creature:getPosition()

        if not destPos then
            -- Se perdeu o alvo, tenta recuperar ou para
            if lastValidCamPos then
                gameMapPanel:setCameraPosition(lastValidCamPos)
            else
                Camera.stop()
            end
            moveEvent = scheduleEvent(updateFollow, 100) 
            return
        end
        
        lastValidCamPos = {x=camPos.x, y=camPos.y, z=camPos.z}

        -- Safety check
        if not camPos then
             camPos = lastValidCamPos
             if not camPos then Camera.stop() return end
        end

        -- Atualiza Z instantaneamente
        if camPos.z ~= destPos.z then
             camPos.z = destPos.z
             gameMapPanel:setCameraPosition(camPos)
             lastValidCamPos = camPos
        end

        -- Interpolação (Suavização)
        local dx = destPos.x - camPos.x
        local dy = destPos.y - camPos.y
        local dist = math.sqrt(dx*dx + dy*dy)

        if dist <= SNAP_DISTANCE then
            gameMapPanel:followCreature(creature)
            moveEvent = nil
            return
        end

        local nextX = camPos.x + dx * SMOOTH_SPEED
        local nextY = camPos.y + dy * SMOOTH_SPEED

        gameMapPanel:setCameraPosition({x = nextX, y = nextY, z = camPos.z})
        moveEvent = scheduleEvent(updateFollow, 10)
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
