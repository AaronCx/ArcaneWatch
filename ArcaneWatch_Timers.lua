------------------------------------------------------------
-- ArcaneWatch_Timers.lua
-- Spell cooldown / timer tracker. Detects casts via
-- combat log events, starts countdown timers, and updates
-- bars with color transitions (blue -> yellow -> red).
-- Pulses icons when a cooldown is ready.
------------------------------------------------------------

ArcaneWatch.Timers = {}

local Timers = ArcaneWatch.Timers

-- Known spell durations (seconds). These are default DoT/CD durations
-- for common Warlock spells. Users can customize the tracked list.
local SPELL_DURATIONS = {
    ["Corruption"]           = 18,
    ["Curse of Agony"]       = 24,
    ["Unstable Affliction"]  = 18,
    ["Siphon Life"]          = 30,
    ["Shadow Bolt"]          = 0,   -- no CD, track cast only
    ["Fear"]                 = 20,  -- duration of the CC
    ["Death Coil"]           = 120, -- 2 min cooldown
    ["Shadowburn"]           = 15,  -- cooldown
    ["Immolate"]             = 15,
    ["Conflagrate"]          = 10,
    ["Curse of the Elements"] = 300,
    ["Curse of Recklessness"] = 120,
    ["Curse of Tongues"]     = 30,
    ["Curse of Weakness"]    = 120,
    ["Drain Life"]           = 5,
    ["Drain Soul"]           = 15,
    ["Life Tap"]             = 0,
    ["Howl of Terror"]       = 40,
    ["Shadowfury"]           = 20,
    ["Soul Fire"]            = 0,
}

-- Active timers: { spellName = { startTime, duration, active } }
local activeTimers = {}

-- Pulse state for ready spells
local pulseTimers = {}

-- OnUpdate accumulator
local elapsed = 0
local UPDATE_INTERVAL = 0.05 -- smooth bar updates

------------------------------------------------------------
-- Init: register events for cast detection
------------------------------------------------------------
function Timers:Init()
    self.frame = CreateFrame("Frame", "ArcaneWatchTimerLogic", UIParent)

    -- Vanilla combat log events for self-cast detection
    self.frame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
    self.frame:RegisterEvent("CHAT_MSG_SPELL_SELF_BUFF")
    self.frame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE")
    self.frame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE")
    self.frame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE")

    -- Turtle WoW may support UNIT_SPELLCAST_SUCCEEDED
    if self.frame.RegisterEvent then
        -- Try registering; will silently fail if not available
        self.frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    end

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

    -- Initialize tracked spells from config
    self:RefreshTrackedList()
end

------------------------------------------------------------
-- Refresh the list of tracked spells from saved config
------------------------------------------------------------
function Timers:RefreshTrackedList()
    local tracked = ArcaneWatch.Config:Get("trackedSpells")
    if not tracked then return end

    -- Build icon cache for each tracked spell
    self.trackedSpells = {}
    for i, spellName in ipairs(tracked) do
        if i > 10 then break end -- max 10 slots

        -- Try to find the spell texture
        local texture = nil
        -- Search spellbook for the icon
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

        self.trackedSpells[i] = {
            name     = spellName,
            texture  = texture,
            duration = SPELL_DURATIONS[spellName] or 10,
        }
    end

    -- Setup initial UI for tracked spells
    self:SetupTimerRows()
end

------------------------------------------------------------
-- Setup timer row icons and names
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
            row.timeText:SetText("")
            row.bar:SetValue(0)
            row.bar:SetStatusBarColor(0.3, 0.5, 0.9, 0.9) -- default blue
            row.frame:Show()
        else
            row.frame:Hide()
        end
    end

    -- Resize the timers panel to fit actual tracked count
    local count = 0
    for _ in ipairs(self.trackedSpells) do count = count + 1 end
    local panelH = 22 + count * 22 + 6
    ArcaneWatch.UI.timersPanel:SetHeight(panelH)
end

------------------------------------------------------------
-- Event handler: detect spell casts from combat log
------------------------------------------------------------
function Timers:OnEvent(evt, a1, a2, a3)
    if not ArcaneWatch.Config:Get("timersEnabled") then return end

    -- UNIT_SPELLCAST_SUCCEEDED (Turtle WoW extended event)
    if evt == "UNIT_SPELLCAST_SUCCEEDED" then
        if a1 == "player" then
            self:TryStartTimer(a2)
        end
        return
    end

    -- Vanilla combat log parsing
    if evt == "CHAT_MSG_SPELL_SELF_DAMAGE" or
       evt == "CHAT_MSG_SPELL_SELF_BUFF" or
       evt == "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE" or
       evt == "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE" or
       evt == "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE" then
        if a1 then
            self:ParseCombatMessage(a1)
        end
    end
end

------------------------------------------------------------
-- Parse combat log message to detect spell names
------------------------------------------------------------
function Timers:ParseCombatMessage(msg)
    if not self.trackedSpells then return end

    for i, spell in ipairs(self.trackedSpells) do
        -- Check if the combat message contains our tracked spell name
        -- Patterns: "Your Corruption hits ...", "You cast Corruption", etc.
        if string.find(msg, spell.name) then
            -- Only start if "Your" or "You" is in the message (self-cast)
            if string.find(msg, "^Your ") or string.find(msg, "^You ") then
                self:TryStartTimer(spell.name)
                return -- first match wins
            end
        end
    end
end

------------------------------------------------------------
-- Start a timer for a spell
------------------------------------------------------------
function Timers:TryStartTimer(spellName)
    if not self.trackedSpells then return end

    for i, spell in ipairs(self.trackedSpells) do
        if spell.name == spellName then
            local dur = spell.duration
            if dur and dur > 0 then
                activeTimers[spellName] = {
                    startTime = GetTime(),
                    duration  = dur,
                    active    = true,
                }
                pulseTimers[spellName] = nil -- stop pulsing if re-cast
            end
            return
        end
    end
end

------------------------------------------------------------
-- OnUpdate: update timer bars, colors, and pulse effects
------------------------------------------------------------
function Timers:OnUpdate()
    if not ArcaneWatch.Config:Get("timersEnabled") then return end
    if not self.trackedSpells then return end

    local now = GetTime()
    local rows = ArcaneWatch.UI.timerRows

    for i, spell in ipairs(self.trackedSpells) do
        local row = rows[i]
        if not row then break end

        local timer = activeTimers[spell.name]
        if timer and timer.active then
            local remaining = timer.duration - (now - timer.startTime)

            if remaining <= 0 then
                -- Timer expired: mark ready, start pulse
                timer.active = false
                row.bar:SetValue(0)
                row.timeText:SetText("Ready")
                row.timeText:SetTextColor(0.3, 1.0, 0.3, 1)
                row.bar:SetStatusBarColor(0.2, 0.8, 0.2, 0.7)
                pulseTimers[spell.name] = now
            else
                -- Timer active: update bar and text
                local pct = remaining / timer.duration
                row.bar:SetValue(pct)
                row.timeText:SetText(ArcaneWatch.FormatTime(remaining))
                row.timeText:SetTextColor(1, 1, 1, 1)

                -- Color transition: blue(1.0) -> yellow(0.5) -> red(0.0)
                local r, g, b
                if pct > 0.5 then
                    -- Blue to Yellow: pct 1.0->0.5
                    local t = (pct - 0.5) / 0.5
                    r = 1.0 - t * 0.7     -- 0.3 -> 1.0
                    g = 0.5 + t * 0.0     -- 0.5 -> 0.5  ... actually:
                    -- blue (0.3, 0.5, 0.9) -> yellow (0.9, 0.8, 0.2)
                    r = 0.9 - t * 0.6     -- 0.9 at 0.5, 0.3 at 1.0
                    g = 0.8 - t * 0.3     -- 0.8 at 0.5, 0.5 at 1.0
                    b = 0.2 + t * 0.7     -- 0.2 at 0.5, 0.9 at 1.0
                else
                    -- Yellow to Red: pct 0.5->0.0
                    local t = pct / 0.5
                    -- yellow (0.9, 0.8, 0.2) -> red (0.9, 0.2, 0.1)
                    r = 0.9
                    g = 0.2 + t * 0.6     -- 0.2 at 0.0, 0.8 at 0.5
                    b = 0.1 + t * 0.1     -- 0.1 at 0.0, 0.2 at 0.5
                end
                row.bar:SetStatusBarColor(r, g, b, 0.9)
            end
        elseif pulseTimers[spell.name] then
            -- Pulse the icon when ready
            local pulseAge = now - pulseTimers[spell.name]
            local alpha = 0.5 + 0.5 * math.abs(math.sin(pulseAge * 3))
            row.icon:SetAlpha(alpha)
        else
            -- Idle state: no active timer
            row.bar:SetValue(0)
            row.timeText:SetText("")
            row.bar:SetStatusBarColor(0.3, 0.5, 0.9, 0.3)
            row.icon:SetAlpha(1.0)
        end
    end
end
