-- client.nav.lua (segmented routing + anti-stall)
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

local function nextSegmentToward(fromPos, dest, segLen)
    local dir = dest - fromPos
    local d = #(dir)
    if d < (segLen or 300.0) then return dest end
    dir = dir / d
    local ahead = fromPos + (dir * (segLen or 300.0))
    local node, _ = closestRoadWithHeading(ahead)
    return node
end

local function TaskDriveSmart(driver, bus, dest, speed, style)
    TaskVehicleDriveToCoordLongrange(driver, bus, dest.x, dest.y, dest.z, speed, style or (Config.DriveStyle or 443), 5.0)
    SetDriveTaskDrivingStyle(driver, style or (Config.DriveStyle or 443))
    SetDriverAbility(driver, 1.0)
    SetDriverAggressiveness(driver, 0.5)
    SetPedKeepTask(driver, true)
end

local function driveSegmented(phaseArrivedEvent, busNet, driverNet, destTbl, speed, style, arriveDist, delayMs)
    local dest = toVec3(destTbl); if not dest then return end
    local dms = tonumber(delayMs or 0) or 0; if dms > 0 then Wait(dms) end

    local bus = GetEntityFromNet(busNet)
    local drv = GetEntityFromNet(driverNet)
    if bus == 0 or drv == 0 then
        TriggerServerEvent('esx_prisonerconvoy:sv_stalled_cleanup'); return
    end

    local arrive = arriveDist or (Config.MaxDriveRangeForArrive or 15.0)
    local timeout = (Config.StuckTimeoutSeconds or 420) * 1000
    local segConf = Config.NavSegments or {}
    local anti = Config.AntiStall or {}
    local segEnabled   = (segConf.Enabled ~= false)
    local segLen       = segConf.SegmentLength or 300.0
    local segMaxHops   = segConf.MaxHops or 30
    local segDebug     = (segConf.DebugToasts == true)

    local speedThresh  = anti.SpeedThreshold or 1.2
    local stallSeconds = anti.SecondsStalled or 6
    local maxRetries   = anti.MaxRetries or 4
    local nudgeDist    = anti.NudgeDistance or 6.0
    local clearRadius  = anti.ClearRadius or 6.0

    local started = GetGameTimer()
    local lastMoving = GetGameTimer()
    local retries = 0

    FreezeEntityPosition(bus, false)
    FreezeEntityPosition(drv, false)

    local function ensureOnRoad(pos)
        local node, heading = closestRoadWithHeading(pos)
        return node, heading
    end

    local function gentleNudgeToward(posDest)
        if not DoesEntityExist(bus) then return end
        local pos = GetEntityCoords(bus)
        local dir = posDest - pos
        local d = #(dir)
        if d < 0.01 then return end
        dir = dir / d
        local newPos = pos + (dir * nudgeDist)
        local roadPos, roadHeading = ensureOnRoad(newPos)
        ClearAreaOfVehicles(roadPos.x, roadPos.y, roadPos.z, clearRadius, false, false, false, false, false)
        ClearArea(roadPos.x, roadPos.y, roadPos.z, clearRadius, true, false, false, false)
        SetEntityCoords(bus, roadPos.x, roadPos.y, roadPos.z, true, false, false, false)
        SetEntityHeading(bus, roadHeading)
        SetVehicleOnGroundProperly(bus)
    end

    local function driveTo(target)
        TaskDriveSmart(drv, bus, target, speed or (Config.DriveSpeed or 20.0), style)
    end

    local function debugToast(txt)
        if segDebug then notify(txt) end
    end

    local target = dest
    local hops = 0

    while true do
        Wait(250)
        if not DoesEntityExist(bus) or not DoesEntityExist(drv) then break end

        local bpos = GetEntityCoords(bus)
        local distToFinal = #(bpos - dest)

        if distToFinal <= arrive then
            FreezeEntityPosition(bus, true)
            FreezeEntityPosition(drv, true)
            TriggerServerEvent(phaseArrivedEvent)
            return
        end

        if GetGameTimer() - started > timeout then
            TriggerServerEvent('esx_prisonerconvoy:sv_stalled_cleanup')
            return
        end

        if segEnabled then
            if hops == 0 then
                target = nextSegmentToward(bpos, dest, segLen)
                driveTo(target)
                debugToast(("Routing via segment %d (%.0fm remaining)"):format(hops+1, distToFinal))
                hops = 1
            else
                local distToTarget = #(bpos - target)
                if distToTarget < (arrive/2) then
                    if distToFinal > arrive then
                        local nextHop = nextSegmentToward(bpos, dest, segLen)
                        if #(nextHop - target) > 3.0 then
                            target = nextHop
                            driveTo(target)
                            hops = hops + 1
                            debugToast(("Advancing to segment %d (%.0fm remaining)"):format(hops, distToFinal))
                            if hops > segMaxHops then
                                target = dest
                                driveTo(target)
                            end
                        end
                    end
                end
            end
        else
            target = dest
        end

        local spd = GetEntitySpeed(bus)
        if spd > speedThresh then
            lastMoving = GetGameTimer()
        elseif (GetGameTimer() - lastMoving) > (stallSeconds * 1000) then
            retries = retries + 1
            if retries <= maxRetries then
                driveTo(target)
                debugToast("Re-issuing drive task (retry "..retries..")")
                lastMoving = GetGameTimer()
            else
                gentleNudgeToward(target)
                driveTo(target)
                debugToast("Nudged bus forward and re-routed")
                lastMoving = GetGameTimer()
                retries = 0
            end
        end
    end

    TriggerServerEvent('esx_prisonerconvoy:sv_stalled_cleanup')
end

RegisterNetEvent('esx_prisonerconvoy:cl_depart_to_prison', function(busNet, driverNet, destTbl, speed, style, arriveDist, delaySeconds)
    local dms = (tonumber(delaySeconds) or 0) * 1000
    driveSegmented('esx_prisonerconvoy:sv_arrived_prison_check', busNet, driverNet, destTbl, speed, style, arriveDist, dms)
end)

RegisterNetEvent('esx_prisonerconvoy:cl_go_to_drop', function(busNet, driverNet, destTbl, speed, style, arriveDist)
    driveSegmented('esx_prisonerconvoy:sv_arrived_drop', busNet, driverNet, destTbl, speed, style, arriveDist, 0)
end)
