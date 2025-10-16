-- client.waypoint.lua (deterministic waypoint routing with hard fallback)
local function toVec3(v)
  if type(v) == 'vector3' then return v end
  if type(v) == 'table' and v.x and v.y and v.z then return vector3(v.x+0.0, v.y+0.0, v.z+0.0) end
  return nil
end

local function GetEntityFromNet(net)
  if not net then return 0 end
  if NetworkDoesEntityExistWithNetworkId(net) then
      return NetworkGetEntityFromNetworkId(net)
  end
  return 0
end

local function notify(msg)
  TriggerEvent('esx_prisonerconvoy:cl_notify', msg)
end

local function closestRoadWithHeading(pos)
  local ok, nodePos, heading = GetClosestVehicleNodeWithHeading(pos.x, pos.y, pos.z, 1, 3.0, 0)
  if ok then
      return vector3(nodePos.x, nodePos.y, nodePos.z + 1.0), heading
  else
      return pos, GetEntityHeading(PlayerPedId())
  end
end

local function snapWaypoints(waypoints)
  local snapped = {}
  for i,wp in ipairs(waypoints) do
    local v = toVec3(wp); if v then
      local node,_ = closestRoadWithHeading(v)
      table.insert(snapped, node)
    end
  end
  return snapped
end

local function matchRouteForStation(station)
  local bestIdx, bestD = nil, 1e9
  for idx,route in pairs(Config.Routes or {}) do
    local rpos = toVec3(route.station)
    if rpos then
      local d = #(station - rpos)
      if d < bestD then bestD, bestIdx = d, idx end
    end
  end
  if bestIdx and bestD <= (Config.RouteStationMatchDist or 60.0) then
    return Config.Routes[bestIdx]
  end
  return nil
end

local function TaskDriveSmart(driver, bus, dest, speed, style)
  TaskVehicleDriveToCoordLongrange(driver, bus, dest.x, dest.y, dest.z, speed, style or (Config.DriveStyle or 7443), 5.0)
  SetDriveTaskDrivingStyle(driver, style or (Config.DriveStyle or 443))
  SetDriverAbility(driver, 1.0)
  SetDriverAggressiveness(driver, 0.5)
  SetPedKeepTask(driver, true)
end

-- Shared anti-stall helpers
local function ensureOnRoad(pos)
  local node, heading = closestRoadWithHeading(pos)
  return node, heading
end

local function gentleNudgeToward(bus, posDest, nudgeDist, clearRadius)
  if not DoesEntityExist(bus) then return end
  local pos = GetEntityCoords(bus)
  local dir = posDest - pos
  local d = #(dir)
  if d < 0.01 then return end
  dir = dir / d
  local newPos = pos + (dir * (nudgeDist or 6.0))
  local roadPos, roadHeading = ensureOnRoad(newPos)
  ClearAreaOfVehicles(roadPos.x, roadPos.y, roadPos.z, clearRadius or 6.0, false, false, false, false, false)
  ClearArea(roadPos.x, roadPos.y, roadPos.z, clearRadius or 6.0, true, false, false, false)
  SetEntityCoords(bus, roadPos.x, roadPos.y, roadPos.z, true, false, false, false)
  SetEntityHeading(bus, roadHeading)
  SetVehicleOnGroundProperly(bus)
end

-- Waypoint-driven leg execution with hard-fallback
local function driveWaypoints(phaseArrivedEvent, busNet, driverNet, stationPos, waypoints, finalDest, speed, style, arriveDist, delayMs)
  local dms = tonumber(delayMs or 0) or 0; if dms > 0 then Wait(dms) end

  local bus = GetEntityFromNet(busNet)
  local drv = GetEntityFromNet(driverNet)
  if bus == 0 or drv == 0 then
      TriggerServerEvent('esx_prisonerconvoy:sv_stalled_cleanup'); return
  end

  local arrive = arriveDist or (Config.MaxDriveRangeForArrive or 15.0)
  local timeout = (Config.StuckTimeoutSeconds or 420) * 1000
  local anti = Config.AntiStall or {}
  local speedThresh  = anti.SpeedThreshold or 1.2
  local stallSeconds = anti.SecondsStalled or 6
  local maxRetries   = anti.MaxRetries or 4
  local nudgeDist    = anti.NudgeDistance or 6.0
  local clearRadius  = anti.ClearRadius or 6.0
  local maxStallsLeg = Config.RouteMaxStallsPerLeg or 3

  FreezeEntityPosition(bus, false)
  FreezeEntityPosition(drv, false)

  -- Build leg list: snapped waypoints then finalDest
  local snapped = snapWaypoints(waypoints)
  table.insert(snapped, toVec3(finalDest))

  local started = GetGameTimer()

  for i,wp in ipairs(snapped) {
    local target = wp
    local legStalls = 0
    local lastMoving = GetGameTimer()
    local retries = 0

    -- Issue drive for this leg
    TaskDriveSmart(drv, bus, target, speed or (Config.DriveSpeed or 18.0), style)

    while true do
      Wait(250)
      if not DoesEntityExist(bus) or not DoesEntityExist(drv) then
        TriggerServerEvent('esx_prisonerconvoy:sv_stalled_cleanup'); return
      end

      local bpos = GetEntityCoords(bus)
      local distToTarget = #(bpos - target)
      local distToFinal  = #(bpos - snapped[#snapped])

      -- Arrived target (advance to next leg)
      if distToTarget <= arrive then
        break
      end

      -- Arrived final
      if i == #snapped and distToFinal <= arrive then
        FreezeEntityPosition(bus, true); FreezeEntityPosition(drv, true)
        TriggerServerEvent(phaseArrivedEvent)
        return
      end

      -- Global timeout
      if GetGameTimer() - started > timeout then
        TriggerServerEvent('esx_prisonerconvoy:sv_stalled_cleanup')
        return
      end

      -- Anti-stall with per-leg hard fallback
      local spd = GetEntitySpeed(bus)
      if spd > speedThresh then
        lastMoving = GetGameTimer()
      elseif (GetGameTimer() - lastMoving) > (stallSeconds * 1000) then
        retries = retries + 1
        if retries <= maxRetries then
          TaskDriveSmart(drv, bus, target, speed or (Config.DriveSpeed or 18.0), style)
          lastMoving = GetGameTimer()
        else
          -- Nudge first
          gentleNudgeToward(bus, target, nudgeDist, clearRadius)
          TaskDriveSmart(drv, bus, target, speed or (Config.DriveSpeed or 18.0), style)
          lastMoving = GetGameTimer()
          retries = 0
          legStalls = legStalls + 1
          if legStalls >= maxStallsLeg then
            -- HARD FALLBACK: warp to next leg's road node (or final if last leg)
            local nextIdx = math.min(i + 1, #snapped)
            local warpPos,_ = closestRoadWithHeading(snapped[nextIdx])
            SetEntityCoords(bus, warpPos.x, warpPos.y, warpPos.z, true, false, false, false)
            SetVehicleOnGroundProperly(bus)
            TaskDriveSmart(drv, bus, snapped[nextIdx], speed or (Config.DriveSpeed or 18.0), style)
            legStalls = 0
          end
        end
      end
    end
  end

  -- If loop ends unexpectedly
  TriggerServerEvent('esx_prisonerconvoy:sv_stalled_cleanup')
end

-- Replace the movement handlers to prefer deterministic routes
RegisterNetEvent('esx_prisonerconvoy:cl_depart_to_prison', function(busNet, driverNet, destTbl, speed, style, arriveDist, delaySeconds)
  -- stationPos is not directly provided here. We infer it from the bus position once.
  local bus = GetEntityFromNet(busNet)
  if bus == 0 then TriggerServerEvent('esx_prisonerconvoy:sv_stalled_cleanup'); return end
  local stationPos = GetEntityCoords(bus)

  local route = matchRouteForStation(stationPos)
  if route then
    notify("Routing via predefined convoy path.")
    driveWaypoints('esx_prisonerconvoy:sv_arrived_prison_check', busNet, driverNet, stationPos, route.waypoints, route.waypoints[#route.waypoints], speed, style, arriveDist, (tonumber(delaySeconds) or 0) * 1000)
  else
    -- Fallback to original event (if you kept segmented or simple drive in your file, it will be present)
    TriggerEvent('__esx_prisonerconvoy_internal:segmented_or_simple_depart', busNet, driverNet, destTbl, speed, style, arriveDist, delaySeconds)
  end
end)

RegisterNetEvent('esx_prisonerconvoy:cl_go_to_drop', function(busNet, driverNet, destTbl, speed, style, arriveDist)
  -- From checkpoint to drop-off: we can reuse the last matched route's final
  local bus = GetEntityFromNet(busNet)
  if bus == 0 then TriggerServerEvent('esx_prisonerconvoy:sv_stalled_cleanup'); return end
  local stationPos = GetEntityCoords(bus)

  local route = matchRouteForStation(stationPos)  -- will likely fail here, so just use a generic leg from current -> dest
  if route then
    notify("Routing to drop via predefined final leg.")
    driveWaypoints('esx_prisonerconvoy:sv_arrived_drop', busNet, driverNet, stationPos, { toVec3(destTbl) }, destTbl, speed, style, arriveDist, 0)
  else
    TriggerEvent('__esx_prisonerconvoy_internal:segmented_or_simple_drop', busNet, driverNet, destTbl, speed, style, arriveDist)
  end
end)
