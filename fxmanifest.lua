fx_version 'cerulean'
game 'gta5'

lua54 'yes'

name 'blixt-busking'
version '1.2'

shared_scripts {
    'bridge/init.lua',
    'config.lua',
    'progression.lua',
    'shop.lua',
    'songs.lua'
}

client_scripts {
    'bridge/qb_client.lua',
    'bridge/qb_menu.lua',
    'client.lua',
    'bridge/qb_objects.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/qb_server.lua',
    'server.lua'
}

dependencies {
    'xsound',
    'oxmysql'
}
