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
  combatRecord = {
      season = 5,
      stats = {
          {title = "K/D RATIO", value = "4.5", color = "#1fbf6e"},
          {title = "STREAK", value = "18", color = "#e5bc6d"},
          {title = "NEMESIS", value = "Orochi_X", color = "#ff5555"}
      },
      guildWar = {
          contribution = "2,450",
          rank = "Top 5%",
          percent = 75
      },
      history = {
          {level = 45, name = "Cloud_Ninja_01", location = "Valley of Clouds", time = "2m ago", type = "victory"},
          {level = 38, name = "Sand_Puppet", location = "Desert Border", time = "1h ago", type = "victory"},
          {level = 55, name = "Madara_U", location = "Final Valley", time = "Yesterday", type = "defeat"},
          {level = 42, name = "Mist_Assassin", location = "Hidden Mist Lake", time = "3d ago", type = "victory"},
          {level = 60, name = "Hokage_Pro", location = "Konoha Gates", time = "4d ago", type = "defeat"}
      }
  },
  missionLog = {
      total = 342,
      ranks = {
          {rank = "RANK SS", value = 2, sub = "/0", color = "#ff9999", barColor = "#ff5555"},
          {rank = "RANK S", value = 12, sub = "/1", color = "#ff5555", barColor = "#ff0000"},
          {rank = "RANK A", value = 45, sub = "/3", color = "#ffcc00", barColor = "#ffaa00"},
          {rank = "RANK B", value = 88, sub = "/2", color = "#1fbf6e", barColor = "#00ff00"},
          {rank = "RANK C", value = 124, sub = "/5", color = "#3399ff", barColor = "#0055ff"},
          {rank = "RANK D", value = 71, sub = "/0", color = "#aaaaaa", barColor = "#ffffff"}
      }
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
  },
  bankData = {
        actions = {
            {text = "Deposit", icon = "/images/profile/bank/icon_down", color = "#1fbf6e"},
            {text = "Withdraw", icon = "/images/profile/bank/icon_up", color = "#ff5555"},
            {text = "Transfer", icon = "/images/profile/bank/icon_exchange", color = "#55aaff"}
        },
        transactions = {
            {title = "Mission Reward", date = "Today, 10:42 AM", amount = "+ ¥25,000", detail = "S-RANK #422", type = "income"},
            {title = "Sent to Sasuke", date = "Yesterday, 14:20 PM", amount = "- ¥5,000", detail = "CLAN FEE", type = "expense"},
            {title = "Market Sale", date = "Yesterday, 09:15 AM", amount = "+ ¥12,500", detail = "Rare Ore x5", type = "income"},
            {title = "Equipment Repair", date = "2 days ago", amount = "- ¥2,400", detail = "Blacksmith", type = "expense"},
            {title = "Tournament Prize", date = "3 days ago", amount = "+ ¥50,000", detail = "1st Place", type = "income"}
        }
    },
    betrayalData = {
        actions = {
            {text = "Place Bounty", icon = "/images/icons/icon_skull", color = "#ff5555"},
            {text = "My Bounties", icon = "/images/icons/icon_list", color = "#e5bc6d"},
            {text = "Top Hunters", icon = "/images/icons/icon_trophy", color = "#ffffff"}
        },
        bingoBook = {
            {name = "Kisame Hoshigaki", rank = "S-Rank Criminal", bounty = "¥45,000,000", status = "Alive"},
            {name = "Deidara", rank = "S-Rank Criminal", bounty = "¥38,500,000", status = "Alive"},
            {name = "Kakuzu", rank = "S-Rank Criminal", bounty = "¥55,000,000", status = "Alive"},
            {name = "Hidan", rank = "S-Rank Criminal", bounty = "¥40,000,000", status = "Alive"},
            {name = "Sasori", rank = "S-Rank Criminal", bounty = "¥42,000,000", status = "Alive"},
            {name = "Zetsu", rank = "S-Rank Criminal", bounty = "¥30,000,000", status = "Alive"}
        }
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
  if not self.ui then
    self.ui = g_ui.displayUI('profile')
    if not self.ui then
        print("Failed to create UI")
        return
    end
    -- Select default tab
    self:selectTab('Missions')
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

function profileController:selectTab(tabName)
    if not self.ui then return end
    
    local tabs = {'Missions', 'PvP', 'Betrayals', 'Bank', 'Special'}
    
    for _, tab in ipairs(tabs) do
        local tabButton = self.ui:recursiveGetChildById('tab' .. tab)
        local contentPanel = self.ui:recursiveGetChildById('content' .. tab)
        
        if tabButton then
            tabButton:setChecked(tab == tabName)
        end
        
        if contentPanel then
            contentPanel:setVisible(tab == tabName)
        end
    end
    
    -- Refresh UI to populate content for the newly visible tab
    self:refreshUI()
end

function profileController:refreshUI()
  local ui = self.ui
  if not ui then return end
  
  -- 1. Header Population
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

  -- 2. Tab Buttons Data (Summaries)
  local tabBar = ui:getChildById('tabBar')
  if tabBar then
      local tabMissions = tabBar:getChildById('tabMissions')
      if tabMissions then tabMissions:getChildById('missionValue'):setText(profileData.stats.sRankMissions) end
      
      local tabPvP = tabBar:getChildById('tabPvP')
      if tabPvP then tabPvP:getChildById('killsValue'):setText(profileData.stats.pvpKills) end
      
      local tabBetrayals = tabBar:getChildById('tabBetrayals')
      if tabBetrayals then tabBetrayals:getChildById('betrayalValue'):setText(profileData.stats.betrayals) end
      
      local tabBank = tabBar:getChildById('tabBank')
      if tabBank then tabBank:getChildById('bankValue'):setText("¥" .. profileData.balance.ryo) end
      
      local tabSpecial = tabBar:getChildById('tabSpecial')
      if tabSpecial then tabSpecial:getChildById('specialValue'):setText(profileData.balance.koban) end
  end

  -- 3. Content Panels Population
  
  -- Content: Missions (Mission Log)
  local missionLogCard = ui:recursiveGetChildById('missionLogCard')
  if missionLogCard then
      missionLogCard:getChildById('totalCompleted'):setText("TOTAL COMPLETED: " .. profileData.missionLog.total)
      
      local missionGrid = missionLogCard:getChildById('missionGrid')
      if missionGrid then
          missionGrid:destroyChildren()
          for _, rankData in ipairs(profileData.missionLog.ranks) do
              local card = g_ui.createWidget('MissionRankCard', missionGrid)
              
              local rankTitle = card:getChildById('rankTitle')
              rankTitle:setText(rankData.rank)
              rankTitle:setColor(rankData.color)
              
              card:getChildById('mainValue'):setText(rankData.value)
              card:getChildById('subValue'):setText(rankData.sub)
              
              local progressBar = card:getChildById('progressBar')
              progressBar:setBackgroundColor(rankData.barColor)
          end
      end
  end

  -- Content: PvP (Combat Record)
  local contentPvP = ui:recursiveGetChildById('contentPvP')
  if contentPvP and contentPvP:isVisible() then
      -- Stats Row
      local statsRow = contentPvP:getChildById('statsRow')
      if statsRow then
          statsRow:destroyChildren()
          -- Use fixed width since layout might not be ready
          local cardWidth = 280 
          
          for _, stat in ipairs(profileData.combatRecord.stats) do
              local card = g_ui.createWidget('CombatStatCard', statsRow)
              card:setWidth(cardWidth)
              
              card:getChildById('title'):setText(stat.title)
              card:getChildById('value'):setText(stat.value)
              card:getChildById('underline'):setBackgroundColor(stat.color)
          end
      end
      
      -- Guild War
      local gwCard = contentPvP:getChildById('guildWarCard')
      if gwCard then
          gwCard:getChildById('gwValue'):setText(profileData.combatRecord.guildWar.contribution)
          gwCard:getChildById('gwRank'):setText(profileData.combatRecord.guildWar.rank)
          
          local gwBar = gwCard:getChildById('gwProgressBar')
          local gwBarBg = gwCard:getChildById('gwProgressBarBg')
          if gwBar and gwBarBg then
              local percent = profileData.combatRecord.guildWar.percent
              gwBar:setWidth(gwBarBg:getWidth() * (percent / 100))
          end
      end
      
      -- Combat History
      local historyList = contentPvP:getChildById('combatHistoryList')
      if historyList then
          historyList:destroyChildren()
          for _, match in ipairs(profileData.combatRecord.history) do
              local panel = g_ui.createWidget('CombatMatchPanel', historyList)
              panel:setWidth(historyList:getWidth() - 14) -- Subtract scrollbar width
              
              -- Common data
              panel:recursiveGetChildById('levelValue'):setText(match.level)
              panel:getChildById('name'):setText(match.name)
              panel:getChildById('location'):setText(match.location)
              panel:getChildById('timeLabel'):setText(match.time)
              
              -- Type specific styling
              local statusIndicator = panel:getChildById('statusIndicator')
              local levelBox = panel:getChildById('levelBox')
              local levelTitle = panel:recursiveGetChildById('levelTitle')
              local outcomeLabel = panel:getChildById('outcomeLabel')
              
              if match.type == 'victory' then
                  statusIndicator:setBackgroundColor('#1fbf6e')
                  levelBox:setBorderColor('#1fbf6e')
                  levelTitle:setColor('#1fbf6e')
                  outcomeLabel:setText('VICTORY')
                  outcomeLabel:setColor('#1fbf6e')
              elseif match.type == 'defeat' then
                  statusIndicator:setBackgroundColor('#ff5555')
                  levelBox:setBorderColor('#ff5555')
                  levelTitle:setColor('#ff5555')
                  outcomeLabel:setText('DEFEAT')
                  outcomeLabel:setColor('#ff5555')
              end
          end
      end
  end

  -- Content: Betrayals (Bingo Book)
  local contentBetrayals = ui:recursiveGetChildById('contentBetrayals')
  if contentBetrayals and contentBetrayals:isVisible() then
      -- Actions
      local actionPanel = contentBetrayals:getChildById('betrayalActions')
      if actionPanel then
          actionPanel:destroyChildren()
          for _, action in ipairs(profileData.betrayalData.actions) do
              local btn = g_ui.createWidget('BankActionButton', actionPanel)
              btn:getChildById('text'):setText(action.text)
              btn:getChildById('icon'):setImageSource(action.icon)
              btn:getChildById('icon'):setImageColor(action.color)
              btn:setWidth(280)
          end
      end
      
      -- Bingo Book
      local grid = contentBetrayals:getChildById('bingoBookGrid')
      if grid then
          grid:destroyChildren()
          for _, criminal in ipairs(profileData.betrayalData.bingoBook) do
              local card = g_ui.createWidget('BingoBookCard', grid)
              card:getChildById('name'):setText(criminal.name)
              card:getChildById('rank'):setText(criminal.rank)
              card:getChildById('bounty'):setText(criminal.bounty)
              -- card:getChildById('avatar'):setImageSource(criminal.avatar) 
          end
      end
  end

  -- Content: Bank
  local contentBank = ui:recursiveGetChildById('contentBank')
  if contentBank and contentBank:isVisible() then
      -- Actions
      local actionPanel = contentBank:getChildById('bankActions')
      if actionPanel then
          actionPanel:destroyChildren()
          for _, action in ipairs(profileData.bankData.actions) do
              local btn = g_ui.createWidget('BankActionButton', actionPanel)
              btn:getChildById('text'):setText(action.text)
              btn:getChildById('icon'):setImageSource(action.icon)
              btn:getChildById('icon'):setImageColor(action.color)
              btn:setWidth(280) 
          end
      end

      -- Transactions
      local list = contentBank:getChildById('transactionList')
      if list then
          list:destroyChildren()
          for _, trans in ipairs(profileData.bankData.transactions) do
              local card = g_ui.createWidget('BankTransactionCard', list)
              card:setWidth(list:getWidth())
              card:getChildById('title'):setText(trans.title)
              card:getChildById('date'):setText(trans.date)
              card:getChildById('amount'):setText(trans.amount)
              card:getChildById('detail'):setText(trans.detail)
              
              if trans.type == 'income' then
                  card:getChildById('amount'):setColor('#1fbf6e')
                  card:getChildById('icon'):setImageSource('/images/game/profile/icon_down')
                  card:getChildById('icon'):setImageColor('#1fbf6e')
              else
                  card:getChildById('amount'):setColor('#888888')
                  card:getChildById('icon'):setImageSource('/images/game/profile/icon_up')
                  card:getChildById('icon'):setImageColor('#ff5555')
              end
          end
      end
  end
end
