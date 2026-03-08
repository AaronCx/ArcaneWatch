------------------------------------------------------------
-- ArcaneWatch_Timers.lua  (v1.2)
-- Spell cooldown / timer tracker.
--
-- Auto-detects spells from the player's spellbook that have
-- known durations/cooldowns. Shows up to 9 spells.
-- No hardcoded class list — works for any class.
--
-- State flow per spell:
--   READY  (green bar, "Ready" text, icon pulses)
--     -> cast detected ->
--   ACTIVE (bar drains, countdown text, blue->yellow->red)
--     -> timer expires ->
--   READY  (back to green, "Ready", pulse)
------------------------------------------------------------

ArcaneWatch.Timers = {}

local Timers = ArcaneWatch.Timers
local MAX_TRACKED = 9

-- Known spell durations/cooldowns (seconds).
-- Any spell in the player's spellbook that matches a key here
-- will be auto-tracked. Covers multiple classes.
local SPELL_DURATIONS = {
    -- Warlock
    ["Corruption"]            = 18,
    ["Curse of Agony"]        = 24,
    ["Unstable Affliction"]   = 18,
    ["Siphon Life"]           = 30,
    ["Fear"]                  = 20,
    ["Death Coil"]            = 120,
    ["Shadowburn"]            = 15,
    ["Immolate"]              = 15,
    ["Conflagrate"]           = 10,
    ["Curse of the Elements"] = 300,
    ["Curse of Tongues"]      = 30,
    ["Drain Life"]            = 5,
    ["Drain Soul"]            = 15,
    ["Howl of Terror"]        = 40,
    ["Shadowfury"]            = 20,
    ["Banish"]                = 30,
    ["Curse of Doom"]         = 60,
    ["Dark Pact"]             = 10,
    -- Mage
    ["Frostbolt"]             = 3,
    ["Fireball"]              = 3.5,
    ["Polymorph"]             = 50,
    ["Ice Barrier"]           = 60,
    ["Frost Nova"]            = 25,
    ["Fire Blast"]            = 8,
    ["Cone of Cold"]          = 10,
    ["Counterspell"]          = 30,
    ["Arcane Power"]          = 15,
    ["Combustion"]            = 180,
    ["Ice Block"]             = 300,
    ["Evocation"]             = 480,
    ["Presence of Mind"]      = 180,
    ["Blink"]                 = 15,
    ["Pyroblast"]             = 6,
    ["Scorch"]                = 2,
    -- Priest
    ["Shadow Word: Pain"]     = 18,
    ["Renew"]                 = 15,
    ["Power Word: Shield"]    = 30,
    ["Mind Blast"]            = 8,
    ["Psychic Scream"]        = 30,
    ["Fade"]                  = 30,
    ["Inner Focus"]           = 180,
    ["Devouring Plague"]      = 24,
    ["Vampiric Embrace"]      = 60,
    ["Silence"]               = 45,
    ["Power Infusion"]        = 180,
    ["Desperate Prayer"]      = 600,
    -- Druid
    ["Rejuvenation"]          = 12,
    ["Regrowth"]              = 21,
    ["Moonfire"]              = 12,
    ["Insect Swarm"]          = 12,
    ["Entangling Roots"]      = 27,
    ["Faerie Fire"]           = 40,
    ["Barkskin"]              = 60,
    ["Innervate"]             = 360,
    ["Nature's Swiftness"]    = 180,
    ["Bash"]                  = 60,
    ["Frenzied Regeneration"] = 180,
    -- Rogue
    ["Slice and Dice"]        = 21,
    ["Rupture"]               = 16,
    ["Kidney Shot"]           = 20,
    ["Blind"]                 = 300,
    ["Vanish"]                = 300,
    ["Sprint"]                = 300,
    ["Evasion"]               = 300,
    ["Adrenaline Rush"]       = 300,
    ["Blade Flurry"]          = 120,
    ["Cold Blood"]            = 180,
    ["Preparation"]           = 600,
    ["Gouge"]                 = 10,
    ["Kick"]                  = 10,
    ["Expose Armor"]          = 30,
    -- Warrior
    ["Rend"]                  = 21,
    ["Thunder Clap"]          = 30,
    ["Hamstring"]             = 15,
    ["Shield Block"]          = 5,
    ["Shield Wall"]           = 1800,
    ["Recklessness"]          = 1800,
    ["Retaliation"]           = 1800,
    ["Berserker Rage"]        = 30,
    ["Bloodrage"]             = 60,
    ["Intimidating Shout"]    = 8,
    ["Mortal Strike"]         = 6,
    ["Bloodthirst"]           = 6,
    ["Whirlwind"]             = 10,
    ["Overpower"]             = 5,
    ["Pummel"]                = 10,
    ["Shield Slam"]           = 6,
    -- Hunter
    ["Serpent Sting"]         = 15,
    ["Multi-Shot"]            = 10,
    ["Aimed Shot"]            = 6,
    ["Arcane Shot"]           = 6,
    ["Concussive Shot"]       = 12,
    ["Rapid Fire"]            = 300,
    ["Feign Death"]           = 30,
    ["Freezing Trap"]         = 30,
    ["Frost Trap"]            = 30,
    ["Intimidation"]          = 60,
    ["Bestial Wrath"]         = 120,
    ["Deterrence"]            = 300,
    ["Scatter Shot"]          = 30,
    -- Paladin
    ["Judgement"]              = 10,
    ["Blessing of Protection"] = 300,
    ["Blessing of Freedom"]   = 25,
    ["Hammer of Justice"]     = 60,
    ["Divine Shield"]         = 300,
    ["Lay on Hands"]          = 3600,
    ["Holy Shock"]            = 30,
    ["Consecration"]          = 8,
    ["Exorcism"]              = 15,
    ["Repentance"]            = 60,
    ["Avenger's Shield"]      = 30,
    -- Shaman
    ["Flame Shock"]           = 12,
    ["Frost Shock"]           = 6,
    ["Earth Shock"]           = 6,
    ["Stormstrike"]           = 10,
    ["Elemental Mastery"]     = 180,
    ["Nature's Swiftness"]    = 180,
    ["Grounding Totem"]       = 15,
    ["Fire Nova Totem"]       = 15,
    ["Chain Lightning"]       = 6,
    ["Purge"]                 = 5,
}

-- Timer states
local STATE_READY  = 1
local STATE_ACTIVE = 2

-- Per-spell state: { state, startTime, duration }
local spellStates = {}

-- OnUpdate accumulator
local elapsed = 0
local UPDATE_INTERVAL = 0.05

------------------------------------------------------------
-- Init
------------------------------------------------------------
function Timers:Init()
    self.frame = CreateFrame("Frame", "ArcaneWatchTimerLogic", UIParent)

    -- Vanilla combat log events for self-cast detection
    self.frame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
    self.frame:RegisterEvent("CHAT_MSG_SPELL_SELF_BUFF")
    self.frame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE")
    self.frame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE")
    self.frame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE")

    -- Turtle WoW extended events
    self.frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    self.frame:RegisterEvent("UNIT_SPELLCAST_SENT")

    -- Re-scan spellbook when spells change (talent respec, level up)
    self.frame:RegisterEvent("SPELLS_CHANGED")
    self.frame:RegisterEvent("PLAYER_ENTERING_WORLD")

    local this = self
    self.frame:SetScript("OnEvent", function()
        if event == "SPELLS_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
            this:ScanSpellbook()
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

    -- Initial scan
    self:ScanSpellbook()
end

------------------------------------------------------------
-- Scan spellbook: find all learned spells that we know
-- durations for, pick the first 9.
------------------------------------------------------------
function Timers:ScanSpellbook()
    local found = {}  -- { name, texture, duration }
    local seen = {}   -- avoid duplicates (different ranks)

    local bookType = "spell"
    local i = 1
    while true do
        local name, rank = GetSpellName(i, bookType)
        if not name then break end

        -- If this spell has a known duration and we haven't seen it yet
        if SPELL_DURATIONS[name] and not seen[name] then
            seen[name] = true
            local texture = GetSpellTexture(i, bookType)
            table.insert(found, {
                name     = name,
                texture  = texture,
                duration = SPELL_DURATIONS[name],
            })
        end

        i = i + 1
    end

    -- Cap at MAX_TRACKED (9)
    self.trackedSpells = {}
    for j = 1, MAX_TRACKED do
        if found[j] then
            self.trackedSpells[j] = found[j]
        end
    end

    -- Init state for each tracked spell
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
-- Setup timer row visuals (icons, names, initial "Ready")
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

            -- Start in READY state
            row.bar:SetValue(1)
            row.bar:SetStatusBarColor(0.2, 0.8, 0.3, 0.8)
            row.timeText:SetText("Ready")
            row.timeText:SetTextColor(0.3, 1.0, 0.3, 1)
            row.icon:SetAlpha(1.0)
            row.frame:Show()
        else
            row.frame:Hide()
        end
    end

    -- Resize panel to fit actual tracked spell count
    local count = 0
    for _ in ipairs(self.trackedSpells) do count = count + 1 end
    local panelH = 22 + count * 20 + 6
    ArcaneWatch.UI.timersPanel:SetHeight(panelH)
end

------------------------------------------------------------
-- Event: detect spell casts
------------------------------------------------------------
function Timers:OnEvent(evt, a1, a2, a3)
    if not ArcaneWatch.Config:Get("timersEnabled") then return end

    -- Turtle WoW: UNIT_SPELLCAST_SUCCEEDED / UNIT_SPELLCAST_SENT
    if evt == "UNIT_SPELLCAST_SUCCEEDED" or evt == "UNIT_SPELLCAST_SENT" then
        if a1 == "player" and a2 then
            self:OnSpellCast(a2)
        end
        return
    end

    -- Vanilla combat log
    if a1 then
        self:ParseCombatMessage(a1)
    end
end

------------------------------------------------------------
-- Parse vanilla combat log for self-casts
------------------------------------------------------------
function Timers:ParseCombatMessage(msg)
    if not self.trackedSpells then return end

    -- Only process our own casts
    if not (string.find(msg, "^Your ") or string.find(msg, "^You ")) then
        return
    end

    for i, spell in ipairs(self.trackedSpells) do
        if string.find(msg, spell.name, 1, true) then
            self:OnSpellCast(spell.name)
            return
        end
    end
end

------------------------------------------------------------
-- Handle a spell cast: transition from READY -> ACTIVE
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
-- OnUpdate: render all timer rows based on state
------------------------------------------------------------
function Timers:OnUpdate()
    if not ArcaneWatch.Config:Get("timersEnabled") then return end
    if not self.trackedSpells then return end

    local now = GetTime()
    local rows = ArcaneWatch.UI.timerRows

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
                -- Timer expired -> back to READY
                ss.state = STATE_READY
                row.bar:SetValue(1)
                row.bar:SetStatusBarColor(0.2, 0.8, 0.3, 0.8)
                row.timeText:SetText("Ready")
                row.timeText:SetTextColor(0.3, 1.0, 0.3, 1)
                row.icon:SetAlpha(1.0)
            else
                -- Active countdown
                local pct = remaining / ss.duration
                row.bar:SetValue(pct)
                row.timeText:SetText(ArcaneWatch.FormatTime(remaining))
                row.timeText:SetTextColor(1, 1, 1, 1)
                row.icon:SetAlpha(1.0)

                -- Color: blue (full) -> yellow (half) -> red (empty)
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
