if not g_game.isOnline() then return end
local player = g_game.getLocalPlayer()
if not player then return end

-- Reset
player:setHealthPercent(100)
player:setShield(0)

g_logger.info("Test: Full HP")

-- Step 1: Take massive damage (show decay)
scheduleEvent(function()
  g_logger.info("Test: Taking 60% damage (Decay should appear)")
  player:setHealthPercent(40)
end, 1000)

-- Step 2: Add Shield
scheduleEvent(function()
  g_logger.info("Test: Adding 30% Shield")
  player:setShield(30)
end, 4000)

-- Step 3: Take more damage (Decay should appear alongside shield)
scheduleEvent(function()
  g_logger.info("Test: Taking 20% more damage")
  player:setHealthPercent(20)
end, 7000)
