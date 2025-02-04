-- localize common functions
local djui_chat_message_create,network_send,tonumber = djui_chat_message_create,network_send,tonumber

-- main command
function mario_hunt_command(msg)
  local np = gNetworkPlayers[0]

  if not has_mod_powers(0) and msg ~= "unmod" and msg ~= "" and msg ~= "menu" then
    djui_chat_message_create(trans("not_mod"))
    return true
  elseif marioHuntCommands == nil or #marioHuntCommands < 1 then
    setup_commands()
  end

  local args = split(msg," ",2)
  local usedCmd = args[1] or ""
  local data = args[2] or ""
  --djui_chat_message_create("!"..usedCmd.."! !"..data.."!")
  if usedCmd == "" or usedCmd == "menu" then
    if not is_game_paused() then
      if menu then
        close_menu()
      else
        menu_reload()
        menu = true
        menu_enter()
      end
    end
    return true
  elseif usedCmd == "help" then
    local cmdPerPage = 3

    if tonumber(data) == nil and data ~= "" then
      local foundCommand = false
      for i,cdata in ipairs(marioHuntCommands) do
        if cdata[1] == data or cdata[2] == data then
          local desc = trans(cdata[1] .. "_desc")
          local hidden = false
          if cdata[4] == true then
            if not has_mod_powers(0,true) then
              hidden = true
            end
          end

          if not hidden then
            foundCommand = true
            djui_chat_message_create("/mh " .. cdata[1] .. " " .. desc)
          end
          break
        end
      end
      if not foundCommand then
        djui_chat_message_create(trans("bad_command"))
      end
      return true
    end
    local page = tonumber(usedCmd) or tonumber(data) or 1
    page = math.floor(page)
    local maxPage = 8
    if has_mod_powers(0,true) then maxPage = math.ceil(#marioHuntCommands / cmdPerPage) end

    if page > maxPage then
      page = maxPage
    elseif page < 1 then
      page = 1
    end

    djui_chat_message_create(trans("page",page,maxPage))
    for i,cdata in ipairs(marioHuntCommands) do
      if i > (page-1) * cmdPerPage and i <= page * cmdPerPage then
        local desc = trans(cdata[1] .. "_desc")
        local hidden = false
        if cdata[4] == true then
          if not has_mod_powers(0,true) then
            hidden = true
          end
        end

        if not hidden then
          djui_chat_message_create("/mh " .. cdata[1] .. " " .. desc)
        end
      elseif i > (page + 1) * 5 then
        break
      end
    end
  else
    local cmd = nil
    for i,cdata in ipairs(marioHuntCommands) do
      if cdata[1] == usedCmd or cdata[2] == usedCmd then
        cmd = cdata
        break
      end
    end
    if cmd ~= nil then
      local func = cmd[3]

      if (not func(data)) then
        djui_chat_message_create(trans("bad_param"))
      end
    else
      djui_chat_message_create(trans("bad_command"))
      return true
    end
  end
  return true
end

-- start game
function start_game(msg)
  -- count runners
  local runners = 0
  for i=0,(MAX_PLAYERS-1) do
    if gPlayerSyncTable[i].team == 1 and gNetworkPlayers[i].connected then
      runners = runners + 1
    end
  end
  if runners < 1 then
    if gGlobalSyncTable.mhMode ~= 2 then
      djui_chat_message_create(trans("error_no_runners"))
      return true
    else
      local singlePlayer = true
      for i=1,MAX_PLAYERS-1 do
        local np = gNetworkPlayers[i]
        local sMario = gPlayerSyncTable[i]
        if np.connected and sMario.spectator ~= 1 then
          singlePlayer = false
          break
        end
      end
      if singlePlayer then
        become_runner(gPlayerSyncTable[0])
      else
        djui_chat_message_create(trans("error_no_runners"))
        return true
      end
    end
  end

  local cmd = "none"
  if msg ~= nil and msg ~= "" then
    cmd = msg
  end
  network_send_include_self(true, {
    id = PACKET_MH_START,
    cmd = cmd,
  })
  return true
end

-- runs network_send and also the respective function for this user
function network_send_include_self(reliable, data)
    network_send(reliable, data)
    sPacketTable[data.id](data, true)
end

function change_team_command(msg)
  local playerID,np = get_specified_player(msg)
  if playerID == nil then return true end

  local sMario = gPlayerSyncTable[playerID]
  if sMario.team ~= 1 then
    become_runner(sMario)
  else
    become_hunter(sMario)
  end
  network_send_include_self(false, {id = PACKET_ROLE_CHANGE, index = np.globalIndex})
  return true
end

function set_life_command(msg)
  local args = split(msg, " ")
  local lookingFor = ""
  local lives = args[1] or "no"
  if args[2] ~= nil then
    lookingFor = args[1]
    lives = args[2]
  end

  lives = tonumber(lives)
  if lives == nil or lives < 0 or lives > 100 or math.floor(lives) ~= lives then
    return false
  end

  local playerID,np = get_specified_player(lookingFor)
  if playerID == nil then return true end

  local sMario = gPlayerSyncTable[playerID]
  local name = remove_color(np.name)
  if gGlobalSyncTable.mhState == 0 then
    djui_chat_message_create(trans("not_started"))
  elseif sMario.runnerLives ~= nil then
    sMario.runnerLives = lives
    djui_chat_message_create(trans_plural("set_lives",name,lives))
  else
    djui_chat_message_create(trans("not_runner",name))
  end
  return true
end

function allow_leave_command(msg)
  local playerID,np = get_specified_player(msg)
  if playerID == nil then return true end

  local sMario = gPlayerSyncTable[playerID]
  local name = remove_color(np.name)
  sMario.allowLeave = true
  djui_chat_message_create(trans("may_leave",name))
  return true
end

function add_runner(msg)
  local runners = tonumber(msg)
  if msg == "" or msg == 0 or msg == "auto" then
    runners = 0 -- TBD
  elseif runners == nil or runners ~= math.floor(runners) or runners < 1 then
    return false
  end

  -- get current hunters
  local currHunterIDs = {}
  local goodHunterIDs = {}
  local runners_available = 0
  local currPlayers = 0
  local currRunners = 0
  for i=0,(MAX_PLAYERS-1) do
    local np = gNetworkPlayers[i]
    local sMario = gPlayerSyncTable[i]
    if np.connected and (sMario.spectator ~= 1 or sMario.team == 1) then
      if sMario.team ~= 1 then
        if sMario.beenRunner == 0 then
          runners_available = runners_available + 1
          table.insert(goodHunterIDs, np.localIndex)
        end
        table.insert(currHunterIDs, np.localIndex)
      else
        currRunners = currRunners + 1
      end
      currPlayers = currPlayers + 1
    end
  end

  if runners == 0 then -- calculate good amount of runners
    runners = (currPlayers+2)//4-currRunners -- 3 hunters per runner (4 max with 16 player lobby)
    if runners <= 0 then
      djui_chat_message_create(trans("no_runners_added"))
      return true
    end
  end

  if #currHunterIDs < (runners + 1) then
    djui_chat_message_create(trans("must_have_one"))
    return true
  elseif runners_available < runners then -- if everyone has been a runner before, ignore recent status
    print("Not enough recent runners! Ignoring recent status")
    goodHunterIDs = currHunterIDs
  end

  local runnerNames = {}
  for i=1,runners do
    local selected = math.random(1, #goodHunterIDs)
    local lIndex = goodHunterIDs[selected]
    local sMario = gPlayerSyncTable[lIndex]
    local np = gNetworkPlayers[lIndex]
    become_runner(sMario)
    network_send_include_self(false, {id = PACKET_ROLE_CHANGE, index = np.globalIndex})
    table.insert(runnerNames, remove_color(np.name))
    table.remove(goodHunterIDs, selected)
  end

  local text = trans("added")
  for i=1,#runnerNames do
    text = text .. runnerNames[i] .. ", "
  end
  text = text:sub(1,-3)
  djui_chat_message_create(text)
  return true
end

function runner_randomize(msg)
  local runners = tonumber(msg)
  if msg == nil or msg == "" or msg == 99 or msg == 0 or msg == "auto" then
    runners = 0 -- TBD
  elseif (runners == nil or runners ~= math.floor(runners) or runners < 1) then
    return false
  end

  -- get current hunters
  local currPlayerIDs = {}
  local goodPlayerIDs = {}
  local runners_available = 0
  for i=0,(MAX_PLAYERS-1) do
    local np = gNetworkPlayers[i]
    local sMario = gPlayerSyncTable[i]
    become_hunter(sMario)
    if np.connected and sMario.spectator ~= 1 then
      if sMario.beenRunner == 0 then
        runners_available = runners_available + 1
        table.insert(goodPlayerIDs, np.localIndex)
      end
      table.insert(currPlayerIDs, np.localIndex)
    end
  end

  if runners == 0 then -- calculate good amount of runners
    runners = (#currPlayerIDs+2)//4 -- 3 hunters per runner (4 max with 16 player lobby)
    if runners <= 0 then
      djui_chat_message_create(trans("must_have_one"))
      return true
    end
  end

  if #currPlayerIDs < (runners + 1) then
    djui_chat_message_create(trans("must_have_one"))
    return true
  elseif runners_available < runners then -- if everyone has been a runner before, ignore recent status
    print("Not enough recent runners! Ignoring recent status")
    goodPlayerIDs = currPlayerIDs
  end

  local runnerNames = {}
  for i=1,runners do
    local selected = math.random(1, #goodPlayerIDs)
    local lIndex = goodPlayerIDs[selected]
    local sMario = gPlayerSyncTable[lIndex]
    local np = gNetworkPlayers[lIndex]
    become_runner(sMario)
    network_send_include_self(false, {id = PACKET_ROLE_CHANGE, index = np.globalIndex})
    table.insert(runnerNames, remove_color(np.name))
    table.remove(goodPlayerIDs, selected)
  end

  local text = trans("runners_are")
  for i=1,#runnerNames do
    text = text .. runnerNames[i] .. ", "
  end
  text = text:sub(1,-3)
  djui_chat_message_create(text)
  return true
end

function become_runner(sMario)
  sMario.team = 1
  sMario.runnerLives = gGlobalSyncTable.runnerLives
  sMario.runTime = 0
  sMario.allowLeave = false
end

function become_hunter(sMario)
  sMario.team = 0
  sMario.runnerLives = nil
  sMario.runTime = nil
  sMario.allowLeave = false
end

function runner_lives(msg)
  local num = tonumber(msg)
  if num ~= nil and num >= 0 and num <= 99 and math.floor(num) == num then
    gGlobalSyncTable.runnerLives = num
    djui_chat_message_create(trans("set_lives_total",num))
    return true
  end
  return false
end

function time_needed_command(msg)
  if gGlobalSyncTable.starMode and gGlobalSyncTable.mhMode ~= 2 then
    djui_chat_message_create(trans("wrong_mode"))
    return true
  end
  local num = tonumber(msg)
  if num ~= nil then
    gGlobalSyncTable.runTime = math.floor(num * 30)
    if gGlobalSyncTable.mhMode ~= 2 then
      djui_chat_message_create(trans("need_time_feedback",num))
    else
      djui_chat_message_create(trans("game_time",num))
    end
    return true
  end
  return false
end

function stars_needed_command(msg)
  if not gGlobalSyncTable.starMode or gGlobalSyncTable.mhMode == 2 then
    djui_chat_message_create(trans("wrong_mode"))
    return true
  end
  local num = tonumber(msg)
  if num ~= nil and num >= 0 and num < 8 then
    gGlobalSyncTable.runTime = num
    djui_chat_message_create(trans("need_stars_feedback",num))
    return true
  end
  return false
end

function auto_command(msg)
  if gGlobalSyncTable.mhMode ~= 2 then
    djui_chat_message_create(trans("wrong_mode"))
    return true
  end

  local num = tonumber(msg)
  if string.lower(msg) == "on" then
    num = 99
  elseif string.lower(msg) == "off" then
    num = 0
  elseif num == nil or math.floor(num) ~= num then
    return false
  elseif num > (MAX_PLAYERS-1) then
    djui_chat_message_create(trans("must_have_one"))
    return true
  end

  if num == 99 then
    gGlobalSyncTable.gameAuto = 99
    djui_chat_message_create(trans("auto_on"))
    if gGlobalSyncTable.mhState == 0 then
      gGlobalSyncTable.mhTimer = 20 * 30 -- 20 seconds
    end
  elseif num > 0 then
    gGlobalSyncTable.gameAuto = num
    local runners = trans("runners")
    if num == 1 then runners = trans("runner") end
    djui_chat_message_create(string.format("%s (%d %s)",trans("auto_on"),num,runners))
    if gGlobalSyncTable.mhState == 0 then
      gGlobalSyncTable.mhTimer = 20 * 30 -- 20 seconds
    end
  else
    gGlobalSyncTable.gameAuto = 0
    djui_chat_message_create(trans("auto_off"))
    if gGlobalSyncTable.mhState == 0 then
      gGlobalSyncTable.mhTimer = 0 -- don't set
    end
  end
  return true
end

function star_count_command(msg)
  local num = tonumber(msg)
  if num ~= nil and num >= -1 and num <= ROMHACK.max_stars and math.floor(num) == num then
    gGlobalSyncTable.starRun = num
    if num ~= -1 then
      djui_chat_message_create(trans("new_category",num))
    else
      djui_chat_message_create(trans("new_category_any"))
    end
    return true
  end
  return false
end

function change_game_mode(msg,mode)
  if mode == 0 or string.lower(msg) == "normal" then
    gGlobalSyncTable.mhMode = 0

    -- defaults
    gGlobalSyncTable.runnerLives = 1
    gGlobalSyncTable.runTime = 7200 -- 4 minutes
    gGlobalSyncTable.anarchy = 0
    gGlobalSyncTable.dmgAdd = 0
    if gGlobalSyncTable.starMode then gGlobalSyncTable.runTime = 2 end

    gGlobalSyncTable.gameAuto = 0
    if gGlobalSyncTable.mhState == 0 then
      gGlobalSyncTable.mhTimer = 0
    end
    
    omm_disable_non_stop_mode(false)
  elseif mode == 1 or string.lower(msg) == "switch" then
    gGlobalSyncTable.mhMode = 1

    -- defaults
    gGlobalSyncTable.runnerLives = 0
    gGlobalSyncTable.runTime = 7200 -- 4 minutes
    gGlobalSyncTable.anarchy = 0
    gGlobalSyncTable.dmgAdd = 0
    if gGlobalSyncTable.starMode then gGlobalSyncTable.runTime = 2 end

    gGlobalSyncTable.gameAuto = 0
    if gGlobalSyncTable.mhState == 0 then
      gGlobalSyncTable.mhTimer = 0
    end
    
    omm_disable_non_stop_mode(false)
  elseif mode == 2 or string.lower(msg) == "mini" then
    local np = gNetworkPlayers[0]
    gGlobalSyncTable.mhMode = 2
    
    -- defaults
    gGlobalSyncTable.runnerLives = 0
    gGlobalSyncTable.runTime = 9000 -- 5 minutes
    gGlobalSyncTable.anarchy = 1
    gGlobalSyncTable.dmgAdd = 2

    gGlobalSyncTable.gameLevel = np.currLevelNum
    gGlobalSyncTable.getStar = np.currActNum
    omm_disable_non_stop_mode(true)
  else
    return false
  end

  load_settings(true)
  return true
end

-- TroopaParaKoopa's pause mod
function pause_command(msg)
  if msg == "all" or msg == nil or msg == "" then
    if gGlobalSyncTable.pause then
      gGlobalSyncTable.pause = false
      for i=0,(MAX_PLAYERS-1) do
        gPlayerSyncTable[i].pause = false
      end
      djui_chat_message_create(trans("all_unpaused"))
    else
      gGlobalSyncTable.pause = true
      for i=0,(MAX_PLAYERS-1) do
        gPlayerSyncTable[i].pause = true
      end
      djui_chat_message_create(trans("all_paused"))
    end
    return true
  end

  local playerID,np = get_specified_player(msg)
  if playerID == nil then return true end

  local sMario = gPlayerSyncTable[playerID]
  local name = remove_color(np.name)
  if sMario.pause then
    sMario.pause = false
    djui_chat_message_create(trans("player_unpaused",name))
  else
    sMario.pause = true
    djui_chat_message_create(trans("player_paused",name))
  end
  return true
end

-- to get around a weird bug, we save a bunch of shorter values until it's short enough to save without causing issues
function mod_storage_save_fix_bug(key, value_)
  local value = value_
  local old = mod_storage_load(key)
  if old ~= nil then
    while string.len(old) - 4 > string.len(value) do
      old = string.sub(old,1,-5)
      mod_storage_save(key, old)
    end
  end
  mod_storage_save(key, value)
end

-- gets the name and color of the user's role (color is either a table or string)
function get_role_name_and_color(sMario)
  local roleName = ""
  local color = {r = 255, g = 92, b = 92} -- red
  local colorString = "\\#ff5a5a\\"
  if sMario.team == 1 then
    if sMario.hard == 1 then
      color = {r = 255, g = 255, b = 92} -- yellow
      colorString = "\\#ffff5a\\"
    elseif sMario.hard == 2 then
      color = {r = 180, g = 92, b = 255} -- purple
      colorString = "\\#b45aff\\"
    else
      color = {r = 0, g = 255, b = 255} -- cyan
      colorString = "\\#00ffff\\"
    end
    roleName = trans("runner")
  elseif sMario.team == nil then -- joining
    color = {r = 169, g = 169, b = 169} -- grey
    colorString = "\\#a9a9a9\\"
    roleName = trans("menu_unknown")
  elseif sMario.spectator ~= 1 then
    roleName = trans("hunter")
  else
    color = {r = 169, g = 169, b = 169} -- grey
    colorString = "\\#a9a9a9\\"
    roleName = trans("spectator")
  end
  return roleName,colorString,color
end

function set_lobby_music(month)
  if month ~= 10 and month ~= 12 then
    set_background_music(0,0x53,0)
  elseif month == 10 then
    set_background_music(0,SEQ_LEVEL_SPOOKY,0)
  else
    set_background_music(0,SEQ_LEVEL_SNOW,0)
  end
end

-- some minor conversion functions
function bool_to_int(bool)
  return (bool and 1) or 0
end

function is_zero(int)
  return (int == 0 and 1) or 0
end