-- chunkname: @/modules/corelib/inputvalidation.lua

function isRequired(text)
	return text:trim():len() > 0
end

function isValidEmail(email)
	return email:match("[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+%.[a-zA-Z]+") ~= nil
end

function isValidAmount(amount, minimum, maximum)
	return tonumber(amount) and minimum <= tonumber(amount) and maximum >= tonumber(amount)
end

function isValidPassword(password)
	local validations = {
		{
			message = "A senha deve conter ao menos 1 letra min\xFAscula.",
			has = password:match("[%l]")
		},
		{
			message = "A senha deve conter ao menos 1 letra mai\xFAscula.",
			has = password:match("[%u]")
		},
		{
			message = "A senha deve conter ao menos 8 caracteres.",
			has = password:len() > 8
		},
		{
			message = "A senha deve conter ao menos 1 caracter especial.",
			has = password:match("[%p]")
		},
		{
			message = "A senha deve conter ao menos 1 numero.",
			has = password:match("%d")
		}
	}

	for i, value in pairs(validations) do
		if not value.has then
			return value.message
		end
	end

	return ""
end

function isValidCPF(cpf)
	cpf = cpf:gsub("[^%d]", "")

	if #cpf ~= 11 then
		return false
	end

	local allEqual = true
	local prevDigit = tonumber(cpf:sub(1, 1))

	for i = 2, 11 do
		local digit = tonumber(cpf:sub(i, i))

		if digit ~= prevDigit then
			allEqual = false

			break
		end
	end

	if allEqual then
		return false
	end

	local sum = 0

	for i = 1, 9 do
		sum = sum + tonumber(cpf:sub(i, i)) * (11 - i)
	end

	local remainder = sum * 10 % 11
	local digit1 = (remainder == 10 or remainder == 11) and 0 or remainder

	if tonumber(cpf:sub(10, 10)) ~= digit1 then
		return false
	end

	sum = 0

	for i = 1, 10 do
		sum = sum + tonumber(cpf:sub(i, i)) * (12 - i)
	end

	remainder = sum * 10 % 11

	local digit2 = (remainder == 10 or remainder == 11) and 0 or remainder

	if tonumber(cpf:sub(11, 11)) ~= digit2 then
		return false
	end

	return true
end

function isValidName(name, minLength, maxLength)
	local minimum = minLength or 5
	local maximum = maxLength or 14
	local invalidChars = "{}|_*+-=<>0123456789@#%^&()/*'\\.,:;~!\"$"

	if minimum > #name or maximum < #name then
		return ("O comprimento do nome deve estar entre %d e %d caracteres."):format(minimum, maximum)
	end

	if name:find("%s%s") then
		return "O nome n\xE3o pode conter mais de um espa\xE7o em branco consecutivo."
	end

	if name == name:upper() then
		return "O nome n\xE3o pode estar todo em letras mai\xFAsculas."
	end

	if name:find("^%s") or name:find("%s$") then
		return "O nome n\xE3o pode ter espa\xE7os em branco no in\xEDcio ou no final."
	end

	for caracter in invalidChars:gmatch(".") do
		local escapedChar = caracter:match("[%p]") and "%" .. caracter or caracter

		if name:find(escapedChar) then
			return "O nome cont\xE9m caracteres inv\xE1lidos: " .. caracter
		end
	end

	if name:find("[^%w%s]") then
		return "O nome n\xE3o pode conter acentua\xE7\xF5es ou caracteres especiais."
	end

	for part in name:gmatch("%S+") do
		if not part:find("^[A-Z]") then
			return "Cada parte do nome deve come\xE7ar com uma letra mai\xFAscula."
		end
	end

	return ""
end

function onInputError(input, message)
	input:setHelperText("#F83930", message)

	return false
end

function onInputSuccess(input, message)
	if message and message:trim():len() > 0 then
		input:setHelperText("#6DFFB0", message)
	else
		input:setHelperText("#000000", "")
	end

	return true
end

function onInputRequired(input)
	local isValid = isRequired(input:getText())

	if not isValid then
		onInputError(input, "Preencha este campo.")
	end

	return isValid
end

function onInputEmail(input)
    if onInputRequired(input) then
        return isValidEmail(input:getText()) and onInputSuccess(input) or onInputError(input, "E-mail n\xE3o \xE9 v\xE1lido.")
    end

    return false
end

function onInputAmount(input, minimum, maximum)
	if onInputRequired(input) then
		return isValidAmount(input:getText(), minimum, maximum) and onInputSuccess(input) or onInputError(input, tr("O valor deve estar entre %d \xE0 %d", minimum, maximum))
	end

	return false
end

function onInputPassword(input)
    if onInputRequired(input) then
        local strValidPassword = isValidPassword(input:getText())

        if strValidPassword:len() > 0 then
            return onInputError(input, strValidPassword)
        else
            return onInputSuccess(input)
        end
    end

    return false
end

function onInputCPF(input)
	if onInputRequired(input) then
		return isValidCPF(input:getText()) and onInputSuccess(input) or onInputError(input, "CPF inv\xE1lido.")
	end

	return false
end

function onInputName(input)
	if onInputRequired(input) then
		local strValidName = isValidName(input:getText())

		if strValidName:len() > 0 then
			return onInputError(input, strValidName)
		end

		return onInputSuccess(input)
	end

	return false
end

function onInputConfirmPassword(inputPassword, inputConfirm)
    local password = inputPassword:getText()
    local confirm = inputConfirm:getText()

    if password ~= confirm then
        return onInputError(inputConfirm, "Essa senha n\xE3o \xE9 a mesma.")
    end

    return onInputSuccess(inputConfirm)
end

function onInputConfirmEmail(inputEmail, inputConfirm)
    local email = inputEmail:getText()
    local confirm = inputConfirm:getText()

    if email ~= confirm then
        return onInputError(inputConfirm, "O e-mail n\xE3o \xE9 o mesmo.")
    end

    return onInputSuccess(inputConfirm)
end
