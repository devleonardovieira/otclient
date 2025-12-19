g_spells = {}

local currentSelection = nil

function init()
    _G.g_spells = g_spells
end

function terminate()
    g_spells.cancelSelection()
    _G.g_spells = nil
    g_spells = nil
end

-- ========================================================
-- HELPER FUNCTIONS
-- ========================================================

-- (Legacy functions removed as requested)

-- ========================================================
-- MOUSE SELECTION CONTROLLER (THE HAND)
-- Responsável APENAS por capturar o input e mostrar preview
-- ========================================================

function g_spells.cancelSelection()
    if not currentSelection then return end
    
    local s = currentSelection
    -- Set to nil immediately to prevent re-entrancy
    currentSelection = nil
    
    -- Cleanup Preview Widgets
    if s.previewWidgets then
        for _, widget in pairs(s.previewWidgets) do
            widget:destroy()
        end
        s.previewWidgets = nil
    end
    
    -- Restore Mouse/Keyboard State
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
    
    -- Trigger onCancel callback if it exists
    if s.onCancel then
        pcall(s.onCancel)
    end
end

function g_spells.requestPosition(options)
    -- Enforce strict table parameter
    if type(options) ~= "table" then
        perror("g_spells.requestPosition: options must be a table")
        return
    end

    -- 1. Cancel any existing selection (Global State Management)
    g_spells.cancelSelection()
    
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
        previewWidgets = {} -- List of UIWidgets for tiles
    }
    
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

            local dimension = gameMapPanel:getVisibleDimension()
            local tileSize = gameMapPanel:getHeight() / dimension.height
            
            local w = selectionState.previewWidgets[1]
            if not w then return end
            
            local centerTile = gameMapPanel:getTile(mousePos)
            if not centerTile then
                w:setVisible(false)
                return
            end

            -- Calculate Position
            local cameraPos = nil
            if gameMapPanel.getCameraPosition then
                cameraPos = gameMapPanel:getCameraPosition()
            end
            if not cameraPos then
                local player = g_game.getLocalPlayer()
                if player then cameraPos = player:getPosition() end
            end

            local baseX, baseY = 0, 0
            if cameraPos then
                local centerPos = centerTile:getPosition()
                local mapRect = gameMapPanel:getRect()
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

            -- Validation Logic
            local player = g_game.getLocalPlayer()
            local isValid = false
            if player then
                local playerPos = player:getPosition()
                local targetPos = centerTile:getPosition()
                if options.validate then
                    isValid = options.validate(targetPos, playerPos)
                else
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
                
                -- Cleanup state manually (success path)
                currentSelection = nil
                
                -- Destroy widgets
                if selectionState.previewWidgets then
                    for _, w in pairs(selectionState.previewWidgets) do
                        w:destroy()
                    end
                end
                
                if selectionState.onMouseMove then
                    disconnect(mouseGrabber, { onMouseMove = selectionState.onMouseMove })
                end
                
                mouseGrabber:ungrabMouse()
                mouseGrabber:ungrabKeyboard()
                mouseGrabber.onMouseRelease = modules.game_interface.onMouseGrabberRelease
                mouseGrabber.onKeyPress = nil
                g_mouse.popCursor("target")
                
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
        return false
    end
    
    currentSelection = selectionState
end

-- ========================================================
-- CONFIG & SPELL REGISTRY
-- ========================================================
local SpellsConfig = {
    ["exevo gran mas flam"] = {
        asset = "/images/spell_assets/Lightning - 15 ft. radius - 8x8.png",
        tiles = {width = 8, height = 8},
        range = 7, -- Max cast distance
        mana = 1100,
        cooldown = 40000,
        cast = "position" -- self | position | target
    },
    ["exevo vis hur"] = {
        asset = "/images/spell_assets/Lightning - 15 ft. cone - 4x4.png",
        tiles = {width = 4, height = 4},
        range = 5,
        mana = 170,
        cooldown = 8000,
        cast = "position"
    },
    ["exura vita"] = {
        mana = 160,
        cooldown = 1000,
        cast = "self"
    }
}

-- ========================================================
-- SPELL CONTROLLER (THE BRAIN)
-- ========================================================
SpellController = {}

function SpellController.cast(spellName)
    local spell = SpellsConfig[spellName]
   --[[  if not spell then
        g_game.talk(spellName) -- Fallback for unknown spells
        return
    end ]]

    local player = g_game.getLocalPlayer()
    if not player then return end

    -- 1. Validate Mana (Client-side check)
  --[[   if player:getMana() < spell.mana then
        modules.game_textmessage.displayGameMessage(TextMessageCenterRed, "Not enough mana.")
        return
    end
 ]]
    -- 2. Validate Cooldown (Client-side check)
    -- This requires storing last cast time. For now, we skip or implement basic storage.
    -- if isCooldown(spellName) then return end

    -- 3. Decide Input Type based on Cast Mode
    if spell.cast == "self" then
        SpellController.execute(spellName, player:getPosition())
    elseif spell.cast == "position" then
        -- Request Mouse Position with Asset Preview
        g_spells.requestPosition({
            asset = spell.asset,
            tiles = spell.tiles,
            range = spell.range,
            validate = function(pos, playerPos)
                -- Custom validation logic (e.g., line of sight, range)
                local dist = math.max(math.abs(playerPos.x - pos.x), math.abs(playerPos.y - pos.y))
                local inRange = not spell.range or (dist <= spell.range)
                local visible = true
                if g_map.isSightClear and not g_map.isSightClear(playerPos, pos) then
                    visible = false
                end
                return inRange and visible
            end,
            callback = function(pos)
                SpellController.execute(spellName, pos)
            end
        })
    elseif spell.cast == "instant_mouse" then 
        -- Fallback if we want instant mouse cast without preview (just in case)
        g_spells.requestPosition({
            instant = true,
            callback = function(pos)
                SpellController.execute(spellName, pos)
            end
        })
    end
end

function SpellController.execute(spellName, targetPos)
    local spell = SpellsConfig[spellName]
    
    -- 1. Client Side Prediction: REMOVED EFFECTS as requested
    
    -- 2. Send Command to Server
    g_game.talk(spellName)
    
    -- 3. Trigger Cooldown (Visual only)
    -- startCooldown(spellName)
end
