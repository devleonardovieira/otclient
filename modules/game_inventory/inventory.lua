-- chunkname: @/modules/game_inventory/inventory.lua

local inventoryWindow

InventoryHotkeyList = {}

function registerInventoryHotkey(hotkeyName, keyCombo, callback)
	local function bindCallback()
		if g_game.isOnline() and (g_keyboard.isChatEnabled() or g_keyboard.hasTextEditChange()) then
			return
		end

		callback()
	end

	InventoryHotkeyList[hotkeyName] = {
		keyCombo = keyCombo,
		callback = bindCallback
	}

	g_keyboard.bindHotkeyPress(keyCombo, bindCallback, gameRootPanel, "Action Bar")
end

function unregisterInventoryHotkey(hotkeyName)
	local hotkey = InventoryHotkeyList[hotkeyName]

	if hotkey then
		g_keyboard.unbindHotkeyPress(hotkey.keyCombo, hotkey.callback, gameRootPanel)
	end
end

function updateInventoryHotkey(hotkeyName, keyCombo)
	local hotkey = InventoryHotkeyList[hotkeyName]

	if hotkey then
		unregisterInventoryHotkey(hotkeyName)
		registerInventoryHotkey(hotkeyName, keyCombo, hotkey.callback)
	end
end

function getInventoryHotkeys()
	return InventoryHotkeyList
end

registerInventoryHotkey("pokedex", "Shift+D", function()
	g_game.getLocalPlayer():doUsePokedex()
end)
registerInventoryHotkey("fishing", "Shift+F", function()
	g_game.getLocalPlayer():doUseFishing()
end)
registerInventoryHotkey("pokebag", "Shift+I", function()
	g_game.getLocalPlayer():doUsePokeBag()
end)
registerInventoryHotkey("autoloot", "Shift+E", function()
	g_game.getLocalPlayer():doUseAutoLoot()
end)
registerInventoryHotkey("order", "Shift+R", function()
	g_game.getLocalPlayer():doUseOrder()
end)

function init()
    connect(g_game, {
        onGameStart = online,
        onGameEnd = offline
    })

    -- Carrega a MiniWindow diretamente no RootPanel para evitar problemas de container lateral
    inventoryWindow = g_ui.loadUI("inventory", modules.game_interface.getRootPanel())

    inventoryWindow:setup()
    -- Atalho de teclado para abrir/fechar o inventário
    g_keyboard.bindKeyDown("Ctrl+I", toggle)
end

function terminate()
    disconnect(g_game, {
        onGameStart = online,
        onGameEnd = offline
    })

	for hotkeyName, v in pairs(InventoryHotkeyList) do
		unregisterInventoryHotkey(hotkeyName)
	end

    inventoryWindow:destroy()

    inventoryWindow = nil
    g_keyboard.unbindKeyDown("Ctrl+I")
end

function online()
	local inventoryHotkeys = g_settings.getNode("inventoryHotkeys") or {}

	for hotkeyName, keyCombo in pairs(inventoryHotkeys) do
		local callback = InventoryHotkeyList[hotkeyName] and InventoryHotkeyList[hotkeyName].callback or function()
			return
		end

		unregisterInventoryHotkey(hotkeyName)
		registerInventoryHotkey(hotkeyName, keyCombo, callback)
	end
end

function offline()
	local inventoryHotkeys = {}

	for hotkeyName, v in pairs(InventoryHotkeyList) do
		inventoryHotkeys[hotkeyName] = v.keyCombo

		unregisterInventoryHotkey(hotkeyName)
	end

	g_settings.setNode("inventoryHotkeys", inventoryHotkeys)
end

function getInventoryWindow()
    return inventoryWindow
end

function toggle()
    if not inventoryWindow or inventoryWindow:isDestroyed() then
        -- Recria a miniwindow no RootPanel para preservar posição absoluta ao abrir/fechar
        inventoryWindow = g_ui.loadUI("inventory", modules.game_interface.getRootPanel())
        inventoryWindow:setup()
    end

    -- MiniWindow deve usar open/close para persistir estado e integrar com containers
    if not inventoryWindow:isExplicitlyVisible() then
        inventoryWindow:open()
        inventoryWindow:raise()
    else
        inventoryWindow:close()
    end
end
