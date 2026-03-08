------------------------------------------------------------
-- ArcaneWatch_Config.lua
-- SavedVariables management, defaults, and slash commands.
-- Handles /aw and /arcanewatch commands with a simple
-- config panel toggle.
------------------------------------------------------------

ArcaneWatch.Config = {}

local defaults = {
    threatEnabled  = true,
    timersEnabled  = true,
    locked         = false,
    opacity        = 0.85,
    threatPos      = { x = -200, y = 0 },
    timersPos      = { x = 200, y = 0 },
    configPos      = { x = 0, y = 0 },
    autoHideThreat = true,
    trackedSpells  = {},  -- auto-detected from spellbook
}

------------------------------------------------------------
-- Deep copy utility
------------------------------------------------------------
local function deepCopy(src)
    if type(src) ~= "table" then return src end
    local copy = {}
    for k, v in pairs(src) do
        copy[k] = deepCopy(v)
    end
    return copy
end

------------------------------------------------------------
-- Merge defaults into saved data (fill missing keys)
------------------------------------------------------------
local function mergeDefaults(saved, def)
    if type(def) ~= "table" then return saved end
    if type(saved) ~= "table" then return deepCopy(def) end
    for k, v in pairs(def) do
        if saved[k] == nil then
            saved[k] = deepCopy(v)
        elseif type(v) == "table" and type(saved[k]) == "table" then
            mergeDefaults(saved[k], v)
        end
    end
    return saved
end

------------------------------------------------------------
-- Init: load or create saved variables
------------------------------------------------------------
function ArcaneWatch.Config:Init()
    if not ArcaneWatchDB then
        ArcaneWatchDB = deepCopy(defaults)
    else
        mergeDefaults(ArcaneWatchDB, defaults)
    end
    self.db = ArcaneWatchDB
    self:RegisterSlashCommands()
end

------------------------------------------------------------
-- Save: called on PLAYER_LOGOUT
------------------------------------------------------------
function ArcaneWatch.Config:Save()
    -- Panel positions are saved in real-time by the UI module;
    -- this hook exists for any future flush needs.
    ArcaneWatchDB = self.db
end

------------------------------------------------------------
-- Get / Set helpers
------------------------------------------------------------
function ArcaneWatch.Config:Get(key)
    return self.db and self.db[key]
end

function ArcaneWatch.Config:Set(key, value)
    if self.db then
        self.db[key] = value
    end
end

------------------------------------------------------------
-- Slash commands
------------------------------------------------------------
function ArcaneWatch.Config:RegisterSlashCommands()
    SLASH_ARCANEWATCH1 = "/aw"
    SLASH_ARCANEWATCH2 = "/arcanewatch"
    SlashCmdList["ARCANEWATCH"] = function(msg)
        msg = string.lower(msg or "")
        if msg == "threat" then
            self:ToggleThreat()
        elseif msg == "timers" then
            self:ToggleTimers()
        elseif msg == "lock" then
            self:ToggleLock()
        elseif msg == "reset" then
            self:ResetPositions()
        elseif msg == "config" or msg == "" then
            ArcaneWatch.UI:ToggleConfigPanel()
        else
            self:PrintHelp()
        end
    end
end

function ArcaneWatch.Config:PrintHelp()
    local c = DEFAULT_CHAT_FRAME
    c:AddMessage("|cff5a8abfArcaneWatch|r commands:")
    c:AddMessage("  /aw          - Toggle config panel")
    c:AddMessage("  /aw threat   - Toggle threat meter")
    c:AddMessage("  /aw timers   - Toggle spell timers")
    c:AddMessage("  /aw lock     - Lock/unlock panel dragging")
    c:AddMessage("  /aw reset    - Reset panel positions")
end

function ArcaneWatch.Config:ToggleThreat()
    self.db.threatEnabled = not self.db.threatEnabled
    local state = self.db.threatEnabled and "enabled" or "disabled"
    DEFAULT_CHAT_FRAME:AddMessage("|cff5a8abfArcaneWatch|r Threat meter " .. state .. ".")
    ArcaneWatch.UI:UpdateVisibility()
end

function ArcaneWatch.Config:ToggleTimers()
    self.db.timersEnabled = not self.db.timersEnabled
    local state = self.db.timersEnabled and "enabled" or "disabled"
    DEFAULT_CHAT_FRAME:AddMessage("|cff5a8abfArcaneWatch|r Spell timers " .. state .. ".")
    ArcaneWatch.UI:UpdateVisibility()
end

function ArcaneWatch.Config:ToggleLock()
    self.db.locked = not self.db.locked
    local state = self.db.locked and "locked" or "unlocked"
    DEFAULT_CHAT_FRAME:AddMessage("|cff5a8abfArcaneWatch|r Panels " .. state .. ".")
    ArcaneWatch.UI:UpdateLock()
end

function ArcaneWatch.Config:ResetPositions()
    self.db.threatPos = deepCopy(defaults.threatPos)
    self.db.timersPos = deepCopy(defaults.timersPos)
    self.db.configPos = deepCopy(defaults.configPos)
    ArcaneWatch.UI:ApplyPositions()
    DEFAULT_CHAT_FRAME:AddMessage("|cff5a8abfArcaneWatch|r Panel positions reset.")
end
