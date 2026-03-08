------------------------------------------------------------
-- ArcaneWatch.lua  (v1.10.0)
-- Core addon namespace, constants, and initialization.
-- Sets up the global table, registers ADDON_LOADED,
-- and provides shared utility functions.
------------------------------------------------------------

ArcaneWatch = {}
ArcaneWatch.version = "1.10.0"

-- Shared color constants
ArcaneWatch.colors = {
    border    = { 0.227, 0.290, 0.361, 0.9 },   -- #3a4a5c muted blue-gray
    bg        = { 0.05,  0.05, 0.08,  0.85 },    -- dark semi-transparent
    highlight = { 0.30,  0.60, 1.00,  0.25 },    -- player row glow
    barBg     = { 0.10,  0.10, 0.12,  0.6  },    -- bar background
    text      = { 0.85,  0.85, 0.85,  1.0  },    -- label text
    header    = { 0.70,  0.80, 0.95,  1.0  },    -- header text
    warning   = { 1.00,  0.30, 0.20,  0.9  },    -- threat warning flash
    ready     = { 0.30,  1.00, 0.30,  1.0  },    -- timer ready green
}

-- WoW class colors (vanilla palette)
ArcaneWatch.classColors = {
    ["WARRIOR"]  = { 0.78, 0.61, 0.43 },
    ["PALADIN"]  = { 0.96, 0.55, 0.73 },
    ["HUNTER"]   = { 0.67, 0.83, 0.45 },
    ["ROGUE"]    = { 1.00, 0.96, 0.41 },
    ["PRIEST"]   = { 1.00, 1.00, 1.00 },
    ["SHAMAN"]   = { 0.00, 0.44, 0.87 },
    ["MAGE"]     = { 0.41, 0.80, 0.94 },
    ["WARLOCK"]  = { 0.58, 0.51, 0.79 },
    ["DRUID"]    = { 1.00, 0.49, 0.04 },
}

-- Bar texture path
ArcaneWatch.barTexture = "Interface\\TargetingFrame\\UI-StatusBar"

-- Backdrop template for panels
ArcaneWatch.panelBackdrop = {
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile     = true,
    tileSize = 16,
    edgeSize = 12,
    insets   = { left = 2, right = 2, top = 2, bottom = 2 },
}

------------------------------------------------------------
-- Utility: safe format time
------------------------------------------------------------
function ArcaneWatch.FormatTime(seconds)
    if not seconds or seconds <= 0 then return "0.0s" end
    if seconds >= 60 then
        local m = math.floor(seconds / 60)
        local s = math.floor(seconds - m * 60)
        return m .. "m " .. s .. "s"
    end
    return string.format("%.1fs", seconds)
end

------------------------------------------------------------
-- Utility: get group context
------------------------------------------------------------
function ArcaneWatch.GetGroupType()
    if GetNumRaidMembers() > 0 then
        return "raid", GetNumRaidMembers()
    elseif GetNumPartyMembers() > 0 then
        return "party", GetNumPartyMembers()
    end
    return "solo", 0
end

------------------------------------------------------------
-- Utility: iterate group units (includes player)
------------------------------------------------------------
function ArcaneWatch.IterGroupUnits(callback)
    local gtype, count = ArcaneWatch.GetGroupType()
    if gtype == "raid" then
        for i = 1, count do
            callback("raid" .. i)
        end
    elseif gtype == "party" then
        callback("player")
        for i = 1, count do
            callback("party" .. i)
        end
    else
        callback("player")
    end
end

------------------------------------------------------------
-- Utility: play a sound (vanilla-compatible)
------------------------------------------------------------
function ArcaneWatch.PlaySound(soundId)
    if PlaySound then
        PlaySound(soundId)
    end
end

------------------------------------------------------------
-- Initialization frame
------------------------------------------------------------
local initFrame = CreateFrame("Frame", "ArcaneWatchInitFrame", UIParent)
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_LOGOUT")
initFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "ArcaneWatch" then
        ArcaneWatch.Config:Init()
        ArcaneWatch.UI:Init()
        ArcaneWatch.Threat:Init()
        ArcaneWatch.Timers:Init()
        DEFAULT_CHAT_FRAME:AddMessage("|cff5a8abfArcaneWatch|r v" .. ArcaneWatch.version .. " loaded. Type |cff88ccff/aw|r for options.")
    elseif event == "PLAYER_LOGOUT" then
        ArcaneWatch.Config:Save()
    end
end)
