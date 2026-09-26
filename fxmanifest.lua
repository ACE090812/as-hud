fx_version 'cerulean'
game 'gta5'
name 'as-hud'
author 'ACE Studios'
description 'FiveM Custom Hud'
version '1.0.0'

ui_page 'html/dist/index.html'

client_scripts {
    'config.lua',
    'client/framework.lua',
    'client/radar.lua',
    'client/main.lua',
}
files { 'html/dist/**', 'assets/radar-mask.png' }
