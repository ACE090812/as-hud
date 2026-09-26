ashudConfig = {
    framework = 'auto',
    brand = GetConvar('acestudios:brand', 'acestudios'),
    showBrand = false,
    hideOnNuiFocus = true, -- hide while inventory, shops, or other modal menus own focus
    speedUnit = 'mph', -- 'mph' or 'kmh'
    showVehicle = true,
    showStaminaBelow = 101,
    showOxygenBelow = 95,
    oxygenCapacitySeconds = 10, -- match any diving/stamina resource's configured capacity
    lowThreshold = 20,
    updateInterval = 200,
    radar = {
        enabled = true,
        onlyInVehicle = false,
        diameter = 0.19, -- fraction of screen height; round on ultrawide displays
        right = 0.025,   -- fraction of screen width, plus GTA safe-zone inset
        top = 0.080,     -- fraction of screen height, plus GTA safe-zone inset
        zoomDistance = 140.0, -- native street-level zoom distance
        -- 'auto': if as-map is installed it draws the map inside this frame and
        -- the native radar is left alone. true forces it, false = native radar.
        external = 'auto',
        externalResource = 'as-map',
    },
}
