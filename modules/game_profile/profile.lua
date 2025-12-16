-- chunkname: @/modules/game_profile/profile.lua

profileController = Controller:new()

local profileData = {
  name = "Kenji Zero",
  level = 42,
  class = "SHADOW WALKER",
  title = "Master Assassin",
  balance = "¥1,450,000",
  reputation = { value = 98, max = 100 },
  guild = "Silent Lotus",
  clan = "Wind Fury",
  rank = "Jonin"
}

function profileController:onInit()
  g_keyboard.bindKeyDown('Ctrl+P', function() self:toggle() end)
end

function profileController:onTerminate()
  if self.ui then
    self.ui:destroy()
    self.ui = nil
  end
end

function profileController:onGameEnd()
  if self.ui then
    self.ui:destroy()
    self.ui = nil
  end
end

function profileController:toggle()
  if not self.ui then
    self.ui = g_ui.displayUI('profile')
  end
  
  if not self.ui then
    return
  end

  if self.ui:isVisible() then
    self.ui:hide()
  else
    self:refreshUI()
    self.ui:show()
    self.ui:raise()
    self.ui:focus()
  end
end

function profileController:refreshUI()
  local ui = self.ui
  if not ui then return end
  
  -- Header
  local header = ui:getChildById('header')
  if header then
      -- Portrait
      local portrait = header:getChildById('portrait')
      if portrait then
          local localPlayer = g_game.getLocalPlayer()
          if localPlayer then
            portrait:setCreature(localPlayer)
          end
      end

      -- Level Badge
      local levelBadge = header:getChildById('levelBadge')
      if levelBadge then levelBadge:setText(tostring(profileData.level)) end

      -- Name & Info
      local infoPanel = header:getChildById('infoPanel')
      if infoPanel then
          infoPanel:getChildById('nameLabel'):setText(profileData.name)
          infoPanel:getChildById('classLabel'):setText(profileData.class)
          infoPanel:getChildById('titleLabel'):setText(profileData.title)
      end
  end

  -- Stats Row
  local statsRow = ui:getChildById('statsRow')
  if statsRow then
      -- Balance
      local balanceCard = statsRow:getChildById('balanceCard')
      if balanceCard then
          balanceCard:getChildById('valueLabel'):setText(profileData.balance)
      end

      -- Reputation
      local reputationCard = statsRow:getChildById('reputationCard')
      if reputationCard then
          reputationCard:getChildById('valueLabel'):setText(profileData.reputation.value .. "/" .. profileData.reputation.max)
          local progressBar = reputationCard:getChildById('progressBar')
          if progressBar then
              progressBar:setPercent(profileData.reputation.value)
          end
      end
  end

  -- Details List
  local detailsList = ui:getChildById('detailsList')
  if detailsList then
      local guildItem = detailsList:getChildById('guildItem')
      if guildItem then guildItem:getChildById('valueLabel'):setText(profileData.guild) end

      local clanItem = detailsList:getChildById('clanItem')
      if clanItem then clanItem:getChildById('valueLabel'):setText(profileData.clan) end

      local rankItem = detailsList:getChildById('rankItem')
      if rankItem then rankItem:getChildById('valueLabel'):setText(profileData.rank) end
  end
end
