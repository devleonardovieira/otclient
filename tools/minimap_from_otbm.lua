-- Generate minimap .mmz cache blocks from an OTBM map.
-- Requires client built with FRAMEWORK_EDITOR (g_map.loadOtbm available).
--
-- Usage in OTClient terminal:
--   dofile('tools/minimap_from_otbm.lua')
--   buildMinimapFromOtbm('D:/maps/world.otbm')
--   buildMinimapFromOtbm('D:/maps/world.otbm', true) -- assume OTBM ids are client ids
--   buildMinimapOtmmFromOtbm('D:/maps/world.otbm', 'data/minimap.otmm')
--   buildMinimapOtmmFromOtbm('D:/maps/world.otbm', 'data/minimap.otmm', nil, 'D:/server/data/items/items.otb')
--   buildMinimapOtmmFromOtbm('D:/maps/world.otbm', 'data/minimap.otmm', nil, nil, true)
--   buildMinimapOtmmFromLiveCache('data/minimap.otmm')

local function assertEditorBindings()
  if not g_map or not g_map.loadOtbm then
    error('g_map.loadOtbm is unavailable. Build with TOGGLE_FRAMEWORK_EDITOR=ON')
  end

  if not g_minimap or not g_minimap.save then
    error('g_minimap bindings are unavailable')
  end

  if not g_things or not g_things.isOtbLoaded or not g_things.loadOtb then
    error('g_things OTB bindings are unavailable. Build with TOGGLE_FRAMEWORK_EDITOR=ON')
  end
end

local function normalizeReadableFilePath(path, label)
  assert(type(path) == 'string' and path ~= '', (label or 'path') .. ' must be a non-empty string')

  local normalized = string.gsub(path, '\\', '/')

  -- Absolute Windows path (e.g. D:/maps/world.otbm) needs mounting into PHYSFS.
  if string.match(normalized, '^%a:/') then
    local dir, file = string.match(normalized, '^(.*)/([^/]+)$')
    if not dir or not file then
      error((label or 'path') .. ' is invalid: ' .. tostring(path))
    end

    if not g_resources.addSearchPath(dir, true) then
      error('Unable to add search path for ' .. (label or 'file') .. ': ' .. dir)
    end

    return '/' .. file
  end

  -- Keep virtual root paths unchanged.
  if string.sub(normalized, 1, 1) == '/' then
    return normalized
  end

  -- Force project-root relative path instead of /tools/<file>.
  return '/' .. normalized
end

local function clearMinimapCacheFiles()
  if not (g_minimap and g_minimap.cacheBlockFileName) then
    g_logger.warning('Minimap generator: cacheBlockFileName binding unavailable; skipping .mmz deletion to avoid stale-index file-not-found errors')
    return
  end

  local files = g_resources.listDirectoryFiles('/minimap') or {}
  for _, fileName in ipairs(files) do
    if string.match(fileName, '^minimap_%d+_%d+%.mmz$') then
      g_resources.deleteFile('/minimap/' .. fileName)
    end
  end

  -- Keep internal saved-block index in sync after deleting cache files.
  if g_minimap and g_minimap.cacheBlockFileName then
    g_minimap.cacheBlockFileName()
  end
end

local function ensureItemResolver(otbPath, useClientIds)
  if g_map and g_map.setAssumeOtbmClientIds then
    g_map.setAssumeOtbmClientIds(false)
  end

  if g_things.isOtbLoaded() then
    return 'otb'
  end

  if type(otbPath) == 'string' and otbPath ~= '' then
    local resolvedOtbPath = normalizeReadableFilePath(otbPath, 'otbPath')
    g_logger.info('Minimap generator: loading OTB ' .. resolvedOtbPath)
    g_things.loadOtb(resolvedOtbPath)
  end

  if g_things.isOtbLoaded() then
    return 'otb'
  end

  if useClientIds then
    if g_map and g_map.setAssumeOtbmClientIds then
      g_logger.warning('Minimap generator: OTB missing; enabling raw client-id mode for OTBM parsing')
      g_map.setAssumeOtbmClientIds(true)
      return 'clientIds'
    end

    error('This client build does not expose g_map.setAssumeOtbmClientIds. Rebuild the client first.')
  end

  error('items.otb is required in OTB mode. Pass otbPath or set useClientIds=true.')
end

function buildMinimapFromOtbm(otbmPath, otbPath, useClientIds)
  assert(type(otbmPath) == 'string' and otbmPath ~= '', 'otbmPath must be a non-empty string')
  assertEditorBindings()
  if type(otbPath) == 'boolean' and useClientIds == nil then
    useClientIds = otbPath
    otbPath = nil
  end

  local resolvedOtbmPath = normalizeReadableFilePath(otbmPath, 'otbmPath')

  local resolver = ensureItemResolver(otbPath, useClientIds == true)
  g_logger.info('Minimap generator: item resolver = ' .. resolver)

  g_logger.info('Minimap generator: cleaning current map/minimap state')
  g_map.clean()
  g_minimap.clean()
  clearMinimapCacheFiles()

  g_logger.info('Minimap generator: loading OTBM ' .. resolvedOtbmPath)
  g_map.loadOtbm(resolvedOtbmPath)

  local tiles = g_map.getTiles and g_map.getTiles() or {}
  if not tiles or #tiles == 0 then
    error('OTBM load produced 0 tiles. Check OTB path/version compatibility.')
  end

  g_logger.info('Minimap generator: saving mmz blocks')
  g_minimap.save()
  g_logger.info('Minimap generator: done')
end

local OTMM_SIGNATURE = 0x4D4D544F
local OTMM_VERSION = 1
local INVALID_POS_X = 0xFFFF
local INVALID_POS_Y = 0xFFFF
local INVALID_POS_Z = 0xFF

local function packU8(v)
  return string.char(v % 256)
end

local function packU16(v)
  local lo = v % 256
  local hi = math.floor(v / 256) % 256
  return string.char(lo, hi)
end

local function packU32(v)
  local b1 = v % 256
  local b2 = math.floor(v / 256) % 256
  local b3 = math.floor(v / 65536) % 256
  local b4 = math.floor(v / 16777216) % 256
  return string.char(b1, b2, b3, b4)
end

local function readU8(s, pos)
  return string.byte(s, pos) or 0
end

local function readU16(s, pos)
  local b1 = string.byte(s, pos) or 0
  local b2 = string.byte(s, pos + 1) or 0
  return b1 + (b2 * 256)
end

local function parseMmzBlock(fileName, raw)
  if not raw or #raw < 12 then
    return nil, 'invalid or truncated block: ' .. tostring(fileName)
  end

  local x = readU16(raw, 1)
  local y = readU16(raw, 3)
  local z = readU8(raw, 5)
  local len = readU16(raw, 6)
  local dataStart = 8
  local dataEnd = dataStart + len - 1
  if dataEnd > #raw then
    return nil, 'payload out of bounds: ' .. tostring(fileName)
  end

  local tailSize = #raw - dataEnd
  if tailSize >= 5 then
    local endX = readU16(raw, dataEnd + 1)
    local endY = readU16(raw, dataEnd + 3)
    local endZ = readU8(raw, dataEnd + 5)
    local isLegacyZero = (endX == 0 and endY == 0 and endZ == 0)
    local isInvalidPos = (endX == INVALID_POS_X and endY == INVALID_POS_Y and endZ == INVALID_POS_Z)
    if not isLegacyZero and not isInvalidPos then
      return nil, 'invalid tail marker: ' .. tostring(fileName)
    end
  elseif tailSize ~= 0 then
    return nil, 'invalid trailer size (' .. tostring(tailSize) .. '): ' .. tostring(fileName)
  end

  local idx = 0
  local mz, mindex = string.match(fileName, '^minimap_(%d+)_(%d+)%.mmz$')
  if mz and mindex then
    idx = tonumber(mindex) or 0
  else
    idx = math.floor(y / 32) * math.floor(65536 / 32) + math.floor(x / 32)
  end

  return {
    file = fileName,
    x = x,
    y = y,
    z = z,
    index = idx,
    payload = string.sub(raw, dataStart, dataEnd)
  }
end

function packMmzToOtmm(mmzDir, outputPath, description)
  mmzDir = mmzDir or '/minimap'
  outputPath = outputPath or 'data/minimap.otmm'
  description = description or 'Generated from mmz cache'

  local files = g_resources.listDirectoryFiles(mmzDir) or {}
  local blocks = {}
  local skipped = 0

  for _, fileName in ipairs(files) do
    if string.match(fileName, '^minimap_%d+_%d+%.mmz$') then
      local raw = g_resources.readFileContents(mmzDir .. '/' .. fileName)
      local block, err = parseMmzBlock(fileName, raw)
      if block then
        table.insert(blocks, block)
      else
        skipped = skipped + 1
        g_logger.warning('MMZ skip: ' .. tostring(err))
      end
    end
  end

  if #blocks == 0 then
    error('No valid mmz blocks found in ' .. tostring(mmzDir))
  end

  table.sort(blocks, function(a, b)
    if a.z ~= b.z then return a.z < b.z end
    if a.index ~= b.index then return a.index < b.index end
    return a.file < b.file
  end)

  local desc = description or ''
  local headerParts = {}
  local startOffset = 4 + 2 + 2 + 4 + 2 + #desc
  table.insert(headerParts, packU32(OTMM_SIGNATURE))
  table.insert(headerParts, packU16(startOffset))
  table.insert(headerParts, packU16(OTMM_VERSION))
  table.insert(headerParts, packU32(0))
  table.insert(headerParts, packU16(#desc))
  table.insert(headerParts, desc)

  local bodyParts = {}
  for _, b in ipairs(blocks) do
    table.insert(bodyParts, packU16(b.x))
    table.insert(bodyParts, packU16(b.y))
    table.insert(bodyParts, packU8(b.z))
    table.insert(bodyParts, packU16(#b.payload))
    table.insert(bodyParts, b.payload)
  end

  table.insert(bodyParts, packU16(INVALID_POS_X))
  table.insert(bodyParts, packU16(INVALID_POS_Y))
  table.insert(bodyParts, packU8(INVALID_POS_Z))

  local output = table.concat(headerParts) .. table.concat(bodyParts)

  local oldWriteDir = g_resources.getWriteDir and g_resources.getWriteDir() or ""
  local workDir = g_resources.getWorkDir and g_resources.getWorkDir() or oldWriteDir
  local switchedWriteDir = false
  if workDir ~= "" and oldWriteDir ~= workDir then
    switchedWriteDir = g_resources.setWriteDir(workDir)
  end

  local function ensureDir(path)
    local acc = ''
    for part in string.gmatch(path, '[^/]+') do
      if acc == '' then
        acc = part
      else
        acc = acc .. '/' .. part
      end
      g_resources.makeDir(acc)
    end
  end

  local slashPos = string.match(outputPath, '^.*()/')
  if slashPos and slashPos > 1 then
    local dir = string.sub(outputPath, 1, slashPos - 1)
    ensureDir(dir)
  end

  local ok = g_resources.writeFileContents(outputPath, output)

  if switchedWriteDir and oldWriteDir ~= "" then
    g_resources.setWriteDir(oldWriteDir)
  end

  if not ok then
    error('Failed to write OTMM file to ' .. tostring(outputPath))
  end

  g_logger.info(string.format('Packed %d blocks into %s (skipped=%d)', #blocks, outputPath, skipped))
  return outputPath
end

function buildMinimapOtmmFromOtbm(otbmPath, outputPath, description, otbPath, useClientIds)
  if type(otbPath) == 'boolean' then
    useClientIds = otbPath
    otbPath = nil
  end

  buildMinimapFromOtbm(otbmPath, otbPath, useClientIds)
  return packMmzToOtmm('/minimap', outputPath or 'data/minimap.otmm', description or ('Generated from ' .. tostring(otbmPath)))
end

function buildMinimapOtmmFromOtbmClientIds(otbmPath, outputPath, description)
  return buildMinimapOtmmFromOtbm(otbmPath, outputPath, description, nil, true)
end

-- Generates OTMM from the current minimap cache received while playing online.
-- This path does not require OTB/OTBM and is suitable for modern protocol/appearances setups.
function buildMinimapOtmmFromLiveCache(outputPath, description)
  if g_minimap and g_minimap.save then
    g_minimap.save() -- flush current in-memory blocks to /minimap/*.mmz
  end
  return packMmzToOtmm('/minimap', outputPath or 'data/minimap.otmm', description or 'Generated from live minimap cache')
end
