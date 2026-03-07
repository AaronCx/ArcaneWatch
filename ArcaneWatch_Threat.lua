------------------------------------------------------------
-- ArcaneWatch_Threat.lua
-- Threat meter logic. Polls threat data via OnUpdate at
-- 0.2s intervals using UnitThreatSituation() and
-- GetThreatStatusColor() (Turtle WoW extended API).
-- Supports solo, party, and raid contexts.
-- Auto-shows on combat start, auto-hides on combat end.
------------------------------------------------------------

ArcaneWatch.Threat = {}

local Threat = ArcaneWatch.Threat
local POLL_INTERVAL = 0.2
local FADE_DELAY    = 3.0   -- seconds after combat ends before hiding

local elapsed   = 0
local inCombat  = false
local fadeTimer = 0

------------------------------------------------------------
-- Threat data entry
------------------------------------------------------------
-- { name, unit, threat (0-100 normalized), class, isPlayer }

------------------------------------------------------------
-- Init: register combat events and start OnUpdate
------------------------------------------------------------
function Threat:Init()
    self.frame = CreateFrame("Frame", "ArcaneWatchThreatLogic", UIParent)
    self.frame:RegisterEvent("PLAYER_REGEN_DISABLED")  -- enter combat
    self.frame:RegisterEvent("PLAYER_REGEN_ENABLED")   -- leave combat

    local this = self
    self.frame:SetScript("OnEvent", function()
        if event == "PLAYER_REGEN_DISABLED" then
            this:OnCombatStart()
        elseif event == "PLAYER_REGEN_ENABLED" then
            this:OnCombatEnd()
        end
    end)

    self.frame:SetScript("OnUpdate", function()
        elapsed = elapsed + arg1
        if elapsed < POLL_INTERVAL then return end
        elapsed = 0
        this:OnPoll()
    end)
end

------------------------------------------------------------
-- Combat state management
------------------------------------------------------------
function Threat:OnCombatStart()
    inCombat  = true
    fadeTimer = 0
    local db = ArcaneWatch.Config.db
    if db.threatEnabled then
        ArcaneWatch.UI.threatPanel:SetAlpha(db.opacity or 0.85)
        ArcaneWatch.UI.threatPanel:Show()
    end
end

function Threat:OnCombatEnd()
    inCombat  = false
    fadeTimer = FADE_DELAY
end

------------------------------------------------------------
-- Poll: gather threat data and update UI
------------------------------------------------------------
function Threat:OnPoll()
    -- Handle fade-out after combat
    if not inCombat then
        if fadeTimer > 0 then
            fadeTimer = fadeTimer - POLL_INTERVAL
            if fadeTimer <= 0 then
                local db = ArcaneWatch.Config.db
                if db.autoHideThreat then
                    ArcaneWatch.UI.threatPanel:Hide()
                end
                self:ClearRows()
                return
            end
            -- Fade alpha during fade delay
            local alpha = (fadeTimer / FADE_DELAY) * (ArcaneWatch.Config.db.opacity or 0.85)
            ArcaneWatch.UI.threatPanel:SetAlpha(alpha)
        end
        if fadeTimer <= 0 then return end
    end

    if not ArcaneWatch.Config:Get("threatEnabled") then return end

    local target = "target"
    if not UnitExists(target) then
        self:ClearRows()
        return
    end

    -- Gather threat info for all group members against current target
    local data = {}
    local playerName = UnitName("player")

    ArcaneWatch.IterGroupUnits(function(unit)
        local name = UnitName(unit)
        if not name then return end

        -- UnitThreatSituation(unit, target) returns status (0-3) on Turtle WoW
        local status = nil
        if UnitThreatSituation then
            status = UnitThreatSituation(unit, target)
        end

        -- UnitDetailedThreatSituation is available on Turtle WoW
        local isTanking, statusVal, threatPct, rawThreat, threatValue
        if UnitDetailedThreatSituation then
            isTanking, statusVal, threatPct, rawThreat, threatValue = UnitDetailedThreatSituation(unit, target)
        end

        local threat = 0
        if threatPct then
            threat = threatPct
        elseif status then
            -- Fallback: estimate from status (0=low, 1=mid, 2=high, 3=tanking)
            local estimates = { [0] = 10, [1] = 40, [2] = 70, [3] = 100 }
            threat = estimates[status] or 0
        end

        -- Get class for coloring
        local _, class = UnitClass(unit)

        if threat > 0 or (unit == "player") then
            table.insert(data, {
                name     = name,
                unit     = unit,
                threat   = threat,
                class    = class,
                isPlayer = (name == playerName),
            })
        end
    end)

    -- Sort descending by threat
    table.sort(data, function(a, b) return a.threat > b.threat end)

    -- Normalize to top threat = 100%
    local maxThreat = (data[1] and data[1].threat > 0) and data[1].threat or 1

    -- Update UI rows
    local rows = ArcaneWatch.UI.threatRows
    for i = 1, 5 do
        local row = rows[i]
        local d = data[i]
        if d then
            local pct = (d.threat / maxThreat) * 100
            row.nameText:SetText(d.name)
            row.pctText:SetText(string.format("%.0f%%", d.threat))
            row.bar:SetValue(pct)

            -- Class color the bar
            local cc = ArcaneWatch.classColors[d.class]
            if cc then
                row.bar:SetStatusBarColor(cc[1], cc[2], cc[3], 0.85)
            else
                row.bar:SetStatusBarColor(0.4, 0.6, 0.8, 0.85)
            end

            -- Highlight player row
            if d.isPlayer then
                row.glow:Show()
            else
                row.glow:Hide()
            end

            row.frame:Show()
        else
            row.frame:Hide()
        end
    end
end

------------------------------------------------------------
-- Clear all threat rows
------------------------------------------------------------
function Threat:ClearRows()
    local rows = ArcaneWatch.UI.threatRows
    if not rows then return end
    for i = 1, 5 do
        rows[i].frame:Hide()
        rows[i].bar:SetValue(0)
        rows[i].nameText:SetText("")
        rows[i].pctText:SetText("")
        rows[i].glow:Hide()
    end
end
