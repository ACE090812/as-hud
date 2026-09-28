-- Server side of the integrated chat: suggestion registry (so suggestions
-- registered by other resources reach players who join later), the server
-- command list, and relaying chat messages between players.

local chatConfig = Config.Chat or {}

if chatConfig.enabled == false then
    return
end

local suggestions = {}
local lastMessageAt = {}

local function addSuggestion(name, help, params)
    if type(name) ~= 'string' or name == '' then
        return
    end

    suggestions[name] = { name = name, help = help or '', params = params or {} }
    TriggerClientEvent('chat:addSuggestion', -1, name, help, params)
end

local function removeSuggestion(name)
    if type(name) ~= 'string' then
        return
    end

    suggestions[name] = nil
    TriggerClientEvent('chat:removeSuggestion', -1, name)
end

exports('addSuggestion', addSuggestion)
exports('removeSuggestion', removeSuggestion)

RegisterNetEvent('chat:addSuggestion', function(name, help, params)
    addSuggestion(name, help, params)
end)

RegisterNetEvent('chat:addSuggestions', function(list)
    if type(list) ~= 'table' then
        return
    end

    for _, suggestion in ipairs(list) do
        if type(suggestion) == 'table' then
            addSuggestion(suggestion.name, suggestion.help, suggestion.params)
        end
    end
end)

RegisterNetEvent('chat:removeSuggestion', function(name)
    removeSuggestion(name)
end)

RegisterNetEvent('chat:clear', function()
    TriggerClientEvent('chat:clear', -1)
end)

RegisterNetEvent('chat:init', function()
    local source = source
    for _, suggestion in pairs(suggestions) do
        TriggerClientEvent('chat:addSuggestion', source, suggestion.name, suggestion.help, suggestion.params)
    end
end)

RegisterNetEvent('as-hud:chat:commands', function()
    local src = source
    local commands = {}

    for _, command in ipairs(GetRegisteredCommands()) do
        local firstChar = command.name:sub(1, 1)
        if firstChar ~= '+' and firstChar ~= '-' and IsPlayerAceAllowed(src, 'command.' .. command.name) then
            commands[#commands + 1] = { name = '/' .. command.name }
        end
    end

    TriggerClientEvent('as-hud:chat:commands', src, commands)
end)

local function sanitizeMessage(message, maxLength)
    message = message:gsub('[%z\1-\31\127]', '')
    message = message:match('^%s*(.-)%s*$') or ''

    if #message > maxLength then
        message = message:sub(1, maxLength)
    end

    return message
end

RegisterNetEvent('as-hud:chat:send', function(message)
    local src = source

    if type(message) ~= 'string' then
        return
    end

    local cooldown = chatConfig.cooldown or 800
    local now = GetGameTimer()
    local last = lastMessageAt[src] or 0

    if now - last < cooldown then
        return
    end
    lastMessageAt[src] = now

    message = sanitizeMessage(message, chatConfig.maxLength or 300)
    if message == '' then
        return
    end

    local author = GetPlayerName(src) or ('Player ' .. src)
    TriggerClientEvent('chatMessage', -1, author, nil, message)
end)

AddEventHandler('playerDropped', function()
    lastMessageAt[source] = nil
end)
