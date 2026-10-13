-- QB-Core menu adapter. Loaded before client.lua.
if GetResourceState('qbx_core') == 'started' or GetResourceState('qb-core') ~= 'started' then
    return
end

if GetResourceState('qb-menu') ~= 'started' then
    print('^1[blixt-busking] qb-menu must start before blixt-busking.^0')
    return
end

local menus = {}
local pendingConfirm

lib.registerContext = function(context)
    if type(context) ~= 'table' then return end

    if context.id then
        menus[context.id] = context
        return
    end

    for _, entry in ipairs(context) do
        if type(entry) == 'table' and entry.id then
            menus[entry.id] = entry
        end
    end
end

lib.showContext = function(id)
    local context = menus[id]
    if not context then
        print(('^1[blixt-busking] Unknown menu: %s^0'):format(tostring(id)))
        return
    end

    local entries = {
        { header = context.title or 'Busking', isMenuHeader = true, params = {} }
    }

    for _, option in ipairs(context.options or {}) do
        local item = option
        local row = {
            header = item.title or '',
            txt = item.description or '',
            icon = item.icon,
            disabled = item.disabled == true or item.readOnly == true,
            isMenuHeader = item.readOnly == true,
            params = {}
        }

        if not row.disabled then
            row.action = function()
                if type(item.onSelect) == 'function' then
                    item.onSelect(item.args)
                elseif item.event then
                    TriggerEvent(item.event, item.args)
                end
            end
        end

        entries[#entries + 1] = row
    end

    exports['qb-menu']:openMenu(entries)
end

lib.hideContext = function()
    exports['qb-menu']:closeMenu()
end

-- The only alert dialog in this resource is the next-song yes/no prompt.
lib.alertDialog = function(data)
    if pendingConfirm then return 'cancel' end

    local deferred = promise.new()
    local active = true
    local function finish(value)
        if not active then return end
        active = false
        pendingConfirm = nil
        deferred:resolve(value)
    end

    pendingConfirm = finish
    local labels = data.labels or {}
    exports['qb-menu']:openMenu({
        { header = data.header or 'Confirm', txt = data.content or '', isMenuHeader = true, params = {} },
        { header = labels.confirm or 'Yes', action = function() finish('confirm') end, params = {} },
        { header = labels.cancel or 'No', action = function() finish('cancel') end, params = {} }
    })

    return Citizen.Await(deferred)
end

AddEventHandler('qb-menu:client:menuClosed', function()
    if pendingConfirm then pendingConfirm('cancel') end
end)

print('^2[blixt-busking] QB-Core / qb-menu adapter enabled.^0')
