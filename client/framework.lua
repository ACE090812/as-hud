ashudPlayer = { data = {}, framework = nil }
local P = ashudPlayer
local names = {
    ['qb-core'] = 'qb',
    qbx_core = 'qbox',
    acestudios_core = 'acestudios',
    es_extended = 'esx',
}
local core

function P.detect()
    local found
    local requested = GetConvar('as-hud:framework', (ashudConfig and ashudConfig.framework) or 'auto')
    local aliases = {
        qb = 'qb-core',
        qbcore = 'qb-core',
        qbox = 'qbx_core',
        qbx = 'qbx_core',
        esx = 'es_extended',
        acestudios = 'acestudios_core',
    }
    requested = aliases[requested] or requested
    assert(requested == 'auto' or names[requested], 'as-hud: unsupported framework override ' .. requested)

    for i = 0, GetNumResources() - 1 do
        local name = GetResourceByFindIndex(i)
        if names[name] and GetResourceState(name) == 'started' and (requested == 'auto' or requested == name) then
            assert(not found, 'as-hud: more than one real player framework is running; set as-hud:framework explicitly')
            found = { name = names[name], resource = name }
        end
    end

    return found
end

local function copy(value)
    if type(value) ~= 'table' then
        return value
    end

    local out = {}
    for key, entry in pairs(value) do
        out[key] = copy(entry)
    end

    return out
end

function P.publish(data)
    data = copy(data or {})
    if P.framework and P.framework.name == 'esx' then
        data.citizenid = data.identifier
    end

    P.data = data.citizenid and data or {}
end

function P.refresh(playerLoaded)
    if not P.framework then
        return
    end

    if not playerLoaded and P.framework.name ~= 'esx' and LocalPlayer.state.isLoggedIn == false then
        P.publish({})
        return
    end
    if P.framework.name == 'qb' then
        core = core or exports['qb-core']:GetCoreObject()
        P.publish(core.Functions.GetPlayerData())
    elseif P.framework.name == 'esx' then
        core = core or exports.es_extended:getSharedObject()
        P.publish(core.IsPlayerLoaded() and core.GetPlayerData() or {})
    else
        P.publish(exports[P.framework.resource]:GetPlayerData())
    end
end

local function isESX()
    return P.framework and P.framework.name == 'esx'
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    if not isESX() then
        P.refresh(true)
    end
end)

RegisterNetEvent('QBCore:Client:UpdateObject', function()
    if P.framework and P.framework.name == 'qb' then
        core = nil
        P.refresh()
    end
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    if not isESX() then
        P.publish({})
    end
end)

RegisterNetEvent('QBCore:Player:SetPlayerData', function(data)
    if not isESX() then
        P.publish(data)
    end
end)

RegisterNetEvent('QBCore:Client:OnPlayerUpdated', function(key, value)
    if isESX() then
        return
    end

    if key == 'all' then
        P.publish(value)
    elseif key and P.data.citizenid then
        P.data[key] = copy(value)
    end
end)

RegisterNetEvent('esx:playerLoaded', function(data)
    if isESX() then
        P.publish(data)
    end
end)

RegisterNetEvent('esx:onPlayerLogout', function()
    if isESX() then
        P.publish({})
    end
end)

RegisterNetEvent('esx:setPlayerData', function(key, value)
    if isESX() and P.data.citizenid and key then
        P.data[key] = copy(value)
    end
end)

AddEventHandler('esx_status:onTick', function(statuses)
    if not isESX() or not P.data.citizenid then
        return
    end

    P.data.metadata = P.data.metadata or {}
    for _, status in pairs(type(statuses) == 'table' and statuses or {}) do
        if status.name == 'hunger' or status.name == 'thirst' then
            local value = tonumber(status.percent)
            if value then
                P.data.metadata[status.name] = math.max(0, math.min(100, value))
            end
        end
    end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if P.framework and P.framework.resource == resource then
        P.framework, core = nil, nil
        P.publish({})
    end
end)

CreateThread(function()
    local warned, attempts = false, 0
    while true do
        if not P.framework then
            local ok, framework = pcall(P.detect)
            if ok and framework then
                P.framework = framework
                local loaded, err = pcall(P.refresh)
                if not loaded then
                    P.framework, core = nil, nil
                    if not warned then
                        print(tostring(err))
                        warned = true
                    end
                else
                    warned = false
                    attempts = 0
                end
            elseif not ok and not warned then
                print(tostring(framework))
                warned = true
            end

            attempts = attempts + 1
            if ok and not framework and attempts >= 20 and not warned then
                print('as-hud: waiting for qb-core, qbx_core, es_extended or acestudios_core. Start one supported framework before this resource.')
                warned = true
            end
        end

        Wait(500)
    end
end)
