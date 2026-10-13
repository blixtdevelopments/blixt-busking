-- QB-Core prop interactions. Loaded after client.lua.
if GetResourceState('qbx_core') == 'started' or GetResourceState('qb-core') ~= 'started' then
    return
end

-- ox_target already supplies these interactions when present.
if GetResourceState('ox_target') == 'started' then return end

local props = {}
local targets = {}
local labels = { hat = 'Busking Hat', speaker = 'Speaker', mic = 'Mic Stand' }

local function key(id)
    return tonumber(id)
end

local function notify(message, kind)
    lib.notify({ title = 'Busking', description = message, type = kind or 'inform' })
end

local function findObject(netId)
    if not netId or not NetworkDoesNetworkIdExist(netId) then return 0 end
    local entity = NetToObj(netId)
    return entity and DoesEntityExist(entity) and entity or 0
end

local function removeTarget(netId)
    local old = targets[netId]
    if not old then return end

    if GetResourceState('qb-target') == 'started' then
        pcall(function()
            exports['qb-target']:RemoveTargetEntity(old.entity, old.labels)
        end)
    end
    targets[netId] = nil
end

local function setProp(data)
    if type(data) ~= 'table' or not data.netId then return end
    local netId = key(data.netId)
    if not netId then return end
    if props[netId] and props[netId].objectType ~= data.objectType then
        removeTarget(netId)
    end
    props[netId] = data
end

local function removeProp(data)
    if type(data) ~= 'table' then return end
    local netId = key(data.netId)
    if not netId then return end
    removeTarget(netId)
    props[netId] = nil
end

RegisterNetEvent('blixt-busking:client:syncPlacedProp', function(action, data)
    if action == 'add' then
        setProp(data)
    elseif action == 'remove' then
        removeProp(data)
    elseif action == 'bulk' then
        for _, prop in ipairs(data or {}) do setProp(prop) end
    end
end)

local function pickup(data)
    local netId = key(data.netId)
    if not netId or not props[netId] then return end
    if tonumber(data.owner) ~= GetPlayerServerId(PlayerId()) then return end

    local ok = lib.callback.await('blixt-busking:server:pickupPlacedProp', false, data.objectType, netId)
    if not ok then
        notify('You cannot pick that up.', 'error')
        return
    end

    -- The original syncPlacedProp remove event deletes the object for everyone.
    removeProp(data)
    notify(('%s picked up.'):format(labels[data.objectType] or 'Equipment'), 'success')
end

local function askTip()
    if GetResourceState('qb-input') == 'started' then
        local form = exports['qb-input']:ShowInput({
            header = 'Give Cash Tip',
            submitText = 'Tip',
            inputs = { { text = 'Tip amount ($)', name = 'amount', type = 'number', isRequired = true } }
        })
        return form and form.amount
    end

    local form = lib.inputDialog('Give Cash Tip', {
        { type = 'number', label = 'Tip amount', min = 1, default = 10, required = true }
    })
    return form and form[1]
end

local function tip(data)
    local owner = tonumber(data.owner)
    if not owner or owner == GetPlayerServerId(PlayerId()) or data.objectType ~= 'hat' then return end
    local amount = askTip()
    if amount == nil then return end
    amount = tonumber(amount)
    if not amount or amount < 1 or amount % 1 ~= 0 then
        notify('Enter a whole dollar amount of at least $1.', 'error')
        return
    end

    -- The original server callback alone handles debiting and crediting cash.
    local ok, message = lib.callback.await('blixt-busking:server:tipBuskerPlayer', false, owner, amount)
    if ok then
        notify(('You tipped $%d.'):format(amount), 'success')
    else
        notify(message or 'Tip could not be sent.', 'error')
    end
end

local function isInRange(data, distance)
    local player = PlayerPedId()
    if not DoesEntityExist(player) then return false end
    local entity = findObject(key(data.netId))
    if entity == 0 then return false end
    return #(GetEntityCoords(player) - GetEntityCoords(entity)) <= (distance or 2.0)
end

local function openInteraction(data)
    if not isInRange(data, 2.2) then return end
    local me = GetPlayerServerId(PlayerId())

    if tonumber(data.owner) == me then
        exports['qb-menu']:openMenu({
            { header = labels[data.objectType] or 'Busking Equipment', isMenuHeader = true, params = {} },
            { header = 'Pick up', action = function() pickup(data) end, params = {} }
        })
    elseif data.objectType == 'hat' then
        exports['qb-menu']:openMenu({
            { header = 'Busking Hat', isMenuHeader = true, params = {} },
            { header = 'Give cash tip', action = function() tip(data) end, params = {} }
        })
    end
end

local function installTarget(netId, data)
    if GetResourceState('qb-target') ~= 'started' then return end
    local entity = findObject(netId)
    if entity == 0 then return end

    local old = targets[netId]
    if old and old.entity == entity then return end
    removeTarget(netId)

    local pickupLabel = ('Busking: Pick up %s'):format(labels[data.objectType] or 'Equipment')
    local tipLabel = 'Busking: Give cash tip'
    local options = {
        {
            icon = 'fas fa-hand', label = pickupLabel,
            action = function() if isInRange(data, 2.2) then pickup(data) end end,
            canInteract = function(_, dist)
                return dist <= 2.0 and tonumber(data.owner) == GetPlayerServerId(PlayerId())
            end
        }
    }
    local registeredLabels = { pickupLabel }

    if data.objectType == 'hat' then
        options[#options + 1] = {
            icon = 'fas fa-dollar-sign', label = tipLabel,
            action = function() if isInRange(data, 2.2) then tip(data) end end,
            canInteract = function(_, dist)
                return dist <= 2.0 and tonumber(data.owner) ~= GetPlayerServerId(PlayerId())
            end
        }
        registeredLabels[#registeredLabels + 1] = tipLabel
    end

    local ok = pcall(function()
        exports['qb-target']:AddTargetEntity(entity, { options = options, distance = 2.0 })
    end)
    if ok then targets[netId] = { entity = entity, labels = registeredLabels } end
end

local function drawPrompt(coords, label)
    SetDrawOrigin(coords.x, coords.y, coords.z + 0.25, 0)
    SetTextScale(0.0, 0.32)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextCentre(true)
    SetTextColour(255, 255, 255, 235)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

-- Seed existing props when a player connects or restarts this resource.
CreateThread(function()
    Wait(1600)
    local existing = lib.callback.await('blixt-busking:server:getPlacedProps', false)
    for _, data in ipairs(existing or {}) do setProp(data) end
end)

-- Optional qb-target binds to streamed-in entities; no extra dependency required.
CreateThread(function()
    while true do
        Wait(1200)
        if GetResourceState('ox_target') ~= 'started' then
            for netId, data in pairs(props) do
                if GetResourceState('qb-target') == 'started' then
                    installTarget(netId, data)
                else
                    removeTarget(netId)
                end
            end
        end
    end
end)

-- Without qb-target, E opens a qb-menu for pickup / player cash tips.
CreateThread(function()
    while true do
        local sleep = 600
        if GetResourceState('ox_target') ~= 'started' and GetResourceState('qb-target') ~= 'started' then
            local ped = PlayerPedId()
            if DoesEntityExist(ped) and not IsPedInAnyVehicle(ped, false) and not IsEntityPositionFrozen(ped) then
                local playerCoords = GetEntityCoords(ped)
                local nearest, nearestDist, nearestCoords = nil, 2.0, nil
                for netId, data in pairs(props) do
                    local ent = findObject(netId)
                    if ent ~= 0 then
                        local coords = GetEntityCoords(ent)
                        local dist = #(playerCoords - coords)
                        if dist < nearestDist then
                            local owner = tonumber(data.owner)
                            if owner == GetPlayerServerId(PlayerId()) or data.objectType == 'hat' then
                                nearest, nearestDist, nearestCoords = data, dist, coords
                            end
                        end
                    end
                end
                if nearest then
                    sleep = 0
                    drawPrompt(nearestCoords, '[E] Busking equipment')
                    if IsControlJustReleased(0, 38) then openInteraction(nearest) end
                end
            end
        end
        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for netId in pairs(targets) do removeTarget(netId) end
end)

print('^2[blixt-busking] QB-Core equipment interactions enabled.^0')
