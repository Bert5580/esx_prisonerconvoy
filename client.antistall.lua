-- client.lua (anti-stall reinforced drive logic)
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

local function ensureOnRoad(pos)
    local outPos, outHeading = vector3(pos.x, pos.y, pos.z), 0.0
    local ok, nodePos, nodeHeading = GetClosestVehicleNodeWithHeading(pos.x, pos.y, pos.z, 1, 3.0, 0)
    if ok then
        outPos = vector3(nodePos.x, nodePos.y, nodePos.z + 1.0)
        outHeading = nodeHeading
    end
    return outPos, outHeading
end

local function gentleNudgeToward(bus, dest, nudgeDist, clearRadius)
    if not DoesEntityExist(bus) then return end
    local pos = GetEntityCoords(bus)
    local dir = dest - pos
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

local function TaskDriveSmart(driver, bus, dest, speed, style)
    TaskVehicleDriveToCoordLongrange(driver, bus, dest.x, dest.y, dest.z, speed, style or (Config.DriveStyle or 443), 5.0)
    SetDriveTaskDrivingStyle(driver, style or (Config.DriveStyle or 443))
    SetDriverAbility(driver, 1.0)
    SetDriverAggressiveness(driver, 0.5)
    SetPedKeepTask(driver, true)
end

local function driveWithResilience(phaseArrivedEvent, busNet, driverNet, destTbl, speed, style, arriveDist, delayMs)
    local dest = toVec3(destTbl)
    if not dest then return end
    local dms = tonumber(delayMs or 0) or 0
    if dms > 0 then Wait(dms) end

    local bus = GetEntityFromNet(busNet)
    local drv = GetEntityFromNet(driverNet)
    if bus == 0 or drv == 0 then
        TriggerServerEvent('esx_prisonerconvoy:sv_stalled_cleanup'); return
    end

    FreezeEntityPosition(bus, false)
    FreezeEntityPosition(drv, false)
    TaskDriveSmart(drv, bus, dest, speed or (Config.DriveSpeed or 20.0), style)

    local arrive = arriveDist or (Config.MaxDriveRangeForArrive or 15.0)
    local timeout = (Config.StuckTimeoutSeconds or 420) * 1000
    local startTime = GetGameTimer()

    local anti = Config.AntiStall or {}
    local antEnabled   = (anti.Enabled ~= false)
    local speedThresh  = anti.SpeedThreshold or 1.2
    local stallSeconds = anti.SecondsStalled or 6
    local maxRetries   = anti.MaxRetries or 4
    local nudgeDist    = anti.NudgeDistance or 6.0
    local clearRadius  = anti.ClearRadius or 6.0

    local lastMoving = GetGameTimer()
    local retries = 0

    while true do
        Wait(250)
        if not DoesEntityExist(bus) or not DoesEntityExist(drv) then break end
        local bpos = GetEntityCoords(bus)

        if #(bpos - dest) <= arrive then
            FreezeEntityPosition(bus, true)
            FreezeEntityPosition(drv, true)
            TriggerServerEvent(phaseArrivedEvent)
            return
        end

        if GetGameTimer() - startTime > timeout then
            TriggerServerEvent('esx_prisonerconvoy:sv_stalled_cleanup')
            return
        end

        if antEnabled then
            local spd = GetEntitySpeed(bus)
            if spd > speedThresh then
                lastMoving = GetGameTimer()
            elseif (GetGameTimer() - lastMoving) > (stallSeconds * 1000) then
                retries = retries + 1
                if retries <= maxRetries then
                    TaskDriveSmart(drv, bus, dest, speed or (Config.DriveSpeed or 20.0), style)
                    lastMoving = GetGameTimer()
                else
                    gentleNudgeToward(bus, dest, nudgeDist, clearRadius)
                    TaskDriveSmart(drv, bus, dest, speed or (Config.DriveSpeed or 20.0), style)
                    lastMoving = GetGameTimer()
                    retries = 0
                end
            end
        end
    end

    TriggerServerEvent('esx_prisonerconvoy:sv_stalled_cleanup')
end

AddEventHandler('esx_prisonerconvoy:cl_depart_to_prison', function(busNet, driverNet, destTbl, speed, style, arriveDist, delaySeconds)
    local dms = (tonumber(delaySeconds) or 0) * 1000
    driveWithResilience('esx_prisonerconvoy:sv_arrived_prison_check', busNet, driverNet, destTbl, speed, style, arriveDist, dms)
end)

AddEventHandler('esx_prisonerconvoy:cl_go_to_drop', function(busNet, driverNet, destTbl, speed, style, arriveDist)
    driveWithResilience('esx_prisonerconvoy:sv_arrived_drop', busNet, driverNet, destTbl, speed, style, arriveDist, 0)
end)
