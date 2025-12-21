g_spells = {}

-- ========================================================
-- UTILS
-- ========================================================
local function computeTileScreenRect(gameMapPanel, tilePos, tiles, cache, cameraPos)
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
        
        -- 2. Try to handle it (Protected)
        if callbacks.onKeyPress then
            local status, result = pcall(callbacks.onKeyPress, widget, keyCode, keyboardModifiers)
            if status and result then
                return true
            elseif not status then
                 g_logger.error("[Spells Input] KeyPress Error: " .. tostring(result))
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
    
    -- Persistent Session Cache (Survives Reloads)
    -- This prevents "Already registered" errors from C++ engine on script reload
    if not _G.g_spells_cache then
        _G.g_spells_cache = {}
    end
    g_spells.RegisteredEffects = _G.g_spells_cache

    if ProtocolGame and ProtocolGame.registerExtendedJSONOpcode then
        ProtocolGame.registerExtendedJSONOpcode(50, g_spells.onExtendedOpcode)
    else
        ProtocolGame.registerExtendedOpcode(50, g_spells.onExtendedOpcode)
    end
    
    connect(g_game, { onGameEnd = g_spells.onGameEnd })
    
    -- Start Registry Cleanup Loop
    g_spells.cleanupRegistry()
end

function g_spells.onGameEnd()
    g_spells.cleanupSelection()
    -- Clear Cache on Logout (New Session = New IDs allowed)
    _G.g_spells_cache = {}
    g_spells.RegisteredEffects = _G.g_spells_cache
end

function terminate()
    if g_spells.cleanupEvent then
        removeEvent(g_spells.cleanupEvent)
        g_spells.cleanupEvent = nil
    end

    g_spells.cleanupSelection()
    
    -- Do NOT clear _G.g_spells_cache here (allows Hot-Reload persistence)
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
-- WIDGET POOL
-- ========================================================
local WidgetPool = {
    pool = {}
}

function WidgetPool:get(parent)
    local w = table.remove(self.pool)
    if w then
        if not w:isDestroyed() then
            w:setParent(parent)
            w:setVisible(true)
            return w
        end
    end
    w = g_ui.createWidget('UIWidget', parent)
    w:setPhantom(true)
    w:setOpacity(0.7)
    return w
end

function WidgetPool:recycle(w)
    if w and not w:isDestroyed() then
        w:setVisible(false)
        w:setParent(nil)
        table.insert(self.pool, w)
    end
end

function WidgetPool:clear()
    for _, w in ipairs(self.pool) do
        if not w:isDestroyed() then w:destroy() end
    end
    self.pool = {}
end

-- ========================================================
-- SELECTION LOGIC HELPERS
-- ========================================================
local function validateTarget(state, playerPos, targetPos)
    if not playerPos or not targetPos then return false end
    local params = state.options
    
    if params.validate then
        return params.validate(targetPos, playerPos)
    else
        -- Standard validation
        local dist = math.max(math.abs(playerPos.x - targetPos.x), math.abs(playerPos.y - targetPos.y))
        local inRange = not params.range or (dist <= params.range)
        local visible = true
        if g_map.isSightClear and not g_map.isSightClear(playerPos, targetPos) then
            visible = false
        end
        return inRange and visible
    end
end

local function updateRender(state, gameMapPanel, centerPos, isValid)
    local cache = state.cache
    
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
                
                local rect = computeTileScreenRect(gameMapPanel, centerPos, config.tiles or state.options.tiles, cache, state.cameraPos)
                
                if rect then
                    w:setSize({width = rect.width, height = rect.height})
                    w:setPosition({x = rect.x, y = rect.y})
                    w:setVisible(true)
                else
                    w:setVisible(false)
                end
            end
        end
        
        -- Visual Feedback (Widget Color)
        local color = isValid and '#ffffff' or '#ff4444'
        for _, entry in ipairs(state.previewWidgets) do
            if entry.widget then
                entry.widget:setImageColor(color)
            end
        end
    end
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
        listeners = {}, -- Cursor/State Listeners
        lastTilePos = nil,
        cache = {
            tileSize = nil,
            mapRect = nil
        }
    }
    
    -- Listener Support
    function state:addListener(cb) table.insert(self.listeners, cb) end
    function state:notify(isValid) for _, cb in ipairs(self.listeners) do cb(isValid) end end

    -- 2. Setup Event Handlers
    state.onMouseMove = function(widget, mousePos, mouseMoved)
        -- ADAPTIVE THROTTLE
        -- Adjust throttle based on current FPS (Target ~60 FPS update rate)
        local currentFps = g_app.getFps()
        local frameTime = 1000 / math.max(10, currentFps) -- Min 10 FPS cap
        frameTime = math.max(16, frameTime) -- Max 60 FPS cap
        
        local now = g_clock.millis()
        if state.lastMoveTime and (now - state.lastMoveTime) < frameTime then
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
        
        -- Cache Camera Position per frame (validation + render)
        state.cameraPos = nil 
        if gameMapPanel.getCameraPosition then
            state.cameraPos = gameMapPanel:getCameraPosition()
        end
        if not state.cameraPos and playerPos then
            state.cameraPos = playerPos
        end

        -- Render Pipeline
        local isValid = false
        if centerTile then
            local centerPos = centerTile:getPosition()
            
            -- 1. Validate
            isValid = validateTarget(state, playerPos, centerPos)
            
            -- 2. Notify Listeners (Cursor Feedback decoupled)
            if state.isValid ~= isValid then
                state:notify(isValid)
            end
            state.isValid = isValid
            
            -- 3. Render Preview
            updateRender(state, gameMapPanel, centerPos, isValid)
        else
            -- No tile selected
            if state.previewWidgets then
                for _, entry in ipairs(state.previewWidgets) do
                    if entry.widget then entry.widget:setVisible(false) end
                end
            end
            state.lastTilePos = nil
            state.isValid = false
            state:notify(false)
        end
    end

    state.onMouseRelease = function(widget, mousePos, mouseButton)
        local gameMapPanel = modules.game_interface.getGameMapPanel() -- Local capture
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
         local w = WidgetPool:get(modules.game_interface.getRootPanel())
         w:setImageSource(params.asset)
         -- Pipeline Structure: { widget, config }
         table.insert(state.previewWidgets, { widget = w, config = { tiles = params.tiles } })
    end
    
    -- 4. Setup Cursor Feedback (Decoupled Listener)
    state:addListener(function(isValid)
        local cursorW = modules.game_interface.getRootPanel():recursiveGetChildById('targetCursor')
        if cursorW then
            local color = isValid and '#ffffff' or '#ff4444'
            cursorW:setImageColor(color)
        end
    end)

    -- 5. Auto-Cancel Timeout (30 seconds)
    state.timeoutEvent = scheduleEvent(function()
        if self.active == state then
             self:cancel()
        end
    end, 30000)

    -- 6. Capture Input
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
        
        -- Notify Server to clear AIM visual
        local protocol = g_game.getProtocolGame()
        if protocol then
            local payload = { action = "cancel_aim" }
            protocol:sendExtendedOpcode(50, json.encode(payload))
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

    -- Cleanup Widgets (Recycle)
    if s.previewWidgets then
        for _, entry in ipairs(s.previewWidgets) do
            WidgetPool:recycle(entry.widget)
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
-- REGISTRY HELPER (Checksum & Cleanup)
-- ========================================================
local function generateChecksum(config)
    local function serialize(t)
        local keys = {}
        for k in pairs(t) do table.insert(keys, k) end
        table.sort(keys)
        local parts = {}
        for _, k in ipairs(keys) do
            local v = t[k]
            if type(v) == "table" then
                table.insert(parts, k .. ":" .. serialize(v))
            else
                table.insert(parts, k .. ":" .. tostring(v))
            end
        end
        return table.concat(parts, "|")
    end
    local str = serialize(config)
    if g_crypt and g_crypt.md5 then return g_crypt.md5(str) end
    return str
end

function g_spells.cleanupRegistry()
    if not g_spells.RegisteredEffects then return end
    local now = os.time()
    local ttl = 3600 -- 1 hour TTL
    
    for id, entry in pairs(g_spells.RegisteredEffects) do
        if type(entry) == "table" and entry.lastAccess then
            if (now - entry.lastAccess) > ttl then
                g_spells.RegisteredEffects[id] = nil
            end
        elseif type(entry) == "boolean" then
             -- Auto-migrate/clean legacy boolean entries
             g_spells.RegisteredEffects[id] = nil
        end
    end
    
    g_spells.cleanupEvent = scheduleEvent(g_spells.cleanupRegistry, 600 * 1000) -- Check every 10 mins
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
            
            local config = data.config
            local currentChecksum = generateChecksum(config)
            local now = os.time()
            local entry = g_spells.RegisteredEffects[id]
            
            local needsRegister = false
            
            if not entry then
                -- New registration
                needsRegister = true
            elseif type(entry) == "table" then
                -- Check Checksum
                if entry.checksum ~= currentChecksum then
                     g_logger.warning(string.format("[SpellVisuals] Config mismatch for ID %d. Re-registering.", id))
                     needsRegister = true
                else
                     -- Update Access Time (LRU)
                     entry.lastAccess = now
                end
            else
                -- Legacy boolean support (force update to new format)
                needsRegister = true
            end
            
            if needsRegister then
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
                
                -- Update Cache
                g_spells.RegisteredEffects[id] = {
                    checksum = currentChecksum,
                    lastAccess = now
                }
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

-- ========================================================
-- STRESS TEST SUITE===========================================
function g_spells.runStressTest()
    g_logger.info("[StressTest] Starting Heavy Stress Test Suite...")
    -- Tests: Singleton stability, InputStack integrity, Widget destruction, Memory leaks
    g_logger.info("[StressTest] 1. Thrashing Selection State (1000 cycles)...")
    local start = g_clock.millis()
    for i = 1, 1000 do
        g_spells.requestPosition({
            spellName = "Stress_" .. i,
            asset = nil, -- Test without asset first
            callback = function() end
        })
        
        -- Force internal state check
        if not SelectionController:isActive() then
            g_logger.error("[StressTest] Failed to activate selection at cycle " .. i)
        end
        
        g_spells.cancelSelection()
        
        if SelectionController:isActive() then
            g_logger.error("[StressTest] Failed to cancel selection at cycle " .. i)
        end
    end
    g_logger.info("[StressTest] Thrashing complete in " .. (g_clock.millis() - start) .. "ms")

    -- 2. Render Pipeline & Throttle
    -- Tests: Math cache, Throttle logic, Coordinate projection
    g_logger.info("[StressTest] 2. Hammering Render Pipeline (5000 events)...")
    g_spells.requestPosition({ spellName = "Stress_Render", range = 5 })
    local state = SelectionController.active
    if state then
        start = g_clock.millis()
        local moves = 0
        local ignored = 0
        
        -- Mock widget for feedback
        state.previewWidgets = {{ widget = g_ui.createWidget('UIWidget', modules.game_interface.getRootPanel()), config = {} }}
        
        for i = 1, 5000 do
            -- Simulate random mouse positions
            local mockPos = { x = math.random(0, 800), y = math.random(0, 600) }
            
            -- Bypass throttle for stress test
            state.lastMoveTime = 0 
            
            -- Manually invoke handler
            state.onMouseMove(nil, mockPos, nil)
        end
        g_logger.info("[StressTest] Render Hammering complete in " .. (g_clock.millis() - start) .. "ms")
        g_spells.cancelSelection()
    else
        g_logger.error("[StressTest] Could not start selection for Render Test")
    end

    -- 3. Registry Cache Explosion
    -- Tests: Table growth, Opcode parsing, AttachedEffectManager load
    g_logger.info("[StressTest] 3. Simulating Registry Explosion (2000 unique effects)...")
    start = g_clock.millis()
    local fakeProtocol = {}
    for i = 1, 2000 do
        local id = 900000 + i
        local data = {
            action = "register_effect",
            id = id,
            name = "StressEffect_" .. id,
            config = { thingId = 10, type = "outfit" }
        }
        -- We pass JSON string to force parsing load
        g_spells.onExtendedOpcode(fakeProtocol, 50, json.encode(data))
    end
    g_logger.info("[StressTest] Registry Explosion complete in " .. (g_clock.millis() - start) .. "ms")
    
    -- Verify Cache Size
    local count = 0
    if g_spells.RegisteredEffects then
        for _ in pairs(g_spells.RegisteredEffects) do count = count + 1 end
    end
    g_logger.info("[StressTest] RegisteredEffects Size: " .. count)

    g_logger.info("[StressTest] All Tests Finished in " .. (g_clock.millis() - startTotal) .. "ms")
end
