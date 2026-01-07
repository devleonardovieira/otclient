function init()
  connect(g_game, { onPartyDetailedInfo = onPartyDetailedInfo })
  g_logger.info("Party Test Module loaded!")
end

function terminate()
  disconnect(g_game, { onPartyDetailedInfo = onPartyDetailedInfo })
end

function onPartyDetailedInfo(partyId, leaderId, members)
  g_logger.info("--------------------------------------------------")
  g_logger.info("Received Party Detailed Info:")
  g_logger.info("Party ID: " .. partyId)
  g_logger.info("Leader ID: " .. leaderId)
  g_logger.info("Member Count: " .. #members)
  
  for i, member in ipairs(members) do
    g_logger.info(string.format("  [%d] ID: %d, Name: %s, Level: %d, Vocation: %d, HP: %d/%d, Mana: %d/%d", 
      i, member.id, member.name, member.level, member.vocation, member.health, member.maxHealth, member.mana, member.maxMana))
  end
  g_logger.info("--------------------------------------------------")
end
