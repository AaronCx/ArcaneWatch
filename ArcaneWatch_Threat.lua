------------------------------------------------------------
-- ArcaneWatch_Threat.lua  (v1.1)
-- Threat meter logic. Uses a hybrid approach:
--   1) UnitDetailedThreatSituation / UnitThreatSituation
--      if available (Turtle WoW extended API)
--   2) Combat-log based threat estimation as fallback:
--      parses damage/healing from all group members and
--      builds a running threat table.
-- Polls at 0.2s intervals. Auto-shows on combat start,
-- fades out after combat ends.
------------------------------------------------------------

ArcaneWatch.Threat = {}

local Threat = ArcaneWatch.Threat
local POLL_INTERVAL = 0.2
local FADE_DELAY    = 3.0

local elapsed   = 0
local inCombat  = false
local fadeTimer = 0

-- Combat-log based threat accumulator
-- threatTable[name] = { threat = number, class = string, isPlayer = bool }
local threatTable = {}

-- Threat multipliers (approximations for vanilla)
local HEAL_THREAT_MOD = 0.5  -- healing generates ~50% threat
local DAMAGE_THREAT_MOD = 1.0

------------------------------------------------------------
-- Init: register events
------------------------------------------------------------
function Threat:Init()
    self.frame = CreateFrame("Frame", "ArcaneWatchThreatLogic", UIParent)

    -- Combat state events
    self.frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    self.frame:RegisterEvent("PLAYER_REGEN_ENABLED")

    -- Combat log events for threat estimation (all group members)
    self.frame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
    self.frame:RegisterEvent("CHAT_MSG_SPELL_PARTY_DAMAGE")
    self.frame:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE")
    self.frame:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE")
    self.frame:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
    self.frame:RegisterEvent("CHAT_MSG_COMBAT_PARTY_HITS")
    self.frame:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_CREATURE_HITS")
    self.frame:RegisterEvent("CHAT_MSG_SPELL_SELF_BUFF")
    self.frame:RegisterEvent("CHAT_MSG_SPELL_PARTY_BUFF")
    self.frame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE")
    self.frame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_PARTY_DAMAGE")
    self.frame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE")
    self.frame:RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES")
    self.frame:RegisterEvent("CHAT_MSG_COMBAT_PARTY_MISSES")
    self.frame:RegisterEvent("CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF")
    self.frame:RegisterEvent("CHAT_MSG_SPELL_DAMAGESHIELDS_ON_OTHERS")
    self.frame:RegisterEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH")

    local this = self
    self.frame:SetScript("OnEvent", function()
        this:OnEvent(event, arg1, arg2, arg3)
    end)

    self.frame:SetScript("OnUpdate", function()
        elapsed = elapsed + arg1
        if elapsed < POLL_INTERVAL then return end
        elapsed = 0
        this:OnPoll()
    end)
end

------------------------------------------------------------
-- Event handler
------------------------------------------------------------
function Threat:OnEvent(evt, a1, a2, a3)
    if evt == "PLAYER_REGEN_DISABLED" then
        self:OnCombatStart()
        return
    elseif evt == "PLAYER_REGEN_ENABLED" then
        self:OnCombatEnd()
        return
    elseif evt == "CHAT_MSG_COMBAT_HOSTILE_DEATH" then
        -- Could reset threat for dead mob, but we clear on combat end
        return
    end

    -- Parse combat messages for threat accumulation
    if a1 and inCombat then
        self:ParseThreatFromMessage(evt, a1)
    end
end

------------------------------------------------------------
-- Combat state
------------------------------------------------------------
function Threat:OnCombatStart()
    inCombat  = true
    fadeTimer = 0
    threatTable = {} -- reset threat on new combat

    -- Pre-populate all group members so they show immediately
    local playerName = UnitName("player")
    ArcaneWatch.IterGroupUnits(function(unit)
        local name = UnitName(unit)
        if not name then return end
        local _, class = UnitClass(unit)
        threatTable[name] = {
            threat   = 0,
            class    = class,
            isPlayer = (name == playerName),
        }
    end)

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
-- Parse combat log messages to accumulate threat
------------------------------------------------------------
function Threat:ParseThreatFromMessage(evt, msg)
    local amount = 0
    local source = nil

    -- Try to extract damage amounts and source names from combat messages
    -- Melee: "Playername hits Mob for 123."
    -- Spell: "Playername's Spell hits Mob for 123."
    -- Your: "Your Spell hits Mob for 123." / "You hit Mob for 123."
    -- Periodic: "Playername's Spell crits Mob for 123."

    -- Pattern: "Your X hits/crits Target for N"
    local amt = nil

    -- Self melee: "You hit Target for N."
    amt = string.match(msg, "^You hit .+ for (%d+)")
    if amt then
        source = UnitName("player")
        amount = tonumber(amt) or 0
    end

    -- Self crit melee: "You crit Target for N."
    if not source then
        amt = string.match(msg, "^You crit .+ for (%d+)")
        if amt then
            source = UnitName("player")
            amount = tonumber(amt) or 0
        end
    end

    -- Self spell: "Your Spell hits Target for N."
    if not source then
        amt = string.match(msg, "^Your .+ hits .+ for (%d+)")
        if amt then
            source = UnitName("player")
            amount = tonumber(amt) or 0
        end
    end

    -- Self spell crit: "Your Spell crits Target for N."
    if not source then
        amt = string.match(msg, "^Your .+ crits .+ for (%d+)")
        if amt then
            source = UnitName("player")
            amount = tonumber(amt) or 0
        end
    end

    -- Self periodic: "Target suffers N ... damage from your Spell."
    if not source then
        amt = string.match(msg, "suffers (%d+) .+ from your")
        if amt then
            source = UnitName("player")
            amount = tonumber(amt) or 0
        end
    end

    -- Other player melee: "Playername hits Target for N."
    if not source then
        local who
        who, amt = string.match(msg, "^(.+) hits .+ for (%d+)")
        if who and amt then
            source = who
            amount = tonumber(amt) or 0
        end
    end

    -- Other player crit: "Playername crits Target for N."
    if not source then
        local who
        who, amt = string.match(msg, "^(.+) crits .+ for (%d+)")
        if who and amt then
            source = who
            amount = tonumber(amt) or 0
        end
    end

    -- Other player spell: "Playername's Spell hits Target for N."
    if not source then
        local who
        who, amt = string.match(msg, "^(.+)'s .+ hits .+ for (%d+)")
        if who and amt then
            source = who
            amount = tonumber(amt) or 0
        end
    end

    -- Other player spell crit: "Playername's Spell crits Target for N."
    if not source then
        local who
        who, amt = string.match(msg, "^(.+)'s .+ crits .+ for (%d+)")
        if who and amt then
            source = who
            amount = tonumber(amt) or 0
        end
    end

    -- Other periodic: "Target suffers N ... from Playername's Spell."
    if not source then
        local who
        amt, who = string.match(msg, "suffers (%d+) .+ from (.+)'s")
        if who and amt then
            source = who
            amount = tonumber(amt) or 0
        end
    end

    -- Healing events (generate threat too): "Playername's Spell heals Target for N."
    if not source then
        local who
        who, amt = string.match(msg, "^(.+)'s .+ heals .+ for (%d+)")
        if who and amt then
            source = who
            amount = (tonumber(amt) or 0) * HEAL_THREAT_MOD
        end
    end

    -- Self healing: "Your Spell heals Target for N."
    if not source then
        amt = string.match(msg, "^Your .+ heals .+ for (%d+)")
        if amt then
            source = UnitName("player")
            amount = (tonumber(amt) or 0) * HEAL_THREAT_MOD
        end
    end

    -- Accumulate threat if we found a group member
    if source and amount > 0 then
        self:AddThreat(source, amount * DAMAGE_THREAT_MOD)
    end
end

------------------------------------------------------------
-- Add threat for a source (only if they're in the group)
------------------------------------------------------------
function Threat:AddThreat(name, amount)
    if not name then return end

    -- Check if this person is in our group
    local entry = threatTable[name]
    if entry then
        entry.threat = entry.threat + amount
    else
        -- Maybe they joined mid-combat; check if they're in the group
        local inGroup = false
        local _, class = nil, nil
        local playerName = UnitName("player")
        ArcaneWatch.IterGroupUnits(function(unit)
            local uname = UnitName(unit)
            if uname == name then
                inGroup = true
                _, class = UnitClass(unit)
            end
        end)
        if inGroup then
            threatTable[name] = {
                threat   = amount,
                class    = class,
                isPlayer = (name == playerName),
            }
        end
    end
end

------------------------------------------------------------
-- Poll: try API-based threat first, fall back to combat log
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
            local alpha = (fadeTimer / FADE_DELAY) * (ArcaneWatch.Config.db.opacity or 0.85)
            ArcaneWatch.UI.threatPanel:SetAlpha(alpha)
        end
        if fadeTimer <= 0 then return end
    end

    if not ArcaneWatch.Config:Get("threatEnabled") then return end

    -- Try API-based threat (Turtle WoW)
    local apiWorked = false
    if UnitDetailedThreatSituation and UnitExists("target") then
        apiWorked = self:PollAPI()
    end

    -- Fall back to combat-log accumulated threat
    if not apiWorked then
        self:PollCombatLog()
    end
end

------------------------------------------------------------
-- API-based threat polling (Turtle WoW extended API)
------------------------------------------------------------
function Threat:PollAPI()
    local target = "target"
    local data = {}
    local playerName = UnitName("player")
    local anyData = false

    ArcaneWatch.IterGroupUnits(function(unit)
        local name = UnitName(unit)
        if not name then return end

        local isTanking, status, threatPct, rawThreat, threatValue =
            UnitDetailedThreatSituation(unit, target)

        if threatPct and threatPct > 0 then
            anyData = true
        end

        local threat = threatPct or 0
        local _, class = UnitClass(unit)

        -- If player is tanking, API returns 100 for them
        if isTanking then threat = 100 end

        table.insert(data, {
            name     = name,
            threat   = threat,
            class    = class,
            isPlayer = (name == playerName),
        })
    end)

    if not anyData then return false end

    -- Sort and display
    table.sort(data, function(a, b) return a.threat > b.threat end)
    self:UpdateRows(data)
    return true
end

------------------------------------------------------------
-- Combat-log based threat display
------------------------------------------------------------
function Threat:PollCombatLog()
    local data = {}
    for name, entry in pairs(threatTable) do
        table.insert(data, {
            name     = name,
            threat   = entry.threat,
            class    = entry.class,
            isPlayer = entry.isPlayer,
        })
    end

    if #data == 0 then
        self:ClearRows()
        return
    end

    table.sort(data, function(a, b) return a.threat > b.threat end)
    self:UpdateRows(data)
end

------------------------------------------------------------
-- Update UI rows from sorted threat data
------------------------------------------------------------
function Threat:UpdateRows(data)
    local rows = ArcaneWatch.UI.threatRows
    if not rows then return end

    -- Find max threat for normalization
    local maxThreat = 1
    if data[1] and data[1].threat > 0 then
        maxThreat = data[1].threat
    end

    for i = 1, 5 do
        local row = rows[i]
        local d = data[i]
        if d then
            -- Normalize bar fill: top threat = 100%
            local barPct = (d.threat / maxThreat) * 100
            -- Display percentage relative to top threat holder
            local displayPct = barPct

            row.nameText:SetText(d.name)
            row.pctText:SetText(string.format("%.0f%%", displayPct))
            row.bar:SetValue(barPct)

            -- Class-color the bar
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
