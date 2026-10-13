-- QB-Core replacement for the ox_lib server callbacks used by this resource.
if GetResourceState('qbx_core') == 'started' or GetResourceState('qb-core') ~= 'started' then return end

local handlers = {}

lib.callback = {}

function lib.callback.register(name, handler)
    handlers[name] = handler
end

RegisterNetEvent('blixt-busking:bridge:request', function(requestId, name, args)
    local src = source
    local handler = handlers[name]
    if not handler or type(requestId) ~= 'number' or type(args) ~= 'table' then return end

    local results = table.pack(handler(src, table.unpack(args, 1, args.n or #args)))
    TriggerClientEvent('blixt-busking:bridge:response', src, requestId, results)
end)
