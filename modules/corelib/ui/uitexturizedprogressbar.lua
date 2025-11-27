-- chunkname: @/modules/corelib/ui/uitexturizedprogressbar.lua

UITexturizedProgressBar = extends(UIWidget, "UITexturizedProgressBar")

function UITexturizedProgressBar.create()
	local progressbar = UITexturizedProgressBar.internalCreate()

	progressbar:setOn(true)

	progressbar.minimum = 0
	progressbar.maximum = 100
	progressbar.value = 0
	progressbar.frontWidget_ImageSource = ""
	progressbar.frontWidget_ImageColor = "#FFFFFF"
	progressbar.textWidget_Text = ""
	progressbar.frontWidget_Progress_ImageBorderLeft = 0
	progressbar.frontWidget_Progress_ImageBorderRight = 0
	progressbar.frontWidget_Progress_ImageBorderTop = 0
	progressbar.frontWidget_Progress_ImageBorderBottom = 0
	progressbar.frontWidget_Progress_ImageClipLeft = 0
	progressbar.frontWidget_Progress_ImageClipRight = 0
	progressbar.frontWidget_Progress_ImageClipTop = 0
	progressbar.frontWidget_Progress_ImageClipBottom = 0
	progressbar.frontWidget_Progress_MarginLeft = 0
	progressbar.frontWidget_Progress_MarginRight = 0
	progressbar.frontWidget_Progress_MarginTop = 0
	progressbar.frontWidget_Progress_MarginBottom = 0
	progressbar.frontWidget_Progress_MaxWidth = 0
	progressbar.frontWidget_Full_ImageBorderLeft = 0
	progressbar.frontWidget_Full_ImageBorderRight = 0
	progressbar.frontWidget_Full_ImageBorderTop = 0
	progressbar.frontWidget_Full_ImageBorderBottom = 0
	progressbar.frontWidget_Full_ImageClipLeft = 0
	progressbar.frontWidget_Full_ImageClipRight = 0
	progressbar.frontWidget_Full_ImageClipTop = 0
	progressbar.frontWidget_Full_ImageClipBottom = 0
	progressbar.frontWidget_Full_MarginLeft = 0
	progressbar.frontWidget_Full_MarginRight = 0
	progressbar.frontWidget_Full_MarginTop = 0
	progressbar.frontWidget_Full_MarginBottom = 0
	progressbar.frontWidget_Full_MaxWidth = 0

	return progressbar
end

function UITexturizedProgressBar:onSetup()
	return
end

function UITexturizedProgressBar:getFrontWidget()
	return self.frontWidget
end

function UITexturizedProgressBar:getTextWidget()
	return self.textWidget
end

function UITexturizedProgressBar:setText(value)
	self.textWidget_Text = value

	self:updateBackground()
end

function UITexturizedProgressBar:setFrontImageSource(value)
	self.frontWidget_ImageSource = value

	self:updateBackground()
end

function UITexturizedProgressBar:setFrontImageColor(value)
	self.frontWidget_ImageColor = value

	self:updateBackground()
end

function UITexturizedProgressBar:setProgressImageBorderLeft(value)
	self.frontWidget_Progress_ImageBorderLeft = tonumber(value)

	self:updateBackground()
end

function UITexturizedProgressBar:setProgressImageBorderTop(value)
	self.frontWidget_Progress_ImageBorderTop = tonumber(value)

	self:updateBackground()
end

function UITexturizedProgressBar:setProgressImageBorderRight(value)
	self.frontWidget_Progress_ImageBorderRight = tonumber(value)

	self:updateBackground()
end

function UITexturizedProgressBar:setProgressImageBorderBottom(value)
	self.frontWidget_Progress_ImageBorderBottom = tonumber(value)

	self:updateBackground()
end

function UITexturizedProgressBar:setProgressImageBorder(value)
	self.frontWidget_Progress_ImageBorderLeft = tonumber(value)
	self.frontWidget_Progress_ImageBorderRight = tonumber(value)
	self.frontWidget_Progress_ImageBorderTop = tonumber(value)
	self.frontWidget_Progress_ImageBorderBottom = tonumber(value)

	self:updateBackground()
end

function UITexturizedProgressBar:setProgressImageClipLeft(value)
	self.frontWidget_Progress_ImageClipLeft = tonumber(value)

	self:updateBackground()
end

function UITexturizedProgressBar:setProgressImageClipTop(value)
	self.frontWidget_Progress_ImageClipTop = tonumber(value)

	self:updateBackground()
end

function UITexturizedProgressBar:setProgressImageClipRight(value)
	self.frontWidget_Progress_ImageClipRight = tonumber(value)

	self:updateBackground()
end

function UITexturizedProgressBar:setProgressImageClipBottom(value)
	self.frontWidget_Progress_ImageClipBottom = tonumber(value)

	self:updateBackground()
end

function UITexturizedProgressBar:setProgressImageClip(value)
	local clip = value:split(" ")

	self.frontWidget_Progress_ImageClipLeft = tonumber(clip[1])
	self.frontWidget_Progress_ImageClipTop = tonumber(clip[2])
	self.frontWidget_Progress_ImageClipRight = tonumber(clip[3])
	self.frontWidget_Progress_ImageClipBottom = tonumber(clip[4])

	self:updateBackground()
end

function UITexturizedProgressBar:setProgressMarginLeft(value)
	self.frontWidget_Progress_MarginLeft = tonumber(value)

	self:updateBackground()
end

function UITexturizedProgressBar:setProgressMarginTop(value)
	self.frontWidget_Progress_MarginTop = tonumber(value)

	self:updateBackground()
end

function UITexturizedProgressBar:setProgressMarginRight(value)
	self.frontWidget_Progress_MarginRight = tonumber(value)

	self:updateBackground()
end

function UITexturizedProgressBar:setProgressMarginBottom(value)
	self.frontWidget_Progress_MarginBottom = tonumber(value)

	self:updateBackground()
end

function UITexturizedProgressBar:setProgressMargin(value)
	local margin = value:split(" ")

	self.frontWidget_Progress_MarginLeft = tonumber(margin[1])
	self.frontWidget_Progress_MarginTop = tonumber(margin[2])
	self.frontWidget_Progress_MarginRight = tonumber(margin[3])
	self.frontWidget_Progress_MarginBottom = tonumber(margin[4])

	self:updateBackground()
end

function UITexturizedProgressBar:setProgressMaxWidth(value)
	self.frontWidget_Progress_MaxWidth = tonumber(value)

	self:updateBackground()
end

function UITexturizedProgressBar:setFullImageBorderLeft(value)
	self.frontWidget_Full_ImageBorderLeft = tonumber(value)

	self:updateBackground()
end

function UITexturizedProgressBar:setFullImageBorderTop(value)
	self.frontWidget_Full_ImageBorderTop = tonumber(value)

	self:updateBackground()
end

function UITexturizedProgressBar:setFullImageBorderRight(value)
	self.frontWidget_Full_ImageBorderRight = tonumber(value)

	self:updateBackground()
end

function UITexturizedProgressBar:setFullImageBorderBottom(value)
	self.frontWidget_Full_ImageBorderBottom = tonumber(value)

	self:updateBackground()
end

function UITexturizedProgressBar:setFullImageBorder(value)
	self.frontWidget_Full_ImageBorderLeft = tonumber(value)
	self.frontWidget_Full_ImageBorderRight = tonumber(value)
	self.frontWidget_Full_ImageBorderTop = tonumber(value)
	self.frontWidget_Full_ImageBorderBottom = tonumber(value)

	self:updateBackground()
end

function UITexturizedProgressBar:setFullImageClipLeft(value)
	self.frontWidget_Full_ImageClipLeft = tonumber(value)

	self:updateBackground()
end

function UITexturizedProgressBar:setFullImageClipTop(value)
	self.frontWidget_Full_ImageClipTop = tonumber(value)

	self:updateBackground()
end

function UITexturizedProgressBar:setFullImageClipRight(value)
	self.frontWidget_Full_ImageClipRight = tonumber(value)

	self:updateBackground()
end

function UITexturizedProgressBar:setFullImageClipBottom(value)
	self.frontWidget_Full_ImageClipBottom = tonumber(value)

	self:updateBackground()
end

function UITexturizedProgressBar:setFullImageClip(value)
	local clip = value:split(" ")

	self.frontWidget_Full_ImageClipLeft = tonumber(clip[1])
	self.frontWidget_Full_ImageClipTop = tonumber(clip[2])
	self.frontWidget_Full_ImageClipRight = tonumber(clip[3])
	self.frontWidget_Full_ImageClipBottom = tonumber(clip[4])

	self:updateBackground()
end

function UITexturizedProgressBar:setFullMarginLeft(value)
	self.frontWidget_Full_MarginLeft = tonumber(value)

	self:updateBackground()
end

function UITexturizedProgressBar:setFullMarginTop(value)
	self.frontWidget_Full_MarginTop = tonumber(value)

	self:updateBackground()
end

function UITexturizedProgressBar:setFullMarginRight(value)
	self.frontWidget_Full_MarginRight = tonumber(value)

	self:updateBackground()
end

function UITexturizedProgressBar:setFullMarginBottom(value)
	self.frontWidget_Full_MarginBottom = tonumber(value)

	self:updateBackground()
end

function UITexturizedProgressBar:setFullMargin(value)
	local margin = value:split(" ")

	self.frontWidget_Full_MarginLeft = tonumber(margin[1])
	self.frontWidget_Full_MarginTop = tonumber(margin[2])
	self.frontWidget_Full_MarginRight = tonumber(margin[3])
	self.frontWidget_Full_MarginBottom = tonumber(margin[4])

	self:updateBackground()
end

function UITexturizedProgressBar:setFullMaxWidth(value)
	self.frontWidget_Full_MaxWidth = tonumber(value)

	self:updateBackground()
end

function UITexturizedProgressBar:onStyleApply(name, node)
	for name, value in pairs(node) do
		if name == "front-image-source" then
			self.frontWidget_ImageSource = value
		elseif name == "front-image-color" then
			self.frontWidget_ImageColor = value
		elseif name == "textwidget-text" then
			self.textWidget_Text = value
		elseif name == "front-progress-image-border-left" then
			self.frontWidget_Progress_ImageBorderLeft = tonumber(value)
		elseif name == "front-progress-image-border-right" then
			self.frontWidget_Progress_ImageBorderRight = tonumber(value)
		elseif name == "front-progress-image-border-top" then
			self.frontWidget_Progress_ImageBorderTop = tonumber(value)
		elseif name == "front-progress-image-border-bottom" then
			self.frontWidget_Progress_ImageBorderBottom = tonumber(value)
		elseif name == "front-progress-image-border" then
			self.frontWidget_Progress_ImageBorderLeft = tonumber(value)
			self.frontWidget_Progress_ImageBorderRight = tonumber(value)
			self.frontWidget_Progress_ImageBorderTop = tonumber(value)
			self.frontWidget_Progress_ImageBorderBottom = tonumber(value)
		elseif name == "front-progress-image-clip-left" then
			self.frontWidget_Progress_ImageClipLeft = tonumber(value)
		elseif name == "front-progress-image-clip-right" then
			self.frontWidget_Progress_ImageClipRight = tonumber(value)
		elseif name == "front-progress-image-clip-top" then
			self.frontWidget_Progress_ImageClipTop = tonumber(value)
		elseif name == "front-progress-image-clip-bottom" then
			self.frontWidget_Progress_ImageClipBottom = tonumber(value)
		elseif name == "front-progress-image-clip" then
			local clip = value:split(" ")

			self.frontWidget_Progress_ImageClipLeft = tonumber(clip[1])
			self.frontWidget_Progress_ImageClipTop = tonumber(clip[2])
			self.frontWidget_Progress_ImageClipRight = tonumber(clip[3])
			self.frontWidget_Progress_ImageClipBottom = tonumber(clip[4])
		elseif name == "front-progress-margin-left" then
			self.frontWidget_Progress_MarginLeft = tonumber(value)
		elseif name == "front-progress-margin-right" then
			self.frontWidget_Progress_MarginRight = tonumber(value)
		elseif name == "front-progress-margin-top" then
			self.frontWidget_Progress_MarginTop = tonumber(value)
		elseif name == "front-progress-margin-bottom" then
			self.frontWidget_Progress_MarginBottom = tonumber(value)
		elseif name == "front-progress-margin" then
			local margin = value:split(" ")

			self.frontWidget_Progress_MarginLeft = tonumber(margin[1])
			self.frontWidget_Progress_MarginTop = tonumber(margin[2])
			self.frontWidget_Progress_MarginRight = tonumber(margin[3])
			self.frontWidget_Progress_MarginBottom = tonumber(margin[4])
		elseif name == "front-progress-max-width" then
			self.frontWidget_Progress_MaxWidth = tonumber(value)
		elseif name == "front-full-image-border-left" then
			self.frontWidget_Full_ImageBorderLeft = tonumber(value)
		elseif name == "front-full-image-border-right" then
			self.frontWidget_Full_ImageBorderRight = tonumber(value)
		elseif name == "front-full-image-border-top" then
			self.frontWidget_Full_ImageBorderTop = tonumber(value)
		elseif name == "front-full-image-border-bottom" then
			self.frontWidget_Full_ImageBorderBottom = tonumber(value)
		elseif name == "front-full-image-border" then
			self.frontWidget_Full_ImageBorderLeft = tonumber(value)
			self.frontWidget_Full_ImageBorderRight = tonumber(value)
			self.frontWidget_Full_ImageBorderTop = tonumber(value)
			self.frontWidget_Full_ImageBorderBottom = tonumber(value)
		elseif name == "front-full-image-clip-left" then
			self.frontWidget_Full_ImageClipLeft = tonumber(value)
		elseif name == "front-full-image-clip-right" then
			self.frontWidget_Full_ImageClipRight = tonumber(value)
		elseif name == "front-full-image-clip-top" then
			self.frontWidget_Full_ImageClipTop = tonumber(value)
		elseif name == "front-full-image-clip-bottom" then
			self.frontWidget_Full_ImageClipBottom = tonumber(value)
		elseif name == "front-full-image-clip" then
			local clip = value:split(" ")

			self.frontWidget_Full_ImageClipLeft = tonumber(clip[1])
			self.frontWidget_Full_ImageClipTop = tonumber(clip[2])
			self.frontWidget_Full_ImageClipRight = tonumber(clip[3])
			self.frontWidget_Full_ImageClipBottom = tonumber(clip[4])
		elseif name == "front-full-margin-left" then
			self.frontWidget_Full_MarginLeft = tonumber(value)
		elseif name == "front-full-margin-right" then
			self.frontWidget_Full_MarginRight = tonumber(value)
		elseif name == "front-full-margin-top" then
			self.frontWidget_Full_MarginTop = tonumber(value)
		elseif name == "front-full-margin-bottom" then
			self.frontWidget_Full_MarginBottom = tonumber(value)
		elseif name == "front-full-margin" then
			local margin = value:split(" ")

			self.frontWidget_Full_MarginLeft = tonumber(margin[1])
			self.frontWidget_Full_MarginTop = tonumber(margin[2])
			self.frontWidget_Full_MarginRight = tonumber(margin[3])
			self.frontWidget_Full_MarginBottom = tonumber(margin[4])
		elseif name == "front-full-max-width" then
			self.frontWidget_Full_MaxWidth = tonumber(value)
		end
	end
end

function UITexturizedProgressBar:setMinimum(minimum)
	self.minimum = minimum

	if minimum > self.value then
		self:setValue(minimum)
	end
end

function UITexturizedProgressBar:setMaximum(maximum)
	self.maximum = maximum

	if maximum < self.value then
		self:setValue(maximum)
	end
end

function UITexturizedProgressBar:setValue(value, minimum, maximum)
	if minimum then
		self:setMinimum(minimum)
	end

	if maximum then
		self:setMaximum(maximum)
	end

	self.value = math.max(math.min(value, self.maximum), self.minimum)

	self:updateBackground()
end

function UITexturizedProgressBar:setPercent(percent)
	self:setValue(percent, 0, 100)
end

function UITexturizedProgressBar:getPercent()
	return self.value
end

function UITexturizedProgressBar:getPercentPixels()
	return (self.maximum - self.minimum) / self:getWidth()
end

function UITexturizedProgressBar:getProgress()
	if self.minimum == self.maximum then
		return 1
	end

	return (self.value - self.minimum) / (self.maximum - self.minimum)
end

function UITexturizedProgressBar:getProgressWidth()
	local width = self:getWidth()

	if self:getProgress() == 1 then
		width = self.frontWidget_Full_MaxWidth > 0 and math.min(width, self.frontWidget_Full_MaxWidth) or width

		return width
	end

	width = self.frontWidget_Progress_MaxWidth > 0 and math.min(width, self.frontWidget_Progress_MaxWidth) or width

	return width
end

function UITexturizedProgressBar:updateBackground()
	if self:isOn() then
		local frontWidget = self:getFrontWidget()

		if self:getProgress() == 1 then
			frontWidget:setImageBorderLeft(self.frontWidget_Full_ImageBorderLeft)
			frontWidget:setImageBorderRight(self.frontWidget_Full_ImageBorderRight)
			frontWidget:setImageBorderTop(self.frontWidget_Full_ImageBorderTop)
			frontWidget:setImageBorderBottom(self.frontWidget_Full_ImageBorderBottom)
			frontWidget:setMarginLeft(self.frontWidget_Full_MarginLeft)
			frontWidget:setMarginRight(self.frontWidget_Full_MarginRight)
			frontWidget:setMarginTop(self.frontWidget_Full_MarginTop)
			frontWidget:setMarginBottom(self.frontWidget_Full_MarginBottom)
			frontWidget:setImageClip(torect(string.format("%d %d %d %d", self.frontWidget_Full_ImageClipLeft, self.frontWidget_Full_ImageClipTop, self.frontWidget_Full_ImageClipRight, self.frontWidget_Full_ImageClipBottom)))
		else
			frontWidget:setImageBorderLeft(self.frontWidget_Progress_ImageBorderLeft)
			frontWidget:setImageBorderRight(self.frontWidget_Progress_ImageBorderRight)
			frontWidget:setImageBorderTop(self.frontWidget_Progress_ImageBorderTop)
			frontWidget:setImageBorderBottom(self.frontWidget_Progress_ImageBorderBottom)
			frontWidget:setMarginLeft(self.frontWidget_Progress_MarginLeft)
			frontWidget:setMarginRight(self.frontWidget_Progress_MarginRight)
			frontWidget:setMarginTop(self.frontWidget_Progress_MarginTop)
			frontWidget:setMarginBottom(self.frontWidget_Progress_MarginBottom)
			frontWidget:setImageClip(torect(string.format("%d %d %d %d", self.frontWidget_Progress_ImageClipLeft, self.frontWidget_Progress_ImageClipTop, self.frontWidget_Progress_ImageClipRight, self.frontWidget_Progress_ImageClipBottom)))
		end

		frontWidget:setWidth(math.max(math.round(self:getProgressWidth() * self:getProgress()), 1))
		frontWidget:setImageSource(self.frontWidget_ImageSource)
		frontWidget:setImageColor(self.frontWidget_ImageColor)
		self:getTextWidget():setText(self.textWidget_Text)
	end
end

function UITexturizedProgressBar:onGeometryChange(oldRect, newRect)
	if not self:isOn() then
		self:setHeight(0)
	end

	self:updateBackground()
end
