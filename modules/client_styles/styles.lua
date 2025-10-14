local function importTTF(filePath)
    local name = g_resources.getFileName(filePath)
    name = name:gsub("%.ttf$", ""):gsub("%.otf$", "")
    -- tamanho padrão: 16px; ajuste conforme necessário
    local ok, res = pcall(g_fonts.importTTFFont, name, filePath, 16)
    if not ok or not res then
        g_logger.error(string.format("Failed to import TTF/OTF font '%s'", filePath))
    end
end

local resourceLoaders = {
    ["otui"] = g_ui.importStyle,
    ["otfont"] = g_fonts.importFont,
    ["otps"] = g_particles.importParticle,
    ["ttf"] = importTTF,
    ["otf"] = importTTF,
}

function init()
    local device = g_platform.getDevice()
    importResources("styles", "otui", device)
    importResources("fonts", "otfont", device)
    importResources("fonts", "ttf", device)
    importResources("fonts", "otf", device)
    importResources("particles", "otps", device)

    g_mouse.loadCursors('/cursors/cursors')
    g_gameConfig.loadFonts()
end

function terminate()
end

function importResources(dir, type, device)
    local path = '/' .. dir .. '/'
    local files = g_resources.listDirectoryFiles(path)
    for _, file in pairs(files) do
        if g_resources.isFileType(file, type) then
            resourceLoaders[type](path .. file)
        end
    end

    -- try load device specific resources
    if device then
        local devicePath = g_platform.getDeviceShortName(device.type)
        if devicePath ~= "" then
            table.insertall(files, importResources(dir .. '/' .. devicePath, type))
        end
        local osPath = g_platform.getOsShortName(device.os)
        if osPath ~= "" then
            table.insertall(files, importResources(dir .. '/' .. osPath, type))
        end
        return
    end
    return files
end

function reloadParticles()
    g_particles.terminate()
    local device = g_platform.getDevice()
    importResources("particles", "otps", device)
end
