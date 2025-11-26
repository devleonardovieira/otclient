-- chunkname: @/modules/game_api/api.lua

Api = {}
Api.__index = Api
Accounts = {}
Accounts.__index = Accounts
Pix = {}
Pix.__index = Pix

function Api.new()
	local data = {}

	setmetatable(data, Api)

	return data
end

function Api:send(url, data, callback)
	if not data.bearer then
		data.bearer = G.sessionKey
	end

	return HTTP.postJSON(G.host .. url, data, callback)
end

function Api:get(url, callback)
	if G.sessionKey then
		g_http.setAuthorization("Bearer " .. G.sessionKey)
	end

	return HTTP.getJSON(G.host .. url, callback)
end

local api = Api.new()

function Accounts.new()
	local data = {}

	setmetatable(data, Accounts)

	return data
end

function Accounts:active(code, callback)
	local data = {
		key = code
	}

	return api:send(API.ACTIVATION.CODE, data, callback)
end

function Accounts:sendCodeEmail(callback)
	local data = {}

	return api:send(API.ACTIVATION.SEND_EMAIL, data, callback)
end

function Accounts:changeEmail(email, callback)
	local data = {
		newEmail = email
	}

	return api:send(API.EMAIL.CHANGE, data, callback)
end

function Accounts:cancelChangeEmail(callback)
	local data = {}

	return api:send(API.EMAIL.CHANGE_CANCEL, data, callback)
end

function Accounts:create(email, password, callback)
	local data = {
		email = email,
		password = password,
		bearer = API_KEY[G.host]
	}

	return api:send(API.ACCOUNTS.CREATE, data, callback)
end

function Accounts:createCharacter(name, gender, worldId, callback)
	local data = {
		name = name,
		sex = gender,
		worldId = worldId
	}

	return api:send(API.CHARACTERS.CREATE, data, callback)
end

function Accounts:getCharacters(callback)
	return api:get(API.CHARACTERS.GET, callback)
end

function Accounts:deleteCharacter(name, callback)
	local data = {
		name = name
	}

	return api:send(API.CHARACTERS.DELETE, data, callback)
end

function Accounts:cancelDeleteCharacter(name, callback)
	local data = {
		name = name
	}

	return api:send(API.CHARACTERS.DELETE_CANCEL, data, callback)
end

function Accounts:changePassword(oldPassword, newPassword, repeatPassword, callback)
	local data = {
		oldPassword = oldPassword,
		newPassword = newPassword,
		newPasswordRepeated = repeatPassword
	}

	return api:send(API.PASSWORD.CHANGE, data, callback)
end

function Accounts:recoverCodeEmail(email, callback)
	local data = {
		email = email,
		bearer = API_KEY[G.host]
	}

	return api:send(API.PASSWORD.SEND_RECOVER_CODE, data, callback)
end

function Accounts:changeRecoverPassword(email, code, newPassword, repeatPassword, callback)
	local data = {
		email = email,
		recoverCode = code,
		newPassword = newPassword,
		newPasswordRepeated = repeatPassword,
		bearer = API_KEY[G.host]
	}

	return api:send(API.PASSWORD.RECOVER, data, callback)
end

function Pix.new()
	local data = {}

	setmetatable(data, Pix)

	return data
end

function Pix:donate(cpf, amount, callback)
	local data = {
		cpf = cpf,
		amount = amount
	}

	return api:send(API.PIX.DONATE, data, callback)
end
