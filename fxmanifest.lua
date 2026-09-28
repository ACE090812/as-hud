fx_version 'cerulean'
game 'gta5'

author 'ACE Studios'
description 'as-map'
version '1.0.0'

lua54 'yes'

ui_page 'web/index.html'

-- Shared
shared_script 'config.lua'

-- Server
server_scripts {
    'server/main.lua',
    'server/chat.lua'
}

-- Client
client_scripts {
    'bridge/framework.lua',
    'client/screen.lua',
    'client/settings.lua',
    'client/chat.lua',
    'client/main.lua',
    'client/minimap.lua'
}

-- NUI / assets
files {
    -- HTML/CSS/JS
    'web/index.html',
    'web/style.css',
    'web/chat.css',
    'web/chat.js',
    'web/script.js',
    'web/layout-math.js',
    'web/hud-screen.js',
    'web/hud-preferences.js',
    'web/hud-layout.js',
    'web/hud-editor.js',
    'web/hud-settings.js',
    'web/hud-settings.css',

    -- Images
    'web/compass-frame.png',
    'assets/radar-mask.png',

    -- Fonts
    'web/fonts/BarlowCondensed-ExtraBoldItalic.ttf',
    'web/fonts/BarlowCondensed-Bold.ttf',
    'web/fonts/BarlowCondensed-OFL.txt',

    -- Streamed assets
    'stream/*.*',
    'stream/**/*.*'
}