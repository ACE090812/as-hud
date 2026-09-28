HudScreen = {}

local cachedScreen = nil
local customMinimapLayout = nil
local screenRevision = 0

local function clamp(value, minValue, maxValue)
  return math.max(minValue, math.min(maxValue, value))
end

local function isValidNumber(value)
  return type(value) == "number" and value == value
end

-- Measures the on-screen bounds of a given gfx alignment (e.g. "L","T") as {x, y, sx, sy}
local function getGfxAlignBounds(alignX, alignY)
  SetScriptGfxAlign(string.byte(alignX), string.byte(alignY))
  SetScriptGfxAlignParams(0.0, 0.0, 0.0, 0.0)

  local x, y = GetScriptGfxPosition(0.0, 0.0)
  local x2, y2 = GetScriptGfxPosition(1.0, 1.0)

  ResetScriptGfxAlign()

  return { x = x, y = y, sx = x2 - x, sy = y2 - y }
end

function HudScreen.Get()
  if cachedScreen then
    return cachedScreen
  end

  HudScreen.Refresh(true)
  return cachedScreen
end

function HudScreen.Refresh(force)
  local width, height = GetActiveScreenResolution()
  if width < 1 or height < 1 then
    return
  end

  local aspect = GetAspectRatio(false)
  local physicalAspect = GetAspectRatio(true)
  local safezone = GetSafeZoneSize()
  local transform = getGfxAlignBounds("L", "T")

  if not (isValidNumber(transform.sx) and isValidNumber(transform.sy)
    and math.abs(transform.sx) >= 1.0E-5
    and math.abs(transform.sy) >= 1.0E-5) then
    return
  end

  if not force and cachedScreen
    and cachedScreen.width == width
    and cachedScreen.height == height
    and math.abs(cachedScreen.aspect - aspect) < 1.0E-5
    and math.abs(cachedScreen.physicalAspect - physicalAspect) < 1.0E-5
    and math.abs(cachedScreen.safezone - safezone) < 1.0E-5
    and math.abs(cachedScreen.transform.x - transform.x) < 1.0E-5
    and math.abs(cachedScreen.transform.y - transform.y) < 1.0E-5
    and math.abs(cachedScreen.transform.sx - transform.sx) < 1.0E-5
    and math.abs(cachedScreen.transform.sy - transform.sy) < 1.0E-5 then
    return
  end

  screenRevision = screenRevision + 1
  local safeMargin = (1 - clamp(safezone, 0.0, 1.0)) * 0.5

  cachedScreen = {
    width = width,
    height = height,
    aspect = aspect,
    physicalAspect = physicalAspect,
    safezone = safezone,
    revision = screenRevision,
    transform = transform,
    safe = { left = safeMargin, right = safeMargin, top = safeMargin, bottom = safeMargin }
  }
  customMinimapLayout = nil

  SendNUIMessage({ action = "hudScreen", screen = cachedScreen })
  TriggerEvent("as-hud:applyMinimapLayout")
  TriggerEvent("as-hud:screenChanged")
end

-- Normalized reference space that minimap component rects are authored against
local minimapReferenceSpace = { cx = 0.5, cy = 0.5, width = 1.0, height = 1.0 }

-- Computes the native minimap's default position/size for the current screen, unless overridden by the NUI
local function getMinimapLayout(screen)
  local mapScale = clamp(math.min(screen.width / 1920, screen.height / 1080), 0.7, 1.35)
  local squareSize = math.min(screen.width, screen.height * 16 / 9)
  local rightMargin = math.max(
    (screen.width - squareSize) / 2 + squareSize * (1 - screen.safezone) / 2,
    screen.safe.right * screen.width
  )

  return {
    cx = (screen.width - rightMargin - 147.5 * mapScale) / screen.width,
    cy = screen.safe.top + 163.5 * mapScale / screen.height,
    diameter = 175 * mapScale
  }
end

-- Transforms a rect (x, y, w, h) defined in minimapReferenceSpace into screen-space coordinates
function HudScreen.MinimapRect(x, y, w, h)
  local screen = HudScreen.Get()
  if not screen then
    return x, y, w, h
  end

  local layout = customMinimapLayout or getMinimapLayout(screen)
  local transform = screen.transform
  local aspect = (isValidNumber(screen.aspect) and screen.aspect > 0) and screen.aspect or (screen.width / screen.height)

  local scaleX = transform.sx * (screen.width / screen.height) / aspect
  local diameterPx = layout.diameter * 0.9771428571428571

  local scaleFactorX = diameterPx / (screen.width * scaleX * minimapReferenceSpace.width)
  local scaleFactorY = diameterPx / (screen.height * transform.sy * minimapReferenceSpace.height)

  local resultX = (layout.cx - transform.x) / scaleX + (x - minimapReferenceSpace.cx) * scaleFactorX
  local resultY = (layout.cy - transform.y) / transform.sy + (y - minimapReferenceSpace.cy) * scaleFactorY
  local resultW = w * scaleFactorX
  local resultH = h * scaleFactorY

  return resultX, resultY, resultW, resultH
end

local fullMinimapRect = { left = 0, top = 0, width = 1, height = 1 }

-- Computes a zoomed/offset rect around the minimap's center: rect defines the crop, zoom/offsetX/offsetY tune it
local function computeMinimapZoomRect(rect, zoom, offsetX, offsetY)
  local screen = HudScreen.Get()
  if not screen then
    return 0.0, 0.0, 0.0, 0.0
  end

  local layout = customMinimapLayout or getMinimapLayout(screen)
  local transform = screen.transform
  local aspect = (isValidNumber(screen.aspect) and screen.aspect > 0) and screen.aspect or (screen.width / screen.height)

  local scaleX = transform.sx * (screen.width / screen.height) / aspect
  local diameterPx = layout.diameter * clamp(tonumber(zoom) or 1.0, 0.5, 2.0)

  local scaleFactorX = diameterPx / rect.width
  local scaleFactorY = diameterPx / rect.height

  local offX = clamp(tonumber(offsetX) or 0.0, -0.5, 0.5) * diameterPx / screen.width
  local offY = clamp(tonumber(offsetY) or 0.0, -0.5, 0.5) * diameterPx / screen.height

  local centerX = layout.cx + offX - (rect.left * scaleFactorX + diameterPx * 0.5) / screen.width
  local centerY = layout.cy + offY - (rect.top * scaleFactorY + diameterPx * 0.5) / screen.height

  local resultX = (centerX - transform.x) / scaleX
  local resultY = (centerY - transform.y) / transform.sy
  local resultW = scaleFactorX / (screen.width * scaleX)
  local resultH = scaleFactorY / (screen.height * transform.sy)

  return resultX, resultY, resultW, resultH
end

function HudScreen.MinimapRadarRect(zoom, offsetX, offsetY)
  return computeMinimapZoomRect(fullMinimapRect, zoom, offsetX, offsetY)
end

function HudScreen.MinimapCircleRect(zoom, offsetX, offsetY)
  return computeMinimapZoomRect(fullMinimapRect, zoom, offsetX, offsetY)
end

RegisterNUICallback("hudScreenReady", function(_, cb)
  cb({ ok = true, screen = HudScreen.Get() })
end)

RegisterNUICallback("hudRadarLayout", function(data, cb)
  local screen = HudScreen.Get()

  if not (type(data) == "table" and data.revision == screen.revision) then
    cb({ ok = false, error = "Screen changed", screen = screen })
    return
  end

  local cx, cy, diameter = data.cx, data.cy, data.diameter

  if not (isValidNumber(cx) and isValidNumber(cy) and isValidNumber(diameter))
    or cx < 0 or cx > 1
    or cy < 0 or cy > 1
    or diameter <= 0 or diameter > 1 then
    cb({ ok = false, error = "Invalid radar bounds" })
    return
  end

  customMinimapLayout = { cx = cx, cy = cy, diameter = diameter * screen.height }
  TriggerEvent("as-hud:applyMinimapLayout")

  cb({ ok = true })
end)

CreateThread(function()
  while true do
    HudScreen.Refresh(false)
    Wait(500)
  end
end)