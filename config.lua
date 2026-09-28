Config = {}

-- 'auto' picks 'qb' if qbx_core/qb-core is running, 'esx' if es_extended is
-- running, otherwise 'custom'. Force it if auto-detection picks wrong or you
-- run something else. See bridge/framework.lua for how each is wired up.
Config.Framework = 'esx'

Config.HudSettings = {
    command = 'hudsettings',
    key = 'F7',
    snapToGrid = true
}

-- Custom frameworks may supply { id = 'stable-character-id', cash = 0, bank = 0 }.
-- Leave nil for the built-in QBox/QBCore/ESX adapters.
Config.GetHudPlayer = nil

-- If you run a resource that replaces the minimap entirely (a 3D/web map
-- like as-map), as-hud should not fight it for the native minimap:
-- no radar mask texture, no clip type, no LockMinimapPosition/Angle, no
-- DisplayRadar calls, and no native blip hiding/clipping. Everything else
-- (compass heading, waypoint distance/bearing, HUD sections) keeps working
-- as normal since those are drawn by as-hud's own NUI, not the native
-- minimap.
--   true   -- always defer to the external map resource
--   false  -- always use as-hud's own circular minimap
--   'auto' -- defer automatically while Config.ExternalMinimapResource is running
Config.ExternalMinimap = 'auto'
Config.ExternalMinimapResource = 'as-map'

Config.UpdateInterval = 200
Config.ShowNavigation = true
Config.UseMetricSpeed = true
Config.HideDefaultHud = true
-- true puts dark strips behind the heading and the zone name. Off by default:
-- the layered text shadow reads cleaner, and the strips were the thing players
-- most often asked to remove.
Config.NavigationTextBackdrop = false
-- How long the vehicle control hints stay on screen after getting in, in ms.
-- 0 keeps them up for as long as the player is in the vehicle.
Config.VehicleControlsTimeout = 5000
Config.ShowDefaultAmmo = true
Config.StressSpeedThresholdKmh = 9999.0
Config.StressGainDriving = 0
Config.StressGainShooting = 0
Config.StressGainCooldown = 5000

-- Admin commands for stress. Rename them to whatever you like.
--   /addstress <id> <percent>   adds that much stress (both args required)
--   /removestress [id]          clears it entirely (id defaults to you)
-- Admins only, detected automatically: the group.admin / group.superadmin /
-- command ACEs, QBCore and QBox admin permissions, or an ESX admin group.
-- Nothing to set up if your admins are already admins.
-- Put your own ace name in acePermission to use that instead of the admin
-- check, or set it to false to let anyone use the commands.
Config.StressCommands = {
    enabled = false,
    add = 'addstress',
    remove = 'removestress',
    acePermission = nil
}

-- Clear a player's stress automatically when they are revived. The events
-- below are the usual ambulance scripts; add your own if it is not listed.
Config.ClearStressOnRevive = false
Config.ReviveEvents = {
    'hospital:client:Revive',
    'qbx_medical:client:playerRevived',
    'esx_ambulancejob:revive',
    'ambulance:client:revive'
}
-- Stress screen effects, ported from qbx_hud: blur swells that get longer and
-- more frequent as stress climbs, and at 100 a full breakdown -- the player
-- collapses and the screen blacks out a few times.
--
-- Two fixes over the qbx original:
--   * its effectInterval used math.random(a, b) written straight into the
--     config, which Lua evaluates ONCE when the file loads. Every player then
--     got the same fixed interval for the whole session instead of a new roll
--     each time. Here the bounds are stored and rolled at use.
--   * its bands overlap at the edges (60 is in both the 50-60 and 60-70 row)
--     and it walked them with pairs(), whose order is undefined -- so exactly
--     on a boundary you got whichever row Lua happened to visit first. These
--     are walked in order, first match wins.
Config.StressEffects = {
    enabled = false,
    -- Below this nothing happens at all. The name is qbx's; there is no camera
    -- shake in this system (qbx_hud has none either) -- it is blur, blackout
    -- and ragdoll. Kept as-is so the port stays recognisable.
    minForShaking = 50,
    -- Ragdoll the player at 100 stress. false keeps the blackouts without the
    -- collapse, which some servers prefer for passengers/drivers.
    ragdoll = true,
    -- How long the screen stays black on each blackout at 100 stress.
    fadeOutMs = 200,
    fadeInMs = 200,
    -- How long each blur swell is held, per stress band (ms).
    blurIntensity = {
        { min = 50, max = 60,  intensity = 1500 },
        { min = 60, max = 70,  intensity = 2000 },
        { min = 70, max = 80,  intensity = 2500 },
        { min = 80, max = 90,  intensity = 2700 },
        { min = 90, max = 100, intensity = 3000 }
    },
    -- Gap between effects, per stress band. Rolled fresh every cycle.
    effectInterval = {
        { min = 50, max = 60,  timeoutMin = 50000, timeoutMax = 60000 },
        { min = 60, max = 70,  timeoutMin = 40000, timeoutMax = 50000 },
        { min = 70, max = 80,  timeoutMin = 30000, timeoutMax = 40000 },
        { min = 80, max = 90,  timeoutMin = 20000, timeoutMax = 30000 },
        { min = 90, max = 100, timeoutMin = 15000, timeoutMax = 20000 }
    }
}

-- Native radar components are fitted so the visible map circle lands on the
-- compass-frame.png aperture measured by the NUI. 1.0 = map edge on the rim's
-- inner line; the rim spans 1.00-1.09, so 1.05 tucks the soft edge under it.
Config.RadarMaskScale = 1.05
-- Fractions of the circle diameter. Positive X moves the map right; positive Y
-- moves it down.
Config.RadarMaskOffsetX = 0.0
Config.RadarMaskOffsetY = 0.0
-- GTA clips the GPS route (and blips) to the minimap component's rectangle, not
-- to the round mask, so the route could run far outside compass-frame.png.
-- true shrinks that rectangle to the square around the circle; the mask keeps
-- its own fitted rect.
Config.RadarClipRoute = true
Config.RadarLockToPlayer = true
-- World distance the locked radar spans. Lower = more zoomed in.
Config.RadarZoomDistance = 75.0

-- true: past MinimapBlipRange the native waypoint blip leaves the radar and the
-- HUD draws a waypoint marker on the edge of the ring at its real bearing,
-- turning with the compass. false: GTA draws it itself, and for far waypoints
-- parks it at the corner of the radar rectangle, outside the ring.
Config.ClipWaypointBlip = true

-- Legacy fallback zoom used only when RadarLockToPlayer is false. Higher = more
-- zoomed in = less world on screen. GTA's own default is 1100.
Config.RadarZoom = 1100

-- GTA's circular-mask trick only clips the map texture, not blip icons, so
-- POI blips (PD, shops, etc.) can render outside the ring near its edges.
-- Keeping only the waypoint on the radar avoids that entirely.
Config.HideMinimapBlips = false
-- How far (in metres) a blip may be before it is hidden instead of being
-- clamped to the edge of the radar *rectangle*, which is wider than the circle
-- and therefore parks it outside the ring. This must match the world radius the
-- ring actually covers at the active radar zoom: too high and blips still sit
-- outside the circle, too low and they vanish before reaching its edge.
--
-- 0 disables it.
Config.MinimapBlipRange = 185.0

Config.SeatbeltFeedback = {
    sound = true,
    animation = true,
    buckle = {
        dict = 'new@anim@carseatbelt',
        names = { 'seatbelt_driver' }
    },
    unbuckle = {
        dict = 'new@anim@cargreabox',
        names = { 'gearbox_up' }
    },
    blendIn = 8.0,
    blendOut = -8.0,
    duration = 1000,
    flag = 49,
    buckleSound = { name = 'SELECT', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    unbuckleSound = { name = 'BACK', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' }
}

Config.GearChangeAnimation = {
    enabled = true,
    dict = 'new@anim@cargreabox',
    names = { 'gearbox_up' },
    blendIn = 8.0,
    blendOut = -8.0,
    duration = 1000,
    flag = 49,
    minSpeed = 1.0,
    cooldown = 450
}

Config.HornAnimation = {
    enabled = true,
    dict = 'new@anim@cargreabox',
    names = { 'gearbox_up' },
    blendIn = 8.0,
    blendOut = -8.0,
    duration = 1000,
    flag = 49,
    cooldown = 900
}

-- Add custom/add-on electric vehicle spawn names here if your server has them.
Config.ElectricVehicles = {
    'airtug',
    'caddy',
    'caddy2',
    'caddy3',
    'cyclone',
    'cyclone2',
    'dilettante',
    'imorgon',
    'iwagen',
    'khamelion',
    'neon',
    'omnisegt',
    'powersurge',
    'raiden',
    'surge',
    'tezeract',
    'virtue',
    'voltic',
    'voltic2'
}

-- Integrated chat. Set enabled = false if you run another chat resource.
-- When disabled, this HUD will not register chat commands, keybinds, events,
-- exports, NUI callbacks, or block GTA chat controls.
Config.Chat = {
    enabled = true,
    key = 'T',
    maxLength = 300,
    messageLifetime = 8000,
    maxMessages = 60,
    cooldown = 800
}

Config.VehicleControls = {
    { label = 'STOP ENGINE', icon = 'engine' },
    { key = 'L', label = 'VEHICLE LOCK' },
    { key = 'H', label = 'HEADLIGHTS' },
    { key = 'E', label = 'HORN' },
    { key = 'F', label = 'EXIT' }
}
