-- client.lua (v1.5.0) — optimized single-file client
local locale = Locales and (Locales[Config.Locale] or Locales['en']) or {}

-- ============== UTIL & NOTIFY ==============
local function notify(msg)
  msg = tostring(msg or '')
  if ESX and ESX.ShowNotification then ESX.ShowNotification(msg)
  else TriggerEvent('chat:addMessage', { args = { '^3[Convoy]^7', msg } }) end
end

local function ensureModelLoaded(model)
  model = (type(model) == 'number') and model or joaat(model)
  if not IsModelInCdimage(model) then return false end
  RequestModel(model); local t = GetGameTimer() + 10000
  while not HasModelLoaded(model) and GetGameTimer() < t do Wait(0) end
  return HasModelLoaded(model)
end

local function applySiren(veh, cfg)
  if not (veh and DoesEntityExist(veh)) then return end
  local wantSound      = cfg and (cfg.SirensOn ~= false)
  local wantLightsOnly = cfg and (cfg.SirenLightsOn and not wantSound)
  if wantSound then
    SetVehicleSiren(veh, true); SetVehicleHasMutedSirens(veh, false)
  elseif wantLightsOnly then
    SetVehicleSiren(veh, true); SetVehicleHasMutedSirens(veh, true)
  else
    SetVehicleSiren(veh, false)
  end
end

-- ============== STATE ==============
local State = {
  active = false,
  bus = 0,
  lead = 0,
  rear = 0,
  prisoners_loaded = 0,
  route_index = 1,
  blips = {}
}

local function clearBlips()
  for _,b in ipairs(State.blips) do if DoesBlipExist(b) then RemoveBlip(b) end end
  State.blips = {}
end

AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  clearBlips()
end)

-- ============== BLIPS ==============
local function addBlip(ent, name)
  if not (Config.Blips and Config.Blips.Enabled) then return end
  if not (ent and DoesEntityExist(ent)) then return end
  local b = AddBlipForEntity(ent)
  SetBlipSprite(b, Config.Blips.LeadSprite or 56)
  SetBlipColour(b, Config.Blips.Colour or 3)
  SetBlipAsShortRange(b, true); BeginTextCommandSetBlipName('STRING')
  AddTextComponentString(name or 'Convoy'); EndTextCommandSetBlipName(b)
  table.insert(State.blips, b); return b
end

-- ============== SPAWN & SETUP ==============
local function spawnVehicle(model, at, opts)
  if not ensureModelLoaded(model) then return 0 end
  local v = CreateVehicle(joaat(model), at.x, at.y, at.z, at.w or 0.0, true, false)
  SetVehicleOnGroundProperly(v)
  SetVehicleHasBeenOwnedByPlayer(v, true)
  SetVehicleDoorsLocked(v, 1)
  SetEntityAsMissionEntity(v, true, true)
  if opts and opts.plate then SetVehicleNumberPlateText(v, opts.plate) end
  return v
end

local function spawnPed(model, at)
  if not ensureModelLoaded(model) then return 0 end
  local p = CreatePed(4, joaat(model), at.x, at.y, at.z, at.w or 0.0, true, true)
  SetEntityAsMissionEntity(p, true, true)
  SetBlockingOfNonTemporaryEvents(p, true)
  SetPedFleeAttributes(p, 0, false)
  SetPedCombatAttributes(p, 46, true)
  return p
end

-- ============== DRIVE HELPERS ==============
local DRIVE_STYLE = Config.DriveStyle or 443

local function taskDrive(ped, veh, dest, speed)
  TaskVehicleDriveToCoordLongrange(ped, veh, dest.x, dest.y, dest.z, speed or Config.LeadSpeedMS, DRIVE_STYLE, 10.0)
end

local function distance(a,b) return #(vector3(a.x,a.y,a.z) - vector3(b.x,b.y,b.z)) end

-- ============== ROUTE LOGIC ==============
local function getCurrentNode()
  local r = Config.CustomRoute
  if not (r and r.Enabled and r.Nodes and r.Nodes[State.route_index]) then return nil end
  return r.Nodes[State.route_index]
end

local function advanceNodeIfArrived(entity, arriveDist)
  local node = getCurrentNode(); if not node then return false end
  local pos = GetEntityCoords(entity)
  if #(pos - node) <= (arriveDist or (Config.CustomRoute and Config.CustomRoute.NodeArrive) or 12.0) then
    State.route_index = State.route_index + 1
    return true
  end
  return false
end

-- ============== START CONVOY (CLIENT) ==============
RegisterNetEvent('esx_prisonerconvoy:cl_start', function()
  if State.active then return end
  State.active = true
  State.route_index = 1

  -- spawn bus + driver at spawn point
  local bus = spawnVehicle(Config.BusModel, Config.BusSpawnPoint, { plate = 'PRISON' })
  if bus == 0 then notify('Failed to spawn bus.'); State.active=false; return end
  local driver = spawnPed(Config.DriverPedModel, Config.BusSpawnPoint)
  TaskWarpPedIntoVehicle(driver, bus, -1)

  -- spawn escorts: lead & rear (police)
  local lead = spawnVehicle('police', vector4(Config.BusSpawnPoint.x, Config.BusSpawnPoint.y + 5.0, Config.BusSpawnPoint.z, Config.BusSpawnPoint.w), nil)
  local lped = spawnPed(Config.GuardEscortPedModel, Config.BusSpawnPoint); TaskWarpPedIntoVehicle(lped, lead, -1)
  local rear = spawnVehicle('police', vector4(Config.BusSpawnPoint.x, Config.BusSpawnPoint.y - 7.0, Config.BusSpawnPoint.z, Config.BusSpawnPoint.w), nil)
  local rped = spawnPed(Config.GuardEscortPedModel, Config.BusSpawnPoint); TaskWarpPedIntoVehicle(rped, rear, -1)

  State.bus = bus; State.lead = lead; State.rear = rear

  -- blips
  addBlip(lead, Config.Blips.LeadName or 'Convoy Lead')
  addBlip(rear, Config.Blips.RearName or 'Convoy Rear')

  applySiren(lead, Config.Escort)
  applySiren(rear, Config.Escort)

  notify(locale.start_convoy or 'Starting prisoner convoy...')

  -- initial tasks
  local node = getCurrentNode()
  if node then
    taskDrive(lped, lead, node, Config.LeadSpeedMS)
    taskDrive(rped,  rear, node, Config.RearSpeedMS)
  end

  -- control loop
  CreateThread(function()
    while State.active do
      local node = getCurrentNode()
      if not node then
        -- final prison checkpoint
        local cp = Config.PrisonCheckpoint
        taskDrive(lped, lead, vector3(cp.x, cp.y, cp.z), Config.LeadSpeedMS)
        taskDrive(rped, rear, vector3(cp.x, cp.y, cp.z), Config.RearSpeedMS)
        local lp = GetEntityCoords(lead)
        if #(lp - vector3(cp.x, cp.y, cp.z)) < (Config.CustomRoute and Config.CustomRoute.FinalArrive or 15.0) then
          FreezeEntityPosition(State.bus, true)
          FreezeEntityPosition(lead, true)
          FreezeEntityPosition(rear, true)
          notify(locale.arriving or 'Arriving at prison checkpoint...')
          Wait((Config.PrisonCheckFreezeSeconds or 15) * 1000)
          TriggerServerEvent('esx_prisonerconvoy:sv_handoff_and_jail')
          State.active = false
          clearBlips()
          DeleteEntity(driver); DeleteEntity(lped); DeleteEntity(rped)
          DeleteEntity(State.bus); DeleteEntity(lead); DeleteEntity(rear)
          break
        end
      else
        -- keep escorts moving toward node; re-issue task if far/stalled
        local ld = #(GetEntityCoords(lead) - node)
        local rd = #(GetEntityCoords(rear) - node)
        if ld > (Config.Escort.RepathThresh or 28.0) then taskDrive(lped, lead, node, Config.CatchupSpeedMS) end
        if rd > (Config.Escort.RepathThresh or 28.0) then taskDrive(rped, rear, node, Config.CatchupSpeedMS) end
        advanceNodeIfArrived(lead, Config.CustomRoute.NodeArrive)
      end
      Wait(500)
    end
  end)
end)

-- ============== ANTI-STALL / UNSTUCK ==============
RegisterNetEvent('esx_prisonerconvoy:cl_unstuck', function()
  if not State.active then return end
  notify(locale.unstuck or 'Convoy anti-stall engaged (clearing path).')
  local p = PlayerPedId()
  ClearAreaOfPeds(GetEntityCoords(p), 30.0, 1)
  ClearAreaOfVehicles(GetEntityCoords(p), 30.0, false, false, false, false, false)
end)

-- ============== LOCAL JAIL UI ==============
local JailUI = { active=false, endTime=0 }
local function drawJailTimer()
  if not JailUI.active then return end
  local seconds = math.max(0, math.floor((JailUI.endTime - GetGameTimer())/1000))
  SetTextFont(4); SetTextProportional(0); SetTextScale(0.45,0.45)
  SetTextColour(255,255,255,255); SetTextOutline()
  SetTextEntry('STRING'); AddTextComponentString(('Jail: %dm %ds'):format(seconds//60, seconds%60))
  DrawText(0.88, 0.95)
end
CreateThread(function() while true do if JailUI.active then drawJailTimer() end Wait(0) end end)

RegisterNetEvent('esx_prisonerconvoy:cl_begin_local_jail', function(jailPointV4, minutes)
  local ped = PlayerPedId()
  local x,y,z,w = jailPointV4.x+0.0, jailPointV4.y+0.0, jailPointV4.z+0.0, (jailPointV4.w or 0.0)+0.0
  SetEntityCoords(ped, x, y, z, true, false, false, false)
  SetEntityHeading(ped, w)
  local base = tonumber(minutes) or (Config.AutoJailMinutes or 15)
  local clamped = math.max(base, 15)
  JailUI.active = true
  JailUI.endTime = GetGameTimer() + clamped*60*1000
end)

RegisterNetEvent('esx_prisonerconvoy:cl_release_local_jail', function(v4)
  JailUI.active = false
  local ped=PlayerPedId(); local x,y,z,w=v4.x+0.0,v4.y+0.0,v4.z+0.0,(v4.w or 0.0)+0.0
  SetEntityCoords(ped,x,y,z,true,false,false,false); SetEntityHeading(ped,w)
  notify(locale.released or 'You have served your sentence. You are released.')
end)
