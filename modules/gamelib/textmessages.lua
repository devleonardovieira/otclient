local messageModeCallbacks = {}
local messageQueue = {}

function g_game.onTextMessage(messageMode, message)
    local callbacks = messageModeCallbacks[messageMode]
    if not callbacks or #callbacks == 0 then
        -- Sem handlers registrados ainda: enfileira para entrega posterior
        if not messageQueue[messageMode] then
            messageQueue[messageMode] = {}
        end
        table.insert(messageQueue[messageMode], message)
        return
    end

    for _, callback in pairs(callbacks) do
        callback(messageMode, message)
    end
end

function registerMessageMode(messageMode, callback)
    if not messageModeCallbacks[messageMode] then
        messageModeCallbacks[messageMode] = {}
    end

    table.insert(messageModeCallbacks[messageMode], callback)

    -- Assim que um handler é registrado, entrega mensagens pendentes daquele modo
    if messageQueue[messageMode] and #messageQueue[messageMode] > 0 then
        for _, queuedMessage in pairs(messageQueue[messageMode]) do
            callback(messageMode, queuedMessage)
        end
        messageQueue[messageMode] = nil
    end
    return true
end

function unregisterMessageMode(messageMode, callback)
    if not messageModeCallbacks[messageMode] then
        return false
    end

    return table.removevalue(messageModeCallbacks[messageMode], callback)
end
