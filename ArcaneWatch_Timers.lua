------------------------------------------------------------
-- ArcaneWatch_Timers.lua  (v1.1)
-- Spell cooldown / timer tracker.
--
-- State flow per spell:
--   READY  (green bar, "Ready" text, icon pulses)
--     -> cast detected ->
--   ACTIVE (bar drains, countdown text, blue->yellow->red)
--     -> timer expires ->
--   READY  (back to green, "Ready", pulse)
--
-- Detects casts via combat log events and
-- UNIT_SPELLCAST_SUCCEEDED (Turtle WoW).
------------------------------------------------------------

ArcaneWatch.Timers = {}

local Timers = ArcaneWatch.Timers

-- Known spell durations (seconds) — DoT durations / cooldowns
local SPELL_DURATIONS = {
    ["Corruption"]           = 18,
    ["Curse of Agony"]       = 24,
    ["Unstable Affliction"]  = 18,
    ["Siphon Life"]          = 30,
    ["Shadow Bolt"]          = 3,    -- cast time as pseudo-timer
    ["Fear"]                 = 20,
    ["Death Coil"]           = 120,
    ["Shadowburn"]           = 15,
    ["Immolate"]             = 15,
    ["Conflagrate"]          = 10,
    ["Curse of the Elements"] = 300,
    ["Curse of Recklessness"] = 120,
    ["Curse of Tongues"]     = 30,
    ["Curse of Weakness"]    = 120,
    ["Drain Life"]           = 5,
    ["Drain Soul"]           = 15,
    ["Life Tap"]             = 3,
    ["Howl of Terror"]       = 40,
    ["Shadowfury"]           = 20,
    ["Soul Fire"]            = 6,
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

    -- Turtle WoW extended event
    self.frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    self.frame:RegisterEvent("UNIT_SPELLCAST_SENT")

    local this = self
    self.frame:SetScript("OnEvent", function()
        this:OnEvent(event, arg1, arg2, arg3)
    end)

    self.frame:SetScript("OnUpdate", function()
        elapsed = elapsed + arg1
        if elapsed < UPDATE_INTERVAL then return end
        elapsed = 0
        this:OnUpdate()
    end)

    self:RefreshTrackedList()
end

------------------------------------------------------------
-- Refresh tracked spell list from config
------------------------------------------------------------
function Timers:RefreshTrackedList()
    local tracked = ArcaneWatch.Config:Get("trackedSpells")
    if not tracked then return end

    self.trackedSpells = {}
    for i, spellName in ipairs(tracked) do
        if i > 10 then break end

        -- Search spellbook for the icon texture
        local texture = nil
        local bookType = "spell"
        local j = 1
        while true do
            local name, rank = GetSpellName(j, bookType)
            if not name then break end
            if name == spellName then
                texture = GetSpellTexture(j, bookType)
                break
            end
            j = j + 1
        end

        local dur = SPELL_DURATIONS[spellName] or 10

        self.trackedSpells[i] = {
            name     = spellName,
            texture  = texture,
            duration = dur,
        }

        -- Initialize all spells to READY state
        if not spellStates[spellName] then
            spellStates[spellName] = {
                state     = STATE_READY,
                startTime = 0,
                duration  = dur,
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

    for i = 1, 10 do
        local row = rows[i]
        local spell = self.trackedSpells[i]
        if spell then
            if spell.texture then
                row.icon:SetTexture(spell.texture)
            else
                row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            end
            row.nameText:SetText(spell.name)

            -- Start in READY state: full green bar, "Ready" text
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

    -- Resize panel to fit tracked spell count
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
            -- Safety: init to ready
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
                -- Active countdown: bar drains from full to empty
                local pct = remaining / ss.duration
                row.bar:SetValue(pct)
                row.timeText:SetText(ArcaneWatch.FormatTime(remaining))
                row.timeText:SetTextColor(1, 1, 1, 1)
                row.icon:SetAlpha(1.0)

                -- Color: blue (full) -> yellow (half) -> red (empty)
                local r, g, b
                if pct > 0.5 then
                    local t = (pct - 0.5) / 0.5  -- 1 at full, 0 at half
                    -- blue (0.3, 0.5, 0.9) -> yellow (0.9, 0.8, 0.2)
                    r = 0.9 - t * 0.6
                    g = 0.8 - t * 0.3
                    b = 0.2 + t * 0.7
                else
                    local t = pct / 0.5  -- 1 at half, 0 at empty
                    -- yellow (0.9, 0.8, 0.2) -> red (0.9, 0.2, 0.1)
                    r = 0.9
                    g = 0.2 + t * 0.6
                    b = 0.1 + t * 0.1
                end
                row.bar:SetStatusBarColor(r, g, b, 0.9)
            end

        else
            -- STATE_READY: green bar, "Ready" text, gentle pulse
            row.bar:SetValue(1)
            row.bar:SetStatusBarColor(0.2, 0.8, 0.3, 0.8)
            row.timeText:SetText("Ready")
            row.timeText:SetTextColor(0.3, 1.0, 0.3, 1)

            -- Subtle pulse on the icon to indicate ready
            local pulse = 0.85 + 0.15 * math.sin(now * 2.5)
            row.icon:SetAlpha(pulse)
        end
    end
end
