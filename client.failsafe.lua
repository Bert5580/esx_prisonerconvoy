-- client.failsafe.lua (ultimate failsafe warp on chronic stall)
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
    local ok, nodePos, heading = GetClosestVehicleNodeWithHeading(pos.x, pos.y, pos.z, 1, 3.0, 0)
    if ok then
        return vector3(nodePos.x, nodePos.y, nodePos.z + 1.0), heading
    end
    return pos, GetEntityHeading(PlayerPedId())
end

local function warpBusTo(bus, dest)
    local roadPos, _ = ensureOnRoad(dest)
    ClearAreaOfVehicles(roadPos.x, roadPos.y, roadPos.z, 10.0, false, false, false, false, false)
    ClearArea(roadPos.x, roadPos.y, roadPos.z, 10.0, true, false, false, false)
    SetEntityCoords(bus, roadPos.x, roadPos.y, roadPos.z, true, false, false, false)
    SetVehicleOnGroundProperly(bus)
end

-- Wrapper to apply failsafe on the drive loops you already have
local function driveWithFailsafe(phaseArrivedEvent, baseFnName, busNet, driverNet, destTbl, speed, style, arriveDist, delaySeconds)
    local dest = toVec3(destTbl); if not dest then return end
    local start = GetGameTimer()
    local stallCycles = 0
    local fs = Config.UltimateFailsafe or {}
    local enabled = (fs.Enabled ~= false)
    local maxSecs = (fs.MaxTotalSeconds or 300)
    local maxCycles = (fs.MaxStallCycles or 12)

    -- We hook into progress by polling distance and bus speed to infer stalls
    local bus = GetEntityFromNet(busNet)
    if bus == 0 then TriggerServerEvent('esx_prisonerconvoy:sv_stalled_cleanup'); return end

    -- Kick off your existing segmented/owned/anti-stall handler
    TriggerEvent(baseFnName, busNet, driverNet, destTbl, speed, style, arriveDist, delaySeconds)

    local lastProgress = GetGameTimer()
    local lastPos = GetEntityCoords(bus)

    while enabled do
        Wait(1000)
        if not DoesEntityExist(bus) then break end
        local pos = GetEntityCoords(bus)
        local moved = #(pos - lastPos)
        if moved > 3.0 then
            stallCycles = 0
            lastProgress = GetGameTimer()
            lastPos = pos
        else
            stallCycles = stallCycles + 1
        end

        -- Hard limit on leg duration or chronic stall
        if (GetGameTimer() - start) > (maxSecs * 1000) or stallCycles >= maxCycles then
            warpBusTo(bus, dest)
            -- give physics a tick
            Wait(250)
            -- trigger arrival immediately
            if phaseArrivedEvent == 'esx_prisonerconvoy:sv_arrived_prison_check' then
                TriggerServerEvent('esx_prisonerconvoy:sv_arrived_prison_check')
            else
                TriggerServerEvent('esx_prisonerconvoy:sv_arrived_drop')
            end
            return
        end
    end
end

-- Replace public handlers with failsafe wrapper that calls your internal base implementations:
RegisterNetEvent('esx_prisonerconvoy:cl_depart_to_prison', function(busNet, driverNet, destTbl, speed, style, arriveDist, delaySeconds)
    -- choose the base event name matching your current implementation
    local base = '__esx_prisonerconvoy_internal:segmented_or_simple_depart'
    driveWithFailsafe('esx_prisonerconvoy:sv_arrived_prison_check', base, busNet, driverNet, destTbl, speed, style, arriveDist, delaySeconds)
end)

RegisterNetEvent('esx_prisonerconvoy:cl_go_to_drop', function(busNet, driverNet, destTbl, speed, style, arriveDist)
    local base = '__esx_prisonerconvoy_internal:segmented_or_simple_drop'
    driveWithFailsafe('esx_prisonerconvoy:sv_arrived_drop', base, busNet, driverNet, destTbl, speed, style, arriveDist, 0)
end)
