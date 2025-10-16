-- client.escort.lua
-- Adds lead & rear police escort vehicles with sirens and 2 officers each.
-- Uses Config.Escort and project-mandated driving style 443.
-- This file is self-contained and expects helpers from client.lua: RequestModelSync, ensureOnRoad.

local Escort = {
    active = false,
    busNet = nil,
    lead = { veh = nil, drv = nil, pas = nil, blip = nil },
    rear = { veh = nil, drv = nil, pas = nil, blip = nil }
}

local function _safe(e) return (e and e ~= 0 and DoesEntityExist(e)) end

local function _spawnEscortVehicle(model, worldPos, heading)
    local okVeh, vehHash = RequestModelSync(model or 'police')
    if not okVeh then return nil end
    local roadPos, hd = ensureOnRoad(worldPos)
    local veh = CreateVehicle(vehHash, roadPos.x, roadPos.y, roadPos.z, heading or hd, true, false)
    if not _safe(veh) then return nil end
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleOnGroundProperly(veh)
    SetVehicleEngineOn(veh, true, true, false)
    return veh
end

local function _spawnOfficer(model, atPos, heading)
    local okPed, pedHash = RequestModelSync(model or 's_m_y_cop_01')
    if not okPed then return nil end
    local ped = CreatePed(4, pedHash, atPos.x, atPos.y, atPos.z, heading or 0.0, true, true)
    if not _safe(ped) then return nil end
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 46, true)
    SetPedArmour(ped, 100)
    SetPedAccuracy(ped, 60)
    SetPedKeepTask(ped, true)
    return ped
end

local function _escortBlip(veh, name, sprite, colour)
    local b = AddBlipForEntity(veh)
    SetBlipSprite(b, sprite or 56)
    SetBlipColour(b, colour or 3)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(name or 'Escort')
    EndTextCommandSetBlipName(b)
    return b
end

local function Escort_Cleanup()
    for _, side in pairs({Escort.lead, Escort.rear}) do
        if side.blip and DoesBlipExist(side.blip) then RemoveBlip(side.blip) end
        if _safe(side.pas) then DeleteEntity(side.pas) end
        if _safe(side.drv) then DeleteEntity(side.drv) end
        if _safe(side.veh) then DeleteVehicle(side.veh) end
    end
    Escort.active = false
    Escort.busNet = nil
    Escort.lead = { veh=nil, drv=nil, pas=nil, blip=nil }
    Escort.rear = { veh=nil, drv=nil, pas=nil, blip=nil }
end

RegisterNetEvent('esx_prisonerconvoy:cl_bus_repositioned', function(busEntity)
    if not Escort.active then return end
    if not _safe(busEntity) then return end
    local cfg = Config.Escort or {}
    local bus = busEntity

    if _safe(Escort.lead.veh) then
        local ahead = GetOffsetFromEntityInWorldCoords(bus, 0.0, math.abs(cfg.FrontOffset or 22.0), 0.0)
        local road, hd = ensureOnRoad(ahead)
        SetEntityCoords(Escort.lead.veh, road.x, road.y, road.z, true, false, false, false)
        SetEntityHeading(Escort.lead.veh, hd)
        SetVehicleOnGroundProperly(Escort.lead.veh)
    end

    if _safe(Escort.rear.veh) then
        local back = GetOffsetFromEntityInWorldCoords(bus, 0.0, -(math.abs(cfg.RearOffset or 20.0)), 0.0)
        local road, hd = ensureOnRoad(back)
        SetEntityCoords(Escort.rear.veh, road.x, road.y, road.z, true, false, false, false)
        SetEntityHeading(Escort.rear.veh, hd)
        SetVehicleOnGroundProperly(Escort.rear.veh)
    end
end)

function Escort_Start(bus)
    local cfg = Config.Escort or {}
    if not cfg.Enabled then return end
    if not _safe(bus) then return end
    if Escort.active then Escort_Cleanup() end

    Escort.active = true
    local busPos = GetEntityCoords(bus)
    local busH   = GetEntityHeading(bus)

    -- Lead
    do
        local aheadSpawn = GetOffsetFromEntityInWorldCoords(bus, 0.0, math.abs(cfg.FrontOffset or 22.0) + 4.0, 0.0)
        local car = _spawnEscortVehicle(cfg.VehicleModel or 'police', aheadSpawn, busH)
        if car then
            local cop1 = _spawnOfficer(cfg.OfficerModel or 's_m_y_cop_01', aheadSpawn, busH)
            local cop2 = _spawnOfficer(cfg.OfficerModel or 's_m_y_cop_01', aheadSpawn, busH)
            if cop1 and cop2 then
                SetPedIntoVehicle(cop1, car, -1)
                SetPedIntoVehicle(cop2, car,  0)
                if cfg.SirensOn then SetVehicleSiren(car, true) SetVehicleHasMutedSirens(car, false) end
                if cfg.Blips then
                    Escort.lead.blip = _escortBlip(car, cfg.BlipLeadName or 'Convoy Lead', cfg.BlipSprite, cfg.BlipColour)
                end
                Escort.lead.veh, Escort.lead.drv, Escort.lead.pas = car, cop1, cop2

                CreateThread(function()
                    local speed = cfg.LeadSpeed or ((Config.DriveSpeed or 18.0) + 3.0)
                    local style = cfg.DriveStyle or (Config.DriveStyle or 443)
                    while Escort.active and _safe(bus) and _safe(car) and _safe(cop1) do
                        local target = GetOffsetFromEntityInWorldCoords(bus, 0.0, math.abs(cfg.FrontOffset or 22.0), 0.0)
                        TaskVehicleDriveToCoord(cop1, car, target.x, target.y, target.z, speed, false, GetEntityModel(car), style, 2.0, true)
                        SetDriveTaskDrivingStyle(cop1, style)
                        Wait(700)
                    end
                end)
            end
        end
    end

    -- Rear
    do
        local behindSpawn = GetOffsetFromEntityInWorldCoords(bus, 0.0, -(math.abs(cfg.RearOffset or 20.0) + 4.0), 0.0)
        local car = _spawnEscortVehicle(cfg.VehicleModel or 'police', behindSpawn, busH)
        if car then
            local cop1 = _spawnOfficer(cfg.OfficerModel or 's_m_y_cop_01', behindSpawn, busH)
            local cop2 = _spawnOfficer(cfg.OfficerModel or 's_m_y_cop_01', behindSpawn, busH)
            if cop1 and cop2 then
                SetPedIntoVehicle(cop1, car, -1)
                SetPedIntoVehicle(cop2, car,  0)
                if cfg.SirensOn then SetVehicleSiren(car, true) SetVehicleHasMutedSirens(car, false) end
                if cfg.Blips then
                    Escort.rear.blip = _escortBlip(car, cfg.BlipRearName or 'Convoy Rear', cfg.BlipSprite, cfg.BlipColour)
                end
                Escort.rear.veh, Escort.rear.drv, Escort.rear.pas = car, cop1, cop2

                CreateThread(function()
                    local style = cfg.DriveStyle or (Config.DriveStyle or 443)
                    local speed = cfg.RearSpeed or (Config.DriveSpeed or 18.0)
                    local minDist = math.abs(cfg.RearOffset or 20.0)
                    while Escort.active and _safe(bus) and _safe(car) and _safe(cop1) do
                        TaskVehicleFollow(cop1, car, bus, speed, style, minDist)
                        SetDriveTaskDrivingStyle(cop1, style)
                        Wait(1000)
                    end
                end)
            end
        end
    end

    Escort.busNet = NetworkGetNetworkIdFromEntity(bus)
end

function Escort_Stop()
    Escort_Cleanup()
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    Escort_Cleanup()
end)
