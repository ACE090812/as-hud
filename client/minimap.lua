local enableIslandRadar = false

local ISLAND_INTERIOR_HASH = -1062664944
local ISLAND_RADAR_CENTER = vec(4700.0, -5145.0)
local DEFAULT_RADAR_ZOOM = 1200

-- { level, zoomScale, zoomSpeed, scrollSpeed, tilesX, tilesY }
local mapZoomLevels = {
    { 0, 2.75, 0.9, 0.08, 0.0, 0.0 },
    { 1, 2.8, 0.9, 0.08, 0.0, 0.0 },
    { 2, 8.0, 0.9, 0.08, 0.0, 0.0 },
    { 3, 20.0, 0.9, 0.08, 0.0, 0.0 },
    { 4, 35.0, 0.9, 0.08, 0.0, 0.0 },
    { 5, 55.0, 0.0, 0.1, 2.0, 1.0 },
    { 6, 450.0, 0.0, 0.1, 1.0, 1.0 },
    { 7, 4.5, 0.0, 0.0, 0.0, 0.0 },
    { 8, 11.0, 0.0, 0.0, 2.0, 3.0 }
}

CreateThread(function()
    for _, zoomData in ipairs(mapZoomLevels) do
        SetMapZoomDataLevel(table.unpack(zoomData))
    end
end)

CreateThread(function()
    while true do
        Wait(80)
        if Config.RadarLockToPlayer == false then
            SetRadarZoom(math.floor(tonumber(Config.RadarZoom) or DEFAULT_RADAR_ZOOM))
        end
    end
end)

if enableIslandRadar then
    CreateThread(function()
        while true do
            SetRadarAsExteriorThisFrame()
            SetRadarAsInteriorThisFrame(ISLAND_INTERIOR_HASH, ISLAND_RADAR_CENTER.x, ISLAND_RADAR_CENTER.y, 0, 0)
            Wait(0)
        end
    end)
end