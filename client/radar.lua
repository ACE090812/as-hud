ashudRadar = {}
local config = ashudConfig.radar
local layoutKey
local maskLoaded = false
local radarVisible
local originalVisibility = not IsRadarHidden()
local originalNorthAlpha
local scaleform
local refreshGeneration = 0
local tracking = false
local stopped = false
local lastHeading, headingUpdated = nil, -1000
local lastLayout
local lastVisibleEvent

local function isExternal()
    if config.external == true then return true end
    if config.external ~= 'auto' then return false end
    local state = GetResourceState(config.externalResource or 'as-map')
    return state ~= 'missing' and state ~= 'unknown'
end

local function releaseTracking()
    if not tracking then return end
    UnlockMinimapAngle()
    UnlockMinimapPosition()
    tracking = false
    lastHeading = nil
end

function ashudRadar.layout(force)
    if force then lastHeading, headingUpdated = nil, -1000 end
    local screenWidth, screenHeight = GetActiveScreenResolution()
    if screenWidth <= 0 or screenHeight <= 0 then return end
    SetScriptGfxAlign(string.byte('L'), string.byte('T'))
    local originX, originY = GetScriptGfxPosition(0.0, 0.0)
    local endX, endY = GetScriptGfxPosition(1.0, 1.0)
    ResetScriptGfxAlign()
    local scaleX, scaleY = endX - originX, endY - originY
    if scaleX <= 0 or scaleY <= 0 then return end
    local key = ('%d:%d:%.5f:%.5f:%.5f:%.5f'):format(screenWidth, screenHeight, originX, originY, scaleX, scaleY)
    if not force and layoutKey == key then return end
    layoutKey = key
    local diameter = math.max(0.12, math.min(0.28, config.diameter))
    local width = diameter * screenHeight / screenWidth
    local left = 1.0 - config.right - originX - width
    local top = config.top + originY
    local x, y = (left - originX) / scaleX, (top - originY) / scaleY
    local w, h = width / scaleX, diameter / scaleY
    lastLayout = {
        left = left, top = top, width = width, height = diameter,
        safeX = originX, safeY = originY,
    }
    SendNUIMessage({ action = 'hud:layout', data = lastLayout })
    TriggerEvent('as-hud:radarLayout', lastLayout)
    if not config.enabled or isExternal() then return end
    for _, component in ipairs({ 'minimap', 'minimap_mask', 'minimap_blur' }) do
        SetMinimapComponentPosition(component, 'L', 'T', x, y, w, h)
    end
    if maskLoaded then
        refreshGeneration = refreshGeneration + 1
        local refresh = refreshGeneration
        SetRadarBigmapEnabled(true, false)
        CreateThread(function()
            Wait(0)
            if refresh == refreshGeneration then SetRadarBigmapEnabled(false, false) end
        end)
    end
end

local function initialize()
    if maskLoaded then return end
    local txdName = GetCurrentResourceName() .. '_radar'
    local txd = CreateRuntimeTxd(txdName)
    local texture = CreateRuntimeTextureFromImage(txd, 'round_mask', 'assets/radar-mask.png')
    if not texture or texture == 0 then return end
    AddReplaceTexture('platform:/textures/graphics', 'radarmasksm', txdName, 'round_mask')
    AddReplaceTexture('platform:/textures/graphics', 'radarmask1g', txdName, 'round_mask')
    SetMinimapClipType(1)
    local north = GetNorthRadarBlip()
    originalNorthAlpha = GetBlipAlpha(north)
    SetBlipAlpha(north, 0)
    scaleform = RequestScaleformMovie('minimap')
    maskLoaded = true
    ashudRadar.layout(true)
end

function ashudRadar.update(visible, inVehicle)
    if not config.enabled then return false end
    local show = visible and (not config.onlyInVehicle or inVehicle)
    if lastVisibleEvent ~= show then
        lastVisibleEvent = show
        TriggerEvent('as-hud:radarVisible', show)
    end
    if isExternal() then
        if show and not lastLayout then ashudRadar.layout(true) end
        radarVisible = show
        return show
    end
    if show then initialize() end
    if radarVisible ~= show or (show and IsRadarHidden()) then
        DisplayRadar(show)
        radarVisible = show
    end
    if not show then releaseTracking() end
    if show and scaleform and HasScaleformMovieLoaded(scaleform) then
        BeginScaleformMovieMethod(scaleform, 'SETUP_HEALTH_ARMOUR')
        ScaleformMovieMethodAddParamInt(3)
        EndScaleformMovieMethod()
    end
    return show and maskLoaded
end

local function sendHeading()
    local angle = math.floor(GetGameplayCamRot(2).z + 0.5) % 360
    local heading = (360 - angle) % 360
    local now = GetGameTimer()
    if lastHeading ~= heading and now - headingUpdated >= 33 then
        SendNUIMessage({ action = 'hud:heading', data = { heading = heading } })
        lastHeading, headingUpdated = heading, now
    end
end

function ashudRadar.frame()
    if stopped or not radarVisible then return end
    if isExternal() then
        if not IsPauseMenuActive() then sendHeading() end
        return
    end
    if not maskLoaded then return end
    if IsPauseMenuActive() or LocalPlayer.state.invOpen or LocalPlayer.state.inv_busy or LocalPlayer.state.characterCreation then
        releaseTracking()
        return
    end

    local coords = GetEntityCoords(PlayerPedId())
    SetRadarAsExteriorThisFrame()
    SetRadarZoomToDistance(config.zoomDistance or 140.0)
    LockMinimapPosition(coords.x, coords.y)
    local angle = math.floor(GetGameplayCamRot(2).z + 0.5) % 360
    LockMinimapAngle(angle)
    tracking = true
    local heading = (360 - angle) % 360
    local now = GetGameTimer()
    if lastHeading ~= heading and now - headingUpdated >= 33 then
        SendNUIMessage({ action = 'hud:heading', data = { heading = heading } })
        lastHeading, headingUpdated = heading, now
    end
end

CreateThread(function()
    while not stopped do
        ashudRadar.frame()
        Wait(radarVisible and 0 or 150)
    end
end)

exports('GetRadarLayout', function()
    return lastLayout
end)

exports('IsRadarVisible', function()
    return lastVisibleEvent == true
end)

function ashudRadar.reset()
    stopped = true
    if lastVisibleEvent then TriggerEvent('as-hud:radarVisible', false) end
    if isExternal() then return end
    releaseTracking()
    refreshGeneration = refreshGeneration + 1
    SetRadarBigmapEnabled(false, false)
    if not config.enabled then return end
    if maskLoaded then
        RemoveReplaceTexture('platform:/textures/graphics', 'radarmasksm')
        RemoveReplaceTexture('platform:/textures/graphics', 'radarmask1g')
        SetMinimapClipType(0)
        SetMinimapComponentPosition('minimap', 'L', 'B', 0.0, -0.022, 0.152, 0.188888)
        SetMinimapComponentPosition('minimap_mask', 'L', 'B', 0.0, 0.032, 0.111, 0.159)
        SetMinimapComponentPosition('minimap_blur', 'L', 'B', -0.03, 0.022, 0.266, 0.237)
        if originalNorthAlpha then SetBlipAlpha(GetNorthRadarBlip(), originalNorthAlpha) end
    end
    if scaleform and HasScaleformMovieLoaded(scaleform) then
        BeginScaleformMovieMethod(scaleform, 'SETUP_HEALTH_ARMOUR')
        ScaleformMovieMethodAddParamInt(0)
        EndScaleformMovieMethod()
        SetScaleformMovieAsNoLongerNeeded(scaleform)
    end
    DisplayRadar(originalVisibility)
end
