local activeBuskers = {}
local placedProps = {}
local progressCache = {}

local placementDefinitions = {
    hat = { item = 'busking_hat', model = `prop_busker_hat_01` },
    speaker = { item = 'busking_speaker', model = `prop_speaker_06` },
    mic = { item = 'busking_mic', model = `v_club_roc_micstd` }
}

local achievementMap = {}
for _, achievement in ipairs((Config.Progression and Config.Progression.Achievements) or {}) do
    achievementMap[achievement.key] = achievement
end

local function encodeAchievements(achievements)
    return json.encode(achievements or {})
end

local function decodeAchievements(value)
    if type(value) == 'table' then
        return value
    end

    if type(value) ~= 'string' or value == '' then
        return {}
    end

    local ok, data = pcall(json.decode, value)
    if ok and type(data) == 'table' then
        return data
    end

    return {}
end

local function getPlayer(source)
    if GetResourceState('qbx_core') == 'started' then
        local ok, player = pcall(function()
            return exports.qbx_core:GetPlayer(source)
        end)

        if ok and player then
            return player, 'qbx'
        end
    end

    if GetResourceState('qb-core') == 'started' then
        local QBCore = exports['qb-core']:GetCoreObject()
        local player = QBCore.Functions.GetPlayer(source)
        if player then
            return player, 'qb'
        end
    end

    return nil, nil
end

local function getCitizenId(source)
    local player = getPlayer(source)
    if not player then return nil end

    if player.PlayerData and player.PlayerData.citizenid then
        return player.PlayerData.citizenid
    end

    if player.PlayerData and player.PlayerData.charinfo and player.PlayerData.charinfo.citizenid then
        return player.PlayerData.charinfo.citizenid
    end

    if player.PlayerData and player.PlayerData.license then
        return player.PlayerData.license
    end

    return nil
end

local function removeItem(source, itemName, amount)
    amount = amount or 1

    if GetResourceState('ox_inventory') == 'started' then
        return exports.ox_inventory:RemoveItem(source, itemName, amount) == true
    end

    local player = getPlayer(source)
    if player and player.Functions and player.Functions.RemoveItem then
        return player.Functions.RemoveItem(itemName, amount) == true
    end

    return false
end

local function addItem(source, itemName, amount)
    amount = amount or 1

    if GetResourceState('ox_inventory') == 'started' then
        return exports.ox_inventory:AddItem(source, itemName, amount) == true
    end

    local player = getPlayer(source)
    if player and player.Functions and player.Functions.AddItem then
        return player.Functions.AddItem(itemName, amount) == true
    end

    return false
end

local function getItemCount(source, itemName)
    if GetResourceState('ox_inventory') == 'started' then
        return exports.ox_inventory:GetItemCount(source, itemName) or 0
    end

    local player = getPlayer(source)
    if player and player.Functions and player.Functions.GetItemByName then
        local item = player.Functions.GetItemByName(itemName)
        return item and item.amount or 0
    end

    return 0
end

local function getCash(source)
    local player = getPlayer(source)
    if not player then return 0 end

    if player.PlayerData and player.PlayerData.money then
        return tonumber(player.PlayerData.money[Config.Payouts.cashType] or 0) or 0
    end

    return 0
end

local function removeCash(source, amount)
    if amount <= 0 then return false end

    local player = getPlayer(source)
    if player and player.Functions and player.Functions.RemoveMoney then
        return player.Functions.RemoveMoney(Config.Payouts.cashType, amount, 'blixt-busking-tip') == true
    end

    return false
end

local function addCash(source, amount)
    if amount <= 0 then
        return false
    end

    local player = getPlayer(source)
    if player and player.Functions and player.Functions.AddMoney then
        player.Functions.AddMoney(Config.Payouts.cashType, amount, 'blixt-busking')
        return true
    end

    return false
end

local function getOwnedProp(source, objectType)
    for netId, entry in pairs(placedProps) do
        if entry.owner == source and entry.objectType == objectType then
            return netId, entry
        end
    end
end

local function getOwnersHat(source)
    local _, entry = getOwnedProp(source, 'hat')
    return entry
end

local function getPlacedPropsList()
    local result = {}

    for netId, entry in pairs(placedProps) do
        result[#result + 1] = {
            objectType = entry.objectType,
            owner = entry.owner,
            netId = netId,
            coords = entry.coords,
            heading = entry.heading,
            model = entry.model
        }
    end

    return result
end

local function removePlacedPropByOwner(source)
    local removed = {}

    for netId, entry in pairs(placedProps) do
        if entry.owner == source then
            removed[#removed + 1] = { objectType = entry.objectType, netId = netId }
            placedProps[netId] = nil
        end
    end

    for i = 1, #removed do
        TriggerClientEvent('blixt-busking:client:syncPlacedProp', -1, 'remove', removed[i])
    end
end

local function getLevelFromXP(xp)
    local level = 0
    local levels = (Config.Progression and Config.Progression.Levels) or {}

    for i = 0, 5 do
        if xp >= (levels[i] or math.huge) then
            level = i
        end
    end

    return level
end

local function getNextLevelXp(level)
    local levels = (Config.Progression and Config.Progression.Levels) or {}
    return levels[level + 1]
end

local function sanitizeProgress(row)
    local xp = math.max(0, tonumber(row and row.xp or 0) or 0)
    local level = getLevelFromXP(xp)

    return {
        xp = xp,
        level = level,
        songs_completed = math.max(0, tonumber(row and row.songs_completed or 0) or 0),
        best_crowd = math.max(0, tonumber(row and row.best_crowd or 0) or 0),
        achievements = decodeAchievements(row and row.achievements or nil)
    }
end

local function saveProgress(citizenId, progress)
    if not citizenId or not MySQL then return end

    MySQL.update.await([[
        INSERT INTO busking_progress (citizenid, xp, level, songs_completed, best_crowd, achievements)
        VALUES (?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            xp = VALUES(xp),
            level = VALUES(level),
            songs_completed = VALUES(songs_completed),
            best_crowd = VALUES(best_crowd),
            achievements = VALUES(achievements)
    ]], {
        citizenId,
        progress.xp,
        progress.level,
        progress.songs_completed,
        progress.best_crowd,
        encodeAchievements(progress.achievements)
    })
end

local function getProgress(source)
    local citizenId = getCitizenId(source)
    if not citizenId then
        return nil, nil
    end

    if progressCache[citizenId] then
        return progressCache[citizenId], citizenId
    end

    local row = nil
    if MySQL then
        row = MySQL.single.await('SELECT xp, level, songs_completed, best_crowd, achievements FROM busking_progress WHERE citizenid = ?', { citizenId })
    end

    local progress = sanitizeProgress(row)
    progressCache[citizenId] = progress

    if not row and MySQL then
        saveProgress(citizenId, progress)
    end

    return progress, citizenId
end

local function pushProgressUpdate(source, progress)
    if not progress then return end

    TriggerClientEvent('blixt-busking:client:updateProgress', source, {
        xp = progress.xp,
        level = progress.level,
        songs_completed = progress.songs_completed,
        best_crowd = progress.best_crowd,
        achievements = progress.achievements,
        nextLevelXp = getNextLevelXp(progress.level)
    })
end

local function awardAchievement(source, progress, citizenId, key)
    if not key or not progress or not citizenId then
        return false
    end

    if progress.achievements[key] then
        return false
    end

    local achievement = achievementMap[key]
    if not achievement then
        return false
    end

    progress.achievements[key] = true
    progress.xp = progress.xp + (achievement.xp or 0)

    local oldLevel = progress.level
    progress.level = getLevelFromXP(progress.xp)
    saveProgress(citizenId, progress)

    TriggerClientEvent('blixt-busking:client:achievementUnlocked', source, {
        key = achievement.key,
        name = achievement.name,
        description = achievement.description,
        xp = achievement.xp
    })

    if progress.level > oldLevel then
        TriggerClientEvent('blixt-busking:client:levelUp', source, {
            oldLevel = oldLevel,
            newLevel = progress.level,
            xp = progress.xp,
            nextLevelXp = getNextLevelXp(progress.level)
        })
    end

    pushProgressUpdate(source, progress)
    return true
end

local function awardXp(source, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end

    local progress, citizenId = getProgress(source)
    if not progress or not citizenId then return end

    local oldLevel = progress.level
    progress.xp = progress.xp + amount
    progress.level = getLevelFromXP(progress.xp)
    saveProgress(citizenId, progress)

    if progress.level > oldLevel then
        TriggerClientEvent('blixt-busking:client:levelUp', source, {
            oldLevel = oldLevel,
            newLevel = progress.level,
            xp = progress.xp,
            nextLevelXp = getNextLevelXp(progress.level)
        })
    end

    pushProgressUpdate(source, progress)
end

local function handleSongAchievements(source, progress, citizenId)
    local milestones = (Config.Progression and Config.Progression.SongMilestones) or {}
    local key = milestones[progress.songs_completed]
    if key then
        awardAchievement(source, progress, citizenId, key)
    end
end

local function handleCrowdAchievements(source, progress, citizenId, crowdSize)
    local milestones = (Config.Progression and Config.Progression.CrowdMilestones) or {}
    for threshold, key in pairs(milestones) do
        if crowdSize >= threshold then
            awardAchievement(source, progress, citizenId, key)
        end
    end
end

local function getSongTipXpAmount(session, tipAmount)
    local perDollar = (Config.Progression and Config.Progression.TipXpPerDollar) or 1
    local perTipCap = (Config.Progression and Config.Progression.MaxTipXpPerTip) or 10
    local perSongCap = (Config.Progression and Config.Progression.MaxTipXpPerSong) or 50

    local rawXp = math.floor((math.max(0, tipAmount)) * perDollar)
    local tipXp = math.min(rawXp, perTipCap)
    local remaining = math.max(0, perSongCap - (session.tipXpThisSong or 0))

    if remaining <= 0 then
        return 0
    end

    tipXp = math.min(tipXp, remaining)
    session.tipXpThisSong = (session.tipXpThisSong or 0) + tipXp

    return tipXp
end

local function getPlayerSnapshot(source)
    local progress = getProgress(source)
    if not progress then return nil end

    return {
        progress = {
            xp = progress.xp,
            level = progress.level,
            songs_completed = progress.songs_completed,
            best_crowd = progress.best_crowd,
            achievements = progress.achievements,
            nextLevelXp = getNextLevelXp(progress.level)
        },
        levels = Config.Progression and Config.Progression.Levels or {},
        achievements = Config.Progression and Config.Progression.Achievements or {}
    }
end

lib.callback.register('blixt-busking:server:placeProp', function(source, objectType, netId, coords, heading)
    local def = placementDefinitions[objectType]
    if not def or type(coords) ~= 'table' or not netId then
        return false
    end

    local existingNetId = getOwnedProp(source, objectType)
    if existingNetId then
        return false
    end

    if not removeItem(source, def.item, 1) then
        return false
    end

    placedProps[netId] = {
        owner = source,
        objectType = objectType,
        coords = { x = coords.x, y = coords.y, z = coords.z },
        heading = heading,
        model = def.model
    }

    TriggerClientEvent('blixt-busking:client:syncPlacedProp', -1, 'add', {
        objectType = objectType,
        owner = source,
        netId = netId,
        coords = coords,
        heading = heading,
        model = def.model
    })

    return true
end)

lib.callback.register('blixt-busking:server:pickupPlacedProp', function(source, objectType, netId)
    local def = placementDefinitions[objectType]
    local entry = placedProps[netId]

    if not def or not entry or entry.owner ~= source or entry.objectType ~= objectType then
        return false
    end

    if not addItem(source, def.item, 1) then
        return false
    end

    placedProps[netId] = nil
    TriggerClientEvent('blixt-busking:client:syncPlacedProp', -1, 'remove', { objectType = objectType, netId = netId })
    return true
end)

lib.callback.register('blixt-busking:server:getPlacedProps', function()
    return getPlacedPropsList()
end)

lib.callback.register('blixt-busking:server:getPlayerProgress', function(source)
    return getPlayerSnapshot(source)
end)

lib.callback.register('blixt-busking:server:canUseItem', function(source, itemName)
    local progress = getProgress(source)
    if not progress then
        return false, 'Progress data is not ready yet.'
    end

    local requiredLevel = 0
    local itemLabel = itemName

    if itemName == 'guitar' then
        requiredLevel = 0
        itemLabel = 'Guitar'
    else
        for _, entry in pairs((Config.Shop and Config.Shop.Items) or {}) do
            if entry.item == itemName then
                requiredLevel = tonumber(entry.requiredLevel or 0) or 0
                itemLabel = entry.label or itemName
                break
            end
        end
    end

    if progress.level < requiredLevel then
        return false, ('%s unlocks at Busker Level %s.'):format(itemLabel, requiredLevel)
    end

    return true
end)

lib.callback.register('blixt-busking:server:buyShopItem', function(source, itemKey)
    local shopItem = Config.Shop and Config.Shop.Items and Config.Shop.Items[itemKey]
    if not shopItem then
        return false, 'Invalid shop item.'
    end

    local progress = getProgress(source)
    if not progress then
        return false, 'Progress data is not ready yet.'
    end

    local requiredLevel = tonumber(shopItem.requiredLevel or 0) or 0
    if progress.level < requiredLevel then
        return false, ('Requires Busker Level %s.'):format(requiredLevel)
    end

    local price = math.max(0, math.floor(tonumber(shopItem.price) or 0))
    if getCash(source) < price then
        return false, 'Not enough cash.'
    end

    if not removeCash(source, price) then
        return false, 'Could not take your cash.'
    end

    if not addItem(source, shopItem.item, 1) then
        addCash(source, price)
        return false, 'Could not give you the item.'
    end

    return true, ('Purchased %s for $%s.'):format(shopItem.label or shopItem.item, price)
end)

lib.callback.register('blixt-busking:server:getShopData', function(source)
    local snapshot = getPlayerSnapshot(source)
    if not snapshot then return nil end

    local items = {}
    for key, entry in pairs((Config.Shop and Config.Shop.Items) or {}) do
        items[#items + 1] = {
            key = key,
            item = entry.item,
            label = entry.label,
            description = entry.description,
            price = entry.price,
            requiredLevel = entry.requiredLevel or 0,
            owned = getItemCount(source, entry.item)
        }
    end

    table.sort(items, function(a, b)
        return (a.requiredLevel or 0) < (b.requiredLevel or 0)
    end)

    snapshot.shopItems = items
    snapshot.shopHeader = Config.Shop and Config.Shop.Header or 'Busking Supplier'
    return snapshot
end)

lib.callback.register('blixt-busking:server:tipBuskerPlayer', function(source, ownerId, amount)
    ownerId = tonumber(ownerId)
    amount = math.floor(tonumber(amount) or 0)

    if not ownerId or ownerId == source then
        return false, 'You cannot tip yourself.'
    end

    if amount < 1 then
        return false, 'Invalid tip amount.'
    end

    local hat = getOwnersHat(ownerId)
    if not hat then
        return false, 'That hat is not accepting tips right now.'
    end

    if getCash(source) < amount then
        return false, 'Not enough cash.'
    end

    if not removeCash(source, amount) then
        return false, 'Could not take your cash.'
    end

    if not addCash(ownerId, amount) then
        addCash(source, amount)
        return false, 'Could not deliver the tip.'
    end

    local session = activeBuskers[ownerId]
    if session then
        awardXp(ownerId, getSongTipXpAmount(session, amount))
    end

    TriggerClientEvent('ox_lib:notify', ownerId, {
        title = 'Busking',
        description = ('You received a $%s player tip!'):format(amount),
        type = 'success'
    })

    return true
end)

RegisterNetEvent('blixt-busking:server:setBuskingState', function(state)
    local src = source

    if state then
        activeBuskers[src] = {
            startedAt = GetGameTimer(),
            lastTipAt = 0,
            tipCount = 0,
            totalEarned = 0,
            tipXpThisSong = 0,
            currentCrowd = 0
        }
    else
        activeBuskers[src] = nil
    end
end)

RegisterNetEvent('blixt-busking:server:playSound', function(id, url, coords, volume, range)
    TriggerClientEvent('blixt-busking:client:playSound', -1, id, url, coords, volume, range)
end)

RegisterNetEvent('blixt-busking:server:updateSoundPosition', function(id, coords)
    TriggerClientEvent('blixt-busking:client:updateSoundPosition', -1, id, coords)
end)

RegisterNetEvent('blixt-busking:server:stopSound', function(id)
    TriggerClientEvent('blixt-busking:client:stopSound', -1, id)
end)

RegisterNetEvent('blixt-busking:server:npcTip', function(multiplier, isFreestyle)
    local src = source
    local session = activeBuskers[src]

    if not session then
        return
    end

    if not getOwnersHat(src) then
        return
    end

    local now = GetGameTimer()
    if now - session.lastTipAt < Config.Payouts.cooldownMs then
        return
    end

    if session.tipCount >= Config.Payouts.maxTipsPerSession then
        return
    end

    if session.totalEarned >= Config.Payouts.maxSessionEarnings then
        return
    end

    multiplier = tonumber(multiplier) or 1.0
    multiplier = math.max(0.5, math.min(multiplier, 2.0))

    local amount = math.random(Config.Payouts.minTip, Config.Payouts.maxTip)
    amount = math.floor(amount * multiplier)

    if amount < 1 then
        amount = 1
    end

    if session.totalEarned + amount > Config.Payouts.maxSessionEarnings then
        amount = Config.Payouts.maxSessionEarnings - session.totalEarned
    end

    if amount <= 0 then
        return
    end

    if addCash(src, amount) then
        session.lastTipAt = now
        session.tipCount = session.tipCount + 1
        session.totalEarned = session.totalEarned + amount
        awardXp(src, getSongTipXpAmount(session, amount))
    end
end)

RegisterNetEvent('blixt-busking:server:songCompleted', function(crowdSize)
    local src = source
    local progress, citizenId = getProgress(src)
    if not progress or not citizenId then return end

    progress.songs_completed = progress.songs_completed + 1
    saveProgress(citizenId, progress)

    awardXp(src, (Config.Progression and Config.Progression.SongCompletionXp) or 20)
    handleSongAchievements(src, progress, citizenId)

    crowdSize = math.max(0, math.floor(tonumber(crowdSize) or 0))
    if crowdSize > progress.best_crowd then
        progress.best_crowd = crowdSize
        saveProgress(citizenId, progress)
    end

    handleCrowdAchievements(src, progress, citizenId, crowdSize)
    pushProgressUpdate(src, progress)
end)

RegisterNetEvent('blixt-busking:server:updateCrowdSize', function(crowdSize)
    local src = source
    local session = activeBuskers[src]
    if not session then return end

    crowdSize = math.max(0, math.floor(tonumber(crowdSize) or 0))
    if crowdSize <= (session.currentCrowd or 0) then
        return
    end

    session.currentCrowd = crowdSize

    local progress, citizenId = getProgress(src)
    if not progress or not citizenId then return end

    if crowdSize > progress.best_crowd then
        progress.best_crowd = crowdSize
        saveProgress(citizenId, progress)
    end

    handleCrowdAchievements(src, progress, citizenId, crowdSize)
    pushProgressUpdate(src, progress)
end)

AddEventHandler('playerDropped', function()
    local src = source
    activeBuskers[src] = nil
    removePlacedPropByOwner(src)

    local citizenId = getCitizenId(src)
    if citizenId then
        progressCache[citizenId] = nil
    end
end)

CreateThread(function()
    if MySQL then
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS busking_progress (
                citizenid VARCHAR(50) NOT NULL,
                xp INT NOT NULL DEFAULT 0,
                level INT NOT NULL DEFAULT 0,
                songs_completed INT NOT NULL DEFAULT 0,
                best_crowd INT NOT NULL DEFAULT 0,
                achievements LONGTEXT NULL,
                PRIMARY KEY (citizenid)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ]])
    end

    if GetResourceState('qb-core') == 'started' then
        local QBCore = exports['qb-core']:GetCoreObject()
        for _, def in pairs(placementDefinitions) do
            QBCore.Functions.CreateUseableItem(def.item, function(source)
                TriggerClientEvent('blixt-busking:usePlacementItem', source, def.item)
            end)
        end

        QBCore.Functions.CreateUseableItem('guitar', function(source)
            TriggerClientEvent('blixt-busking:useGuitar', source)
        end)
    end
end)
