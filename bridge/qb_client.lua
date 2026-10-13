-- QB-Core replacements for the small set of ox_lib features this resource uses.
if GetResourceState('qbx_core') == 'started' or GetResourceState('qb-core') ~= 'started' then return end

local QBCore = exports['qb-core']:GetCoreObject()
local nextId = 0
local pending = {}
local textUI

lib.callback = {}

function lib.callback.await(name, _, ...)
    nextId = nextId + 1
    local requestId = nextId
    local deferred = promise.new()
    pending[requestId] = deferred

    TriggerServerEvent('blixt-busking:bridge:request', requestId, name, table.pack(...))

    SetTimeout(30000, function()
        if pending[requestId] ~= deferred then return end
        pending[requestId] = nil
        print(('[blixt-busking] Callback timed out: %s'):format(name))
        deferred:resolve({ n = 0 })
    end)

    local result = Citizen.Await(deferred)
    return table.unpack(result, 1, result.n or #result)
end

RegisterNetEvent('blixt-busking:bridge:response', function(requestId, result)
    local deferred = pending[requestId]
    if not deferred then return end
    pending[requestId] = nil
    deferred:resolve(result or { n = 0 })
end)

function lib.notify(data)
    if type(data) ~= 'table' then return end
    local text = tostring(data.description or '')
    if data.title and data.title ~= 'Busking' then
        text = ('%s: %s'):format(data.title, text)
    end
    local notifyType = data.type == 'inform' and 'primary' or (data.type or 'primary')
    QBCore.Functions.Notify(text, notifyType, math.floor(tonumber(data.duration) or 5000))
end

-- Original server events use this name for player-to-player tip notifications.
RegisterNetEvent('ox_lib:notify', function(data)
    lib.notify(data)
end)

function lib.showTextUI(message)
    textUI = tostring(message or '')
end

function lib.hideTextUI()
    textUI = nil
end

CreateThread(function()
    while true do
        if textUI then
            Wait(0)
            SetTextFont(4)
            SetTextScale(0.0, 0.33)
            SetTextCentre(true)
            SetTextColour(255, 255, 255, 255)
            SetTextOutline()
            BeginTextCommandDisplayText('STRING')
            AddTextComponentSubstringPlayerName(textUI)
            EndTextCommandDisplayText(0.5, 0.92)
        else
            Wait(250)
        end
    end
end)

function lib.inputDialog(title, fields)
    local field = fields and fields[1]
    if not field then return nil end

    local value
    if GetResourceState('qb-input') == 'started' then
        local result = exports['qb-input']:ShowInput({
            header = title,
            submitText = 'Confirm',
            inputs = {{
                text = field.label or 'Amount',
                name = 'value',
                type = field.type == 'number' and 'number' or 'text',
                isRequired = field.required == true,
                default = field.default
            }}
        })
        value = result and result.value
    else
        AddTextEntry('BLIXT_BUSKING_INPUT', field.label or title or 'Enter amount')
        DisplayOnscreenKeyboard(1, 'BLIXT_BUSKING_INPUT', '', tostring(field.default or ''), '', '', '', 12)
        while UpdateOnscreenKeyboard() == 0 do Wait(0) end
        if UpdateOnscreenKeyboard() == 1 then
            value = GetOnscreenKeyboardResult()
        end
    end

    if value == nil or value == '' then return nil end
    if field.type == 'number' then value = tonumber(value) end
    if value == nil then return nil end
    return { value }
end

print('^2[blixt-busking] QB-Core callbacks, notifications, input and text UI ready.^0')
