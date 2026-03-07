------------------------------------------------------------
-- ArcaneWatch_UI.lua
-- Creates all visual frames: threat panel, timers panel,
-- and config panel. Handles dragging, positioning, and
-- visibility toggling. All frames live here.
------------------------------------------------------------

ArcaneWatch.UI = {}

local UI = ArcaneWatch.UI
local PANEL_WIDTH_THREAT  = 160
local PANEL_WIDTH_TIMERS  = 190
local THREAT_ROW_HEIGHT   = 16
local TIMER_ROW_HEIGHT    = 20
local HEADER_HEIGHT       = 22
local MAX_THREAT_ROWS     = 5
local MAX_TIMER_ROWS      = 10
local PANEL_PAD           = 6

------------------------------------------------------------
-- Helper: create a styled panel frame
------------------------------------------------------------
local function CreatePanel(name, width, height, parent)
    local f = CreateFrame("Frame", name, parent or UIParent)
    f:SetWidth(width)
    f:SetHeight(height)
    f:SetBackdrop(ArcaneWatch.panelBackdrop)
    local c = ArcaneWatch.colors
    f:SetBackdropColor(c.bg[1], c.bg[2], c.bg[3], c.bg[4])
    f:SetBackdropBorderColor(c.border[1], c.border[2], c.border[3], c.border[4])
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("MEDIUM")
    return f
end

------------------------------------------------------------
-- Helper: make a panel draggable, saving position on stop
------------------------------------------------------------
local function MakeDraggable(frame, posKey)
    frame:SetScript("OnMouseDown", function()
        if not ArcaneWatch.Config:Get("locked") then
            frame:StartMoving()
        end
    end)
    frame:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        -- Save position relative to CENTER of UIParent
        local cx, cy = frame:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if cx and ux then
            local db = ArcaneWatch.Config.db
            db[posKey] = { x = cx - ux, y = cy - uy }
        end
    end)
end

------------------------------------------------------------
-- Helper: add a header label to a panel
------------------------------------------------------------
local function AddHeader(parent, text)
    local h = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h:SetPoint("TOP", parent, "TOP", 0, -5)
    h:SetTextColor(ArcaneWatch.colors.header[1], ArcaneWatch.colors.header[2],
                   ArcaneWatch.colors.header[3], ArcaneWatch.colors.header[4])
    h:SetText(text)
    return h
end

------------------------------------------------------------
-- Create threat row (name + bar + percent)
------------------------------------------------------------
local function CreateThreatRow(parent, index)
    local yOff = -(HEADER_HEIGHT + (index - 1) * THREAT_ROW_HEIGHT) - 2

    local row = CreateFrame("Frame", nil, parent)
    row:SetWidth(PANEL_WIDTH_THREAT - PANEL_PAD * 2)
    row:SetHeight(THREAT_ROW_HEIGHT - 2)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", PANEL_PAD, yOff)

    -- Background bar
    local barBg = row:CreateTexture(nil, "BACKGROUND")
    barBg:SetTexture(ArcaneWatch.barTexture)
    barBg:SetAllPoints(row)
    barBg:SetVertexColor(ArcaneWatch.colors.barBg[1], ArcaneWatch.colors.barBg[2],
                         ArcaneWatch.colors.barBg[3], ArcaneWatch.colors.barBg[4])

    -- Foreground threat bar
    local bar = CreateFrame("StatusBar", nil, row)
    bar:SetAllPoints(row)
    bar:SetStatusBarTexture(ArcaneWatch.barTexture)
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(0)
    bar:SetStatusBarColor(0.4, 0.6, 0.8, 0.9)

    -- Player highlight overlay
    local glow = row:CreateTexture(nil, "OVERLAY")
    glow:SetTexture("Interface\\Buttons\\UI-ListBox-Highlight")
    glow:SetAllPoints(row)
    glow:SetVertexColor(ArcaneWatch.colors.highlight[1], ArcaneWatch.colors.highlight[2],
                        ArcaneWatch.colors.highlight[3], ArcaneWatch.colors.highlight[4])
    glow:Hide()

    -- Name label
    local nameText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("LEFT", bar, "LEFT", 3, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetTextColor(0.9, 0.9, 0.9, 1)

    -- Percent label
    local pctText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pctText:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
    pctText:SetJustifyH("RIGHT")
    pctText:SetTextColor(0.9, 0.9, 0.9, 1)

    return {
        frame    = row,
        bar      = bar,
        barBg    = barBg,
        glow     = glow,
        nameText = nameText,
        pctText  = pctText,
    }
end

------------------------------------------------------------
-- Create timer row (icon + name + bar + time text)
------------------------------------------------------------
local function CreateTimerRow(parent, index)
    local yOff = -(HEADER_HEIGHT + (index - 1) * TIMER_ROW_HEIGHT) - 2

    local row = CreateFrame("Frame", nil, parent)
    row:SetWidth(PANEL_WIDTH_TIMERS - PANEL_PAD * 2)
    row:SetHeight(TIMER_ROW_HEIGHT - 2)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", PANEL_PAD, yOff)

    -- Spell icon
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(TIMER_ROW_HEIGHT - 4)
    icon:SetHeight(TIMER_ROW_HEIGHT - 4)
    icon:SetPoint("LEFT", row, "LEFT", 1, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trim icon borders

    -- Background bar area (right of icon)
    local barBg = row:CreateTexture(nil, "BACKGROUND")
    barBg:SetTexture(ArcaneWatch.barTexture)
    barBg:SetPoint("LEFT", icon, "RIGHT", 3, 0)
    barBg:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    barBg:SetHeight(TIMER_ROW_HEIGHT - 4)
    barBg:SetVertexColor(ArcaneWatch.colors.barBg[1], ArcaneWatch.colors.barBg[2],
                         ArcaneWatch.colors.barBg[3], ArcaneWatch.colors.barBg[4])

    -- Cooldown bar
    local bar = CreateFrame("StatusBar", nil, row)
    bar:SetPoint("LEFT", icon, "RIGHT", 3, 0)
    bar:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    bar:SetHeight(TIMER_ROW_HEIGHT - 4)
    bar:SetStatusBarTexture(ArcaneWatch.barTexture)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    bar:SetStatusBarColor(0.3, 0.5, 0.9, 0.9)

    -- Spell name
    local nameText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("LEFT", bar, "LEFT", 3, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetTextColor(0.9, 0.9, 0.9, 1)

    -- Time remaining
    local timeText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timeText:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
    timeText:SetJustifyH("RIGHT")
    timeText:SetTextColor(1, 1, 1, 1)

    return {
        frame    = row,
        icon     = icon,
        bar      = bar,
        barBg    = barBg,
        nameText = nameText,
        timeText = timeText,
        pulse    = 0,   -- pulse animation state
    }
end

------------------------------------------------------------
-- Init: build all UI frames
------------------------------------------------------------
function UI:Init()
    -- Threat panel
    local threatH = HEADER_HEIGHT + MAX_THREAT_ROWS * THREAT_ROW_HEIGHT + PANEL_PAD
    self.threatPanel = CreatePanel("ArcaneWatchThreatPanel", PANEL_WIDTH_THREAT, threatH)
    self.threatHeader = AddHeader(self.threatPanel, "Threat")
    MakeDraggable(self.threatPanel, "threatPos")

    self.threatRows = {}
    for i = 1, MAX_THREAT_ROWS do
        self.threatRows[i] = CreateThreatRow(self.threatPanel, i)
        self.threatRows[i].frame:Hide()
    end

    -- Timers panel
    local timersH = HEADER_HEIGHT + MAX_TIMER_ROWS * TIMER_ROW_HEIGHT + PANEL_PAD
    self.timersPanel = CreatePanel("ArcaneWatchTimersPanel", PANEL_WIDTH_TIMERS, timersH)
    self.timersHeader = AddHeader(self.timersPanel, "Spell Timers")
    MakeDraggable(self.timersPanel, "timersPos")

    self.timerRows = {}
    for i = 1, MAX_TIMER_ROWS do
        self.timerRows[i] = CreateTimerRow(self.timersPanel, i)
        self.timerRows[i].frame:Hide()
    end

    -- Config panel
    self:CreateConfigPanel()

    -- Apply saved state
    self:ApplyPositions()
    self:UpdateVisibility()
    self:UpdateLock()
end

------------------------------------------------------------
-- Config panel with toggle buttons
------------------------------------------------------------
function UI:CreateConfigPanel()
    local panelH = 160
    local panelW = 200
    self.configPanel = CreatePanel("ArcaneWatchConfigPanel", panelW, panelH)
    self.configPanel:SetFrameStrata("DIALOG")
    self.configPanel:Hide()
    AddHeader(self.configPanel, "ArcaneWatch Config")
    MakeDraggable(self.configPanel, "configPos")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, self.configPanel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", self.configPanel, "TOPRIGHT", -1, -1)
    closeBtn:SetWidth(20)
    closeBtn:SetHeight(20)
    closeBtn:SetScript("OnClick", function()
        self.configPanel:Hide()
    end)

    local function CreateToggleButton(parent, yOff, label, onClick)
        local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        btn:SetWidth(panelW - 20)
        btn:SetHeight(20)
        btn:SetPoint("TOP", parent, "TOP", 0, yOff)
        btn:SetText(label)
        btn:SetScript("OnClick", onClick)
        local txt = btn:GetFontString()
        if txt then txt:SetFont(txt:GetFont(), 10) end
        return btn
    end

    self.cfgBtnThreat = CreateToggleButton(self.configPanel, -30, "Toggle Threat Meter", function()
        ArcaneWatch.Config:ToggleThreat()
        self:UpdateConfigLabels()
    end)

    self.cfgBtnTimers = CreateToggleButton(self.configPanel, -55, "Toggle Spell Timers", function()
        ArcaneWatch.Config:ToggleTimers()
        self:UpdateConfigLabels()
    end)

    self.cfgBtnLock = CreateToggleButton(self.configPanel, -80, "Lock / Unlock Panels", function()
        ArcaneWatch.Config:ToggleLock()
        self:UpdateConfigLabels()
    end)

    self.cfgBtnReset = CreateToggleButton(self.configPanel, -105, "Reset Positions", function()
        ArcaneWatch.Config:ResetPositions()
    end)

    -- Status text
    self.cfgStatus = self.configPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.cfgStatus:SetPoint("BOTTOM", self.configPanel, "BOTTOM", 0, 8)
    self.cfgStatus:SetTextColor(0.6, 0.6, 0.6, 1)
end

function UI:UpdateConfigLabels()
    local db = ArcaneWatch.Config.db
    local parts = {}
    table.insert(parts, "Threat: " .. (db.threatEnabled and "ON" or "OFF"))
    table.insert(parts, "Timers: " .. (db.timersEnabled and "ON" or "OFF"))
    table.insert(parts, "Lock: " .. (db.locked and "ON" or "OFF"))
    if self.cfgStatus then
        self.cfgStatus:SetText(table.concat(parts, "  |  "))
    end
end

function UI:ToggleConfigPanel()
    if self.configPanel:IsVisible() then
        self.configPanel:Hide()
    else
        self:UpdateConfigLabels()
        self.configPanel:Show()
    end
end

------------------------------------------------------------
-- Position management
------------------------------------------------------------
function UI:ApplyPositions()
    local db = ArcaneWatch.Config.db
    self.threatPanel:ClearAllPoints()
    self.threatPanel:SetPoint("CENTER", UIParent, "CENTER", db.threatPos.x, db.threatPos.y)
    self.timersPanel:ClearAllPoints()
    self.timersPanel:SetPoint("CENTER", UIParent, "CENTER", db.timersPos.x, db.timersPos.y)
    self.configPanel:ClearAllPoints()
    self.configPanel:SetPoint("CENTER", UIParent, "CENTER", db.configPos.x, db.configPos.y)
end

------------------------------------------------------------
-- Visibility
------------------------------------------------------------
function UI:UpdateVisibility()
    local db = ArcaneWatch.Config.db
    if db.threatEnabled then
        -- Threat panel may be managed by auto-show logic; just ensure it's not force-hidden
        if not db.autoHideThreat then
            self.threatPanel:Show()
        end
    else
        self.threatPanel:Hide()
    end
    if db.timersEnabled then
        self.timersPanel:Show()
    else
        self.timersPanel:Hide()
    end
end

------------------------------------------------------------
-- Lock state
------------------------------------------------------------
function UI:UpdateLock()
    local locked = ArcaneWatch.Config:Get("locked")
    self.threatPanel:EnableMouse(not locked or true) -- always receive mouse for tooltip, etc
    self.timersPanel:EnableMouse(not locked or true)
    -- Drag is gated inside OnMouseDown handler via Config check
end
