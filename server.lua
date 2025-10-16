-- server.lua (v1.5.0) — ESX Legacy + mysql-async logging
ESX = exports['es_extended'] and exports['es_extended']:getSharedObject() or nil

local function getIdentifier(src)
  if ESX and ESX.GetPlayerFromId then
    local xPlayer = ESX.GetPlayerFromId(src)
    if xPlayer then return xPlayer.identifier end
  end
  return 'unknown:'..tostring(src)
end

-- Optional: simple jail log table (create if desired)
-- CREATE TABLE IF NOT EXISTS prisoner_jail_log (
--   id INT AUTO_INCREMENT PRIMARY KEY,
--   identifier VARCHAR(60) NOT NULL,
--   minutes INT NOT NULL,
--   created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
-- );

RegisterNetEvent('esx_prisonerconvoy:sv_handoff_and_jail', function()
  local src = source
  local id  = getIdentifier(src)
  local minutes = math.max(15, tonumber(Config and Config.AutoJailMinutes or 15) or 15)

  -- persist (optional)
  if MySQL and MySQL.Async and MySQL.Async.execute then
    MySQL.Async.execute(
      'INSERT INTO prisoner_jail_log (identifier, minutes) VALUES (@id, @m)',
      { ['@id']=id, ['@m']=minutes },
      function() end
    )
  end

  -- local (client-side) jail UI & teleport; adjust if using a real jail system
  TriggerClientEvent('esx_prisonerconvoy:cl_begin_local_jail', src, Config.UnjailLocation, minutes)

  -- release after time (server timer)
  SetTimeout(minutes*60*1000, function()
    if GetPlayerPing(src) > 0 then
      TriggerClientEvent('esx_prisonerconvoy:cl_release_local_jail', src, Config.UnjailLocation)
    end
  end)
end)

-- Command to start convoy (police only if enabled)
RegisterCommand('convoy_start', function(src)
  local allow = true
  if Config.RequirePoliceForStart then
    local xPlayer = ESX and ESX.GetPlayerFromId(src)
    if not (xPlayer and xPlayer.job and xPlayer.job.name == (Config.PoliceJob or 'police')) then
      allow = false
      TriggerClientEvent('esx_prisonerconvoy:cl_notify', src, Locales['en'].need_police or 'Police only.')
    end
  end
  if allow then
    TriggerClientEvent('esx_prisonerconvoy:cl_start', src)
  end
end, false)

RegisterCommand('convoy_unstuck', function(src)
  TriggerClientEvent('esx_prisonerconvoy:cl_unstuck', src)
end, false)
