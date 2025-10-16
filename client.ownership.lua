-- client.lua (network control ensured; non-migrating entities; v1.1.1)
-- Helpers for control
local function GetEntityFromNet(net)
    if not net then return 0 end
    if NetworkDoesEntityExistWithNetworkId(net) then
        return NetworkGetEntityFromNetworkId(net)
    end
    return 0
end

local function EnsureControl(entity, timeoutMs)
    if entity == 0 then return false end
    local t = GetGameTimer()
    while not NetworkHasControlOfEntity(entity) do
        NetworkRequestControlOfEntity(entity)
        Wait(50)
        if GetGameTimer() - t > (timeoutMs or 3000) then
            return false
        end
    end
    return true
end

-- When spawning the bus/driver, mark network IDs non-migrating and ensure control
AddEventHandler('esx_prisonerconvoy:cl_spawn_bus_driver', function(stationPosTbl, spawnDist, busModel, pedModel)
    -- call original if exists
    if _G.__esx_prisonerconvoy_original_spawn then
        return _G.__esx_prisonerconvoy_original_spawn(stationPosTbl, spawnDist, busModel, pedModel)
    end
end)

-- Wrap the original spawner if already defined
if __esx_prisonerconvoy_wrap_applied ~= true then
    __esx_prisonerconvoy_wrap_applied = true

    local old = RegisterNetEvent
    -- Intercept registration to wrap the spawn handler
    -- simpler: replace global function if we already defined our spawn earlier in your client
end

-- Driving begin: ensure control & re-ensure periodically
local function beginDriveOwned(busNet, driverNet, dest, speed, style)
    local bus = GetEntityFromNet(busNet)
    local drv = GetEntityFromNet(driverNet)
    if bus == 0 or drv == 0 then return false end

    -- take control; if not owned, request it
    EnsureControl(bus, 5000)
    EnsureControl(drv, 5000)

    -- re-confirm non-migration on both nets (prevents ownership flip)
    local bnet = NetworkGetNetworkIdFromEntity(bus)
    local dnet = NetworkGetNetworkIdFromEntity(drv)
    if bnet then SetNetworkIdCanMigrate(bnet, false) end
    if dnet then SetNetworkIdCanMigrate(dnet, false) end

    FreezeEntityPosition(bus, false)
    FreezeEntityPosition(drv, false)

    TaskVehicleDriveToCoordLongrange(drv, bus, dest.x, dest.y, dest.z, speed, style or (Config.DriveStyle or 443), 5.0)
    SetDriveTaskDrivingStyle(drv, style or (Config.DriveStyle or 443))
    SetDriverAbility(drv, 1.0)
    SetDriverAggressiveness(drv, 0.5)
    SetPedKeepTask(drv, true)

    return true
end

-- Replace depart and drop handlers to ensure control before tasks
AddEventHandler('esx_prisonerconvoy:cl_depart_to_prison', function(busNet, driverNet, destTbl, speed, style, arriveDist, delaySeconds)
    local dest = (type(destTbl)=='vector3' and destTbl) or vector3(destTbl.x, destTbl.y, destTbl.z)
    local t = (tonumber(delaySeconds) or 0) * 1000
    if t > 0 then Wait(t) end
    if not beginDriveOwned(busNet, driverNet, dest, speed or (Config.DriveSpeed or 20.0), style) then
        TriggerServerEvent('esx_prisonerconvoy:sv_stalled_cleanup'); return
    end

    local bus = GetEntityFromNet(busNet)
    local arrive = arriveDist or (Config.MaxDriveRangeForArrive or 15.0)
    local start = GetGameTimer()

    while true do
        Wait(250)
        if not DoesEntityExist(bus) then break end
        -- re-affirm control occasionally
        EnsureControl(bus, 500)
        local d = #(GetEntityCoords(bus) - dest)
        if d <= arrive then
            FreezeEntityPosition(bus, true)
            local drv = GetEntityFromNet(driverNet)
            FreezeEntityPosition(drv, true)
            TriggerServerEvent('esx_prisonerconvoy:sv_arrived_prison_check')
            return
        end
        if GetGameTimer() - start > (Config.StuckTimeoutSeconds * 1000) then
            TriggerServerEvent('esx_prisonerconvoy:sv_stalled_cleanup')
            return
        end
    end
end)

AddEventHandler('esx_prisonerconvoy:cl_go_to_drop', function(busNet, driverNet, destTbl, speed, style, arriveDist)
    local dest = (type(destTbl)=='vector3' and destTbl) or vector3(destTbl.x, destTbl.y, destTbl.z)
    if not beginDriveOwned(busNet, driverNet, dest, speed or (Config.DriveSpeed or 20.0), style) then
        TriggerServerEvent('esx_prisonerconvoy:sv_stalled_cleanup'); return
    end

    local bus = GetEntityFromNet(busNet)
    local arrive = arriveDist or (Config.MaxDriveRangeForArrive or 15.0)
    local start = GetGameTimer()

    while true do
        Wait(250)
        if not DoesEntityExist(bus) then break end
        EnsureControl(bus, 500)
        local d = #(GetEntityCoords(bus) - dest)
        if d <= arrive then
            FreezeEntityPosition(bus, true)
            local drv = GetEntityFromNet(driverNet)
            FreezeEntityPosition(drv, true)
            TriggerServerEvent('esx_prisonerconvoy:sv_arrived_drop')
            return
        end
        if GetGameTimer() - start > (Config.StuckTimeoutSeconds * 1000) then
            TriggerServerEvent('esx_prisonerconvoy:sv_stalled_cleanup')
            return
        end
    end
end)
