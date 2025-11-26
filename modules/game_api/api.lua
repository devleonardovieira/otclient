-- chunkname: @/modules/game_api/api.lua

Api = {}
Api.__index = Api
Accounts = {}
Accounts.__index = Accounts
Pix = {}
Pix.__index = Pix

-- Derive base host and login.php path from Servers_init (HTTP login configuration)
local SITE_API_PATH = "/login.php"
local function deriveHostAndPath()
    if G and G.host then
        -- host already set elsewhere; try to keep it
    end
    if Servers_init then
        for hostWithPath, cfg in pairs(Servers_init) do
            if type(hostWithPath) == 'string' and cfg and cfg.httpLogin then
                local base, path = hostWithPath:match("^(https?://[^/]+)(/.*)$")
                if base and path then
                    G = G or {}
                    G.host = base
                    SITE_API_PATH = path
                    return
                end
            end
        end
    end
    -- Fallbacks: keep defaults
    G = G or {}
    G.host = G.host or "http://127.0.0.1"
    SITE_API_PATH = SITE_API_PATH or "/login.php"
end
deriveHostAndPath()

-- Minimal lifecycle so @onLoad/@onUnload work without errors
function init()
    -- No-op: module environment is exposed as modules.game_api automatically
end

function terminate()
    -- No-op
end

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

-- Compatibility helpers for site API in api/login.php
function Api:sendSite(action, payload, callback)
    local data = payload or {}
    data.type = action
    if data.stayloggedin == nil then
        data.stayloggedin = true
    end
    return HTTP.postJSON(G.host .. SITE_API_PATH, data, callback)
end

function Accounts.new()
    local data = {}

    setmetatable(data, Accounts)

    return data
end

-- Site API wrappers (login.php actions)
function Accounts:login(email, password, token, callback)
    local data = {
        email = email,
        password = password,
    }
    if token then data.token = token end
    return api:sendSite('login', data, callback)
end

function Accounts:cacheinfo(callback)
    return api:sendSite('cacheinfo', {}, callback)
end

function Accounts:eventschedule(callback)
    return api:sendSite('eventschedule', {}, callback)
end

function Accounts:boostedcreature(callback)
    return api:sendSite('boostedcreature', {}, callback)
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
        password = password
    }
    -- Use site API: /login.php with type=register
    return api:sendSite('register', data, callback)
end

function Accounts:createCharacter(name, gender, worldId, callback)
	local data = {
		name = name,
		sex = gender,
		worldId = worldId,
		-- authenticate via site API using current login credentials
		email = G and G.account or nil,
		password = G and G.password or nil
	}

	-- Use site API endpoint in /login.php
	return api:sendSite('createCharacter', data, callback)
end

-- Real-time validation endpoints (site API)
function Accounts:validateRegister(payload, callback)
    -- payload can include: email, confirmEmail, password, confirmPassword, termsAccepted
    return api:sendSite('validateRegister', payload or {}, callback)
end

function Accounts:validateCharacter(name, callback)
    local data = { name = name }
    return api:sendSite('validateCharacter', data, callback)
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
