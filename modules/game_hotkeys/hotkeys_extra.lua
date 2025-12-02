-- chunkname: @/modules/game_hotkeys/hotkeys_extra.lua

extraHotkeys = {}

function addExtraHotkey(name, description, callback)
	table.insert(extraHotkeys, {
		name = name:lower(),
		description = tr(description),
		callback = callback
	})
end

function setupExtraHotkeys(combobox)
	addExtraHotkey("none", "None", nil)
	addExtraHotkey("cancelAttack", "Stop attacking", function(repeated)
		if not repeated then
			g_game.attack(nil)
		end
	end)
	addExtraHotkey("attackNext", "Attack next target from battle list", function(repeated)
		if repeated or not modules.game_battle then
			return
		end

		local battlePanel = modules.game_battle.battlePanel
		local attackedCreature = g_game.getAttackingCreature()
		local nextChild
		local breakNext = false

		for i, child in ipairs(battlePanel:getChildren()) do
			if child.creature and child:isOn() and not child.creature:isSummon() and not child.creature:isOtherSummon() and not not child.creature:isMonster() then
				if breakNext then
					nextChild = child

					break
				end

				if child.creature == attackedCreature then
					breakNext = true
				end
			end
		end

		if not nextChild then
			for i, child in ipairs(battlePanel:getChildren()) do
				if child.creature and child:isOn() and not child.creature:isSummon() and not child.creature:isOtherSummon() and not not child.creature:isMonster() then
					nextChild = child

					break
				end
			end
		end

		if nextChild and nextChild.creature ~= attackedCreature then
			g_game.attack(nextChild.creature)
		end
	end)
	addExtraHotkey("attackPrevious", "Attack previous target from battle list", function(repeated)
		if repeated or not modules.game_battle then
			return
		end

		local battlePanel = modules.game_battle.battlePanel
		local attackedCreature = g_game.getAttackingCreature()
		local prevChild

		for i, child in ipairs(battlePanel:getChildren()) do
			if not child.creature or not child:isOn() then
				break
			end

			if child.creature == attackedCreature then
				break
			end

			prevChild = child
		end

		if prevChild and prevChild.creature ~= attackedCreature then
			g_game.attack(prevChild.creature)
		end
	end)
	addExtraHotkey("toogleWsad", "Enable/disable wsad walking", function(repeated)
		if repeated or not modules.game_console then
			return
		end

		if not modules.game_console.consoleToggleChat:isChecked() then
			modules.game_console.disableChat(true)
		else
			modules.game_console.enableChat(true)
		end
	end)
	addExtraHotkey("autoWalk", "Enable/disable auto walk", function(repeated)
		if repeated or not modules.game_pokeinfo then
			return
		end

		modules.game_pokeinfo.autoWalkButton:setOn(not modules.game_pokeinfo.autoWalkButton:isOn())
		modules.game_pokeinfo.onAutoWalk()
	end)
	addExtraHotkey("order", "Order pok\xE9mon", function(repeated)
		if repeated then
			return
		end

		local player = g_game.getLocalPlayer()

		if player then
			player:doUseOrder()
		end
	end)

	for index, actionDetails in ipairs(extraHotkeys) do
		combobox:addOption(actionDetails.description)
	end
end

function executeExtraHotkey(action, repeated)
	action = action:lower()

	for index, actionDetails in ipairs(extraHotkeys) do
		if actionDetails.name == action and actionDetails.callback then
			actionDetails.callback(repeated)
		end
	end
end

function translateActionToActionComboboxIndex(action)
	action = action:lower()

	for index, actionDetails in ipairs(extraHotkeys) do
		if actionDetails.name == action then
			return index
		end
	end

	return 1
end

function translateActionComboboxIndexToAction(index)
	if index > 1 and index <= #extraHotkeys then
		return extraHotkeys[index].name
	end

	return nil
end

function getActionDescription(action)
	action = action:lower()

	for index, actionDetails in ipairs(extraHotkeys) do
		if actionDetails.name == action then
			return actionDetails.description
		end
	end

	return "invalid action"
end
