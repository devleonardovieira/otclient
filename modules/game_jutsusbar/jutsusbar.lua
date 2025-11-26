-- Controller para a barra de Jutsus (10 slots)

local slotsCount = 10
local ButtonJutsusBar = nil
local ButtonJutsusBarEdit = nil

JutsusBar = Controller:new()

-- Funções de atalho para callbacks do painel principal
function toggleJutsusBar()
  if JutsusBar then
    JutsusBar:toggle()
  end
end

function startEditJutsusBar()
  if JutsusBar then
    JutsusBar:startEditMode()
  end
end

function JutsusBar:onInit()
  -- Inicialização do módulo (não carregar HTML aqui por padrão)
  self.isEditMode = false
  self.selectedSlotIndex = nil
  self.locked = false
  self.orientation = 'horizontal'
end

function JutsusBar:onGameStart()
  -- Cria botão no painel principal para abrir/fechar a barra
  local createBtn = function()
    local controllerRef = JutsusBar
    ButtonJutsusBar = modules.game_mainpanel.addToggleButton(
      'jutsusBar',
      tr('Jutsus Bar'),
      '/images/options/button_spells',
      function()
        if controllerRef then controllerRef:toggle() end
      end,
      false,
      13
    )
    if ButtonJutsusBar then ButtonJutsusBar:setOn(false) end

    -- Botão dedicado para edição da barra (12x12)
    ButtonJutsusBarEdit = modules.game_mainpanel.addToggleButton(
      'jutsusBarEdit',
      tr('Editar barra'),
      '/images/options/button_control',
      function()
        if controllerRef then
          if controllerRef.isEditMode then controllerRef:stopEditMode() else controllerRef:startEditMode() end
        end
      end,
      false,
      14
    )
    if ButtonJutsusBarEdit then
      ButtonJutsusBarEdit:setSize('12 12')
      ButtonJutsusBarEdit:setImageClip('0 0 12 12')
      ButtonJutsusBarEdit:setOn(false)
    end
  end

--[[   if not g_modules.getModule('game_mainpanel'):isLoaded() then
    scheduleEvent(createBtn, 100)
  else
    createBtn()
  end ]]
end

function JutsusBar:open()
  if self.ui then return end
  self:loadUI('jutsusbar', modules.game_interface.getMapPanel())
  if not self.ui then
    g_logger.error('Falha ao carregar OTUI: /game_jutsusbar/jutsusbar')
    return
  end
  -- Garantir que o overlay fique acima e capture o mouse
  self.ui:raise()
  self.ui:setPhantom(false)
  self.ui:setDraggable(true)
  self:wireUi()
  -- Captura cliques diretamente no painel da barra e repassa aos slots
  self.ui.onMouseRelease = function(widget, mousePos, mouseButton)
    if mouseButton == MouseLeftButton then
      for i = 1, slotsCount do
        local slot = self.ui:getChildById('slot' .. i)
        if slot and slot:containsPoint(mousePos) then
          if slot.onMouseRelease then
            slot.onMouseRelease(slot, mousePos, mouseButton)
          elseif slot.onClick then
            slot.onClick(slot)
          else
            self:onSpellClick(i)
          end
          return true
        end
      end
      return true
    elseif mouseButton == MouseRightButton then
      -- Abrir menu da barra quando clicar fora de um slot
      local hitSlot = false
      for i = 1, slotsCount do
        local slot = self.ui:getChildById('slot' .. i)
        if slot and slot:containsPoint(mousePos) then
          hitSlot = true
          break
        end
      end
      if not hitSlot then
        self:showBarContextMenu(mousePos)
        return true
      end
      return false
    end
    return false
  end

  if ButtonJutsusBar then ButtonJutsusBar:setOn(true) end

  -- OTUI já centraliza via anchors.centerIn: parent
end

function JutsusBar:close()
  if not self.ui then return end
  self:destroyUI()
  if ButtonJutsusBar then ButtonJutsusBar:setOn(false) end
end

function JutsusBar:toggle()
  if self.ui then self:close() else self:open() end
end

function JutsusBar:wireUi()
  if not self.ui then return end
  -- Configure shield para bloquear eventos nos espaços vazios
  local shield = self.ui:getChildById('shield')
  if shield then
    shield:setPhantom(false)
    shield:setFocusable(false)
    shield:lower()
  end

  -- Permitir arrastar a barra quando não estiver fixada
  self.ui.onDragEnter = function()
    if self.locked then return false end
    self.ui:breakAnchors()
    local oldPos = self.ui:getPosition()
    local mp = g_window.getMousePosition()
    if not mp then return false end
    self.movingReference = { x = mp.x - oldPos.x, y = mp.y - oldPos.y }
    return true
  end
  self.ui.onDragMove = function()
    if self.locked then return false end
    local mp = g_window.getMousePosition()
    if not mp then return false end
    local pos = { x = mp.x - (self.movingReference and self.movingReference.x or 0), y = mp.y - (self.movingReference and self.movingReference.y or 0) }
    self.ui:setPosition(pos)
    self.ui:bindRectToParent()
    return true
  end

  for i = 1, slotsCount do
    local slot = self.ui:getChildById('slot' .. i)
    if slot then
      slot:setText('+')
      slot:setPhantom(false)
      slot:setFocusable(false)
      slot:raise()
      slot:setDraggable(true)
      slot.onDragEnter = function(mousePos)
        -- Aceitar arrasto em edição ou quando arrastando da janela de seleção
        local dragging = g_ui.getDraggingWidget()
        if dragging then
          local parent = dragging:getParent()
          if parent and parent:getId() == 'spellsPanel' then
            slot:mergeStyle({ ['border-width'] = 2, ['border-color'] = '#66ccff' })
            return true
          end
        end
        if self.isEditMode then
          slot:mergeStyle({ ['border-width'] = 2, ['border-color'] = '#ffd24f' })
          return true
        end
        return false
      end
      slot.onDragLeave = function(droppedWidget, mousePos)
        slot:mergeStyle({ ['border-width'] = 0, ['border-color'] = 'alpha' })
        return true
      end
      slot.onDrop = function(...)
        local args = { ... }
        local draggedWidget = args[1]
        local mousePos = args[#args]
        -- Suporte à assinatura alternativa (target, draggedWidget, mousePos)
        if args[2] and type(args[2]) == 'table' and args[2].getId then
          draggedWidget = args[2]
        end
        if not draggedWidget or not draggedWidget.getId then return false end
        local draggedId = draggedWidget:getId()
        local bIndex = tonumber(slot:getId():match('slot(%d+)')) or i

        -- Caso 1: arrasto entre slots durante edição (swap)
        local aIndex = tonumber(draggedId:match('slot(%d+)'))
        if aIndex and bIndex and aIndex ~= bIndex then
          if not self.isEditMode then return false end
          self:swapSlotContents(aIndex, bIndex)
          slot:mergeStyle({ ['border-width'] = 0, ['border-color'] = 'alpha' })
          return true
        end

        -- Caso 2: arrasto de botão da lista de magias para a barra (atribuir)
        local parent = draggedWidget:getParent()
        if parent and parent:getId() == 'spellsPanel' then
          local spellName = draggedId
          self:setSlotSpell(bIndex, spellName)
          self:closeSpellAssign()
          slot:mergeStyle({ ['border-width'] = 0, ['border-color'] = 'alpha' })
          return true
        end
        return false
      end
      slot.onMouseRelease = function(widget, mousePos, mouseButton)
        if mouseButton == MouseLeftButton then
          if self.isEditMode then
            self:onEditSlotClick(i)
            return true
          else
            self:onSpellClick(i)
            return true
          end
        elseif mouseButton == MouseRightButton then
          self:showSlotContextMenu(i, mousePos)
          return true
        end
        return false
      end
    end
  end
  -- Botão 12x12 no canto direito para habilitar edição
  local editBtn = self.ui:getChildById('editButton')
  if editBtn then
    editBtn.onMouseRelease = function(widget, mousePos, mouseButton)
      if widget:containsPoint(mousePos) and mouseButton == MouseLeftButton then
        if self.isEditMode then self:stopEditMode() else self:startEditMode() end
        return true
      end
      return false
    end
    editBtn:setTooltip(tr('Editar barra'))
  end
end

function JutsusBar:onSpellClick(index)
  -- Placeholder: dispare sua lógica de cast aqui
  local slot = self.ui and self.ui:getChildById('slot' .. index)
  if slot and slot.words and slot.words ~= '' then
    if slot.parameter and slot.parameter ~= '' then
      g_game.talk(slot.words .. ' "' .. slot.parameter .. '"')
    else
      g_game.talk(slot.words)
    end
  else
    -- Sem magia no slot: abrir tela de seleção de jutsu
    self:openSpellAssign(index)
  end
end

function JutsusBar:setSpellIcon(index, iconPath)
  if not self.ui then return end
  if index < 1 or index > slotsCount then return end
  local slot = self.ui:getChildById('slot' .. index)
  if slot then
    slot:setIcon(stdext.resolve_path(iconPath))
  end
end

function JutsusBar:setOrbValue(value)
  if not self.ui then return end
  local label = self.ui:getChildById('orbValue')
  if label then
    label:setText(tostring(value))
  end
end

-- Exibe menu de contexto do slot
function JutsusBar:showSlotContextMenu(index, mousePos)
  local menu = g_ui.createWidget('PopupMenu')
  menu:addOption(tr('Adicionar magia'), function()
    self:openSpellAssign(index)
  end)
  menu:addSeparator()
  menu:addOption(tr('Limpar slot'), function()
    self:clearSlot(index)
  end)
  menu:addSeparator()
  if not self.isEditMode then
    menu:addOption(tr('Editar barra'), function()
      self:startEditMode()
    end)
  else
    menu:addOption(tr('Concluir edição'), function()
      self:stopEditMode()
    end)
  end
  menu:display(mousePos)
end

-- Abre janela para selecionar magia
function JutsusBar:openSpellAssign(index)
  self.slotToEdit = index
  if self.spellWindow and not self.spellWindow:isDestroyed() then
    self.spellWindow:destroy()
  end

  self.spellWindow = g_ui.displayUI('jutsusbar_spells')
  if not self.spellWindow then
    g_logger.error('Falha ao abrir janela de seleção de magias (jutsusbar_spells).')
    return
  end
  self.spellWindow:show()
  self.spellWindow:raise()
  self.spellWindow.onEscape = function()
    self:closeSpellAssign()
  end

  local panel = self.spellWindow:recursiveGetChildById('spellsPanel')
  if not panel then
    g_logger.error('Painel de magias não encontrado em jutsusbar_spells.')
    return
  end
  panel:destroyChildren()

  local player = g_game.getLocalPlayer()
  local vocId = player and player:getVocation() or nil
  local spellOrder = SpelllistSettings['Default'].spellOrder

  for _, spellName in ipairs(spellOrder) do
    local info = SpellInfo['Default'][spellName]
    local allowed = true
    if vocId then
      allowed = table.contains(info.vocations, vocId)
    end
    if allowed then
      local btn = g_ui.createWidget('JutsuSpellButton', panel)
      btn:setId(spellName)
      btn:setText(spellName .. (info.words and ('\n\'' .. info.words .. '\'') or ''))
      local iconId = tonumber(Spells.getClientId(spellName))
      local profile = Spells.getSpellProfileByName(spellName) or 'Default'
      btn:setImageSource(SpelllistSettings[profile].iconFile)
      btn:setImageClip(Spells.getImageClip(iconId, profile))
      if self:isSpellAssigned(info.words, index) then
        btn:setEnabled(false)
        btn:setTooltip(tr('Já em uso em outro slot'))
      else
        btn.onClick = function()
          self:setSlotSpell(index, spellName)
          self:closeSpellAssign()
        end
      end
    end
  end
end

function JutsusBar:closeSpellAssign()
  if self.spellWindow and not self.spellWindow:isDestroyed() then
    self.spellWindow:destroy()
    self.spellWindow = nil
  end
end

function JutsusBar:setSlotSpell(index, spellName)
  if not self.ui then return end
  local slot = self.ui:getChildById('slot' .. index)
  if not slot then return end

  local profile = Spells.getSpellProfileByName(spellName) or 'Default'
  local iconId = tonumber(Spells.getClientId(spellName))
  local info = SpellInfo[profile][spellName]

  if info and info.words and self:isSpellAssigned(info.words, index) then
    return
  end

  local imgSrc = SpelllistSettings[profile].iconFile
  local imgClip = Spells.getImageClip(iconId, profile)
  slot.iconSource = imgSrc
  slot.iconClip = imgClip
  slot:setImageSource(imgSrc)
  slot:setImageClip(imgClip)
  slot.words = info and info.words or nil
  slot.parameter = nil
  slot:setText('')
end

function JutsusBar:clearSlot(index)
  if not self.ui then return end
  local slot = self.ui:getChildById('slot' .. index)
  if not slot then return end
  slot.iconSource = nil
  slot.iconClip = nil
  slot:setImageSource('/images/ui/button_rounded')
  slot:setImageClip('0 0 0 0')
  slot.words = nil
  slot.parameter = nil
  slot:setText('+')
end

-- Verifica se palavras da magia já estão atribuídas (exceto index)
function JutsusBar:isSpellAssigned(words, exceptIndex)
  if not self.ui or not words or words == '' then return false end
  for i = 1, slotsCount do
    if i ~= (exceptIndex or -1) then
      local s = self.ui:getChildById('slot' .. i)
      if s and s.words == words then
        return true
      end
    end
  end
  return false
end

function JutsusBar:startEditMode()
  self.isEditMode = true
  self.selectedSlotIndex = nil
  -- Desabilita arrasto da barra enquanto em edição
  if self.ui then
    self.ui:setDraggable(false)
  end
  if ButtonJutsusBarEdit then ButtonJutsusBarEdit:setOn(true) end
end

function JutsusBar:stopEditMode()
  if self.selectedSlotIndex then
    local s = self.ui:getChildById('slot' .. self.selectedSlotIndex)
    if s then
      s:mergeStyle({ ['border-width'] = 0, ['border-color'] = 'alpha' })
    end
  end
  self.selectedSlotIndex = nil
  self.isEditMode = false
  -- Restaura arrasto da barra conforme estado de travamento
  if self.ui then
    self.ui:setDraggable(not self.locked)
  end
  if ButtonJutsusBarEdit then ButtonJutsusBarEdit:setOn(false) end
end

function JutsusBar:onEditSlotClick(index)
  if not self.isEditMode then return end
  local slot = self.ui:getChildById('slot' .. index)
  if not slot then return end
  if not self.selectedSlotIndex then
    self.selectedSlotIndex = index
    slot:mergeStyle({ ['border-width'] = 2, ['border-color'] = '#ffd24f' })
  elseif self.selectedSlotIndex == index then
    slot:mergeStyle({ ['border-width'] = 0, ['border-color'] = 'alpha' })
    self.selectedSlotIndex = nil
  else
    local other = self.ui:getChildById('slot' .. self.selectedSlotIndex)
    if other then
      self:swapSlotContents(self.selectedSlotIndex, index)
      other:mergeStyle({ ['border-width'] = 0, ['border-color'] = 'alpha' })
    end
    self.selectedSlotIndex = nil
  end
end

function JutsusBar:applySlotVisual(index)
  local slot = self.ui and self.ui:getChildById('slot' .. index)
  if not slot then return end
  if slot.iconSource then
    slot:setImageSource(slot.iconSource)
    slot:setImageClip(slot.iconClip or '0 0 0 0')
    slot:setText('')
  else
    slot:setImageSource('/images/ui/button_rounded')
    slot:setImageClip('0 0 0 0')
    slot:setText('+')
  end
end

function JutsusBar:swapSlotContents(aIndex, bIndex)
  local a = self.ui and self.ui:getChildById('slot' .. aIndex)
  local b = self.ui and self.ui:getChildById('slot' .. bIndex)
  if not a or not b then return end
  a.iconSource, b.iconSource = b.iconSource, a.iconSource
  a.iconClip,   b.iconClip   = b.iconClip,   a.iconClip
  a.words,      b.words      = b.words,      a.words
  a.parameter,  b.parameter  = b.parameter,  a.parameter
  self:applySlotVisual(aIndex)
  self:applySlotVisual(bIndex)
end

-- Alterna orientação da barra
function JutsusBar:setOrientation(orient)
  if not self.ui then return end
  if orient ~= 'horizontal' and orient ~= 'vertical' then return end
  if orient == self.orientation then return end
  local layout
  local slotSize, editSize, spacing = 36, 12, 6
  if orient == 'horizontal' then
    layout = UIHorizontalLayout.create(self.ui)
  else
    layout = UIVerticalLayout.create(self.ui)
  end
  if layout then
    layout:setSpacing(spacing)
    self.ui:setLayout(layout)
    self.orientation = orient
    -- Ajustar tamanho conforme orientação para evitar deformação (sem orbe)
    if orient == 'horizontal' then
      local width = (slotSize * 10) + editSize + spacing * 10 + 8 -- padding
      local height = 44
      self.ui:resize(width, height)
    else
      local height = (slotSize * 10) + editSize + spacing * 10 + 8 -- padding
      local width = slotSize + 8 -- padding
      self.ui:resize(width, height)
    end
    self.ui:updateLayout()
  end
end

-- Menu da barra (fixar, orientação, editar)
function JutsusBar:showBarContextMenu(mousePos)
  local menu = g_ui.createWidget('PopupMenu')
  if self.locked then
    menu:addOption(tr('Desfixar barra'), function()
      self.locked = false
      self.ui:setDraggable(true)
    end)
  else
    menu:addOption(tr('Fixar barra'), function()
      self.locked = true
      self.ui:setDraggable(false)
    end)
  end
  menu:addSeparator()
  if self.orientation == 'horizontal' then
    menu:addOption(tr('Orientação vertical'), function()
      self:setOrientation('vertical')
    end)
  else
    menu:addOption(tr('Orientação horizontal'), function()
      self:setOrientation('horizontal')
    end)
  end
  menu:addSeparator()
  if not self.isEditMode then
    menu:addOption(tr('Editar barra'), function() self:startEditMode() end)
  else
    menu:addOption(tr('Concluir edição'), function() self:stopEditMode() end)
  end
  menu:display(mousePos)
end