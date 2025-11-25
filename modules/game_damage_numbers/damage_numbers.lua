g_damageNumbers = {
	screenshotMode = false,
	default = {
		fonts = {
			"baby-14",
			"baby-20",
			"baby-26",
			"baby-32",
			"critical"
		},
		offset = {
			x = 25,
			y = 25
		},
		speed = {
			x = 25,
			y = 36
		}
	},
	screenshot = {
		fonts = {
			"baby-12",
			"baby-12",
			"baby-12",
			"baby-12",
			"critical"
		},
		offset = {
			x = 12,
			y = 12
		},
		speed = {
			x = 12,
			y = 18
		}
	}
}
g_damageNumbers.init = function ()
	connect(g_map, {
		onAnimatedText = g_damageNumbers.onAnimatedText,
		onDamageText = g_damageNumbers.onDamageText
	})

	return 
end
g_damageNumbers.terminate = function ()
	disconnect(g_map, {
		onAnimatedText = g_damageNumbers.onAnimatedText,
		onDamageText = g_damageNumbers.onDamageText
	})

	return 
end
g_damageNumbers.setScreenshotMode = function (setOn)
	g_damageNumbers.screenshotMode = setOn

	return 
end
g_damageNumbers.onAnimatedText = function (widget, text)
	if g_damageNumbers.screenshotMode and not widget.isDamageText(widget) then
		widget.setOffset(widget, {
			x = 1000,
			y = 1000
		})
	end

	return 
end
g_damageNumbers.onDamageText = function (widget, text)
	if widget.getText(widget):startswith("-") then
		widget.setText(widget, widget.getText(widget):sub(2))
	end

	local screenshotMode = g_damageNumbers.screenshotMode
	local screenshot = g_damageNumbers.screenshot
	local default = g_damageNumbers.default
	local fonts = (screenshotMode and screenshot.fonts) or default.fonts
	local offsetx = (screenshotMode and screenshot.offset.x) or default.offset.x
	local offsety = (screenshotMode and screenshot.offset.y) or default.offset.y
	local speedx = (screenshotMode and screenshot.speed.x) or default.speed.x
	local speedy = (screenshotMode and screenshot.speed.y) or default.speed.y
	local impact = widget.getImpact(widget)
	local isCritical = impact == 500
	local mode = widget.getMode(widget)
	local type = widget.getType(widget)
	local impactIndex = (isCritical and 5) or (FishFight.gameState == 1 and ((FishFight.bigNumbers and 3) or 1)) or math.min(4, math.floor(math.max(1, impact/25 - 1)))
	local color = (mode == MessageDamageReceived and MessageColors[mode]) or MessageColors[type]

	widget.setFont(widget, fonts[impactIndex])
	widget.setAnimationSpeed(widget, {
		x = math.random(-speedx, speedx),
		y = math.min(3, impactIndex)*speedy
	})
	widget.setColorEx(widget, color)
	widget.setOffset(widget, {
		x = math.random(-offsetx, offsetx),
		y = math.random(-offsety, offsety)
	})

	if isCritical then
		widget.setText(widget, string.format("%s%s", "@", widget.getText(widget)))
	end

	local amount = math.min(3, impactIndex - 1)
	local intensity = math.min(3, impactIndex - 2)
	local speed = 50
	local pause = 0
	local direction = 1
	local sendScreenShake = (mode == MessageDamageDealed or mode == MessageDamageReceived) and mode ~= MessageHeal and mode ~= MessageHealOthers

	if 150 <= impact and sendScreenShake and g_settings.getBoolean("screenShake") then
		modules.game_interface.getMapPanel():shake(amount, intensity, speed, pause, direction)
	end

	return 
end

return 