-- chunkname: @/modules/corelib/keybind.lua

KEYCOMBO_PRIMARY = 1
KEYCOMBO_SECONDARY = 2
KB_PROFILES_PATH = "/profiles/keybinds/"
KB_CATEGORY_LOAD_ORDER = {
	"Pokemon",
	"Golpes"
}
KB_CALLBACKS = {
	["Chamar 1"] = function()
		modules.game_pokebar.doCallPokemon(1)
	end,
	["Chamar 2"] = function()
		modules.game_pokebar.doCallPokemon(2)
	end,
	["Chamar 3"] = function()
		modules.game_pokebar.doCallPokemon(3)
	end,
	["Chamar 4"] = function()
		modules.game_pokebar.doCallPokemon(4)
	end,
	["Chamar 5"] = function()
		modules.game_pokebar.doCallPokemon(5)
	end,
	["Chamar 6"] = function()
		modules.game_pokebar.doCallPokemon(6)
	end,
	["Ficar Parado"] = function()
		g_game.talkChannel(MessageModes.None, 0, ".h")
	end,
	["Ordernar Pokemon"] = function()
		g_game.getLocalPlayer():doUseOrder()
	end,
	["Ordernar Pokemon em si"] = function()
		g_game.getLocalPlayer():doUseSelfOrder()
	end,
	["Usar 1"] = function()
		modules.game_pokemoves.doUseSkill(1)
	end,
	["Usar 2"] = function()
		modules.game_pokemoves.doUseSkill(2)
	end,
	["Usar 3"] = function()
		modules.game_pokemoves.doUseSkill(3)
	end,
	["Usar 4"] = function()
		modules.game_pokemoves.doUseSkill(4)
	end,
	["Usar 5"] = function()
		modules.game_pokemoves.doUseSkill(5)
	end,
	["Usar 6"] = function()
		modules.game_pokemoves.doUseSkill(6)
	end,
	["Usar 7"] = function()
		modules.game_pokemoves.doUseSkill(7)
	end,
	["Usar 8"] = function()
		modules.game_pokemoves.doUseSkill(8)
	end,
	["Usar 9"] = function()
		modules.game_pokemoves.doUseSkill(9)
	end,
	["Usar 10"] = function()
		modules.game_pokemoves.doUseSkill(10)
	end,
	["Usar 11"] = function()
		modules.game_pokemoves.doUseSkill(11)
	end,
	["Usar 12"] = function()
		modules.game_pokemoves.doUseSkill(12)
	end
}
KB_DEFAULTS = {
	Pokemon = {
		content = {
			{
				keyCombo = "Ctrl+1",
				name = "Chamar 1",
				altKeyCombo = "Ctrl+F1",
				callback = "Chamar 1"
			},
			{
				keyCombo = "Ctrl+2",
				name = "Chamar 2",
				altKeyCombo = "Ctrl+F2",
				callback = "Chamar 2"
			},
			{
				keyCombo = "Ctrl+3",
				name = "Chamar 3",
				altKeyCombo = "Ctrl+F3",
				callback = "Chamar 3"
			},
			{
				keyCombo = "Ctrl+4",
				name = "Chamar 4",
				altKeyCombo = "Ctrl+F4",
				callback = "Chamar 4"
			},
			{
				keyCombo = "Ctrl+5",
				name = "Chamar 5",
				altKeyCombo = "Ctrl+F5",
				callback = "Chamar 5"
			},
			{
				keyCombo = "Ctrl+6",
				name = "Chamar 6",
				altKeyCombo = "Ctrl+F6",
				callback = "Chamar 6"
			},
			{
				keyCombo = "Shift+S",
				name = "Ficar Parado",
				altKeyCombo = "<none>",
				callback = "Ficar Parado"
			},
			{
				keyCombo = "Mouse Middle",
				name = "Ordernar Pokemon",
				altKeyCombo = "<none>",
				callback = "Ordernar Pokemon"
			},
			{
				keyCombo = "<none>",
				name = "Ordernar Pokemon em si mesmo(a)",
				altKeyCombo = "<none>",
				callback = "Ordernar Pokemon em si"
			}
		}
	},
	Golpes = {
		content = {
			{
				keyCombo = "F1",
				name = "Usar 1",
				altKeyCombo = "1",
				callback = "Usar 1"
			},
			{
				keyCombo = "F2",
				name = "Usar 2",
				altKeyCombo = "2",
				callback = "Usar 2"
			},
			{
				keyCombo = "F3",
				name = "Usar 3",
				altKeyCombo = "3",
				callback = "Usar 3"
			},
			{
				keyCombo = "F4",
				name = "Usar 4",
				altKeyCombo = "4",
				callback = "Usar 4"
			},
			{
				keyCombo = "F5",
				name = "Usar 5",
				altKeyCombo = "5",
				callback = "Usar 5"
			},
			{
				keyCombo = "F6",
				name = "Usar 6",
				altKeyCombo = "6",
				callback = "Usar 6"
			},
			{
				keyCombo = "F7",
				name = "Usar 7",
				altKeyCombo = "7",
				callback = "Usar 7"
			},
			{
				keyCombo = "F8",
				name = "Usar 8",
				altKeyCombo = "8",
				callback = "Usar 8"
			},
			{
				keyCombo = "F9",
				name = "Usar 9",
				altKeyCombo = "9",
				callback = "Usar 9"
			},
			{
				keyCombo = "F10",
				name = "Usar 10",
				altKeyCombo = "0",
				callback = "Usar 10"
			},
			{
				keyCombo = "F11",
				name = "Usar 11",
				altKeyCombo = "-",
				callback = "Usar 11"
			},
			{
				keyCombo = "F12",
				name = "Usar 12",
				altKeyCombo = "=",
				callback = "Usar 12"
			}
		}
	}
}

 
