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

RegisterNetEvent('SpaceELS:server:syncELSStage', function(netId, stage, extras, muteSiren, sirenOn)
    if not netId then return end
    TriggerClientEvent('SpaceELS:client:syncELSStage', -1, netId, stage, extras, muteSiren, sirenOn)
end)

RegisterNetEvent('SpaceELS:server:syncExtra', function(netId, extraId, state)
    if not netId or not extraId then return end
    TriggerClientEvent('SpaceELS:client:syncExtra', -1, netId, extraId, state)
end)

RegisterNetEvent('SpaceELS:server:syncSirenState', function(netId, sirenOn, muted, tone)
    if not netId then return end
    TriggerClientEvent('SpaceELS:client:syncSirenState', -1, netId, sirenOn, muted, tone)
end)

RegisterNetEvent('SpaceELS:server:syncAirhorn', function(netId, isBlasting)
    if not netId then return end
    TriggerClientEvent('SpaceELS:client:syncAirhorn', -1, netId, isBlasting)
end)

RegisterNetEvent('SpaceELS:server:requestProfiles', function()
    local src = source
    TriggerClientEvent('SpaceELS:client:receiveProfiles', src, vehicleProfiles)
end)

RegisterNetEvent('SpaceELS:server:saveVehicleProfile', function(modelName, profileData)
    local src = source
    if not modelName or not profileData then return end
    modelName = string.lower(tostring(modelName)):gsub("^%s*(.-)%s*$", "%1")
    vehicleProfiles[modelName] = profileData
    SaveProfiles()
    TriggerClientEvent('SpaceELS:client:updateSingleProfile', -1, modelName, profileData)
end)

RegisterNetEvent('SpaceELS:server:resetVehicleProfile', function(modelName)
    local src = source
    if not modelName then return end
    modelName = string.lower(tostring(modelName)):gsub("^%s*(.-)%s*$", "%1")
    vehicleProfiles[modelName] = nil
    SaveProfiles()
    TriggerClientEvent('SpaceELS:client:updateSingleProfile', -1, modelName, nil)
end)