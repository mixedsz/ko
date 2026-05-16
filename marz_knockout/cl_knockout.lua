local Config = lib.require('config')
local knockedOut = false
local audioMuffled = false
local originalHealth = 0
local drunkEffectEndTime = 0
local recentlyWokeUp = false -- Recovery protection flag
local recoveryProtectionTime = 5000 -- 5 seconds of protection after waking up
local damageTracker = {} -- Track damage timestamps
local isDead = false -- Track if player is dead
local lastDamageTime = 0 -- Track last damage time for knockedOut state
local debugMode = false -- Set to false to disable debug messages

-- Function to get current timestamp (FiveM compatible)
local function GetCurrentTimestamp()
    return string.format("%.3f", GetGameTimer() / 1000.0)
end

-- Function to format time for logging
local function GetFormattedTime()
    local gameTime = GetClockHours() .. ":" .. string.format("%02d", GetClockMinutes()) .. ":" .. string.format("%02d", GetClockSeconds())
    return gameTime
end

-- Load check to prevent nil errors
if not Config or not Config.Animations then
    if debugMode then print("[MarzKnockout] ERROR: Config missing required fields. Using defaults.") end
    Config = Config or {}
    Config.Animations = Config.Animations or {
        WakeUp = "get_up@drunk@verydrunk"
    }
end

-- Animation dictionaries to load
local animDicts = {
    Config.Animations.WakeUp,
    "move_m@drunk@verydrunk" -- Animation for drunk staggering
}

-- Load animation dictionaries
CreateThread(function()
    for _, dict in ipairs(animDicts) do
        while not HasAnimDictLoaded(dict) do
            RequestAnimDict(dict)
            Wait(10)
        end
    end
    
    -- Load drunk movement animation set
    RequestAnimSet("MOVE_M@DRUNK@VERYDRUNK")
    while not HasAnimSetLoaded("MOVE_M@DRUNK@VERYDRUNK") do
        RequestAnimSet("MOVE_M@DRUNK@VERYDRUNK")
        Wait(10)
    end
    
    if debugMode then print("[MarzKnockout] All animations loaded successfully") end
end)

-- Function to clear all damage flags properly
local function clearAllDamageFlags()
    local ped = PlayerPedId()
    ClearEntityLastDamageEntity(ped)
    ClearEntityLastWeaponDamage(ped)
    ClearPedLastWeaponDamage(ped)
    -- Reset our damage tracker
    damageTracker = {}
end

-- Function to properly clean up all effects
local function cleanupAllEffects()
    -- Clear audio
    if audioMuffled then
        StopAudioScene("CHARACTER_CHANGE_IN_SKY_SCENE")
        audioMuffled = false
    end
    
    -- Clear screen effects
    DoScreenFadeIn(1000)
    ClearTimecycleModifier()
    ResetPedMovementClipset(PlayerPedId(), 0)
    StopGameplayCamShaking(true)
    
    -- Clear drunk state
    SetPedIsDrunk(PlayerPedId(), false)
    SetPedMotionBlur(PlayerPedId(), false)
    AnimpostfxStopAll()
    
    -- Clear other states
    knockedOut = false
    recentlyWokeUp = false
    drunkEffectEndTime = 0
    
    -- Clear damage trackers
    clearAllDamageFlags()
    
    -- Clear voice filter
    TriggerServerEvent('marzknockout:clearVoiceFilter', PlayerId())
    
    if debugMode then print("[MarzKnockout] All effects cleaned up") end
end

-- Death state change listener
CreateThread(function()
    while true do
        Wait(500)
        
        local playerDead = IsPlayerDead(PlayerId())
        
        -- If player just died and we have active knockout effects
        if playerDead and not isDead and knockedOut then
            if debugMode then print("[MarzKnockout] Player died during knockout - cleaning up effects") end
            cleanupAllEffects()
            
            -- Log knockout end due to death
            TriggerServerEvent('marzknockout:logKnockout', false, "Player died")
        end
        
        isDead = playerDead
    end
end)

-- Function to apply muffled audio
local function applyMuffledAudio()
    audioMuffled = true
    StartAudioScene("CHARACTER_CHANGE_IN_SKY_SCENE")
    
    -- Also apply server-side voice filter
    TriggerServerEvent('marzknockout:applyVoiceFilter', PlayerId())
end

-- Function to clear muffled audio
local function clearMuffledAudio()
    audioMuffled = false
    StopAudioScene("CHARACTER_CHANGE_IN_SKY_SCENE")
    
    -- Also clear server-side voice filter
    TriggerServerEvent('marzknockout:clearVoiceFilter', PlayerId())
end

-- Function to play sound from UI
local function playKnockoutSound()
    SendNUIMessage({
        transactionType = 'playSound',
        transactionFile = 'knockout',
        transactionVolume = 0.8
    })
end

-- Debug function to print player state
local function debugPlayerState()
    if not debugMode then return end
    
    local ped = PlayerPedId()
    local health = GetEntityHealth(ped)
    local maxHealth = GetEntityMaxHealth(ped)
    local isInvincible = GetPlayerInvincible(PlayerId())
    local playerDead = IsPlayerDead(PlayerId())
    
    print("--------- PLAYER STATE ---------")
    print("Health: " .. health .. "/" .. maxHealth)
    print("Knocked out: " .. tostring(knockedOut))
    print("Invincible: " .. tostring(isInvincible))
    print("Recently woke up: " .. tostring(recentlyWokeUp))
    print("Is Dead: " .. tostring(playerDead))
    print("Game Time: " .. GetFormattedTime())
    print("Timestamp: " .. GetCurrentTimestamp())
    print("--------------------------------")
end

-- Function to check if player is actually dead
local function isReallyDead()
    local ped = PlayerPedId()
    local health = GetEntityHealth(ped)
    return health <= 0 or IsPlayerDead(PlayerId())
end

-- Function to wake up from knockout
local function wakeUp()
    if not knockedOut or isReallyDead() then return end
    
    local ped = PlayerPedId()
    
    -- First stop all effects and clear status
    knockedOut = false
    clearMuffledAudio()
    DoScreenFadeIn(1500)
    
    -- Set recovery protection flag
    recentlyWokeUp = true
    
    -- Clear all damage flags to prevent any lingering damage detection
    clearAllDamageFlags()
    
    -- No longer setting health back to original value - let player keep whatever health they have
    
    if HasAnimDictLoaded(Config.Animations.WakeUp) then
        TaskPlayAnim(ped, Config.Animations.WakeUp, "b_getup_f_facedown_01", 8.0, -8.0, -1, 0, 0, false, false, false)
    end
    
    -- Apply drunk effect only if player is alive and config enables it
    if Config.DrunkEffect and Config.DrunkEffect.Enabled and not isReallyDead() then
        
        local playerPed = PlayerPedId()
        
        RequestAnimSet("MOVE_M@DRUNK@VERYDRUNK")
        while not HasAnimSetLoaded("MOVE_M@DRUNK@VERYDRUNK") do
            Citizen.Wait(0)
        end

        SetTimecycleModifier("spectator6")
        SetPedMotionBlur(playerPed, true)
        SetPedMovementClipset(playerPed, "MOVE_M@DRUNK@VERYDRUNK", true)
        SetPedIsDrunk(playerPed, true)
        AnimpostfxPlay("ChopVision", 10000001, true)
        ShakeGameplayCam("DRUNK_SHAKE", 1.0)
        
        -- Track effect end time
        local drunkDuration = (Config.DrunkEffect.Duration or 30) * 1000
        drunkEffectEndTime = GetGameTimer() + drunkDuration
        
        -- Set timer to clear effects after duration
        CreateThread(function()
            Citizen.Wait(drunkDuration)
            
            if not isReallyDead() then
                
                SetPedMoveRateOverride(PlayerId(), 1.0)
                SetRunSprintMultiplierForPlayer(PlayerId(), 1.0)
                SetPedIsDrunk(GetPlayerPed(-1), false)
                SetPedMotionBlur(playerPed, false)
                ResetPedMovementClipset(GetPlayerPed(-1))
                AnimpostfxStopAll()
                ShakeGameplayCam("DRUNK_SHAKE", 0.0)
                ClearTimecycleModifier()
                
                drunkEffectEndTime = 0
                
                if lib and lib.notify then
                    lib.notify({
                        title = '',
                        description = 'You recovered from your dazed state',
                        type = 'inform',
                        position = 'top',
                        duration = 3000
                    })
                end
            end
        end)
    end
    
    -- Show notification
    if lib and lib.notify then
        lib.notify({
            title = '',
            description = 'You have regained consciousness',
            type = 'inform',
            position = 'top',
            duration = 5000
        })
    end
    
    -- Set recovery protection timer
    SetTimeout(recoveryProtectionTime, function()
        recentlyWokeUp = false
        if debugMode then print("[MarzKnockout] Recovery protection ended") end
    end)
    
    -- Log recovery
    TriggerServerEvent('marzknockout:logKnockout', false, "Natural recovery")
    
    if debugMode then print("[MarzKnockout] Player woke up with health: " .. GetEntityHealth(ped)) end
end

-- Check if damage is a new hit (prevents multiple registrations for same hit)
local function isNewDamage()
    local currentTime = GetGameTimer()
    
    -- Clean up old damage entries (older than 2 seconds)
    for timestamp in pairs(damageTracker) do
        if currentTime - timestamp > 2000 then
            damageTracker[timestamp] = nil
        end
    end
    
    -- Check if we've had damage in the last 500ms
    for timestamp in pairs(damageTracker) do
        if currentTime - timestamp < 500 then
            return false
        end
    end
    
    -- Record this damage
    damageTracker[currentTime] = true
    return true
end

-- Function to handle knockout
local function knockoutPlayer()
    local ped = PlayerPedId()
    
    -- If player is dead, don't do anything
    if isReallyDead() then 
        if debugMode then print("[MarzKnockout] Player is dead, not starting knockout") end
        return 
    end
    
    if debugMode then print("[MarzKnockout] Knockout started, health before: " .. GetEntityHealth(ped)) end
    
    -- Set status
    knockedOut = true
    recentlyWokeUp = false
    
    -- Clear all damage flags
    clearAllDamageFlags()
    
    -- Save current health for later reference
    originalHealth = GetEntityHealth(ped)
    
    -- Ensure minimum health to prevent instant death (but still allow damage while knocked out)
    if GetEntityHealth(ped) < 110 then
        SetEntityHealth(ped, 110)
    end
    
    -- Play sound and show notification
    playKnockoutSound()
    
    if lib and lib.notify then
        lib.notify({
            title = '',
            description = Config.BlurEffect and Config.BlurEffect.NotificationText or 'You just got knocked out',
            type = 'error',
            position = 'top',
            duration = 3000
        })
    end
    
    -- Apply effects
    DoScreenFadeOut(1500)
    applyMuffledAudio()
    
    -- Log knockout event
    TriggerServerEvent('marzknockout:logKnockout', true, "Damage threshold reached")
    
    -- Start the knockout timer
    timer = (Config.KnockoutTime or 20) * 1000
    
    -- Add health regeneration feature similar to knockout.lua
    -- Only if configured to do so
    if Config.RestoreHealth then
        CreateThread(function()
            while knockedOut and not isReallyDead() do
                Wait(3000) -- Slower health regeneration to balance with faster damage
                local currentHealth = GetEntityHealth(ped)
                local maxHealth = GetEntityMaxHealth(ped)
                
                if currentHealth < maxHealth then
                    -- Add 3 health points every 3 seconds (reduced from 5 every 2 seconds)
                    local newHealth = math.min(currentHealth + 3, maxHealth)
                    SetEntityHealth(ped, newHealth)
                    
                    -- Sync health with server if enabled
                    if Config.ServerHealthSync then
                        TriggerServerEvent('marzknockout:syncHealth', newHealth)
                    end
                    
                    if debugMode then print("[MarzKnockout] Health regenerating during knockout: " .. currentHealth .. " -> " .. newHealth) end
                end
            end
        end)
    end
    
    -- NEW: Aggressive damage detection during knockout with no cooldown
    CreateThread(function()
        while knockedOut do
            Wait(10) -- Check very frequently for damage (10ms)
            
            if isReallyDead() then break end
            
            local ped = PlayerPedId()
            local hasBeenDamaged = HasEntityBeenDamagedByAnyPed(ped) or 
                                   HasEntityBeenDamagedByAnyVehicle(ped) or 
                                   HasEntityBeenDamagedByAnyObject(ped)
            
            if hasBeenDamaged then
                -- Apply damage immediately with no cooldown
                local currentHealth = GetEntityHealth(ped)
                local damageAmount = 5 -- REDUCED from 15 to 5 damage per hit
                
                if currentHealth > 101 then -- Ensure player stays above death threshold
                    local newHealth = currentHealth - damageAmount
                    SetEntityHealth(ped, newHealth)
                    
                    -- Sync health with server if enabled
                    if Config.ServerHealthSync then
                        TriggerServerEvent('marzknockout:syncHealth', newHealth)
                    end
                    
                    if debugMode then print("[MarzKnockout] Damage detected while knocked out: " .. currentHealth .. " -> " .. newHealth) end
                end
                
                -- Clear the damage flag so it doesn't trigger again
                ClearEntityLastDamageEntity(ped)
                ClearEntityLastWeaponDamage(ped)
                ClearPedLastWeaponDamage(ped)
            end
        end
    end)
    
    -- Monitor health and apply ragdoll during knockout
    CreateThread(function()
        while knockedOut do
            if isReallyDead() then
                if debugMode then print("[MarzKnockout] Player died during knockout, stopping") end
                break
            end
            
            -- Apply ragdoll with shorter intervals
            SetPedToRagdoll(ped, 1000, 1000, 0, 0, 0, 0)
            
            -- We've replaced the health reduction with regeneration if Config.RestoreHealth is true
            -- If Config.RestoreHealth is false, we'll just maintain current health behavior
            if not Config.RestoreHealth then
                local currentHealth = GetEntityHealth(ped)
                if currentHealth > 102 then -- Keep slightly above death threshold
                    local newHealth = currentHealth - 1
                    SetEntityHealth(ped, newHealth) -- Reduce by 1 each cycle
                    
                    -- Sync health with server if enabled
                    if Config.ServerHealthSync then
                        TriggerServerEvent('marzknockout:syncHealth', newHealth)
                    end
                    
                    if debugMode then print("[MarzKnockout] Health reduced during knockout: " .. currentHealth .. " -> " .. newHealth) end
                end
            end
            
            -- Update timer
            timer = timer - 100
            if timer <= 0 then
                if not isReallyDead() then
                    wakeUp()
                end
                break
            end
            
            Wait(100) -- Shorter wait time to enforce ragdoll and apply damage more frequently
        end
    end)
end

-- Event handler for damage events
AddEventHandler('gameEventTriggered', function(event, data)
    if event ~= "CEventNetworkEntityDamage" then return end

    local victim = NetworkGetPlayerIndexFromPed(data[1])
    if victim ~= PlayerId() then return end
    
    local ped = PlayerPedId()
    
    -- Get attacker and damage weapon
    local attacker = data[2]
    local weaponHash = GetPedCauseOfDeath(ped)
    
    -- SPECIAL HANDLING FOR DAMAGE WHILE KNOCKED OUT
    if knockedOut then
        -- Allow all damage to pass through, but ensure health drops
        local currentHealth = GetEntityHealth(ped)
        local newHealth = currentHealth - 3 -- REDUCED from 5 to 3 points per hit
        
        -- Only update health if we're not already dead
        if not isReallyDead() and currentHealth > 100 then
            if debugMode then print("[MarzKnockout] Taking damage while knocked out (from event): " .. currentHealth .. " -> " .. newHealth) end
            SetEntityHealth(ped, newHealth)
            
            -- Sync health with server if enabled
            if Config.ServerHealthSync then
                TriggerServerEvent('marzknockout:syncHealth', newHealth)
            end
            
            -- Track when we last applied damage
            lastDamageTime = GetGameTimer()
        end
        return
    end
    
    -- Skip if player is dead
    if isReallyDead() then return end
    
    -- Skip if player just woke up and is still in recovery protection
    if recentlyWokeUp then
        if debugMode then print("[MarzKnockout] Damage ignored - Recovery protection active") end
        return 
    end
    
    -- Check if it's unarmed damage or melee weapon and if it's new damage
    local currentHealth = GetEntityHealth(ped)
    local isDamagedByUnarmed = HasPedBeenDamagedByWeapon(ped, GetHashKey("WEAPON_UNARMED"), 0)
    local isDamagedByMelee = HasPedBeenDamagedByWeapon(ped, GetHashKey("WEAPON_BAT"), 0) or 
                             HasPedBeenDamagedByWeapon(ped, GetHashKey("WEAPON_CROWBAR"), 0) or
                             HasPedBeenDamagedByWeapon(ped, GetHashKey("WEAPON_GOLFCLUB"), 0) or
                             HasPedBeenDamagedByWeapon(ped, GetHashKey("WEAPON_HAMMER"), 0) or
                             HasPedBeenDamagedByWeapon(ped, GetHashKey("WEAPON_NIGHTSTICK"), 0)

    -- NEW: Add configurable weapons from config
    local isDamagedByConfigWeapons = false
    if Config.WeaponKnockout and Config.WeaponKnockout.Enabled and Config.WeaponKnockout.KnockoutWeapons then
        for weaponName, knockoutHealth in pairs(Config.WeaponKnockout.KnockoutWeapons) do
            if HasPedBeenDamagedByWeapon(ped, GetHashKey(weaponName), 0) then
                isDamagedByConfigWeapons = true
                -- Use weapon-specific health threshold
                if currentHealth < knockoutHealth then
                    if debugMode then print("[MarzKnockout] " .. weaponName .. " damage detected, health below " .. knockoutHealth) end
                    
                    -- Return if not a new damage event (debounce)
                    if not isNewDamage() then return end
                    
                    -- CRITICAL: Ensure player has enough health to not die immediately
                    if currentHealth < 110 then
                        SetEntityHealth(ped, 110)
                    end
                    
                    -- Start knockout
                    knockoutPlayer()
                    return
                end
            end
        end
    end
    
    -- Return if not a new damage event (debounce)
    if not isNewDamage() then return end
    
    if debugMode then
        print("[MarzKnockout] Damage detected - Health: " .. currentHealth .. 
              ", Unarmed: " .. tostring(isDamagedByUnarmed) .. 
              ", Melee: " .. tostring(isDamagedByMelee) ..
              ", Config Weapons: " .. tostring(isDamagedByConfigWeapons) ..
              ", Game Time: " .. GetFormattedTime())
    end
    
    -- Allow knockout from both unarmed and melee weapons (original behavior)
    if isDamagedByUnarmed or isDamagedByMelee then
        -- If health below threshold, knock out the player
        if currentHealth < (Config.Health or 140) then
            if debugMode then print("[MarzKnockout] Health below threshold, triggering knockout") end
            
            -- CRITICAL: Ensure player has enough health to not die immediately
            if currentHealth < 110 then
                SetEntityHealth(ped, 110)
            end
            
            -- Start knockout
            knockoutPlayer()
        else
            -- Clear damage flags for hits that don't trigger knockout
            ClearEntityLastDamageEntity(ped)
            ClearEntityLastWeaponDamage(ped)
            ClearPedLastWeaponDamage(ped)
        end
    end
end)

-- Event handlers for skin changes (to keep drunk effect)
RegisterNetEvent('qb-clothing:client:loadPlayerClothing')
AddEventHandler('qb-clothing:client:loadPlayerClothing', function()
    if drunkEffectEndTime > 0 and GetGameTimer() < drunkEffectEndTime and not isReallyDead() then
        
        local playerPed = PlayerPedId()
        
        RequestAnimSet("MOVE_M@DRUNK@VERYDRUNK")
        while not HasAnimSetLoaded("MOVE_M@DRUNK@VERYDRUNK") do
            Citizen.Wait(0)
        end

        SetTimecycleModifier("spectator6")
        SetPedMotionBlur(playerPed, true)
        SetPedMovementClipset(playerPed, "MOVE_M@DRUNK@VERYDRUNK", true)
        SetPedIsDrunk(playerPed, true)
        AnimpostfxPlay("ChopVision", 10000001, true)
        ShakeGameplayCam("DRUNK_SHAKE", 1.0)
    end
end)

-- Also handle ESX skin changes
RegisterNetEvent('skinchanger:loadSkin')
AddEventHandler('skinchanger:loadSkin', function()
    if drunkEffectEndTime > 0 and GetGameTimer() < drunkEffectEndTime and not isReallyDead() then
        
        local playerPed = PlayerPedId()
        
        RequestAnimSet("MOVE_M@DRUNK@VERYDRUNK")
        while not HasAnimSetLoaded("MOVE_M@DRUNK@VERYDRUNK") do
            Citizen.Wait(0)
        end

        SetTimecycleModifier("spectator6")
        SetPedMotionBlur(playerPed, true)
        SetPedMovementClipset(playerPed, "MOVE_M@DRUNK@VERYDRUNK", true)
        SetPedIsDrunk(playerPed, true)
        AnimpostfxPlay("ChopVision", 10000001, true)
        ShakeGameplayCam("DRUNK_SHAKE", 1.0)
    end
end)

-- Generic thread to catch skin changes
CreateThread(function()
    local lastPed = nil
    while true do
        Wait(1000)
        local ped = PlayerPedId()
        
        if ped ~= lastPed or (lastPed and GetEntityModel(ped) ~= GetEntityModel(lastPed)) then
            lastPed = ped
            
            if drunkEffectEndTime > 0 and GetGameTimer() < drunkEffectEndTime and not isReallyDead() then
                
                local playerPed = PlayerPedId()
                
                RequestAnimSet("MOVE_M@DRUNK@VERYDRUNK")
                while not HasAnimSetLoaded("MOVE_M@DRUNK@VERYDRUNK") do
                    Citizen.Wait(0)
                end

                SetTimecycleModifier("spectator6")
                SetPedMotionBlur(playerPed, true)
                SetPedMovementClipset(playerPed, "MOVE_M@DRUNK@VERYDRUNK", true)
                SetPedIsDrunk(playerPed, true)
                AnimpostfxPlay("ChopVision", 10000001, true)
                ShakeGameplayCam("DRUNK_SHAKE", 1.0)
            end
        end
    end
end)

-- Event handler for admin-authorized knockout command (REPLACES OLD COMMAND)
RegisterNetEvent('marzknockout:executeCommand')
AddEventHandler('marzknockout:executeCommand', function()
    if not knockedOut and not isReallyDead() then
        if debugMode then
            print("[MarzKnockout] Admin knockout triggered")
            debugPlayerState()
        end
        knockoutPlayer()
        
        -- Show admin notification
        if lib and lib.notify then
            lib.notify({
                title = 'Admin Command',
                description = 'Knockout command executed by admin',
                type = 'inform',
                position = 'top',
                duration = 3000
            })
        end
        
        -- Log admin knockout
        TriggerServerEvent('marzknockout:logKnockout', true, "Admin command")
    else
        if debugMode then print("[MarzKnockout] Admin wake up triggered") end
        wakeUp()
        
        -- Show admin notification
        if lib and lib.notify then
            lib.notify({
                title = 'Admin Command',
                description = 'Wake up command executed by admin',
                type = 'inform',
                position = 'top',
                duration = 3000
            })
        end
    end
end)

-- Event handler for admin-authorized knockout test command (REPLACES OLD COMMAND)
RegisterNetEvent('marzknockout:executeTestCommand')
AddEventHandler('marzknockout:executeTestCommand', function()
    if not knockedOut and not isReallyDead() then
        local ped = PlayerPedId()
        local maxHealth = GetEntityMaxHealth(ped)
        local halfHealth = math.floor(maxHealth/2)
        
        -- Set health to half first to simulate damage
        SetEntityHealth(ped, halfHealth)
        
        -- Sync health with server if enabled
        if Config.ServerHealthSync then
            TriggerServerEvent('marzknockout:syncHealth', halfHealth)
        end
        
        if debugMode then
            print("[MarzKnockout] Admin knockout with half health triggered")
            debugPlayerState()
        end
        knockoutPlayer()
        
        -- Show admin notification
        if lib and lib.notify then
            lib.notify({
                title = 'Admin Command',
                description = 'Knockout test command executed (health set to 50%)',
                type = 'inform',
                position = 'top',
                duration = 4000
            })
        end
        
        -- Log admin knockout test
        TriggerServerEvent('marzknockout:logKnockout', true, "Admin test command")
    else
        if debugMode then print("[MarzKnockout] Admin wake up triggered") end
        wakeUp()
        
        -- Show admin notification
        if lib and lib.notify then
            lib.notify({
                title = 'Admin Command',
                description = 'Wake up command executed by admin',
                type = 'inform',
                position = 'top',
                duration = 3000
            })
        end
    end
end)

-- Health monitoring thread (optional - for debugging and server sync)
if Config.HealthMonitoring then
    CreateThread(function()
        local lastHealth = 0
        while true do
            Wait(5000) -- Check every 5 seconds
            
            local currentHealth = GetEntityHealth(PlayerPedId())
            
            if math.abs(currentHealth - lastHealth) > 10 then -- Significant health change
                if debugMode then
                    print(string.format("[MarzKnockout] Health change detected: %d -> %d (Δ%d)", 
                        lastHealth, currentHealth, currentHealth - lastHealth))
                end
                
                -- Sync with server if enabled
                if Config.ServerHealthSync then
                    TriggerServerEvent('marzknockout:syncHealth', currentHealth)
                end
            end
            
            lastHealth = currentHealth
        end
    end)
end

-- Client-side anti-cheat thread (optional)
if Config.AntiCheat then
    CreateThread(function()
        while true do
            Wait(1000)
            
            local ped = PlayerPedId()
            local health = GetEntityHealth(ped)
            local maxHealth = GetEntityMaxHealth(ped)
            
            -- Check for suspicious health values
            if health > maxHealth + 50 then
                if debugMode then 
                    print("[MarzKnockout] ⚠️ Suspicious health detected: " .. health .. "/" .. maxHealth) 
                end
                
                -- Reset to max health
                SetEntityHealth(ped, maxHealth)
                
                -- Log to server
                TriggerServerEvent('marzknockout:suspiciousActivity', 'health_manipulation', {
                    health = health,
                    maxHealth = maxHealth,
                    timestamp = GetCurrentTimestamp()
                })
            end
            
            -- Check if player is using god mode while knocked out
            if knockedOut and GetPlayerInvincible(PlayerId()) then
                if debugMode then 
                    print("[MarzKnockout] ⚠️ God mode detected during knockout") 
                end
                
                -- Disable god mode
                SetPlayerInvincible(PlayerId(), false)
                
                -- Log to server
                TriggerServerEvent('marzknockout:suspiciousActivity', 'godmode_during_knockout', {
                    timestamp = GetCurrentTimestamp()
                })
            end
        end
    end)
end

-- Clean up if resource stops
AddEventHandler('onResourceStop', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then return end
    
    if debugMode then print("[MarzKnockout] Resource stopping, cleaning up effects") end
    cleanupAllEffects()
    
    print("[MarzKnockout] Client script stopped and cleaned up - " .. GetFormattedTime())
end)

-- Resource start confirmation
AddEventHandler('onResourceStart', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then return end
    
    print("[MarzKnockout] Client script started successfully - " .. GetFormattedTime())
    
    if debugMode then
        print("[MarzKnockout] Debug mode is ENABLED")
        print("[MarzKnockout] Framework: " .. (Config.Framework or "Not set"))
        print("[MarzKnockout] Health threshold: " .. (Config.Health or 140))
        print("[MarzKnockout] Knockout time: " .. (Config.KnockoutTime or 20) .. " seconds")
    end
end)

-- NOTE: The old RegisterCommand handlers for 'marzknockout' and 'marzknockouttest' 
-- have been REMOVED and replaced with server-side validation and client events.
-- This prevents unauthorized players from using these commands directly.

print("[MarzKnockout] Client script loaded with server-side command restrictions - " .. GetFormattedTime())