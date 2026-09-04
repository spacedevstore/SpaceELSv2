local profilesFile = 'vehicle_profiles.json'
local vehicleProfiles = {}

local function LoadProfiles()
    local content = LoadResourceFile(GetCurrentResourceName(), profilesFile)
    if content and content:match('%S') then
        local success, decoded = pcall(json.decode, content)
        if success and type(decoded) == 'table' then
            vehicleProfiles = decoded
            return
        end
    end
    vehicleProfiles = {}
end

local function SaveProfiles()
    SaveResourceFile(GetCurrentResourceName(), profilesFile, json.encode(vehicleProfiles, { indent = true }), -1)
end

LoadProfiles()

local function IsPlayerAuthorized(src)
    if not Config or not Config.ELS or Config.ELS.RequireAdminForBuilder == false then
        return true
    end

    local adminIds = Config.ELS.AdminIdentifiers or {}
    if #adminIds > 0 then
        local playerIds = GetPlayerIdentifiers(src)
        for _, pid in ipairs(playerIds) do
            local pidLower = string.lower(pid)
            for _, allowedId in ipairs(adminIds) do
                if pidLower == string.lower(allowedId) then
                    return true
                end
            end
        end
    end

    local requiredPerm = Config.ELS.AdminPermission
    if requiredPerm and requiredPerm ~= '' then
        if IsPlayerAceAllowed(src, requiredPerm) or IsPlayerAceAllowed(src, 'spaceels.admin') then
            return true
        end
    end

    return false
end

RegisterNetEvent('SpaceELS:server:checkBuilderAccess', function()
    local src = source
    if IsPlayerAuthorized(src) then
        TriggerClientEvent('SpaceELS:client:openBuilderAuthorized', src)
    else
        TriggerClientEvent('chat:addMessage', src, {
            color = { 255, 60, 60 },
            multiline = true,
            args = { 'SpaceELS', 'You do not have permission to access the ELS Studio menu.' }
        })
    end
end)

local function ValidateVehicleEntity(src, netId)
    if not netId or type(netId) ~= 'number' then return false end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or not DoesEntityExist(entity) then return false end

    local ped = GetPlayerPed(src)
    if not ped or not DoesEntityExist(ped) then return false end

    local pCoords = GetEntityCoords(ped)
    local vCoords = GetEntityCoords(entity)
    local dist = #(pCoords - vCoords)
    if dist > 60.0 then
        return false
    end

    return true
end

local function BroadcastExcept(src, eventName, ...)
    for _, playerId in ipairs(GetPlayers()) do
        local pid = tonumber(playerId)
        if pid ~= src then
            TriggerClientEvent(eventName, pid, ...)
        end
    end
end

RegisterNetEvent('SpaceELS:server:syncELSStage', function(netId, stage, extras, muteSiren, sirenOn)
    local src = source
    if not ValidateVehicleEntity(src, netId) then return end
    BroadcastExcept(src, 'SpaceELS:client:syncELSStage', netId, stage, extras, muteSiren, sirenOn)
end)

RegisterNetEvent('SpaceELS:server:syncExtra', function(netId, extraId, state)
    local src = source
    if not ValidateVehicleEntity(src, netId) or not extraId then return end
    BroadcastExcept(src, 'SpaceELS:client:syncExtra', netId, extraId, state)
end)

RegisterNetEvent('SpaceELS:server:syncSirenState', function(netId, sirenOn, muted, tone)
    local src = source
    if not ValidateVehicleEntity(src, netId) then return end
    BroadcastExcept(src, 'SpaceELS:client:syncSirenState', netId, sirenOn, muted, tone)
end)

RegisterNetEvent('SpaceELS:server:syncAirhorn', function(netId, isBlasting)
    local src = source
    if not ValidateVehicleEntity(src, netId) then return end
    BroadcastExcept(src, 'SpaceELS:client:syncAirhorn', netId, isBlasting)
end)

RegisterNetEvent('SpaceELS:server:requestProfiles', function()
    local src = source
    TriggerClientEvent('SpaceELS:client:receiveProfiles', src, vehicleProfiles)
end)

RegisterNetEvent('SpaceELS:server:saveVehicleProfile', function(modelName, profileData)
    local src = source
    if not IsPlayerAuthorized(src) then
        print(('[SpaceELS] Player %s (%s) tried to save profile without permission'):format(GetPlayerName(src) or 'Unknown', src))
        return
    end

    if not modelName or type(modelName) ~= 'string' or type(profileData) ~= 'table' then return end
    modelName = string.lower(modelName):gsub("^%s*(.-)%s*$", "%1")
    if #modelName == 0 or #modelName > 50 or modelName:match('[^%w_%-]') then
        return
    end

    vehicleProfiles[modelName] = profileData
    SaveProfiles()
    TriggerClientEvent('SpaceELS:client:updateSingleProfile', -1, modelName, profileData)
end)

RegisterNetEvent('SpaceELS:server:resetVehicleProfile', function(modelName)
    local src = source
    if not IsPlayerAuthorized(src) then
        print(('[SpaceELS] Player %s (%s) tried to reset profile without permission'):format(GetPlayerName(src) or 'Unknown', src))
        return
    end

    if not modelName or type(modelName) ~= 'string' then return end
    modelName = string.lower(modelName):gsub("^%s*(.-)%s*$", "%1")
    if #modelName == 0 or #modelName > 50 or modelName:match('[^%w_%-]') then
        return
    end

    vehicleProfiles[modelName] = nil
    SaveProfiles()
    TriggerClientEvent('SpaceELS:client:updateSingleProfile', -1, modelName, nil)
end)