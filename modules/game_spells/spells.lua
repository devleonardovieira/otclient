g_spells = {}

-- ========================================================
-- UTILS
-- ========================================================
-- Helper: Correct rounding for negatives (True Truncate)
local function trunc(v) 
    return v >= 0 and (v - v % 1) or (v + (-v % 1)) 
end

local function computeTileScreenRect(gameMapPanel, tilePos, tiles, cache, cameraPos)
    if not gameMapPanel or not tilePos then return nil end
    
    -- Strict Camera: If not provided, abort (Caller must handle it)
    if not cameraPos then return nil end

    local tileSize = cache.tileSize
    local mapRect = cache.mapRect
    
    -- Strict Cache: Expect valid cache from updateRender
    if not tileSize or not mapRect then return nil end

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
    
    -- Optimization: Fast Rounding Inline (Lua 5.1 safe)
    return { 
        x = trunc(finalX), 
        y = trunc(finalY), 
        width = trunc(width), 
        height = trunc(height) 
    }
end

-- ========================================================
-- INPUT HELPER (Modal Manager)
-- ========================================================
function g_spells.captureInput(callbacks)
    local rootPanel = modules.game_interface.getRootPanel()
    local mouseGrabber = rootPanel:recursiveGetChildById('mouseGrabber')
    if not mouseGrabber then return nil end
    
    local handle = {
        mouseGrabber = mouseGrabber,
        active = true,
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
    
    -- Safe KeyPress Stack (Explicit Stack)
    handle.proxyKeyPress = function(widget, keyCode, keyboardModifiers)
        if not handle.active then
            return false
        end
        
        -- Try to handle it (Protected)
        if callbacks.onKeyPress then
            local status, result = pcall(callbacks.onKeyPress, widget, keyCode, keyboardModifiers)
            if status and result then
                return true
            elseif not status then
                 g_logger.error("[Spells Input] KeyPress Error: " .. tostring(result))
            end
        end
        return false
    end
    
    -- Init Stack if needed
    mouseGrabber._keyPressStack = mouseGrabber._keyPressStack or {}
    table.insert(mouseGrabber._keyPressStack, handle.proxyKeyPress)
    
    -- Master Proxy (Only installed once)
    if not mouseGrabber._masterProxy then
        mouseGrabber._masterProxy = function(widget, keyCode, keyboardModifiers)
            local stack = mouseGrabber._keyPressStack
            if not stack then return false end
            
            -- Iterate from top to bottom
            for i = #stack, 1, -1 do
                local handler = stack[i]
                if handler(widget, keyCode, keyboardModifiers) then
                    return true
                end
            end
            return false
        end
        mouseGrabber.onKeyPress = mouseGrabber._masterProxy
    end
    
    -- Reference Counting for Grab
    mouseGrabber._grabCount = (mouseGrabber._grabCount or 0) + 1
    if mouseGrabber._grabCount == 1 then
        mouseGrabber:grabMouse()
        mouseGrabber:grabKeyboard()
    end
    
    return handle
end

function g_spells.releaseInput(handle)
    if not handle or not handle.mouseGrabber then return end
    
    -- Mark as inactive
    handle.active = false
    
    local mg = handle.mouseGrabber
    
    if handle.mouseReleaseConnected and handle.callbacks.onMouseRelease then
        disconnect(mg, { onMouseRelease = handle.callbacks.onMouseRelease })
    end
    
    if handle.mouseMoveConnected and handle.callbacks.onMouseMove then
        disconnect(mg, { onMouseMove = handle.callbacks.onMouseMove })
    end
    
    -- Remove from Stack
    if mg._keyPressStack then
        for i, func in ipairs(mg._keyPressStack) do
            if func == handle.proxyKeyPress then
                table.remove(mg._keyPressStack, i)
                break
            end
        end
        
        -- Cleanup Master Proxy if stack is empty
        if #mg._keyPressStack == 0 then
            mg.onKeyPress = nil
            mg._masterProxy = nil
        end
    end

    -- Reference Counting for Ungrab
    if mg._grabCount then
        mg._grabCount = mg._grabCount - 1
        if mg._grabCount <= 0 then
            mg:ungrabMouse()
            mg:ungrabKeyboard()
            mg._grabCount = 0
        end
    else
        -- Fallback if count is missing (Safety)
        mg:ungrabMouse()
        mg:ungrabKeyboard()
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
    --[[ _G.g_spells_cache = {}
    g_spells.RegisteredEffects = _G.g_spells_cache ]]
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
        -- Safe recycling: Re-parent to root to avoid orphans if previous parent dies
        w:setParent(modules.game_interface.getRootPanel())
        w:setVisible(false)
        
        -- Cap pool size to prevent memory leaks
        if #self.pool < 200 then
            table.insert(self.pool, w)
        else
            w:destroy()
        end
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
    
    -- Fix: Validate Z plane
    if playerPos.z ~= targetPos.z then return false end
    
    local params = state.options or {}
    
    if params.validate then
        return params.validate(targetPos, playerPos)
    else
        -- Standard validation (Micro-optimized math)
        local dx = playerPos.x - targetPos.x
        local dy = playerPos.y - targetPos.y
        if dx < 0 then dx = -dx end
        if dy < 0 then dy = -dy end
        
        local dist = (dx > dy) and dx or dy
        
        -- Optimization: Short-circuit range check before sight check
        if params.range and dist > params.range then
             return false
        end
        
        -- Optimization: Short-circuit sight check
        if params.checkSight ~= false and g_map.isSightClear and not g_map.isSightClear(playerPos, targetPos) then
            return false
        end
        
        return true
    end
end

local function updateRender(state, gameMapPanel, centerPos, isValid, cameraPos)
    local cache = state.cache
    
    -- Recalculate basic metrics if needed (Time-Slice: 16ms)
    local now = g_clock.millis()
    if not cache.lastFrame or (now - cache.lastFrame) > 16 then
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
        cache.lastFrame = now
    end

    -- Update All Widgets
    if state.previewWidgets then
        -- Check if position changed to avoid redundant calculations
        local posChanged = false
        
        if not state.lastTilePos then
            posChanged = true
            state.lastTilePos = {x=centerPos.x, y=centerPos.y, z=centerPos.z}
        elseif state.lastTilePos.x ~= centerPos.x or 
               state.lastTilePos.y ~= centerPos.y or 
               state.lastTilePos.z ~= centerPos.z then
            posChanged = true
            -- Reuse table to avoid GC
            state.lastTilePos.x = centerPos.x
            state.lastTilePos.y = centerPos.y
            state.lastTilePos.z = centerPos.z
        end

        if posChanged then
            
            for _, entry in ipairs(state.previewWidgets) do
                local w = entry.widget
                local config = entry.config or {}
                
                local renderPos = centerPos
                if config.offset then
                    renderPos = { x = centerPos.x + config.offset.x, y = centerPos.y + config.offset.y, z = centerPos.z }
                end
                
                local tiles = config.tiles or state.options.tiles
                
                local rect = computeTileScreenRect(gameMapPanel, renderPos, tiles, cache, cameraPos)
                
                if rect then
                    -- Visual Improvement: 1px Gap + Border same as background
                    w:setSize({width = math.max(1, rect.width - 1), height = math.max(1, rect.height - 1)})
                    w:setPosition({x = rect.x, y = rect.y})
                    
                    -- Define cores
                    local bgColor = state.isValid and '#00FF0066' or '#FF000066' -- mesma cor do fundo
                    w:setBackgroundColor(bgColor)
                    w:setBorderColor(bgColor)
                    w:setBorderWidth(1)
                    
                    w:setVisible(true)
                else
                    w:setVisible(false)
                end
            end

            
            -- Hide Unused Widgets (if area shrank or widgets exceed needed)
            if #state.previewWidgets > 0 then
                -- Note: Logic above iterates all widgets. But if we dynamically resize pool?
                -- Current logic iterates ALL previewWidgets. So "unused" means handled inside loop?
                -- Actually, if logic is "one widget per tile", we just iterate all.
                -- BUT if we want to support dynamic area size (not current case), we would need to hide extras.
                -- For now, all widgets in state.previewWidgets ARE used.
                -- The "Hide Unused" logic is relevant if we were reusing a pool > needed.
                -- Since we create exactly needed count in init, this is fine.
                -- But for safety/robustness if logic changes:
                -- for i = #needed + 1, #state.previewWidgets do ... end
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
    -- Optimization: Cache root panel
    local rootPanel = modules.game_interface.getRootPanel()

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
        listeners = {}, -- Cursor/State Listeners (Transient: Cleared via GC/finish)
        lastTilePos = nil,
        lastTile = nil, -- Tile Cache
        player = g_game.getLocalPlayer(), -- Player Cache
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
        -- Note: If FPS drops, visual feedback might lag. This is an intended trade-off for performance.
        local currentFps = g_app.getFps()
        local frameTime = 1000 / math.max(10, currentFps) -- Min 10 FPS cap
        frameTime = math.max(16, frameTime) -- Max 60 FPS cap
        
        local now = g_clock.millis()
        if state.lastMoveTime and (now - state.lastMoveTime) < frameTime then
            return
        end
        state.lastMoveTime = now

        local gameMapPanel = modules.game_interface.getGameMapPanel()
        if not gameMapPanel then return end

        -- Force update mouse position to be safe (unless testing)
        mousePos = mousePos or g_window.getMousePosition()
        
        -- Optimization: Tile Cache to avoid expensive logic when mouse didn't change tile
        local centerTile = gameMapPanel:getTile(mousePos)
        if state.lastTile and centerTile == state.lastTile then return end
        state.lastTile = centerTile
        
        -- Optimization: Use cached player (with stale check)
        if not state.player or state.player:isRemoved() then
            state.player = g_game.getLocalPlayer()
        end
        local player = state.player
        local playerPos = player and player:getPosition() or nil
        
        -- Cache Camera Position per frame (validation + render)
        -- Use cached value if frame matches (Time-Slice: 16ms)
        local now = g_clock.millis()
        if not state.cache.cameraFrame or (now - state.cache.cameraFrame) > 16 then
             state.cache.cameraPos = nil
             if gameMapPanel.getCameraPosition then
                 state.cache.cameraPos = gameMapPanel:getCameraPosition()
             end
             -- Fallback if nil
             if not state.cache.cameraPos and playerPos then
                 state.cache.cameraPos = playerPos
             end
             state.cache.cameraFrame = now
        end
        local cameraPos = state.cache.cameraPos

        -- Render Pipeline
        local isValid = false
        if centerTile then
            local centerPos = centerTile:getPosition()
            
            -- 1. Validate
            isValid = validateTarget(state, playerPos, centerPos)
            
            -- 2. Notify Listeners (Cursor Feedback decoupled) & Update Colors
            if state.isValid ~= isValid then
                state:notify(isValid)
                
                -- Optimization: Color Update only on state change
                if state.previewWidgets then
                    local mainColor = isValid and '#00FF00' or '#FF0000'
                    local bgColor = isValid and '#00FF0066' or '#FF000066' -- Slightly more opaque for better visibility without borders
                    for _, entry in ipairs(state.previewWidgets) do
                        if entry.widget then
                            -- entry.widget:setBorderColor(mainColor) -- Removed to clean up the grid
                            entry.widget:setBackgroundColor(bgColor)
                            entry.widget:setImageColor('#ffffff')
                        end
                    end
                end
            end
            state.isValid = isValid
            
            -- 3. Render Preview
            updateRender(state, gameMapPanel, centerPos, isValid, cameraPos)
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
        if params.areaOffsets and #params.areaOffsets > 0 then
            for _, offset in ipairs(params.areaOffsets) do
                local w = WidgetPool:get(rootPanel)
               --[[  w:setImageSource(params.asset) ]]
                w:setOpacity(0.8)
                table.insert(state.previewWidgets, { widget = w, config = { tiles = {width=1, height=1}, offset = offset } })
            end
        else
            -- Grid Generation: Populate widgets for each tile in the area
            -- This ensures updateRender has enough widgets to display the full grid
            local tiles = params.tiles or {width=1, height=1}
            local width = tiles.width or 1
            local height = tiles.height or 1
            
            for x = 0, width - 1 do
                for y = 0, height - 1 do
                    local w = WidgetPool:get(rootPanel)
                    w:setOpacity(0.8) -- Default opacity
                    -- Note: offset is relative to center (0,0)
                    -- Adjusting so (0,0) is center, or top-left? 
                    -- Standard: Center is target. Grid usually expands around.
                    -- If 3x3, offsets: -1,-1 to 1,1? Or 0,0 to 2,2?
                    -- Assuming 0,0 is Top-Left of the area relative to target? 
                    -- Actually, computeTileScreenRect handles 'tiles' dimension centering.
                    -- But if we split into 1x1 widgets, we need manual offsets.
                    
                    -- Let's use 0,0 as top-left of the multi-tile area relative to center?
                    -- No, computeTileScreenRect with 'tiles' param handles the whole area centering.
                    -- BUT the user wants a GRID (1x1 tiles), not one big stretched image.
                    
                    -- Correct Approach: Generate 1x1 widgets with Offsets centered around 0,0
                    local offsetX = x - math.floor(width / 2)
                    local offsetY = y - math.floor(height / 2)
                    
                    table.insert(state.previewWidgets, { 
                        widget = w, 
                        config = { 
                            tiles = {width=1, height=1}, 
                            offset = {x=offsetX, y=offsetY, z=0} 
                        } 
                    })
                end
            end
        end
    end
    
    -- 4. Setup Cursor Feedback (Decoupled Listener)
    state:addListener(function(isValid)
        local cursorW = rootPanel:recursiveGetChildById('targetCursor')
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
    
    -- Explicit Listener Cleanup (Help GC)
    s.listeners = nil

    -- Restore Input
    if s.inputHandle then
        g_spells.releaseInput(s.inputHandle)
    end
    pcall(g_mouse.popCursor, "target")
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
    local function serialize(t, depth)
        depth = depth or 0
        if depth > 10 then return "max_depth" end -- Prevent cycle/deep recursion

        local keys = {}
        for k in pairs(t) do table.insert(keys, k) end
        table.sort(keys)
        local parts = {}
        for _, k in ipairs(keys) do
            local v = t[k]
            if type(v) == "table" then
                table.insert(parts, k .. ":" .. serialize(v, depth + 1))
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
    local now = g_clock.millis()
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
        local smartCast = modules.client_options.getOption("smartCast")
        local options = {
            instant = smartCast,
            spellName = data.spellName,
            asset = data.asset,
            tiles = data.tiles,
            range = data.range,
            areaOffsets = data.areaOffsets,
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