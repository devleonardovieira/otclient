-- chunkname: @/modules/corelib/ui/effects.lua

g_effects = {}

function g_effects.fadeIn(widget, time, elapsed, finishCallback)
	elapsed = elapsed or 0
	time = time or 300

	widget:setOpacity(math.min(elapsed / time, 1))
	removeEvent(widget.fadeEvent)

	if elapsed < time then
		removeEvent(widget.fadeEvent)

		widget.fadeEvent = scheduleEvent(function()
			g_effects.fadeIn(widget, time, elapsed + 30, finishCallback)
		end, 30)
	else
		if finishCallback then
			finishCallback()
		end

		widget.fadeEvent = nil
	end
end

function g_effects.fadeOut(widget, time, elapsed, finishCallback)
	elapsed = elapsed or 0
	time = time or 300
	elapsed = math.max((1 - widget:getOpacity()) * time, elapsed)

	removeEvent(widget.fadeEvent)
	widget:setOpacity(math.max((time - elapsed) / time, 0))

	if elapsed < time then
		widget.fadeEvent = scheduleEvent(function()
			g_effects.fadeOut(widget, time, elapsed + 30, finishCallback)
		end, 30)
	else
		if finishCallback then
			finishCallback()
		end

		widget.fadeEvent = nil
	end
end

function g_effects.cancelFade(widget)
	removeEvent(widget.fadeEvent)

	widget.fadeEvent = nil
end

function g_effects.startBlink(widget, duration, interval, clickCancel)
	duration = duration or 0
	interval = interval or 500
	clickCancel = clickCancel or true

	removeEvent(widget.blinkEvent)
	removeEvent(widget.blinkStopEvent)

	widget.blinkEvent = cycleEvent(function()
		widget:setOn(not widget:isOn())
	end, interval)

	if duration > 0 then
		widget.blinkStopEvent = scheduleEvent(function()
			g_effects.stopBlink(widget)
		end, duration)
	end

	connect(widget, {
		onClick = g_effects.stopBlink
	})
end

function g_effects.stopBlink(widget)
	disconnect(widget, {
		onClick = g_effects.stopBlink
	})
	removeEvent(widget.blinkEvent)
	removeEvent(widget.blinkStopEvent)

	widget.blinkEvent = nil
	widget.blinkStopEvent = nil

	widget:setOn(false)
end

function g_effects.onCooldown(widget, cooldown, params, first)
	if not first then
		if widget.event then
			removeEvent(widget.event)
		end

		if params.onStart and not params.onStart(cooldown) then
			return
		end
	end

	if cooldown < 1 and (not params.onEnd or params.onEnd(cooldown) or true) then
		removeEvent(widget.event)

		return
	end

	if params.onExecute and not params.onExecute(cooldown) then
		removeEvent(widget.event)

		return
	end

	widget.event = scheduleEvent(function()
		g_effects.onCooldown(widget, cooldown - 1, params, true)
	end, 1000)
end

function g_effects.moveToPosition(widget, fromPosition, toPosition, duration, easingFunction, finishCallback)
	local startTime = g_clock.millis()
	local endTime = startTime + duration

	local function updateWidgetPosition()
		local currentTime = g_clock.millis()
		local elapsedTime = math.min(currentTime - startTime, duration)
		local t = elapsedTime / duration
		local newX = easingFunction(t, fromPosition.x, toPosition.x - fromPosition.x, 1)
		local newY = easingFunction(t, fromPosition.y, toPosition.y - fromPosition.y, 1)

		widget:setPosition({
			x = newX,
			y = newY
		})

		if currentTime < endTime then
			scheduleEvent(updateWidgetPosition, 16)
		elseif finishCallback then
			finishCallback()
		end
	end

	updateWidgetPosition()
end

function g_effects.moveToMargin(widget, marginType, initialMargin, finalMargin, duration, easingFunction, finishCallback)
	local marginUpdate = {
		[MarginTop] = function(value)
			widget:setMarginTop(value)
		end,
		[MarginLeft] = function(value)
			widget:setMarginLeft(value)
		end,
		[MarginBottom] = function(value)
			widget:setMarginBottom(value)
		end,
		[MarginRight] = function(value)
			widget:setMarginRight(value)
		end
	}

	if not marginUpdate[marginType] then
		return
	end

	local deltaMargin = math.abs(finalMargin - initialMargin)
	local startTime = g_clock.millis()
	local endTime = startTime + duration

	local function moveToMarginEvent()
		local currentTime = g_clock.millis()
		local elapsedTime = math.min(currentTime - startTime, duration)
		local t = elapsedTime / duration
		local currentMargin = easingFunction(t, initialMargin, finalMargin - initialMargin, 1)

		marginUpdate[marginType](currentMargin)

		if currentTime < endTime then
			scheduleEvent(moveToMarginEvent, 16)
		elseif finishCallback then
			finishCallback()
		end
	end

	moveToMarginEvent()
end
