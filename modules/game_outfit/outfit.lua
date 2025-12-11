-- chunkname: @/modules/game_outfit/outfit.lua

local OutfitWindow, outfits
local maxperlist = 20
local currentpage = 1
local maxpages = 1
local selectedOutfit, selectedWidget, currentClotheButtonBox, currentColorBox
local colorBoxes = {}

-- Normaliza qualquer valor de outfit para a tabela esperada pelo binding C++
local function toOutfitTable(o)
  if type(o) == 'table' then
    return {
      type = o.type or o.id or 0,
      auxType = o.auxType or o.auxId or 0,
      addons = o.addons or 0,
      head = o.head or 0,
      body = o.body or 0,
      legs = o.legs or 0,
      feet = o.feet or 0,
      mount = o.mount or 0,
      familiar = o.familiar or 0,
      wings = o.wings or 0,
      effects = o.effects or 0,
      auras = o.auras or 0,
      shaders = o.shaders or ""
    }
  end
  -- Quando vier um userdata incorreto, retorna uma tabela vazia segura
  return { type = 0, auxType = 0, addons = 0, head = 0, body = 0, legs = 0, feet = 0 }
end

ignoreNextOutfitWindow = 0
direction = 2

local ADDON_SETS = {
	{
		1
	},
	{
		2
	},
	{
		1,
		2
	},
	{
		3
	},
	{
		1,
		3
	},
	{
		2,
		3
	},
	{
		1,
		2,
		3
	}
}

function init()
	connect(g_game, {
		onOpenOutfitWindow = create,
		onGameEnd = destroy
	})
end

function terminate()
	disconnect(g_game, {
		onOpenOutfitWindow = create,
		onGameEnd = destroy
	})
	destroy()
end

function create(creatureOutfit, outfitList, creatureMount, mountList)
	if ignoreNextOutfitWindow and g_clock.millis() < ignoreNextOutfitWindow + 1000 then
		return
	end

	if OutfitWindow and not OutfitWindow:isHidden() then
		return
	end

	selectedOutfit = creatureOutfit
	OutfitWindow = g_ui.displayUI("outfitwindow")

	OutfitWindow:onVisibilityChange(true)

	outfits = outfitList
	maxpages = math.ceil(#outfitList / maxperlist)

    for num, out in ipairs(outfitList) do
		if selectedOutfit.type == out[1] then
			currentpage = math.ceil(num / maxperlist)

			OutfitWindow:getChildById("outfitPanel"):getChildById("confirm"):setEnabled(out[3])
            OutfitWindow:getChildById("outfitPanel"):getChildById("outfit"):setOutfit(toOutfitTable(selectedOutfit))
            OutfitWindow:getChildById("outfitPanel"):getChildById("name"):setText(out[2])

			break
		end
	end

	drawOutfitList()
	updatePageButtons()

	currentClotheButtonBox = OutfitWindow:getChildById("outfitPanel"):getChildById("template"):getChildById("head")
	OutfitWindow:getChildById("outfitPanel"):getChildById("template"):getChildById("head").onCheckChange = onClotheCheckChange
	OutfitWindow:getChildById("outfitPanel"):getChildById("template"):getChildById("primary").onCheckChange = onClotheCheckChange
	OutfitWindow:getChildById("outfitPanel"):getChildById("template"):getChildById("secondary").onCheckChange = onClotheCheckChange
	OutfitWindow:getChildById("outfitPanel"):getChildById("template"):getChildById("detail").onCheckChange = onClotheCheckChange

	for j = 0, 6 do
		for i = 0, 18 do
			local colorBox = g_ui.createWidget("ColorBox", OutfitWindow:getChildById("outfitPanel"):getChildById("colorBoxPanel"))
			local outfitColor = getOutfitColor(j * 19 + i)

			colorBox:setImageColor(outfitColor)
			colorBox:setId("colorBox" .. j * 19 + i)

			colorBox.colorId = j * 19 + i

			if j * 19 + i == selectedOutfit.head then
				currentColorBox = colorBox

				colorBox:setChecked(true)
			end

			colorBox.onCheckChange = onColorCheckChange
			colorBoxes[#colorBoxes + 1] = colorBox
		end
	end
end

function drawOutfitList()
	OutfitWindow:getChildById("pagePanel"):getChildById("page"):setText(tr("%s de %s", string.format("%02d", currentpage), string.format("%02d", maxpages)))
	OutfitWindow:getChildById("outfitList"):destroyChildren()

	for i = 1, 1 do
		for num, out in ipairs(outfits) do
			if math.ceil(num / maxperlist) == currentpage then
                local ot = {
                    type = out[1],
                    head = selectedOutfit.head,
                    body = selectedOutfit.body,
                    legs = selectedOutfit.legs,
                    feet = selectedOutfit.feet,
                    addons = out[3]
                }
                local widget = g_ui.createWidget("OutfitBox", OutfitWindow:getChildById("outfitList"))

                widget.outfit:setOutfit(toOutfitTable(ot))

                widget.ot = ot

				widget:setTooltip(out[2])
				widget.lock:setVisible(not out[3])

				if selectedOutfit.type == out[1] then
					selectedWidget = widget

					widget:focus()
				end

                function widget.onClick()
                    selectedOutfit = ot
                    selectedWidget = widget

                    OutfitWindow:getChildById("outfitPanel"):getChildById("confirm"):setEnabled(out[3])
                    OutfitWindow:getChildById("outfitPanel"):getChildById("outfit"):setOutfit(toOutfitTable(ot))
                    OutfitWindow:getChildById("outfitPanel"):getChildById("name"):setText(out[2])
                end
            end
        end
    end
end

local movementState = false -- guarda o estado já que não existe isAnimating()

function setOutfitAnimation(button)
    movementState = not movementState  -- inverte estado

    -- atualiza botão
    button:setOn(movementState)

    -- pega o creature dentro do UICreature outfit
    local creature = OutfitWindow.outfitPanel.outfit:getCreature()
    if creature then
        -- aplica movimento
        creature:setStaticWalking(movementState and 1000 or 0)
    end
end


function setOutfitRotate()
	direction = (direction + 1) % 4

	OutfitWindow.outfitPanel.outfit:setDirection(direction)
end

function randomize()
	local outfitTemplate = {
		OutfitWindow:getChildById("outfitPanel"):getChildById("template"):getChildById("head"),
		OutfitWindow:getChildById("outfitPanel"):getChildById("template"):getChildById("primary"),
		OutfitWindow:getChildById("outfitPanel"):getChildById("template"):getChildById("secondary"),
		OutfitWindow:getChildById("outfitPanel"):getChildById("template"):getChildById("detail")
	}

	for i = 1, #outfitTemplate do
		outfitTemplate[i]:setChecked(true)
		colorBoxes[math.random(1, #colorBoxes)]:setChecked(true)
		outfitTemplate[i]:setChecked(false)
	end

	outfitTemplate[1]:setChecked(true)
end

function onClotheCheckChange(clotheButtonBox)
	if clotheButtonBox == currentClotheButtonBox then
		clotheButtonBox.onCheckChange = nil

		clotheButtonBox:setChecked(true)

		clotheButtonBox.onCheckChange = onClotheCheckChange
	else
		currentClotheButtonBox.onCheckChange = nil

		currentClotheButtonBox:setChecked(false)

		currentClotheButtonBox.onCheckChange = onClotheCheckChange
		currentClotheButtonBox = clotheButtonBox

		local colorId = 0

		if currentClotheButtonBox:getId() == "head" then
			colorId = selectedOutfit.head or 0
		elseif currentClotheButtonBox:getId() == "primary" then
			colorId = selectedOutfit.body or 0
		elseif currentClotheButtonBox:getId() == "secondary" then
			colorId = selectedOutfit.legs or 0
		elseif currentClotheButtonBox:getId() == "detail" then
			colorId = selectedOutfit.feet or 0
		end

		local panel = OutfitWindow:getChildById("outfitPanel"):getChildById("colorBoxPanel")
		local target = panel:recursiveGetChildById("colorBox" .. tostring(colorId or 0))
		if target then
			target:setChecked(true)
		end
	end
end

function onColorCheckChange(colorBox)
	if colorBox == currentColorBox then
		colorBox.onCheckChange = nil

		colorBox:setChecked(true)

		colorBox.onCheckChange = onColorCheckChange
	else
		-- Protege contra estado inicial sem seleção anterior
		if currentColorBox then
			currentColorBox.onCheckChange = nil
			currentColorBox:setChecked(false)
			currentColorBox.onCheckChange = onColorCheckChange
		end

		currentColorBox = colorBox

		if currentClotheButtonBox:getId() == "head" then
			selectedOutfit.head = currentColorBox.colorId
		elseif currentClotheButtonBox:getId() == "primary" then
			selectedOutfit.body = currentColorBox.colorId
		elseif currentClotheButtonBox:getId() == "secondary" then
			selectedOutfit.legs = currentColorBox.colorId
		elseif currentClotheButtonBox:getId() == "detail" then
			selectedOutfit.feet = currentColorBox.colorId
		end

        currentColorBox:setBorderColor(getOutfitColor(currentColorBox.colorId))
        OutfitWindow:getChildById("outfitPanel"):getChildById("outfit"):setOutfit(toOutfitTable(selectedOutfit))

        for i, child in ipairs(OutfitWindow:getChildById("outfitList"):getChildren()) do
            local out = child.ot

			out.head = selectedOutfit.head
			out.body = selectedOutfit.body
			out.legs = selectedOutfit.legs
			out.feet = selectedOutfit.feet

            child.outfit:setOutfit(toOutfitTable(out))
        end
    end
end

function destroy()
    if OutfitWindow then
        OutfitWindow:onVisibilityChange(false)

        -- Limpa callbacks dos itens da lista de outfits
        local list = OutfitWindow:getChildById("outfitList")
        if list then
            for _, child in ipairs(list:getChildren()) do
                child.onClick = nil
            end
        end

        -- Limpa callbacks dos botões de roupa (template)
        local panel = OutfitWindow:getChildById("outfitPanel")
        if panel then
            local template = panel:getChildById("template")
            if template then
                local head = template:getChildById("head")
                local primary = template:getChildById("primary")
                local secondary = template:getChildById("secondary")
                local detail = template:getChildById("detail")
                if head then head.onCheckChange = nil end
                if primary then primary.onCheckChange = nil end
                if secondary then secondary.onCheckChange = nil end
                if detail then detail.onCheckChange = nil end
            end

            -- Limpa callbacks das color boxes
            local colorPanel = panel:getChildById("colorBoxPanel")
            if colorPanel then
                for _, box in ipairs(colorPanel:getChildren()) do
                    box.onCheckChange = nil
                end
            end
        end

        OutfitWindow:destroy()

		OutfitWindow = nil
        selectedOutfit = nil
        selectedWidget = nil
        currentColorBox = nil
        currentClotheButtonBox = nil
        colorBoxes = {}
        addons = {}
    end
end

function accept()
	if not selectedOutfit then
		return
	end

	selectedOutfit.addons = OutfitWindow:getChildById("outfitPanel"):getChildById("addon"):isChecked() and 1 or 0

	g_game.changeOutfit(selectedOutfit)
	destroy()
end

function firstPage()
	currentpage = 1

	updatePageButtons()
	drawOutfitList()
end

function lastPage()
	currentpage = maxpages

	updatePageButtons()
	drawOutfitList()
end

function prevPage()
	currentpage = math.max(1, currentpage - 1)

	updatePageButtons()
	drawOutfitList()
end

function nextPage()
	currentpage = math.min(maxpages, currentpage + 1)

	updatePageButtons()
	drawOutfitList()
end

function updatePageButtons()
	if maxpages == 1 then
		OutfitWindow:getChildById("pagePanel"):getChildById("firstPage"):disable()
		OutfitWindow:getChildById("pagePanel"):getChildById("prevPage"):disable()
		OutfitWindow:getChildById("pagePanel"):getChildById("nextPage"):disable()
		OutfitWindow:getChildById("pagePanel"):getChildById("lastPage"):disable()
	elseif currentpage == maxpages then
		OutfitWindow:getChildById("pagePanel"):getChildById("firstPage"):enable()
		OutfitWindow:getChildById("pagePanel"):getChildById("prevPage"):enable()
		OutfitWindow:getChildById("pagePanel"):getChildById("nextPage"):disable()
		OutfitWindow:getChildById("pagePanel"):getChildById("lastPage"):disable()
	elseif currentpage == 1 then
		OutfitWindow:getChildById("pagePanel"):getChildById("firstPage"):disable()
		OutfitWindow:getChildById("pagePanel"):getChildById("prevPage"):disable()
		OutfitWindow:getChildById("pagePanel"):getChildById("nextPage"):enable()
		OutfitWindow:getChildById("pagePanel"):getChildById("lastPage"):enable()
	else
		OutfitWindow:getChildById("pagePanel"):getChildById("firstPage"):enable()
		OutfitWindow:getChildById("pagePanel"):getChildById("prevPage"):enable()
		OutfitWindow:getChildById("pagePanel"):getChildById("nextPage"):enable()
		OutfitWindow:getChildById("pagePanel"):getChildById("lastPage"):enable()
	end
end
