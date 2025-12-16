-- chunkname: @/modules/game_profile/profile.lua

profileController = Controller:new()

local profileData = {
  name = "Kenji Zero",
  level = 42,
  rank = "SHADOW WALKER",
  title = "Master Assassin • Night Operative",
  balance = {
      ryo = "1,400,000",
      koban = "850"
  },
  stats = {
      sRankMissions = 12,
      pvpKills = 27,
      betrayals = 2
  },
  -- Legacy data structures kept for reference or future expansion
  ninjaPath = {
    class = "Assassino",
    stars = 4
  },
  affinities = {
    {name = "Ninjutsu", stars = 5},
    {name = "Taijutsu", stars = 4},
    {name = "Genjutsu", stars = 2}
  },
  detailedStats = {
    {name = "Concluiu missões S Rank", value = 12},
    {name = "Maior Rank", value = "Jonin"},
    {name = "Mortes PvP", value = 27},
    {name = "Traições", value = 2}
  },
  ninjaWorld = {
    reputation = "HONRADO",
    percentage = 95,
    factions = {
      {name = "Vila da Folha", status = "Aliado", color = "#55FF55"},
      {name = "Mercadores", status = "Neutro", color = "#FFFF55"},
      {name = "Submundo", status = "Infame", color = "#FF5555"}
    }
  },
  lineage = {
    clan = "Uchiha",
    kekkeiGenkai = "Sharingan",
    state = "Observado pela ANBU"
  },
  history = {
    {text = "Concluiu missão S Rank", type = "success"},
    {text = "Traiu uma facção", type = "warning"},
    {text = "Eliminou alvo de elite", type = "success"}
  }
}

function profileController:onInit()
  g_keyboard.bindKeyDown('Ctrl+Shift+P', function() self:toggle() end)
  print("Profile module initialized. Press Ctrl+Shift+P to open.")
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
  print("Toggle called")
  if not self.ui then
    print("Creating UI...")
    self.ui = g_ui.displayUI('profile')
    if self.ui then
        print("UI created successfully")
    else
        print("Failed to create UI - displayUI returned nil")
    end
  end
  
  if not self.ui then
    print("UI is nil, returning")
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
  local headerPanel = ui:getChildById('headerPanel')
  if headerPanel then
      headerPanel:getChildById('nameLabel'):setText(profileData.name)
      headerPanel:getChildById('rankLabel'):setText(profileData.rank)
      headerPanel:getChildById('titleLabel'):setText(profileData.title)
      headerPanel:getChildById('levelBadge'):setText(profileData.level)
      
      local portrait = headerPanel:getChildById('portrait')
      if portrait then
          local localPlayer = g_game.getLocalPlayer()
          if localPlayer then
            portrait:setCreature(localPlayer)
          end
      end
  end

  -- Balance Row
  local balanceRow = ui:getChildById('balanceRow')
  if balanceRow then
      local bankCard = balanceRow:getChildById('bankCard')
      if bankCard then
          bankCard:getChildById('bankValue'):setText("¥" .. profileData.balance.ryo)
      end
      
      local specialCard = balanceRow:getChildById('specialCard')
      if specialCard then
          specialCard:getChildById('specialValue'):setText(profileData.balance.koban)
      end
  end

  -- Stats Row
  local statsRow = ui:getChildById('statsRow')
  if statsRow then
      local missionCard = statsRow:getChildById('missionCard')
      if missionCard then
          missionCard:getChildById('missionValue'):setText(profileData.stats.sRankMissions)
      end

      local killsCard = statsRow:getChildById('killsCard')
      if killsCard then
          killsCard:getChildById('killsValue'):setText(profileData.stats.pvpKills)
      end
      
      local betrayalCard = statsRow:getChildById('betrayalCard')
      if betrayalCard then
          betrayalCard:getChildById('betrayalValue'):setText(profileData.stats.betrayals)
      end
  end
end
