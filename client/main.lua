-- ============================================================
-- State
-- ============================================================

local hudVisible = true
local pausedHidden = false
local navigationVisible = true
local speedometerVisible = true
local seatbeltOn = false
local lastMainHudJson = ""
local lastVehicleHudKey = ""
local lastCompassHeading = -1
local minimapScaleform = nil
local lastVehicleEntity = 0
local engineToggleCooldownUntil = 0
local hornCooldownUntil = 0
local hornWasPressed = false
local lastGear = nil
local lastGearChangeTime = 0
local hunger, thirst = Bridge.GetNeeds()
local stressLevel = 0
local lastStressGainTime = 0
local screenblurActive = false
local fadeActive = false
local devMode = false
local electricVehicleHashes = nil

-- ============================================================
-- Small utilities
-- ============================================================

local function round(value)
  return math.floor(value + 0.5)
end

local function clamp(value, minValue, maxValue)
  value = tonumber(value) or 0
  if minValue > value then
    return minValue
  end
  if maxValue < value then
    return maxValue
  end
  return value
end

local function clampPercent(value)
  return clamp(value, 0, 100)
end

local function getOxygenStatus(ped)
  local remaining = GetPlayerUnderwaterTimeRemaining and GetPlayerUnderwaterTimeRemaining(PlayerId()) or 10.0
  local visible = IsPedSwimmingUnderWater and IsPedSwimmingUnderWater(ped) or remaining < 9.8
  return clampPercent(remaining / 10.0 * 100.0), visible
end

local function setStress(value)
  stressLevel = clampPercent(value)
  SendNUIMessage({ action = "status", stress = stressLevel })
end

local function addStress(amount)
  setStress(stressLevel + (tonumber(amount) or 0))
end

local function removeStress(amount)
  setStress(stressLevel - (tonumber(amount) or 0))
end

local function getElectricVehicleHashes()
  if electricVehicleHashes then
    return electricVehicleHashes
  end

  electricVehicleHashes = {}
  for _, model in ipairs(Config.ElectricVehicles or {}) do
    local hash = joaat and joaat(model) or GetHashKey(model)
    electricVehicleHashes[hash] = true
  end
  return electricVehicleHashes
end

local function isVehicleElectric(vehicle)
  if vehicle == 0 then
    return false
  end
  if GetIsVehicleElectric and GetIsVehicleElectric(vehicle) then
    return true
  end
  return getElectricVehicleHashes()[GetEntityModel(vehicle)] == true
end

local function getVehicleFuelLevel(vehicle)
  if vehicle == 0 then
    return 0.0
  end

  local state = Entity(vehicle).state
  if state and state.fuel ~= nil then
    return clamp(state.fuel, 0, 100)
  end

  return clamp(GetVehicleFuelLevel(vehicle), 0, 100)
end

local function getVehicleGearLabel(vehicle)
  if vehicle == 0 then
    return "N"
  end

  local velocity = GetEntitySpeedVector(vehicle, true)
  if velocity.y < -0.2 then
    return "R"
  end

  local gear = GetVehicleCurrentGear(vehicle)
  if gear <= 0 then
    return "N"
  end

  return tostring(gear)
end

local function getStreetNames(coords)
  local street1, street2 = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
  local name1 = street1 ~= 0 and GetStreetNameFromHashKey(street1) or ""
  local name2 = street2 ~= 0 and GetStreetNameFromHashKey(street2) or ""
  return name1, name2
end

local function getZoneName(coords)
  local label = GetLabelText(GetNameOfZone(coords.x, coords.y, coords.z))
  return label == "NULL" and "" or label
end

local WAYPOINT_BLIP_SPRITE = 8

local function getWaypointInfo(coords)
  if not IsWaypointActive() then
    return false, 0, "mi", 0, false
  end

  local waypointBlip = GetFirstBlipInfoId(WAYPOINT_BLIP_SPRITE)
  if not DoesBlipExist(waypointBlip) then
    return false, 0, "mi", 0, false
  end

  local blipCoords = GetBlipCoords(waypointBlip)
  local dx = coords.x - blipCoords.x
  local dy = coords.y - blipCoords.y
  local distance = math.sqrt(dx * dx + dy * dy)

  local bearing = math.floor(((math.deg(math.atan(-dx, -dy)) + 360.0) % 360.0) * 2 + 0.5) / 2

  local rangeLimit = tonumber(Config.MinimapBlipRange) or 0.0
  local offRadar = Config.ClipWaypointBlip == true and rangeLimit > 0.0 and distance > rangeLimit

  local useMetric = Config.UseMetricSpeed
  if ShouldUseMetricMeasurements then
    useMetric = ShouldUseMetricMeasurements()
  end

  if useMetric then
    return true, round(distance), "m", bearing, offRadar
  end

  local miles = math.floor(distance / 1609.344 * 100 + 0.5) / 100
  return true, miles, "mi", bearing, offRadar
end

-- ============================================================
-- Blip management
-- ============================================================

local HIDDEN_BLIP_DISPLAY = 3
local MAX_BLIP_SPRITE = 900

local function forEachBlip(callback)
  for spriteId = 0, MAX_BLIP_SPRITE, 1 do
    local blip = GetFirstBlipInfoId(spriteId)
    while DoesBlipExist(blip) do
      callback(blip, spriteId)
      blip = GetNextBlipInfoId(spriteId)
    end
  end
end

local cachedBlips = {}
local lastBlipCacheTime = 0

local function getAllBlips()
  if GetGameTimer() - lastBlipCacheTime > 500 then
    lastBlipCacheTime = GetGameTimer()
    cachedBlips = {}
    forEachBlip(function(blip)
      cachedBlips[#cachedBlips + 1] = blip
    end)
  end
  return cachedBlips
end

local function hideNorthBlip()
  if GetNorthRadarBlip then
    local blip = GetNorthRadarBlip()
    if DoesBlipExist(blip) then
      SetBlipAlpha(blip, 0)
      SetBlipDisplay(blip, 0)
    end
  end
end

local function restoreNonWaypointBlipsDisplay()
  forEachBlip(function(blip, spriteId)
    if spriteId ~= WAYPOINT_BLIP_SPRITE then
      if GetBlipInfoIdDisplay(blip) == HIDDEN_BLIP_DISPLAY then
        SetBlipDisplay(blip, 2)
      end
    end
  end)
end

local function hideNonWaypointBlipsFromMinimap()
  forEachBlip(function(blip, spriteId)
    if spriteId ~= WAYPOINT_BLIP_SPRITE then
      SetBlipDisplay(blip, HIDDEN_BLIP_DISPLAY)
    end
  end)
end

local clippedBlipOriginalDisplay = {}

local function updateBlipRangeClipping(coords)
  local rangeLimit = tonumber(Config.MinimapBlipRange) or 0.0
  if rangeLimit <= 0.0 then
    return
  end

  local rangeSq = rangeLimit * rangeLimit

  local function evaluateBlip(blip)
    if not DoesBlipExist(blip) then
      return
    end

    local blipCoords = GetBlipCoords(blip)
    local dx = coords.x - blipCoords.x
    local dy = coords.y - blipCoords.y
    local outOfRange = (dx * dx + dy * dy) > rangeSq

    if outOfRange then
      if not clippedBlipOriginalDisplay[blip] then
        clippedBlipOriginalDisplay[blip] = GetBlipInfoIdDisplay(blip)
        SetBlipDisplay(blip, HIDDEN_BLIP_DISPLAY)
        SetBlipAlpha(blip, 0)
      end
    else
      if clippedBlipOriginalDisplay[blip] then
        SetBlipDisplay(blip, clippedBlipOriginalDisplay[blip])
        clippedBlipOriginalDisplay[blip] = nil
        SetBlipAlpha(blip, 255)
      end
    end
  end

  if Config.HideMinimapBlips then
    if Config.ClipWaypointBlip then
      evaluateBlip(GetFirstBlipInfoId(WAYPOINT_BLIP_SPRITE))
    end
    return
  end

  local northBlip = GetNorthRadarBlip and GetNorthRadarBlip() or 0
  local waypointBlip = (not Config.ClipWaypointBlip) and GetFirstBlipInfoId(WAYPOINT_BLIP_SPRITE) or 0

  for _, blip in ipairs(getAllBlips()) do
    if blip ~= northBlip and blip ~= waypointBlip then
      evaluateBlip(blip)
    end
  end
end

local function cleanupClippedBlips()
  for blip in pairs(clippedBlipOriginalDisplay) do
    if not DoesBlipExist(blip) then
      clippedBlipOriginalDisplay[blip] = nil
    end
  end
end

local function restoreAllClippedBlips()
  for blip, originalDisplay in pairs(clippedBlipOriginalDisplay) do
    if DoesBlipExist(blip) then
      SetBlipDisplay(blip, originalDisplay)
      SetBlipAlpha(blip, 255)
    end
    clippedBlipOriginalDisplay[blip] = nil
  end
end

-- ============================================================
-- Visibility helpers
-- ============================================================

local function isHudVisible()
  if not HudPreferences.IsEditing() then
    if not hudVisible then
      return false
    end
    if not HudPreferences.Option("hud", true) then
      return false
    end
  end
  return not pausedHidden
end

local function isPauseMenuActive()
  if IsPauseMenuActive() then
    return true
  end
  if type(GetPauseMenuState) == "function" then
    return GetPauseMenuState() ~= 0
  end
  return false
end

-- When another resource owns the minimap (a 3D/web map like as-map),
-- as-hud must not touch the native minimap at all: no mask texture, no
-- clip type, no position locking, no DisplayRadar calls, no native blip
-- hiding. Everything else (compass, waypoint info, HUD sections) is drawn by
-- as-hud's own NUI and keeps working regardless.
local function isExternalMinimap()
  local mode = Config.ExternalMinimap
  if mode == true then
    return true
  end
  if mode ~= "auto" then
    return false
  end
  local state = GetResourceState(Config.ExternalMinimapResource or "as-map")
  return state ~= "missing" and state ~= "unknown"
end

local function setNativeRadarVisible(visible)
  if isExternalMinimap() then
    return
  end
  DisplayRadar(visible)
end

local function clearScreenEffects(instant)
  if screenblurActive then
    TriggerScreenblurFadeOut(instant and 0 or 1000.0)
    screenblurActive = false
  end
  if fadeActive then
    DoScreenFadeIn(instant and 0 or 200)
    fadeActive = false
  end
end

local function setHudVisible(visible)
  asChat.SetVisible(visible == true)
  hudVisible = visible == true
  SendNUIMessage({ action = "visible", visible = isHudVisible() })
end

-- Sections (navigation/minimap) are shown when globally enabled and either
-- the HUD editor is open or the player has left them visible.
local function isNavigationEnabled()
  return Config.ShowNavigation ~= false and (HudPreferences.IsEditing() or navigationVisible)
end

local function isMinimapVisible()
  if not isNavigationEnabled() then
    return false
  end
  if not HudPreferences.IsEditing() then
    return HudPreferences.Option("minimap", true)
  end
  return true
end

local function setPausedState(paused)
  pausedHidden = paused == true
  if not pausedHidden then
    HudScreen.Refresh(true)
  end

  lastMainHudJson = ""
  lastCompassHeading = -1

  SendNUIMessage({ action = "visible", visible = isHudVisible() })
  setNativeRadarVisible(isHudVisible() and isMinimapVisible())
end

local function sendSectionsUpdate()
  SendNUIMessage({ action = "sections", navigation = isNavigationEnabled(), speedometer = speedometerVisible })
end

local function setNavigationVisible(visible)
  navigationVisible = visible == true
  lastCompassHeading = -1
  sendSectionsUpdate()
  setNativeRadarVisible(isHudVisible() and isMinimapVisible())
end

local function setSpeedometerVisible(visible)
  speedometerVisible = visible == true
  lastVehicleHudKey = ""
  sendSectionsUpdate()
end

local function setUseMetricSpeed(useMetric)
  Config.UseMetricSpeed = useMetric == true
  SetResourceKvp("as-hud:useMetricSpeed", Config.UseMetricSpeed and "true" or "false")
  TriggerEvent("as-hud:preferencesSpeedUnit", Config.UseMetricSpeed)
end

local function loadUseMetricSpeedPreference()
  local saved = GetResourceKvpString("as-hud:useMetricSpeed")
  if saved == "true" then
    Config.UseMetricSpeed = true
  elseif saved == "false" then
    Config.UseMetricSpeed = false
  end
end
loadUseMetricSpeedPreference()

-- ============================================================
-- External minimap frame reporting (e.g. as-map)
-- ============================================================
-- When another resource draws the minimap, it still needs to know where
-- as-hud's own minimap hole is (so its map lines up with the ring/frame
-- art) and whether that hole is currently visible. as-map's own "as-hud"
-- adapter reads this through the GetRadarLayout/IsRadarVisible exports below
-- and the as-hud:radarLayout/as-hud:radarVisible events.

local lastRadarLayout = nil
local lastRadarVisible = nil

local function computeRadarLayout()
  local screen = HudScreen.Get()
  if not screen then
    return nil
  end

  local scale = Config.RadarMaskScale or 1.0
  local offsetX = Config.RadarMaskOffsetX or 0.0
  local offsetY = Config.RadarMaskOffsetY or 0.0

  local rx, ry, rw, rh = HudPreferences.MinimapRadarRect(scale, offsetX, offsetY)
  local transform = screen.transform

  return {
    left = transform.x + rx * transform.sx,
    top = transform.y + ry * transform.sy,
    width = rw * transform.sx,
    height = rh * transform.sy
  }
end

local function layoutsEqual(a, b)
  if not a or not b then
    return a == b
  end
  return a.left == b.left and a.top == b.top and a.width == b.width and a.height == b.height
end

exports("GetRadarLayout", function()
  return lastRadarLayout
end)

exports("IsRadarVisible", function()
  return lastRadarVisible == true
end)

CreateThread(function()
  while true do
    if isExternalMinimap() then
      local visible = isHudVisible() and isMinimapVisible()

      if visible ~= lastRadarVisible then
        lastRadarVisible = visible
        TriggerEvent("as-hud:radarVisible", visible)
      end

      if visible then
        local layout = computeRadarLayout()
        if layout and not layoutsEqual(layout, lastRadarLayout) then
          lastRadarLayout = layout
          TriggerEvent("as-hud:radarLayout", layout)
        end
      end

      Wait(250)
    else
      Wait(1000)
    end
  end
end)

-- ============================================================
-- Animations
-- ============================================================

local function ensureAnimDictLoaded(dict)
  if not dict or dict == "" then
    return false
  end

  RequestAnimDict(dict)
  local deadline = GetGameTimer() + 1000

  while not HasAnimDictLoaded(dict) do
    if GetGameTimer() > deadline then
      return false
    end
    Wait(0)
  end

  return true
end

local function playVehicleAnim(opts)
  if not opts then
    return
  end

  CreateThread(function()
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then
      return
    end

    local dict = opts.dict
    if not ensureAnimDictLoaded(dict) then
      return
    end

    local names = opts.names or { opts.name }
    local blendIn = opts.blendIn or 8.0
    local blendOut = opts.blendOut or -8.0
    local duration = opts.duration or 850
    local flag = opts.flag or 48

    for _, name in ipairs(names) do
      if name and name ~= "" then
        TaskPlayAnim(ped, dict, name, blendIn, blendOut, duration, flag, 0.0, false, false, false)
        Wait(60)

        if IsEntityPlayingAnim(ped, dict, name, 3) then
          SetTimeout(duration, function()
            if DoesEntityExist(ped) then
              StopAnimTask(ped, dict, name, 1.0)
            end
          end)
          return
        end
      end
    end
  end)
end

local function playSeatbeltFeedback(buckled)
  local cfg = Config.SeatbeltFeedback or {}

  if cfg.sound ~= false then
    local soundCfg = (buckled and cfg.buckleSound or cfg.unbuckleSound) or {}
    PlaySoundFrontend(-1, soundCfg.name or "SELECT", soundCfg.set or "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
  end

  if cfg.animation ~= false then
    local animCfg = buckled and cfg.buckle or cfg.unbuckle
    if animCfg then
      playVehicleAnim({
        dict = animCfg.dict,
        names = animCfg.names,
        name = animCfg.name,
        blendIn = animCfg.blendIn or cfg.blendIn or 8.0,
        blendOut = animCfg.blendOut or cfg.blendOut or -8.0,
        duration = animCfg.duration or cfg.duration or 850,
        flag = animCfg.flag or cfg.flag or 48
      })
    end
  end
end

local function toggleSeatbelt()
  if not IsPedInAnyVehicle(PlayerPedId(), false) then
    return
  end

  seatbeltOn = not seatbeltOn
  playSeatbeltFeedback(seatbeltOn)
  SendNUIMessage({ action = "status", seatbelt = seatbeltOn })
end

local function setVehicleEngine(vehicle, wantOn)
  if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= PlayerPedId() then
    return
  end

  SetVehicleEngineOn(vehicle, wantOn, true, not wantOn)
  SendNUIMessage({ action = "status", engine = wantOn })
end

-- ============================================================
-- Circular minimap
-- ============================================================

local RADAR_MASK_TXD_FALLBACK = "circlemap"
local RADAR_MASK_IMAGE = "assets/radar-mask.png"
local RADAR_MASK_TEXTURE_NAME = "round_mask"
local MINIMAP_LOAD_TIMEOUT = 5000

local circleMinimapReady = false
local circleMinimapLoading = false
local customRadarTxd = nil
local minimapLocked = false

local defaultMinimapComponents = {
  { name = "minimap", alignX = "L", alignY = "B", x = 0.0, y = -0.047, width = 0.14, height = 0.188 },
  { name = "minimap_mask", alignX = "L", alignY = "B", x = 0.0, y = 0.0, width = 0.125, height = 0.19 },
  { name = "minimap_blur", alignX = "L", alignY = "B", x = -0.008, y = -0.008, width = 0.162, height = 0.234 }
}

local function resetMinimapComponents()
  SetMinimapClipType(0)
  for _, component in ipairs(defaultMinimapComponents) do
    SetMinimapComponentPosition(component.name, component.alignX, component.alignY, component.x, component.y, component.width, component.height)
  end
end

local function unlockMinimapIfNeeded()
  if not minimapLocked then
    return
  end
  UnlockMinimapAngle()
  UnlockMinimapPosition()
  minimapLocked = false
end

local function ensureRadarMaskTexture()
  if not customRadarTxd then
    if CreateRuntimeTxd and CreateRuntimeTextureFromImage then
      local txdName = GetCurrentResourceName() .. "_radar"
      local txd = CreateRuntimeTxd(txdName)
      local texture = txd and CreateRuntimeTextureFromImage(txd, RADAR_MASK_TEXTURE_NAME, RADAR_MASK_IMAGE)

      if texture and texture ~= 0 then
        customRadarTxd = txdName
      end
    end
  end

  if customRadarTxd then
    AddReplaceTexture("platform:/textures/graphics", "radarmasksm", customRadarTxd, RADAR_MASK_TEXTURE_NAME)
    AddReplaceTexture("platform:/textures/graphics", "radarmask1g", customRadarTxd, RADAR_MASK_TEXTURE_NAME)
    return true
  end

  RequestStreamedTextureDict(RADAR_MASK_TXD_FALLBACK, false)
  if HasStreamedTextureDictLoaded(RADAR_MASK_TXD_FALLBACK) then
    AddReplaceTexture("platform:/textures/graphics", "radarmasksm", RADAR_MASK_TXD_FALLBACK, "radarmasksm")
    AddReplaceTexture("platform:/textures/graphics", "radarmask1g", RADAR_MASK_TXD_FALLBACK, "radarmasksm")
    return true
  end

  return false
end

local function applyCircularMinimapLayout()
  SetMinimapClipType(1)

  local scale = Config.RadarMaskScale or 1.0
  local offsetX = Config.RadarMaskOffsetX or 0.0
  local offsetY = Config.RadarMaskOffsetY or 0.0

  local rx, ry, rw, rh = HudPreferences.MinimapRadarRect(scale, offsetX, offsetY)

  if Config.RadarClipRoute ~= false then
    local cx, cy, cw, ch = HudPreferences.MinimapCircleRect(scale, offsetX, offsetY)
    SetMinimapComponentPosition("minimap", "L", "T", cx, cy, cw, ch)
  else
    SetMinimapComponentPosition("minimap", "L", "T", rx, ry, rw, rh)
  end

  SetMinimapComponentPosition("minimap_mask", "L", "T", rx, ry, rw, rh)
  SetMinimapComponentPosition("minimap_blur", "L", "T", rx, ry, rw, rh)
end

local minimapRefreshRequestId = 0
local minimapRefreshBusy = false
local screenChangedRequestId = 0

local function refreshMinimapDisplay()
  if minimapRefreshBusy or IsPauseMenuActive() then
    return
  end

  minimapRefreshBusy = true

  applyCircularMinimapLayout()
  setNativeRadarVisible(false)
  SetRadarBigmapEnabled(true, false)
  Wait(50)
  SetRadarBigmapEnabled(false, false)
  applyCircularMinimapLayout()
  setNativeRadarVisible(isHudVisible() and isMinimapVisible())

  minimapRefreshBusy = false
end

AddEventHandler("as-hud:screenChanged", function()
  if isExternalMinimap() then
    return
  end

  screenChangedRequestId = screenChangedRequestId + 1
  local requestId = screenChangedRequestId

  CreateThread(function()
    while requestId == screenChangedRequestId do
      if not IsPauseMenuActive() or circleMinimapReady then
        break
      end
      Wait(100)
    end

    if requestId ~= screenChangedRequestId then
      return
    end

    Wait(350)

    for step = 1, 6, 1 do
      if requestId == screenChangedRequestId then
        if not IsPauseMenuActive() then
          return
        end
      else
        return
      end

      if ensureRadarMaskTexture() then
        applyCircularMinimapLayout()
        if step == 1 or step == 6 then
          refreshMinimapDisplay()
        end
      end

      Wait(350)
    end
  end)
end)

AddEventHandler("as-hud:applyMinimapLayout", function()
  if not circleMinimapReady then
    return
  end

  applyCircularMinimapLayout()

  minimapRefreshRequestId = minimapRefreshRequestId + 1
  local requestId = minimapRefreshRequestId

  CreateThread(function()
    Wait(250)

    while requestId == minimapRefreshRequestId do
      if not IsPauseMenuActive() then
        break
      end
      Wait(100)
    end

    if requestId == minimapRefreshRequestId and circleMinimapReady then
      refreshMinimapDisplay()
    end
  end)
end)

local function initCircularMinimap()
  if isExternalMinimap() or circleMinimapReady or circleMinimapLoading then
    return
  end

  circleMinimapLoading = true

  local deadline = GetGameTimer() + MINIMAP_LOAD_TIMEOUT
  while not ensureRadarMaskTexture() do
    if GetGameTimer() > deadline then
      print(("[as-hud] Timed out loading \"%s\" and the \"%s\" texture dict; keeping the default square minimap."):format(RADAR_MASK_IMAGE, RADAR_MASK_TXD_FALLBACK))
      circleMinimapLoading = false
      return
    end
    Wait(50)
  end

  applyCircularMinimapLayout()
  setNativeRadarVisible(false)
  SetRadarBigmapEnabled(true, false)
  Wait(50)
  SetRadarBigmapEnabled(false, false)
  SetMinimapClipType(1)
  setNativeRadarVisible(isHudVisible() and isMinimapVisible())

  minimapScaleform = RequestScaleformMovie("minimap")

  local scaleformDeadline = GetGameTimer() + MINIMAP_LOAD_TIMEOUT
  while not HasScaleformMovieLoaded(minimapScaleform) do
    if GetGameTimer() > scaleformDeadline then
      print("[as-hud] Timed out loading the minimap scaleform; stock health/armour pips may still show on the map.")
      minimapScaleform = nil
      circleMinimapLoading = false
      return
    end
    Wait(0)
  end

  circleMinimapLoading = false
  circleMinimapReady = true
end

AddEventHandler("onResourceStop", function(resourceName)
  if resourceName ~= GetCurrentResourceName() then
    return
  end

  clearScreenEffects(true)

  if not isExternalMinimap() then
    restoreAllClippedBlips()
    RemoveReplaceTexture("platform:/textures/graphics", "radarmasksm")
    RemoveReplaceTexture("platform:/textures/graphics", "radarmask1g")
    unlockMinimapIfNeeded()

    if minimapScaleform then
      SetScaleformMovieAsNoLongerNeeded(minimapScaleform)
      minimapScaleform = nil
    end

    if circleMinimapReady then
      resetMinimapComponents()
    end
  end
end)

CreateThread(function()
  if isExternalMinimap() then
    return
  end

  local tick = 0

  if not Config.HideMinimapBlips then
    Wait(2000)
    pcall(restoreNonWaypointBlipsDisplay)
  end

  while true do
    Wait(100)
    tick = tick + 1

    if tick % 5 == 0 then
      pcall(hideNorthBlip)
      if Config.HideMinimapBlips then
        pcall(hideNonWaypointBlipsFromMinimap)
      end
    end

    cleanupClippedBlips()

    if isHudVisible() and isNavigationEnabled() then
      pcall(updateBlipRangeClipping, GetEntityCoords(PlayerPedId()))
    elseif next(clippedBlipOriginalDisplay) then
      restoreAllClippedBlips()
    end
  end
end)

local function getWaypointBlipSignature()
  if not IsWaypointActive() then
    return "off"
  end

  local blip = GetFirstBlipInfoId(WAYPOINT_BLIP_SPRITE)
  if not DoesBlipExist(blip) then
    return "missing"
  end

  local coords = GetBlipCoords(blip)
  return ("on:%d:%d"):format(math.floor(coords.x + 0.5), math.floor(coords.y + 0.5))
end

CreateThread(function()
  if isExternalMinimap() then
    return
  end

  local lastSignature = "off"
  local lastRefreshTime = 0

  while true do
    Wait(100)

    if circleMinimapReady then
      local signature = getWaypointBlipSignature()

      if signature ~= lastSignature then
        lastSignature = signature
        Wait(150)

        if circleMinimapReady then
          refreshMinimapDisplay()
          for _ = 1, 12, 1 do
            applyCircularMinimapLayout()
            Wait(50)
          end
        end
      elseif signature ~= "off" and signature ~= "missing" then
        if GetGameTimer() - lastRefreshTime > 250 then
          lastRefreshTime = GetGameTimer()
          applyCircularMinimapLayout()
          SetMinimapClipType(1)
        end
      end
    end
  end
end)

CreateThread(function()
  if isExternalMinimap() then
    return
  end

  local nextLockRefresh = 0

  while true do
    Wait(0)

    if circleMinimapReady and isHudVisible() and isMinimapVisible() and not isPauseMenuActive() and Config.RadarLockToPlayer ~= false then
      local ped = PlayerPedId()
      local coords = GetEntityCoords(ped)
      local now = GetGameTimer()

      if nextLockRefresh <= now then
        applyCircularMinimapLayout()
        SetMinimapClipType(1)
        nextLockRefresh = now + 500
      end

      SetRadarAsExteriorThisFrame()

      if Config.RadarZoomDistance then
        SetRadarZoomToDistance(Config.RadarZoomDistance)
      end

      LockMinimapPosition(coords.x, coords.y)
      LockMinimapAngle(math.floor(GetGameplayCamRot(2).z + 0.5) % 360)
      minimapLocked = true
    else
      nextLockRefresh = 0
      unlockMinimapIfNeeded()
    end
  end
end)

CreateThread(function()
  while true do
    Wait(0)
    setPausedState(isPauseMenuActive())
  end
end)

local function waitForPlayerReady()
  while not NetworkIsPlayerActive(PlayerId()) do
    Wait(100)
  end
  while GetIsLoadingScreenActive() do
    Wait(100)
  end
  while not IsScreenFadedIn() do
    Wait(100)
  end
  while not DoesEntityExist(PlayerPedId()) do
    Wait(100)
  end
  Wait(1500)
end

local function settleCircularMinimap()
  if not circleMinimapReady then
    return
  end

  for _ = 1, 30, 1 do
    applyCircularMinimapLayout()
    Wait(100)
  end

  refreshMinimapDisplay()
end

CreateThread(function()
  if isExternalMinimap() then
    return
  end

  waitForPlayerReady()

  while not circleMinimapReady do
    initCircularMinimap()
    if not circleMinimapReady then
      Wait(1000)
    end
  end

  settleCircularMinimap()
end)

local function delayedMinimapResettle()
  if isExternalMinimap() then
    return
  end

  CreateThread(function()
    Wait(1500)
    settleCircularMinimap()
  end)
end

AddEventHandler("playerSpawned", delayedMinimapResettle)
RegisterNetEvent("QBCore:Client:OnPlayerLoaded", delayedMinimapResettle)

-- ============================================================
-- Main HUD status update
-- ============================================================

CreateThread(function()
  while true do
    Wait(Config.UpdateInterval)

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)

    local healthRange = math.max(1, GetEntityMaxHealth(ped) - 100)
    local health = clamp((GetEntityHealth(ped) - 100) / healthRange * 100, 0, 100)

    local maxArmour = GetPlayerMaxArmour and GetPlayerMaxArmour(PlayerId()) or 100
    local armor = clamp(GetPedArmour(ped) / math.max(1, maxArmour) * 100, 0, 100)

    local oxygen, oxygenVisible = getOxygenStatus(ped)

    local vehicle = IsPedInAnyVehicle(ped, false) and GetVehiclePedIsIn(ped, false) or 0
    if vehicle ~= lastVehicleEntity then
      lastVehicleEntity = vehicle
      seatbeltOn = false
      lastGear = nil
      lastGearChangeTime = 0
      SendNUIMessage({ action = "status", seatbelt = false })
    end

    local fuel, electric, lights, locked, engineOn = 0.0, false, 0, false, false

    if vehicle ~= 0 then
      fuel = getVehicleFuelLevel(vehicle)
      electric = isVehicleElectric(vehicle)

      local _, highBeams, lightsOn = GetVehicleLightsState(vehicle)
      if highBeams == 1 then
        lights = 2
      elseif lightsOn == 1 then
        lights = 1
      else
        lights = 0
      end

      locked = GetVehicleDoorLockStatus(vehicle) > 1
      engineOn = GetIsVehicleEngineRunning(vehicle)
    end

    local talking = asChat.IsTalking()
    local stamina = clamp(100 - math.floor(GetPlayerSprintStaminaRemaining(PlayerId())), 0, 100)

    local street, crossing = getStreetNames(coords)
    local zone = getZoneName(coords)
    local waypointActive, waypointDistance, waypointUnit, waypointBearing, waypointOffRadar = getWaypointInfo(coords)

    local payload = {
      action = "update",
      visible = isHudVisible(),
      navigation = isNavigationEnabled(),
      speedometer = speedometerVisible,
      navBackdrop = HudPreferences.Option("navBackdrop", Config.NavigationTextBackdrop == true),
      controlsTimeout = Config.VehicleControlsTimeout or 0,
      health = health,
      armor = armor,
      hunger = clampPercent(hunger),
      thirst = clampPercent(thirst),
      stamina = stamina,
      oxygen = oxygen,
      oxygenVisible = oxygenVisible,
      talking = talking,
      inVehicle = vehicle,
      seatbelt = seatbeltOn,
      stress = stressLevel,
      dev = devMode,
      fuel = fuel,
      electric = electric,
      fuelType = electric and "electric" or "gasoline",
      speedUnit = Config.UseMetricSpeed and "KMH" or "MPH",
      lights = lights,
      locked = locked,
      engine = engineOn,
      zone = zone,
      street = street,
      crossing = crossing,
      waypoint = waypointActive,
      waypointDistance = waypointDistance,
      waypointUnit = waypointUnit,
      waypointBearing = waypointBearing,
      waypointOffRadar = waypointOffRadar
    }

    local encoded = json.encode(payload)
    if encoded ~= lastMainHudJson then
      SendNUIMessage(json.decode(encoded))
      lastMainHudJson = encoded
    end

    setNativeRadarVisible(isHudVisible() and isMinimapVisible())
  end
end)

CreateThread(function()
  while true do
    Wait(250)

    local elapsedSinceGain = GetGameTimer() - lastStressGainTime
    local cooldown = Config.StressGainCooldown or 5000

    if elapsedSinceGain >= cooldown then
      local ped = PlayerPedId()

      if IsPedShooting(ped) then
        addStress(Config.StressGainShooting or 2)
        lastStressGainTime = GetGameTimer()
      else
        local vehicle = GetVehiclePedIsIn(ped, false)
        if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
          local speedKmh = GetEntitySpeed(vehicle) * 3.6
          local threshold = Config.StressSpeedThresholdKmh or 140.0

          if speedKmh >= threshold then
            addStress(Config.StressGainDriving or 1)
            lastStressGainTime = GetGameTimer()
          end
        end
      end
    end
  end
end)

-- ============================================================
-- Stress visual effects
-- ============================================================

local function pickThresholdEntry(buckets, value)
  if type(buckets) ~= "table" then
    return nil
  end

  for _, bucket in ipairs(buckets) do
    if value >= (bucket.min or 0) and value <= (bucket.max or 100) then
      return bucket
    end
  end

  return nil
end

local function resolveBlurIntensity(effectsConfig)
  local bucket = pickThresholdEntry(effectsConfig.blurIntensity, stressLevel)
  return tonumber(bucket and bucket.intensity) or 1500
end

local function resolveEffectInterval(effectsConfig)
  local bucket = pickThresholdEntry(effectsConfig.effectInterval, stressLevel)
  if not bucket then
    return 60000
  end

  local minTimeout = tonumber(bucket.timeoutMin) or 60000
  local maxTimeout = tonumber(bucket.timeoutMax) or minTimeout

  if minTimeout >= maxTimeout then
    return minTimeout
  end

  return math.random(minTimeout, maxTimeout)
end

local function canRunStressEffects()
  local cfg = Config.StressEffects or {}
  if cfg.enabled == false then
    return false
  end
  if not isHudVisible() then
    return false
  end
  if isPauseMenuActive() or IsNuiFocused() then
    return false
  end
  return not IsEntityDead(PlayerPedId())
end

local function blurPulse(durationMs)
  TriggerScreenblurFadeIn(1000.0)
  screenblurActive = true
  Wait(durationMs)
  TriggerScreenblurFadeOut(1000.0)
  screenblurActive = false
end

local function runStressShakeEffect(effectsConfig)
  if stressLevel < 100 then
    blurPulse(resolveBlurIntensity(effectsConfig))
    return
  end

  local intensity = resolveBlurIntensity(effectsConfig)
  local cycles = math.random(2, 4)
  local fadeOutMs = tonumber(effectsConfig.fadeOutMs) or 200
  local fadeInMs = tonumber(effectsConfig.fadeInMs) or 200

  blurPulse(intensity)

  local ped = PlayerPedId()
  if effectsConfig.ragdoll ~= false then
    if not IsPedRagdoll(ped) and IsPedOnFoot(ped) and not IsPedSwimming(ped) then
      local forward = GetEntityForwardVector(ped)
      SetPedToRagdollWithFall(ped, cycles * 1750, cycles * 1750, 1, forward.x, forward.y, forward.z, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
    end
  end

  Wait(1000)

  for _ = 1, cycles, 1 do
    if not canRunStressEffects() or stressLevel < 100 then
      return
    end

    Wait(750)
    DoScreenFadeOut(fadeOutMs)
    fadeActive = true
    Wait(1000)
    DoScreenFadeIn(fadeInMs)
    fadeActive = false

    blurPulse(intensity)
  end
end

CreateThread(function()
  while true do
    local effectsConfig = Config.StressEffects or {}
    local minForShaking = tonumber(effectsConfig.minForShaking) or 50

    if canRunStressEffects() and stressLevel >= minForShaking then
      runStressShakeEffect(effectsConfig)
      Wait(resolveEffectInterval(effectsConfig))
    else
      Wait(1000)
    end
  end
end)

CreateThread(function()
  local wasDead = false

  while true do
    Wait(250)

    local isDead = IsEntityDead(PlayerPedId())
    if isDead and not wasDead then
      clearScreenEffects(true)
    end

    wasDead = isDead
  end
end)

-- ============================================================
-- Compass
-- ============================================================

CreateThread(function()
  while true do
    Wait(0)

    if isHudVisible() and isNavigationEnabled() then
      local camHeading = GetGameplayCamRot(2).z
      local normalized = ((camHeading % 360.0) + 360.0) % 360.0
      local heading = (360.0 - normalized) % 360.0
      heading = math.floor(heading * 4 + 0.5) / 4
      if heading >= 360.0 then
        heading = 0.0
      end

      local changed = lastCompassHeading < 0
        or math.abs(((heading - lastCompassHeading + 540.0) % 360.0) - 180.0) >= 0.25

      if changed then
        SendNUIMessage({ action = "compass", heading = heading })
        lastCompassHeading = heading
      end
    else
      lastCompassHeading = -1
    end
  end
end)

-- ============================================================
-- Vehicle dashboard
-- ============================================================

CreateThread(function()
  while true do
    Wait(0)

    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if isHudVisible() and vehicle ~= 0 then
      local rpm = math.floor(math.max(0.0, math.min(1.0, GetVehicleCurrentRpm(vehicle))) * 1000 + 0.5) / 1000

      local speedMultiplier = Config.UseMetricSpeed and 3.6 or 2.236936
      local speed = math.floor(GetEntitySpeed(vehicle) * speedMultiplier * 10 + 0.5) / 10

      local gear = getVehicleGearLabel(vehicle)
      local electric = isVehicleElectric(vehicle)

      local gearAnimCfg = Config.GearChangeAnimation or {}
      if gearAnimCfg.enabled ~= false then
        if GetPedInVehicleSeat(vehicle, -1) == ped then
          if lastGear and lastGear ~= gear then
            local now = GetGameTimer()
            local minSpeed = gearAnimCfg.minSpeed or 1.0

            if minSpeed <= GetEntitySpeed(vehicle) then
              if now - lastGearChangeTime >= (gearAnimCfg.cooldown or 450) then
                playVehicleAnim({
                  dict = gearAnimCfg.dict,
                  names = gearAnimCfg.names,
                  name = gearAnimCfg.name,
                  blendIn = gearAnimCfg.blendIn or 8.0,
                  blendOut = gearAnimCfg.blendOut or -8.0,
                  duration = gearAnimCfg.duration or 650,
                  flag = gearAnimCfg.flag or 48
                })
                lastGearChangeTime = now
              end
            end
          end

          lastGear = gear
        end
      end

      local key = ("%.3f|%.1f|%s|%s"):format(rpm, speed, gear, electric and "1" or "0")

      if key ~= lastVehicleHudKey then
        SendNUIMessage({
          action = "vehicle",
          inVehicle = true,
          rpm = rpm,
          speed = speed,
          gear = gear,
          electric = electric,
          fuelType = electric and "electric" or "gasoline",
          speedUnit = Config.UseMetricSpeed and "KMH" or "MPH"
        })
        lastVehicleHudKey = key
      end
    elseif lastVehicleHudKey ~= "" then
      SendNUIMessage({
        action = "vehicle",
        inVehicle = false,
        rpm = 0.0,
        speed = 0,
        gear = "N",
        electric = false,
        fuelType = "gasoline",
        speedUnit = Config.UseMetricSpeed and "KMH" or "MPH"
      })
      lastVehicleHudKey = ""
      lastGear = nil
    end
  end
end)

-- ============================================================
-- Engine toggle / horn feedback
-- ============================================================

CreateThread(function()
  while true do
    local waitTime = 250

    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if not HudPreferences.IsOpen() and isHudVisible() and vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
      waitTime = 0

      if IsControlJustReleased(0, 14) then
        local now = GetGameTimer()
        if now > engineToggleCooldownUntil then
          setVehicleEngine(vehicle, not GetIsVehicleEngineRunning(vehicle))
          engineToggleCooldownUntil = now + 450
        end
      end

      local hornCfg = Config.HornAnimation or {}
      local hornPressed
      if IsHornActive then
        hornPressed = IsHornActive(vehicle)
      else
        hornPressed = IsControlPressed(0, 86) or IsDisabledControlPressed(0, 86)
      end

      if hornCfg.enabled ~= false and hornPressed then
        if not hornWasPressed then
          local now = GetGameTimer()
          if now > hornCooldownUntil then
            playVehicleAnim({
              dict = hornCfg.dict,
              names = hornCfg.names,
              name = hornCfg.name,
              blendIn = hornCfg.blendIn or 8.0,
              blendOut = hornCfg.blendOut or -8.0,
              duration = hornCfg.duration or 1000,
              flag = hornCfg.flag or 49
            })
            hornCooldownUntil = now + (hornCfg.cooldown or 900)
          end
        end
      end

      hornWasPressed = hornPressed
    else
      hornWasPressed = false
    end

    Wait(waitTime)
  end
end)

-- ============================================================
-- Native HUD component tweaks
-- ============================================================

CreateThread(function()
  while true do
    Wait(0)

    if minimapScaleform then
      BeginScaleformMovieMethod(minimapScaleform, "SETUP_HEALTH_ARMOUR")
      ScaleformMovieMethodAddParamInt(3)
      EndScaleformMovieMethod()
    end
  end
end)

CreateThread(function()
  while true do
    Wait(0)

    if Config.HideDefaultHud then
      HideHudComponentThisFrame(6)
      HideHudComponentThisFrame(7)
      HideHudComponentThisFrame(8)
      HideHudComponentThisFrame(9)
    end

    if isHudVisible() and Config.ShowDefaultAmmo then
      DisplayHud(true)
      DisplayAmmoThisFrame(true)
      ShowHudComponentThisFrame(2)
      ShowHudComponentThisFrame(20)
      ShowHudComponentThisFrame(22)
    end
  end
end)

-- ============================================================
-- Commands / events / exports
-- ============================================================

RegisterCommand("seatbelt", function()
  toggleSeatbelt()
end, false)
RegisterKeyMapping("seatbelt", "Toggle seatbelt", "keyboard", "B")

local function onNeedsUpdate(newHunger, newThirst)
  if newHunger ~= nil then
    hunger = clampPercent(newHunger)
  end
  if newThirst ~= nil then
    thirst = clampPercent(newThirst)
  end
end

RegisterNetEvent("hud:client:UpdateNeeds", onNeedsUpdate)
Bridge.OnNeedsUpdate(onNeedsUpdate)

RegisterCommand("ashud", function()
  hudVisible = not hudVisible
  setHudVisible(hudVisible)
end, false)

RegisterCommand("dev", function()
  devMode = not devMode
  SendNUIMessage({ action = "status", dev = devMode })
end, false)

RegisterCommand("speedunit", function(_, args)
  local option = args[1] and string.lower(args[1])

  if option == "kmh" then
    setUseMetricSpeed(true)
  elseif option == "mph" then
    setUseMetricSpeed(false)
  else
    setUseMetricSpeed(not Config.UseMetricSpeed)
  end
end, false)
RegisterKeyMapping("speedunit", "Toggle speed unit (MPH/KMH)", "keyboard", "")

RegisterNetEvent("as-hud:setVisible", function(visible)
  setHudVisible(visible)
end)

RegisterNetEvent("as-hud:setNavigationVisible", function(visible)
  setNavigationVisible(visible)
end)

RegisterNetEvent("as-hud:setSpeedometerVisible", function(visible)
  setSpeedometerVisible(visible)
end)

RegisterNetEvent("as-hud:updateStatus", function(data)
  if data.stress ~= nil then
    setStress(data.stress)
  end
  data.action = "status"
  SendNUIMessage(data)
end)

RegisterNetEvent("as-hud:setStress", function(value)
  setStress(value)
end)

RegisterNetEvent("as-hud:addStress", function(amount)
  addStress(amount)
end)

if Config.ClearStressOnRevive ~= false then
  local registeredReviveEvents = {}

  for _, eventName in ipairs(Config.ReviveEvents or {}) do
    if type(eventName) == "string" and eventName ~= "" then
      if not registeredReviveEvents[eventName] then
        registeredReviveEvents[eventName] = true
        pcall(RegisterNetEvent, eventName)
        AddEventHandler(eventName, function()
          setStress(0)
        end)
      end
    end
  end
end

exports("SetVisible", setHudVisible)
exports("showHUD", function()
  setHudVisible(true)
end)
exports("hideHUD", function()
  setHudVisible(false)
end)
exports("SetStatus", function(data)
  TriggerEvent("as-hud:updateStatus", data)
end)
exports("SetSpeedUnit", setUseMetricSpeed)
exports("SetStress", setStress)
exports("AddStress", addStress)
exports("DecreaseStress", removeStress)
exports("RemoveStress", removeStress)
exports("GetStress", function()
  return stressLevel
end)
exports("ResetStress", function()
  setStress(0)
end)
exports("SetNavigationVisible", setNavigationVisible)
exports("showCompass", function()
  setNavigationVisible(true)
end)
exports("hideCompass", function()
  setNavigationVisible(false)
end)
exports("SetSpeedometerVisible", setSpeedometerVisible)
exports("showSpeedometer", function()
  setSpeedometerVisible(true)
end)
exports("hideSpeedometer", function()
  setSpeedometerVisible(false)
end)