-- chunkname: @/modules/game_dialog/dialog.lua

Dialog = {}

local pendingByNpc = {}
local suppressUntilStartBlock = false
local suppressNpcName = nil

local dialogWindow
local protocol = runinsandbox("protocol")

local function sanitizeNpcMessage(text)
  if not text then return '' end
  return text:gsub('[{}]', '')
end

local function extractKeywords(text)
  local opts = {}
  for word in string.gmatch(text or '', '{(.-)}') do
    for opt in string.gmatch(word, '[^|,;]+') do
      opt = opt:trim()
      opt = opt:gsub('^[`"%s]+', '')
      opt = opt:gsub('[`"%s%.,;:!?]+$', '')
      if opt ~= '' and not table.find(opts, opt) then
        table.insert(opts, opt)
      end
    end
  end
  if not table.find(opts, 'bye') then
    table.insert(opts, 'bye')
  end
  return opts
end

local function resize(height)
	if dialogWindow then
		local newHeight = dialogWindow:getPaddingTop() + dialogWindow:getPaddingBottom() + dialogWindow:getPaddingLeft() + dialogWindow:getPaddingRight() + height

		dialogWindow:resize(dialogWindow:getWidth(), newHeight)
	end
end

function addDialogOption(data)
	local keywords = data.keywords
	local pokemons = data.pokemons
	local items = data.items
	local height = 0

	dialogWindow.extra:setOn(pokemons or items)
	dialogWindow.extraScroll:setOn(pokemons or items)

	if keywords and #keywords > 0 then
		for i = 1, #keywords do
			local option = g_ui.createWidget("OptionDialog", dialogWindow.options)

			if i <= 3 then
				height = height + option:getHeight() + option:getMarginTop()
			end

			option:setMultiColorText(keywords[i])
		end

		dialogWindow.options.selectedWidget = dialogWindow.options:getFirstChild()

		dialogWindow.optionsScroll:setVisible(#keywords > 3)
	end

	if pokemons and #pokemons > 0 then
		for i = 1, #pokemons, 2 do
			local pokemon = g_ui.createWidget("PokemonDialog", dialogWindow.extra)

			pokemon:setTooltip(pokemons[i])
			pokemon:setOutfit(pokemons[i + 1])
		end
	end

	if items and #items > 0 then
		for i = 1, #items, 3 do
			local item = g_ui.createWidget("ItemDialog", dialogWindow.extra)
			local tmpItem = Item.create(items[i])

			tmpItem:setTooltip(tr("%s (%sx).", items[i + 2], items[i + 1]))
			item:setItem(tmpItem)
			item:setItemCount(items[i + 1])
		end
	end

	local newHeight = 36 + height + dialogWindow.extra:getHeight() + dialogWindow.extra:getMarginTop() + dialogWindow.extraScroll:getHeight() + dialogWindow.extraScroll:getMarginTop() + dialogWindow.message:getTextSize().height

	resize(newHeight)
end

local function onOpen(params)
	onDialogGameEnd()

	dialogWindow = g_ui.createWidget("DialogWindow", rootWidget)

	local creature = g_map.getCreatureById(params.cid)

	dialogWindow.title:setText(creature:getName())
	dialogWindow.message:setMultiColorText(params.message)
	resize(dialogWindow.message:getTextSize().height + 5)
	addDialogOption(params.options)
end

local function onClose()
  onDialogGameEnd()
end

local function openWindowFromTalk(name, message)
  onDialogGameEnd()
  dialogWindow = g_ui.createWidget("DialogWindow", rootWidget)
  dialogWindow.title:setText(name or "NPC")
  dialogWindow.message:setMultiColorText(sanitizeNpcMessage(message))

  local keywords = extractKeywords(message)
  addDialogOption({ keywords = keywords })

  ignoreNpcMessages = true
end

function onTalk(npcName, level, mode, message, channelId, creaturePos)
  if mode ~= MessageModes.NpcFrom and mode ~= MessageModes.NpcFromStartBlock then
    return
  end

  local hasOptions = (message and string.find(message, '{.-}')) ~= nil

  if suppressUntilStartBlock and npcName and suppressNpcName == npcName then
    if mode ~= MessageModes.NpcFromStartBlock then
      return
    else
      suppressUntilStartBlock = false
      suppressNpcName = nil
      if not hasOptions then
        return
      end
    end
  end

  if mode == MessageModes.NpcFromStartBlock then
    local combined = sanitizeNpcMessage(message)
    if pendingByNpc[npcName] and #pendingByNpc[npcName] > 0 then
      combined = pendingByNpc[npcName] .. "\n" .. combined
    end
    pendingByNpc[npcName] = nil
    openWindowFromTalk(npcName, combined)
    return
  end

  if dialogWindow then
    -- Append to current dialog if already open
    local current = dialogWindow.message:getText() or ''
    local sanitized = sanitizeNpcMessage(message)
    local combined = current ~= '' and (current .. "\n" .. sanitized) or sanitized
    dialogWindow.message:setMultiColorText(combined)
    return
  end

  if hasOptions then
    openWindowFromTalk(npcName, sanitizeNpcMessage(message))
  else
    pendingByNpc[npcName] = (pendingByNpc[npcName] and (pendingByNpc[npcName] .. "\n") or "") .. sanitizeNpcMessage(message)
  end
end

function init()
  protocol.initProtocol()
  connect(g_game, {
    onGameEnd = onDialogGameEnd,
    onTalk = onTalk
  })
  connect(Dialog, {
    onOpen = onOpen,
    onClose = onClose
  })
end

function terminate()
  protocol.terminateProtocol()
  disconnect(g_game, {
    onGameEnd = onDialogGameEnd,
    onTalk = onTalk
  })
  disconnect(Dialog, {
    onOpen = onOpen,
    onClose = onClose
  })
  onDialogGameEnd()
end

function onDialogGameEnd()
  if dialogWindow then
    dialogWindow:destroy()

    dialogWindow = nil
  end
  ignoreNpcMessages = false
end
