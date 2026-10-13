-- Paste these assignments at the END of qb-core/shared/items.lua.
-- Do not load this file as a FiveM client/server script.
QBShared.Items['guitar'] = {
    name = 'guitar', label = 'Guitar', weight = 1500, type = 'item',
    image = 'guitar.png', unique = true, useable = true, shouldClose = true,
    description = 'Use to start busking.'
}

QBShared.Items['busking_hat'] = {
    name = 'busking_hat', label = 'Busking Hat', weight = 250, type = 'item',
    image = 'busking_hat.png', unique = true, useable = true, shouldClose = true,
    description = 'Place it down so people can tip your performance.'
}

QBShared.Items['busking_speaker'] = {
    name = 'busking_speaker', label = 'Busking Speaker', weight = 2500, type = 'item',
    image = 'busking_speaker.png', unique = true, useable = true, shouldClose = true,
    description = 'Place it down for a better busking setup.'
}

QBShared.Items['busking_mic'] = {
    name = 'busking_mic', label = 'Busking Mic Stand', weight = 1500, type = 'item',
    image = 'busking_mic.png', unique = true, useable = true, shouldClose = true,
    description = 'Place it down to boost your busking setup.'
}
