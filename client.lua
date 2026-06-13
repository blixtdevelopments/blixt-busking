local isBusking = false
local isFreestyle = false
local currentSound = nil
local startCoords = nil
local currentEmoteIndex = 1
local currentSong = nil
local currentSongEnded = false
local suppressSongFinishedPrompt = false
local buskingSessionId = 0
local playerProgress = nil
local shopPed = nil
local shopFallbackActive = false
local lastReportedCrowdSize = 0

local placedProps = {}
local registeredPlacementTargets = {}

local placementItems = {
    hat = { item = 'busking_hat', model = `prop_busker_hat_01`, label = 'Busking Hat', multiplier = 1.0, tipTarget = true },
    speaker = { item = 'busking_speaker', model = `prop_speaker_06`, label = 'Speaker', multiplier = 1.2 },
    mic = { item = 'busking_mic', model = `v_club_roc_micstd`, label = 'Mic Stand', multiplier = 1.3 }
}

local placementMaxDistance = 6.0

local reactingPeds = {}
local pedCooldowns = {}
local sessionReactedPeds = {}

local guitarEmotes = { 'guitar', 'guitar2' }
local emoteResourceCandidates = {
    (Config and Config.EmoteResource) or nil,
    'rpe_emotes',
    'rpemotes-reborn-v.2.0.4',
    'rpemotes'
}

math.randomseed(GetGameTimer())

local function notify(description, notifyType)
    if lib and lib.notify then
        lib.notify({
            title = 'Busking',
            description = description,
            type = notifyType or 'inform'
        })
    end
end

local function getNextLevelRequirement(level)
    if not Config.Progression or not Config.Progression.Levels then
        return nil
    end

    return Config.Progression.Levels[(level or 0) + 1]
end

local function getAchievementCount(achievements)
    local count = 0
    for _, unlocked in pairs(achievements or {}) do
        if unlocked then
            count += 1
        end
    end
    return count
end

local function fetchPlayerProgress()
    local data = lib.callback.await('blixt-busking:server:getPlayerProgress', false)
    if data and data.progress then
        playerProgress = data.progress
    end
    return data
end

local function formatProgressDescription(progress)
    progress = progress or playerProgress or {}
    local level = progress.level or 0
    local xp = progress.xp or 0
    local nextLevelXp = progress.nextLevelXp or getNextLevelRequirement(level)
    local achievementCount = getAchievementCount(progress.achievements)

    if nextLevelXp then
        return ('Level %s | XP: %s / %s | Achievements: %s'):format(level, xp, nextLevelXp, achievementCount)
    end

    return ('Level %s | XP: %s | Achievements: %s'):format(level, xp, achievementCount)
end

local function getSongRequiredLevel(song)
    return math.max(0, math.floor(tonumber(song and song.level or 0) or 0))
end

local function isSongUnlocked(song)
    local requiredLevel = getSongRequiredLevel(song)
    local currentLevel = playerProgress and playerProgress.level or 0
    return currentLevel >= requiredLevel, requiredLevel
end

local function openAchievementsMenu()
    local data = fetchPlayerProgress()
    local snapshot = data and data.progress or playerProgress or {}
    local options = {
        {
            title = 'Your Progress',
            description = formatProgressDescription(snapshot),
            readOnly = true
        }
    }

    for _, achievement in ipairs((Config.Progression and Config.Progression.Achievements) or {}) do
        local unlocked = snapshot.achievements and snapshot.achievements[achievement.key]
        options[#options + 1] = {
            title = unlocked and ('✓ %s'):format(achievement.name) or achievement.name,
            description = ('%s (+%s XP)'):format(achievement.description or 'Achievement', achievement.xp or 0),
            disabled = not unlocked
        }
    end

    options[#options + 1] = {
        title = 'Back',
        onSelect = function()
            openBuskingMenu()
        end
    }

    lib.registerContext({
        id = 'blixt_busking_achievements',
        title = 'Achievements',
        options = options
    })

    lib.showContext('blixt_busking_achievements')
end

local function openBuskingShopMenu()
    local data = lib.callback.await('blixt-busking:server:getShopData', false)
    if not data then
        notify('Could not load the busking shop.', 'error')
        return
    end

    playerProgress = data.progress or playerProgress

    local options = {
        {
            title = 'Your Progress',
            description = formatProgressDescription(playerProgress),
            readOnly = true
        }
    }

    for _, entry in ipairs(data.shopItems or {}) do
        local ownedText = (entry.owned and entry.owned > 0) and (' | Owned: %s'):format(entry.owned) or ''
        local description = ('$%s | Unlock Level %s%s'):format(entry.price or 0, entry.requiredLevel or 0, ownedText)
        if entry.description and entry.description ~= '' then
            description = (('%s\n%s'):format(description, entry.description))
        end

        local locked = (playerProgress and playerProgress.level or 0) < (entry.requiredLevel or 0)

        options[#options + 1] = {
            title = locked and ('%s (Locked)'):format(entry.label) or entry.label,
            description = description,
            disabled = locked,
            onSelect = function()
                local ok, message = lib.callback.await('blixt-busking:server:buyShopItem', false, entry.key)
                if ok then
                    notify(message or 'Purchased.', 'success')
                else
                    notify(message or 'Purchase failed.', 'error')
                end
                openBuskingShopMenu()
            end
        }
    end

    lib.registerContext({
        id = 'blixt_busking_shop',
        title = data.shopHeader or 'Busking Supplier',
        options = options
    })

    lib.showContext('blixt_busking_shop')
end

local function loadAnimDict(dict)
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 5000

    while not HasAnimDictLoaded(dict) do
        Wait(0)
        if GetGameTimer() > timeout then
            return false
        end
    end

    return true
end

local function randBetween(rangeTable)
    return math.random(rangeTable.min or 1000, rangeTable.max or 2000)
end

local function showNextSongPrompt()
    if not Config.NextSongPrompt or not Config.NextSongPrompt.enabled then
        return
    end

    CreateThread(function()
        local result = lib.alertDialog({
            header = Config.NextSongPrompt.title or 'Song finished',
            content = Config.NextSongPrompt.content or 'Play another song?',
            centered = true,
            cancel = true,
            labels = {
                confirm = Config.NextSongPrompt.confirm or 'Yes',
                cancel = Config.NextSongPrompt.cancel or 'No'
            }
        })

        if result == 'confirm' then
            Wait(150)
            if not isBusking then
                openBuskingMenu()
            end
        end
    end)
end

local function playAmbientSpeech(ped, speechName)
    if not Config.NPC.voiceEnabled or not speechName or speechName == '' then
        return
    end

    if IsAmbientSpeechPlaying(ped) then
        return
    end

    PlayPedAmbientSpeechNative(ped, speechName, Config.NPC.voiceSpeechParams or 'SPEECH_PARAMS_FORCE_NORMAL_CLEAR')
end

local function getRandomSpeech()
    local speeches = (Config.NPC and Config.NPC.positiveSpeech) or {}
    if #speeches == 0 then return nil end
    return speeches[math.random(#speeches)]
end

local function playReactionEntry(ped, entry)
    if not entry then return end

    ClearPedTasks(ped)

    if entry.type == 'scenario' then
        TaskStartScenarioInPlace(ped, entry.name, 0, true)
        Wait(entry.duration or 2500)
        ClearPedTasks(ped)
        return
    end

    if entry.type == 'anim' and entry.dict and entry.clip then
        if loadAnimDict(entry.dict) then
            TaskPlayAnim(ped, entry.dict, entry.clip, 2.0, 2.0, entry.duration or 2500, entry.flag or 48, 0.0, false, false, false)
            Wait(entry.duration or 2500)
            StopAnimTask(ped, entry.dict, entry.clip, 1.0)
        end
    end
end

local function playPositiveReaction(ped)
    local reactions = (Config.NPC and Config.NPC.positiveReactions) or {}
    if #reactions == 0 then return end

    if math.random(100) <= (Config.NPC.voiceChance or 0) then
        playAmbientSpeech(ped, getRandomSpeech())
    end

    playReactionEntry(ped, reactions[math.random(#reactions)])
end

local function playTipReaction(ped)
    local reaction = Config.NPC.tipReaction
    if not reaction or not reaction.enabled then return end

    if reaction.speech and reaction.speech ~= '' then
        playAmbientSpeech(ped, reaction.speech)
    end

    playReactionEntry(ped, reaction)
end

local function getEmoteResource()
    for _, resourceName in ipairs(emoteResourceCandidates) do
        if resourceName and GetResourceState(resourceName) == 'started' then
            return resourceName
        end
    end

    return nil
end

local function startRpEmote(emoteName)
    local resourceName = getEmoteResource()

    if resourceName then
        local ok = pcall(function()
            exports[resourceName]:EmoteCommandStart(emoteName)
        end)

        if ok then
            return true
        end
    end

    ExecuteCommand(('e %s'):format(emoteName))
    return false
end

local function cancelRpEmote()
    local resourceName = getEmoteResource()

    if resourceName then
        pcall(function()
            exports[resourceName]:EmoteCancel()
        end)
    else
        ExecuteCommand('e c')
    end
end

local function clearPedTracking()
    reactingPeds = {}
    sessionReactedPeds = {}
end


local function getPlacementDataByItem(itemName)
    for objectType, data in pairs(placementItems) do
        if data.item == itemName then
            return objectType, data
        end
    end
end

local function getPlacedProp(objectType)
    return placedProps[objectType]
end

local function isPlacedPropActive(objectType)
    local placed = getPlacedProp(objectType)
    if not placed or not placed.coords then
        return false
    end

    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then
        return false
    end

    return #(GetEntityCoords(ped) - placed.coords) <= placementMaxDistance
end

local function getNpcTipMultiplier()
    if not isPlacedPropActive('hat') then
        return nil
    end

    local hasSpeaker = isPlacedPropActive('speaker')
    local hasMic = isPlacedPropActive('mic')

    if hasSpeaker and hasMic then
        return 1.8
    elseif hasMic then
        return 1.3
    elseif hasSpeaker then
        return 1.2
    end

    return 1.0
end

local function cleanupPlacementTarget(netId)
    if not netId then return end

    local optionNames = registeredPlacementTargets[netId]

    if optionNames and GetResourceState('ox_target') == 'started' then
        pcall(function()
            exports.ox_target:removeEntity(netId, optionNames)
        end)
    end

    registeredPlacementTargets[netId] = nil
end

local function removePlacedPropState(objectType, netId)
    if objectType and placedProps[objectType] and (not netId or placedProps[objectType].netId == netId) then
        placedProps[objectType] = nil
    elseif netId then
        for placedType, data in pairs(placedProps) do
            if data.netId == netId then
                placedProps[placedType] = nil
                break
            end
        end
    end

    cleanupPlacementTarget(netId)
end

local function setPlacedPropState(data)
    if not data or not data.objectType then return end
    if data.owner ~= GetPlayerServerId(PlayerId()) then return end

    placedProps[data.objectType] = {
        netId = data.netId,
        coords = data.coords and vec3(data.coords.x, data.coords.y, data.coords.z) or nil,
        heading = data.heading,
        owner = data.owner,
        model = data.model
    }
end

local function registerPlacedPropTarget(data)
    if not data or not data.netId or GetResourceState('ox_target') ~= 'started' then
        return
    end

    CreateThread(function()
        local netId = tonumber(data.netId) or data.netId

        if registeredPlacementTargets[netId] then
            return
        end

        local optionNames = {
            ('blixt_busking_pickup_%s'):format(netId)
        }

        local options = {
            {
                name = ('blixt_busking_pickup_%s'):format(netId),
                icon = 'fa-solid fa-hand',
                label = 'Pick up',
                distance = 2.0,
                canInteract = function(_, distance)
                    return data.owner == GetPlayerServerId(PlayerId()) and distance <= 2.0
                end,
                onSelect = function()
                    local success = lib.callback.await('blixt-busking:server:pickupPlacedProp', false, data.objectType, netId)
                    if success then
                        local obj = NetworkDoesNetworkIdExist(netId) and NetToObj(netId) or 0
                        if obj and obj ~= 0 and DoesEntityExist(obj) then
                            SetEntityAsMissionEntity(obj, true, true)
                            DeleteEntity(obj)
                        end
                        removePlacedPropState(data.objectType, netId)
                    else
                        notify('You cannot pick that up.', 'error')
                    end
                end
            }
        }

        if data.objectType == 'hat' then
            optionNames[#optionNames + 1] = ('blixt_busking_tip_%s'):format(netId)
            options[#options + 1] = {
                name = ('blixt_busking_tip_%s'):format(netId),
                icon = 'fa-solid fa-dollar-sign',
                label = 'Give cash tip',
                distance = 2.0,
                canInteract = function(_, distance)
                    return data.owner ~= GetPlayerServerId(PlayerId()) and distance <= 2.0
                end,
                onSelect = function()
                    local input = lib.inputDialog('Give Cash Tip', {
                        {
                            type = 'number',
                            label = 'Tip amount',
                            min = 1,
                            default = 10,
                            required = true
                        }
                    })

                    if not input or not input[1] then
                        return
                    end

                    local amount = math.floor(tonumber(input[1]) or 0)
                    if amount < 1 then
                        notify('Enter a valid tip amount.', 'error')
                        return
                    end

                    local ok, message = lib.callback.await('blixt-busking:server:tipBuskerPlayer', false, data.owner, amount)
                    if ok then
                        notify(('You tipped $%s'):format(amount), 'success')
                    elseif message then
                        notify(message, 'error')
                    end
                end
            }
        end

        registeredPlacementTargets[netId] = optionNames
        exports.ox_target:addEntity(netId, options)
    end)
end

local function finalizePlacementObject(objectType, data, coords, heading)
    local model = data.model
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(0) end

    local obj = CreateObjectNoOffset(model, coords.x, coords.y, coords.z, true, true, false)
    if not obj or obj == 0 then
        SetModelAsNoLongerNeeded(model)
        return nil
    end

    SetEntityHeading(obj, heading)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetEntityInvincible(obj, true)
    SetEntityAsMissionEntity(obj, true, true)
    SetEntityDynamic(obj, false)
    ActivatePhysics(obj)
    SetNetworkIdCanMigrate(ObjToNet(obj), true)
    SetNetworkIdExistsOnAllMachines(ObjToNet(obj), true)
    SetModelAsNoLongerNeeded(model)

    return obj
end

local function openPlacementPreview(objectType, data)
    if getPlacedProp(objectType) then
        notify(('%s is already placed.'):format(data.label), 'error')
        return
    end

    local ped = PlayerPedId()
    if not DoesEntityExist(ped) or IsPedInAnyVehicle(ped, false) then
        notify('You cannot place that right now.', 'error')
        return
    end

    local model = data.model
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(0) end

    local pedCoords = GetEntityCoords(ped)
    local forward = GetEntityForwardVector(ped)
    local previewCoords = vec3(pedCoords.x + (forward.x * 1.0), pedCoords.y + (forward.y * 1.0), pedCoords.z - 1.0)
    local heading = GetEntityHeading(ped)

    local preview = CreateObjectNoOffset(model, previewCoords.x, previewCoords.y, previewCoords.z, false, false, false)
    SetEntityCollision(preview, false, false)
    SetEntityAlpha(preview, 170, false)
    FreezeEntityPosition(preview, true)
    PlaceObjectOnGroundProperly(preview)
    SetEntityHeading(preview, heading)

    lib.showTextUI('[W/A/S/D] Move  [Q/E] Rotate  [ENTER] Place  [BACKSPACE] Cancel')

    local moveStep = 0.02
    local rotateStep = 1.25
    local placing = true

    FreezeEntityPosition(ped, true)

    while placing do
        Wait(0)

        DisableControlAction(0, 32, true)
        DisableControlAction(0, 33, true)
        DisableControlAction(0, 34, true)
        DisableControlAction(0, 35, true)
        DisableControlAction(0, 44, true)
        DisableControlAction(0, 38, true)
        DisableControlAction(0, 191, true)
        DisableControlAction(0, 177, true)
        DisableControlAction(0, 21, true)
        DisableControlAction(0, 24, true)
        DisableControlAction(0, 25, true)
        DisableControlAction(0, 140, true)
        DisableControlAction(0, 141, true)
        DisableControlAction(0, 142, true)

        local currentMoveStep = IsDisabledControlPressed(0, 21) and 0.04 or moveStep
        local currentRotateStep = IsDisabledControlPressed(0, 21) and 2.5 or rotateStep
        local camHeading = math.rad(GetGameplayCamRot(0).z)
        local forwardVec = vec3(-math.sin(camHeading), math.cos(camHeading), 0.0)
        local rightVec = vec3(math.cos(camHeading), math.sin(camHeading), 0.0)

        if IsDisabledControlPressed(0, 32) then previewCoords = previewCoords + (forwardVec * currentMoveStep) end
        if IsDisabledControlPressed(0, 33) then previewCoords = previewCoords - (forwardVec * currentMoveStep) end
        if IsDisabledControlPressed(0, 34) then previewCoords = previewCoords - (rightVec * currentMoveStep) end
        if IsDisabledControlPressed(0, 35) then previewCoords = previewCoords + (rightVec * currentMoveStep) end
        if IsDisabledControlPressed(0, 44) then heading = heading - currentRotateStep end
        if IsDisabledControlPressed(0, 38) then heading = heading + currentRotateStep end

        SetEntityCoordsNoOffset(preview, previewCoords.x, previewCoords.y, previewCoords.z, false, false, false)
        SetEntityHeading(preview, heading)
        PlaceObjectOnGroundProperly(preview)
        previewCoords = GetEntityCoords(preview)

        if IsDisabledControlJustPressed(0, 191) then
            placing = false

            local finalCoords = GetEntityCoords(preview)
            DeleteEntity(preview)
            lib.hideTextUI()
            FreezeEntityPosition(ped, false)

            local obj = finalizePlacementObject(objectType, data, finalCoords, heading)
            if not obj then
                notify('Failed to place item.', 'error')
                break
            end

            local netId = ObjToNet(obj)
            local success = lib.callback.await('blixt-busking:server:placeProp', false, objectType, netId, {
                x = finalCoords.x,
                y = finalCoords.y,
                z = finalCoords.z
            }, heading)

            if success then
                local state = {
                    objectType = objectType,
                    netId = netId,
                    coords = { x = finalCoords.x, y = finalCoords.y, z = finalCoords.z },
                    heading = heading,
                    owner = GetPlayerServerId(PlayerId()),
                    model = data.model
                }
                setPlacedPropState(state)
                registerPlacedPropTarget(state)
            else
                SetEntityAsMissionEntity(obj, true, true)
                DeleteEntity(obj)
                notify('You do not have that item.', 'error')
            end
        elseif IsDisabledControlJustPressed(0, 177) then
            placing = false
            DeleteEntity(preview)
            lib.hideTextUI()
            FreezeEntityPosition(ped, false)
        end
    end

    if DoesEntityExist(preview) then
        DeleteEntity(preview)
    end

    FreezeEntityPosition(ped, false)
    lib.hideTextUI()
    SetModelAsNoLongerNeeded(model)
end

RegisterNetEvent('blixt-busking:client:syncPlacedProp', function(action, data)
    if action == 'add' then
        setPlacedPropState(data)
        registerPlacedPropTarget(data)
    elseif action == 'remove' then
        if data and data.netId then
            local obj = NetworkDoesNetworkIdExist(data.netId) and NetToObj(data.netId) or 0
            if obj and obj ~= 0 and DoesEntityExist(obj) then
                SetEntityAsMissionEntity(obj, true, true)
                DeleteEntity(obj)
            end
        end
        removePlacedPropState(data and data.objectType or nil, data and data.netId or nil)
    elseif action == 'bulk' then
        for _, entry in ipairs(data or {}) do
            setPlacedPropState(entry)
            registerPlacedPropTarget(entry)
        end
    end
end)


RegisterNetEvent('blixt-busking:useBuskingHat', function()
    local ok, message = lib.callback.await('blixt-busking:server:canUseItem', false, 'busking_hat')
    if not ok then
        notify(message or 'You cannot use that yet.', 'error')
        return
    end
    openPlacementPreview('hat', placementItems.hat)
end)

RegisterNetEvent('blixt-busking:useBuskingSpeaker', function()
    local ok, message = lib.callback.await('blixt-busking:server:canUseItem', false, 'busking_speaker')
    if not ok then
        notify(message or 'You cannot use that yet.', 'error')
        return
    end
    openPlacementPreview('speaker', placementItems.speaker)
end)

RegisterNetEvent('blixt-busking:useBuskingMic', function()
    local ok, message = lib.callback.await('blixt-busking:server:canUseItem', false, 'busking_mic')
    if not ok then
        notify(message or 'You cannot use that yet.', 'error')
        return
    end
    openPlacementPreview('mic', placementItems.mic)
end)

RegisterNetEvent('blixt-busking:usePlacementItem', function(itemName)
    if type(itemName) == 'table' then
        itemName = itemName.data or itemName.name
    end

    local objectType, data = getPlacementDataByItem(itemName)
    if not objectType or not data then
        return
    end

    openPlacementPreview(objectType, data)
end)


RegisterNetEvent('blixt-busking:client:playSound', function(id, url, coords, volume, range)
    if not id or not url or not coords then return end

    if exports.xsound:soundExists(id) then
        exports.xsound:Destroy(id)
    end

    exports.xsound:PlayUrlPos(id, url, volume, coords, false)
    exports.xsound:Distance(id, range)
end)

RegisterNetEvent('blixt-busking:client:updateSoundPosition', function(id, coords)
    if not id or not coords then return end
    if not exports.xsound:soundExists(id) then return end

    exports.xsound:Position(id, coords)
end)

RegisterNetEvent('blixt-busking:client:stopSound', function(id)
    if not id then return end
    if not exports.xsound:soundExists(id) then return end

    exports.xsound:Destroy(id)
end)

local function stopBusking(promptForNextSong)
    suppressSongFinishedPrompt = not promptForNextSong

    if currentSound then
        TriggerServerEvent('blixt-busking:server:stopSound', currentSound)
    end

    local completedSong = currentSongEnded and not isFreestyle and currentSong ~= nil
    local crowdSize = 0
    for ped, active in pairs(reactingPeds) do
        if active and DoesEntityExist(ped) then
            crowdSize += 1
        end
    end

    if completedSong then
        TriggerServerEvent('blixt-busking:server:songCompleted', crowdSize)
    end

    currentSound = nil
    isBusking = false
    isFreestyle = false
    startCoords = nil
    currentEmoteIndex = 1
    currentSong = nil
    currentSongEnded = false
    lastReportedCrowdSize = 0

    clearPedTracking()
    cancelRpEmote()
    TriggerServerEvent('blixt-busking:server:setBuskingState', false)

    if promptForNextSong and Config.NextSongPrompt and Config.NextSongPrompt.enabled then
        showNextSongPrompt()
    end
end

local function playCurrentBuskingEmote()
    if isFreestyle then
        startRpEmote('guitar')
        return
    end

    startRpEmote(guitarEmotes[currentEmoteIndex])
end

local function isPedEligible(ped, playerPed, playerCoords)
    if not DoesEntityExist(ped) then return false end
    if ped == playerPed then return false end
    if IsPedAPlayer(ped) then return false end
    if IsEntityDead(ped) then return false end
    if IsPedInAnyVehicle(ped, true) then return false end
    if not IsPedHuman(ped) then return false end
    if IsPedFleeing(ped) or IsPedRunning(ped) or IsPedSprinting(ped) then return false end
    if IsPedInCombat(ped, playerPed) then return false end
    if IsPedRagdoll(ped) then return false end
    if IsPedFatallyInjured(ped) then return false end
    if reactingPeds[ped] then return false end
    if Config.NPC.oneReactionPerSession and sessionReactedPeds[ped] then return false end

    local cooldownUntil = pedCooldowns[ped] or 0
    if cooldownUntil >= GetGameTimer() then return false end

    local pedCoords = GetEntityCoords(ped)
    local dist = #(pedCoords - playerCoords)
    if dist > Config.NPC.radius then return false end
    if dist < (Config.NPC.minApproachDistance or 4.0) then return false end

    local model = GetEntityModel(ped)
    if model == `s_m_y_cop_01` or model == `s_f_y_cop_01` then
        return false
    end

    return true
end

local function countReactingPeds()
    local count = 0
    for ped, active in pairs(reactingPeds) do
        if active and DoesEntityExist(ped) then
            count += 1
        end
    end
    return count
end

local function getEligibleNearbyPeds()
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local peds = GetGamePool('CPed')
    local nearby = {}

    for i = 1, #peds do
        local ped = peds[i]
        if isPedEligible(ped, playerPed, playerCoords) then
            nearby[#nearby + 1] = ped
        end
    end

    return nearby
end

local function claimPedForReaction(ped)
    if not DoesEntityExist(ped) then
        return false
    end

    if reactingPeds[ped] then
        return false
    end

    if Config.NPC.oneReactionPerSession and sessionReactedPeds[ped] then
        return false
    end

    reactingPeds[ped] = true
    pedCooldowns[ped] = GetGameTimer() + (Config.NPC.tipCooldownPerPed or 180000)

    if Config.NPC.oneReactionPerSession then
        sessionReactedPeds[ped] = true
    end

    return true
end

local function releasePedReaction(ped)
    reactingPeds[ped] = nil
end

local function getLeaveCoords(playerCoords, pedCoords)
    local dx = pedCoords.x - playerCoords.x
    local dy = pedCoords.y - playerCoords.y
    local length = math.sqrt((dx * dx) + (dy * dy))

    if length < 0.001 then
        dx, dy, length = 1.0, 0.0, 1.0
    end

    dx = dx / length
    dy = dy / length

    return vec3(
        pedCoords.x + (dx * (Config.NPC.leaveDistance or 16.0)),
        pedCoords.y + (dy * (Config.NPC.leaveDistance or 16.0)),
        pedCoords.z
    )
end

local function sendPedAwayFromBusker(ped, playerPed)
    if not DoesEntityExist(ped) or not DoesEntityExist(playerPed) then
        return
    end

    local playerCoords = GetEntityCoords(playerPed)
    local pedCoords = GetEntityCoords(ped)
    local leaveCoords = getLeaveCoords(playerCoords, pedCoords)

    ClearPedTasks(ped)
    TaskGoStraightToCoord(ped, leaveCoords.x, leaveCoords.y, leaveCoords.z, Config.NPC.leaveSpeed or 1.2, -1, 0.0, 0.0)

    local timeoutAt = GetGameTimer() + 9000

    while DoesEntityExist(ped) and GetGameTimer() < timeoutAt do
        Wait(500)

        local currentCoords = GetEntityCoords(ped)
        if #(currentCoords - playerCoords) >= ((Config.NPC.radius or 22.0) + 2.0) then
            break
        end
    end

    if DoesEntityExist(ped) then
        TaskWanderStandard(ped, 10.0, 10)
    end
end

local function keepPedEngaged(ped, playerPed)
    local lingerUntil = GetGameTimer() + randBetween(Config.NPC.lingerTime)
    local tipped = false

    while isBusking and DoesEntityExist(ped) and DoesEntityExist(playerPed) and GetGameTimer() < lingerUntil do
        local playerCoords = GetEntityCoords(playerPed)
        local pedCoords = GetEntityCoords(ped)

        if #(pedCoords - playerCoords) > (Config.NPC.watchRadius or 2.8) + 1.5 then
            TaskGoStraightToCoord(ped, playerCoords.x, playerCoords.y, playerCoords.z, 1.0, 1500, 0.0, 0.0)
            Wait(1200)
        end

        TaskTurnPedToFaceEntity(ped, playerPed, randBetween(Config.NPC.reactionSpacing))

        playPositiveReaction(ped)

        if not tipped and math.random(100) <= (Config.NPC.tipChance or 60) then
            local propMultiplier = getNpcTipMultiplier()

            if propMultiplier then
                playTipReaction(ped)

                local baseMultiplier = isFreestyle and Config.Freestyle.tipMultiplier or ((currentSong and currentSong.tipMultiplier) or 1.0)
                TriggerServerEvent('blixt-busking:server:npcTip', baseMultiplier * propMultiplier, isFreestyle)
                notify('You received a tip!', 'success')
                tipped = true
            end
        end

        Wait(randBetween(Config.NPC.reactionSpacing))
    end
end

local function handleReactingPed(ped)
    if not claimPedForReaction(ped) then
        return
    end

    local playerPed = PlayerPedId()
    local timeoutAt = GetGameTimer() + (Config.NPC.approachTimeout or 12000)
    local targetOffset = GetOffsetFromEntityInWorldCoords(playerPed, math.random(-30, 30) / 100.0, 1.7 + math.random() * 0.9, 0.0)

    ClearPedTasks(ped)
    TaskGoStraightToCoord(ped, targetOffset.x, targetOffset.y, targetOffset.z, 1.0, -1, 0.0, 0.0)

    while isBusking and DoesEntityExist(ped) and GetGameTimer() < timeoutAt do
        Wait(500)

        if not DoesEntityExist(playerPed) then
            break
        end

        local playerCoords = GetEntityCoords(playerPed)
        local pedCoords = GetEntityCoords(ped)

        if #(pedCoords - playerCoords) <= (Config.NPC.watchRadius or 2.8) + 0.4 then
            TaskTurnPedToFaceEntity(ped, playerPed, 1200)
            Wait(900)

            keepPedEngaged(ped, playerPed)
            break
        end
    end

    if DoesEntityExist(ped) and DoesEntityExist(playerPed) then
        sendPedAwayFromBusker(ped, playerPed)
    end

    releasePedReaction(ped)
end

local function startNPCThread(sessionId)
    if not Config.NPC.enabled then return end

    CreateThread(function()
        while isBusking and buskingSessionId == sessionId do
            Wait(Config.NPC.scanInterval)

            if not isBusking or buskingSessionId ~= sessionId then break end

            local currentCrowd = countReactingPeds()
            if currentCrowd > lastReportedCrowdSize then
                lastReportedCrowdSize = currentCrowd
                TriggerServerEvent('blixt-busking:server:updateCrowdSize', currentCrowd)
            end

            if currentCrowd >= Config.NPC.maxReactingPeds then goto continue end

            local nearby = getEligibleNearbyPeds()
            if #nearby == 0 then goto continue end

            for i = 1, #nearby do
                if countReactingPeds() >= Config.NPC.maxReactingPeds then
                    break
                end

                local ped = nearby[i]
                if math.random(100) <= (Config.NPC.approachChance or 30) then
                    CreateThread(function()
                        handleReactingPed(ped)
                    end)
                end
            end

            ::continue::
        end
    end)
end

local function getPlayerSongGender()
    local model = GetEntityModel(PlayerPedId())

    if model == `mp_m_freemode_01` then
        return 'male'
    elseif model == `mp_f_freemode_01` then
        return 'female'
    end

    return nil
end

local function getInstrumentalSongs()
    return (Config.Songs and Config.Songs.instrumentals) or {}
end

local function getVocalSongsForPlayer()
    local vocals = (Config.Songs and Config.Songs.vocals) or {}
    local gender = getPlayerSongGender()

    if gender and vocals[gender] then
        return vocals[gender], gender
    end

    local fallback = {}

    if vocals.male then
        for i = 1, #vocals.male do
            fallback[#fallback + 1] = vocals.male[i]
        end
    end

    if vocals.female then
        for i = 1, #vocals.female do
            fallback[#fallback + 1] = vocals.female[i]
        end
    end

    return fallback, gender
end

local function openSongListMenu(menuId, title, songs)
    local options = {}

    for i = 1, #songs do
        local song = songs[i]
        local unlocked, requiredLevel = isSongUnlocked(song)
        options[#options + 1] = {
            title = unlocked and song.label or ('%s (Locked)'):format(song.label),
            description = unlocked and 'Unlocked' or ('Requires Busker Level %s'):format(requiredLevel),
            disabled = not unlocked,
            onSelect = function()
                startBusking(song, false)
            end
        }
    end

    options[#options + 1] = {
        title = 'Back',
        onSelect = function()
            openBuskingMenu()
        end
    }

    lib.registerContext({
        id = menuId,
        title = title,
        options = options
    })

    lib.showContext(menuId)
end

function openBuskingMenu()
    if isBusking then
        stopBusking(false)
        return
    end

    local data = fetchPlayerProgress()
    if data and data.progress then
        playerProgress = data.progress
    end

    local options = {
        {
            title = 'Your Progress',
            description = formatProgressDescription(playerProgress),
            readOnly = true
        },
        {
            title = 'Achievements',
            description = ('Unlocked: %s'):format(getAchievementCount(playerProgress and playerProgress.achievements or {})),
            onSelect = function()
                openAchievementsMenu()
            end
        }
    }

    local instrumentals = getInstrumentalSongs()
    local vocals, gender = getVocalSongsForPlayer()

    if #instrumentals > 0 then
        options[#options + 1] = {
            title = 'Instrumentals',
            description = ('%s song%s'):format(#instrumentals, #instrumentals == 1 and '' or 's'),
            onSelect = function()
                openSongListMenu('blixt_busking_instrumentals', 'Instrumentals', instrumentals)
            end
        }
    end

    if #vocals > 0 then
        local vocalsTitle = 'Vocals'
        if gender == 'male' then
            vocalsTitle = 'Vocals (Male)'
        elseif gender == 'female' then
            vocalsTitle = 'Vocals (Female)'
        end

        options[#options + 1] = {
            title = vocalsTitle,
            description = ('%s song%s'):format(#vocals, #vocals == 1 and '' or 's'),
            onSelect = function()
                openSongListMenu('blixt_busking_vocals', vocalsTitle, vocals)
            end
        }
    end

    if Config.Freestyle.enabled then
        options[#options + 1] = {
            title = 'Freestyle',
            description = 'Jam without a track.',
            onSelect = function()
                startBusking(nil, true)
            end
        }
    end

    lib.registerContext({
        id = 'blixt_busking_menu',
        title = 'Busking',
        options = options
    })

    lib.showContext('blixt_busking_menu')
end

local function registerSongEndHook(soundId, sessionId)
    if not soundId then return end

    CreateThread(function()
        local timeout = GetGameTimer() + 5000

        while isBusking and currentSound == soundId and buskingSessionId == sessionId do
            if exports.xsound:soundExists(soundId) then
                local ok = pcall(function()
                    exports.xsound:onPlayEnd(soundId, function()
                        if isBusking and currentSound == soundId and buskingSessionId == sessionId and not suppressSongFinishedPrompt then
                            currentSongEnded = true
                            stopBusking(true)
                        end
                    end)
                end)

                if ok then
                    return
                end
            end

            if GetGameTimer() > timeout then
                break
            end

            Wait(100)
        end
    end)
end

local function registerSongEndWatcher(soundId, sessionId)
    if not soundId then return end

    CreateThread(function()
        local waitedForDuration = false

        while isBusking and currentSound == soundId and buskingSessionId == sessionId do
            Wait(1000)

            if not exports.xsound:soundExists(soundId) then
                break
            end

            local maxDuration = exports.xsound:getMaxDuration(soundId)
            local timeStamp = exports.xsound:getTimeStamp(soundId)

            if maxDuration and maxDuration > 0 and timeStamp and timeStamp >= 0 then
                waitedForDuration = true

                if timeStamp >= (maxDuration - 0.75) then
                    if isBusking and currentSound == soundId and buskingSessionId == sessionId and not suppressSongFinishedPrompt then
                        currentSongEnded = true
                        stopBusking(true)
                    end
                    break
                end
            end
        end

        if not waitedForDuration then
            -- fallback: if xSound never reports duration, do nothing rather than guessing
        end
    end)
end

function startBusking(song, freestyle)
    local ped = PlayerPedId()

    if isBusking then
        stopBusking(false)
        Wait(150)
    end

    buskingSessionId += 1
    suppressSongFinishedPrompt = false
    currentSongEnded = false
    isBusking = true
    isFreestyle = freestyle == true
    startCoords = GetEntityCoords(ped)
    currentSound = nil
    currentEmoteIndex = 1
    currentSong = song

    playCurrentBuskingEmote()

    if not isFreestyle and song and song.url and song.url ~= '' then
        local soundId = ('busking_%s_%s'):format(GetPlayerServerId(PlayerId()), buskingSessionId)
        currentSound = soundId

        TriggerServerEvent('blixt-busking:server:playSound', soundId, song.url, startCoords, song.volume or Config.DefaultVolume, song.range or Config.AudioRange)
        registerSongEndHook(soundId, buskingSessionId)
        registerSongEndWatcher(soundId, buskingSessionId)
    end

    TriggerServerEvent('blixt-busking:server:setBuskingState', true)
    startNPCThread(buskingSessionId)

    CreateThread(function()
        local sessionId = buskingSessionId
        local nextAnimSwitch = GetGameTimer() + math.random(6000, 10000)

        while isBusking and buskingSessionId == sessionId do
            Wait(500)

            ped = PlayerPedId()

            if not DoesEntityExist(ped) then
                stopBusking(false)
                break
            end

            local coords = GetEntityCoords(ped)

            if currentSound then
                TriggerServerEvent('blixt-busking:server:updateSoundPosition', currentSound, coords)
            end

            if not isFreestyle and GetGameTimer() >= nextAnimSwitch then
                currentEmoteIndex = currentEmoteIndex == 1 and 2 or 1
                playCurrentBuskingEmote()
                nextAnimSwitch = GetGameTimer() + math.random(6000, 10000)
            end

            if Config.RequireStill and startCoords and #(coords - startCoords) > Config.MaxMovement then
                stopBusking(false)
                break
            end

            if IsPedInAnyVehicle(ped, false) or IsEntityDead(ped) or IsPedRagdoll(ped) then
                stopBusking(false)
                break
            end
        end
    end)
end

RegisterNetEvent('blixt-busking:useGuitar', function()
    local ok, message = lib.callback.await('blixt-busking:server:canUseItem', false, 'guitar')
    if not ok then
        notify(message or 'You cannot use that yet.', 'error')
        return
    end
    openBuskingMenu()
end)

CreateThread(function()
    Wait(1000)
    local existing = lib.callback.await('blixt-busking:server:getPlacedProps', false)
    if existing then
        TriggerEvent('blixt-busking:client:syncPlacedProp', 'bulk', existing)
    end

    fetchPlayerProgress()
end)

RegisterNetEvent('blixt-busking:client:updateProgress', function(progress)
    if progress then
        playerProgress = progress
    end
end)

RegisterNetEvent('blixt-busking:client:levelUp', function(data)
    if data then
        if not playerProgress then playerProgress = {} end
        playerProgress.level = data.newLevel or playerProgress.level or 0
        playerProgress.xp = data.xp or playerProgress.xp or 0
        playerProgress.nextLevelXp = data.nextLevelXp
    end

    notify(('Busker Level Up! You are now Level %s.'):format(data and data.newLevel or '?'), 'success')
end)

RegisterNetEvent('blixt-busking:client:achievementUnlocked', function(data)
    if not data then return end
    if not playerProgress then playerProgress = { achievements = {} } end
    playerProgress.achievements = playerProgress.achievements or {}
    playerProgress.achievements[data.key] = true

    lib.notify({
        title = 'Achievement Unlocked!',
        description = (('%s\n+%s XP'):format(data.name or 'Achievement', data.xp or 0)),
        type = 'success',
        duration = 7000
    })
end)

local function createShopPed()
    if not Config.Shop or not Config.Shop.Ped then return end
    local pedData = Config.Shop.Ped
    local model = pedData.model
    if not model then return end

    RequestModel(model)
    while not HasModelLoaded(model) do
        Wait(0)
    end

    if shopPed and DoesEntityExist(shopPed) then
        DeleteEntity(shopPed)
        shopPed = nil
    end

    shopPed = CreatePed(4, model, pedData.coords.x, pedData.coords.y, pedData.coords.z - 1.0, pedData.coords.w, false, true)
    SetEntityInvincible(shopPed, true)
    FreezeEntityPosition(shopPed, true)
    SetBlockingOfNonTemporaryEvents(shopPed, true)

    if pedData.scenario and pedData.scenario ~= '' then
        TaskStartScenarioInPlace(shopPed, pedData.scenario, 0, true)
    end

    if GetResourceState('ox_target') == 'started' then
        exports.ox_target:addLocalEntity(shopPed, {
            {
                name = 'blixt_busking_shop',
                icon = 'fa-solid fa-guitar',
                label = 'Open Busking Shop',
                distance = 2.0,
                onSelect = function()
                    openBuskingShopMenu()
                end
            },
            {
                name = 'blixt_busking_progress',
                icon = 'fa-solid fa-star',
                label = 'View Busking Progress',
                distance = 2.0,
                onSelect = function()
                    openBuskingMenu()
                end
            }
        })
        return
    end

    if shopFallbackActive then return end
    shopFallbackActive = true

    CreateThread(function()
        while shopPed and DoesEntityExist(shopPed) do
            local playerCoords = GetEntityCoords(PlayerPedId())
            local pedCoords = GetEntityCoords(shopPed)
            local distance = #(playerCoords - pedCoords)

            if distance <= 2.0 then
                lib.showTextUI('[E] Open Busking Shop')
                if IsControlJustReleased(0, 38) then
                    openBuskingShopMenu()
                end
            else
                lib.hideTextUI()
            end

            Wait(distance <= 2.5 and 0 or 500)
        end

        lib.hideTextUI()
        shopFallbackActive = false
    end)
end

CreateThread(function()
    Wait(1500)
    createShopPed()
end)

RegisterCommand('busk', function()
    openBuskingMenu()
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    FreezeEntityPosition(PlayerPedId(), false)
    stopBusking(false)

    if shopPed and DoesEntityExist(shopPed) then
        DeleteEntity(shopPed)
        shopPed = nil
    end

    for objectType, data in pairs(placedProps) do
        if data and data.netId then
            local obj = NetworkDoesNetworkIdExist(data.netId) and NetToObj(data.netId) or 0
            if obj and obj ~= 0 and DoesEntityExist(obj) then
                SetEntityAsMissionEntity(obj, true, true)
                DeleteEntity(obj)
            end
            removePlacedPropState(objectType, data.netId)
        end
    end
end)
