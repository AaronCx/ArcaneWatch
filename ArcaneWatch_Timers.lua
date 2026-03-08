------------------------------------------------------------
-- ArcaneWatch_Timers.lua  (v1.10.0)
-- Spell cooldown / timer tracker.
--
-- Features:
--   - Auto-detects spells from spellbook
--   - Cleaned duration table (no cast-time entries)
--   - Each entry has a type: "cd" (cooldown) or "dur" (buff/debuff)
--   - Filters out resist/immune/miss false positives
--   - Syncs with GetSpellCooldown on login/reload
--   - Sound alert when timer returns to Ready
--   - Tooltip shows spell type and duration
------------------------------------------------------------

ArcaneWatch.Timers = {}

local Timers = ArcaneWatch.Timers
local MAX_TRACKED = 9

-- Spell data: { duration, type }
-- type: "dur" = buff/debuff duration, "cd" = ability cooldown
local SPELL_DATA = {
    -- Warlock
    ["Corruption"]            = { 18,  "dur" },
    ["Curse of Agony"]        = { 24,  "dur" },
    ["Unstable Affliction"]   = { 18,  "dur" },
    ["Siphon Life"]           = { 30,  "dur" },
    ["Fear"]                  = { 20,  "dur" },
    ["Death Coil"]            = { 120, "cd"  },
    ["Shadowburn"]            = { 15,  "cd"  },
    ["Immolate"]              = { 15,  "dur" },
    ["Conflagrate"]           = { 10,  "cd"  },
    ["Curse of the Elements"] = { 300, "dur" },
    ["Curse of Tongues"]      = { 30,  "dur" },
    ["Drain Life"]            = { 5,   "dur" },
    ["Drain Soul"]            = { 15,  "dur" },
    ["Howl of Terror"]        = { 40,  "cd"  },
    ["Shadowfury"]            = { 20,  "cd"  },
    ["Banish"]                = { 30,  "dur" },
    ["Curse of Doom"]         = { 60,  "dur" },
    -- Mage
    ["Polymorph"]             = { 50,  "dur" },
    ["Ice Barrier"]           = { 60,  "cd"  },
    ["Frost Nova"]            = { 25,  "cd"  },
    ["Fire Blast"]            = { 8,   "cd"  },
    ["Cone of Cold"]          = { 10,  "cd"  },
    ["Counterspell"]          = { 30,  "cd"  },
    ["Arcane Power"]          = { 180, "cd"  },
    ["Combustion"]            = { 180, "cd"  },
    ["Ice Block"]             = { 300, "cd"  },
    ["Evocation"]             = { 480, "cd"  },
    ["Presence of Mind"]      = { 180, "cd"  },
    ["Blink"]                 = { 15,  "cd"  },
    -- Priest
    ["Shadow Word: Pain"]     = { 18,  "dur" },
    ["Renew"]                 = { 15,  "dur" },
    ["Power Word: Shield"]    = { 30,  "dur" },
    ["Mind Blast"]            = { 8,   "cd"  },
    ["Psychic Scream"]        = { 30,  "cd"  },
    ["Fade"]                  = { 30,  "cd"  },
    ["Inner Focus"]           = { 180, "cd"  },
    ["Devouring Plague"]      = { 24,  "dur" },
    ["Vampiric Embrace"]      = { 60,  "dur" },
    ["Silence"]               = { 45,  "cd"  },
    ["Power Infusion"]        = { 180, "cd"  },
    ["Desperate Prayer"]      = { 600, "cd"  },
    -- Druid
    ["Rejuvenation"]          = { 12,  "dur" },
    ["Regrowth"]              = { 21,  "dur" },
    ["Moonfire"]              = { 12,  "dur" },
    ["Insect Swarm"]          = { 12,  "dur" },
    ["Entangling Roots"]      = { 27,  "dur" },
    ["Faerie Fire"]           = { 40,  "dur" },
    ["Barkskin"]              = { 60,  "cd"  },
    ["Innervate"]             = { 360, "cd"  },
    ["Nature's Swiftness"]    = { 180, "cd"  },
    ["Bash"]                  = { 60,  "cd"  },
    ["Frenzied Regeneration"] = { 180, "cd"  },
    -- Rogue
    ["Slice and Dice"]        = { 21,  "dur" },
    ["Rupture"]               = { 16,  "dur" },
    ["Kidney Shot"]           = { 20,  "cd"  },
    ["Blind"]                 = { 300, "cd"  },
    ["Vanish"]                = { 300, "cd"  },
    ["Sprint"]                = { 300, "cd"  },
    ["Evasion"]               = { 300, "cd"  },
    ["Adrenaline Rush"]       = { 300, "cd"  },
    ["Blade Flurry"]          = { 120, "cd"  },
    ["Cold Blood"]            = { 180, "cd"  },
    ["Preparation"]           = { 600, "cd"  },
    ["Gouge"]                 = { 10,  "cd"  },
    ["Kick"]                  = { 10,  "cd"  },
    ["Expose Armor"]          = { 30,  "dur" },
    -- Warrior
    ["Rend"]                  = { 21,  "dur" },
    ["Thunder Clap"]          = { 30,  "dur" },
    ["Hamstring"]             = { 15,  "dur" },
    ["Shield Block"]          = { 5,   "cd"  },
    ["Shield Wall"]           = { 1800,"cd"  },
    ["Recklessness"]          = { 1800,"cd"  },
    ["Retaliation"]           = { 1800,"cd"  },
    ["Berserker Rage"]        = { 30,  "cd"  },
    ["Bloodrage"]             = { 60,  "cd"  },
    ["Intimidating Shout"]    = { 120, "cd"  },
    ["Mortal Strike"]         = { 6,   "cd"  },
    ["Bloodthirst"]           = { 6,   "cd"  },
    ["Whirlwind"]             = { 10,  "cd"  },
    ["Overpower"]             = { 5,   "cd"  },
    ["Pummel"]                = { 10,  "cd"  },
    ["Shield Slam"]           = { 6,   "cd"  },
    -- Hunter
    ["Serpent Sting"]         = { 15,  "dur" },
    ["Multi-Shot"]            = { 10,  "cd"  },
    ["Aimed Shot"]            = { 6,   "cd"  },
    ["Arcane Shot"]           = { 6,   "cd"  },
    ["Concussive Shot"]       = { 12,  "cd"  },
    ["Rapid Fire"]            = { 300, "cd"  },
    ["Feign Death"]           = { 30,  "cd"  },
    ["Freezing Trap"]         = { 30,  "cd"  },
    ["Frost Trap"]            = { 30,  "cd"  },
    ["Intimidation"]          = { 60,  "cd"  },
    ["Bestial Wrath"]         = { 120, "cd"  },
    ["Deterrence"]            = { 300, "cd"  },
    ["Scatter Shot"]          = { 30,  "cd"  },
    -- Paladin
    ["Judgement"]              = { 10,  "cd"  },
    ["Blessing of Protection"] = { 300, "cd"  },
    ["Blessing of Freedom"]   = { 25,  "dur" },
    ["Hammer of Justice"]     = { 60,  "cd"  },
    ["Divine Shield"]         = { 300, "cd"  },
    ["Lay on Hands"]          = { 3600,"cd"  },
    ["Holy Shock"]            = { 30,  "cd"  },
    ["Consecration"]          = { 8,   "dur" },
    ["Exorcism"]              = { 15,  "cd"  },
    ["Repentance"]            = { 60,  "cd"  },
    -- Shaman
    ["Flame Shock"]           = { 12,  "dur" },
    ["Frost Shock"]           = { 6,   "cd"  },
    ["Earth Shock"]           = { 6,   "cd"  },
    ["Stormstrike"]           = { 10,  "cd"  },
    ["Elemental Mastery"]     = { 180, "cd"  },
    ["Grounding Totem"]       = { 15,  "cd"  },
    ["Fire Nova Totem"]       = { 15,  "cd"  },
    ["Chain Lightning"]       = { 6,   "cd"  },
}

-- Timer states
local STATE_READY  = 1
local STATE_ACTIVE = 2

-- Per-spell state
local spellStates = {}

-- Fail patterns: skip timer if message indicates resist/immune/miss
local FAIL_PATTERNS = {
    "was resisted",
    "was immune",
    "was evaded",
    "was dodged",
    "was parried",
    "was blocked",
    "missed",
    "immune",
    "absorb",
    "resist",
}

-- OnUpdate accumulator
local elapsed = 0
local UPDATE_INTERVAL = 0.05

------------------------------------------------------------
-- Init
------------------------------------------------------------
function Timers:Init()
    self.frame = CreateFrame("Frame", "ArcaneWatchTimerLogic", UIParent)

    -- Vanilla combat log events
    self.frame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
    self.frame:RegisterEvent("CHAT_MSG_SPELL_SELF_BUFF")
    self.frame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE")
    self.frame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE")
    self.frame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE")

    -- Turtle WoW extended events
    self.frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    self.frame:RegisterEvent("UNIT_SPELLCAST_SENT")

    -- Spellbook changes
    self.frame:RegisterEvent("SPELLS_CHANGED")
    self.frame:RegisterEvent("PLAYER_ENTERING_WORLD")

    local this = self
    self.frame:SetScript("OnEvent", function()
        if event == "SPELLS_CHANGED" then
            this:ScanSpellbook()
            return
        elseif event == "PLAYER_ENTERING_WORLD" then
            this:ScanSpellbook()
            this:SyncCooldowns()
            return
        end
        this:OnEvent(event, arg1, arg2, arg3)
    end)

    self.frame:SetScript("OnUpdate", function()
        elapsed = elapsed + arg1
        if elapsed < UPDATE_INTERVAL then return end
        elapsed = 0
        this:OnUpdate()
    end)

    self:ScanSpellbook()
end

------------------------------------------------------------
-- Scan spellbook
------------------------------------------------------------
function Timers:ScanSpellbook()
    local found = {}
    local seen = {}

    -- Check for user custom overrides
    local customSpells = ArcaneWatch.Config:Get("customSpells")

    local bookType = "spell"
    local i = 1
    while true do
        local name, rank = GetSpellName(i, bookType)
        if not name then break end

        if SPELL_DATA[name] and not seen[name] then
            seen[name] = true
            local texture = GetSpellTexture(i, bookType)
            local data = SPELL_DATA[name]
            table.insert(found, {
                name     = name,
                texture  = texture,
                duration = data[1],
                type     = data[2],
                bookId   = i,
            })
        end

        i = i + 1
    end

    -- Cap at MAX_TRACKED
    self.trackedSpells = {}
    for j = 1, MAX_TRACKED do
        if found[j] then
            self.trackedSpells[j] = found[j]
        end
    end

    -- Init state
    for j, spell in ipairs(self.trackedSpells) do
        if not spellStates[spell.name] then
            spellStates[spell.name] = {
                state     = STATE_READY,
                startTime = 0,
                duration  = spell.duration,
            }
        end
    end

    self:SetupTimerRows()
end

------------------------------------------------------------
-- Sync cooldowns with GetSpellCooldown on login/reload
------------------------------------------------------------
function Timers:SyncCooldowns()
    if not self.trackedSpells then return end
    if not GetSpellCooldown then return end

    local now = GetTime()
    for i, spell in ipairs(self.trackedSpells) do
        if spell.bookId and spell.type == "cd" then
            local start, dur, enabled = GetSpellCooldown(spell.bookId, "spell")
            if start and start > 0 and dur and dur > 1.5 then
                -- Spell is on cooldown (ignore GCD which is <= 1.5)
                local remaining = (start + dur) - now
                if remaining > 0 then
                    spellStates[spell.name] = {
                        state     = STATE_ACTIVE,
                        startTime = start,
                        duration  = dur,
                    }
                end
            end
        end
    end
end

------------------------------------------------------------
-- Setup timer row visuals
------------------------------------------------------------
function Timers:SetupTimerRows()
    local rows = ArcaneWatch.UI.timerRows
    if not rows or not self.trackedSpells then return end

    for i = 1, MAX_TRACKED do
        local row = rows[i]
        if not row then break end
        local spell = self.trackedSpells[i]
        if spell then
            if spell.texture then
                row.icon:SetTexture(spell.texture)
            else
                row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            end
            row.nameText:SetText(spell.name)
            row.spellDuration = spell.duration
            row.spellType = spell.type == "cd" and "Cooldown" or "Duration"

            -- Initial visual based on current state
            local ss = spellStates[spell.name]
            if ss and ss.state == STATE_ACTIVE then
                row.bar:SetValue(1)
                row.bar:SetStatusBarColor(0.3, 0.5, 0.9, 0.9)
                row.timeText:SetText("")
            else
                row.bar:SetValue(1)
                row.bar:SetStatusBarColor(0.2, 0.8, 0.3, 0.8)
                row.timeText:SetText("Ready")
                row.timeText:SetTextColor(0.3, 1.0, 0.3, 1)
            end
            row.icon:SetAlpha(1.0)
            row.frame:Show()
        else
            row.frame:Hide()
        end
    end

    local count = table.getn(self.trackedSpells)
    local panelH = 22 + count * 20 + 6
    ArcaneWatch.UI.timersPanel:SetHeight(panelH)
end

------------------------------------------------------------
-- Event: detect spell casts
------------------------------------------------------------
function Timers:OnEvent(evt, a1, a2, a3)
    if not ArcaneWatch.Config:Get("timersEnabled") then return end

    if evt == "UNIT_SPELLCAST_SUCCEEDED" or evt == "UNIT_SPELLCAST_SENT" then
        if a1 == "player" and a2 then
            self:OnSpellCast(a2)
        end
        return
    end

    if a1 then
        self:ParseCombatMessage(a1)
    end
end

------------------------------------------------------------
-- Parse combat log — filter out resists/immunes
------------------------------------------------------------
function Timers:ParseCombatMessage(msg)
    if not self.trackedSpells then return end

    -- Only our casts
    if not (string.find(msg, "^Your ") or string.find(msg, "^You ")) then
        return
    end

    -- Check if this is a fail message (resist, immune, miss, etc.)
    local msgLower = string.lower(msg)
    for _, pattern in ipairs(FAIL_PATTERNS) do
        if string.find(msgLower, pattern, 1, true) then
            return  -- spell failed, don't start timer
        end
    end

    for i, spell in ipairs(self.trackedSpells) do
        if string.find(msg, spell.name, 1, true) then
            self:OnSpellCast(spell.name)
            return
        end
    end
end

------------------------------------------------------------
-- Handle a spell cast
------------------------------------------------------------
function Timers:OnSpellCast(spellName)
    if not self.trackedSpells then return end

    for i, spell in ipairs(self.trackedSpells) do
        if spell.name == spellName then
            local dur = spell.duration
            if dur and dur > 0 then
                spellStates[spellName] = {
                    state     = STATE_ACTIVE,
                    startTime = GetTime(),
                    duration  = dur,
                }
            end
            return
        end
    end
end

------------------------------------------------------------
-- OnUpdate: render timer rows
------------------------------------------------------------
function Timers:OnUpdate()
    if not ArcaneWatch.Config:Get("timersEnabled") then return end
    if not self.trackedSpells then return end

    local now = GetTime()
    local rows = ArcaneWatch.UI.timerRows
    local db = ArcaneWatch.Config.db

    for i, spell in ipairs(self.trackedSpells) do
        local row = rows[i]
        if not row then break end

        local ss = spellStates[spell.name]
        if not ss then
            ss = { state = STATE_READY, startTime = 0, duration = spell.duration }
            spellStates[spell.name] = ss
        end

        if ss.state == STATE_ACTIVE then
            local remaining = ss.duration - (now - ss.startTime)

            if remaining <= 0 then
                -- Timer expired -> READY + sound
                ss.state = STATE_READY
                row.bar:SetValue(1)
                row.bar:SetStatusBarColor(0.2, 0.8, 0.3, 0.8)
                row.timeText:SetText("Ready")
                row.timeText:SetTextColor(0.3, 1.0, 0.3, 1)
                row.icon:SetAlpha(1.0)

                if db.timerReadySound then
                    ArcaneWatch.PlaySound("igPlayerInviteAccept")
                end
            else
                -- Active countdown
                local pct = remaining / ss.duration
                row.bar:SetValue(pct)
                row.timeText:SetText(ArcaneWatch.FormatTime(remaining))
                row.timeText:SetTextColor(1, 1, 1, 1)
                row.icon:SetAlpha(1.0)

                -- Color: blue -> yellow -> red
                local r, g, b
                if pct > 0.5 then
                    local t = (pct - 0.5) / 0.5
                    r = 0.9 - t * 0.6
                    g = 0.8 - t * 0.3
                    b = 0.2 + t * 0.7
                else
                    local t = pct / 0.5
                    r = 0.9
                    g = 0.2 + t * 0.6
                    b = 0.1 + t * 0.1
                end
                row.bar:SetStatusBarColor(r, g, b, 0.9)
            end

        else
            -- STATE_READY
            row.bar:SetValue(1)
            row.bar:SetStatusBarColor(0.2, 0.8, 0.3, 0.8)
            row.timeText:SetText("Ready")
            row.timeText:SetTextColor(0.3, 1.0, 0.3, 1)

            local pulse = 0.85 + 0.15 * math.sin(now * 2.5)
            row.icon:SetAlpha(pulse)
        end
    end
end
