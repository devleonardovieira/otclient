-- chunkname: @/modules/game_minimap/minimap.lua

minimapWidget = nil
minimapButton = nil
minimapWindow = nil
preloaded = false
mapPrepared = false
otmmCachePrepared = false
minimapPreloadStats = {
	cacheBlocks = 0,
	importedBlocks = 0,
	usedOtmm = false,
	cacheReady = false,
	source = "none"
}
oldZoom = nil
oldPos = nil
oldFloor = nil
panelControls = nil
confirmTeleport = nil
cameraSmoothEvent = nil

local DEFAULT_MINIMAP_ZOOM_MAX = 5
local CAMERA_SMOOTH_TICK_MS = 16

local function stopCameraSmoothLoop()
	if cameraSmoothEvent then
		removeEvent(cameraSmoothEvent)
		cameraSmoothEvent = nil
	end
end

local function startCameraSmoothLoop()
	if cameraSmoothEvent then
		return
	end

	cameraSmoothEvent = cycleEvent(function()
		if not g_game.isOnline() or not minimapWidget or not minimapWidget.setCameraOffset then
			return
		end

		local player = g_game.getLocalPlayer()
		if not player or not player.isWalking then
			return
		end

		if player:isWalking() then
			updateCameraPosition()
			return
		end

		local cameraOffset = minimapWidget.getCameraOffset and minimapWidget:getCameraOffset() or nil
		if cameraOffset and (cameraOffset.x ~= 0 or cameraOffset.y ~= 0) then
			updateCameraPosition()
		end
	end, CAMERA_SMOOTH_TICK_MS)
end

local function getMinimapZoomMin()
	if minimapWidget and minimapWidget.getMaxZoom then
		local maxZoom = minimapWidget:getMaxZoom()
		if type(maxZoom) == 'number' then
			return maxZoom - 1
		end
	end

	return DEFAULT_MINIMAP_ZOOM_MAX - 1
end

local function getMinimapZoomMax()
	if minimapWidget and minimapWidget.getMaxZoom then
		local maxZoom = minimapWidget:getMaxZoom()
		if type(maxZoom) == 'number' then
			return maxZoom
		end
	end

	return DEFAULT_MINIMAP_ZOOM_MAX
end

local function clampMinimapZoom(zoom)
	local minZoom = getMinimapZoomMin()
	local maxZoom = getMinimapZoomMax()
	zoom = tonumber(zoom) or minZoom
	if zoom <= minZoom then
		return minZoom
	end
	if zoom >= maxZoom then
		return maxZoom
	end
	return zoom
end

local function applyMinimapCloseZoomRange()
	if not minimapWidget then
		return
	end

	local maxZoom = getMinimapZoomMax()
	local minZoom = maxZoom - 1

	-- Lua binding has a legacy typo (setMixZoom), keep both for compatibility.
	if minimapWidget.setMixZoom then
		minimapWidget:setMixZoom(minZoom)
	elseif minimapWidget.setMinZoom then
		minimapWidget:setMinZoom(minZoom)
	end

	if minimapWidget.setMaxZoom then
		minimapWidget:setMaxZoom(maxZoom)
	end

	minimapWidget:setZoom(clampMinimapZoom(minimapWidget:getZoom()))
end

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
		minimapWidget:setZoom(clampMinimapZoom(minimapWidget:getZoom() + 1))
	end,
	zoomOut = function()
		minimapWidget:setZoom(clampMinimapZoom(minimapWidget:getZoom() - 1))
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
	applyMinimapCloseZoomRange()
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

	stopCameraSmoothLoop()

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
		applyMinimapCloseZoomRange()
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
		loadMap(false)
		updateCameraPosition()
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

local function countCachedMinimapBlocks()
	local files = g_resources.listDirectoryFiles('/minimap') or {}
	local count = 0
	for _, file in pairs(files) do
		if string.match(file, '^minimap_%d+_%d+%.mmz$') then
			count = count + 1
		end
	end

	return count
end

function getPreloadStats()
	return minimapPreloadStats
end

function getPreloadSummary()
	local stats = minimapPreloadStats
	if stats.usedOtmm then
		return tr("Minimap pronto: %d blocos em cache (+%d importados de OTMM) [%s]", stats.cacheBlocks, stats.importedBlocks, stats.source or 'unknown')
	end

	if stats.cacheReady then
		return tr("Minimap pronto: %d blocos em cache [%s]", stats.cacheBlocks, stats.source or 'cache')
	end

	return tr("Minimap pronto: cache vazio [%s]", stats.source or 'none')
end

local function prepareOtmmCache()
	if otmmCachePrepared then
		return minimapPreloadStats
	end

	otmmCachePrepared = true
	local cacheBefore = countCachedMinimapBlocks()
	minimapPreloadStats = {
		cacheBlocks = cacheBefore,
		importedBlocks = 0,
		usedOtmm = false,
		cacheReady = cacheBefore > 0,
		source = "cache"
	}

	if not g_minimap.importOtmm then
		return minimapPreloadStats
	end

	local otmmFile = nil
	local otmmCandidates = {
		'/data/minimap.otmm',
		'data/minimap.otmm',
		'/data/minimap/minimap.otmm',
		'data/minimap/minimap.otmm',
		'/data/world/minimap.otmm',
		'data/world/minimap.otmm',
		'/data/world/minimap/minimap.otmm',
		'data/world/minimap/minimap.otmm',
		'/mods/game_minimap/minimap.otmm',
		'mods/game_minimap/minimap.otmm',
		'/minimap.otmm',
		'minimap.otmm',
		'/modules/game_minimap/minimap.otmm',
		'modules/game_minimap/minimap.otmm'
	}

	for _, candidate in ipairs(otmmCandidates) do
		if g_resources.fileExists(candidate) then
			otmmFile = candidate
			break
		end
	end

	if not otmmFile then
		g_logger.warning('OTMM not found in known paths; minimap will rely on existing /minimap .mmz cache')
		return minimapPreloadStats
	end

	-- Force full rebuild from OTMM to avoid stale/partial .mmz cache.
	local importedOk = g_minimap.importOtmm(otmmFile, true)
	local cacheAfter = countCachedMinimapBlocks()

	minimapPreloadStats.cacheBlocks = cacheAfter
	minimapPreloadStats.importedBlocks = math.max(cacheAfter - cacheBefore, 0)
	minimapPreloadStats.usedOtmm = importedOk
	minimapPreloadStats.cacheReady = cacheAfter > 0
	minimapPreloadStats.source = otmmFile

	if not importedOk then
		g_logger.warning('Failed to import OTMM from: ' .. tostring(otmmFile))
	elseif cacheAfter <= 0 then
		g_logger.warning('OTMM import finished but cache is empty: ' .. tostring(otmmFile))
	end

	return minimapPreloadStats
end

function preload()
	if preloaded then
		return getPreloadSummary()
	end

	prepareOtmmCache()
	local ramPreloadReady = false
	if g_minimap and g_minimap.preloadAll then
		local ok, err = pcall(function()
			g_minimap.preloadAll(false, true)
		end)

		if not ok then
			g_logger.warning('Failed to preload minimap blocks into RAM: ' .. tostring(err))
		else
			ramPreloadReady = true
		end
	end

	loadMap(false)

	preloaded = true
	local summary = getPreloadSummary()
	if ramPreloadReady then
		return summary .. ' | ' .. tr('RAM cache warmed')
	end

	return summary
end

function online()
	loadMap(not preloaded)
	startCameraSmoothLoop()
	updateCameraPosition()
end

function offline()
	stopCameraSmoothLoop()
	if minimapWidget and minimapWidget.setCameraOffset then
		minimapWidget:setCameraOffset({ x = 0, y = 0 })
	end
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

			confirmTeleport = displayConfirmBox(tr("Teleport"),
				tr("Voc\xEA realmente deseja teleportar para {%s|%s}?", "#e2bb5b", composition.text), onConfirm)
		end

		minimapWidget:insertChild(1, flag)
		minimapWidget:centerInPosition(flag, flag.pos)
		-- sempre visível no full map (qualquer zoom)
		minimapWidget:addAlternativeWidget(flag, flag.pos, getMinimapZoomMin(), getMinimapZoomMax())
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
	if clean then
		g_minimap.clean()
		mapPrepared = false
	end

	if not mapPrepared then
		loadGuides()
		loadComposition()
		minimapWidget:load()
		mapPrepared = true
	end

	toggleGuides()
end

function saveMap()
	g_minimap.save()

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
			oldFloor = pos.z

			if minimapWidget.setCameraOffset then
				local walkOffset = { x = 0, y = 0 }
				if player.isWalking and player.getWalkOffset and player:isWalking() then
					local playerWalkOffset = player:getWalkOffset()
					if playerWalkOffset then
						walkOffset = {
							x = playerWalkOffset.x or 0,
							y = playerWalkOffset.y or 0
						}
					end
				end
				minimapWidget:setCameraOffset(walkOffset)
			end

			minimapWidget:setCameraPosition(pos)
			minimapWidget:setCrossPosition(pos, true)
		elseif minimapWidget.setCameraOffset then
			minimapWidget:setCameraOffset({ x = 0, y = 0 })
			minimapWidget:setCrossPosition(pos)
		end

	elseif minimapWidget.setCameraOffset then
		minimapWidget:setCameraOffset({ x = 0, y = 0 })
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
	-- salva estado atual
	oldZoom = clampMinimapZoom(minimapWidget:getZoom())
	oldPos  = minimapWidget:getCameraPosition()

	if not minimapWidget.fullView then
		minimapWidget.fullView = true

		minimapWindow:hide()
		minimapWidget:setParent(modules.game_interface.getRootPanel())
		minimapWidget:fill("parent")
		minimapWidget:setAlternativeWidgetsVisible(true)
		if panelControls then panelControls:show() end
		setupFullMapUI()
		minimapWidget:setMargin(90, 210, 140, 210)
	else
		minimapWidget.fullView = false

		minimapWidget:setParent(minimapWindow:getChildById("contentsPanel"))
		minimapWidget:fill("parent")
		minimapWindow:show()
		minimapWidget:setAlternativeWidgetsVisible(false)
		if panelControls then panelControls:hide() end
		minimapWidget:setMargin(0)
		destroySearchPokemon()
	end

	-- aplica estado desejado
	local pos = oldPos or minimapWidget:getCameraPosition()
	if minimapWidget.fullView then
		-- Entrando no full map: respeita piso manual selecionado, se houver.
		pos.z = oldFloor or pos.z
	else
		-- Saindo do full map: volta para o piso real do player para evitar andar incorreto.
		local player = g_game.getLocalPlayer()
		local playerPos = player and player:getPosition() or nil
		if playerPos then
			pos.z = playerPos.z
			oldFloor = playerPos.z
		else
			pos.z = oldFloor or pos.z
		end
	end

	minimapWidget:setZoom(clampMinimapZoom(oldZoom or getMinimapZoomMin()))
	if minimapWidget.setCameraOffset then
		minimapWidget:setCameraOffset({ x = 0, y = 0 })
	end
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
