g_spells = {}

-- ========================================================
-- UTILS
-- ========================================================
local function computeTileScreenRect(gameMapPanel, tilePos, tiles, cache)
    if not gameMapPanel or not tilePos then return nil end

    local tileSize = cache.tileSize
    local mapRect = cache.mapRect
    
    -- Recalculate basic metrics if missing
    if not tileSize or not mapRect then
        local dimension = gameMapPanel:getVisibleDimension()
        tileSize = gameMapPanel:getHeight() / dimension.height
        mapRect = gameMapPanel:getRect()
        
        -- Write back to cache
        cache.tileSize = tileSize
        cache.mapRect = mapRect
    end
    
    local cameraPos = cache.cameraPos
    if not cameraPos then
        if gameMapPanel.getCameraPosition then
            cameraPos = gameMapPanel:getCameraPosition()
        end
        if not cameraPos then
            local player = g_game.getLocalPlayer()
            if player then cameraPos = player:getPosition() end
        end
    end
    
    if not cameraPos then return nil end

    local screenCenterX = mapRect.x + (mapRect.width / 2)
    local screenCenterY = mapRect.y + (mapRect.height / 2)
    
    local diffX = tilePos.x - cameraPos.x
    local diffY = tilePos.y - cameraPos.y
    
    local baseX = screenCenterX + (diffX * tileSize) - (tileSize / 2)
    local baseY = screenCenterY + (diffY * tileSize) - (tileSize / 2)
    
    local width = (tiles and tiles.width or 1) * tileSize
    local height = (tiles and tiles.height or 1) * tileSize
    
    -- Center offset
    local finalX = baseX + (tileSize / 2) - (width / 2)
    local finalY = baseY + (tileSize / 2) - (height / 2)
    
    return { x = finalX, y = finalY, width = width, height = height }
end

-- ========================================================
-- INPUT HELPER (Modal Manager)
-- ========================================================
function g_spells.captureInput(callbacks)
    local mouseGrabber = modules.game_interface.getRootPanel():recursiveGetChildById('mouseGrabber')
    if not mouseGrabber then return nil end
    
    local handle = {
        mouseGrabber = mouseGrabber,
        active = true,
        prevKeyPress = mouseGrabber.onKeyPress,
        mouseReleaseConnected = false,
        mouseMoveConnected = false,
        callbacks = callbacks
    }
    
    -- Connect Mouse Release
    if callbacks.onMouseRelease then
        connect(mouseGrabber, { onMouseRelease = callbacks.onMouseRelease })
        handle.mouseReleaseConnected = true
    end
    
    -- Connect Mouse Move
    if callbacks.onMouseMove then
        connect(mouseGrabber, { onMouseMove = callbacks.onMouseMove })
        handle.mouseMoveConnected = true
    end
    
    -- Safe KeyPress Stack (Chain of Responsibility)
    -- This ensures that if we are overwritten, we stay in the chain but become passive if released.
    local prevKeyPress = handle.prevKeyPress
    handle.proxyKeyPress = function(widget, keyCode, keyboardModifiers)
        -- 1. If we are no longer active, pass through immediately (we are a "dead" node in the chain)
        if not handle.active then
            if prevKeyPress then
                return prevKeyPress(widget, keyCode, keyboardModifiers)
            end
            return false
        end
        
        -- 2. Try to handle it
        if callbacks.onKeyPress then
            if callbacks.onKeyPress(widget, keyCode, keyboardModifiers) then
                return true
            end
        end
        
        -- 3. Pass to previous handler
        if prevKeyPress then
            return prevKeyPress(widget, keyCode, keyboardModifiers)
        end
        return false
    end
    
    mouseGrabber.onKeyPress = handle.proxyKeyPress
    
    -- Grab
    mouseGrabber:grabMouse()
    mouseGrabber:grabKeyboard()
    
    return handle
end

function g_spells.releaseInput(handle)
    if not handle or not handle.mouseGrabber then return end
    
    -- Mark as inactive (turns the proxy into a pass-through)
    handle.active = false
    
    local mg = handle.mouseGrabber
    
    if handle.mouseReleaseConnected and handle.callbacks.onMouseRelease then
        disconnect(mg, { onMouseRelease = handle.callbacks.onMouseRelease })
    end
    
    if handle.mouseMoveConnected and handle.callbacks.onMouseMove then
        disconnect(mg, { onMouseMove = handle.callbacks.onMouseMove })
    end
    
    mg:ungrabMouse()
    mg:ungrabKeyboard()
    
    -- Restore KeyPress Optimistically
    -- If we are still the top handler, pop us off.
    -- If we are NOT the top handler, we leave our "pass-through" proxy in the chain.
    if mg.onKeyPress == handle.proxyKeyPress then
        if handle.prevKeyPress then
            mg.onKeyPress = handle.prevKeyPress
        else
            mg.onKeyPress = nil
        end
    end
end

function init()
    _G.g_spells = g_spells
    if ProtocolGame and ProtocolGame.registerExtendedJSONOpcode then
        ProtocolGame.registerExtendedJSONOpcode(50, g_spells.onExtendedOpcode)
    else
        ProtocolGame.registerExtendedOpcode(50, g_spells.onExtendedOpcode)
    end
    
    connect(g_game, { onGameEnd = g_spells.onGameEnd })
end

function g_spells.onGameEnd()
    g_spells.cleanupSelection()
    g_spells.RegisteredEffects = {}
end

function terminate()
    g_spells.cleanupSelection()
    
    -- Clear Session Cache
    g_spells.RegisteredEffects = nil
    
    if ProtocolGame and ProtocolGame.unregisterExtendedJSONOpcode then
        ProtocolGame.unregisterExtendedJSONOpcode(50, g_spells.onExtendedOpcode)
    else
        ProtocolGame.unregisterExtendedOpcode(50, g_spells.onExtendedOpcode)
    end
    
    disconnect(g_game, { onGameEnd = g_spells.onGameEnd })
    
    _G.g_spells = nil
    g_spells = nil
end

-- ========================================================
-- SELECTION CONTROLLER (Singleton)
-- ========================================================
local SelectionController = {
    active = nil
}

function SelectionController:isActive()
    return self.active ~= nil
end

function SelectionController:start(params)
    -- 1. Auto-cancel existing selection
    if self.active then
        self:cancel()
    end

    local state = {
        options = params,
        callback = params.callback,
        onCancel = params.onCancel,
        isValid = false,
        success = false,
        inputHandle = nil,
        previewWidgets = {},
        lastTilePos = nil,
        cache = {
            tileSize = nil,
            mapRect = nil,
            cameraPos = nil
        }
    }

    -- 2. Setup Event Handlers
    state.onMouseMove = function(widget, mousePos, mouseMoved)
        -- THROTTLE: 16ms (approx 60 FPS)
        local now = g_clock.millis()
        if state.lastMoveTime and (now - state.lastMoveTime) < 16 then
            return
        end
        state.lastMoveTime = now

        -- Force update mouse position to be safe
        mousePos = g_window.getMousePosition()
        
        local gameMapPanel = modules.game_interface.getGameMapPanel()
        if not gameMapPanel then return end
        
        -- Optimization: Pre-calculate player position once per frame
        local player = g_game.getLocalPlayer()
        local playerPos = player and player:getPosition() or nil
        
        local centerTile = gameMapPanel:getTile(mousePos)
        
        -- Cache Invalidations
        local cache = state.cache
        local root = modules.game_interface.getRootPanel()
        if root and cache.rootSize then
            if root:getWidth() ~= cache.rootSize.width or root:getHeight() ~= cache.rootSize.height then
                 cache.mapRect = nil
                 cache.tileSize = nil
                 cache.rootSize = {width = root:getWidth(), height = root:getHeight()}
            end
        elseif root then
            cache.rootSize = {width = root:getWidth(), height = root:getHeight()}
        end
        
        -- Cache Camera Position per frame (validation + render)
        cache.cameraPos = nil -- Always refresh camera pos in dynamic movement
        if gameMapPanel.getCameraPosition then
            cache.cameraPos = gameMapPanel:getCameraPosition()
        end
        if not cache.cameraPos and playerPos then
            cache.cameraPos = playerPos
        end

        -- Render Pipeline
        local isValid = false
        if centerTile then
            local centerPos = centerTile:getPosition()
            
            -- Recalculate basic metrics if needed
            local dimension = gameMapPanel:getVisibleDimension()
            local zoom = gameMapPanel:getZoom()
            
            if not cache.tileSize or not cache.mapRect or 
               not cache.lastZoom or cache.lastZoom ~= zoom or 
               not cache.lastDimension or (cache.lastDimension.width ~= dimension.width or cache.lastDimension.height ~= dimension.height) then
                
                cache.tileSize = gameMapPanel:getHeight() / dimension.height
                cache.mapRect = gameMapPanel:getRect()
                cache.lastZoom = zoom
                cache.lastDimension = {width = dimension.width, height = dimension.height}
            end

            -- Update All Widgets
            if state.previewWidgets then
                -- Check if position changed to avoid redundant calculations
                local posChanged = true
                if state.lastTilePos and 
                   state.lastTilePos.x == centerPos.x and 
                   state.lastTilePos.y == centerPos.y and 
                   state.lastTilePos.z == centerPos.z then
                    posChanged = false
                end

                if posChanged then
                    state.lastTilePos = centerPos
                    for _, entry in ipairs(state.previewWidgets) do
                        local w = entry.widget
                        local config = entry.config or {}
                        
                        local rect = computeTileScreenRect(gameMapPanel, centerPos, config.tiles or params.tiles, cache)
                        
                        if rect then
                            w:setSize({width = rect.width, height = rect.height})
                            w:setPosition({x = rect.x, y = rect.y})
                            w:setVisible(true)
                        else
                            w:setVisible(false)
                        end
                    end
                end
            end
            
            -- Validation Logic
            if playerPos then
                local targetPos = centerPos
                if params.validate then
                    isValid = params.validate(targetPos, playerPos)
                else
                    -- Standard validation
                    local dist = math.max(math.abs(playerPos.x - targetPos.x), math.abs(playerPos.y - targetPos.y))
                    local inRange = not params.range or (dist <= params.range)
                    local visible = true
                    if g_map.isSightClear and not g_map.isSightClear(playerPos, targetPos) then
                        visible = false
                    end
                    isValid = inRange and visible
                end
            end
        else
            -- No tile selected
            if state.previewWidgets then
                for _, entry in ipairs(state.previewWidgets) do
                    if entry.widget then entry.widget:setVisible(false) end
                end
            end
            state.lastTilePos = nil
        end
        
        state.isValid = isValid
        
        -- Visual Feedback (Widget Color)
        if state.previewWidgets then
            local color = isValid and '#ffffff' or '#ff4444'
            for _, entry in ipairs(state.previewWidgets) do
                if entry.widget then
                    entry.widget:setImageColor(color)
                end
            end
        end
        
        -- Cursor Feedback
        local cursorW = modules.game_interface.getRootPanel():recursiveGetChildById('targetCursor')
        if cursorW then
            local color = isValid and '#ffffff' or '#ff4444'
            cursorW:setImageColor(color)
        end
    end

    state.onMouseRelease = function(widget, mousePos, mouseButton)
        local gameMapPanel = modules.game_interface.getGameMapPanel()
        if not gameMapPanel then return false end

        if mouseButton == MouseLeftButton then
            if state.isValid == false then
                return true -- Block invalid
            end

            local tile = gameMapPanel:getTile(mousePos)
            if tile then
                local pos = tile:getPosition()
                
                -- Mark success
                state.success = true
                
                -- Cleanup before callback to allow callback to start new selection if needed
                local callback = state.callback
                SelectionController:finish() 
                
                if callback then
                    pcall(callback, pos)
                end
            end
            return true
        elseif mouseButton == MouseRightButton then
            SelectionController:cancel()
            return true
        end
        return false
    end

    local onKeyPress = function(widget, keyCode, keyboardModifiers)
        if keyCode == KeyEscape then
            SelectionController:cancel()
            return true
        end
        
        -- Movement Support
        local direction = nil
        if keyCode == KeyUp or keyCode == KeyW then direction = North
        elseif keyCode == KeyRight or keyCode == KeyD then direction = East
        elseif keyCode == KeyDown or keyCode == KeyS then direction = South
        elseif keyCode == KeyLeft or keyCode == KeyA then direction = West
        elseif keyCode == KeyUpRight then direction = NorthEast
        elseif keyCode == KeyDownRight then direction = SouthEast
        elseif keyCode == KeyDownLeft then direction = SouthWest
        elseif keyCode == KeyUpLeft then direction = NorthWest
        end
        
        if direction then
            g_game.walk(direction)
            return true
        end
        return false
    end

    -- 3. Setup Preview (Asset-Driven)
    if params.asset then
         local w = g_ui.createWidget('UIWidget', modules.game_interface.getRootPanel())
         w:setPhantom(true)
         w:setOpacity(0.7)
         w:setImageSource(params.asset)
         -- Pipeline Structure: { widget, config }
         table.insert(state.previewWidgets, { widget = w, config = { tiles = params.tiles } })
    end

    -- 4. Auto-Cancel Timeout (30 seconds)
    state.timeoutEvent = scheduleEvent(function()
        if self.active == state then
             self:cancel()
        end
    end, 30000)

    -- 5. Capture Input
    state.inputHandle = g_spells.captureInput({
        onMouseRelease = state.onMouseRelease,
        onMouseMove = state.onMouseMove,
        onKeyPress = onKeyPress
    })
    
    g_mouse.pushCursor("target")
    
    self.active = state
    
    -- Trigger initial move to set cursor color
    state.onMouseMove(nil, g_window.getMousePosition(), nil)
end

function SelectionController:cancel()
    if not self.active then return end
    
    local s = self.active
    
    -- Notify Cancel (only if not successful)
    if not s.success then
        if s.onCancel then
            pcall(s.onCancel)
        end
    end
    
    self:finish()
end

function SelectionController:finish()
    if not self.active then return end
    
    local s = self.active
    self.active = nil
    
    -- Cleanup Timeout
    if s.timeoutEvent then
        removeEvent(s.timeoutEvent)
        s.timeoutEvent = nil
    end

    -- Cleanup Widgets
    if s.previewWidgets then
        for _, entry in ipairs(s.previewWidgets) do
            local widget = entry.widget
            if widget and not widget:isDestroyed() then
                widget:destroy()
            end
        end
    end

    -- Restore Input
    if s.inputHandle then
        g_spells.releaseInput(s.inputHandle)
    end
    g_mouse.popCursor("target")
end

-- ========================================================
-- PUBLIC API
-- ========================================================

function g_spells.requestPosition(options)
    if type(options) ~= "table" then return end

    -- Handle Instant Mode
    if options.instant then
        local gameMapPanel = modules.game_interface.getGameMapPanel()
        if not gameMapPanel then return end
        local mousePos = g_window.getMousePosition()
        local tile = gameMapPanel:getTile(mousePos)
        if tile and options.callback then
            pcall(options.callback, tile:getPosition())
        end
        return
    end

    SelectionController:start(options)
end

function g_spells.cancelSelection()
    SelectionController:cancel()
end

function g_spells.cleanupSelection()
    SelectionController:finish()
end

function g_spells.sendCast(spellName, pos)
    local response = {
        action = "cast",
        version = 2,
        spellName = spellName,
        position = {x = pos.x, y = pos.y, z = pos.z}
    }
    local protocol = g_game.getProtocolGame()
    if protocol then
        -- Force standard sendExtendedOpcode (String) to ensure compatibility
        -- Some server implementations struggle with auto-JSON opcodes
        protocol:sendExtendedOpcode(50, json.encode(response))
    end
end

-- ========================================================
-- OPCODE HANDLER
-- ========================================================
function g_spells.onExtendedOpcode(protocol, opcode, buffer)
    if opcode ~= 50 then return end

    local data = buffer
    if type(buffer) == 'string' then
        local status, result = pcall(json.decode, buffer)
        if not status or not result then
            return
        end
        data = result
    end
    
    if data.action == "request_position" then
        local options = {
            spellName = data.spellName,
            asset = data.asset,
            tiles = data.tiles,
            range = data.range,
            callback = function(pos)
                g_spells.sendCast(data.spellName, pos)
            end
        }
        g_spells.requestPosition(options)
    elseif data.action == "register_effect" then
        if AttachedEffectManager then
            local id = data.id
            
            -- Client-side Cache to prevent re-registration lag
            if not g_spells.RegisteredEffects then g_spells.RegisteredEffects = {} end
            
            if not g_spells.RegisteredEffects[id] then
                local config = data.config
                local category = ThingCategoryEffect
                
                if config.type == "outfit" then
                    category = ThingCategoryCreature
                elseif config.type == "item" then
                    category = ThingCategoryItem
                end
                
                -- Ensure valid category constant (fallback)
                if not category then
                    if config.type == "outfit" then category = 1 end
                    if config.type == "item" then category = 2 end
                    if config.type == "effect" then category = 3 end
                end
                
                AttachedEffectManager.register(id, data.name or "DynamicEffect", config.thingId, category, config)
                g_spells.RegisteredEffects[id] = true
            end
        end
    end
end

-- ========================================================
-- SPELL CONTROLLER (SIMPLIFIED)
-- ========================================================
SpellController = {}

function SpellController.cast(spellName)
    -- Just send the words to the server. 
    -- If the spell requires a target, the server will send an Opcode back.
    g_game.talk(spellName)
end
