modules.game_hotkeys = modules.game_hotkeys or {}

local M = modules.game_hotkeys

function init()
  g_logger.info('game_hotkeys (stub) initialized')
end

function terminate()
  g_logger.info('game_hotkeys (stub) terminated')
end

function M.show()
  g_logger.info('Hotkeys UI is not implemented in this build.')
end

function M.createHotkeyBlock(name)
  -- Return a simple block object used by dialogs to register hotkeys.
  local block = {
    name = name or 'hotkey_block',
    destroy = function() end
  }
  return block
end

