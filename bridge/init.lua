-- Load the original ox_lib on Qbox; initialise the QB-Core adapter otherwise.
if GetResourceState('qbx_core') == 'started' or GetResourceState('qb-core') ~= 'started' then
    local source = LoadResourceFile('ox_lib', 'init.lua')
    if not source then
        error('[blixt-busking] ox_lib is required for Qbox. Start ox_lib before blixt-busking.', 0)
    end

    local init, err = load(source, '@@ox_lib/init.lua', 't', _ENV)
    if not init then error(err, 0) end
    init()
else
    lib = {}
end
