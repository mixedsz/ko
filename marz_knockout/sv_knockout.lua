local Config = lib.require('config')

-- Framework handles
local ESX = nil
local QBCore = nil

-- Initialize framework on resource start
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    if Config.Framework == "esx" then
        TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)
    elseif Config.Framework == "qbcore" then
        QBCore = exports['qb-core']:GetCoreObject()
    end

    print(string.format("[MarzKnockout] Server script started | Framework: %s", Config.Framework or "standalone"))
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    print("[MarzKnockout] Server script stopped")
end)

-- Returns true if the given source has admin rights
local function isAdmin(source)
    if Config.Framework == "esx" then
        if not ESX then
            TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)
        end
        local xPlayer = ESX and ESX.GetPlayerFromId(source)
        if xPlayer then
            local group = xPlayer.getGroup()
            return group == "admin" or group == "superadmin"
        end
    elseif Config.Framework == "qbcore" then
        if not QBCore then
            QBCore = exports['qb-core']:GetCoreObject()
        end
        local Player = QBCore and QBCore.Functions.GetPlayer(source)
        if Player then
            local group = Player.PlayerData.group
            return group == "admin" or group == "god"
        end
    elseif Config.Framework == "standalone" then
        return IsPlayerAceAllowed(source, "command.marzknockout")
    end
    return false
end

local function notifyPlayer(source, msg)
    TriggerClientEvent('chat:addMessage', source, {
        color = { 255, 0, 0 },
        multiline = true,
        args = { "[MarzKnockout]", msg }
    })
end

-- ─── Server Events ───────────────────────────────────────────────────────────

-- Logs when a player is knocked out or recovers
RegisterNetEvent('marzknockout:logKnockout', function(isKnockout, reason)
    local src = source
    local name = GetPlayerName(src) or "Unknown"
    local identifier = GetPlayerIdentifier(src, 0) or "unknown"

    if isKnockout then
        print(string.format("[MarzKnockout] KNOCKED OUT | Player: %s | ID: %s | Reason: %s",
            name, identifier, reason or "Unknown"))
    else
        print(string.format("[MarzKnockout] RECOVERED   | Player: %s | ID: %s | Reason: %s",
            name, identifier, reason or "Unknown"))
    end
end)

-- Optional server-side health tracking (used when Config.ServerHealthSync is true)
RegisterNetEvent('marzknockout:syncHealth', function(newHealth)
    -- Intentionally lightweight; extend here for database sync or anti-cheat validation
end)

-- Reduce voice proximity when knocked out (supports pma-voice and mumble-voip)
RegisterNetEvent('marzknockout:applyVoiceFilter', function()
    local src = source
    if GetResourceState('pma-voice') == 'started' then
        exports['pma-voice']:setPlayerVoiceDistance(src, 1.5)
    elseif GetResourceState('mumble-voip') == 'started' then
        exports['mumble-voip']:SetPlayerMumbleDistance(src, 1)
    end
end)

-- Restore normal voice proximity when player wakes up
RegisterNetEvent('marzknockout:clearVoiceFilter', function()
    local src = source
    if GetResourceState('pma-voice') == 'started' then
        exports['pma-voice']:setPlayerVoiceDistance(src, 25.0)
    elseif GetResourceState('mumble-voip') == 'started' then
        exports['mumble-voip']:SetPlayerMumbleDistance(src, 25)
    end
end)

-- Anti-cheat: log suspicious client activity
RegisterNetEvent('marzknockout:suspiciousActivity', function(activityType, data)
    local src = source
    local name = GetPlayerName(src) or "Unknown"
    local identifier = GetPlayerIdentifier(src, 0) or "unknown"

    print(string.format("[MarzKnockout] \xE2\x9A\xA0 SUSPICIOUS ACTIVITY | Type: %s | Player: %s (%s)",
        activityType, name, identifier))

    if data then
        print(string.format("[MarzKnockout]   Data: %s", json.encode(data)))
    end
end)

-- ─── Admin Commands ───────────────────────────────────────────────────────────

-- /marzknockout [playerID]
-- Knocks out (or wakes up) the target player. Targets self if no ID given.
RegisterCommand('marzknockout', function(source, args)
    -- Server console bypass
    if source == 0 then
        local targetId = tonumber(args[1])
        if targetId and GetPlayerName(targetId) then
            TriggerClientEvent('marzknockout:executeCommand', targetId)
            print(string.format("[MarzKnockout] Console triggered knockout on player %d", targetId))
        else
            print("[MarzKnockout] Usage: marzknockout <playerID>")
        end
        return
    end

    if not isAdmin(source) then
        notifyPlayer(source, "You don't have permission to use this command.")
        return
    end

    local targetId = tonumber(args[1]) or source

    if not GetPlayerName(targetId) then
        notifyPlayer(source, "Player not found.")
        return
    end

    TriggerClientEvent('marzknockout:executeCommand', targetId)
    print(string.format("[MarzKnockout] Admin %s (ID:%d) triggered knockout on player ID:%d",
        GetPlayerName(source), source, targetId))
end, false)

-- /marzknockouttest
-- Knocks out the calling admin at half health to test the full effect chain.
RegisterCommand('marzknockouttest', function(source, args)
    if source == 0 then
        print("[MarzKnockout] marzknockouttest must be used in-game.")
        return
    end

    if not isAdmin(source) then
        notifyPlayer(source, "You don't have permission to use this command.")
        return
    end

    TriggerClientEvent('marzknockout:executeTestCommand', source)
    print(string.format("[MarzKnockout] Admin %s (ID:%d) triggered knockout test on themselves",
        GetPlayerName(source), source))
end, false)
