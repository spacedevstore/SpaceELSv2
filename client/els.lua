local SetVehicleExtra = SetVehicleExtra
local DisableControlAction = DisableControlAction
local DoesEntityExist = DoesEntityExist
local GetGameTimer = GetGameTimer
local PlayerPedId = PlayerPedId
local IsPedInAnyVehicle = IsPedInAnyVehicle
local GetVehiclePedIsIn = GetVehiclePedIsIn
local NetworkHasControlOfEntity = NetworkHasControlOfEntity
local NetworkRequestControlOfEntity = NetworkRequestControlOfEntity
local NetworkGetNetworkIdFromEntity = NetworkGetNetworkIdFromEntity
local GetEntityModel = GetEntityModel
local GetDisplayNameFromVehicleModel = GetDisplayNameFromVehicleModel
local GetEntityCoords = GetEntityCoords
local GetOffsetFromEntityInWorldCoords = GetOffsetFromEntityInWorldCoords
local DrawLightWithRange = DrawLightWithRange
local PlaySoundFrontend = PlaySoundFrontend
local SendNUIMessage = SendNUIMessage

local isUIOpen = false
local isBuilderOpen = false
local currentControlledVehicle = 0
local customVehicleProfiles = {}
local trackedVehicles = {}
local activeEnvVehicles = {}
local activeSequencerVehicles = {}

local studioCamera = nil
local camYaw = 180.0
local camPitch = 12.0
local camDist = 6.2

local lastHornPressTime = 0
local isClearingIntersection = false
local preSurgeTone = "wail"

local plyPed = 0
local currentVeh = 0
local isInVehicle = false
local canControlCurrentVeh = false
local vehicleModelProfileCache = {}
local vehicleEmergencyCache = {}

local ENV_COLOR_PALETTES = {
    red   = { r = 210, g = 15,  b = 25 },
    blue  = { r = 10,  g = 90,  b = 220 },
    amber = { r = 220, g = 110, b = 10 },
    white = { r = 220, g = 225, b = 230 },
    green = { r = 20,  g = 190, b = 60 }
}

local SIREN_AUDIO_BANKS = {
    wail     = "VEHICLES_HORNS_SIREN_1",
    yelp     = "VEHICLES_HORNS_SIREN_2",
    priority = "VEHICLES_HORNS_POLICE_WARNING",
    hilo     = "VEHICLES_HORNS_AMBULANCE_WARNING"
}

local function GetEnvRGB(colorName, fallback)
    if not colorName or colorName == 'none' then return nil end
    return ENV_COLOR_PALETTES[colorName] or ENV_COLOR_PALETTES[fallback] or ENV_COLOR_PALETTES['blue']
end

local function EnsureEntityControl(entity)
    if not DoesEntityExist(entity) then return false end
    if NetworkHasControlOfEntity(entity) then return true end

    local timeout = 0
    NetworkRequestControlOfEntity(entity)
    while not NetworkHasControlOfEntity(entity) and timeout < 15 do
        Wait(20)
        NetworkRequestControlOfEntity(entity)
        timeout = timeout + 1
    end
    return NetworkHasControlOfEntity(entity)
end

local function GetProfileForVehicle(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return nil end
    local modelHash = GetEntityModel(veh)
    if vehicleModelProfileCache[modelHash] ~= nil then
        return vehicleModelProfileCache[modelHash] == false and nil or vehicleModelProfileCache[modelHash]
    end

    local rawName = string.lower(GetDisplayNameFromVehicleModel(modelHash)):gsub("^%s*(.-)%s*$", "%1")

    if customVehicleProfiles[rawName] then
        vehicleModelProfileCache[modelHash] = customVehicleProfiles[rawName]
        return customVehicleProfiles[rawName]
    end

    for name, prof in pairs(customVehicleProfiles) do
        local cleanKey = string.lower(tostring(name)):gsub("^%s*(.-)%s*$", "%1")
        if cleanKey == rawName or GetHashKey(cleanKey) == modelHash or GetHashKey(name) == modelHash then
            vehicleModelProfileCache[modelHash] = prof
            return prof
        end
    end
    vehicleModelProfileCache[modelHash] = false
    return nil
end

local function IsNonELSVehicle(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return false end
    local modelHash = GetEntityModel(veh)
    local rawName = string.lower(GetDisplayNameFromVehicleModel(modelHash)):gsub("^%s*(.-)%s*$", "%1")

    if Config and Config.ELS and Config.ELS.NonELSVehicles then
        if Config.ELS.NonELSVehicles[rawName] or Config.ELS.NonELSVehicles[modelHash] then
            return true
        end
    end
    return false
end

local function IsVehicleELS(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return false end
    if IsNonELSVehicle(veh) then return false end
    return GetProfileForVehicle(veh) ~= nil
end

local function GetVehicleELSData(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return nil end
    if not trackedVehicles[veh] then
        local existing = {}
        for i = 1, 12 do
            existing[i] = (DoesExtraExist(veh, i) == 1 or DoesExtraExist(veh, i) == true)
        end

        trackedVehicles[veh] = {
            stage = 0,
            pattern = 1,
            sirenOn = false,
            sirenMuted = true,
            sirenTone = "wail",
            sirenSoundId = -1,
            hornSoundId = -1,
            step = 0,
            lastStepTime = 0,
            stageSpeed = 80,
            steady = {},
            phaseA = {},
            phaseB = {},
            envColorA = nil,
            envColorB = nil,
            envPos = 'both',
            extrasState = {},
            existingExtras = existing,
            profile = GetProfileForVehicle(veh)
        }
    end
    return trackedVehicles[veh]
end

local function SetupVehicleStageData(veh, data, stageNum, customProfile)
    data.step = 0
    data.lastStepTime = 0
    data.extrasState = {}

    if stageNum == 0 or not IsVehicleELS(veh) then
        data.steady = {}
        data.phaseA = {}
        data.phaseB = {}
        data.envColorA = nil
        data.envColorB = nil
        activeEnvVehicles[veh] = nil
        activeSequencerVehicles[veh] = nil
        return
    end

    local prof = customProfile or data.testProfile or data.profile or GetProfileForVehicle(veh)
    data.profile = prof
    local stgData = prof and prof["stage" .. stageNum]

    if stgData and type(stgData) == 'table' then
        data.stageSpeed = tonumber(stgData.speed) or (stageNum == 1 and 180 or (stageNum == 2 and 120 or (prof and prof.speed or 80)))
        data.steady = stgData.steady or {}
        data.phaseA = stgData.phaseA or {}
        data.phaseB = stgData.phaseB or {}

        local colorCfg = stgData.envColors or {}
        local fallbackPos = stageNum == 1 and 'rear' or (stageNum == 2 and 'roof' or 'both')
        data.envPos = colorCfg.pos or fallbackPos

        local fallbackA = stageNum == 1 and 'amber' or 'red'
        local fallbackB = stageNum == 1 and 'amber' or 'blue'
        data.envColorA = GetEnvRGB(colorCfg.colorA, fallbackA)
        data.envColorB = GetEnvRGB(colorCfg.colorB, fallbackB)
    else
        data.stageSpeed = (stageNum == 1 and 180 or (stageNum == 2 and 120 or 80))
        data.steady = {}
        data.phaseA = {}
        data.phaseB = {}
        data.envColorA = stageNum == 1 and ENV_COLOR_PALETTES['amber'] or ENV_COLOR_PALETTES['red']
        data.envColorB = stageNum == 1 and ENV_COLOR_PALETTES['amber'] or ENV_COLOR_PALETTES['blue']
        data.envPos = stageNum == 1 and 'rear' or 'both'
    end

    activeSequencerVehicles[veh] = data
    if data.envColorA or data.envColorB then
        activeEnvVehicles[veh] = data
    else
        activeEnvVehicles[veh] = nil
    end
end

local function IsEmergencyVehicle(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return false end
    local modelHash = GetEntityModel(veh)
    if vehicleEmergencyCache[modelHash] ~= nil then
        return vehicleEmergencyCache[modelHash]
    end

    local isEmergency = (GetVehicleClass(veh) == 18) or (GetProfileForVehicle(veh) ~= nil)
    vehicleEmergencyCache[modelHash] = isEmergency
    return isEmergency
end

local function CanPlayerControlELS(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return false end
    if not IsEmergencyVehicle(veh) then return false end

    local allowPassengers = true
    if Config and Config.ELS and Config.ELS.AllowPassengers ~= nil then
        allowPassengers = Config.ELS.AllowPassengers
    end
    if allowPassengers then return true end

    local ped = plyPed ~= 0 and plyPed or PlayerPedId()
    return GetPedInVehicleSeat(veh, -1) == ped
end

local function GetTargetVehicle()
    if isInVehicle and currentVeh ~= 0 and DoesEntityExist(currentVeh) then
        if not canControlCurrentVeh then return 0 end
        return currentVeh
    end
    local ped = plyPed ~= 0 and plyPed or PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        local veh = GetVehiclePedIsIn(ped, false)
        currentVeh = veh
        isInVehicle = true
        canControlCurrentVeh = CanPlayerControlELS(veh)
        if not canControlCurrentVeh then return 0 end
        GetVehicleELSData(veh)
        return veh
    end
    return 0
end

local function SetExtraState(veh, data, extraId, state)
    if data.extrasState[extraId] == state then return end
    data.extrasState[extraId] = state
    if data.existingExtras and data.existingExtras[extraId] then
        SetVehicleExtra(veh, extraId, state and 0 or 1)
    end
end

local function StopVehicleSirenSound(veh)
    local data = trackedVehicles[veh]
    if data and data.sirenSoundId and data.sirenSoundId ~= -1 then
        local sId = data.sirenSoundId
        data.sirenSoundId = -1
        StopSound(sId)
        ReleaseSoundId(sId)
    end
end

local function StopVehicleHornSound(veh)
    local data = trackedVehicles[veh]
    if data and data.hornSoundId and data.hornSoundId ~= -1 then
        local hId = data.hornSoundId
        data.hornSoundId = -1
        StopSound(hId)
        ReleaseSoundId(hId)
    end
end

local function CleanUpVehicleData(veh)
    if not veh then return end
    StopVehicleSirenSound(veh)
    StopVehicleHornSound(veh)
    activeEnvVehicles[veh] = nil
    activeSequencerVehicles[veh] = nil
    trackedVehicles[veh] = nil
    isClearingIntersection = false
end

local function StartVehicleSirenSound(veh, requestedTone, directSoundBank)
    local data = GetVehicleELSData(veh)
    if not data or not DoesEntityExist(veh) then return end

    StopVehicleSirenSound(veh)
    local newSoundId = GetSoundId()
    if not newSoundId or newSoundId == -1 then return end
    data.sirenSoundId = newSoundId

    local soundName = directSoundBank
    if not soundName or soundName == "NONE" then
        local toneKey = requestedTone or data.sirenTone or "wail"
        data.sirenTone = toneKey
        soundName = SIREN_AUDIO_BANKS[toneKey] or "VEHICLES_HORNS_SIREN_1"
    end

    PlaySoundFromEntity(data.sirenSoundId, soundName, veh, 0, 0, 0)
end

local function StartVehicleHornSound(veh)
    local data = GetVehicleELSData(veh)
    if not data or not DoesEntityExist(veh) then return end

    StopVehicleHornSound(veh)
    local newSoundId = GetSoundId()
    if not newSoundId or newSoundId == -1 then return end
    data.hornSoundId = newSoundId

    PlaySoundFromEntity(data.hornSoundId, "SIRENS_AIRHORN", veh, 0, 0, 0)
end

local function ApplyVehicleSound(veh, sirenOn, muted, tone, directSoundBank)
    local data = GetVehicleELSData(veh)
    if not data or not DoesEntityExist(veh) then return end

    EnsureEntityControl(veh)
    SetVehicleKeepEngineOnWhenAbandoned(veh, true)
    SetVehicleAutoRepairDisabled(veh, true)

    if tone then data.sirenTone = tone end

    if sirenOn and not muted then
        SetVehicleSiren(veh, true)
        SetVehicleHasMutedSirens(veh, true)
        StartVehicleSirenSound(veh, data.sirenTone, directSoundBank)
    elseif sirenOn and muted then
        SetVehicleSiren(veh, true)
        SetVehicleHasMutedSirens(veh, true)
        StopVehicleSirenSound(veh)
    else
        if data.stage == 0 or not IsVehicleELS(veh) then
            SetVehicleSiren(veh, false)
        end
        SetVehicleHasMutedSirens(veh, true)
        StopVehicleSirenSound(veh)
    end
end

local function ScanVehicleExtras(veh)
    local extras = {}
    if not DoesEntityExist(veh) or veh == 0 then
        for i = 1, 12 do extras[i] = { id = i, exists = false, enabled = false } end
        return extras
    end

    for i = 1, 12 do
        local exists = DoesExtraExist(veh, i) == 1 or DoesExtraExist(veh, i) == true
        local enabled = exists and (IsVehicleExtraTurnedOn(veh, i) == 1 or IsVehicleExtraTurnedOn(veh, i) == true) or false
        extras[i] = { id = i, exists = exists, enabled = enabled }
    end
    return extras
end

local function GetRiderSeatName(veh, ped)
    if not DoesEntityExist(veh) or not DoesEntityExist(ped) or not IsPedInAnyVehicle(ped, false) then
        return "Outside"
    end
    if GetPedInVehicleSeat(veh, -1) == ped then
        return "Driver"
    elseif GetPedInVehicleSeat(veh, 0) == ped then
        return "Front Passenger"
    elseif GetPedInVehicleSeat(veh, 1) == ped then
        return "Rear Left"
    elseif GetPedInVehicleSeat(veh, 2) == ped then
        return "Rear Right"
    else
        return "Passenger"
    end
end

local function CollectVehicleState()
    local ped = plyPed ~= 0 and plyPed or PlayerPedId()
    local veh = GetTargetVehicle()

    if veh == 0 or not DoesEntityExist(veh) then
        return {
            inVehicle = false,
            modelName = "NO VEHICLE",
            seatName = "Foot",
            speed = 0,
            stage = 0,
            pattern = 1,
            sirenOn = false,
            sirenMuted = true,
            sirenTone = "wail",
            availableStages = { 1, 2, 3 },
            extras = ScanVehicleExtras(0)
        }
    end

    local data = GetVehicleELSData(veh)
    local modelHash = GetEntityModel(veh)
    local modelDisplayName = GetLabelText(GetDisplayNameFromVehicleModel(modelHash))
    if modelDisplayName == "NULL" or not modelDisplayName then
        modelDisplayName = GetDisplayNameFromVehicleModel(modelHash)
    end

    local prof = data.profile or GetProfileForVehicle(veh)
    local availableStages = {}
    if prof then
        for s = 1, 3 do
            if prof["stage" .. s] ~= nil then table.insert(availableStages, s) end
        end
    else
        availableStages = { 1, 2, 3 }
    end

    return {
        inVehicle = true,
        modelName = modelDisplayName,
        seatName = GetRiderSeatName(veh, ped),
        speed = math.floor(GetEntitySpeed(veh) * 2.236936),
        stage = data.stage,
        pattern = data.pattern,
        availableStages = availableStages,
        sirenOn = data.sirenOn,
        sirenMuted = data.sirenMuted,
        sirenTone = data.sirenTone or "wail",
        extras = ScanVehicleExtras(veh)
    }
end

CreateThread(function()
    while true do
        if Config and Config.ELS and Config.ELS.EnableEnvironmentalLighting == true and next(activeEnvVehicles) ~= nil then
            local pCoords = nil
            local maxDistSq = (Config.ELS.EnvironmentalLightMaxDistance and (Config.ELS.EnvironmentalLightMaxDistance * Config.ELS.EnvironmentalLightMaxDistance)) or 784.0

            for veh, data in pairs(activeEnvVehicles) do
                local isPhaseA = (data.step % 2 == 0)
                local activeRGB = isPhaseA and data.envColorA or data.envColorB

                if activeRGB then
                    local isSelf = (veh == currentVeh)
                    local shouldRender = isSelf

                    if not isSelf then
                        if not pCoords then
                            pCoords = GetEntityCoords(plyPed ~= 0 and plyPed or PlayerPedId())
                        end
                        local vCoords = GetEntityCoords(veh)
                        local dx = pCoords.x - vCoords.x
                        local dy = pCoords.y - vCoords.y
                        local dz = pCoords.z - vCoords.z
                        shouldRender = (dx * dx + dy * dy + dz * dz) <= maxDistSq
                    end

                    if shouldRender then
                        local glowPos = data.envPos
                        if glowPos == 'rear' then
                            local p = GetOffsetFromEntityInWorldCoords(veh, 0.0, -1.8, 0.90)
                            DrawLightWithRange(p.x, p.y, p.z, activeRGB.r, activeRGB.g, activeRGB.b, 5.5, 0.50)
                        elseif glowPos == 'front' then
                            local p = GetOffsetFromEntityInWorldCoords(veh, 0.0, 1.9, 0.75)
                            DrawLightWithRange(p.x, p.y, p.z, activeRGB.r, activeRGB.g, activeRGB.b, 5.5, 0.50)
                        else
                            local sideX = isPhaseA and -0.65 or 0.65
                            local p = GetOffsetFromEntityInWorldCoords(veh, sideX, 0.05, 0.95)
                            DrawLightWithRange(p.x, p.y, p.z, activeRGB.r, activeRGB.g, activeRGB.b, 6.5, 0.55)
                        end
                    end
                end
            end
            Wait(0)
        else
            Wait(350)
        end
    end
end)

CreateThread(function()
    while true do
        if next(activeSequencerVehicles) ~= nil then
            local minSleep = 250
            local now = GetGameTimer()

            for veh, data in pairs(activeSequencerVehicles) do
                local timePassed = now - data.lastStepTime
                local speed = data.stageSpeed or 100
                local remaining = speed - timePassed

                if remaining <= 10 then
                    data.lastStepTime = now
                    data.step = data.step + 1
                    local flashState = (data.step % 2 == 0)

                    for _, exId in ipairs(data.steady) do
                        SetExtraState(veh, data, exId, true)
                    end
                    for _, exId in ipairs(data.phaseA) do
                        SetExtraState(veh, data, exId, flashState)
                    end
                    for _, exId in ipairs(data.phaseB) do
                        SetExtraState(veh, data, exId, not flashState)
                    end

                    if speed < minSleep then
                        minSleep = speed
                    end
                else
                    if remaining < minSleep then
                        minSleep = remaining
                    end
                end
            end

            Wait(math.max(25, minSleep))
        else
            Wait(350)
        end
    end
end)

CreateThread(function()
    while true do
        plyPed = PlayerPedId()
        if IsPedInAnyVehicle(plyPed, false) then
            local veh = GetVehiclePedIsIn(plyPed, false)
            if veh ~= currentVeh then
                currentVeh = veh
                isInVehicle = true
            end
            canControlCurrentVeh = CanPlayerControlELS(currentVeh)
        else
            if isInVehicle then
                currentVeh = 0
                isInVehicle = false
                canControlCurrentVeh = false
                isClearingIntersection = false
            end
        end

        if isUIOpen and isInVehicle and currentVeh ~= 0 then
            SendNUIMessage({
                action = 'syncLiveInfo',
                seatName = GetRiderSeatName(currentVeh, plyPed)
            })
        end
        Wait(400)
    end
end)

CreateThread(function()
    while true do
        Wait(5000)
        for veh, _ in pairs(trackedVehicles) do
            if not DoesEntityExist(veh) then
                CleanUpVehicleData(veh)
            end
        end
        for veh, _ in pairs(activeEnvVehicles) do
            if not DoesEntityExist(veh) then
                activeEnvVehicles[veh] = nil
            end
        end
        for veh, _ in pairs(activeSequencerVehicles) do
            if not DoesEntityExist(veh) then
                activeSequencerVehicles[veh] = nil
            end
        end
    end
end)

CreateThread(function()
    while true do
        if isInVehicle and canControlCurrentVeh and not isUIOpen and not isBuilderOpen then
            DisableControlAction(0, 86, true) -- Horn
            DisableControlAction(0, 81, true) -- Next Radio Track
            Wait(0)
        else
            Wait(350)
        end
    end
end)

local function ResetStageExtras(veh, data)
    if not IsVehicleELS(veh) then return end
    data.extrasState = {}
    if data.existingExtras then
        for i = 1, 12 do
            if data.existingExtras[i] then
                SetVehicleExtra(veh, i, 1)
            end
        end
    end
end

local function SetLightStage(stageNum)
    local veh = GetTargetVehicle()
    if veh == 0 or not DoesEntityExist(veh) then return end
    if not IsVehicleELS(veh) then return end

    local data = GetVehicleELSData(veh)
    stageNum = tonumber(stageNum) or 0
    data.stage = stageNum
    EnsureEntityControl(veh)
    SetVehicleAutoRepairDisabled(veh, true)
    SetVehicleKeepEngineOnWhenAbandoned(veh, true)

    ResetStageExtras(veh, data)
    SetupVehicleStageData(veh, data, stageNum, nil)

    local netId = NetworkGetNetworkIdFromEntity(veh)

    if stageNum == 0 then
        data.sirenOn = false
        data.sirenMuted = true
        ApplyVehicleSound(veh, false, true)
        TriggerServerEvent('SpaceELS:server:syncELSStage', netId, 0, {}, true, false)
    else
        if data.sirenOn and not data.sirenMuted then
            ApplyVehicleSound(veh, true, false, data.sirenTone)
            TriggerServerEvent('SpaceELS:server:syncELSStage', netId, stageNum, {}, false, true)
        else
            ApplyVehicleSound(veh, true, true)
            TriggerServerEvent('SpaceELS:server:syncELSStage', netId, stageNum, {}, true, true)
        end
    end

    SendNUIMessage({
        action = 'updateState',
        data = CollectVehicleState()
    })
end

local function SetSirenTone(toneKey)
    local veh = GetTargetVehicle()
    if veh == 0 or not DoesEntityExist(veh) then return end
    local data = GetVehicleELSData(veh)
    EnsureEntityControl(veh)

    data.sirenTone = toneKey
    local netId = NetworkGetNetworkIdFromEntity(veh)

    if data.sirenOn and not data.sirenMuted then
        ApplyVehicleSound(veh, true, false, toneKey)
        TriggerServerEvent('SpaceELS:server:syncSirenState', netId, true, false, toneKey)
    end

    SendNUIMessage({
        action = 'updateState',
        data = CollectVehicleState()
    })
end

local function TriggerAirhorn(startBlast)
    local veh = GetTargetVehicle()
    if veh == 0 or not DoesEntityExist(veh) then return end
    local data = GetVehicleELSData(veh)
    EnsureEntityControl(veh)

    local netId = NetworkGetNetworkIdFromEntity(veh)

    if startBlast then
        local now = GetGameTimer()
        if (now - lastHornPressTime) < 380 and not isClearingIntersection then
            isClearingIntersection = true
            preSurgeTone = data.sirenTone or "wail"
            SetSirenTone("priority")

            CreateThread(function()
                Wait(4200)
                if DoesEntityExist(veh) and isClearingIntersection then
                    SetSirenTone(preSurgeTone)
                end
                isClearingIntersection = false
            end)
        end
        lastHornPressTime = now

        StartVehicleHornSound(veh)
        TriggerServerEvent('SpaceELS:server:syncAirhorn', netId, true)
    else
        StopVehicleHornSound(veh)
        TriggerServerEvent('SpaceELS:server:syncAirhorn', netId, false)
    end
end

local function ToggleSirenAudio(enable)
    local veh = GetTargetVehicle()
    if veh == 0 or not DoesEntityExist(veh) then return end
    local data = GetVehicleELSData(veh)
    EnsureEntityControl(veh)

    local netId = NetworkGetNetworkIdFromEntity(veh)

    if enable == nil then
        data.sirenOn = not data.sirenOn
    else
        data.sirenOn = enable
    end

    if data.sirenOn then
        data.sirenMuted = false
        if data.stage == 0 and IsVehicleELS(veh) then
            SetLightStage(3)
        else
            ApplyVehicleSound(veh, true, false, data.sirenTone)
            TriggerServerEvent('SpaceELS:server:syncSirenState', netId, true, false, data.sirenTone)
        end
    else
        data.sirenMuted = true
        local keepLights = IsVehicleELS(veh) and (data.stage > 0) or false
        ApplyVehicleSound(veh, keepLights, true)
        TriggerServerEvent('SpaceELS:server:syncSirenState', netId, keepLights, true)
    end

    SendNUIMessage({
        action = 'updateState',
        data = CollectVehicleState()
    })
end

local function ToggleSirenMute(mute)
    local veh = GetTargetVehicle()
    if veh == 0 or not DoesEntityExist(veh) then return end
    local data = GetVehicleELSData(veh)
    EnsureEntityControl(veh)

    local netId = NetworkGetNetworkIdFromEntity(veh)

    if mute == nil then
        data.sirenMuted = not data.sirenMuted
    else
        data.sirenMuted = mute
    end

    if data.sirenMuted then
        data.sirenOn = false
        ApplyVehicleSound(veh, data.stage > 0, true)
    else
        if data.stage > 0 then
            data.sirenOn = true
            ApplyVehicleSound(veh, true, false, data.sirenTone)
        end
    end

    TriggerServerEvent('SpaceELS:server:syncSirenState', netId, data.stage > 0, data.sirenMuted, data.sirenTone)

    SendNUIMessage({
        action = 'updateState',
        data = CollectVehicleState()
    })
end

local function DestroyStudioCamera()
    if studioCamera and DoesCamExist(studioCamera) then
        RenderScriptCams(false, true, 400, true, false)
        DestroyCam(studioCamera, false)
        studioCamera = nil
    end
end

local function UpdateStudioCamera(veh)
    if not DoesEntityExist(veh) or not studioCamera then return end
    local vCoords = GetEntityCoords(veh)
    local vHeading = GetEntityHeading(veh)
    local totalAngle = math.rad(vHeading + camYaw)

    local x = vCoords.x - math.sin(totalAngle) * camDist * math.cos(math.rad(camPitch))
    local y = vCoords.y + math.cos(totalAngle) * camDist * math.cos(math.rad(camPitch))
    local z = vCoords.z + math.sin(math.rad(camPitch)) * camDist + 0.5

    SetCamCoord(studioCamera, x, y, z)
    PointCamAtCoord(studioCamera, vCoords.x, vCoords.y, vCoords.z + 0.3)
end

local function CreateStudioCamera(veh)
    DestroyStudioCamera()
    if not DoesEntityExist(veh) then return end
    camYaw = 180.0
    camPitch = 12.0
    camDist = 6.2

    studioCamera = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    UpdateStudioCamera(veh)
    SetCamActive(studioCamera, true)
    RenderScriptCams(true, true, 400, true, false)
end

local function OpenELSUI()
    local veh = GetTargetVehicle()
    if veh == 0 or not DoesEntityExist(veh) then return end
    if not IsVehicleELS(veh) then return end

    isUIOpen = true
    SetNuiFocus(true, true)
    local soundVolume = (Config and Config.ELS and Config.ELS.SoundVolume) or 0.6
    SendNUIMessage({
        action = 'open',
        soundVolume = soundVolume,
        data = CollectVehicleState()
    })
end

local function CloseELSUI()
    if not isUIOpen then return end
    isUIOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function ToggleELSUI()
    if isUIOpen then CloseELSUI() else OpenELSUI() end
end

local function OpenControlELS()
    local veh = GetTargetVehicle()
    if veh == 0 or not DoesEntityExist(veh) then return end
    if IsNonELSVehicle(veh) then return end

    local modelHash = GetEntityModel(veh)
    local rawModel = string.lower(GetDisplayNameFromVehicleModel(modelHash)):gsub("^%s*(.-)%s*$", "%1")
    local installedExtras = {}
    for i = 1, 12 do
        if DoesExtraExist(veh, i) == 1 or DoesExtraExist(veh, i) == true then
            table.insert(installedExtras, i)
        end
    end

    isBuilderOpen = true
    SetNuiFocus(true, true)
    CreateStudioCamera(veh)

    SendNUIMessage({
        action = 'openBuilder',
        data = {
            modelName = rawModel,
            installedExtras = installedExtras,
            profile = GetProfileForVehicle(veh)
        }
    })
end

local function RequestOpenControlELS()
    if not isInVehicle or isBuilderOpen then return end
    local veh = GetTargetVehicle()
    if veh == 0 or not DoesEntityExist(veh) then return end
    if IsNonELSVehicle(veh) then return end

    TriggerServerEvent('SpaceELS:server:checkBuilderAccess')
end

RegisterNetEvent('SpaceELS:client:openBuilderAuthorized', function()
    OpenControlELS()
end)

local function CloseControlELS()
    if not isBuilderOpen then return end
    isBuilderOpen = false
    SetNuiFocus(false, false)
    DestroyStudioCamera()
    SendNUIMessage({ action = 'closeBuilder' })

    local veh = GetTargetVehicle()
    if veh ~= 0 and DoesEntityExist(veh) then
        local data = GetVehicleELSData(veh)
        if data then
            data.testingStage = nil
            data.testProfile = nil
            ResetStageExtras(veh, data)
        end
    end
end

RegisterNUICallback('close', function(_, cb)
    CloseELSUI()
    cb({ ok = true })
end)

RegisterNUICallback('toggleStage', function(data, cb)
    SetLightStage(tonumber(data.stage) or 0)
    cb({ ok = true })
end)

RegisterNUICallback('toggleSirenAudio', function(data, cb)
    ToggleSirenAudio(data.state)
    cb({ ok = true })
end)

RegisterNUICallback('setSirenTone', function(data, cb)
    if data.tone then SetSirenTone(data.tone) end
    cb({ ok = true })
end)

RegisterNUICallback('toggleSirenMute', function(data, cb)
    ToggleSirenMute(data.state)
    cb({ ok = true })
end)

RegisterNUICallback('triggerAirhorn', function(data, cb)
    TriggerAirhorn(data.blasting)
    cb({ ok = true })
end)

RegisterNUICallback('rotateCamera', function(data, cb)
    local veh = GetTargetVehicle()
    if veh ~= 0 and studioCamera then
        if data.deltaYaw then camYaw = (camYaw + tonumber(data.deltaYaw)) % 360.0 end
        if data.deltaPitch then camPitch = math.max(-10.0, math.min(60.0, camPitch + tonumber(data.deltaPitch))) end
        if data.preset then
            if data.preset == 'front' then camYaw = 180.0 camPitch = 12.0
            elseif data.preset == 'back' then camYaw = 0.0 camPitch = 12.0
            elseif data.preset == 'left' then camYaw = 90.0 camPitch = 10.0
            elseif data.preset == 'right' then camYaw = 270.0 camPitch = 10.0
            elseif data.preset == 'top' then camYaw = 180.0 camPitch = 55.0
            end
        end
        UpdateStudioCamera(veh)
    end
    cb({ ok = true })
end)

RegisterNUICallback('closeBuilder', function(_, cb)
    CloseControlELS()
    cb({ ok = true })
end)

RegisterNUICallback('builderTestStage', function(data, cb)
    local veh = GetTargetVehicle()
    if veh ~= 0 and DoesEntityExist(veh) then
        EnsureEntityControl(veh)
        local vData = GetVehicleELSData(veh)
        if vData then
            ResetStageExtras(veh, vData)
            local stg = tonumber(data.stage) or 3
            vData.testingStage = stg
            vData.testProfile = data.profile
            SetupVehicleStageData(veh, vData, stg, data.profile)
        end
    end
    cb({ ok = true })
end)

RegisterNUICallback('builderInspectExtra', function(data, cb)
    local veh = GetTargetVehicle()
    if veh ~= 0 and DoesEntityExist(veh) then
        EnsureEntityControl(veh)
        local extraId = tonumber(data.extraId) or 0
        local vData = GetVehicleELSData(veh)
        if vData then
            vData.testingStage = nil
            vData.testProfile = nil
            ResetStageExtras(veh, vData)
            SetExtraState(veh, vData, extraId, true)
        end
    end
    cb({ ok = true })
end)

RegisterNUICallback('builderStopTest', function(_, cb)
    local veh = GetTargetVehicle()
    if veh ~= 0 and DoesEntityExist(veh) then
        local vData = GetVehicleELSData(veh)
        if vData then
            vData.testingStage = nil
            vData.testProfile = nil
            ResetStageExtras(veh, vData)
        end
    end
    cb({ ok = true })
end)

RegisterNUICallback('builderSaveProfile', function(data, cb)
    if data.modelName and data.profile then
        local model = string.lower(data.modelName):gsub("^%s*(.-)%s*$", "%1")
        customVehicleProfiles[model] = data.profile
        vehicleModelProfileCache = {}
        vehicleEmergencyCache = {}
        TriggerServerEvent('SpaceELS:server:saveVehicleProfile', model, data.profile)
    end
    cb({ ok = true })
end)

RegisterNUICallback('builderResetProfile', function(data, cb)
    if data.modelName then
        local model = string.lower(data.modelName):gsub("^%s*(.-)%s*$", "%1")
        customVehicleProfiles[model] = nil
        vehicleModelProfileCache = {}
        vehicleEmergencyCache = {}
        TriggerServerEvent('SpaceELS:server:resetVehicleProfile', model)
    end
    cb({ ok = true })
end)

RegisterNetEvent('SpaceELS:client:syncELSStage', function(netId, stage, extras, muteSiren, sirenOn)
    if not NetworkDoesEntityExistWithNetworkId(netId) then return end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not DoesEntityExist(veh) then return end

    local data = GetVehicleELSData(veh)
    if data then
        data.stage = stage
        data.sirenMuted = muteSiren
        data.sirenOn = sirenOn
        ResetStageExtras(veh, data)
        SetupVehicleStageData(veh, data, stage, nil)
    end
    ApplyVehicleSound(veh, sirenOn, muteSiren)
end)

RegisterNetEvent('SpaceELS:client:syncExtra', function(netId, extraId, state)
    if not NetworkDoesEntityExistWithNetworkId(netId) then return end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not DoesEntityExist(veh) then return end

    local data = GetVehicleELSData(veh)
    if data then
        SetExtraState(veh, data, extraId, state)
    end
end)

RegisterNetEvent('SpaceELS:client:syncSirenState', function(netId, sirenOn, muted, tone)
    if not NetworkDoesEntityExistWithNetworkId(netId) then return end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not DoesEntityExist(veh) then return end

    local data = GetVehicleELSData(veh)
    if data then
        data.sirenOn = sirenOn
        data.sirenMuted = muted
        if tone then data.sirenTone = tone end
    end
    ApplyVehicleSound(veh, sirenOn, muted, tone)
end)

RegisterNetEvent('SpaceELS:client:syncAirhorn', function(netId, isBlasting)
    if not NetworkDoesEntityExistWithNetworkId(netId) then return end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not DoesEntityExist(veh) then return end

    if isBlasting then
        StartVehicleHornSound(veh)
    else
        StopVehicleHornSound(veh)
    end
end)

RegisterNetEvent('SpaceELS:client:receiveProfiles', function(profiles)
    if profiles and type(profiles) == 'table' then
        customVehicleProfiles = profiles
        vehicleModelProfileCache = {}
        vehicleEmergencyCache = {}
    end
end)

RegisterNetEvent('SpaceELS:client:updateSingleProfile', function(modelName, profileData)
    if not modelName then return end
    modelName = string.lower(modelName)
    customVehicleProfiles[modelName] = profileData
    vehicleModelProfileCache = {}
    vehicleEmergencyCache = {}
    for veh, data in pairs(trackedVehicles) do
        if DoesEntityExist(veh) then
            data.profile = GetProfileForVehicle(veh)
            if data.stage > 0 then
                SetupVehicleStageData(veh, data, data.stage, nil)
            end
        end
    end
end)

local function HandleKeyStage()
    if not isInVehicle or isUIOpen or isBuilderOpen then return end
    local veh = GetTargetVehicle()
    if veh == 0 or not DoesEntityExist(veh) then return end
    if not IsVehicleELS(veh) then return end
    local data = GetVehicleELSData(veh)
    local current = data.stage or 0

    local prof = data.profile or GetProfileForVehicle(veh)
    local avail = { 0 }
    if prof then
        for s = 1, 3 do
            if prof["stage" .. s] ~= nil then table.insert(avail, s) end
        end
    else
        avail = { 0, 1, 2, 3 }
    end

    if #avail <= 1 then
        SetLightStage(0)
        return
    end

    local curIdx = 1
    for idx, stg in ipairs(avail) do
        if stg == current then curIdx = idx break end
    end

    local nextIdx = (curIdx % #avail) + 1
    PlaySoundFrontend(-1, "NAV_UP_DOWN", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
    SetLightStage(avail[nextIdx])
end

local function HandleKeySiren()
    if not isInVehicle or isUIOpen or isBuilderOpen then return end
    local veh = GetTargetVehicle()
    if veh == 0 or not DoesEntityExist(veh) then return end
    local data = GetVehicleELSData(veh)
    local isELS = IsVehicleELS(veh)

    local tones = { "wail", "yelp", "priority", "hilo" }

    if not data.sirenOn or data.sirenMuted then
        data.sirenOn = true
        data.sirenMuted = false
        data.sirenTone = "wail"
        PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
        ApplyVehicleSound(veh, true, false, "wail")
        local netId = NetworkGetNetworkIdFromEntity(veh)
        TriggerServerEvent('SpaceELS:server:syncSirenState', netId, true, false, "wail")
    else
        local curIdx = 1
        for i, t in ipairs(tones) do
            if t == data.sirenTone then curIdx = i break end
        end

        if curIdx < #tones then
            local nextTone = tones[curIdx + 1]
            data.sirenTone = nextTone
            PlaySoundFrontend(-1, "NAV_LEFT_RIGHT", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
            ApplyVehicleSound(veh, true, false, nextTone)
            local netId = NetworkGetNetworkIdFromEntity(veh)
            TriggerServerEvent('SpaceELS:server:syncSirenState', netId, true, false, nextTone)
        else
            data.sirenOn = false
            data.sirenMuted = true
            PlaySoundFrontend(-1, "CANCEL", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
            local keepLights = isELS and (data.stage > 0) or false
            ApplyVehicleSound(veh, keepLights, true)
            local netId = NetworkGetNetworkIdFromEntity(veh)
            TriggerServerEvent('SpaceELS:server:syncSirenState', netId, keepLights, true)
        end
    end

    SendNUIMessage({
        action = 'updateState',
        data = CollectVehicleState()
    })
end

local elsCmd = (Config and Config.ELS and Config.ELS.Command) or 'els'
local elsCmdAlias = (Config and Config.ELS and Config.ELS.CommandAlias) or 'elsui'
local studioCmd = (Config and Config.ELS and Config.ELS.StudioCommand) or 'controlels'
local studioCmdAlias = (Config and Config.ELS and Config.ELS.StudioCommandAlias) or 'elscontrol'
local defaultKey = (Config and Config.ELS and Config.ELS.DefaultKey) or 'U'
local keyDesc = (Config and Config.ELS and Config.ELS.KeyDescription) or 'Toggle ELS UI'

RegisterCommand(elsCmd, function()
    if not isInVehicle or isBuilderOpen then return end
    ToggleELSUI()
end, false)

if elsCmdAlias and elsCmdAlias ~= '' and elsCmdAlias ~= elsCmd then
    RegisterCommand(elsCmdAlias, function()
        if not isInVehicle or isBuilderOpen then return end
        ToggleELSUI()
    end, false)
end

RegisterCommand(studioCmd, function() RequestOpenControlELS() end, false)
if studioCmdAlias and studioCmdAlias ~= '' and studioCmdAlias ~= studioCmd then
    RegisterCommand(studioCmdAlias, function() RequestOpenControlELS() end, false)
end
RegisterCommand('elsprofile', function() RequestOpenControlELS() end, false)

RegisterCommand('els_stage', function() HandleKeyStage() end, false)
RegisterCommand('els_siren', function() HandleKeySiren() end, false)
RegisterCommand('+els_horn', function()
    if isInVehicle and not isUIOpen and not isBuilderOpen then
        TriggerAirhorn(true)
    end
end, false)
RegisterCommand('-els_horn', function()
    if isInVehicle then
        TriggerAirhorn(false)
    end
end, false)

RegisterKeyMapping(elsCmd, keyDesc, 'keyboard', defaultKey)
RegisterKeyMapping('els_stage', 'Toggle ELS Stages', 'keyboard', 'J')
RegisterKeyMapping('els_siren', 'Cycle ELS Siren Tones', 'keyboard', 'LCONTROL')
RegisterKeyMapping('+els_horn', 'Blast ELS Airhorn', 'keyboard', 'E')

AddEventHandler('onClientResourceStart', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        TriggerServerEvent('SpaceELS:server:requestProfiles')
    end
end)

AddEventHandler('playerSpawned', function()
    TriggerServerEvent('SpaceELS:server:requestProfiles')
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        for veh, _ in pairs(trackedVehicles) do
            StopVehicleSirenSound(veh)
            StopVehicleHornSound(veh)
        end
        if isUIOpen or isBuilderOpen then
            SetNuiFocus(false, false)
            DestroyStudioCamera()
        end
    end
end)
