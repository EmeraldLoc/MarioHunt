-- named this way so it loads last

_G.mhExists = true -- use this to detect MarioHunt
_G.mhVersion = "v2.2" -- version string
_G.mhApi = {}

-- check mhSetup.lua for more info
_G.mhApi.RomhackSetup = function()
  return nil
end

-- takes a local player index and returns 1 (runner) or 0 (hunter)
_G.mhApi.getTeam = function(index)
  local sMario = gPlayerSyncTable[index]
  return sMario.team or 0
end

-- like above, but returns true if the player is a spectator instead
_G.mhApi.isSpectator = function(index)
  local sMario = gPlayerSyncTable[index]
  return (sMario.spectator == 1)
end

-- also like above, but returns true if the player is in hard mode instead
_G.mhApi.isHardMode = function(index)
  local sMario = gPlayerSyncTable[index]
  return (sMario.hard == 1)
end

-- returns true if the player is in extreme mode
_G.mhApi.isExtremeMode = function(index)
  local sMario = gPlayerSyncTable[index]
  return (sMario.hard == 2)
end

-- screw it, just read whatever field you want
_G.mhApi.getPlayerField = function(index,field)
  return gPlayerSyncTable[index][field]
end
_G.mhApi.getGlobalField = function(field)
  return gGlobalSyncTable[field]
end

-- returns game mode
_G.mhApi.getMode = function()
  return gGlobalSyncTable.mhMode or 0
end

-- returns game state
_G.mhApi.getState = function()
  return gGlobalSyncTable.mhState or 0
end

-- become a runner
_G.mhApi.become_runner = function(index)
  local sMario = gPlayerSyncTable[index]
  return become_runner(sMario)
end
-- become a hunter
_G.mhApi.become_hunter = function(index)
  local sMario = gPlayerSyncTable[index]
  return become_hunter(sMario)
end

-- returns a string, a color string, and a table, in that order
_G.mhApi.get_role_name_and_color = function(index)
  local sMario = gPlayerSyncTable[index]
  return get_role_name_and_color(sMario)
end

-- checks if a menu is open
_G.mhApi.isMenuOpen = function()
  return (menu or showingStats)
end

-- making some things global
_G.mhApi.interactionIsValid = on_interact
_G.mhApi.exitIsValid = on_pause_exit
_G.mhApi.pvpIsValid = allow_pvp_attack
_G.mhApi.getStarName = get_custom_star_name
_G.mhApi.trans = trans
_G.mhApi.trans_plural = trans_plural
_G.mhApi.valid_star = valid_star -- takes course, act, bool if we're *not* in minihunt, and bool if replicas are active
_G.mhApi.mod_powers = has_mod_powers -- the first argument is the local player index, the second is a bool if we're only looking for a dev
_G.mhApi.global_popup_lang = global_popup_lang -- takes language parameters and the lines paramter; check lang.lua
_G.mhApi.get_tag = get_tag -- takes index, returns string for tag shown in chat (like [DEV] or [1st Place])

-- this gets the local player's current kill combo
_G.mhApi.getKillCombo = get_kill_combo

-- for mods that use HOOK_ON_CHAT_MESSAGE to cancel messages, set this value to that function (check mute.lua with api_stuff for an example)
-- _G.mhApi.chatValidFunction

-- for mods that use HOOK_ON_CHAT_MESSAGE to modify chat messages, set this value to a function
-- This allows the message to be modified (for things like Swear Filter, etc.)
-- Return argument 1 to modify the message, and argument 2 to modify the sender's name
-- _G.mhApi.chatModifyFunction

-- Here's an example that replaces any message that contains "help" with "I don't need help, everything is fine" and replaces "Mario" in names with "[REDACTED]"
--[[
function hide_the_truth(m, msg_)
  local np = gNetworkPlayers[m.playerIndex]
  local playerColor = network_get_player_text_color_string(m.playerIndex)
  local name = playerColor .. np.name

  local msg = msg_
  if msg:lower():find("help") then
    msg = "I don't need help, everything is fine"
  end
  name = name:gsub("Mario","[REDACTED]")
  return msg,name
end
_G.mhApi.chatModifyFunction = hide_the_truth
]]

-- this function is called when a kill or runner death occurs, or when a player fails to rejoin
-- killer and killed are both global indexes (both may be nil)
-- runner is TRUE if the killed player was a runner
-- death is TRUE if the killed player was on their last life as a runner
-- time is the killed player's run time
-- newRunnerID is a global index containing the new runner (may be nil)
_G.mhApi.onKill = function(killer,killed,runner,death,time,newRunnerID)
  -- does nothing unless you set it
end
