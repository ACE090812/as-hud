-- Admin stress commands (Config.StressCommands). Framework-agnostic: checks
-- ACE permissions first, then falls back to QBox/QBCore/ESX admin checks.

local function isConsole(source)
    return source == 0
end

local function hasAce(source, ace)
    return IsPlayerAceAllowed(source, ace)
end

local function isFrameworkAdmin(source)
    if GetResourceState('qbx_core') == 'started' then
        local ok, isAdmin = pcall(function()
            return exports['qbx_core']:HasPermission(source, 'admin') or exports['qbx_core']:HasPermission(source, 'god')
        end)
        if ok and isAdmin then return true end
    end

    if GetResourceState('qb-core') == 'started' then
        local ok, isAdmin = pcall(function()
            local QBCore = exports['qb-core']:GetCoreObject()
            local player = QBCore.Functions.GetPlayer(source)
            if not player then return false end
            if QBCore.Functions.HasPermission and QBCore.Functions.HasPermission(source, 'admin') then
                return true
            end
            local permission = player.PlayerData and player.PlayerData.permission
            return permission == 'admin' or permission == 'god'
        end)
        if ok and isAdmin then return true end
    end

    if GetResourceState('es_extended') == 'started' then
        local ok, isAdmin = pcall(function()
            local ESX = exports['es_extended']:getSharedObject()
            local xPlayer = ESX.GetPlayerFromId(source)
            if not xPlayer then return false end
            local group = xPlayer.getGroup()
            return group == 'admin' or group == 'superadmin'
        end)
        if ok and isAdmin then return true end
    end

    return false
end

local function isAuthorized(source, commandName)
    if isConsole(source) then
        return true
    end

    local stressCommands = Config.StressCommands or {}
    local acePermission = stressCommands.acePermission

    if acePermission == false then
        return true
    end

    if type(acePermission) == 'string' and acePermission ~= '' then
        return hasAce(source, acePermission)
    end

    if hasAce(source, 'command.' .. commandName) then
        return true
    end

    if hasAce(source, 'group.admin') or hasAce(source, 'group.superadmin') then
        return true
    end

    return isFrameworkAdmin(source)
end

local function notify(source, message)
    if source == 0 then
        print(message)
    else
        TriggerClientEvent('chat:addMessage', source, { args = { 'as-hud', message } })
    end
end

local stressCommands = Config.StressCommands or {}

if stressCommands.enabled then
    local addCommandName = stressCommands.add or 'addstress'
    local removeCommandName = stressCommands.remove or 'removestress'

    RegisterCommand(addCommandName, function(source, args)
        if not isAuthorized(source, addCommandName) then
            notify(source, 'You are not allowed to use this command.')
            return
        end

        local targetId = tonumber(args[1])
        local amount = tonumber(args[2])

        if not targetId or not amount then
            notify(source, ('Usage: /%s <id> <percent>'):format(addCommandName))
            return
        end

        if not GetPlayerName(targetId) then
            notify(source, 'No such player.')
            return
        end

        TriggerClientEvent('as-hud:addStress', targetId, amount)
    end, false)

    RegisterCommand(removeCommandName, function(source, args)
        if not isAuthorized(source, removeCommandName) then
            notify(source, 'You are not allowed to use this command.')
            return
        end

        local targetId = tonumber(args[1]) or source

        if targetId == 0 then
            notify(source, ('Usage: /%s <id>'):format(removeCommandName))
            return
        end

        if not GetPlayerName(targetId) then
            notify(source, 'No such player.')
            return
        end

        TriggerClientEvent('as-hud:setStress', targetId, 0)
    end, false)
end

-- Clear stress on revive events fired server-side (some ambulance scripts
-- revive server-side rather than client-side; the client script already
-- covers client-fired revive events).
if Config.ClearStressOnRevive ~= false then
    local registeredReviveEvents = {}

    for _, eventName in ipairs(Config.ReviveEvents or {}) do
        if type(eventName) == 'string' and eventName ~= '' and not registeredReviveEvents[eventName] then
            registeredReviveEvents[eventName] = true

            pcall(RegisterNetEvent, eventName)
            AddEventHandler(eventName, function()
                local source = source
                if source and source > 0 then
                    TriggerClientEvent('as-hud:setStress', source, 0)
                end
            end)
        end
    end
end
