-- chunkname: @/modules/game_dialog/protocol.lua

local PokemonDialogOpcode = 84
local Actions = {
	Close = 2,
	Create = 1
}

local function parseOpen(params)
	signalcall(Dialog.onOpen, params)
end

local function parseClose()
	signalcall(Dialog.onClose)
end

local ActionParser = {
	[Actions.Create] = parseOpen,
	[Actions.Close] = parseClose
}

local function parseAction(protocol, opcode, jsonData)
	local parser = ActionParser[jsonData.action]

	if parser then
		parser(jsonData.data)
	end
end

function initProtocol()
	ProtocolGame.registerExtendedJSONOpcode(PokemonDialogOpcode, parseAction)
end

function terminateProtocol()
	ProtocolGame.unregisterExtendedJSONOpcode(PokemonDialogOpcode)
end
