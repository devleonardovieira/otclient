_G.OutfitEditor = {}

local window
local outfitList
local creaturePreview
local directionCombo
local offsetTypeCombo
local offsetX
local offsetY
local searchInput
local previewName
local previewLifeBar
local previewManaBar
local previewTarget
local previewBackground
local previewLifeBarBaseWidth
local previewLifeBarBaseHeight
local previewManaBarBaseWidth
local previewManaBarBaseHeight
local previewManaBarBaseMarginTop
local observedMapPanel
local isSyncingOffsets = false

local CLIENT_HEALTH_BAR_WIDTH = 36
local CLIENT_HEALTH_BAR_HEIGHT = 9
local CLIENT_MANA_BAR_GAP = 3
local CLIENT_NAME_BAR_MIN_SPACING = 2

local offsetsCache = {}
local modifiedOutfits = {}
local currentOutfitId = 1
local currentOutfitData = nil
local currentOffsetType = "healthbar"
local dragOffsetState = {
  active = false,
  grabbedWidget = nil,
  accumX = 0,
  accumY = 0
}

local DIRECTIONS = { "north", "east", "south", "west" }
local OFFSET_TYPES = { "healthbar", "outfit", "target" }
local OFFSET_TYPE_LABELS = {
  healthbar = "Health Bar",
  outfit = "Outfit",
  target = "Target"
}

local function isDirectionKey(value)
  if not value then return false end
  value = value:lower()
  for _, dir in ipairs(DIRECTIONS) do
    if dir == value then
      return true
    end
  end
  return false
end

local function isOffsetTypeKey(value)
  if not value then return false end
  value = value:lower()
  for _, typeName in ipairs(OFFSET_TYPES) do
    if typeName == value then
      return true
    end
  end
  return false
end

local function copyPoint(point)
  if not point then return nil end
  return { x = point.x, y = point.y }
end

local function ensureOutfitDir(cache, outfitId, dir)
  cache[outfitId] = cache[outfitId] or {}
  cache[outfitId][dir] = cache[outfitId][dir] or {}
  return cache[outfitId][dir]
end

local function getGameOffsetByType(outfitId, direction, offsetType)
  if offsetType == "healthbar" then
    if g_game.getOutfitHealthBarOffset then
      return g_game.getOutfitHealthBarOffset(outfitId, direction)
    end
    if g_game.getOutfitOffset then
      return g_game.getOutfitOffset(outfitId, direction)
    end
  elseif offsetType == "outfit" then
    if g_game.getOutfitSpriteOffset then
      return g_game.getOutfitSpriteOffset(outfitId, direction)
    end
  elseif offsetType == "target" then
    if g_game.getOutfitTargetOffset then
      return g_game.getOutfitTargetOffset(outfitId, direction)
    end
  end

  return { x = 0, y = 0 }
end

local function setGameOffsetByType(outfitId, direction, offsetType, point)
  if offsetType == "healthbar" then
    if g_game.setOutfitHealthBarOffset then
      g_game.setOutfitHealthBarOffset(outfitId, direction, point)
      return
    end
    if g_game.setOutfitOffset then
      g_game.setOutfitOffset(outfitId, direction, point)
      return
    end
  elseif offsetType == "outfit" then
    if g_game.setOutfitSpriteOffset then
      g_game.setOutfitSpriteOffset(outfitId, direction, point)
      return
    end
  elseif offsetType == "target" then
    if g_game.setOutfitTargetOffset then
      g_game.setOutfitTargetOffset(outfitId, direction, point)
      return
    end
  end
end

local function getEffectiveOffsetPoint(outfitId, direction, dirStr, offsetType)
  local pt = getGameOffsetByType(outfitId, direction, offsetType) or { x = 0, y = 0 }
  if offsetsCache[outfitId] and offsetsCache[outfitId][dirStr] and offsetsCache[outfitId][dirStr][offsetType] then
    pt = offsetsCache[outfitId][dirStr][offsetType]
  end
  return pt
end

local function canStartPreviewDrag(widget)
  if not widget then
    return false
  end

  local wid = widget:getId() or ""
  if currentOffsetType == "outfit" then
    return wid == "creaturePreview" or wid == "creaturePreviewBackground"
  end
  if currentOffsetType == "target" then
    return wid == "targetPreview" or wid == "creaturePreview" or wid == "creaturePreviewBackground"
  end

  return wid == "healthPreview" or wid == "manaPreview" or wid == "namePreview" or wid == "creaturePreview" or wid == "creaturePreviewBackground"
end

local function clearEditorWidgetRefs()
  outfitList = nil
  creaturePreview = nil
  previewName = nil
  previewLifeBar = nil
  previewManaBar = nil
  previewTarget = nil
  previewBackground = nil
  previewLifeBarBaseWidth = nil
  previewLifeBarBaseHeight = nil
  previewManaBarBaseWidth = nil
  previewManaBarBaseHeight = nil
  previewManaBarBaseMarginTop = nil
  directionCombo = nil
  offsetTypeCombo = nil
  offsetX = nil
  offsetY = nil
  searchInput = nil
  currentOutfitData = nil
  dragOffsetState.active = false
  dragOffsetState.grabbedWidget = nil
  dragOffsetState.accumX = 0
  dragOffsetState.accumY = 0
end

local function scaleSizeKeepAspect(width, height, targetWidth, targetHeight)
  if width <= 0 or height <= 0 or targetWidth <= 0 or targetHeight <= 0 then
    return 0, 0
  end

  local resizedWidth = math.floor((targetHeight * width) / height)
  if resizedWidth <= targetWidth then
    return resizedWidth, targetHeight
  end

  local resizedHeight = math.floor((targetWidth * height) / width)
  return targetWidth, resizedHeight
end

local function roundToInt(value)
  if value >= 0 then
    return math.floor(value + 0.5)
  end

  return math.ceil(value - 0.5)
end

local function getPreviewNativeSize(creature, outfitId, spriteSize)
  local thingType = nil
  if outfitId and g_things and g_things.getThingType then
    thingType = g_things.getThingType(outfitId, ThingCategoryCreature)
  end

  local exactSize = spriteSize
  if creature and creature.getExactSize then
    local creatureExactSize = creature:getExactSize()
    if creatureExactSize and creatureExactSize > 0 then
      exactSize = creatureExactSize
    end
  elseif thingType and thingType.getExactSize then
    local thingExactSize = thingType:getExactSize()
    if thingExactSize and thingExactSize > 0 then
      exactSize = thingExactSize
    end
  end

  local nativeSize = exactSize
  if not g_gameConfig.isUseCropSizeForUIDraw() and thingType and thingType.getRealSize then
    local realSize = thingType:getRealSize()
    if realSize and realSize > 0 then
      nativeSize = math.max(exactSize, realSize)
    end
  end

  return math.max(spriteSize, nativeSize), exactSize
end

local function getPreviewMapScale()
  if not modules or not modules.game_interface or not modules.game_interface.getMapPanel then
    return 1
  end

  local mapPanel = modules.game_interface.getMapPanel()
  if not mapPanel then
    return 1
  end

  local visible = mapPanel.getVisibleDimension and mapPanel:getVisibleDimension()
  if not visible or not visible.width or not visible.height or visible.width <= 0 or visible.height <= 0 then
    return 1
  end

  local panelWidth = mapPanel:getWidth()
  local panelHeight = mapPanel:getHeight()
  if mapPanel.getPaddingRect then
    local paddingRect = mapPanel:getPaddingRect()
    if paddingRect and paddingRect.width and paddingRect.width > 0 then
      panelWidth = paddingRect.width
    end
    if paddingRect and paddingRect.height and paddingRect.height > 0 then
      panelHeight = paddingRect.height
    end
  end

  panelWidth = panelWidth - 2
  panelHeight = panelHeight - 2
  if panelWidth <= 0 or panelHeight <= 0 then
    return 1
  end

  if mapPanel.isKeepAspectRatioEnabled and mapPanel:isKeepAspectRatioEnabled() then
    local scaledWidth, scaledHeight = scaleSizeKeepAspect(visible.width, visible.height, panelWidth, panelHeight)
    if scaledWidth > 0 and scaledHeight > 0 then
      panelWidth = scaledWidth
      panelHeight = scaledHeight
    end
  end

  local spriteSize = g_gameConfig.getSpriteSize and g_gameConfig.getSpriteSize() or 32
  if spriteSize <= 0 then
    return 1
  end

  local tileWidth = panelWidth / visible.width
  local tileHeight = panelHeight / visible.height
  local tileSize = math.min(tileWidth, tileHeight)
  if tileSize <= 0 then
    return 1
  end

  return tileSize / spriteSize
end

local function applyPreviewSizeFromMapScale()
  if not creaturePreview then
    return 1
  end

  local spriteSize = g_gameConfig.getSpriteSize and g_gameConfig.getSpriteSize() or 32
  local mapScale = getPreviewMapScale()
  local previewSize = math.max(32, math.floor((spriteSize * 2) * mapScale + 0.5))
  creaturePreview:setWidth(previewSize)
  creaturePreview:setHeight(previewSize)
  return previewSize / (spriteSize * 2)
end

local function updateTargetPreviewOverlay(nativeSize, spriteSize, previewScale)
  if not previewTarget or not creaturePreview or not currentOutfitId then
    return
  end

  if currentOffsetType ~= "target" then
    previewTarget:setVisible(false)
    return
  end

  local dirOption = directionCombo and directionCombo:getCurrentOption()
  if not dirOption or not dirOption.data then
    previewTarget:setVisible(false)
    return
  end

  local dir = dirOption.data.dir
  local dirStr = dirOption.text:lower()
  local targetPt = getEffectiveOffsetPoint(currentOutfitId, dir, dirStr, "target") or { x = 0, y = 0 }
  local outfitPt = getEffectiveOffsetPoint(currentOutfitId, dir, dirStr, "outfit") or { x = 0, y = 0 }
  local totalTargetPt = { x = (outfitPt.x or 0) + (targetPt.x or 0), y = (outfitPt.y or 0) + (targetPt.y or 0) }

  spriteSize = spriteSize or (g_gameConfig.getSpriteSize and g_gameConfig.getSpriteSize() or 32)
  if spriteSize <= 0 then
    previewTarget:setVisible(false)
    return
  end
  nativeSize = nativeSize or spriteSize
  previewScale = previewScale or (creaturePreview:getWidth() / (spriteSize * 2))
  if previewScale <= 0 then
    previewTarget:setVisible(false)
    return
  end

  local thingSizeTiles = 1
  if g_things and g_things.getThingType then
    local thingType = g_things.getThingType(currentOutfitId, ThingCategoryCreature)
    if thingType then
      thingSizeTiles = math.max(thingType:getWidth() or 1, thingType:getHeight() or 1)
    end
  end

  local thingSize = thingSizeTiles * spriteSize
  local texturePath = "/images/targetselector/white" .. thingSize .. ".png"
  local hasTexture = g_resources and g_resources.fileExists and g_resources.fileExists(texturePath)

  local scaledThing = thingSize * previewScale

  -- Match Creature::draw selection-square anchor with the same base used in healthbar preview.
  local left = (nativeSize / 2 + spriteSize / 2 + totalTargetPt.x - thingSize / 2) * previewScale
  local top = (nativeSize / 2 + spriteSize / 2 + totalTargetPt.y - thingSize / 2) * previewScale

  local sizePx = math.max(1, roundToInt(scaledThing))
  previewTarget:setWidth(sizePx)
  previewTarget:setHeight(sizePx)
  previewTarget:setMarginLeft(roundToInt(left))
  previewTarget:setMarginTop(roundToInt(top))

  previewTarget:removeAnchor(AnchorTop)
  previewTarget:removeAnchor(AnchorLeft)
  previewTarget:removeAnchor(AnchorRight)
  previewTarget:removeAnchor(AnchorBottom)
  previewTarget:removeAnchor(AnchorHorizontalCenter)
  previewTarget:removeAnchor(AnchorVerticalCenter)
  previewTarget:addAnchor(AnchorTop, 'creaturePreview', AnchorTop)
  previewTarget:addAnchor(AnchorLeft, 'creaturePreview', AnchorLeft)

  if hasTexture then
    previewTarget:setImageSource(texturePath)
    previewTarget:setImageColor("#FFFFFFFF")
    previewTarget:setBorderWidth(0)
  else
    previewTarget:setImageSource("")
    previewTarget:setBackgroundColor("#00000000")
    previewTarget:setBorderColor("#FFFFFFFF")
    previewTarget:setBorderWidth(2)
  end

  previewTarget:setVisible(true)
  previewTarget:lower()
end

local function parseOffsetsContent(content)
  local parsed = {}
  local currentId = nil
  local currentDir = nil
  if not content then
    return parsed
  end

  for line in content:gmatch("[^\r\n]+") do
    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed and trimmed ~= "" and trimmed ~= "outfits" then
      local idMatch = trimmed:match("^(%d+)%s*$")
      if idMatch then
        currentId = tonumber(idMatch)
        currentDir = nil
        if currentId then
          parsed[currentId] = parsed[currentId] or {}
        end
      elseif currentId then
        local keyWithValues, xStr, yStr = trimmed:match("^([a-zA-Z]+)%s*:%s*([-%d]+)%s+([-%d]+)%s*$")
        if keyWithValues and xStr and yStr then
          local key = keyWithValues:lower()
          local point = { x = tonumber(xStr), y = tonumber(yStr) }
          if isDirectionKey(key) then
            -- Legacy format: "north: x y" maps to healthbar.
            local dirData = ensureOutfitDir(parsed, currentId, key)
            dirData.healthbar = point
            currentDir = key
          elseif currentDir and isOffsetTypeKey(key) then
            -- New format:
            -- north
            --   healthbar: x y
            --   outfit: x y
            --   target: x y
            local dirData = ensureOutfitDir(parsed, currentId, currentDir)
            dirData[key] = point
          end
        else
          local keyOnly = trimmed:match("^([a-zA-Z]+)%s*:?%s*$")
          if keyOnly then
            keyOnly = keyOnly:lower()
            if isDirectionKey(keyOnly) then
              currentDir = keyOnly
              ensureOutfitDir(parsed, currentId, currentDir)
            end
          end
        end
      end
    end
  end

  return parsed
end

local function serializeOffsetsContent(data)
  local content = "outfits\n"
  local ids = {}
  for id, _ in pairs(data) do
    table.insert(ids, id)
  end
  table.sort(ids)

  for _, id in ipairs(ids) do
    content = content .. "  " .. id .. "\n"
    local outfitData = data[id] or {}
    for _, dir in ipairs(DIRECTIONS) do
      local dirData = outfitData[dir]
      if dirData then
        local hasAny = false
        for _, offsetType in ipairs(OFFSET_TYPES) do
          if dirData[offsetType] then
            hasAny = true
            break
          end
        end

        if hasAny then
          content = content .. "    " .. dir .. "\n"
          for _, offsetType in ipairs(OFFSET_TYPES) do
            local p = dirData[offsetType]
            if p then
              content = content .. "      " .. offsetType .. ": " .. p.x .. " " .. p.y .. "\n"
            end
          end
        end
      end
    end
  end

  return content
end

function OutfitEditor.init()
  connect(g_game, {
    onGameStart = OutfitEditor.create,
    onGameEnd = OutfitEditor.destroy
  })

  -- Load existing offsets from file to cache
  OutfitEditor.loadFromFile()

  if g_game.isOnline() then
    OutfitEditor.create()
  end
end

function OutfitEditor.terminate()
  OutfitEditor.destroy()
  disconnect(g_game, {
    onGameStart = OutfitEditor.create,
    onGameEnd = OutfitEditor.destroy
  })
  _G.OutfitEditor = nil
end

function OutfitEditor.create()
  if window then return end
  window = g_ui.loadUI("outfiteditor", g_ui.getRootWidget())

  if not window then
    return
  end

  window:hide()
  function window.onDestroy()
    if observedMapPanel then
      disconnect(observedMapPanel, {
        onZoomChange = OutfitEditor.onMapZoomChange,
        onGeometryChange = OutfitEditor.onMapGeometryChange
      })
      observedMapPanel = nil
    end
    clearEditorWidgetRefs()
    window = nil
  end

  outfitList = window:recursiveGetChildById('outfitList')
  creaturePreview = window:recursiveGetChildById('creaturePreview')
  previewBackground = window:recursiveGetChildById('creaturePreviewBackground')
  directionCombo = window:recursiveGetChildById('directionCombo')
  offsetTypeCombo = window:recursiveGetChildById('offsetTypeCombo')
  offsetX = window:recursiveGetChildById('offsetX')
  offsetY = window:recursiveGetChildById('offsetY')
  searchInput = window:recursiveGetChildById('searchInput')

  -- Find simulated elements (siblings of creaturePreview now)
  previewTarget = window:recursiveGetChildById('targetPreview')
  previewName = window:recursiveGetChildById('namePreview')
  previewLifeBar = window:recursiveGetChildById('healthPreview')
  previewManaBar = window:recursiveGetChildById('manaPreview')
  if previewName and g_gameConfig.getCreatureNameFontName then
    previewName:setFont(g_gameConfig.getCreatureNameFontName())
  end
  if previewTarget then
    previewTarget:setVisible(false)
  end
  if previewName then
    previewName:setColor('#00BC00')
  end
  if previewLifeBar then
    previewLifeBarBaseWidth = CLIENT_HEALTH_BAR_WIDTH
    previewLifeBarBaseHeight = CLIENT_HEALTH_BAR_HEIGHT
    previewLifeBar:setWidth(previewLifeBarBaseWidth)
    previewLifeBar:setHeight(previewLifeBarBaseHeight)
    previewLifeBar:setBackgroundColor('#00BC00')
    previewLifeBar:setBorderWidth(1)
    previewLifeBar:setBorderColor('black')
  end
  if previewManaBar then
    previewManaBarBaseWidth = CLIENT_HEALTH_BAR_WIDTH
    previewManaBarBaseHeight = CLIENT_HEALTH_BAR_HEIGHT
    previewManaBarBaseMarginTop = CLIENT_MANA_BAR_GAP
    previewManaBar:setWidth(previewManaBarBaseWidth)
    previewManaBar:setHeight(previewManaBarBaseHeight)
    previewManaBar:setBackgroundColor('blue')
    previewManaBar:setBorderWidth(1)
    previewManaBar:setBorderColor('black')
    previewManaBar:setMarginTop(previewManaBarBaseMarginTop)
  end

  if not outfitList or not creaturePreview or not directionCombo or not offsetTypeCombo or not offsetX or not offsetY then
    window:destroy()
    window = nil
    return
  end

  -- Setup Combo
  directionCombo:addOption('North', { dir = 0 })
  directionCombo:addOption('East', { dir = 1 })
  directionCombo:addOption('South', { dir = 2 })
  directionCombo:addOption('West', { dir = 3 })
  directionCombo:setCurrentIndex(3) -- Default South

  offsetTypeCombo:addOption(OFFSET_TYPE_LABELS.healthbar, { type = "healthbar" })
  offsetTypeCombo:addOption(OFFSET_TYPE_LABELS.outfit, { type = "outfit" })
  offsetTypeCombo:addOption(OFFSET_TYPE_LABELS.target, { type = "target" })
  offsetTypeCombo:setCurrentIndex(1)

  directionCombo.onOptionChange = OutfitEditor.onDirectionChange
  offsetTypeCombo.onOptionChange = OutfitEditor.onOffsetTypeChange
  offsetX.onValueChange = OutfitEditor.onOffsetChange
  offsetY.onValueChange = OutfitEditor.onOffsetChange

  local function bindPreviewDrag(widget)
    if not widget then return end
    widget.onMousePress = OutfitEditor.onPreviewDragPress
    widget.onMouseMove = OutfitEditor.onPreviewDragMove
    widget.onMouseRelease = OutfitEditor.onPreviewDragRelease
  end

  bindPreviewDrag(previewBackground)
  bindPreviewDrag(creaturePreview)
  bindPreviewDrag(previewTarget)
  bindPreviewDrag(previewLifeBar)
  bindPreviewDrag(previewManaBar)
  bindPreviewDrag(previewName)

  -- Populate list with initial range
  if g_game.isOnline() then
    OutfitEditor.refreshList()
  end

  local saveBtn = window:recursiveGetChildById('saveButton')
  if saveBtn then
    saveBtn.onClick = OutfitEditor.saveOffsets
  end

  local mapPanel = modules and modules.game_interface and modules.game_interface.getMapPanel and modules.game_interface.getMapPanel()
  if mapPanel then
    observedMapPanel = mapPanel
    connect(observedMapPanel, {
      onZoomChange = OutfitEditor.onMapZoomChange,
      onGeometryChange = OutfitEditor.onMapGeometryChange
    })
  end

  -- Bind keys
  g_keyboard.bindKeyDown('Ctrl+Shift+O', OutfitEditor.toggle)

  -- Setup List Selection Change Event (More robust than onClick)
  if outfitList then
    outfitList.onChildFocusChange = function(self, focusedChild)
      if focusedChild then
        local idStr = focusedChild:getId()
        local id = tonumber(idStr)
        if id then
          OutfitEditor.selectOutfit(id)
        end
      end
    end
  end
end

function OutfitEditor.destroy()
  if observedMapPanel then
    disconnect(observedMapPanel, {
      onZoomChange = OutfitEditor.onMapZoomChange,
      onGeometryChange = OutfitEditor.onMapGeometryChange
    })
    observedMapPanel = nil
  end
  if window then
    local oldWindow = window
    window = nil
    oldWindow:destroy()
  end
  clearEditorWidgetRefs()
  g_keyboard.unbindKeyDown('Ctrl+Shift+O')
end

function OutfitEditor.onMapZoomChange()
  OutfitEditor.updatePreviewInformation()
end

function OutfitEditor.onMapGeometryChange()
  OutfitEditor.updatePreviewInformation()
end

function OutfitEditor.toggle()
  if not window then
    OutfitEditor.create()
  end
  if not window then return end
  if window:isVisible() then
    OutfitEditor.hide()
  else
    OutfitEditor.show()
  end
end

function OutfitEditor.show()
  if not window then return end
  window:show()
  window:raise()
  window:focus()
end

function OutfitEditor.hide()
  if not window then return end
  window:hide()
end

function OutfitEditor.refreshList(filter)
  if not outfitList then return end
  outfitList:destroyChildren()

  -- We'll try to get all thing types of category creature (1)
  local maxId = 5000 -- Default fallback (increased for modern clients)

  if g_things.getThingTypes then
    local things = g_things.getThingTypes(ThingCategoryCreature)
    -- Check if things is a table and has items
    if type(things) == 'table' then
      maxId = #things
      if maxId == 0 then maxId = 5000 end
    elseif type(things) == 'userdata' then
      -- Attempt to get length from userdata
      local success, len = pcall(function() return #things end)
      if success and len > 0 then
        maxId = len
      end
    end
  end

  print("OutfitEditor: Refreshing list with Max ID: " .. maxId)

  local count = 0
  local firstValidId = nil

  for id = 1, maxId do
    local isValid = false
    if g_things.isValidDatId then
      isValid = g_things.isValidDatId(id, ThingCategoryCreature)
    else
      -- Fallback if not recompiled yet or function missing
      local t = g_things.getThingType(id, ThingCategoryCreature)
      isValid = (t ~= nil)
    end

    if isValid then
      if not firstValidId then firstValidId = id end
      local match = true
      if filter and filter ~= "" then
        if not string.find(tostring(id), filter) then
          match = false
        end
      end

      if match then
        count = count + 1
        local label = g_ui.createWidget('TextListLabel', outfitList)
        local text = "Outfit ID: " .. id

        -- Visual feedback if we have offsets for this outfit
        if offsetsCache[id] then
          text = text .. " *"
        end

        label:setText(text)
        label:setId(tostring(id))
        label.onClick = function(widget)
          local idStr = widget:getId()
          local id = tonumber(idStr)
          print("OutfitEditor: Clicked widget ID " .. tostring(idStr) .. " -> " .. tostring(id))
          if id then
            OutfitEditor.selectOutfit(id)
          end
        end
      end
    end
  end

  if firstValidId and not currentOutfitData then
    OutfitEditor.selectOutfit(firstValidId)
  end
end

function OutfitEditor.onSearch(text)
  OutfitEditor.refreshList(text)
end

function OutfitEditor.selectOutfit(id)
  currentOutfitId = id
  -- Force full outfit structure to ensure preview renders
  local outfit = { type = id, head = 0, body = 0, legs = 0, feet = 0, addons = 0 }
  currentOutfitData = outfit

  if creaturePreview then
    -- Use Creature.create() to fix category issues (ID 1/2) and ensure clean state
    local c = Creature.create()
    if c then
      c:setOutfit(outfit)

      local option = directionCombo:getCurrentOption()
      if option and option.data then
        c:setDirection(option.data.dir)
      end

      applyPreviewSizeFromMapScale()

      creaturePreview:setCreature(c)
      creaturePreview:setCenter(true)
    else
      -- Fallback
      creaturePreview:setOutfit(outfit)
      creaturePreview:setCenter(true)
      applyPreviewSizeFromMapScale()
      local option = directionCombo:getCurrentOption()
      if option and option.data then
        creaturePreview:setDirection(option.data.dir)
      end
    end
  end

  -- Update name color to match selected id for visual feedback
  if previewName then
    local localPlayer = g_game.getLocalPlayer()
    if localPlayer and localPlayer.getName then
      previewName:setText(localPlayer:getName())
    else
      previewName:setText("Creature " .. id)
    end
  end

  if previewLifeBar then
    previewLifeBar:setPercent(100)
  end

  if previewManaBar then
    previewManaBar:setPercent(100)
  end

  OutfitEditor.updateUIFromOffsets(id)
end

function OutfitEditor.updatePreviewInformation()
  if not creaturePreview then
    return
  end
  if not previewLifeBar then
    return
  end
  if not offsetX or not offsetY then
    return
  end

  local creature = creaturePreview:getCreature()
  local option = directionCombo and directionCombo:getCurrentOption()
  if not option or not option.data then
    return
  end
  local dir = option.data.dir
  local dirStr = option.text:lower()
  local barPt = getEffectiveOffsetPoint(currentOutfitId, dir, dirStr, "healthbar")
  local x = barPt.x or 0
  local y = barPt.y or 0

  local spriteSize = 32
  if g_gameConfig.getSpriteSize then
    spriteSize = g_gameConfig.getSpriteSize()
  end

  local nativeSize, exactSize = getPreviewNativeSize(creature, currentOutfitId, spriteSize)

  local cropSizeText = 12
  if g_gameConfig.isAdjustCreatureInformationBasedCropSize() then
    cropSizeText = exactSize
  end

  -- Apply the same map zoom scale on the preview creature.
  applyPreviewSizeFromMapScale()

  -- Reproduce UICreature::draw + Creature::draw positioning before applying drawInformation offsets.
  local previewScale = creaturePreview:getWidth() / (spriteSize * 2)
  local pX = (nativeSize / 2 + spriteSize / 2 + x) * previewScale
  local pY = (nativeSize / 2 - 2 + y) * previewScale

  if previewLifeBarBaseWidth then
    previewLifeBar:setWidth(previewLifeBarBaseWidth)
  end
  if previewLifeBarBaseHeight then
    previewLifeBar:setHeight(previewLifeBarBaseHeight)
  end
  if previewManaBar then
    if previewManaBarBaseWidth then
      previewManaBar:setWidth(previewManaBarBaseWidth)
    end
    if previewManaBarBaseHeight then
      previewManaBar:setHeight(previewManaBarBaseHeight)
    end
    if previewManaBarBaseMarginTop then
      previewManaBar:setMarginTop(previewManaBarBaseMarginTop)
    end
  end

  local barWidth = previewLifeBar:getWidth()
  local barHeight = previewLifeBar:getHeight()
  local nameSize = previewName and previewName:getTextSize() or { width = 0, height = 0 }

  local cropSizeBackground = 0
  if g_gameConfig.isAdjustCreatureInformationBasedCropSize() then
    cropSizeBackground = cropSizeText - (nameSize.height or 0)
  end

  local textLeft = pX - (nameSize.width / 2)
  local textTop = pY - cropSizeText
  local yOffset = 0
  if g_configs and g_configs.getPublicConfig then
    local cfg = g_configs.getPublicConfig()
    if cfg and cfg.font and cfg.font.creatureTextOffsetY then
      yOffset = cfg.font.creatureTextOffsetY
    end
  end
  textTop = textTop + yOffset

  local barLeft = pX - (barWidth / 2)
  local barTop = pY - cropSizeBackground

  -- Match Creature::drawInformation spacing rules.
  local minSpacing = CLIENT_NAME_BAR_MIN_SPACING
  local currentSpacing = barTop - (textTop + (nameSize.height or 0))
  if currentSpacing < minSpacing then
    textTop = barTop - minSpacing - (nameSize.height or 0)
  end

  -- Apply margins
  if previewLifeBar then
    previewLifeBar:removeAnchor(AnchorTop)
    previewLifeBar:removeAnchor(AnchorLeft)
    previewLifeBar:removeAnchor(AnchorHorizontalCenter)
    previewLifeBar:removeAnchor(AnchorBottom)
    previewLifeBar:addAnchor(AnchorTop, 'creaturePreview', AnchorTop)
    previewLifeBar:addAnchor(AnchorLeft, 'creaturePreview', AnchorLeft)
    previewLifeBar:setMarginLeft(roundToInt(barLeft))
    previewLifeBar:setMarginTop(roundToInt(barTop))
  end

  if previewManaBar then
    previewManaBar:removeAnchor(AnchorTop)
    previewManaBar:removeAnchor(AnchorLeft)
    previewManaBar:removeAnchor(AnchorHorizontalCenter)
    previewManaBar:removeAnchor(AnchorBottom)
    previewManaBar:addAnchor(AnchorTop, 'creaturePreview', AnchorTop)
    previewManaBar:addAnchor(AnchorLeft, 'creaturePreview', AnchorLeft)
    previewManaBar:setMarginLeft(roundToInt(barLeft))
    previewManaBar:setMarginTop(roundToInt(barTop + barHeight + CLIENT_MANA_BAR_GAP))
  end

  if previewName then
    -- Detach from healthPreview anchors so we can position it like the client.
    previewName:removeAnchor(AnchorBottom)
    previewName:removeAnchor(AnchorHorizontalCenter)
    previewName:removeAnchor(AnchorTop)
    previewName:removeAnchor(AnchorLeft)
    previewName:addAnchor(AnchorTop, 'creaturePreview', AnchorTop)
    previewName:addAnchor(AnchorLeft, 'creaturePreview', AnchorLeft)
    previewName:setMarginLeft(roundToInt(textLeft))
    previewName:setMarginTop(roundToInt(textTop))
  end

  updateTargetPreviewOverlay(nativeSize, spriteSize, previewScale)
end

function OutfitEditor.updateUIFromOffsets(id)
  -- The corelib ComboBox doesn't always expose getCurrentData
  -- local index = directionCombo:getCurrentIndex() -- Removed as it causes nil error

  local dirOption = directionCombo:getCurrentOption()
  if not dirOption or not dirOption.data then return end

  local typeOption = offsetTypeCombo and offsetTypeCombo:getCurrentOption()
  if typeOption and typeOption.data and typeOption.data.type then
    currentOffsetType = typeOption.data.type
  else
    currentOffsetType = "healthbar"
  end

  local dir = dirOption.data.dir
  local dirStr = dirOption.text:lower()

  creaturePreview:setDirection(dir)

  local pt = getEffectiveOffsetPoint(id, dir, dirStr, currentOffsetType)
  if not pt then pt = { x = 0, y = 0 } end

  isSyncingOffsets = true
  if offsetX:getValue() ~= pt.x then
    offsetX:setValue(pt.x)
  end
  if offsetY:getValue() ~= pt.y then
    offsetY:setValue(pt.y)
  end
  isSyncingOffsets = false

  -- Force redraw of preview
  if currentOutfitData then
    creaturePreview:setOutfit(currentOutfitData)
  end

  OutfitEditor.updatePreviewInformation()
end

function OutfitEditor.onDirectionChange()
  if currentOutfitId then
    OutfitEditor.updateUIFromOffsets(currentOutfitId)
  end
end

function OutfitEditor.onOffsetTypeChange()
  if currentOutfitId then
    OutfitEditor.updateUIFromOffsets(currentOutfitId)
  else
    OutfitEditor.updatePreviewInformation()
  end
end

function OutfitEditor.onPreviewDragPress(widget, mousePos, mouseButton)
  if mouseButton ~= MouseLeftButton then
    return false
  end
  if not currentOutfitId or not offsetX or not offsetY then
    return false
  end
  if not canStartPreviewDrag(widget) then
    return false
  end

  if dragOffsetState.active and dragOffsetState.grabbedWidget then
    dragOffsetState.grabbedWidget:ungrabMouse()
  end

  dragOffsetState.active = true
  dragOffsetState.grabbedWidget = widget
  dragOffsetState.accumX = 0
  dragOffsetState.accumY = 0
  widget:grabMouse()
  return true
end

function OutfitEditor.onPreviewDragMove(widget, mousePos, mouseMoved)
  if not dragOffsetState.active then
    return false
  end

  if not g_mouse.isPressed(MouseLeftButton) then
    OutfitEditor.onPreviewDragRelease(widget, mousePos, MouseLeftButton)
    return true
  end

  local movedX = mouseMoved and mouseMoved.x or 0
  local movedY = mouseMoved and mouseMoved.y or 0
  if movedX == 0 and movedY == 0 then
    return true
  end

  local spriteSize = g_gameConfig.getSpriteSize and g_gameConfig.getSpriteSize() or 32
  local previewScale = creaturePreview and (creaturePreview:getWidth() / (spriteSize * 2)) or 0
  if previewScale <= 0 then
    return true
  end

  dragOffsetState.accumX = dragOffsetState.accumX + (movedX / previewScale)
  dragOffsetState.accumY = dragOffsetState.accumY + (movedY / previewScale)

  local stepX = 0
  local stepY = 0
  if dragOffsetState.accumX >= 1 then
    stepX = math.floor(dragOffsetState.accumX)
  elseif dragOffsetState.accumX <= -1 then
    stepX = math.ceil(dragOffsetState.accumX)
  end

  if dragOffsetState.accumY >= 1 then
    stepY = math.floor(dragOffsetState.accumY)
  elseif dragOffsetState.accumY <= -1 then
    stepY = math.ceil(dragOffsetState.accumY)
  end

  if stepX == 0 and stepY == 0 then
    return true
  end

  dragOffsetState.accumX = dragOffsetState.accumX - stepX
  dragOffsetState.accumY = dragOffsetState.accumY - stepY

  offsetX:setValue(offsetX:getValue() + stepX)
  offsetY:setValue(offsetY:getValue() + stepY)
  return true
end

function OutfitEditor.onPreviewDragRelease(widget, mousePos, mouseButton)
  if not dragOffsetState.active then
    return false
  end
  if mouseButton ~= MouseLeftButton and g_mouse.isPressed(MouseLeftButton) then
    return false
  end

  dragOffsetState.active = false
  dragOffsetState.accumX = 0
  dragOffsetState.accumY = 0
  if dragOffsetState.grabbedWidget then
    dragOffsetState.grabbedWidget:ungrabMouse()
    dragOffsetState.grabbedWidget = nil
  end
  return true
end

function OutfitEditor.onOffsetChange()
  if not currentOutfitId then return end
  if isSyncingOffsets then
    OutfitEditor.updatePreviewInformation()
    return
  end

  local option = directionCombo:getCurrentOption()
  if not option or not option.data then return end
  local typeOption = offsetTypeCombo and offsetTypeCombo:getCurrentOption()
  if not typeOption or not typeOption.data or not typeOption.data.type then return end

  local dir = option.data.dir
  local dirStr = option.text:lower()
  local offsetType = typeOption.data.type

  local x = offsetX:getValue()
  local y = offsetY:getValue()

  -- Update game
  setGameOffsetByType(currentOutfitId, dir, offsetType, { x = x, y = y })

  -- Force redraw of preview
  if currentOutfitData then
    creaturePreview:setOutfit(currentOutfitData)
  end

  OutfitEditor.updatePreviewInformation()

  -- Update cache
  local dirData = ensureOutfitDir(offsetsCache, currentOutfitId, dirStr)
  dirData[offsetType] = { x = x, y = y }
  modifiedOutfits[currentOutfitId] = true
end

function OutfitEditor.loadFromFile()
  offsetsCache = {}
  modifiedOutfits = {}
  local path = "/data/otml/outfits.otml"
  if not g_resources.fileExists(path) then return end

  local content = g_resources.readFileContents(path)
  if not content then return end
  offsetsCache = parseOffsetsContent(content)
end

function OutfitEditor.saveOffsets()
  if not next(modifiedOutfits) then
    print("OutfitEditor: No changes to save.")
    return
  end

  local virtualPath = "/data/otml/outfits.otml"
  local writePath = "data/otml/outfits.otml"

  -- Merge only edited outfits into current file contents.
  local merged = {}
  if g_resources.fileExists(virtualPath) then
    local currentContent = g_resources.readFileContents(virtualPath)
    merged = parseOffsetsContent(currentContent)
  end

  for outfitId, _ in pairs(modifiedOutfits) do
    local cached = offsetsCache[outfitId]
    if cached then
      merged[outfitId] = merged[outfitId] or {}
      for _, dir in ipairs(DIRECTIONS) do
        if cached[dir] then
          merged[outfitId][dir] = merged[outfitId][dir] or {}
          for _, offsetType in ipairs(OFFSET_TYPES) do
            local p = cached[dir][offsetType]
            if p then
              merged[outfitId][dir][offsetType] = copyPoint(p)
            end
          end
        end
      end
    end
  end

  local content = serializeOffsetsContent(merged)

  -- Save in the project workdir so file seen in IDE is updated.
  local oldWriteDir = g_resources.getWriteDir and g_resources.getWriteDir() or ""
  local workDir = g_resources.getWorkDir and g_resources.getWorkDir() or oldWriteDir
  local switchedWriteDir = false
  if workDir ~= "" and oldWriteDir ~= workDir then
    switchedWriteDir = g_resources.setWriteDir(workDir)
  end

  g_resources.makeDir("data")
  g_resources.makeDir("data/otml")

  local ok = g_resources.writeFileContents(writePath, content)
  if not ok then
    ok = g_resources.writeFileContents(virtualPath, content)
  end

  if switchedWriteDir and oldWriteDir ~= "" then
    g_resources.setWriteDir(oldWriteDir)
  end

  if ok then
    offsetsCache = merged
    modifiedOutfits = {}
    if g_resources.getRealPath then
      print("OutfitEditor: Saved offsets to " .. g_resources.getRealPath(virtualPath))
    else
      print("OutfitEditor: Saved offsets to " .. virtualPath)
    end
  else
    print("OutfitEditor: Failed to save offsets to " .. virtualPath)
  end
end
