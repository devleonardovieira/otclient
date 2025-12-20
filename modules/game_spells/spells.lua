g_spells = {}

local currentSelection = nil

function init()
    _G.g_spells = g_spells
    if ProtocolGame and ProtocolGame.registerExtendedJSONOpcode then
        ProtocolGame.registerExtendedJSONOpcode(50, g_spells.onExtendedOpcode)
    else
        ProtocolGame.registerExtendedOpcode(50, g_spells.onExtendedOpcode)
    end
    
    connect(g_game, { onGameEnd = g_spells.cleanupSelection })
end

function terminate()
    g_spells.cleanupSelection()
    
    if ProtocolGame and ProtocolGame.unregisterExtendedJSONOpcode then
        ProtocolGame.unregisterExtendedJSONOpcode(50, g_spells.onExtendedOpcode)
    else
        ProtocolGame.unregisterExtendedOpcode(50, g_spells.onExtendedOpcode)
    end
    
    disconnect(g_game, { onGameEnd = g_spells.cleanupSelection })
    
    _G.g_spells = nil
    g_spells = nil
end

-- ========================================================
-- SELECTION CONTROLLER (THE HAND)
-- ========================================================

-- Unified cleanup function (safe to call anytime)
function g_spells.cleanupSelection()
    local s = currentSelection
    if not s then return end
    
    -- Set to nil immediately to prevent re-entrancy
    currentSelection = nil

    -- 0. Cancel Timeout Event
    if s.timeoutEvent then
        removeEvent(s.timeoutEvent)
        s.timeoutEvent = nil
    end
    
    -- 1. Cleanup Preview Widgets
    if s.previewWidgets then
        for _, widget in pairs(s.previewWidgets) do
            if widget and not widget:isDestroyed() then
                widget:destroy()
            end
        end
        s.previewWidgets = nil
    end
    
    -- 2. Restore Mouse/Keyboard State
    local mouseGrabber = modules.game_interface.getRootPanel():recursiveGetChildById('mouseGrabber')
    if mouseGrabber then
        if s.onMouseMove then
            disconnect(mouseGrabber, { onMouseMove = s.onMouseMove })
        end
        
        mouseGrabber:ungrabMouse()
        mouseGrabber:ungrabKeyboard()
        
        -- Restore original handlers
        mouseGrabber.onMouseRelease = modules.game_interface.onMouseGrabberRelease
        mouseGrabber.onKeyPress = nil
    end
    
    g_mouse.popCursor("target")
    
    -- 3. Trigger onCancel callback if it exists (and not triggered by success)
    if s.onCancel and not s.success then
        pcall(s.onCancel)
    end
    
    -- 4. Detach Casting Effect (Fail-safe)
    if s.castingEffect then
        local player = g_game.getLocalPlayer()
        if player then
            -- Try to detach even if modules are unloaded, provided the method exists
            if player.detachEffectById then
                player:detachEffectById(s.castingEffect)
            end
        end
    end
end

-- Explicit cancel action (sends opcode to server)
function g_spells.cancelSelection()
    -- Send cancel opcode if we have an active selection
    if currentSelection then
        local protocol = g_game.getProtocolGame()
        if protocol then
             local data = {action = "cancel"}
             if protocol.sendExtendedJSONOpcode then
                  protocol:sendExtendedJSONOpcode(50, data)
             else
                  protocol:sendExtendedOpcode(50, json.encode(data))
             end
        end
    end
    
    -- Proceed with local cleanup
    g_spells.cleanupSelection()
end

function g_spells.requestPosition(options)
    -- Enforce strict table parameter
    if type(options) ~= "table" then
        return
    end

    -- 1. Cancel any existing selection
    g_spells.cleanupSelection()
    
    local gameMapPanel = modules.game_interface.getGameMapPanel()
    if not gameMapPanel then return end

    -- 2. Handle Instant Mode (No preview, just click)
    if options.instant then
        local mousePos = g_window.getMousePosition()
        local tile = gameMapPanel:getTile(mousePos)
        if tile and options.callback then
            pcall(options.callback, tile:getPosition())
        end
        return
    end

    -- 3. Setup Selection Mode
    local mouseGrabber = modules.game_interface.getRootPanel():recursiveGetChildById('mouseGrabber')
    if not mouseGrabber then return end
    
    local selectionState = {
        options = options,
        callback = options.callback,
        onCancel = options.onCancel,
        castingEffect = options.castingEffect, -- Store for cleanup
        previewWidgets = {},
        lastTilePos = nil, -- Optimization: cache last tile position
        cache = {
            tileSize = nil,
            mapRect = nil,
            cameraPos = nil
        }
    }
    
    -- Auto-Cancel Timeout (30 seconds)
    selectionState.timeoutEvent = scheduleEvent(function()
        if currentSelection == selectionState then
             g_spells.cancelSelection()
        end
    end, 30000)
    
    -- Handle Casting Effect (Local Attach)
    if options.castingEffect then
        if g_attachedEffects and AttachedEffectManager then
            local player = g_game.getLocalPlayer()
            if player then
                local effectId = options.castingEffect
                
                -- If castingEffect is a table (dynamic config from server)
                if type(options.castingEffect) == "table" then
                    local config = options.castingEffect
                    -- Unique ID generation to prevent collisions
                    -- Base: 5000 + (Time % 10000) + Random(100)
                    local tempId = 5000 + (g_clock.millis() % 10000) + math.random(1, 100)
                    
                    -- Determine Category
                    local category = ThingCategoryEffect
                    if config.type == "outfit" then
                        category = ThingCategoryCreature
                    elseif config.type == "item" then
                        category = ThingCategoryItem
                    end
                    
                    -- Ensure category is valid (fallback if global constants are missing or nil)
                    if not category then
                        if config.type == "outfit" then category = 1 end -- ThingCategoryCreature
                        if config.type == "item" then category = 2 end -- ThingCategoryItem
                        if config.type == "effect" then category = 3 end -- ThingCategoryEffect
                    end
                    
                    -- Register/Update the dynamic effect
                    AttachedEffectManager.register(tempId, "DynamicCasting", config.thingId or 1, category, config)
                    
                    effectId = tempId
                    
                    -- Update selection state to point to the temp ID for cleanup
                    selectionState.castingEffect = tempId
                end
                
                local effect = g_attachedEffects.getById(effectId)
                if effect then
                    player:attachEffect(effect)
                end
            end
        else
            if not g_attachedEffects then g_logger.error("Spells: g_attachedEffects is nil") end
            if not AttachedEffectManager then g_logger.error("Spells: AttachedEffectManager is nil (Check game_attachedeffects dependency)") end
        end
    end
    
    -- 4. Setup Preview (Asset-Driven)
    if options.asset then
         local w = g_ui.createWidget('UIWidget', modules.game_interface.getRootPanel())
         w:setPhantom(true)
         w:setOpacity(0.7)
         w:setImageSource(options.asset)
         table.insert(selectionState.previewWidgets, w)
         
         selectionState.onMouseMove = function(widget, mousePos, mouseMoved)
            -- Force update mouse position to be safe
            mousePos = g_window.getMousePosition()
            
            local gameMapPanel = modules.game_interface.getGameMapPanel()
            if not gameMapPanel then return end
            
            local centerTile = gameMapPanel:getTile(mousePos)
            local w = selectionState.previewWidgets[1]
            if not w then return end

            if not centerTile then
                w:setVisible(false)
                selectionState.lastTilePos = nil
                return
            end
            
            -- OPTIMIZATION: Only recalculate if tile changed
            local centerPos = centerTile:getPosition()
            local cache = selectionState.cache
            
            -- Invalidate mapRect cache if window size changed
            local root = modules.game_interface.getRootPanel()
            if root and cache.rootSize then
                if root:getWidth() ~= cache.rootSize.width or root:getHeight() ~= cache.rootSize.height then
                     cache.mapRect = nil -- Force recalcultion
                     cache.tileSize = nil
                     cache.rootSize = {width = root:getWidth(), height = root:getHeight()}
                end
            elseif root then
                cache.rootSize = {width = root:getWidth(), height = root:getHeight()}
            end

            if selectionState.lastTilePos and 
               selectionState.lastTilePos.x == centerPos.x and 
               selectionState.lastTilePos.y == centerPos.y and 
               selectionState.lastTilePos.z == centerPos.z and
               cache.mapRect ~= nil then -- Only skip if mapRect is valid
                return
            end
            selectionState.lastTilePos = centerPos

            -- Calculate Metrics (Cached)
            local dimension = gameMapPanel:getVisibleDimension()
            local currentTileSize = gameMapPanel:getHeight() / dimension.height
            
            -- Recalculate cache if needed (e.g. zoom changed)
            if not cache.tileSize or math.abs(cache.tileSize - currentTileSize) > 0.1 then
                cache.tileSize = currentTileSize
                cache.mapRect = gameMapPanel:getRect() -- Cache rect too as it likely changed
            end
            local tileSize = cache.tileSize

            -- Calculate Position
            local cameraPos = nil
            if gameMapPanel.getCameraPosition then
                cameraPos = gameMapPanel:getCameraPosition()
            end
            if not cameraPos then
                local player = g_game.getLocalPlayer()
                if player then cameraPos = player:getPosition() end
            end
            
            -- Invalidate mapRect cache if camera moved (optional, but safer for edge scrolling)
            -- But for now we trust mapRect doesn't change position on screen unless window resizes
            -- Actually mapRect is the UI panel position, it doesn't change when player walks.
            -- So we can keep cache.mapRect constant unless window resizes.
            if not cache.mapRect then
                cache.mapRect = gameMapPanel:getRect()
            end

            local baseX, baseY = 0, 0
            if cameraPos then
                local mapRect = cache.mapRect
                local screenCenterX = mapRect.x + (mapRect.width / 2)
                local screenCenterY = mapRect.y + (mapRect.height / 2)
                
                local diffX = centerPos.x - cameraPos.x
                local diffY = centerPos.y - cameraPos.y
                
                baseX = screenCenterX + (diffX * tileSize) - (tileSize / 2)
                baseY = screenCenterY + (diffY * tileSize) - (tileSize / 2)
            else
                baseX = mousePos.x - (tileSize / 2)
                baseY = mousePos.y - (tileSize / 2)
            end

            -- Calculate Size & Offset based on Tiles count
            local pWidth = (options.tiles and options.tiles.width or 1) * tileSize
            local pHeight = (options.tiles and options.tiles.height or 1) * tileSize
            
            w:setSize({width = pWidth, height = pHeight})
            w:setVisible(true)
            
            -- Center the image on the tile
            local finalX = baseX + (tileSize / 2) - (pWidth / 2)
            local finalY = baseY + (tileSize / 2) - (pHeight / 2)
            w:setPosition({x = finalX, y = finalY})

            -- Validation Logic (Cached Result implicitly by tile change check)
            local player = g_game.getLocalPlayer()
            local isValid = false
            if player then
                local playerPos = player:getPosition()
                local targetPos = centerTile:getPosition()
                if options.validate then
                    isValid = options.validate(targetPos, playerPos)
                else
                    -- Standard validation
                    local dist = math.max(math.abs(playerPos.x - targetPos.x), math.abs(playerPos.y - targetPos.y))
                    local inRange = not options.range or (dist <= options.range)
                    local visible = true
                    if g_map.isSightClear and not g_map.isSightClear(playerPos, targetPos) then
                        visible = false
                    end
                    isValid = inRange and visible
                end
            end
            
            selectionState.isValid = isValid
            local color = isValid and '#ffffff' or '#ff4444' -- White (normal) or Red (blocked)
            w:setImageColor(color)
        end
        
        connect(mouseGrabber, { onMouseMove = selectionState.onMouseMove })
        
        -- Trigger immediately to set initial validity/position
        selectionState.onMouseMove(nil, g_window.getMousePosition(), nil)
    end
    
    -- 5. Grab Input
    mouseGrabber:grabMouse()
    mouseGrabber:grabKeyboard()
    g_mouse.pushCursor("target")
    
    -- 6. Event Handlers
    mouseGrabber.onMouseRelease = function(widget, mousePos, mouseButton)
        if mouseButton == MouseLeftButton then
            -- Check validation before proceeding
            if selectionState.isValid == false then
                return true -- Block invalid selection
            end

            local tile = gameMapPanel:getTile(mousePos)
            if tile then
                local pos = tile:getPosition()
                local callback = selectionState.callback
                
                -- Mark success to avoid onCancel trigger
                selectionState.success = true
                g_spells.cleanupSelection()
                
                -- Execute Callback
                if callback then
                    pcall(callback, pos)
                end
            end
            return true
        elseif mouseButton == MouseRightButton then
            g_spells.cancelSelection()
            return true
        end
        return true
    end
    
    mouseGrabber.onKeyPress = function(widget, keyCode, keyboardModifiers)
        if keyCode == KeyEscape then
            g_spells.cancelSelection()
            return true
        end
        
        -- Movement Support (WASD + Arrows)
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
            return true -- Consume the event so it doesn't do anything else
        end
        
        return false -- Pass other keys
    end
    
    currentSelection = selectionState
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
            castingEffect = data.castingEffect, -- Pass through effect ID
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
