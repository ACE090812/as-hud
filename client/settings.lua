HudPreferences = {}

local currentSettings = { version = 1, options = {}, layout = {} }
local currentProfileId = nil
local kvpKey = nil
local isOpen = false
local isEditing = false
local nuiReady = false
local lastHeartbeat = 0
local cachedDefaults = nil
local lastMoneyPayloadJson = nil

-- [min, max] scale range allowed for each layout-editable HUD component
local layoutScaleRanges = {
  minimap = { 0.75, 1.35 },
  playerStatus = { 0.5, 1.75 },
  stamina = { 0.5, 1.75 },
  speedometer = { 0.5, 1.75 },
  location = { 0.5, 1.75 },
  money = { 0.5, 1.75 },
  vehicleControls = { 0.5, 1.75 }
}

local function getDefaultOptions()
  if not cachedDefaults then
    cachedDefaults = {
      hud = true,
      playerStatus = true,
      stamina = true,
      speedometer = true,
      minimap = true,
      compass = true,
      heading = true,
      location = true,
      money = false,
      waypoint = true,
      vehicleControls = true,
      navBackdrop = Config.NavigationTextBackdrop == true,
      snap = not Config.HudSettings,
      safeArea = 0,
      speedUnit = Config.UseMetricSpeed and "KMH" or "MPH"
    }
  end
  return cachedDefaults
end

local function clampNumber(value, minValue, maxValue)
  if not (type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge) then
    return nil
  end
  return math.max(minValue, math.min(maxValue, value))
end

local function sanitizeSettings(input)
  if type(input) ~= "table" then
    input = {}
  end

  local result = { version = 1, options = {}, layout = {} }
  local opts = type(input.options) == "table" and input.options or {}

  for id, defaultValue in pairs(getDefaultOptions()) do
    if type(defaultValue) == "boolean" then
      result.options[id] = type(opts[id]) == "boolean" and opts[id] or defaultValue
      if opts[id] == false then
        result.options[id] = false
      end
    end
  end

  local speedUnit = opts.speedUnit
  if speedUnit ~= "MPH" and speedUnit ~= "KMH" then
    speedUnit = nil
  end
  result.options.speedUnit = speedUnit or getDefaultOptions().speedUnit

  result.options.safeArea = clampNumber(opts.safeArea, 0, 10) or 0

  if type(input.layout) == "table" then
    for id, range in pairs(layoutScaleRanges) do
      local entry = input.layout[id]
      if type(entry) == "table" then
        local x = clampNumber(entry.x, 0, 1)
        local y = clampNumber(entry.y, 0, 1)
        local scale = clampNumber(entry.scale, range[1], range[2])

        if x and y and scale then
          result.layout[id] = { x = x, y = y, scale = scale }
        end
      end
    end
  end

  return result
end

function HudPreferences.Option(id, fallback)
  local value = currentSettings.options[id]
  if value == nil then
    return fallback
  end
  return value
end

function HudPreferences.IsEditing()
  return isEditing
end

function HudPreferences.IsOpen()
  return isOpen
end

local function syncSpeedUnitToConfig()
  Config.UseMetricSpeed = currentSettings.options.speedUnit == "KMH"
end

local function buildSettingsLoadPayload()
  return {
    ok = true,
    action = "hudSettingsLoad",
    profile = currentProfileId,
    settings = currentSettings,
    defaults = getDefaultOptions()
  }
end

local function closeSettings()
  isEditing = false
  isOpen = false
  SetNuiFocus(false, false)
  SetNuiFocusKeepInput(false)
  SendNUIMessage({ action = "hudSettingsClose" })
end
HudPreferences.Close = closeSettings

local function ensureProfileLoaded()
  local player = Bridge.GetHudPlayer()
  local profileId = player and player.id:sub(1, 128) or nil

  if profileId ~= currentProfileId then
    if isOpen then
      closeSettings()
    end

    currentProfileId = profileId
    kvpKey = currentProfileId and ("as-hud:settings:%s:%s"):format(GetCurrentServerEndpoint() or "local", currentProfileId) or nil

    local raw = kvpKey and GetResourceKvpString(kvpKey)
    local ok, decoded = false, nil

    if raw and #raw <= 16000 then
      ok, decoded = pcall(json.decode, raw)
    end

    currentSettings = sanitizeSettings(ok and decoded or {})
    syncSpeedUnitToConfig()
    TriggerEvent("as-hud:applyMinimapLayout")

    if nuiReady then
      SendNUIMessage(buildSettingsLoadPayload())
    end
  end

  return player
end

local function isReady()
  local player = Bridge.GetHudPlayer()
  return currentProfileId ~= nil and player ~= nil
end

RegisterNUICallback("hudSettingsReady", function(_, cb)
  if isOpen then
    closeSettings()
  end

  nuiReady = true
  lastMoneyPayloadJson = nil
  ensureProfileLoaded()

  cb(buildSettingsLoadPayload())
end)

RegisterNUICallback("hudSaveSettings", function(data, cb)
  if not isReady() then
    cb({ ok = false, error = "Character changed; reopen HUD settings." })
    return
  end

  currentSettings = sanitizeSettings(data.settings)
  syncSpeedUnitToConfig()
  SetResourceKvp(kvpKey, json.encode(currentSettings))

  cb({ ok = true })
end)

RegisterNUICallback("hudPreviewSettings", function(data, cb)
  if not isReady() then
    cb({ ok = false, error = "Character is not ready." })
    return
  end

  currentSettings.options = sanitizeSettings({ options = data.options }).options
  syncSpeedUnitToConfig()

  cb({ ok = true })
end)

HudPreferences.MinimapRect = HudScreen.MinimapRect
HudPreferences.MinimapRadarRect = HudScreen.MinimapRadarRect
HudPreferences.MinimapCircleRect = HudScreen.MinimapCircleRect

RegisterNUICallback("hudEditorMode", function(data, cb)
  isEditing = isOpen and type(data) == "table"
  cb({ ok = true })
end)

RegisterNUICallback("hudCloseSettings", function(_, cb)
  closeSettings()
  cb({ ok = true })
end)

RegisterNUICallback("hudSettingsHeartbeat", function(_, cb)
  lastHeartbeat = GetGameTimer()
  cb({ ok = true })
end)

local function openSettings()
  ensureProfileLoaded()

  if not (nuiReady and currentProfileId and not IsPauseMenuActive()) then
    return
  end

  if isOpen then
    closeSettings()
    return
  end

  if asChat then
    asChat.Close()
  end

  isOpen = true
  lastHeartbeat = GetGameTimer()

  SendNUIMessage(buildSettingsLoadPayload())
  SendNUIMessage({ action = "hudSettingsOpen" })
  SetNuiFocus(true, true)
  SetNuiFocusKeepInput(false)
end

local hudSettingsConfig = Config.HudSettings or {}

RegisterCommand(hudSettingsConfig.command or "hudsettings", openSettings, false)
RegisterKeyMapping(hudSettingsConfig.command or "hudsettings", "HUD settings and layout", "keyboard", hudSettingsConfig.key or "F7")

RegisterNetEvent("as-hud:openSettings", openSettings)
RegisterNetEvent("QBCore:Client:OnPlayerUnload", closeSettings)
RegisterNetEvent("esx:onPlayerLogout", closeSettings)

exports("OpenSettings", openSettings)

AddEventHandler("as-hud:preferencesSpeedUnit", function(useMetric)
  currentSettings.options.speedUnit = useMetric and "KMH" or "MPH"

  if kvpKey then
    SetResourceKvp(kvpKey, json.encode(currentSettings))
  end

  SendNUIMessage({ action = "hudSettingsSpeedUnit", speedUnit = currentSettings.options.speedUnit })
end)

AddEventHandler("onResourceStop", function(resourceName)
  if resourceName == GetCurrentResourceName() then
    closeSettings()
  end
end)

CreateThread(function()
  while true do
    if isOpen then
      DisableAllControlActions(0)
      DisableAllControlActions(1)
      DisableAllControlActions(2)

      if IsPauseMenuActive() or GetGameTimer() - lastHeartbeat > 15000 then
        closeSettings()
      end

      Wait(0)
    else
      Wait(200)
    end
  end
end)

CreateThread(function()
  while true do
    local player = ensureProfileLoaded()

    local payload = {
      action = "hudMoney",
      available = player ~= nil,
      cash = (player and clampNumber(player.cash, 0, 1.0E15)) or 0,
      bank = (player and clampNumber(player.bank, 0, 1.0E15)) or 0
    }

    local encoded = json.encode(payload)

    if nuiReady and encoded ~= lastMoneyPayloadJson then
      lastMoneyPayloadJson = encoded
      SendNUIMessage(payload)
    end

    Wait(1000)
  end
end)