fx_version 'cerulean'
game 'gta5'
lua54 'yes'
author 'Marz Scripts'
description 'Knockout Script with Enhanced Features'

shared_scripts { 
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts { 
    'cl_knockout.lua'
} 

server_scripts {
    'sv_knockout.lua'
}

ui_page 'html/index.html'

files {
    'sounds/*.ogg',
    'html/index.html'
}

dependencies {
    'ox_lib'
}

escrow_ignore {
    'config.lua' 
}