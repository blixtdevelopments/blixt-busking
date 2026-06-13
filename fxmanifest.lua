fx_version 'cerulean'
game 'gta5'

lua54 'yes'

name 'blixt-busking'
version '1.2'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'progression.lua',
    'shop.lua',
    'songs.lua'
}

client_scripts {
    'client.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua'
}

dependencies {
    'xsound',
    'oxmysql'
}
