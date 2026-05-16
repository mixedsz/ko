return {
    -- General Settings
    RestoreHealth = true,       -- Will slowly restore players health when knocked out
    KnockoutTime = 20,          -- Knockout duration in seconds
    Health = 120,               -- Health threshold for knockout (for original weapons)
    
    -- Framework Settings
    Framework = "esx",       -- Options: "esx", "qbcore", "standalone"
    
    -- Animation Settings
    Animations = {
        WakeUp = "get_up@drunk@verydrunk",     -- Animation dictionary for waking up
    },
    
    -- Blur effect settings
    BlurEffect = {
        Enabled = true,         -- Enable blur screen effect during knockout
        NotificationText = "You just got knocked the fuck out"  -- Text to show in notification
    },
    
    -- Drunk effect settings
    DrunkEffect = {
        Enabled = true,         -- Enable drunk effect after knockout
        Duration = 30,          -- Drunk effect duration in seconds
        Intensity = 1.0,        -- Drunk walking intensity (0.0 to 1.0) - Increased for better effect
    },

    --Weapon knockout settings
    WeaponKnockout = {
        Enabled = true,         
        
        KnockoutWeapons = {
            ["WEAPON_BLACKBELT"] = 160,      
            ["WEAPON_REDBELT"] = 160,          
            ["WEAPON_PINKBELT"] = 160,      
            ["WEAPON_LOUISBELT"] = 160, 
            ["WEAPON_RSNAKESKINBELT"] = 160, 
            ["WEAPON_GALIGATORSKINBELT"] = 160, 
            ["WEAPON_COWBOYBELT"] = 160,        
            ["WEAPON_DILDO"] = 120, 
        }
    }
}