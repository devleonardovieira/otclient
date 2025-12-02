-- chunkname: @/modules/client_textedit/textedit.lua

local activeWindow

function init()
	g_ui.importStyle("textedit")
	connect(g_game, {
		onGameEnd = destroyWindow
	})
end

function terminate()
	disconnect(g_game, {
		onGameEnd = destroyWindow
	})
	destroyWindow()
end

function destroyWindow()
	if activeWindow then
		activeWindow:destroy()

		activeWindow = nil
	end
end

function show(text, options, callback)
	if type(text) == "userdata" then
		local widget = text

		function callback(newText)
			widget:setText(newText)
		end

		text = widget:getText()
	elseif type(text) == "number" then
		text = tostring(text)
	elseif type(text) == "nil" then
		text = ""
	elseif type(text) ~= "string" then
		return error("Invalid text type for client_textedit: " .. type(text))
	end

	if type(options) == "function" then
		local tmp = callback

		callback = options
		options = callback
	end

	options = options or {}

	if activeWindow then
		destroyWindow()
	end

	local window

	if options.multiline then
		window = g_ui.createWidget("MultilineTextEditWindow", rootWidget)
		window.text = window.textPanel.text
	else
		window = g_ui.createWidget("SinglelineTextEditWindow", rootWidget)
	end

	g_effects.moveToMargin(window, MarginBottom, 0, 30, 140, Easing.easeOutBack, function()
		g_effects.moveToMargin(window, MarginBottom, 30, 0, 120, Easing.easeOutBack)
	end)

	local function validate(widget, text)
		if type(options.range) == "table" then
			local value = tonumber(text)

			return value >= options.range[1] and value <= options.range[2]
		elseif type(options.validation) == "function" then
			return options.validation(widget)
		end

		return true
	end

	local function destroy()
		window:destroy()
	end

	local function doneFunc()
		local text = window.text:getText()

		if not validate(window.text, text) then
			return
		end

		destroy()

		if callback then
			callback(text)
		end
	end

	window.buttons.ok.onClick = doneFunc
	window.buttons.cancel.onClick = destroy

	if not options.multiline then
		window.onEnter = doneFunc
	end

	window.onEscape = destroy

	function window.onDestroy()
		if window == activeWindow then
			activeWindow = nil
		end
	end

	if options.title then
		window:setText(options.title)
	end

	if options.description then
		window.description:show()
		window.description:setMultiColorText(options.description)
	end

	if type(options.examples) == "table" and #options.examples > 0 then
		window.examples:show()

		for i, title_text in ipairs(options.examples) do
			window.examples:addOption(title_text[1], title_text[2])
		end

		function window.examples.onOptionChange(widget, option, data)
			window.text:setText(data)
			window.text:setCursorPos(-1)
		end
	end

	window.text:setText(text)
	window.text:setCursorPos(-1)

	function window.text.onTextChange(widget, text)
		if validate(widget, text) and g_platform.isMobile() then
			doneFunc()
		end
	end

	if type(options.width) == "number" then
		window:setWidth(options.width)
	end

	activeWindow = window

	activeWindow:raise()
	activeWindow:focus()

	if g_platform.isMobile() then
		window.text:focus()

		local flags = 0

		if options.multiline then
			flags = 1
		end

		g_window.showTextEditor(window:getText(), window.description:getText(), window.text:getText(), flags)
	end

	return activeWindow
end

function hide()
	destroyWindow()
end

function edit(...)
	return show(...)
end

function singlelineEditor(text, callback)
	return show(text, {}, callback)
end

function multilineEditor(description, text, callback)
	return show(text, {
		multiline = true,
		description = description
	}, callback)
end
