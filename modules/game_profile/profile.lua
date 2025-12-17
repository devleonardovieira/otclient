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
  ninjaPath = {
      class = "Assassin",
      rank = "Rank IV",
      stars = 4
  },
  expandedAffinities = {
    {name = "Ninjutsu", value = "MAX", percent = 100, color = "#ffcc00", icon = "/images/game/icons/icon_instinct_20px"},
    {name = "Taijutsu", value = "LV.8", percent = 80, color = "#3399ff", icon = "/images/icons/icon_fist"},
    {name = "Genjutsu", value = "MAX", percent = 100, color = "#cc66ff", icon = "/images/game/icons/icon_mystic_20px"},
    {name = "Kenjutsu", value = "LV.6", percent = 60, color = "#ff5555", icon = "/images/icons/icon_sword"},
    {name = "Fuinjutsu", value = "LV.4", percent = 40, color = "#00cc66", icon = "/images/game/icons/icon_researcher"},
    {name = "Medical", value = "LV.3", percent = 30, color = "#00cc66", icon = "/images/icons/icon_healing"}
  },
  -- Legacy data structures kept for reference or future expansion
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
      reputation = {
          name = "Honored",
          rank = "IV",
          percent = 95,
          next = "Legend"
      },
      factions = {
          {name = "Leaf Village", desc = "Homeland", status = "ALLY", statusColor = "#1fbf6e", icon = "/images/icons/icon_location"},
          {name = "Merchants", desc = "Trade Guild", status = "NEUTRAL", statusColor = "#e5bc6d", icon = "/images/game/npcicons/icon_trade"},
          {name = "Underworld", desc = "Crime Syndicate", status = "INFAMOUS", statusColor = "#ff5555", icon = "/images/game/battle/icon-battlelist-skull"}
      },
      lineage = {
          clan = "Uchiha",
          kekkeiGenkai = "Sharingan",
          watchlist = true
      }
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
  
  -- Layout Containers
  local leftColumn = ui:getChildById('leftColumn')
  local rightColumn = ui:getChildById('rightColumn')

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

  -- Balance Row (Right Column)
  if rightColumn then
      local balanceRow = rightColumn:getChildById('balanceRow')
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
  end

  -- Stats Row (Left Column)
  if leftColumn then
      local statsRow = leftColumn:getChildById('statsRow')
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

  -- Ninja Path Section (Left Column)
  if leftColumn then
      local ninjaPathCard = leftColumn:getChildById('ninjaPathCard')
      if ninjaPathCard then
          ninjaPathCard:getChildById('pathClass'):setText(profileData.ninjaPath.class)
          ninjaPathCard:getChildById('pathRank'):setText(profileData.ninjaPath.rank)
          
          local starsPanel = ninjaPathCard:getChildById('starsPanel')
          if starsPanel then
              starsPanel:destroyChildren()
              for i=1, profileData.ninjaPath.stars do
                  local star = g_ui.createWidget('UIWidget', starsPanel)
                  star:setImageSource('/images/game/icons/star')
                  star:setSize({width=14, height=14})
                  star:setImageColor('#ffcc00')
              end
          end
          
          local affinitiesGrid = ninjaPathCard:getChildById('affinitiesGrid')
          if affinitiesGrid then
              affinitiesGrid:destroyChildren()
              for _, affinity in ipairs(profileData.expandedAffinities) do
                  local panel = g_ui.createWidget('ProfileAffinityPanel', affinitiesGrid)
                  
                  local icon = panel:getChildById('icon')
                  icon:setImageSource(affinity.icon)
                  icon:setImageColor(affinity.color)
                  
                  panel:getChildById('name'):setText(affinity.name)
                  
                  local valueLabel = panel:getChildById('value')
                  valueLabel:setText(affinity.value)
                  valueLabel:setColor(affinity.color)
                  
                  local progressBar = panel:getChildById('progressBar')
                  progressBar:setBackgroundColor(affinity.color)
                  progressBar:setWidth((affinity.percent / 100) * 130) -- Approximate width based on layout
              end
          end
      end
  end

  -- Ninja World Section (Right Column)
  if rightColumn then
      local ninjaWorldCard = rightColumn:getChildById('ninjaWorldCard')
      if ninjaWorldCard then
          -- Reputation
          local reputationCard = ninjaWorldCard:getChildById('reputationCard')
          if reputationCard then
              reputationCard:getChildById('reputationName'):setText(profileData.ninjaWorld.reputation.name)
              reputationCard:getChildById('reputationRank'):setText(profileData.ninjaWorld.reputation.rank)
              reputationCard:getChildById('reputationPercent'):setText(profileData.ninjaWorld.reputation.percent .. "% to " .. profileData.ninjaWorld.reputation.next)
              
              local bar = reputationCard:getChildById('reputationBar')
              local barBg = reputationCard:getChildById('reputationBarBg')
              if bar and barBg then
                  bar:setWidth((profileData.ninjaWorld.reputation.percent / 100) * barBg:getWidth())
              end
          end

          -- Factions
          local factionsList = ninjaWorldCard:getChildById('factionsList')
          if factionsList then
              factionsList:destroyChildren()
              for _, faction in ipairs(profileData.ninjaWorld.factions) do
                  local panel = g_ui.createWidget('ProfileFactionPanel', factionsList)
                  
                  local icon = panel:getChildById('icon')
                  icon:setImageSource(faction.icon)
                  if faction.status == "INFAMOUS" then
                     icon:setImageColor('#ff5555')
                  elseif faction.status == "NEUTRAL" then
                     icon:setImageColor('#e5bc6d')
                  else
                     icon:setImageColor('#1fbf6e')
                  end

                  panel:getChildById('name'):setText(faction.name)
                  panel:getChildById('desc'):setText(faction.desc)
                  
                  local status = panel:getChildById('status')
                  status:setText(faction.status)
                  status:setColor(faction.statusColor)
                  status:setBackgroundColor(faction.statusColor .. "22") -- Low opacity background
              end
          end

          -- Lineage
          local lineageList = ninjaWorldCard:getChildById('lineageList')
          if lineageList then
              lineageList:destroyChildren()
              
              -- Clan
              local clanPanel = g_ui.createWidget('ProfileLineagePanel', lineageList)
              clanPanel:getChildById('icon'):setImageSource('/images/game/icons/icon_no_clan_20px') -- Placeholder
              clanPanel:getChildById('icon'):setImageColor('#ff5555')
              clanPanel:getChildById('label'):setText("Clan")
              clanPanel:getChildById('value'):setText(profileData.ninjaWorld.lineage.clan)

              -- Kekkei Genkai
              local kgPanel = g_ui.createWidget('ProfileLineagePanel', lineageList)
              kgPanel:getChildById('icon'):setImageSource('/images/game/icons/icon_eye_24px')
              kgPanel:getChildById('icon'):setImageColor('#cc66ff')
              kgPanel:getChildById('label'):setText("Kekkei Genkai")
              kgPanel:getChildById('value'):setText(profileData.ninjaWorld.lineage.kekkeiGenkai)
          end
          
          -- Watchlist Button
          local watchlistButton = ninjaWorldCard:getChildById('watchlistButton')
          if watchlistButton then
              watchlistButton:setVisible(profileData.ninjaWorld.lineage.watchlist)
          end
      end
  end
end
