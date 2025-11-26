-- chunkname: @/modules/corelib/ui/easing.lua

Easing = {}

function Easing.easeOutBack(t, b, c, d)
	local s = 1.70158

	t = t / d - 1

	return c * (t * t * ((s + 1) * t + s) + 1) + b
end

function Easing.easeOut(t, b, c, d)
	t = t / d

	return -c * t * (t - 2) + b
end

function Easing.easeIn(t, b, c, d)
	t = t / d

	return c * t * t + b
end

function Easing.linear(t, b, c, d)
	return c * t / d + b
end
