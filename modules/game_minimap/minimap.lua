-- chunkname: @/modules/game_minimap/minimap.lua

minimapWidget = nil
minimapButton = nil
minimapWindow = nil
otmm = true
preloaded = false
oldZoom = nil
oldPos = nil
oldFloor = nil
panelControls = nil
confirmTeleport = nil

local searchPokemon = {
	name = "",
	list = {}
}
local controlsMinimapWidget = {
	floorUp = function()
		minimapWidget:onFloorUp(1)
	end,
	floorDown = function()
		minimapWidget:onFloorDown(1)
	end,
	zoomIn = function()
		minimapWidget:zoomIn()
	end,
	zoomOut = function()
		minimapWidget:zoomOut()
	end,
	reset = function()
		minimapWidget:reset()
	end,
	close = function()
		toggleFullMap()
	end
}
local MAP_COMPOSITIONS = {
	{
		text = "Viridian",
		teleport = true,
		position = {
			z = 7,
			y = 631,
			x = 632
		}
	},
	{
		text = "Pewter",
		teleport = true,
		position = {
			z = 7,
			y = 421,
			x = 631
		}
	},
	{
		text = "Cerulean",
		teleport = true,
		position = {
			z = 7,
			y = 390,
			x = 994
		}
	},
	{
		text = "Saffron",
		teleport = true,
		position = {
			z = 7,
			y = 553,
			x = 1026
		}
	},
	{
		text = "Celadon",
		teleport = true,
		position = {
			z = 7,
			y = 543,
			x = 879
		}
	},
	{
		text = "Lavender",
		teleport = true,
		position = {
			z = 7,
			y = 552,
			x = 1182
		}
	},
	{
		text = "Vermilion",
		teleport = true,
		position = {
			z = 7,
			y = 699,
			x = 1036
		}
	},
	{
		text = "Fuchsia",
		teleport = true,
		position = {
			z = 7,
			y = 863,
			x = 1094
		}
	},
	{
		text = "Cinnabar",
		teleport = true,
		position = {
			z = 7,
			y = 841,
			x = 644
		}
	},
	{
		text = "Wild Area South",
		teleport = true,
		position = {
			z = 7,
			y = 1475,
			x = 1930
		}
	},
	{
		text = "Wild Area North",
		teleport = true,
		position = {
			z = 7,
			y = 1093,
			x = 1918
		}
	},
	{
		text = "Wild Area East",
		teleport = true,
		position = {
			z = 7,
			y = 1315,
			x = 2275
		}
	},
	{
		text = "Azalea",
		teleport = true,
		position = {
			z = 7,
			y = 1623,
			x = 646
		}
	},
	{
		text = "Goldenrod",
		teleport = true,
		position = {
			z = 7,
			y = 1514,
			x = 576
		}
	},
	{
		text = "Ecruteak",
		teleport = true,
		position = {
			z = 7,
			y = 1369,
			x = 660
		}
	},
	{
		text = "Olivine",
		teleport = true,
		position = {
			z = 7,
			y = 1429,
			x = 494
		}
	},
	{
		text = "Cianwood",
		teleport = true,
		position = {
			z = 7,
			y = 1596,
			x = 367
		}
	},
	{
		text = "Violet",
		teleport = true,
		position = {
			z = 7,
			y = 1480,
			x = 740
		}
	},
	{
		text = "Butwall",
		teleport = true,
		position = {
			z = 7,
			y = 1391,
			x = 1015
		}
	},
	{
		text = "The Under",
		teleport = true,
		position = {
			z = 7,
			y = 480,
			x = 1806
		}
	},
	{
		text = "Phenac",
		teleport = true,
		position = {
			z = 7,
			y = 207,
			x = 1983
		}
	},
	{
		text = "Agate",
		teleport = true,
		position = {
			z = 7,
			y = 431,
			x = 1989
		}
	},
	{
		text = "Pyrite Town",
		teleport = true,
		position = {
			z = 7,
			y = 173,
			x = 2466
		}
	},
	{
		text = "Charicific Valley",
		position = {
			z = 7,
			y = 129,
			x = 506
		}
	},
	{
		text = "Fairy Island",
		position = {
			z = 7,
			y = 289,
			x = 427
		}
	},
	{
		text = "Green Island",
		position = {
			z = 7,
			y = 241,
			x = 757
		}
	},
	{
		text = "Wildwind Island",
		position = {
			z = 7,
			y = 197,
			x = 932
		}
	},
	{
		text = "Hurricane Island",
		position = {
			z = 7,
			y = 211,
			x = 1072
		}
	},
	{
		text = "Shell Island",
		position = {
			z = 7,
			y = 271,
			x = 1244
		}
	},
	{
		text = "Lightstorm Island",
		position = {
			z = 7,
			y = 213,
			x = 1527
		}
	},
	{
		text = "Mt. Moon",
		position = {
			z = 7,
			y = 402,
			x = 760
		}
	},
	{
		text = "Cerulean Swamp",
		position = {
			z = 7,
			y = 441,
			x = 849
		}
	},
	{
		text = "Cubone's Lair",
		position = {
			z = 7,
			y = 370,
			x = 1099
		}
	},
	{
		text = "Rock Tunel",
		position = {
			z = 7,
			y = 460,
			x = 1192
		}
	},
	{
		text = "Power Plant",
		position = {
			z = 7,
			y = 435,
			x = 1269
		}
	},
	{
		text = "Dark Light Island",
		position = {
			z = 7,
			y = 410,
			x = 1605
		}
	},
	{
		text = "Desert Island",
		position = {
			z = 7,
			y = 622,
			x = 1545
		}
	},
	{
		text = "Coliseum",
		position = {
			z = 7,
			y = 633,
			x = 512
		}
	},
	{
		text = "Jungle Island",
		position = {
			z = 7,
			y = 717,
			x = 817
		}
	},
	{
		text = "Tropical Island",
		position = {
			z = 7,
			y = 548,
			x = 777
		}
	},
	{
		text = "Diving Spot",
		position = {
			z = 7,
			y = 696,
			x = 1223
		}
	},
	{
		text = "Safari Kanto",
		position = {
			z = 7,
			y = 841,
			x = 974
		}
	},
	{
		text = "Ranch",
		position = {
			z = 7,
			y = 788,
			x = 1087
		}
	},
	{
		text = "Lost Island",
		position = {
			z = 7,
			y = 932,
			x = 1521
		}
	},
	{
		text = "Seafoam Island",
		position = {
			z = 7,
			y = 1067,
			x = 966
		}
	},
	{
		text = "Safari Johto",
		position = {
			z = 7,
			y = 1553,
			x = 292
		}
	},
	{
		text = "Moro Island",
		position = {
			z = 7,
			y = 1641,
			x = 971
		}
	},
	{
		text = "Golden Island",
		position = {
			z = 7,
			y = 1679,
			x = 467
		}
	},
	{
		text = "Kinnow Island",
		position = {
			z = 7,
			y = 1937,
			x = 865
		}
	},
	{
		text = "Enigmatic Island",
		position = {
			z = 7,
			y = 2422,
			x = 731
		}
	},
	{
		text = "Magma Island",
		position = {
			z = 7,
			y = 2353,
			x = 396
		}
	},
	{
		text = "Murcott Island",
		position = {
			z = 7,
			y = 2376,
			x = 1026
		}
	},
	{
		text = "Seafoam Island",
		position = {
			z = 7,
			y = 1067,
			x = 966
		}
	},
	{
		text = "Fairchild Island",
		position = {
			z = 7,
			y = 1940,
			x = 542
		}
	},
	{
		text = "Rock Island Mountain",
		position = {
			z = 7,
			y = 171,
			x = 1274
		}
	},
	{
		text = "Police HQ",
		position = {
			z = 7,
			y = 717,
			x = 490
		}
	},
	{
		text = "Diving Spot",
		position = {
			z = 7,
			y = 457,
			x = 519
		}
	},
	{
		text = "Diving Spot",
		position = {
			z = 7,
			y = 1494,
			x = 991
		}
	},
	{
		text = "Diving Spot",
		position = {
			z = 7,
			y = 935,
			x = 1859
		}
	},
	{
		text = "Hearted Island",
		position = {
			z = 7,
			y = 1736,
			x = 748
		}
	}
}
local COMPOSITIONS_POS_GUIDES = {}
local GUIDES = {
	Stones = {
		{
			description = "First Leaf Stone",
			color = "#4cff4c",
			position = {
				z = 7,
				y = 435,
				x = 1088
			},
			type = MAPMARK_FLAG
		},
		{
			description = "First Fire Stone",
			color = "#ff4000",
			position = {
				z = 7,
				y = 519,
				x = 1160
			},
			type = MAPMARK_FLAG
		},
		{
			description = "First Water Stone",
			color = "#389bff",
			position = {
				z = 7,
				y = 518,
				x = 903
			},
			type = MAPMARK_FLAG
		}
	},
	Eevee = {
		{
			description = "Scout Dungeon: Eeveelution",
			type = "/images/game/icons/umbreon",
			color = "white",
			position = {
				z = 7,
				y = 1998,
				x = 611
			}
		},
		{
			description = "Scout Dungeon: Eeveelution",
			type = "/images/game/icons/espeon",
			color = "white",
			position = {
				z = 7,
				y = 2368,
				x = 736
			}
		},
		{
			description = "Scout Dungeon: Eeveelution",
			type = "/images/game/icons/vaporeon",
			color = "white",
			position = {
				z = 7,
				y = 2010,
				x = 830
			}
		},
		{
			description = "Scout Dungeon: Eeveelution",
			type = "/images/game/icons/jolteon",
			color = "white",
			position = {
				z = 7,
				y = 376,
				x = 1358
			}
		},
		{
			description = "Scout Dungeon: Eeveelution",
			type = "/images/game/icons/flareon",
			color = "white",
			position = {
				z = 7,
				y = 2405,
				x = 390
			}
		}
	}
}

function init()
    -- Carrega a miniwindow diretamente no RootPanel para evitar ajuste automático aos side panels
    minimapWindow = g_ui.loadUI("minimap", modules.game_interface.getRootPanel())

	minimapWindow:setContentMinimumHeight(64)
    minimapWidget = minimapWindow:recursiveGetChildById("minimap")
    -- Ensure children like city labels are clipped to the minimap area
    if minimapWidget and minimapWidget.setClipping then
        minimapWidget:setClipping(true)
    end
    panelControls = minimapWidget:getChildById("panelControls")
    -- Garantir que o painel de controles do fullmap fique oculto ao iniciar a miniwindow
    if panelControls then panelControls:hide() end
    if minimapWidget and minimapWidget.setAlternativeWidgetsVisible then
        minimapWidget:setAlternativeWidgetsVisible(false)
    end
    minimapWidget.fullView = false

	local gameRootPanel = modules.game_interface.getRootPanel()

	g_keyboard.bindKeyPress("Alt+Left", function()
		minimapWidget:move(1, 0)
	end, gameRootPanel)
	g_keyboard.bindKeyPress("Alt+Right", function()
		minimapWidget:move(-1, 0)
	end, gameRootPanel)
	g_keyboard.bindKeyPress("Alt+Up", function()
		minimapWidget:move(0, 1)
	end, gameRootPanel)
	g_keyboard.bindKeyPress("Alt+Down", function()
		minimapWidget:move(0, -1)
	end, gameRootPanel)
	g_keyboard.bindKeyDown("Ctrl+M", toggle)
	g_keyboard.bindKeyDown("Ctrl+Tab", toggleFullMap)
	minimapWindow:setup()
	connect(g_game, {
		onGameStart = online,
		onGameEnd = offline
	})
	connect(LocalPlayer, {
		onPositionChange = updateCameraPosition
	})
	connect(g_minimap, {
		onFloorChange = onFloorChange
	})

	if g_game.isOnline() then
		online()
	end
end

function terminate()
    if g_game.isOnline() then
        saveMap()
    end

	disconnect(g_game, {
		onGameStart = online,
		onGameEnd = offline
	})
	disconnect(LocalPlayer, {
		onPositionChange = updateCameraPosition
	})
	disconnect(g_minimap, {
		onFloorChange = onFloorChange
	})

	local gameRootPanel = modules.game_interface.getRootPanel()

	g_keyboard.unbindKeyPress("Alt+Left", gameRootPanel)
	g_keyboard.unbindKeyPress("Alt+Right", gameRootPanel)
	g_keyboard.unbindKeyPress("Alt+Up", gameRootPanel)
	g_keyboard.unbindKeyPress("Alt+Down", gameRootPanel)
	g_keyboard.unbindKeyDown("Ctrl+M")
	g_keyboard.unbindKeyDown("Ctrl+Tab")
    -- Ensure any open flag window is closed to release child refs (like 'description')
    if minimapWidget and minimapWidget.destroyFlagWindow then
        minimapWidget:destroyFlagWindow()
    end

    -- If full map is active, minimapWidget may be parented to root; destroy it explicitly
    if minimapWidget and minimapWidget.fullView then
        if panelControls then panelControls:hide() end
        if minimapWidget.setAlternativeWidgetsVisible then
            minimapWidget:setAlternativeWidgetsVisible(false)
        end
        minimapWidget:destroy()
    end

    -- Destroy the miniwindow and clear Lua references
    if minimapWindow and not minimapWindow:isDestroyed() then
        if panelControls then panelControls:hide() end
        if minimapWidget and minimapWidget.setAlternativeWidgetsVisible then
            minimapWidget:setAlternativeWidgetsVisible(false)
        end
        minimapWindow:destroy()
    end
    minimapWindow = nil
    minimapWidget = nil
    panelControls = nil

    if confirmTeleport and not confirmTeleport:isDestroyed() then
        confirmTeleport:destroy()

        confirmTeleport = nil
    end

	--[[ if minimapButton then
		minimapButton:destroy()
	end ]]
end

function toggle()
	-- Se a janela foi destruída ou ainda não existe, recria
    if not minimapWindow or minimapWindow:isDestroyed() then
        -- Recria a miniwindow no RootPanel para preservar posição absoluta ao abrir/fechar
        minimapWindow = g_ui.loadUI("minimap", modules.game_interface.getRootPanel())
		minimapWindow:setContentMinimumHeight(64)
		minimapWidget = minimapWindow:recursiveGetChildById("minimap")
		if minimapWidget and minimapWidget.setClipping then
			minimapWidget:setClipping(true)
		end
		panelControls = minimapWidget and minimapWidget:getChildById("panelControls") or nil
		-- Recriação da miniwindow: manter painel do fullmap oculto
        if panelControls then panelControls:hide() end
		if minimapWidget and minimapWidget.setAlternativeWidgetsVisible then
			minimapWidget:setAlternativeWidgetsVisible(false)
		end
		minimapWidget.fullView = false
		minimapWindow:setup()
	end

    -- Não reparentar para o painel direito ao alternar; manter no RootPanel para evitar snap
	if minimapWidget and minimapWidget.fullView then
		toggleFullMap()
	end

	-- Abrindo/fechando a miniwindow: garantir que o painel do fullmap não apareça
    if panelControls then panelControls:hide() end
	if minimapWidget and minimapWidget.setAlternativeWidgetsVisible then
		minimapWidget:setAlternativeWidgetsVisible(false)
	end
	minimapWidget.fullView = false

	if minimapWindow and minimapWindow:isVisible() then
		minimapWindow:close()
	else
		minimapWindow:open()
		minimapWindow:raise()
	end
end

function onMiniWindowClose()
	if minimapWindow and minimapWindow:isVisible() then
		minimapWindow:close()
	end
end

function preload()
	loadMap(false)

	preloaded = true
end

function online()
	loadMap(not preloaded)
	updateCameraPosition()
end

function offline()
	saveMap()

	if confirmTeleport then
		confirmTeleport:destroy()

		confirmTeleport = nil
	end
end

function loadComposition()
	g_minimap.loadImage("/images/game/premap", {
		z = 7,
		y = 0,
		x = 0
	}, 0.5)

	for _, composition in pairs(MAP_COMPOSITIONS) do
		local flag = g_ui.createWidget("CityLabel")

		flag:hide()

		flag.pos = composition.position

		flag.city:setText(composition.text)
		flag.city:resizeToText()
		flag:setWidth(flag.city:getWidth() + 22)
		flag.icon:setVisible(composition.teleport)

		function flag.icon.onClick()
			local function onConfirm()
				g_game.talk(tr("h\" %s", composition.text))
			end

			confirmTeleport = displayConfirmBox(tr("Teleport"), tr("Voc\xEA realmente deseja teleportar para {%s|%s}?", "#e2bb5b", composition.text), onConfirm)
		end

		minimapWidget:insertChild(1, flag)
		minimapWidget:centerInPosition(flag, flag.pos)
		minimapWidget:addAlternativeWidget(flag, flag.pos, -1)
	end
end

function loadGuides()
    if not minimapWidget then return end

    for k, city in pairs(GUIDES) do
        for _, mark in pairs(city) do
            -- Adiciona flags das cidades/locais guiados
            minimapWidget:addFlag(mark.position, mark.type, tr(mark.description), true, tocolor(mark.color))
            -- Armazena posições para alternar visibilidade posteriormente
            table.insert(COMPOSITIONS_POS_GUIDES, mark.position)
        end
    end
end

function toggleGuides()
    if not minimapWidget then return end

    for _, pos in pairs(COMPOSITIONS_POS_GUIDES) do
        local flag = minimapWidget:getFlag(pos)
        if flag then
            flag:setVisible(minimapWidget.fullView)
        end
    end
end

function destroySearchPokemon()
    for i, pin in pairs(searchPokemon.list) do
        if pin and not pin:isDestroyed() then
            pin:destroy()
        end
    end

	searchPokemon = {
		name = "",
		list = {}
	}
end

function onSearchPokemon(name, posZ)
	if searchPokemon.name ~= name then
		destroySearchPokemon()
	end

	if not SPAWNS[name] then
		return
	end

	if not minimapWidget.fullView then
		toggleFullMap()
	end

	local posFloor = posZ or minimapWidget:getCameraPosition().z

	searchPokemon.name = name

	for i, pos in pairs(SPAWNS[name]) do
		local pin = minimapWidget[name .. i]

		if not pin then
			pin = g_ui.createWidget("PokemonLocation", minimapWidget)

			pin:setId(name .. i)

			searchPokemon.list[i] = pin
		end

		pin:setOn(posFloor == pos.z)
		pin:updateOnState(pos, posFloor)
		minimapWidget:centerInPosition(pin, {
			x = pos.x,
			y = pos.y,
			z = posFloor
		})
	end
end

function loadMap(clean)
	local clientVersion = g_game.getClientVersion()

	if clean then
		g_minimap.clean()
	end

	if otmm then
		local minimapFile = "/minimap.otmm"

		if g_resources.fileExists("/data" .. minimapFile) then
			g_minimap.loadOtmm("/data" .. minimapFile)
		elseif g_resources.fileExists(minimapFile) then
			g_minimap.loadOtmm(minimapFile)
		end
	else
		local minimapFile = "/minimap_" .. clientVersion .. ".otcm"

		if g_resources.fileExists("/data" .. minimapFile) then
			g_map.loadOtcm("/data" .. minimapFile)
		elseif g_resources.fileExists(minimapFile) then
			g_map.loadOtcm(minimapFile)
		end
	end

	loadGuides()
	toggleGuides()
	loadComposition()
	minimapWidget:load()
end

function saveMap()
	local clientVersion = g_game.getClientVersion()

	if otmm then
		local minimapFile = "/minimap.otmm"

		g_minimap.saveOtmm(minimapFile)
	else
		local minimapFile = "/minimap_" .. clientVersion .. ".otcm"

		g_map.saveOtcm(minimapFile)
	end

	minimapWidget:save()
end

function updateCameraPosition()
	local player = g_game.getLocalPlayer()

	if not player then
		return
	end

	local pos = player:getPosition()

	if not pos then
		return
	end

	if not minimapWidget:isDragging() then
		if not minimapWidget.fullView then
			oldPos = pos

			minimapWidget:setCameraPosition(player:getPosition())
		end

		minimapWidget:setCrossPosition(player:getPosition())
	end
end

-- Full minimap UI helpers
local fullMapMode = 'icons'
local suppressModeEvents = false

function setFullMapMode(mode)
  fullMapMode = (mode == 'teleports') and 'teleports' or 'icons'
  if not panelControls then return end
  local rightPanel = panelControls:getChildById('fullRightPanel')
  if not rightPanel then return end
  local icons = rightPanel:getChildById('modeIcons')
  local teleports = rightPanel:getChildById('modeTeleports')
  local filtersPanel = rightPanel:getChildById('filtersPanel')
  suppressModeEvents = true
  if icons then icons:setChecked(fullMapMode == 'icons') end
  if teleports then teleports:setChecked(fullMapMode == 'teleports') end
  suppressModeEvents = false
  -- For now the same filters are shown; later, swap contents by mode
  if filtersPanel then filtersPanel:setVisible(true) end
end

function onModeIconsChange(checked)
  if suppressModeEvents then return end
  if checked then setFullMapMode('icons') end
end

function onModeTeleportsChange(checked)
  if suppressModeEvents then return end
  if checked then setFullMapMode('teleports') end
end

function clearAllFullMapFilters()
  if not panelControls then return end
  local rightPanel = panelControls:getChildById('fullRightPanel')
  if not rightPanel then return end
  local filtersPanel = rightPanel:getChildById('filtersPanel')
  if not filtersPanel then return end
  for _, child in ipairs(filtersPanel:getChildren()) do
    if child.setChecked then child:setChecked(false) end
  end
end

local function setupFullMapUI()
  if not panelControls then return end
  local rightPanel = panelControls:getChildById('fullRightPanel')
  if not rightPanel then return end
  setFullMapMode(fullMapMode)
end

function toggleFullMap()
	if not minimapWidget.fullView then
		minimapWidget.fullView = true

		minimapWindow:hide()
		minimapWidget:setParent(modules.game_interface.getRootPanel())
		minimapWidget:fill("parent")
		minimapWidget:setAlternativeWidgetsVisible(true)
        panelControls:show()
        setupFullMapUI()
        minimapWidget:setMargin(90, 210, 140, 210)
	else
		minimapWidget.fullView = false

		minimapWidget:setParent(minimapWindow:getChildById("contentsPanel"))
		minimapWidget:fill("parent")
		minimapWindow:show()
		minimapWidget:setAlternativeWidgetsVisible(false)
        panelControls:hide()
		minimapWidget:setMargin(0)
		destroySearchPokemon()
	end

	local zoom = oldZoom or 2
	local pos = oldPos or minimapWidget:getCameraPosition()

	oldZoom = minimapWidget:getZoom()
	oldPos = minimapWidget:getCameraPosition()
	pos.z = oldFloor or pos.z

	minimapWidget:setZoom(zoom)
	minimapWidget:setCameraPosition(pos)
	toggleGuides()
end

function setupControlPanels(buttonId)
	local executeControl = controlsMinimapWidget[buttonId]

	if executeControl then
		executeControl()
	end
end

function onFloorChange(posZ)
	oldFloor = posZ

	onSearchPokemon(searchPokemon.name, posZ)
end

-- NPC minimap flags via icon
local npcFlagsByCid = {}

local function npcGetMinimapIconPath(creature)
  local iconId = creature:getIcon()
  if not iconId or iconId == NpcIconNone then
    return nil
  end
  if type(iconId) == 'string' then
    return iconId
  end
  return getIconImagePath and getIconImagePath(iconId) or nil
end

local function npcAddOrUpdateFlag(creature)
	print(creature:getName())
  if not minimapWidget then return end
  if not creature:isNpc() then return end
  local iconPath = npcGetMinimapIconPath(creature)
  if not iconPath then return end

  local cid = creature:getId()
  local prevPos = npcFlagsByCid[cid]
  if prevPos then
    minimapWidget:removeFlag(prevPos)
  end

  local pos = creature:getPosition()
  minimapWidget:addFlag(pos, iconPath, creature:getName(), true, 'white')
  print('pos', pos)
  npcFlagsByCid[cid] = pos
end

local function npcRemoveFlag(creature)
  if not minimapWidget then return end
  local cid = creature:getId()
  local prevPos = npcFlagsByCid[cid]
  if prevPos then
    minimapWidget:removeFlag(prevPos)
    npcFlagsByCid[cid] = nil
  end
end

local npcFlagController = Controller:new()

function npcFlagController:onGameStart()
  npcFlagController:registerEvents(Creature, {
    onAppear = function(creature)
      if not creature:isNpc() then return end
      npcAddOrUpdateFlag(creature)
    end,
    onIconChange = function(creature, iconId)
      if not creature:isNpc() then return end
      if not iconId or iconId == NpcIconNone then
        npcRemoveFlag(creature)
      else
        npcAddOrUpdateFlag(creature)
      end
    end,
    onDisappear = function(creature)
      npcRemoveFlag(creature)
    end
  })
end

function npcFlagController:onGameEnd()
  npcFlagsByCid = {}
end
