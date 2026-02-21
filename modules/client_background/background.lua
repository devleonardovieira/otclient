-- private variables
local background
backgroundController = Controller:new()
local clientVersionLabel
local bgEffectEvent = nil
local toggleState = true  -- controls which effect  is active
local timeLoopBackgroundEffect = 5000 -- 5 seconds

-- public functions
function backgroundController:onInit()
    background = g_ui.displayUI('background')
    if not background then
        g_logger.error('client_background: failed to load background UI')
        return
    end

    background:lower()
    clientVersionLabel = background:getChildById('clientVersionLabel')
    if clientVersionLabel then
        clientVersionLabel:setText("Copyright 2025 Shin Online. All Rights Reserverd.")
    end
    local logoutButton = background:getChildById('logoutButton')
    if logoutButton then
        logoutButton:hide()
    end
    if not g_game.isOnline() and clientVersionLabel then
        addEvent(function()
            g_effects.fadeIn(clientVersionLabel, 1500)
        end)
    end
    backgroundController:registerEvents(g_game, {
        onGameStart = hide,
        onGameEnd = show
    })
    startBackgroundEffectLoop()
end

function backgroundController:onTerminate()
    if background then
        local versionLabel = background:getChildById('clientVersionLabel')
        if versionLabel then
            g_effects.cancelFade(versionLabel)
        end
    end

    if bgEffectEvent then
        removeEvent(bgEffectEvent)
        bgEffectEvent = nil
    end
    if background then
        background:destroy()
        background = nil
    end
    clientVersionLabel = nil
    backgroundController:checkWidgetsDestroyed()
end

function hide()
    if not background then
        return
    end

    background:hide()
    if bgEffectEvent then
        removeEvent(bgEffectEvent)
        bgEffectEvent = nil
    end
end

function show()
    if not background then
        return
    end

    background:show()
    startBackgroundEffectLoop()
end

function hideVersionLabel()
    if not background then
        return
    end

    local versionLabel = background:getChildById('clientVersionLabel')
    if versionLabel then
        versionLabel:hide()
    end
end

function setVersionText(text)
    if clientVersionLabel then
        clientVersionLabel:setText(text)
    end
end

function getBackground()
    return background
end

-- 🔄 example of how to use the particles widget
function startBackgroundEffectLoop()
    if bgEffectEvent then
        removeEvent(bgEffectEvent)
        bgEffectEvent = nil
    end

    local function switchEffect()
        if not background then
            return
        end

        local particlesWidget = background:getChildById('particles') -- background is the root widget of the background module
        if not particlesWidget then
            return
        end

        if toggleState then
            particlesWidget:setEffect('background-effect')
        else
            particlesWidget:setEffect('background2-effect')
        end
        toggleState = not toggleState

        -- repeat every 5 seconds (adjust the time you want)
        bgEffectEvent = scheduleEvent(switchEffect, timeLoopBackgroundEffect)
    end

    -- start the first effect change
    switchEffect()
end
