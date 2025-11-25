EnterGameWindow = nil

controller = Controller:new()

function controller:onInit()
EnterGameWindow = g_ui.loadUI('entergame', rootWidget)
    EnterGameWindow.onEscape = function()
        EnterGameWindow:destroy()
        EnterGameWindow = nil
    end
  g_logger.info('client_entergame2: controller init')
end

function controller:onTerminate()
  if EnterGameWindow then
    EnterGameWindow:destroy()
    EnterGameWindow = nil
  end
end

function controller:toggle()
  
  EnterGameWindow:setVisible(not EnterGameWindow:isVisible())
  if EnterGameWindow:isVisible() then
    EnterGameWindow:raise()
    EnterGameWindow:focus()
  end
end

-- Wrapper opcional para chamadas externas: modules.client_entergame2.toggle()
function toggle()
  controller:toggle()
end
