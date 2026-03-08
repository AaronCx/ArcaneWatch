------------------------------------------------------------
-- ArcaneWatch_Threat.lua  (v1.10.0)
-- Threat meter with:
--   - Hybrid API + combat-log threat tracking
--   - Per-target threat tables (reset on target death/switch)
--   - Raid-level combat log events
--   - HoT tick parsing
--   - High-threat warning flash + sound
--   - Dynamic panel resizing
--   - Proper delta-time fade
------------------------------------------------------------

ArcaneWatch.Threat = {}

local Threat = ArcaneWatch.Threat
local POLL_INTERVAL = 0.2
local FADE_DELAY    = 3.0

local realElapsed = 0
local inCombat    = false
local fadeTimer   = 0
local fadeDelta   = 0  -- accumulates real arg1 for fade

-- Per-target threat: threatTargets[targetGUID or name] = { [playerName] = { threat, class, isPlayer } }
-- We key by current target name since vanilla has no GUID
local currentTarget = nil
local threatTargets = {}

-- Flat reference to current target's threat table for fast access
local threatTable = {}

-- Threat multipliers
local HEAL_THREAT_MOD   = 0.5
local DAMAGE_THREAT_MOD = 1.0

-- Warning state
local warnActive = false

------------------------------------------------------------
-- Init
------------------------------------------------------------
function Threat:Init()
    self.frame = CreateFrame("Frame", "ArcaneWatchThreatLogic", UIParent)

    -- Combat state
    self.frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    self.frame:RegisterEvent("PLAYER_REGEN_ENABLED")

    -- Target changes (for per-target tracking)
    self.frame:RegisterEvent("PLAYER_TARGET_CHANGED")

    -- Self combat log events
    self.frame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
    self.frame:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
    self.frame:RegisterEvent("CHAT_MSG_SPELL_SELF_BUFF")
    self.frame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE")
    self.frame:RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES")
    self.frame:RegisterEvent("CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF")

    -- Party combat log events
    self.frame:RegisterEvent("CHAT_MSG_SPELL_PARTY_DAMAGE")
    self.frame:RegisterEvent("CHAT_MSG_COMBAT_PARTY_HITS")
    self.frame:RegisterEvent("CHAT_MSG_SPELL_PARTY_BUFF")
    self.frame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_PARTY_DAMAGE")
    self.frame:RegisterEvent("CHAT_MSG_COMBAT_PARTY_MISSES")
    self.frame:RegisterEvent("CHAT_MSG_SPELL_DAMAGESHIELDS_ON_OTHERS")

    -- Raid / friendly player combat log events (Phase 3)
    self.frame:RegisterEvent("CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE")
    self.frame:RegisterEvent("CHAT_MSG_COMBAT_FRIENDLYPLAYER_HITS")
    self.frame:RegisterEvent("CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF")
    self.frame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE")
    self.frame:RegisterEvent("CHAT_MSG_COMBAT_FRIENDLYPLAYER_MISSES")

    -- Periodic healing (HoT ticks) for self, party, raid
    self.frame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS")
    self.frame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS")
    self.frame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS")

    -- Creature events
    self.frame:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE")
    self.frame:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_CREATURE_HITS")
    self.frame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE")

    -- Death events for threat reset
    self.frame:RegisterEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH")

    local this = self
    self.frame:SetScript("OnEvent", function()
        this:OnEvent(event, arg1, arg2, arg3)
    end)

    self.frame:SetScript("OnUpdate", function()
        local dt = arg1
        realElapsed = realElapsed + dt
        fadeDelta = fadeDelta + dt
        if realElapsed < POLL_INTERVAL then return end
        realElapsed = 0
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
    elseif evt == "PLAYER_TARGET_CHANGED" then
        self:OnTargetChanged()
        return
    elseif evt == "CHAT_MSG_COMBAT_HOSTILE_DEATH" then
        -- Clear threat for dead mob if it matches current target
        if a1 and currentTarget and string.find(a1, currentTarget, 1, true) then
            threatTargets[currentTarget] = nil
            threatTable = {}
        end
        return
    end

    -- Parse combat messages for threat accumulation
    if a1 and inCombat then
        self:ParseThreatFromMessage(evt, a1)
    end
end

------------------------------------------------------------
-- Target changed: switch threat table view
------------------------------------------------------------
function Threat:OnTargetChanged()
    local name = UnitName("target")
    if name then
        currentTarget = name
        if not threatTargets[name] then
            threatTargets[name] = {}
        end
        threatTable = threatTargets[name]
    else
        currentTarget = nil
        threatTable = {}
    end
end

------------------------------------------------------------
-- Combat state
------------------------------------------------------------
function Threat:OnCombatStart()
    inCombat  = true
    fadeTimer = 0
    fadeDelta = 0
    warnActive = false
    threatTargets = {}
    threatTable = {}

    -- Set current target
    self:OnTargetChanged()

    -- Pre-populate group members
    local playerName = UnitName("player")
    ArcaneWatch.IterGroupUnits(function(unit)
        local name = UnitName(unit)
        if not name then return end
        local _, class = UnitClass(unit)
        if currentTarget and threatTargets[currentTarget] then
            threatTargets[currentTarget][name] = {
                threat   = 0,
                class    = class,
                isPlayer = (name == playerName),
            }
        end
    end)
    if currentTarget then
        threatTable = threatTargets[currentTarget] or {}
    end

    local db = ArcaneWatch.Config.db
    if db.threatEnabled then
        ArcaneWatch.UI.threatPanel:SetAlpha(db.opacity or 0.85)
        ArcaneWatch.UI.threatPanel:Show()
    end
end

function Threat:OnCombatEnd()
    inCombat  = false
    fadeTimer = FADE_DELAY
    fadeDelta = 0
    warnActive = false
    ArcaneWatch.UI:FlashThreatWarning(false)
end

------------------------------------------------------------
-- Parse combat log messages to accumulate threat
-- Uses string.find with captures (Lua 5.0 compatible)
------------------------------------------------------------
function Threat:ParseThreatFromMessage(evt, msg)
    local amount = 0
    local source = nil
    local _, _, amt

    -- Self melee: "You hit/crit Target for N."
    _, _, amt = string.find(msg, "^You hit .+ for (%d+)")
    if not amt then
        _, _, amt = string.find(msg, "^You crit .+ for (%d+)")
    end
    if amt then
        source = UnitName("player")
        amount = tonumber(amt) or 0
    end

    -- Self spell: "Your Spell hits/crits Target for N."
    if not source then
        _, _, amt = string.find(msg, "^Your .+ hits .+ for (%d+)")
        if not amt then
            _, _, amt = string.find(msg, "^Your .+ crits .+ for (%d+)")
        end
        if amt then
            source = UnitName("player")
            amount = tonumber(amt) or 0
        end
    end

    -- Self periodic damage: "Target suffers N ... from your Spell."
    if not source then
        _, _, amt = string.find(msg, "suffers (%d+) .+ from your")
        if amt then
            source = UnitName("player")
            amount = tonumber(amt) or 0
        end
    end

    -- Self healing: "Your Spell heals Target for N."
    if not source then
        _, _, amt = string.find(msg, "^Your .+ heals .+ for (%d+)")
        if amt then
            source = UnitName("player")
            amount = (tonumber(amt) or 0) * HEAL_THREAT_MOD
        end
    end

    -- Self HoT tick: "Target gains N health from your Spell."
    if not source then
        _, _, amt = string.find(msg, "gains (%d+) health from your")
        if amt then
            source = UnitName("player")
            amount = (tonumber(amt) or 0) * HEAL_THREAT_MOD
        end
    end

    -- Other player melee: "Playername hits/crits Target for N."
    if not source then
        local who
        _, _, who, amt = string.find(msg, "^(.+) hits .+ for (%d+)")
        if not who then
            _, _, who, amt = string.find(msg, "^(.+) crits .+ for (%d+)")
        end
        if who and amt then
            source = who
            amount = tonumber(amt) or 0
        end
    end

    -- Other player spell: "Playername's Spell hits/crits Target for N."
    if not source then
        local who
        _, _, who, amt = string.find(msg, "^(.+)'s .+ hits .+ for (%d+)")
        if not who then
            _, _, who, amt = string.find(msg, "^(.+)'s .+ crits .+ for (%d+)")
        end
        if who and amt then
            source = who
            amount = tonumber(amt) or 0
        end
    end

    -- Other periodic damage: "Target suffers N ... from Playername's Spell."
    if not source then
        local who
        _, _, amt, who = string.find(msg, "suffers (%d+) .+ from (.+)'s")
        if who and amt then
            source = who
            amount = tonumber(amt) or 0
        end
    end

    -- Other healing: "Playername's Spell heals Target for N."
    if not source then
        local who
        _, _, who, amt = string.find(msg, "^(.+)'s .+ heals .+ for (%d+)")
        if who and amt then
            source = who
            amount = (tonumber(amt) or 0) * HEAL_THREAT_MOD
        end
    end

    -- Other HoT tick: "Target gains N health from Playername's Spell."
    if not source then
        local who
        _, _, amt, who = string.find(msg, "gains (%d+) health from (.+)'s")
        if who and amt then
            source = who
            amount = (tonumber(amt) or 0) * HEAL_THREAT_MOD
        end
    end

    -- Accumulate
    if source and amount > 0 then
        self:AddThreat(source, amount * DAMAGE_THREAT_MOD)
    end
end

------------------------------------------------------------
-- Add threat (into current target's table)
------------------------------------------------------------
function Threat:AddThreat(name, amount)
    if not name or not currentTarget then return end

    if not threatTargets[currentTarget] then
        threatTargets[currentTarget] = {}
    end
    local tbl = threatTargets[currentTarget]

    local entry = tbl[name]
    if entry then
        entry.threat = entry.threat + amount
    else
        -- Check if in group
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
            tbl[name] = {
                threat   = amount,
                class    = class,
                isPlayer = (name == playerName),
            }
        end
    end
    -- Keep the flat reference in sync
    threatTable = threatTargets[currentTarget]
end

------------------------------------------------------------
-- Poll
------------------------------------------------------------
function Threat:OnPoll()
    -- Fade-out after combat using real accumulated delta
    if not inCombat then
        if fadeTimer > 0 then
            fadeTimer = fadeTimer - fadeDelta
            fadeDelta = 0
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
    else
        fadeDelta = 0  -- reset delta accumulator while in combat
    end

    if not ArcaneWatch.Config:Get("threatEnabled") then return end

    -- Try API first
    local apiWorked = false
    if UnitDetailedThreatSituation and UnitExists("target") then
        apiWorked = self:PollAPI()
    end

    if not apiWorked then
        self:PollCombatLog()
    end
end

------------------------------------------------------------
-- API-based threat polling (Turtle WoW)
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
        if isTanking then threat = 100 end

        table.insert(data, {
            name     = name,
            threat   = threat,
            raw      = rawThreat or threat,
            class    = class,
            isPlayer = (name == playerName),
        })
    end)

    if not anyData then return false end

    table.sort(data, function(a, b) return a.threat > b.threat end)
    self:UpdateRows(data)
    self:CheckThreatWarning(data, playerName)
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
            raw      = entry.threat,
            class    = entry.class,
            isPlayer = entry.isPlayer,
        })
    end

    if table.getn(data) == 0 then
        self:ClearRows()
        ArcaneWatch.UI:SetThreatRowCount(1)
        return
    end

    table.sort(data, function(a, b) return a.threat > b.threat end)
    self:UpdateRows(data)

    local playerName = UnitName("player")
    self:CheckThreatWarning(data, playerName)
end

------------------------------------------------------------
-- Update UI rows + dynamic panel height
------------------------------------------------------------
function Threat:UpdateRows(data)
    local rows = ArcaneWatch.UI.threatRows
    if not rows then return end

    local maxThreat = 1
    if data[1] and data[1].threat > 0 then
        maxThreat = data[1].threat
    end

    local visibleCount = 0
    for i = 1, 5 do
        local row = rows[i]
        local d = data[i]
        if d then
            local barPct = (d.threat / maxThreat) * 100
            row.nameText:SetText(d.name)
            row.pctText:SetText(string.format("%.0f%%", barPct))
            row.bar:SetValue(barPct)
            row.frame.rawThreat = d.raw

            local cc = ArcaneWatch.classColors[d.class]
            if cc then
                row.bar:SetStatusBarColor(cc[1], cc[2], cc[3], 0.85)
            else
                row.bar:SetStatusBarColor(0.4, 0.6, 0.8, 0.85)
            end

            if d.isPlayer then
                row.glow:Show()
            else
                row.glow:Hide()
            end

            row.frame:Show()
            visibleCount = visibleCount + 1
        else
            row.frame:Hide()
        end
    end

    -- Dynamic panel height
    if visibleCount > 0 then
        ArcaneWatch.UI:SetThreatRowCount(visibleCount)
    end
end

------------------------------------------------------------
-- Threat warning: flash + sound when player > threshold
------------------------------------------------------------
function Threat:CheckThreatWarning(data, playerName)
    local db = ArcaneWatch.Config.db
    local threshold = db.threatWarnPct or 90

    -- Find player's percentage relative to top threat
    if not data[1] or data[1].threat <= 0 then
        if warnActive then
            warnActive = false
            ArcaneWatch.UI:FlashThreatWarning(false)
        end
        return
    end

    local maxThreat = data[1].threat
    local playerThreat = 0
    local playerIsTop = false

    for i = 1, table.getn(data) do
        if data[i].isPlayer then
            playerThreat = data[i].threat
            if i == 1 then playerIsTop = true end
            break
        end
    end

    -- If player IS the top threat and alone, no warning needed
    local playerPct = (playerThreat / maxThreat) * 100
    local shouldWarn = (playerPct >= threshold) and (not playerIsTop or table.getn(data) == 1)

    -- Actually warn if player is at threshold of the TOP person (and isn't the tank)
    -- Simpler: warn if player's % of top > threshold and player is not rank 1
    shouldWarn = (playerPct >= threshold) and (not playerIsTop)

    if shouldWarn and not warnActive then
        warnActive = true
        ArcaneWatch.UI:FlashThreatWarning(true)
        if db.threatWarnSound then
            ArcaneWatch.PlaySound("igQuestFailed")
        end
    elseif not shouldWarn and warnActive then
        warnActive = false
        ArcaneWatch.UI:FlashThreatWarning(false)
    end

    -- Animate warning pulse
    if warnActive then
        local now = GetTime()
        local alpha = 0.15 + 0.15 * math.abs(math.sin(now * 4))
        ArcaneWatch.UI:SetThreatWarningAlpha(alpha)
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
    warnActive = false
    ArcaneWatch.UI:FlashThreatWarning(false)
end
