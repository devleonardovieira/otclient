-- game_notifications: Toast notifications module

local notifContainer

local DEFAULT_DURATION = 4000 -- ms
local MAX_VISIBLE = 4

function init()
  g_ui.importStyle('notifications')
  notifContainer = g_ui.createWidget('NotificationContainer', rootWidget)
  if notifContainer then
    pdebug('[Notifications] init: container ready')
    notifContainer:setVisible(true)
  end
end

function terminate()
  if notifContainer then
    notifContainer:destroy()
    notifContainer = nil
  end
end

-- options: { duration=ms, icon=path, variant='info'|'success'|'warning'|'error' }
function showNotification(title, message, options)
  pdebug('[Notifications] show: called')
  if not notifContainer then
    init()
  end
  if not notifContainer then
    perror('[Notifications] show: container not available')
    return nil
  end
  options = options or {}

  -- Enforce max visible toasts
  local children = notifContainer:getChildren() or {}
  pdebug('[Notifications] show: current children=' .. tostring(#children))
  if #children >= (options.maxVisible or MAX_VISIBLE) then
    local oldest = children[1]
    if oldest then
      if oldest._dismissEvent then
        removeEvent(oldest._dismissEvent)
        oldest._dismissEvent = nil
      end
      if oldest._progressEvent then
        removeEvent(oldest._progressEvent)
        oldest._progressEvent = nil
      end
      if not oldest:isDestroyed() then oldest:destroy() end
    end
  end

  local ok, toast = pcall(function()
    return g_ui.createWidget('NotificationToast', notifContainer)
  end)
  if not ok or not toast then
    perror('[Notifications] show: failed to create widget NotificationToast')
    return nil
  end
  toast:setVisible(true)
  toast:setOpacity(0)
  if g_effects and g_effects.fadeIn then
    g_effects.fadeIn(toast, 150)
  else
    toast:setOpacity(1)
  end

  local row = toast:getChildById('row')
  local content = row and row:getChildById('content') or toast:getChildById('content')
  local titleLabel = content and content:getChildById('title') or toast:getChildById('title')
  local messageLabel = content and content:getChildById('message') or toast:getChildById('message')
  local iconImage = row and row:getChildById('icon') or toast:getChildById('icon') or toast:getChildById('iconHolder')
  if titleLabel then
    titleLabel:setVisible(true)
    titleLabel:setColor('#ffffff')
    titleLabel:setWidth(312)
    titleLabel:setTextAutoResize(true)
    titleLabel:setTextWrap(true)
    titleLabel:setTextAlign(AlignTopLeft)
    titleLabel:setOpacity(1)
    titleLabel:setText(title or '')
    if titleLabel.resizeToText then titleLabel:resizeToText() end
  end
  if messageLabel then
    messageLabel:setVisible(true)
    messageLabel:setColor('#dfdfdf')
    messageLabel:setWidth(312)
    messageLabel:setTextAutoResize(true)
    messageLabel:setTextWrap(true)
    messageLabel:setTextAlign(AlignTopLeft)
    messageLabel:setOpacity(1)
    messageLabel:setText(message or '')
    if messageLabel.resizeToText then messageLabel:resizeToText() end
  end
  if content then
    local th = titleLabel and titleLabel:getHeight() or 0
    local mh = messageLabel and messageLabel:getHeight() or 0
    local spacing = 6
    local newH = math.max(24, th + mh + spacing)
    content:setVisible(true)
    content:setHeight(newH)
    pwarning(string.format('[Notifications] content sized: th=%d mh=%d h=%d', th, mh, newH))
  end
  pwarning(string.format('[Notifications] set text: title="%s" message="%s"', tostring(title or ''), tostring(message or '')))
  if iconImage and options.icon and g_resources.fileExists(options.icon) then
    if iconImage.setImageSource then iconImage:setImageSource(options.icon) end
  end
  pwarning('[Notifications] children: row=' .. tostring(row) .. ' content=' .. tostring(content) .. ' titleLabel=' .. tostring(titleLabel) .. ' messageLabel=' .. tostring(messageLabel))

  local variant = (options.variant or 'info')
  if variant == 'sucess' then variant = 'success' end
  local colors = {
    info    = { image = '#222a3a', border = '#1a2232', accent = '#1a2232' },
    success = { image = '#1f3a22', border = '#194d2a', accent = '#194d2a' },
    warning = { image = '#3a2f22', border = '#4d3a19', accent = '#4d3a19' },
    error   = { image = '#3a2222', border = '#4d1919', accent = '#4d1919' },
  }
  local cfg = colors[variant] or colors.info
  if toast.setBorderColor then pcall(function() toast:setBorderColor(cfg.border) end) end
  local timebar = toast:getChildById('timebar')
  if timebar and timebar.setBackgroundColor then
    pcall(function()
      local mapColor = { info = '#3b5ea0', success = '#44AD25', warning = '#c59b2f', error = '#c04444' }
      timebar:setBackgroundColor(mapColor[variant] or mapColor.info)
      if timebar.setPercent then timebar:setPercent(100) end
    end)
  end

  -- Click to dismiss
  toast.onClick = function()
    if toast then
      if toast._dismissEvent then
        removeEvent(toast._dismissEvent)
        toast._dismissEvent = nil
      end
      if toast._progressEvent then
        removeEvent(toast._progressEvent)
        toast._progressEvent = nil
      end
      if not toast:isDestroyed() then toast:destroy() end
    end
    return true
  end

  -- Hover/Move detection to pause
  toast.onMouseMove = function(widget, mousePos)
    if toast and toast.getRect then
      local r = toast:getRect()
      if r and r.contains and r:contains(mousePos) then
        toast._paused = true
      else
        toast._paused = false
      end
    end
    return false
  end

  -- Ensure scheduled event is canceled when toast is destroyed by any means
  toast.onDestroy = function()
    if toast and toast._dismissEvent then
      removeEvent(toast._dismissEvent)
      toast._dismissEvent = nil
    end
    if toast and toast._progressEvent then
      removeEvent(toast._progressEvent)
      toast._progressEvent = nil
    end
    toast.onMouseMove = nil
  end

  -- Auto-dismiss with progress bar and hover pause
  local duration = tonumber(options.duration) or DEFAULT_DURATION
  toast._remainingMs = duration
  pdebug('[Notifications] show: start timebar duration=' .. tostring(duration) .. 'ms')
  local interval = 50
  toast._lastHover = nil
  local function isCursorOverToast()
    local mousePos = g_window and g_window.getMousePosition and g_window.getMousePosition() or nil
    if not mousePos then return false end
    if toast and toast.getRect then
      local tr = toast:getRect()
      if tr and tr.contains and tr:contains(mousePos) then return true end
    end
    local rowW = toast:getChildById('row')
    if rowW and rowW.getRect then
      local rr = rowW:getRect()
      if rr and rr.contains and rr:contains(mousePos) then return true end
    end
    local contentW = rowW and rowW:getChildById('content') or toast:getChildById('content')
    if contentW and contentW.getRect then
      local cr = contentW:getRect()
      if cr and cr.contains and cr:contains(mousePos) then return true end
    end
    local timebarW = toast:getChildById('timebar')
    if timebarW and timebarW.getRect then
      local tr = timebarW:getRect()
      if tr and tr.contains and tr:contains(mousePos) then return true end
    end
    local hovered = rootWidget and rootWidget:recursiveGetChildByPos(mousePos, false) or nil
    local p = hovered
    while p do
      if p == toast then return true end
      if p and p.getParent then p = p:getParent() else p = nil end
    end
    return false
  end

  toast._progressEvent = cycleEvent(function()
    if not toast or toast:isDestroyed() then return end
    local hover = isCursorOverToast() or false
    if toast._lastHover ~= hover then
      toast._lastHover = hover
      pwarning('[Notifications] hover=' .. tostring(hover))
    end
    if hover or toast._paused then return end
    toast._remainingMs = math.max(0, toast._remainingMs - interval)
    if timebar and timebar.setPercent then
      local p = math.floor((toast._remainingMs / duration) * 100)
      timebar:setPercent(p)
    end
    if toast._remainingMs <= 0 then
      removeEvent(toast._progressEvent)
      toast._progressEvent = nil
      if g_effects and g_effects.fadeOut then
        g_effects.fadeOut(toast, 180)
        scheduleEvent(function()
          if toast and not toast:isDestroyed() then toast:destroy() end
        end, 190)
      else
        if not toast:isDestroyed() then toast:destroy() end
      end
    end
  end, interval)

  local function bindHoverPause(w)
    if not w then return end
    w.onMouseEnter = function()
      if toast and not toast:isDestroyed() then toast._paused = true end
    end
    w.onMouseLeave = function()
      if toast and not toast:isDestroyed() then toast._paused = false end
    end
  end
  bindHoverPause(toast)
  bindHoverPause(row)
  bindHoverPause(content)
  bindHoverPause(iconImage)
  bindHoverPause(titleLabel)
  bindHoverPause(messageLabel)
  bindHoverPause(timebar)

  return toast
end

-- Convenience alias in module namespace
modules = modules or {}
modules.game_notifications = {
  show = showNotification,
  showNotification = showNotification,
}