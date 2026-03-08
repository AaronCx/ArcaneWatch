------------------------------------------------------------
-- ArcaneWatch_UI.lua  (v1.10.0)
-- Creates all visual frames: threat panel, timers panel,
-- config panel, minimap button. Handles dragging, positioning,
-- visibility, tooltips, and dynamic panel resizing.
------------------------------------------------------------

ArcaneWatch.UI = {}

local UI = ArcaneWatch.UI
local PANEL_WIDTH_THREAT  = 160
local PANEL_WIDTH_TIMERS  = 190
local THREAT_ROW_HEIGHT   = 16
local TIMER_ROW_HEIGHT    = 20
local HEADER_HEIGHT       = 22
local MAX_THREAT_ROWS     = 5
local MAX_TIMER_ROWS      = 9
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
        local cx, cy = frame:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if cx and ux then
            local charDb = ArcaneWatch.Config.charDb
            if charDb then
                charDb[posKey] = { x = cx - ux, y = cy - uy }
            end
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
    row:EnableMouse(true)

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

    -- Tooltip on hover
    row:SetScript("OnEnter", function()
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:AddLine(nameText:GetText() or "", 1, 1, 1)
        GameTooltip:AddLine("Threat: " .. (pctText:GetText() or "0%"), 0.8, 0.8, 0.8)
        if row.rawThreat then
            GameTooltip:AddLine("Raw: " .. string.format("%.0f", row.rawThreat), 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

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
    row:EnableMouse(true)

    -- Spell icon
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(TIMER_ROW_HEIGHT - 4)
    icon:SetHeight(TIMER_ROW_HEIGHT - 4)
    icon:SetPoint("LEFT", row, "LEFT", 1, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

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

    -- Tooltip on hover
    row:SetScript("OnEnter", function()
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        local spellName = nameText:GetText() or ""
        GameTooltip:AddLine(spellName, 1, 1, 1)
        local dur = row.spellDuration
        local typ = row.spellType
        if typ then
            GameTooltip:AddLine("Type: " .. typ, 0.7, 0.8, 0.9)
        end
        if dur then
            GameTooltip:AddLine("Duration: " .. ArcaneWatch.FormatTime(dur), 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return {
        frame         = row,
        icon          = icon,
        bar           = bar,
        barBg         = barBg,
        nameText      = nameText,
        timeText      = timeText,
        spellDuration = nil,
        spellType     = nil,
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

    -- Threat warning flash overlay
    self.threatWarning = self.threatPanel:CreateTexture(nil, "OVERLAY")
    self.threatWarning:SetTexture("Interface\\Buttons\\UI-ListBox-Highlight")
    self.threatWarning:SetAllPoints(self.threatPanel)
    self.threatWarning:SetVertexColor(1.0, 0.2, 0.1, 0)
    self.threatWarning:Hide()

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

    -- Minimap button
    self:CreateMinimapButton()

    -- Apply saved state
    self:ApplyPositions()
    self:UpdateVisibility()
    self:UpdateLock()
end

------------------------------------------------------------
-- Dynamic threat panel height (shrink to visible rows)
------------------------------------------------------------
function UI:SetThreatRowCount(count)
    if count < 1 then count = 1 end
    if count > MAX_THREAT_ROWS then count = MAX_THREAT_ROWS end
    local h = HEADER_HEIGHT + count * THREAT_ROW_HEIGHT + PANEL_PAD
    self.threatPanel:SetHeight(h)
end

------------------------------------------------------------
-- Threat warning flash
------------------------------------------------------------
function UI:FlashThreatWarning(active)
    if not self.threatWarning then return end
    if active then
        self.threatWarning:Show()
        -- Pulse alpha via OnUpdate (driven by Threat module)
    else
        self.threatWarning:Hide()
    end
end

function UI:SetThreatWarningAlpha(alpha)
    if self.threatWarning then
        self.threatWarning:SetVertexColor(1.0, 0.2, 0.1, alpha)
    end
end

------------------------------------------------------------
-- Config panel with toggle buttons, opacity slider,
-- auto-hide toggle, and sound toggles
------------------------------------------------------------
function UI:CreateConfigPanel()
    local panelW = 210
    local panelH = 260
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

    local yPos = -28
    local function NextY(h)
        local y = yPos
        yPos = yPos - (h or 22)
        return y
    end

    -- Toggle buttons
    local function CreateToggleButton(label, onClick)
        local btn = CreateFrame("Button", nil, self.configPanel, "UIPanelButtonTemplate")
        btn:SetWidth(panelW - 20)
        btn:SetHeight(18)
        btn:SetPoint("TOP", self.configPanel, "TOP", 0, NextY(20))
        btn:SetText(label)
        btn:SetScript("OnClick", onClick)
        local txt = btn:GetFontString()
        if txt then
            local font, _, flags = txt:GetFont()
            if font then txt:SetFont(font, 9, flags) end
        end
        return btn
    end

    self.cfgBtnThreat = CreateToggleButton("Toggle Threat Meter", function()
        ArcaneWatch.Config:ToggleThreat()
        self:UpdateConfigLabels()
    end)

    self.cfgBtnTimers = CreateToggleButton("Toggle Spell Timers", function()
        ArcaneWatch.Config:ToggleTimers()
        self:UpdateConfigLabels()
    end)

    self.cfgBtnLock = CreateToggleButton("Lock / Unlock Panels", function()
        ArcaneWatch.Config:ToggleLock()
        self:UpdateConfigLabels()
    end)

    self.cfgBtnReset = CreateToggleButton("Reset Positions", function()
        ArcaneWatch.Config:ResetPositions()
    end)

    -- Auto-hide threat checkbox
    NextY(6) -- spacing
    local autoHideCheck = CreateFrame("CheckButton", "ArcaneWatchAutoHideCheck", self.configPanel, "UICheckButtonTemplate")
    autoHideCheck:SetWidth(20)
    autoHideCheck:SetHeight(20)
    autoHideCheck:SetPoint("TOPLEFT", self.configPanel, "TOPLEFT", 12, NextY(22))
    autoHideCheck:SetChecked(ArcaneWatch.Config:Get("autoHideThreat"))
    autoHideCheck:SetScript("OnClick", function()
        local val = autoHideCheck:GetChecked() and true or false
        ArcaneWatch.Config.db.autoHideThreat = val
        self:UpdateConfigLabels()
    end)
    local autoHideLabel = self.configPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    autoHideLabel:SetPoint("LEFT", autoHideCheck, "RIGHT", 2, 0)
    autoHideLabel:SetText("Auto-hide threat out of combat")
    autoHideLabel:SetTextColor(0.85, 0.85, 0.85, 1)

    -- Sound toggles
    local warnSoundCheck = CreateFrame("CheckButton", "ArcaneWatchWarnSoundCheck", self.configPanel, "UICheckButtonTemplate")
    warnSoundCheck:SetWidth(20)
    warnSoundCheck:SetHeight(20)
    warnSoundCheck:SetPoint("TOPLEFT", self.configPanel, "TOPLEFT", 12, NextY(22))
    warnSoundCheck:SetChecked(ArcaneWatch.Config:Get("threatWarnSound"))
    warnSoundCheck:SetScript("OnClick", function()
        ArcaneWatch.Config.db.threatWarnSound = warnSoundCheck:GetChecked() and true or false
    end)
    local warnSoundLabel = self.configPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    warnSoundLabel:SetPoint("LEFT", warnSoundCheck, "RIGHT", 2, 0)
    warnSoundLabel:SetText("Threat warning sound")
    warnSoundLabel:SetTextColor(0.85, 0.85, 0.85, 1)

    local readySoundCheck = CreateFrame("CheckButton", "ArcaneWatchReadySoundCheck", self.configPanel, "UICheckButtonTemplate")
    readySoundCheck:SetWidth(20)
    readySoundCheck:SetHeight(20)
    readySoundCheck:SetPoint("TOPLEFT", self.configPanel, "TOPLEFT", 12, NextY(22))
    readySoundCheck:SetChecked(ArcaneWatch.Config:Get("timerReadySound"))
    readySoundCheck:SetScript("OnClick", function()
        ArcaneWatch.Config.db.timerReadySound = readySoundCheck:GetChecked() and true or false
    end)
    local readySoundLabel = self.configPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    readySoundLabel:SetPoint("LEFT", readySoundCheck, "RIGHT", 2, 0)
    readySoundLabel:SetText("Timer ready sound")
    readySoundLabel:SetTextColor(0.85, 0.85, 0.85, 1)

    -- Opacity slider
    NextY(4) -- spacing
    local opacityLabel = self.configPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    opacityLabel:SetPoint("TOPLEFT", self.configPanel, "TOPLEFT", 14, NextY(14))
    opacityLabel:SetText("Opacity")
    opacityLabel:SetTextColor(0.85, 0.85, 0.85, 1)

    self.opacityValue = self.configPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.opacityValue:SetPoint("TOPRIGHT", self.configPanel, "TOPRIGHT", -14, opacityLabel:GetTop() and 0 or 0)
    self.opacityValue:SetPoint("RIGHT", self.configPanel, "RIGHT", -14, 0)
    self.opacityValue:SetPoint("TOP", opacityLabel, "TOP", 0, 0)
    self.opacityValue:SetTextColor(0.7, 0.8, 0.95, 1)

    local slider = CreateFrame("Slider", "ArcaneWatchOpacitySlider", self.configPanel, "OptionsSliderTemplate")
    slider:SetWidth(panelW - 30)
    slider:SetHeight(14)
    slider:SetPoint("TOP", self.configPanel, "TOP", 0, NextY(20))
    slider:SetMinMaxValues(20, 100)
    slider:SetValueStep(5)
    slider:SetValue((ArcaneWatch.Config:Get("opacity") or 0.85) * 100)
    getglobal(slider:GetName() .. "Low"):SetText("20%")
    getglobal(slider:GetName() .. "High"):SetText("100%")
    getglobal(slider:GetName() .. "Text"):SetText("")
    slider:SetScript("OnValueChanged", function()
        local val = slider:GetValue() / 100
        ArcaneWatch.Config.db.opacity = val
        self:ApplyOpacity()
        if self.opacityValue then
            self.opacityValue:SetText(string.format("%.0f%%", val * 100))
        end
    end)
    self.opacitySlider = slider
    if self.opacityValue then
        self.opacityValue:SetText(string.format("%.0f%%", (ArcaneWatch.Config:Get("opacity") or 0.85) * 100))
    end

    -- Status text at bottom
    self.cfgStatus = self.configPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.cfgStatus:SetPoint("BOTTOM", self.configPanel, "BOTTOM", 0, 8)
    self.cfgStatus:SetTextColor(0.6, 0.6, 0.6, 1)
end

function UI:ApplyOpacity()
    local alpha = ArcaneWatch.Config:Get("opacity") or 0.85
    self.threatPanel:SetAlpha(alpha)
    self.timersPanel:SetAlpha(alpha)
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
-- Minimap button
------------------------------------------------------------
function UI:CreateMinimapButton()
    local btn = CreateFrame("Button", "ArcaneWatchMinimapBtn", Minimap)
    btn:SetWidth(28)
    btn:SetHeight(28)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local overlay = btn:CreateTexture(nil, "OVERLAY")
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetWidth(54)
    overlay:SetHeight(54)
    overlay:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)

    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\Spell_Arcane_Arcane04")
    icon:SetWidth(18)
    icon:SetHeight(18)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetPoint("CENTER", btn, "CENTER", 0, 1)

    -- Position around minimap at 225 degrees
    local angle = 225
    local rad = math.rad(angle)
    local xOff = 80 * math.cos(rad)
    local yOff = 80 * math.sin(rad)
    btn:SetPoint("CENTER", Minimap, "CENTER", xOff, yOff)

    btn:SetScript("OnClick", function()
        if arg1 == "LeftButton" then
            self:ToggleConfigPanel()
        elseif arg1 == "RightButton" then
            -- Right-click: quick toggle both panels
            ArcaneWatch.Config:ToggleThreat()
            ArcaneWatch.Config:ToggleTimers()
        end
    end)
    btn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cff5a8abfArcaneWatch|r v" .. ArcaneWatch.version)
        GameTooltip:AddLine("Left-click: Config", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click: Toggle panels", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    self.minimapBtn = btn
end

------------------------------------------------------------
-- Position management (uses per-character DB)
------------------------------------------------------------
function UI:ApplyPositions()
    local charDb = ArcaneWatch.Config.charDb
    if not charDb then return end
    self.threatPanel:ClearAllPoints()
    self.threatPanel:SetPoint("CENTER", UIParent, "CENTER", charDb.threatPos.x, charDb.threatPos.y)
    self.timersPanel:ClearAllPoints()
    self.timersPanel:SetPoint("CENTER", UIParent, "CENTER", charDb.timersPos.x, charDb.timersPos.y)
    self.configPanel:ClearAllPoints()
    self.configPanel:SetPoint("CENTER", UIParent, "CENTER", charDb.configPos.x, charDb.configPos.y)
    self:ApplyOpacity()
end

------------------------------------------------------------
-- Visibility
------------------------------------------------------------
function UI:UpdateVisibility()
    local db = ArcaneWatch.Config.db
    if db.threatEnabled then
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
    -- Drag is gated inside OnMouseDown handler via Config check
end
