NpcDialog = {
  window = nil,
  portrait = nil,
  messageLabel = nil,
  optionsPanel = nil,
  currentNpcName = nil,
  suppressNpcName = nil,
  suppressUntilStartBlock = false,
  pendingText = {}
}

local function findNpcByName(name, creaturePos)
  if name == nil or name == '' then return nil end

  -- Try by exact position first
  if creaturePos then
    local tile = g_map.getTile(creaturePos)
    if tile then
      -- tile:getCreatures() may not be exposed; fallback to visible spectators
      local spectators = modules.game_interface.getMapPanel():getSpectators() or {}
      pdebug('[NpcDialog] findNpcByName: tile OK, spectators visiveis=' .. tostring(#spectators))
      for _, c in ipairs(spectators) do
        if c:isNpc() and c:getName() == name then
          return c
        end
      end
    end
  end

  -- Fallback: scan all visible spectators by name
  local spectators = modules.game_interface.getMapPanel():getSpectators() or {}
  pdebug('[NpcDialog] findNpcByName: fallback espectadores=' .. tostring(#spectators))
  for _, c in ipairs(spectators) do
    if c:isNpc() and c:getName() == name then
      return c
    end
  end
  return nil
end

function init()
  pinfo('[NpcDialog] init: conectando a g_game.onTalk')
  connect(g_game, { onTalk = NpcDialog.onTalk, onGameEnd = NpcDialog.onGameEnd })
end

function terminate()
  disconnect(g_game, { onTalk = NpcDialog.onTalk, onGameEnd = NpcDialog.onGameEnd })
  NpcDialog.close()
end

function NpcDialog.onGameEnd()
  NpcDialog.close()
end

function NpcDialog.onTalk(name, level, mode, message, channelId, creaturePos)
  pdebug(string.format('[NpcDialog] onTalk name=%s mode=%s pos=%s', tostring(name), tostring(mode), tostring(creaturePos)))
  if mode ~= MessageModes.NpcFrom and mode ~= MessageModes.NpcFromStartBlock then
    return
  end

  -- Se clicamos "bye", suprimir mensagens subsequentes desse NPC
  if NpcDialog.suppressUntilStartBlock and name and NpcDialog.suppressNpcName == name then
    local hasOptionsSB = (message and string.find(message, '{.-}')) ~= nil
    if mode ~= MessageModes.NpcFromStartBlock then
      pdebug('[NpcDialog] Suprimido (bye) até StartBlock do NPC: ' .. tostring(name))
      return
    else
      -- chegou um StartBlock logo após "bye"
      -- se ele não tem opções, não reabrir; apenas limpar a supressão e sair
      NpcDialog.suppressUntilStartBlock = false
      NpcDialog.suppressNpcName = nil
      if not hasOptionsSB then
        pdebug('[NpcDialog] StartBlock sem opções após bye; não abrir janela')
        return
      end
      -- se possui opções, seguimos fluxo normal para abrir
    end
  end

  local sanitized = NpcDialog.sanitizeMessageText(message)
  local hasOptions = (message and string.find(message, '{.-}')) ~= nil

  -- Se for início de bloco, abrir imediatamente, mesmo sem opções
  if mode == MessageModes.NpcFromStartBlock then
    local combinedDisplay = sanitized
    if NpcDialog.pendingText[name] and #NpcDialog.pendingText[name] > 0 then
      combinedDisplay = NpcDialog.pendingText[name] .. "\n" .. sanitized
    end
    NpcDialog.pendingText[name] = nil
    NpcDialog.show(name, message, creaturePos, combinedDisplay)
    return
  end

  -- Se já há janela aberta para este NPC, apenas anexar o texto e atualizar opções
  if NpcDialog.window and NpcDialog.currentNpcName == name then
    NpcDialog.appendMessage(name, message)
    if hasOptions then
      NpcDialog.refreshOptionsFromText(message)
    end
    return
  end

  -- Sem janela aberta: se houver opções, abrir; caso contrário, bufferizar
  if hasOptions then
    local combinedDisplay = sanitized
    if NpcDialog.pendingText[name] and #NpcDialog.pendingText[name] > 0 then
      combinedDisplay = NpcDialog.pendingText[name] .. "\n" .. sanitized
    end
    NpcDialog.pendingText[name] = nil
    NpcDialog.show(name, message, creaturePos, combinedDisplay)
  else
    NpcDialog.pendingText[name] = (NpcDialog.pendingText[name] and (NpcDialog.pendingText[name] .. "\n") or "") .. sanitized
    pdebug('[NpcDialog] Mensagem sem opções; bufferizada para ' .. tostring(name))
  end
end

-- Remove apenas os caracteres `{` e `}` do texto para exibição
function NpcDialog.sanitizeMessageText(text)
  if not text then return '' end
  -- mantém o conteúdo interno e remove as chaves
  local cleaned = text:gsub('[{}]', '')
  return cleaned
end

function NpcDialog.show(name, message, creaturePos, displayText)
  -- Destroy previous window if any
  if NpcDialog.window then
    NpcDialog.window:destroy()
    NpcDialog.window = nil
  end

  NpcDialog.currentNpcName = name

  NpcDialog.window = g_ui.displayUI('npcdialog')
  if not NpcDialog.window then
    perror('[NpcDialog] Falha ao exibir UI npcdialog')
    return
  end
  -- Suprimir mensagens de NPC na console enquanto a janela estiver aberta
  ignoreNpcMessages = true
  NpcDialog.window.onEscape = function()
    NpcDialog.close()
  end

  local title = NpcDialog.window:getChildById('title')
  if title then
    title:setText(name)
  end

  NpcDialog.portrait = NpcDialog.window:recursiveGetChildById('portrait')
  NpcDialog.messageLabel = NpcDialog.window:recursiveGetChildById('npcMessage')
  NpcDialog.optionsPanel = NpcDialog.window:recursiveGetChildById('optionsPanel')
  local contentArea = NpcDialog.window:recursiveGetChildById('contentArea')

  if NpcDialog.messageLabel then
    local textForLabel = displayText or NpcDialog.sanitizeMessageText(message)
    NpcDialog.messageLabel:setText(textForLabel)
    -- fade-in rápido da mensagem sem bloquear interação
    NpcDialog.messageLabel:setOpacity(0)
    if g_effects and g_effects.fadeIn then
      g_effects.fadeIn(NpcDialog.messageLabel, 250)
    end
  end

  -- Criar opções dinâmicas com base no texto
  NpcDialog.refreshOptionsFromText(message)

  -- Set portrait creature
  local creature = findNpcByName(name, creaturePos)
  if creature and NpcDialog.portrait then
    NpcDialog.portrait:setCreature(creature)
    NpcDialog.portrait:setCenter(true)
    NpcDialog.portrait:setCreatureSize(96)
  else
    -- If not found, hide the portrait to avoid empty frame
    if NpcDialog.portrait then
      NpcDialog.portrait:hide()
    end
  end

  -- Ajustar altura da janela ao conteúdo da mensagem
  addEvent(function()
    NpcDialog.adjustWindowHeight()
  end)

  -- Garantir visibilidade da janela
  NpcDialog.window:show()
  NpcDialog.window:raise()
  NpcDialog.window:focus()
end

-- Anexa texto subsequente do mesmo NPC na janela aberta
function NpcDialog.appendMessage(name, message)
  if not NpcDialog.window or NpcDialog.currentNpcName ~= name then return false end
  if not NpcDialog.messageLabel then return false end
  local sanitized = NpcDialog.sanitizeMessageText(message)
  local current = NpcDialog.messageLabel:getText() or ''
  local combined = current ~= '' and (current .. "\n" .. sanitized) or sanitized
  NpcDialog.messageLabel:setText(combined)
  addEvent(function()
    NpcDialog.adjustWindowHeight()
  end)
  return true
end

-- Gera botões dinamicamente a partir de palavras destacadas em {chaves}
function NpcDialog.refreshOptionsFromText(text)
  if not NpcDialog.optionsPanel then return end
  -- limpar botões existentes
  for _, child in ipairs(NpcDialog.optionsPanel:getChildren()) do
    child:destroy()
  end

  local options = {}
  for word in string.gmatch(text or '', '{(.-)}') do
    for opt in string.gmatch(word, '[^|,;]+') do
      opt = opt:trim()
      -- remover crases e pontuação de borda
      opt = opt:gsub('^[`"%s]+', '')
      opt = opt:gsub('[`"%s%.,;:!?]+$', '')
      if opt ~= '' and not table.find(options, opt) then
        table.insert(options, opt)
      end
    end
  end

  -- garantir opção de saída sempre
  if not table.find(options, 'bye') then
    table.insert(options, 'bye')
  end

  pinfo('[NpcDialog] Opções dinâmicas: ' .. table.concat(options, ', '))
  NpcDialog.optionsPanel:show()

  for _, opt in ipairs(options) do
    local btn = g_ui.createWidget('Button', NpcDialog.optionsPanel)
    btn:setText(opt)
    btn.onClick = function() NpcDialog.chooseOption(opt) end
  end
end

function NpcDialog.chooseOption(option)
  if not NpcDialog.currentNpcName or NpcDialog.currentNpcName == '' then
    return
  end
  local speak = SpeakTypesSettings and SpeakTypesSettings.privatePlayerToNpc
  if speak and speak.speakType then
    g_game.talkPrivate(speak.speakType, NpcDialog.currentNpcName, option)
  else
    -- Fallback: try direct message mode constant if mapping not available
    g_game.talkPrivate(MessageModes.NpcTo, NpcDialog.currentNpcName, option)
  end
  -- Se a opção for bye, impedir reabertura até novo StartBlock
  if option:lower() == 'bye' then
    NpcDialog.suppressUntilStartBlock = true
    NpcDialog.suppressNpcName = NpcDialog.currentNpcName
  end
  NpcDialog.close()
end

function NpcDialog.close()
  if NpcDialog.window then
    NpcDialog.window:destroy()
    NpcDialog.window = nil
  end
  -- Reexibir mensagens de NPC na console quando a janela fecha
  ignoreNpcMessages = false
  NpcDialog.portrait = nil
  NpcDialog.messageLabel = nil
  NpcDialog.optionsPanel = nil
  -- não limpamos a supressão aqui; ela é cancelada apenas no próximo StartBlock
end

-- Ajusta dinamicamente a altura da janela conforme o tamanho do texto
function NpcDialog.adjustWindowHeight()
  if not NpcDialog.window then return end
  local contentArea = NpcDialog.window:recursiveGetChildById('contentArea')
  if not contentArea then return end

  local messageH = 0
  if NpcDialog.messageLabel and NpcDialog.messageLabel:isVisible() then
    messageH = NpcDialog.messageLabel:getHeight()
  end

  local portraitH = 0
  if NpcDialog.portrait and NpcDialog.portrait:isVisible() then
    portraitH = NpcDialog.portrait:getHeight()
  end

  local desiredContent = math.max(messageH, portraitH)
  -- incluir margens/paddings do contentArea
  desiredContent = desiredContent + contentArea:getPaddingTop() + contentArea:getPaddingBottom() + contentArea:getMarginTop() + contentArea:getMarginBottom()

  local currentContent = contentArea:getHeight()
  local delta = (desiredContent - currentContent)
  if math.abs(delta) <= 1 then return end

  local newWinHeight = NpcDialog.window:getHeight() + delta
  -- limitar a 80% da altura da tela para não ocupar tudo
  local maxWinHeight = math.floor((g_ui.getRootWidget():getHeight() or 600) * 0.8)
  if newWinHeight > maxWinHeight then newWinHeight = maxWinHeight end
  if newWinHeight < 180 then newWinHeight = 180 end

  pdebug(string.format('[NpcDialog] resize: contentH=%d desired=%d delta=%d winH->%d', currentContent, desiredContent, delta, newWinHeight))
  -- setHeight é exposto ao Lua; setHeight_px não
  NpcDialog.window:setHeight(newWinHeight)
end