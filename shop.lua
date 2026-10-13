Config.Shop = {
    Header = 'Busker',
    Ped = {
        model = `s_m_o_busker_01`,
        coords = vec4(346.6945, 169.6327, 103.0800, 165.3595),
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT'
    },
    Blip = {
        enabled = true,
        sprite = 136,
        color = 25,
        scale = 0.8,
        shortRange = true
    },
    Items = {
        guitar = {
            item = 'guitar',
            label = 'Guitar',
            description = 'Use to start busking.',
            price = 500,
            requiredLevel = 0
        },
        hat = {
            item = 'busking_hat',
            label = 'Busking Hat',
            description = 'Needed for tips.',
            price = 50,
            requiredLevel = 0
        },
        mic = {
            item = 'busking_mic',
            label = 'Mic Stand',
            description = 'Boosts your setup to get better tips',
            price = 750,
            requiredLevel = 3
        },
        speaker = {
            item = 'busking_speaker',
            label = 'Speaker',
            description = 'Boosts your setup to get better tips',
            price = 1500,
            requiredLevel = 4
        }
    }
}







-----blip logic


if not IsDuplicityVersion() then
    CreateThread(function()
        local config = Config.Shop.Blip
        if not config or not config.enabled then return end

        local coords = Config.Shop.Ped.coords
        local blip = AddBlipForCoord(coords.x, coords.y, coords.z)

        SetBlipSprite(blip, config.sprite)
        SetBlipDisplay(blip, 4)
        SetBlipScale(blip, config.scale)
        SetBlipColour(blip, config.color)
        SetBlipAsShortRange(blip, config.shortRange)

        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(Config.Shop.Header)
        EndTextCommandSetBlipName(blip)
    end)
end
