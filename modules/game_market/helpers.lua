-- chunkname: @/modules/game_market/helpers.lua

OffersProps = {
	idx = function(widget, value)
		widget:setText(value)
	end,
	name = function(widget, value)
		widget:setText(value)
	end,
	item = function(widget, value)
		widget:setItem(value)
	end,
	count = function(widget, value)
		widget:setText(value)
	end,
	price = function(widget, value)
		widget:setText(formatMoney(value))
	end,
	playerName = function(widget, value)
		widget:setText(value)
	end
}
SalesProps = {
	idx = function(widget, value)
		widget:setText(value)
	end,
	name = function(widget, value)
		widget:setText(value)
	end,
	item = function(widget, value)
		widget:setItem(value)
	end,
	count = function(widget, value)
		widget:setText(value)
	end,
	price = function(widget, value)
		widget:setText(formatMoney(value))
	end,
	created = function(widget, value)
		onTimer(widget, value)
	end
}
HistoricProps = {
	description = function(widget, value)
		widget:setText(value)
	end
}
ItemProps = {
	item = function(widget, value)
		widget:setItem(value)
	end,
	count = function(widget, value)
		widget:setRange(1, value)
	end
}

function addWidget(widget, data, propList)
	for key, fn in pairs(propList) do
		fn(widget[key], data[key])
	end
end

function onTimer(widget, timer)
	removeEvent(widget.event)
	widget:setText(timer > 0 and formatTime(timer) or "Expired")

	if timer > 0 then
		widget.event = scheduleEvent(function()
			onTimer(widget, timer - 1)
		end, 1000)
	end
end
