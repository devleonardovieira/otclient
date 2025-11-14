tradeWindow = nil
local MAX_TRADE_SLOTS = 14
local countWindow = nil
local ownAccepted = false

local function updateAcceptEnabled()
    if not tradeWindow then return end
    local acceptButton = tradeWindow:recursiveGetChildById('acceptButton')
    local ownContainer = tradeWindow:recursiveGetChildById('ownTradeContainer')
    local counterContainer = tradeWindow:recursiveGetChildById('counterTradeContainer')
    local function hasItems(container, prefix)
        if not container then return false end
        local children = container:recursiveGetChildren()
        for i = 1, #children do
            local w = children[i]
            if w and w.getId and w:getId():find(prefix) and w.getItem and w:getItem() then
                return true
            end
        end
        return false
    end
    local ownHas = hasItems(ownContainer, 'ownSlot')
    local otherHas = hasItems(counterContainer, 'counterSlot')
    if ownAccepted then
        acceptButton:disable()
    else
        acceptButton:setEnabled(ownHas and otherHas)
    end
end

function init()
    g_ui.importStyle('tradewindow')

    connect(g_game, {
        -- New MMO-style trade window events
        onOpenTradeWindow = onOpenTradeWindow,
        onTradeItemAdd = onTradeItemAdd,
        onTradeItemRemove = onTradeItemRemove,
        onTradeAcceptChange = onTradeAcceptChange,
        onCloseTradeWindow = onCloseTradeWindow,
        -- Fallback: close window when game ends
        onGameEnd = onCloseTradeWindow
    })
    print('[playertrade] init: connected game events for trade window')
end

function terminate()
    disconnect(g_game, {
        onOpenTradeWindow = onOpenTradeWindow,
        onTradeItemAdd = onTradeItemAdd,
        onTradeItemRemove = onTradeItemRemove,
        onTradeAcceptChange = onTradeAcceptChange,
        onCloseTradeWindow = onCloseTradeWindow,
        onGameEnd = onCloseTradeWindow
    })

    if tradeWindow then
        tradeWindow:destroy()
    end
end

local function ensureWindow()
    if not tradeWindow then
        -- Garantir que o estilo da janela esteja importado antes de criar o widget
        g_ui.importStyle('tradewindow')
        tradeWindow = g_ui.createWidget('TradeWindow', rootWidget)
        tradeWindow.onClose = function()
            g_game.rejectTrade()
            tradeWindow:destroy()
            tradeWindow = nil
        end
        tradeWindow:show()
        tradeWindow:raise()
        tradeWindow:focus()
        print('[playertrade] ensureWindow: created TradeWindow UI')
    end
end

-- Helper: prompt for count when adding stackable items to a trade slot
local function promptCountAndAdd(slotIndex, item)
    if countWindow then
        return
    end

    local total = item:getCount()

    -- Keyboard shortcuts behavior aligned with moveStackableItem
    if g_keyboard.isShiftPressed() then
        local sendSlot = (slotIndex or 1) - 1
        print(string.format('[playertrade] send AddItem (shift): slot0=%d itemId=%d count=%d', sendSlot, item:getId(), 1))
        g_game.tradeWindowAddItem(sendSlot, item:getId(), 1)
        return
    elseif g_keyboard.isCtrlPressed() ~= modules.client_options.getOption('moveStack') then
        local sendSlot = (slotIndex or 1) - 1
        print(string.format('[playertrade] send AddItem (ctrl/moveStack): slot0=%d itemId=%d count=%d', sendSlot, item:getId(), total))
        g_game.tradeWindowAddItem(sendSlot, item:getId(), total)
        return
    end

    countWindow = g_ui.createWidget('CountWindow', rootWidget)
    countWindow.hotkeyBlock = modules.game_hotkeys.createHotkeyBlock('stackable_item_trade_dialog')

    local itembox = countWindow:getChildById('item')
    local scrollbar = countWindow:getChildById('countScrollBar')
    local spinbox = countWindow:getChildById('spinBox')
    local okButton = countWindow:getChildById('buttonOk')
    local cancelButton = countWindow:getChildById('buttonCancel')

    itembox:setItemId(item:getId())
    itembox:setItemCount(total)

    scrollbar:setMaximum(total)
    scrollbar:setMinimum(1)
    scrollbar:setValue(total)

    spinbox:setMaximum(total)
    spinbox:setMinimum(0)
    spinbox:setValue(0)
    spinbox:hideButtons()
    spinbox:focus()
    spinbox.firstEdit = true

    local spinBoxValueChange = function(self, value)
        spinbox.firstEdit = false
        scrollbar:setValue(value)
    end
    spinbox.onValueChange = spinBoxValueChange

    local check = function()
        if spinbox.firstEdit then
            spinbox:setValue(spinbox:getMaximum())
            spinbox.firstEdit = false
        end
    end
    g_keyboard.bindKeyPress('Up', function()
        check()
        spinbox:upSpin()
    end, spinbox)
    g_keyboard.bindKeyPress('Down', function()
        check()
        spinbox:downSpin()
    end, spinbox)
    g_keyboard.bindKeyPress('Right', function()
        check()
        spinbox:upSpin()
    end, spinbox)
    g_keyboard.bindKeyPress('Left', function()
        check()
        spinbox:downSpin()
    end, spinbox)
    g_keyboard.bindKeyPress('PageUp', function()
        check()
        spinbox:setValue(spinbox:getValue() + 10)
    end, spinbox)
    g_keyboard.bindKeyPress('PageDown', function()
        check()
        spinbox:setValue(spinbox:getValue() - 10)
    end, spinbox)

    scrollbar.onValueChange = function(self, value)
        itembox:setItemCount(value)
        spinbox.onValueChange = nil
        spinbox:setValue(value)
        spinbox.onValueChange = spinBoxValueChange
    end

    local moveFunc = function()
        local chosen = itembox:getItemCount()
        -- update local preview immediately
        if tradeWindow then
            local ownContainer = tradeWindow:recursiveGetChildById('ownTradeContainer')
            local slotWidget = ownContainer and ownContainer:recursiveGetChildById('ownSlot' .. slotIndex) or nil
            if slotWidget then
                local virtualItem = Item.create(item:getId())
                virtualItem:setCount(chosen)
                slotWidget:setItem(virtualItem)
                ItemsDatabase.setTier(slotWidget, virtualItem)
            end
        end
        local sendSlot = (slotIndex or 1) - 1
        print(string.format('[playertrade] send AddItem (prompt): slot0=%d itemId=%d count=%d', sendSlot, item:getId(), chosen))
        g_game.tradeWindowAddItem(sendSlot, item:getId(), chosen)
        okButton:getParent():destroy()
        countWindow = nil
    end
    local cancelFunc = function()
        cancelButton:getParent():destroy()
        countWindow = nil
    end

    countWindow.onEnter = moveFunc
    countWindow.onEscape = cancelFunc
    okButton.onClick = moveFunc
    cancelButton.onClick = cancelFunc
end

function onOpenTradeWindow(otherName, slotCount)
    ensureWindow()

    -- Reset slots visibility and items
    local ownContainer = tradeWindow:recursiveGetChildById('ownTradeContainer')
    local counterContainer = tradeWindow:recursiveGetChildById('counterTradeContainer')
    -- Evita interceptação de drop pelos containers: deixa o slot ser o alvo
    if ownContainer then ownContainer:setPhantom(true) end
    if counterContainer then counterContainer:setPhantom(true) end

    for i = 1, MAX_TRADE_SLOTS do
        local ownSlot = ownContainer:recursiveGetChildById('ownSlot' .. i)
        local counterSlot = counterContainer:recursiveGetChildById('counterSlot' .. i)
        if ownSlot then
            -- Ensure slot is an active drop target (do not mark as draggable)
            ownSlot:setVisible(i <= (slotCount or MAX_TRADE_SLOTS))
            ownSlot:setItem(nil)
            if ownSlot.setDraggable then ownSlot:setDraggable(false) end
            -- Some themes require focusable to receive hover/drag visuals consistently
            if ownSlot.setFocusable then ownSlot:setFocusable(true) end
            ownSlot.onClick = function()
                g_game.inspectTrade(false, i)
            end
            -- Accept drop from inventory/container items to add à nossa oferta
            ownSlot.onDragEnter = function(mousePos)
                local dragging = g_ui.getDraggingWidget()
                local thing = dragging and (dragging.currentDragThing or (dragging.getClassName and dragging:getClassName() == 'UIItem' and dragging.getItem and dragging:getItem()))
                if thing and thing.isItem and thing:isItem() then
                    ownSlot:setBorderWidth(1)
                    local cls = dragging and dragging.getClassName and dragging:getClassName() or 'unknown'
                    print(string.format('[playertrade] onDragEnter: slot=%d class=%s itemId=%s', i, cls, tostring(thing:getId())))
                    return true
                end
                print(string.format('[playertrade] onDragEnter: slot=%d rejected (no valid item)', i))
                return false
            end
            ownSlot.onDragLeave = function(droppedWidget, mousePos)
                ownSlot:setBorderWidth(0)
                print(string.format('[playertrade] onDragLeave: slot=%d', i))
                return true
            end
            ownSlot.onDrop = function(_, mousePos)
                ownSlot:setBorderWidth(0)
                -- Em algumas versões, o primeiro parâmetro pode não ser o widget arrastado; use fallback
                local dragging = g_ui.getDraggingWidget()
                local item = dragging and (dragging.currentDragThing or (dragging.getClassName and dragging:getClassName() == 'UIItem' and dragging.getItem and dragging:getItem()))
                -- Fallback absoluto: usar g_ui.draggedThing exposto por UIItem/UIGameMap
                if not item and g_ui.draggedThing then
                    item = g_ui.draggedThing
                end
                if not item or not item.isItem or not item:isItem() then
                    local cls = dragging and dragging.getClassName and dragging:getClassName() or 'unknown'
                    print(string.format('[playertrade] onDrop: slot=%d rejected (no item) class=%s', i, cls))
                    return false
                end
                local itemId = item:getId()
                local count = (item.getCount and item:getCount()) or 1
                if not count or count <= 0 then
                    print(string.format('[playertrade] onDrop: slot=%d itemId=%d count=%d (adjust -> 1)', i, itemId, count or -1))
                    count = 1
                end
                print(string.format('[playertrade] onDrop: slot=%d itemId=%d count=%d', i, itemId, count))
                -- Criar item virtual com mesmo id e quantidade do arraste (como no stash)
                local virtualItem = Item.create(itemId)
                virtualItem:setCount(count)
                ownSlot:setItem(virtualItem)
                ItemsDatabase.setTier(ownSlot, virtualItem)
                local sendSlot = (i or 1) - 1
                print(string.format('[playertrade] send AddItem (drop): slot0=%d itemId=%d count=%d', sendSlot, itemId, count))
                g_game.tradeWindowAddItem(sendSlot, itemId, count)
                return true
            end
            ownSlot.onMouseRelease = function(mousePos, mouseButton)
                if mouseButton == MouseRightButton then
                    local sendSlot = (i or 1) - 1
                    print(string.format('[playertrade] onMouseRelease: right-click remove slot=%d (slot0=%d)', i, sendSlot))
                    g_game.tradeWindowRemoveItem(sendSlot)
                    return true
                end
                return false
            end
        end
        if counterSlot then
            counterSlot:setVisible(i <= (slotCount or MAX_TRADE_SLOTS))
            counterSlot:setItem(nil)
            counterSlot.onClick = function()
                g_game.inspectTrade(true, i)
            end
            -- Disallow dropping onto counter side
            counterSlot.onDragEnter = function() return false end
            counterSlot.onDrop = function() return false end
        end
    end

    local ownLabel = tradeWindow:recursiveGetChildById('ownTradeLabel')
    local counterLabel = tradeWindow:recursiveGetChildById('counterTradeLabel')
    ownLabel:setText(tr('You'))
    counterLabel:setText(otherName)
    print(string.format('[playertrade] onOpenTradeWindow: other="%s" slots=%d', otherName, slotCount or MAX_TRADE_SLOTS))

    -- Clear accept state
    local acceptButton = tradeWindow:recursiveGetChildById('acceptButton')
    acceptButton:setEnabled(false)
    ownAccepted = false
end

function onTradeItemAdd(playerSide, slot, itemId, count)
    ensureWindow()

    -- playerSide comes as boolean from C++: true = own, false = other
    -- Keep backward-compat if it ever arrives as number (1/0)
    local isOther = (type(playerSide) == 'boolean') and (not playerSide) or (playerSide == 1)
    local uiIndex0 = (slot or 0)            -- assume server might send 0-based
    local uiIndex1 = uiIndex0 + 1           -- UI ids are 1-based
    local container = tradeWindow:recursiveGetChildById(isOther and 'counterTradeContainer' or 'ownTradeContainer')
    local prefix = isOther and 'counterSlot' or 'ownSlot'
    local slotWidget = container:recursiveGetChildById(prefix .. uiIndex1) or container:recursiveGetChildById(prefix .. uiIndex0)
    local resolvedUiIndex = slotWidget and tonumber(slotWidget:getId():match('%d+')) or uiIndex1
    if not slotWidget then
        print(string.format('[playertrade] onTradeItemAdd: missing widget for side=%s slot=%d (try ui=%d or %d)', isOther and 'counter' or 'own', slot or -1, uiIndex1, uiIndex0))
        return
    end

    local item = Item.create(itemId)
    item:setCount(count)
    slotWidget:setItem(item)
    ItemsDatabase.setTier(slotWidget, item)
    slotWidget.onClick = function()
        -- Inspect the opposite side for details
        g_game.inspectTrade(not isOther, slot)
    end
    print(string.format('[playertrade] onTradeItemAdd: side=%s slot=%d (ui=%d) itemId=%d count=%d', isOther and 'counter' or 'own', slot, resolvedUiIndex, itemId, count))
    updateAcceptEnabled()
end

function onTradeItemRemove(playerSide, slot)
    if not tradeWindow then return end
    local isOther = (type(playerSide) == 'boolean') and (not playerSide) or (playerSide == 1)
    local uiIndex0 = (slot or 0)
    local uiIndex1 = uiIndex0 + 1
    local container = tradeWindow:recursiveGetChildById(isOther and 'counterTradeContainer' or 'ownTradeContainer')
    local prefix = isOther and 'counterSlot' or 'ownSlot'
    local slotWidget = container:recursiveGetChildById(prefix .. uiIndex1) or container:recursiveGetChildById(prefix .. uiIndex0)
    if slotWidget then
        slotWidget:setItem(nil)
    else
        print(string.format('[playertrade] onTradeItemRemove: missing widget for side=%s slot=%d (try ui=%d or %d)', isOther and 'counter' or 'own', slot or -1, uiIndex1, uiIndex0))
    end
    local resolvedUiIndex = slotWidget and tonumber(slotWidget:getId():match('%d+')) or uiIndex1
    print(string.format('[playertrade] onTradeItemRemove: side=%s slot=%d (ui=%d)', isOther and 'counter' or 'own', slot, resolvedUiIndex))
    updateAcceptEnabled()
end

function onTradeAcceptChange(playerSide, accepted)
    if not tradeWindow then return end
    local acceptButton = tradeWindow:recursiveGetChildById('acceptButton')
    local isOwn = (type(playerSide) == 'boolean') and playerSide or (playerSide == 0)
    -- Quando nós aceitamos, desabilitar o botão; quando não, manter habilitado para permitir aceitar
    if isOwn then
        ownAccepted = accepted and true or false
        updateAcceptEnabled()
    end
    print(string.format('[playertrade] onTradeAcceptChange: side=%s accepted=%s', isOwn and 'own' or 'counter', tostring(accepted)))
end

function onCloseTradeWindow()
    if tradeWindow then
        tradeWindow:destroy()
        tradeWindow = nil
    end
    print('[playertrade] onCloseTradeWindow: window destroyed')
end

-- Expose manual opening to interface: open an empty trade window for a player
function openEmptyTradeWindow(otherName, slotCount)
    -- Garantir estilo e janela antes de abrir
    g_ui.importStyle('tradewindow')
    onOpenTradeWindow(otherName, slotCount or MAX_TRADE_SLOTS)
    if tradeWindow then
        tradeWindow:show()
        tradeWindow:raise()
        tradeWindow:focus()
    end
end
