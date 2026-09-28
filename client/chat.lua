asChat = {}

local chatConfig = Config.Chat or {}

local function isPlayerTalking()
    local playerId = PlayerId()
    if NetworkIsPlayerTalking(playerId) then
        return true
    end
    if type(MumbleIsPlayerTalking) == "function" and MumbleIsPlayerTalking(playerId) then
        return true
    end
    return false
end

if chatConfig.enabled == false then
    asChat.IsTalking = isPlayerTalking
    asChat.Close = function() end
    asChat.SetVisible = function() end
    return
end

local MAX_PENDING_MESSAGES = 200
local IDLE_CLOSE_TIMEOUT_MS = 8000

local isChatOpen = false
local isNuiReady = false
local isChatVisible = true
local lastActivityTime = 0
local pendingMessages = {}

SetTextChatEnabled(false)

asChat.IsTalking = isPlayerTalking

function asChat.Close()
    if not isChatOpen then
        return
    end
    isChatOpen = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = "chatClose" })
end

local function sendToChat(payload)
    if isNuiReady then
        SendNUIMessage(payload)
        return
    end
    pendingMessages[#pendingMessages + 1] = payload
    if #pendingMessages > MAX_PENDING_MESSAGES then
        table.remove(pendingMessages, 1)
    end
end

local function addMessage(message)
    if type(message) == "string" then
        message = { args = { message } }
    end
    if type(message) == "table" then
        sendToChat({ action = "chatMessage", message = message })
    end
end

RegisterNetEvent("chat:addMessage", addMessage)
exports("addMessage", addMessage)

RegisterNetEvent("chatMessage", function(author, color, text)
    addMessage({
        args = (author and author ~= "") and { author, text } or { text },
        color = color
    })
end)

RegisterNetEvent("__cfx_internal:serverPrint", function(message)
    addMessage({ args = { message } })
end)

local function addSuggestion(name, help, params)
    if type(name) ~= "string" then
        return
    end
    sendToChat({
        action = "chatSuggestion",
        suggestion = {
            name = name,
            help = help or "",
            params = params or {}
        }
    })
end

exports("addSuggestion", addSuggestion)
RegisterNetEvent("chat:addSuggestion", addSuggestion)

RegisterNetEvent("chat:addSuggestions", function(suggestions)
    if type(suggestions) ~= "table" then
        return
    end
    for _, suggestion in ipairs(suggestions) do
        if type(suggestion) == "table" then
            addSuggestion(suggestion.name, suggestion.help, suggestion.params)
        end
    end
end)

RegisterNetEvent("chat:removeSuggestion", function(name)
    sendToChat({ action = "chatRemoveSuggestion", name = name })
end)

RegisterNetEvent("chat:clear", function()
    sendToChat({ action = "chatClear" })
end)

RegisterNetEvent("as-hud:chat:commands", function(commands)
    sendToChat({ action = "chatServerCommands", commands = commands })
end)

local function refreshCommandList()
    local commands = {}
    for _, command in ipairs(GetRegisteredCommands()) do
        local firstChar = command.name:sub(1, 1)
        if firstChar ~= "+" and firstChar ~= "-" and IsAceAllowed("command." .. command.name) then
            commands[#commands + 1] = { name = "/" .. command.name }
        end
    end
    sendToChat({ action = "chatCommands", commands = commands })
    TriggerServerEvent("as-hud:chat:commands")
end

local function isHudBlockingChat()
    return IsPauseMenuActive()
        or IsScreenFadedOut()
        or HudPreferences.IsOpen()
        or not HudPreferences.Option("hud", true)
        or not HudPreferences.Option("playerStatus", true)
end

RegisterCommand("+asChat", function() end, false)

RegisterCommand("-asChat", function()
    if not isNuiReady or isChatOpen or not isChatVisible then
        return
    end
    if IsPauseMenuActive() or IsScreenFadedOut() or IsNuiFocused() or HudPreferences.IsOpen() then
        return
    end
    if not HudPreferences.Option("hud", true) or not HudPreferences.Option("playerStatus", true) then
        return
    end

    isChatOpen = true
    lastActivityTime = GetGameTimer()
    refreshCommandList()
    SetNuiFocus(true, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = "chatOpen" })
end, false)

RegisterKeyMapping("+asChat", "as HUD: open chat", "keyboard", chatConfig.key or "T")

RegisterNUICallback("asChatReady", function(_, callback)
    isNuiReady = true

    SendNUIMessage({
        action = "chatConfig",
        config = {
            maxLength = chatConfig.maxLength or 300,
            maxMessages = chatConfig.maxMessages or 60,
            messageLifetime = chatConfig.messageLifetime or 8000
        }
    })

    for _, payload in ipairs(pendingMessages) do
        SendNUIMessage(payload)
    end
    pendingMessages = {}

    refreshCommandList()
    TriggerServerEvent("chat:init")
    callback({ ok = true })
end)

RegisterNUICallback("asChatSubmit", function(data, callback)
    if not isChatOpen then
        callback({ ok = false })
        return
    end

    local message = type(data.message) == "string" and data.message or ""
    local maxLength = math.max(1, math.min(1000, chatConfig.maxLength or 300))

    if #message > maxLength * 4 then
        callback({ ok = false })
        return
    end

    message = message:gsub("[%z\001-\031\127]", "")
    message = message:match("^%s*(.-)%s*$")

    asChat.Close()
    callback({ ok = true })

    if message == "" then
        return
    end

    if message:sub(1, 1) == "/" then
        ExecuteCommand(message:sub(2))
    else
        TriggerServerEvent("as-hud:chat:send", message)
    end
end)

RegisterNUICallback("asChatClose", function(_, callback)
    asChat.Close()
    callback({ ok = true })
end)

RegisterNUICallback("asChatHeartbeat", function(_, callback)
    if isChatOpen then
        lastActivityTime = GetGameTimer()
    end
    callback({ ok = true })
end)

RegisterNetEvent("QBCore:Client:OnPlayerUnload", asChat.Close)
RegisterNetEvent("esx:onPlayerLogout", asChat.Close)

AddEventHandler("onClientResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        asChat.Close()
        SetTextChatEnabled(true)
    end
end)

CreateThread(function()
    local wasTalking = nil
    while true do
        Wait(60)

        local isTalking = asChat.IsTalking()
        if isTalking ~= wasTalking then
            wasTalking = isTalking
            SendNUIMessage({ action = "status", talking = isTalking })
        end

        if isChatOpen then
            local shouldClose = not isChatVisible
                or isHudBlockingChat()
                or (GetGameTimer() - lastActivityTime) > IDLE_CLOSE_TIMEOUT_MS
            if shouldClose then
                asChat.Close()
            end
        end
    end
end)

function asChat.SetVisible(visible)
    isChatVisible = visible
    if not visible then
        asChat.Close()
    end
end

CreateThread(function()
    while true do
        SetTextChatEnabled(false)
        DisableControlAction(0, 245, true)
        DisableControlAction(0, 246, true)
        DisableControlAction(0, 247, true)
        DisableControlAction(0, 248, true)
        Wait(0)
    end
end)