local previous = {}
local ready = false
local enabled = true
local street = ''
local crossStreet = ''
local zone = ''
local locationUpdated = -1000
local radioActive = false
local config = ashudConfig

local function percent(value)
    return math.floor(math.max(0, math.min(100, tonumber(value) or 0)) + 0.5)
end

local function publish(data)
    local changed = false
    for key, value in pairs(data) do
        if previous[key] ~= value then
            changed = true
            break
        end
    end
    if ready and changed then
        SendNUIMessage({ action = 'hud:update', data = data })
        previous = data
    end
end

RegisterNUICallback('ready', function(_, cb)
    ready = true
    previous = {}
    SendNUIMessage({ action = 'hud:config', data = config })
    ashudRadar.layout(true)
    cb({ ok = true })
end)

AddEventHandler('pma-voice:radioActive', function(active)
    radioActive = active == true
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource == 'pma-voice' then radioActive = false end
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    radioActive = false
end)

RegisterNetEvent('esx:onPlayerLogout', function()
    radioActive = false
end)

RegisterNetEvent('hud:client:UpdateNeeds', function(hunger, thirst)
    local data = ashudPlayer.data
    if not data.citizenid then return end
    data.metadata = data.metadata or {}
    data.metadata.hunger = tonumber(hunger) or data.metadata.hunger
    data.metadata.thirst = tonumber(thirst) or data.metadata.thirst
end)

exports('SetVisible', function(value)
    enabled = value ~= false
end)

AddStateBagChangeHandler('invOpen', nil, function(bagName, _, value)
    if bagName ~= ('player:%s'):format(GetPlayerServerId(PlayerId())) then return end
    if value then
        publish({ visible = false })
        ashudRadar.update(false, false)
    end
end)

RegisterCommand('hud', function()
    enabled = not enabled
end, false)

CreateThread(function()
    while true do
        local loaded = ashudPlayer.data.citizenid ~= nil and LocalPlayer.state.isLoggedIn ~= false
        local focused = config.hideOnNuiFocus ~= false and IsNuiFocused()
        local visible = loaded and enabled and not focused and not LocalPlayer.state.invOpen and not LocalPlayer.state.inv_busy and not LocalPlayer.state.characterCreation and not IsPauseMenuActive() and not IsScreenFadedOut() and not IsScreenFadingOut()
        local ped,playerId = PlayerPedId(),PlayerId()
        local vehicle = GetVehiclePedIsIn(ped,false)
        local inVehicle = vehicle ~= false and vehicle ~= nil and vehicle ~= 0
        local radar = ashudRadar.update(visible == true, inVehicle)
        if visible then
            local now = GetGameTimer()
            local coords = GetEntityCoords(ped)
            if now - locationUpdated >= 1000 then
                local primary, crossing = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
                street = GetStreetNameFromHashKey(primary)
                crossStreet = crossing ~= 0 and crossing ~= primary and GetStreetNameFromHashKey(crossing) or ''
                zone = GetLabelText(GetNameOfZone(coords.x, coords.y, coords.z))
                locationUpdated = now
                if zone == 'NULL' then zone = '' end
                ashudRadar.layout()
            end

            local metadata = ashudPlayer.data.metadata or {}
            local proximity = LocalPlayer.state.proximity
            local maxHealth = math.max(1, GetEntityMaxHealth(ped) - 100)
            local fuel = inVehicle and (Entity(vehicle).state.fuel or GetVehicleFuelLevel(vehicle)) or 0
            local underwater = IsPedSwimmingUnderWater(ped)

            publish({
                visible = true,
                health = percent((GetEntityHealth(ped) - 100) / maxHealth * 100),
                armor = percent(GetPedArmour(ped)),
                hunger = tonumber(metadata.hunger) and percent(metadata.hunger) or false,
                thirst = tonumber(metadata.thirst) and percent(metadata.thirst) or false,
                stamina = percent(100 - GetPlayerSprintStaminaRemaining(playerId)),
                oxygen = underwater and percent(GetPlayerUnderwaterTimeRemaining(playerId) / math.max(1, config.oxygenCapacitySeconds) * 100) or 100,
                underwater = underwater,
                talking = NetworkIsPlayerTalking(playerId),
                radio = radioActive,
                voice = type(proximity) == 'table' and tonumber(proximity.distance) or false,
                street = street,
                crossStreet = crossStreet,
                zone = zone,
                radar = radar,
                vehicle = inVehicle,
                speed = inVehicle and math.floor(GetEntitySpeed(vehicle) * (config.speedUnit == 'kmh' and 3.6 or 2.236936) + 0.5) or 0,
                fuel = percent(fuel),
                gear = inVehicle and GetVehicleCurrentGear(vehicle) or 0,
                reversing = inVehicle and GetEntitySpeedVector(vehicle, true).y < -0.1 or false,
                rpm = inVehicle and math.floor(GetVehicleCurrentRpm(vehicle) * 100) or 0,
                engine = inVehicle and GetIsVehicleEngineRunning(vehicle) or false,
            })
            Wait(math.max(100, config.updateInterval))
        else
            publish({ visible = false })
            Wait(100)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    ashudRadar.reset()
    SendNUIMessage({ action = 'hud:update', data = { visible = false } })
end)
