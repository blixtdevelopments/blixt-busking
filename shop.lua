Config.Shop = {
    Header = 'Busking Supplier',
    Ped = {
        model = `s_m_o_busker_01`,
        coords = vec4(-267.8177, 235.1316, 90.5748, 2.2282),
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT'
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
