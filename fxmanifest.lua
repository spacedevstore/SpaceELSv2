fx_version 'cerulean'
game 'gta5'

name 'SpaceELS'
description 'ELS Vehicle Light & Sound Controller'
author 'SpaceDev'
version '1.0.1'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/els.lua'
}

server_scripts {
    'server/main.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js'
}
