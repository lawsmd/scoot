-- damagemetersY/frames.lua - Window frame creation, header/bar/button construction, context menus
local _, addon = ...
local DMY = addon.DamageMetersY

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local activeDMYMenu = nil -- tracks any open DMY flyout (gear, segment, column)

local HEADER_HEIGHT = 24
local ICON_SIZE = 22
local NAME_WIDTH = 113
local PINNED_SEPARATOR_HEIGHT = 1

local function GetDefaultFont()
    if addon.ResolveFontFace then
        return addon.ResolveFontFace("ROBOTO_SEMICOND_BOLD")
    end
    return "Fonts\\FRIZQT__.TTF"
end

--------------------------------------------------------------------------------
-- Shared Flyout Menu Factory
--
-- Creates a reusable flyout menu with the same visual treatment as the gear
-- menu. Supports Clear/AddRow/AddDivider/ShowAtAnchor for dynamic population.
--------------------------------------------------------------------------------

function DMY._CreateFlyoutMenu(menuWidth)
    menuWidth = menuWidth or 160

    -- Backdrop click-catcher
    local backdrop = CreateFrame("Button", nil, UIParent)
    backdrop:SetAllPoints(UIParent)
    backdrop:SetFrameStrata("FULLSCREEN_DIALOG")
    backdrop:SetFrameLevel(199)
    backdrop:RegisterForClicks("AnyUp")
    backdrop:Hide()

    -- Menu frame
    local menu = CreateFrame("Frame", nil, UIParent)
    menu:SetSize(menuWidth, 10)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(200)
    menu:EnableMouse(true)
    menu:SetClampedToScreen(true)
    menu:Hide()

    backdrop:SetScript("OnClick", function() menu:Hide() end)
    menu:SetScript("OnHide", function()
        backdrop:Hide()
        if activeDMYMenu == menu then activeDMYMenu = nil end
    end)
    menu:SetScript("OnShow", function() backdrop:Show() end)

    -- Background
    local menuBg = menu:CreateTexture(nil, "BACKGROUND", nil, -8)
    menuBg:SetAllPoints()
    menuBg:SetColorTexture(0.06, 0.06, 0.08, 0.95)

    -- Border edges
    local menuBorder = { 0.3, 0.3, 0.35, 0.8 }
    for _, info in ipairs({
        { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
        { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false },
    }) do
        local t = menu:CreateTexture(nil, "BORDER")
        t:SetPoint(info[1]); t:SetPoint(info[2])
        if info[3] then t:SetHeight(1) else t:SetWidth(1) end
        t:SetColorTexture(menuBorder[1], menuBorder[2], menuBorder[3], menuBorder[4])
    end

    -- Row pool and divider pool
    menu._rows = {}
    menu._dividers = {}
    menu._headerBars = {}
    menu._spellRows = {}
    menu._placeholderTexts = {}
    menu._rowCount = 0
    menu._dividerCount = 0
    menu._headerBarCount = 0
    menu._spellRowCount = 0
    menu._placeholderTextCount = 0
    menu._yOff = -6

    function menu:Clear()
        for i = 1, self._rowCount do
            self._rows[i]:Hide()
        end
        for i = 1, self._dividerCount do
            self._dividers[i]:Hide()
        end
        for i = 1, self._headerBarCount do
            self._headerBars[i]:Hide()
        end
        for i = 1, self._spellRowCount do
            self._spellRows[i]:Hide()
        end
        for i = 1, self._placeholderTextCount do
            self._placeholderTexts[i]:Hide()
        end
        self._rowCount = 0
        self._dividerCount = 0
        self._headerBarCount = 0
        self._spellRowCount = 0
        self._placeholderTextCount = 0
        self._yOff = -6
    end

    function menu:AddRow(label, textColor, onClick, isSelected)
        self._rowCount = self._rowCount + 1
        local idx = self._rowCount
        local btn = self._rows[idx]

        if not btn then
            btn = CreateFrame("Button", nil, self)
            btn:SetSize(menuWidth - 8, 24)
            local bg = btn:CreateTexture(nil, "BACKGROUND", nil, -6)
            bg:SetAllPoints()
            bg:SetColorTexture(1, 1, 1, 0)
            btn._bg = bg
            -- Left accent bar for selection indicator
            local accent = btn:CreateTexture(nil, "ARTWORK")
            accent:SetSize(2, 16)
            accent:SetPoint("LEFT", btn, "LEFT", 2, 0)
            accent:SetColorTexture(1.0, 0.82, 0, 1)
            btn._accent = accent
            local txt = btn:CreateFontString(nil, "OVERLAY")
            txt:SetFont(GetDefaultFont(), 10, "OUTLINE")
            txt:SetPoint("LEFT", 10, 0)
            txt:SetJustifyH("LEFT")
            btn._text = txt
            btn:SetScript("OnEnter", function() bg:SetColorTexture(1, 1, 1, 0.08) end)
            btn:SetScript("OnLeave", function() bg:SetColorTexture(1, 1, 1, 0) end)
            self._rows[idx] = btn
        end

        btn:ClearAllPoints()
        btn:SetPoint("TOP", self, "TOP", 0, self._yOff)
        btn._bg:SetColorTexture(1, 1, 1, 0)

        btn._text:SetText(label)
        if isSelected then
            btn._accent:Show()
            btn._text:SetTextColor(1.0, 0.82, 0, 1)
        else
            btn._accent:Hide()
            btn._text:SetTextColor(textColor[1], textColor[2], textColor[3], textColor[4] or 1)
        end

        btn:SetScript("OnClick", function()
            self:Hide()
            onClick()
        end)
        btn:Show()
        self._yOff = self._yOff - 24
    end

    function menu:AddDivider()
        self._dividerCount = self._dividerCount + 1
        local idx = self._dividerCount
        local div = self._dividers[idx]
        if not div then
            div = self:CreateTexture(nil, "ARTWORK")
            div:SetSize(menuWidth - 12, 1)
            self._dividers[idx] = div
        end
        div:ClearAllPoints()
        div:SetPoint("TOP", self, "TOP", 0, self._yOff - 3)
        div:SetColorTexture(0.3, 0.3, 0.35, 0.5)
        div:Show()
        self._yOff = self._yOff - 7
    end

    -- Header bar: title text (left) + close X button (right).
    function menu:AddHeaderBar(titleText, titleColor, onCloseClick)
        self._headerBarCount = self._headerBarCount + 1
        local idx = self._headerBarCount
        local bar = self._headerBars[idx]
        if not bar then
            bar = CreateFrame("Frame", nil, self)
            bar:SetSize(menuWidth - 8, 26)
            local bg = bar:CreateTexture(nil, "BACKGROUND", nil, -6)
            bg:SetAllPoints()
            bg:SetColorTexture(0.08, 0.08, 0.10, 0.95)
            bar._bg = bg

            local title = bar:CreateFontString(nil, "OVERLAY")
            title:SetFont(GetDefaultFont(), 12, "OUTLINE")
            title:SetPoint("LEFT", bar, "LEFT", 8, 0)
            title:SetPoint("RIGHT", bar, "RIGHT", -28, 0)
            title:SetJustifyH("LEFT")
            title:SetWordWrap(false)
            bar._title = title

            local closeBtn = CreateFrame("Button", nil, bar)
            closeBtn:SetSize(18, 18)
            closeBtn:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
            local closeTex = closeBtn:CreateFontString(nil, "OVERLAY")
            closeTex:SetFont(GetDefaultFont(), 14, "OUTLINE")
            closeTex:SetText("X")
            closeTex:SetPoint("CENTER")
            closeTex:SetTextColor(0.8, 0.3, 0.3, 1)
            closeBtn:SetScript("OnEnter", function() closeTex:SetTextColor(1, 0.5, 0.5, 1) end)
            closeBtn:SetScript("OnLeave", function() closeTex:SetTextColor(0.8, 0.3, 0.3, 1) end)
            bar._closeBtn = closeBtn

            self._headerBars[idx] = bar
        end

        bar:ClearAllPoints()
        bar:SetPoint("TOP", self, "TOP", 0, self._yOff)
        bar._title:SetText(titleText or "")
        if titleColor then
            bar._title:SetTextColor(titleColor[1] or 1, titleColor[2] or 1, titleColor[3] or 1, 1)
        else
            bar._title:SetTextColor(1, 1, 1, 1)
        end
        bar._closeBtn:SetScript("OnClick", onCloseClick or function() self:Hide() end)
        bar:Show()
        self._yOff = self._yOff - 26
    end

    -- Spell row: icon + name + bar fill (behind) + value text.
    function menu:AddSpellRow(spec)
        self._spellRowCount = self._spellRowCount + 1
        local idx = self._spellRowCount
        local row = self._spellRows[idx]
        if not row then
            row = CreateFrame("Frame", nil, self)
            row:SetSize(menuWidth - 8, 22)

            local barBg = row:CreateTexture(nil, "BACKGROUND", nil, -2)
            barBg:SetPoint("LEFT", row, "LEFT", 22, 0)
            barBg:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            barBg:SetPoint("TOP", row, "TOP", 0, -1)
            barBg:SetPoint("BOTTOM", row, "BOTTOM", 0, 1)
            barBg:SetColorTexture(0.1, 0.1, 0.1, 0.7)
            row._barBg = barBg

            local bar = CreateFrame("StatusBar", nil, row)
            bar:SetPoint("LEFT", row, "LEFT", 22, 0)
            bar:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            bar:SetPoint("TOP", row, "TOP", 0, -1)
            bar:SetPoint("BOTTOM", row, "BOTTOM", 0, 1)
            bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
            bar:SetMinMaxValues(0, 1)
            bar:SetValue(0)
            row._bar = bar

            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(18, 18)
            icon:SetPoint("LEFT", row, "LEFT", 2, 0)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row._icon = icon

            local nameFS = bar:CreateFontString(nil, "OVERLAY")
            nameFS:SetFont(GetDefaultFont(), 10, "OUTLINE")
            nameFS:SetPoint("LEFT", bar, "LEFT", 4, 0)
            nameFS:SetPoint("RIGHT", bar, "RIGHT", -72, 0)
            nameFS:SetJustifyH("LEFT")
            nameFS:SetWordWrap(false)
            row._nameFS = nameFS

            local valueFS = bar:CreateFontString(nil, "OVERLAY")
            valueFS:SetFont(GetDefaultFont(), 10, "OUTLINE")
            -- Two-point anchor bounds the value region (name reserves up to
            -- -72) so over-long values truncate instead of overlapping the name
            valueFS:SetPoint("LEFT", bar, "RIGHT", -70, 0)
            valueFS:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
            valueFS:SetJustifyH("RIGHT")
            valueFS:SetWordWrap(false)
            row._valueFS = valueFS

            self._spellRows[idx] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOP", self, "TOP", 0, self._yOff)

        -- Icon
        local tex
        if spec.spellID and C_Spell and C_Spell.GetSpellTexture then
            tex = C_Spell.GetSpellTexture(spec.spellID)
        end
        if tex then
            row._icon:SetTexture(tex)
        else
            row._icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end

        -- Name + color
        row._nameFS:SetText(spec.nameText or "")
        if spec.nameColor then
            row._nameFS:SetTextColor(spec.nameColor[1] or 1, spec.nameColor[2] or 1, spec.nameColor[3] or 1, 1)
        else
            row._nameFS:SetTextColor(1, 1, 1, 1)
        end

        -- Value
        row._valueFS:SetText(spec.valueText or "")
        row._valueFS:SetTextColor(1, 1, 1, 1)

        -- Bar fill + color
        local frac = tonumber(spec.fillFraction) or 0
        if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
        row._bar:SetMinMaxValues(0, 1)
        row._bar:SetValue(frac)
        if spec.barColor then
            row._bar:SetStatusBarColor(spec.barColor[1] or 0.6, spec.barColor[2] or 0.6, spec.barColor[3] or 0.6, 0.85)
        else
            row._bar:SetStatusBarColor(0.6, 0.6, 0.6, 0.85)
        end

        row:Show()
        self._yOff = self._yOff - 22
    end

    -- Placeholder text: single non-interactive informational row.
    function menu:AddPlaceholderText(text)
        self._placeholderTextCount = self._placeholderTextCount + 1
        local idx = self._placeholderTextCount
        local frm = self._placeholderTexts[idx]
        if not frm then
            frm = CreateFrame("Frame", nil, self)
            frm:SetSize(menuWidth - 8, 28)
            local fs = frm:CreateFontString(nil, "OVERLAY")
            fs:SetFont(GetDefaultFont(), 11, "OUTLINE")
            fs:SetPoint("CENTER")
            fs:SetJustifyH("CENTER")
            fs:SetWordWrap(true)
            fs:SetTextColor(0.75, 0.75, 0.78, 1)
            frm._fs = fs
            self._placeholderTexts[idx] = frm
        end
        frm:ClearAllPoints()
        frm:SetPoint("TOP", self, "TOP", 0, self._yOff)
        frm._fs:SetText(text or "")
        frm:Show()
        self._yOff = self._yOff - 28
    end

    function menu:ShowAtAnchor(anchor)
        -- Dismiss any other open menu
        if activeDMYMenu and activeDMYMenu ~= self and activeDMYMenu:IsShown() then
            activeDMYMenu:Hide()
        end

        -- Finalize height
        self:SetHeight(math.abs(self._yOff) + 6)

        -- Smart positioning: flip above when near screen bottom
        self:ClearAllPoints()
        local anchorBottom = select(2, anchor:GetCenter()) - (anchor:GetHeight() / 2)
        local scale = UIParent:GetEffectiveScale()
        local spaceBelow = anchorBottom * scale
        if spaceBelow > self:GetHeight() + 10 then
            self:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
        else
            self:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)
        end
        self:Show()
        activeDMYMenu = self
    end

    return menu
end

--------------------------------------------------------------------------------
-- Column Format Groups (for column right-click menu)
--------------------------------------------------------------------------------

local COLUMN_FORMAT_GROUPS = {
    { keys = { "damage", "dps", "dmg_dps", "dps_dmg" } },
    { keys = { "healing", "hps", "heal_hps", "hps_heal" } },
    { keys = { "absorbs", "interrupts", "dispels", "dmgTaken", "avoidable", "deaths", "enemyDmg" } },
}

--------------------------------------------------------------------------------
-- Bar Row Creation
--
-- Each bar row has: Icon, NameText, a single full-width StatusBar (representing
-- the primary column's data), and up to MAX_COLUMNS value text FontStrings
-- positioned at their column offsets on top of the bar.
--------------------------------------------------------------------------------

function DMY._CreateBarRow(scrollContent, rowIndex, windowIndex)
    local row = CreateFrame("Frame", nil, scrollContent)
    row:SetHeight(22)
    row._windowIndex = windowIndex
    row:EnableMouse(true)
    row:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then return end
        if DMY._OpenDrilldown then
            DMY._OpenDrilldown(self)
        end
    end)

    -- Icon
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.icon = icon

    -- Bar area starts at a fixed offset (icon + gap + name width + gap)
    local barAreaLeft = ICON_SIZE + 6 + NAME_WIDTH + 8

    -- Name clip region — rank sits to the left, name fills the rest
    -- Reserve 15px on the left for rank numbers
    local nameClipWidth = NAME_WIDTH - 15
    local nameClip = CreateFrame("Frame", nil, row)
    nameClip:SetPoint("LEFT", icon, "RIGHT", 19, 0)
    nameClip:SetPoint("TOP", row, "TOP")
    nameClip:SetPoint("BOTTOM", row, "BOTTOM")
    nameClip:SetWidth(nameClipWidth)
    nameClip:SetClipsChildren(true)
    nameClip:SetFrameLevel(row:GetFrameLevel() + 1)

    -- Inner frame holds the FontString (ClipsChildren clips child frames)
    local nameInner = CreateFrame("Frame", nil, nameClip)
    nameInner:SetAllPoints()

    local nameText = nameInner:CreateFontString(nil, "OVERLAY")
    nameText:SetFont(GetDefaultFont(), 12, "OUTLINE")
    nameText:SetPoint("LEFT", 0, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    nameText:SetTextColor(1, 1, 1, 1)
    row.nameText = nameText

    -- Bar background (full width, behind the StatusBar)
    local barBg = row:CreateTexture(nil, "BACKGROUND")
    barBg:SetPoint("LEFT", row, "LEFT", barAreaLeft, 0)
    barBg:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    barBg:SetPoint("TOP", row, "TOP", 0, 0)
    barBg:SetPoint("BOTTOM", row, "BOTTOM", 0, 0)
    barBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
    row.barBg = barBg

    -- Single full-width StatusBar (primary column data)
    local bar = CreateFrame("StatusBar", nil, row)
    bar:SetPoint("LEFT", row, "LEFT", barAreaLeft, 0)
    bar:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    bar:SetPoint("TOP", row, "TOP", 0, 0)
    bar:SetPoint("BOTTOM", row, "BOTTOM", 0, 0)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    row.bar = bar

    -- Rank number text (e.g., "1.", "2.") — positioned dynamically in layout
    -- Use a higher sublevel so it renders on top of the name clip area
    local rankText = row:CreateFontString(nil, "OVERLAY", nil, 7)
    rankText:SetFont(GetDefaultFont(), 11, "OUTLINE")
    rankText:SetJustifyH("LEFT")
    rankText:SetWordWrap(false)
    rankText:SetTextColor(0.6, 0.6, 0.6, 0.7)
    row.rankText = rankText

    -- Column value texts (up to MAX_COLUMNS, positioned at column offsets)
    row.valueTexts = {}
    for c = 1, DMY.MAX_COLUMNS do
        local vt = bar:CreateFontString(nil, "OVERLAY")
        vt:SetFont(GetDefaultFont(), 11, "OUTLINE")
        vt:SetJustifyH("RIGHT")
        vt:SetWordWrap(false)
        vt:SetTextColor(1, 1, 1, 1)
        vt:Hide()
        row.valueTexts[c] = vt
    end

    -- Per-column click overlays (multi-column drill-down dispatch).
    -- Children of row at level+1 so they intercept clicks before the row's
    -- OnMouseUp. Sized/positioned by _LayoutBarRows. Hidden when numColumns==1.
    row.colClickRegions = {}
    for c = 1, DMY.MAX_COLUMNS do
        local btn = CreateFrame("Button", nil, row)
        btn:SetFrameLevel(row:GetFrameLevel() + 1)
        btn:RegisterForClicks("LeftButtonUp")
        btn._columnIndex = c

        local hl = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0)
        btn._hl = hl

        btn:SetScript("OnEnter", function(self) self._hl:SetColorTexture(1, 1, 1, 0.05) end)
        btn:SetScript("OnLeave", function(self) self._hl:SetColorTexture(1, 1, 1, 0) end)
        btn:SetScript("OnClick", function(self)
            if DMY._OpenDrilldown then
                DMY._OpenDrilldown(row, self._columnIndex)
            end
        end)
        btn:Hide()
        row.colClickRegions[c] = btn
    end

    row._rowIndex = rowIndex
    row:Hide()
    return row
end

--------------------------------------------------------------------------------
-- Window Creation
--------------------------------------------------------------------------------

function DMY._CreateWindow(windowIndex, comp)
    local db = comp.db
    local fw = tonumber(db.frameWidth) or 350
    local fh = tonumber(db.frameHeight) or 250

    -- Main container
    local frame = CreateFrame("Frame", "ScootDMYWindow" .. windowIndex, UIParent)
    frame:SetSize(fw, fh)
    frame:SetPoint("CENTER", UIParent, "CENTER", -200 + (windowIndex - 1) * 100, 0)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:Hide()

    -- Background
    local background = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    background:SetAllPoints()
    background:SetColorTexture(0.06, 0.06, 0.08, 0.95)

    -- Header
    local header = CreateFrame("Frame", nil, frame)
    header:SetHeight(HEADER_HEIGHT)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)

    local headerBg = header:CreateTexture(nil, "BACKGROUND", nil, -6)
    headerBg:SetAllPoints()
    headerBg:SetColorTexture(0.08, 0.08, 0.10, 0.9)
    header._bg = headerBg

    -- Gear button (left side of header, opens flyout menu)
    local gearBtn = CreateFrame("Button", nil, header)
    gearBtn:SetSize(18, 18)
    gearBtn:SetPoint("LEFT", header, "LEFT", 4, 0)

    local gearIcon = gearBtn:CreateTexture(nil, "ARTWORK")
    gearIcon:SetAllPoints()
    gearIcon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    gearIcon:SetDesaturated(true)
    gearIcon:SetVertexColor(0.8, 0.8, 0.8, 0.7)
    gearBtn._icon = gearIcon

    gearBtn:SetScript("OnEnter", function() gearIcon:SetVertexColor(1, 1, 1, 1) end)
    gearBtn:SetScript("OnLeave", function() gearIcon:SetVertexColor(0.8, 0.8, 0.8, 0.7) end)

    -- Title text (e.g., "Overall", "Current") — to the right of gear button
    local titleText = header:CreateFontString(nil, "OVERLAY")
    titleText:SetFont(GetDefaultFont(), 13, "OUTLINE")
    titleText:SetPoint("LEFT", gearBtn, "RIGHT", 4, 0)
    titleText:SetTextColor(1, 1, 1, 1) -- default white
    titleText:SetText("Overall")
    titleText:SetWordWrap(true)
    titleText:SetMaxLines(2)
    titleText:SetNonSpaceWrap(false)

    -- Timer text (e.g., "[5:23]") — to the right of title
    local timerText = header:CreateFontString(nil, "OVERLAY")
    timerText:SetFont(GetDefaultFont(), 13, "OUTLINE")
    timerText:SetPoint("LEFT", titleText, "RIGHT", 4, 0)
    timerText:SetTextColor(1.0, 0.82, 0, 1) -- default yellow
    timerText:SetText("")

    -- Vertical title text (shown when verticalTitleMode is on)
    local verticalTitle = frame:CreateFontString(nil, "OVERLAY")
    verticalTitle:SetFont(GetDefaultFont(), 11, "OUTLINE")
    verticalTitle:SetTextColor(1, 1, 1, 0.7)
    verticalTitle:SetText("")
    verticalTitle:Hide()
    -- Rotate 90 degrees counter-clockwise for vertical text
    -- WoW doesn't support FontString rotation directly; workaround below:
    -- Put the text in a frame and rotate the frame... but WoW doesn't support
    -- frame rotation either. Use single-character-per-line approach instead.

    -- For vertical title: text is set as stacked characters in _UpdateTimerText

    -- Column headers (right side, created dynamically)
    local columnHeaders = {}
    local columnClickRegions = {}
    for c = 1, DMY.MAX_COLUMNS do
        local ch = header:CreateFontString(nil, "OVERLAY")
        ch:SetFont(GetDefaultFont(), 10, "OUTLINE")
        ch:SetTextColor(0.8, 0.8, 0.8, 1)
        ch:SetJustifyH("RIGHT")
        ch:Hide()
        columnHeaders[c] = ch

        -- Invisible overlay for right-click on column header
        local chClickRegion = CreateFrame("Button", nil, header)
        chClickRegion:SetAllPoints(ch)
        chClickRegion:SetFrameLevel(header:GetFrameLevel() + 2)
        chClickRegion:RegisterForClicks("RightButtonUp")
        chClickRegion:Hide()
        chClickRegion._colIndex = c
        columnClickRegions[c] = chClickRegion
    end

    -- Title right-click overlay (segment selector)
    local titleClickRegion = CreateFrame("Button", nil, header)
    titleClickRegion:SetAllPoints(titleText)
    titleClickRegion:SetFrameLevel(header:GetFrameLevel() + 2)
    titleClickRegion:RegisterForClicks("RightButtonUp")

    -- Segment selector menu (lazy, one per window)
    local segmentMenu = nil
    local winIdx = windowIndex -- capture for closures

    local function ApplySegmentChange(cfg)
        local c = DMY._comp
        if not c then return end
        -- Close drill-down if it belongs to this window (context invalidated)
        if DMY._activeDrilldown and DMY._activeDrilldown.windowIndex == winIdx then
            if DMY._CloseDrilldown then DMY._CloseDrilldown() end
        end
        DMY._UpdateSessionHeader(winIdx, c)
        DMY._CalculateColumnWidths(winIdx, c)
        DMY._LayoutBarRows(winIdx, c)
        if DMY._inCombat then
            DMY._UpdateWindowCombat(winIdx)
        else
            DMY._UpdateWindowOOC(winIdx)
        end
        DMY._UpdateTimerText(winIdx)
    end

    titleClickRegion:SetScript("OnClick", function(self, button)
        if button ~= "RightButton" then return end
        if not segmentMenu then
            segmentMenu = DMY._CreateFlyoutMenu(200)
        end
        segmentMenu:Clear()

        local cfg = DMY._GetWindowConfig(winIdx)
        if not cfg then return end

        -- Overall
        local isOverall = cfg.sessionType == 0 and not cfg.sessionID
        segmentMenu:AddRow("Overall", { 1, 1, 1, 0.9 }, function()
            cfg.sessionType = 0
            cfg.sessionID = nil
            cfg._sessionName = nil
            ApplySegmentChange(cfg)
        end, isOverall)

        -- Current
        local isCurrent = cfg.sessionType == 1 and not cfg.sessionID
        segmentMenu:AddRow("Current", { 1, 1, 1, 0.9 }, function()
            cfg.sessionType = 1
            cfg.sessionID = nil
            cfg._sessionName = nil
            ApplySegmentChange(cfg)
        end, isCurrent)

        -- Available expired segments from the API (sorted newest first)
        if C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions then
            local ok, available = pcall(C_DamageMeter.GetAvailableCombatSessions)
            if ok and available and #available > 0 then
                -- Sort by sessionID descending (most recent first)
                table.sort(available, function(a, b) return a.sessionID > b.sessionID end)
                segmentMenu:AddDivider()
                for _, session in ipairs(available) do
                    local name = session.name
                    if not name or name == "" then
                        name = "Combat #" .. session.sessionID
                    end
                    if session.durationSeconds then
                        name = name .. " [" .. DMY._FormatDuration(session.durationSeconds) .. "]"
                    end
                    local isThis = cfg.sessionID == session.sessionID
                    local sid = session.sessionID
                    local sname = session.name
                    segmentMenu:AddRow(name, { 0.8, 0.8, 0.8, 1 }, function()
                        cfg.sessionType = nil
                        cfg.sessionID = sid
                        cfg._sessionName = (sname and sname ~= "") and sname or nil
                        ApplySegmentChange(cfg)
                    end, isThis)
                end
            end
        end

        segmentMenu:ShowAtAnchor(self)
    end)

    -- Column format menu (lazy, one shared per window)
    local columnMenu = nil

    local function ShowColumnMenu(clickRegion)
        local colIdx = clickRegion._colIndex
        local cfg = DMY._GetWindowConfig(winIdx)
        if not cfg or not cfg.columns[colIdx] then return end
        local currentFormat = cfg.columns[colIdx].format

        if not columnMenu then
            columnMenu = DMY._CreateFlyoutMenu(160)
        end
        columnMenu:Clear()

        for gi, group in ipairs(COLUMN_FORMAT_GROUPS) do
            if gi > 1 then columnMenu:AddDivider() end
            for _, key in ipairs(group.keys) do
                local def = DMY.COLUMN_FORMATS[key]
                -- Exclude amountPerSecond-based formats from secondary columns
                if def and (colIdx == 1 or not DMY.SECONDARY_EXCLUDED_FORMATS[key]) then
                    columnMenu:AddRow(def.headerText, { 1, 1, 1, 0.9 }, function()
                        cfg.columns[colIdx].format = key
                        local c = DMY._comp
                        if c then
                            DMY._CalculateColumnWidths(winIdx, c)
                            DMY._LayoutBarRows(winIdx, c)
                            if DMY._inCombat then
                                DMY._UpdateWindowCombat(winIdx)
                            else
                                DMY._UpdateWindowOOC(winIdx)
                            end
                        end
                    end, currentFormat == key)
                end
            end
        end

        columnMenu:ShowAtAnchor(clickRegion)
    end

    for c = 1, DMY.MAX_COLUMNS do
        columnClickRegions[c]:SetScript("OnClick", function(self, button)
            if button ~= "RightButton" then return end
            ShowColumnMenu(self)
        end)
    end

    -- Header divider
    local headerDiv = frame:CreateTexture(nil, "ARTWORK")
    headerDiv:SetHeight(1)
    headerDiv:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    headerDiv:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
    headerDiv:SetColorTexture(0.3, 0.3, 0.35, 0.5)

    -- Scroll area (clips children)
    local scrollArea = CreateFrame("Frame", nil, frame)
    scrollArea:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -1)
    scrollArea:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    scrollArea:SetClipsChildren(true)

    -- Scroll content (height grows with data)
    local scrollContent = CreateFrame("Frame", nil, scrollArea)
    scrollContent:SetPoint("TOPLEFT", scrollArea, "TOPLEFT", 0, 0)
    scrollContent:SetPoint("RIGHT", scrollArea, "RIGHT", 0, 0)
    scrollContent:SetHeight(1) -- grows dynamically

    -- Mouse wheel for scrolling
    scrollArea:EnableMouseWheel(true)
    scrollArea:SetScript("OnMouseWheel", function(self, delta)
        local win = DMY._windows[windowIndex]
        if not win or not win.mergedData then return end
        local bh = (tonumber(db.barHeight) or 22) + (tonumber(db.barSpacing) or 2)
        local maxVisible = math.floor(scrollArea:GetHeight() / bh)
        local totalRows = #win.mergedData.playerOrder
        local maxOffset = math.max(0, totalRows - maxVisible)
        win.scrollOffset = math.max(0, math.min(win.scrollOffset - delta, maxOffset))
        DMY._RefreshBarRows(windowIndex, comp)
    end)

    -- Create bar row pool
    local barRows = {}
    for r = 1, DMY.MAX_POOL do
        barRows[r] = DMY._CreateBarRow(scrollContent, r, windowIndex)
    end

    -- Local player pinned row (separate frame below scroll area)
    local pinnedRow = DMY._CreateBarRow(frame, 0, windowIndex)
    pinnedRow:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    pinnedRow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

    local pinnedSeparator = frame:CreateTexture(nil, "ARTWORK")
    pinnedSeparator:SetHeight(PINNED_SEPARATOR_HEIGHT)
    pinnedSeparator:SetPoint("BOTTOMLEFT", pinnedRow, "TOPLEFT", 0, 0)
    pinnedSeparator:SetPoint("BOTTOMRIGHT", pinnedRow, "TOPRIGHT", 0, 0)
    pinnedSeparator:SetColorTexture(0.4, 0.4, 0.45, 0.6)
    pinnedSeparator:Hide()

    -- Gear button click handler: flyout menu with export + reset
    local gearMenu = nil
    gearBtn:SetScript("OnClick", function()
        -- Close any other window's gear menu first
        if activeDMYMenu and activeDMYMenu ~= gearMenu and activeDMYMenu:IsShown() then
            activeDMYMenu:Hide()
        end
        if gearMenu and gearMenu:IsShown() then
            gearMenu:Hide()
            return
        end
        if not gearMenu then
            -- Full-screen click-catcher to dismiss menu on outside click
            local backdrop = CreateFrame("Button", nil, UIParent)
            backdrop:SetAllPoints(UIParent)
            backdrop:SetFrameStrata("FULLSCREEN_DIALOG")
            backdrop:SetFrameLevel(199)
            backdrop:RegisterForClicks("AnyUp")
            backdrop:SetScript("OnClick", function()
                gearMenu:Hide()
            end)
            backdrop:Hide()

            gearMenu = CreateFrame("Frame", nil, UIParent)
            gearMenu:SetSize(160, 10) -- height computed dynamically below
            gearMenu:SetFrameStrata("FULLSCREEN_DIALOG")
            gearMenu:SetFrameLevel(200)
            gearMenu:EnableMouse(true)
            gearMenu:SetClampedToScreen(true)

            gearMenu:SetScript("OnHide", function()
                backdrop:Hide()
                activeDMYMenu = nil
            end)
            gearMenu:SetScript("OnShow", function()
                backdrop:Show()
            end)

            local menuBg = gearMenu:CreateTexture(nil, "BACKGROUND", nil, -8)
            menuBg:SetAllPoints()
            menuBg:SetColorTexture(0.06, 0.06, 0.08, 0.95)

            local menuBorder = { 0.3, 0.3, 0.35, 0.8 }
            for _, info in ipairs({
                { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
                { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false },
            }) do
                local t = gearMenu:CreateTexture(nil, "BORDER")
                t:SetPoint(info[1]); t:SetPoint(info[2])
                if info[3] then t:SetHeight(1) else t:SetWidth(1) end
                t:SetColorTexture(menuBorder[1], menuBorder[2], menuBorder[3], menuBorder[4])
            end

            local yOff = -6
            local function AddMenuRow(label, textColor, onClick)
                local btn = CreateFrame("Button", nil, gearMenu)
                btn:SetSize(152, 24)
                btn:SetPoint("TOP", gearMenu, "TOP", 0, yOff)
                local bg = btn:CreateTexture(nil, "BACKGROUND", nil, -6)
                bg:SetAllPoints()
                bg:SetColorTexture(1, 1, 1, 0)
                local txt = btn:CreateFontString(nil, "OVERLAY")
                txt:SetFont(GetDefaultFont(), 10, "OUTLINE")
                txt:SetPoint("LEFT", 8, 0)
                txt:SetText(label)
                txt:SetTextColor(textColor[1], textColor[2], textColor[3], textColor[4] or 1)
                btn:SetScript("OnEnter", function() bg:SetColorTexture(1, 1, 1, 0.08) end)
                btn:SetScript("OnLeave", function() bg:SetColorTexture(1, 1, 1, 0) end)
                btn:SetScript("OnClick", function()
                    gearMenu:Hide()
                    onClick()
                end)
                yOff = yOff - 24
                return btn
            end

            -- Reset All Data (red) — top of menu
            AddMenuRow("Reset All Data", { 1, 0.3, 0.3, 1 }, function()
                if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
                    C_DamageMeter.ResetAllCombatSessions()
                end
                DMY._HandleReset()
            end)

            -- Divider
            local divider = gearMenu:CreateTexture(nil, "ARTWORK")
            divider:SetSize(148, 1)
            divider:SetPoint("TOP", gearMenu, "TOP", 0, yOff - 3)
            divider:SetColorTexture(0.3, 0.3, 0.35, 0.5)
            yOff = yOff - 7

            -- Export to Window
            AddMenuRow("Export to Window", { 1, 1, 1, 0.9 }, function()
                if DMY._ExportToWindow then DMY._ExportToWindow(winIdx) end
            end)

            yOff = yOff - 4

            -- Export to Chat section
            local chatChannels = { "SAY", "PARTY", "RAID", "INSTANCE_CHAT", "GUILD" }
            local chatLabels = { SAY = "Say", PARTY = "Party", RAID = "Raid", INSTANCE_CHAT = "Instance", GUILD = "Guild" }
            local currentLines = (DMY._comp and DMY._comp.db and DMY._comp.db.exportChatLineCount) or 5

            local chatHeader = gearMenu:CreateFontString(nil, "OVERLAY")
            chatHeader:SetFont(GetDefaultFont(), 9, "OUTLINE")
            chatHeader:SetPoint("TOPLEFT", gearMenu, "TOPLEFT", 8, yOff)
            chatHeader:SetText("Export to Chat")
            chatHeader:SetTextColor(0.5, 0.5, 0.55, 1)
            yOff = yOff - 14

            -- Lines slider
            local sliderLabel = gearMenu:CreateFontString(nil, "OVERLAY")
            sliderLabel:SetFont(GetDefaultFont(), 9, "OUTLINE")
            sliderLabel:SetPoint("TOPLEFT", gearMenu, "TOPLEFT", 16, yOff)
            sliderLabel:SetTextColor(0.7, 0.7, 0.7, 1)

            local function UpdateSliderLabel()
                local count = (DMY._comp and DMY._comp.db and DMY._comp.db.exportChatLineCount) or 5
                sliderLabel:SetText("Lines: " .. count)
            end
            UpdateSliderLabel()
            yOff = yOff - 14

            local slider = CreateFrame("Slider", nil, gearMenu, "OptionsSliderTemplate")
            slider:SetSize(136, 14)
            slider:SetPoint("TOP", gearMenu, "TOP", 0, yOff)
            slider:SetMinMaxValues(1, 20)
            slider:SetValueStep(1)
            slider:SetObeyStepOnDrag(true)
            if slider.Text then slider.Text:SetText("") end
            if slider.Low then slider.Low:SetText("") end
            if slider.High then slider.High:SetText("") end

            slider:SetValue(currentLines)
            slider:SetScript("OnValueChanged", function(_, value)
                value = math.floor(value)
                if DMY._comp and DMY._comp.db then
                    DMY._comp.db.exportChatLineCount = value
                end
                currentLines = value
                UpdateSliderLabel()
            end)
            gearMenu._slider = slider
            yOff = yOff - 16

            -- Channel buttons
            for _, ch in ipairs(chatChannels) do
                local chBtn = CreateFrame("Button", nil, gearMenu)
                chBtn:SetSize(152, 20)
                chBtn:SetPoint("TOP", gearMenu, "TOP", 0, yOff)
                local chBg = chBtn:CreateTexture(nil, "BACKGROUND", nil, -6)
                chBg:SetAllPoints()
                chBg:SetColorTexture(1, 1, 1, 0)
                local chText = chBtn:CreateFontString(nil, "OVERLAY")
                chText:SetFont(GetDefaultFont(), 9, "OUTLINE")
                chText:SetPoint("LEFT", 16, 0)
                chText:SetText(chatLabels[ch] or ch)
                chText:SetTextColor(1, 1, 1, 0.8)
                local sendText = chBtn:CreateFontString(nil, "OVERLAY")
                sendText:SetFont(GetDefaultFont(), 9, "OUTLINE")
                sendText:SetPoint("RIGHT", -8, 0)
                sendText:SetText("Send")
                sendText:SetTextColor(0.5, 0.5, 0.5, 0.6)
                chBtn:SetScript("OnEnter", function()
                    chBg:SetColorTexture(1, 1, 1, 0.08)
                    sendText:SetTextColor(0.3, 1.0, 0.3, 1)
                end)
                chBtn:SetScript("OnLeave", function()
                    chBg:SetColorTexture(1, 1, 1, 0)
                    sendText:SetTextColor(0.5, 0.5, 0.5, 0.6)
                end)
                chBtn:SetScript("OnClick", function()
                    gearMenu:Hide()
                    if DMY._ExportToChatChannel then
                        DMY._ExportToChatChannel(winIdx, ch, currentLines)
                    end
                end)
                yOff = yOff - 20
            end

            gearMenu:SetHeight(math.abs(yOff) + 6)
        end

        -- Sync slider value on every show
        if gearMenu._slider then
            local count = (DMY._comp and DMY._comp.db and DMY._comp.db.exportChatLineCount) or 5
            gearMenu._slider:SetValue(count)
        end

        -- Smart positioning: flip above gear button when near screen bottom
        gearMenu:ClearAllPoints()
        local btnBottom = select(2, gearBtn:GetCenter()) - (gearBtn:GetHeight() / 2)
        local scale = UIParent:GetEffectiveScale()
        local spaceBelow = btnBottom * scale

        if spaceBelow > gearMenu:GetHeight() + 10 then
            gearMenu:SetPoint("TOPLEFT", gearBtn, "BOTTOMLEFT", 0, -2)
        else
            gearMenu:SetPoint("BOTTOMLEFT", gearBtn, "TOPLEFT", 0, 2)
        end
        gearMenu:Show()
        activeDMYMenu = gearMenu
    end)

    -- Store window state
    DMY._windows[windowIndex] = {
        frame = frame,
        background = background,
        header = header,
        gearBtn = gearBtn,
        titleText = titleText,
        timerText = timerText,
        verticalTitle = verticalTitle,
        columnHeaders = columnHeaders,
        columnClickRegions = columnClickRegions,
        titleClickRegion = titleClickRegion,
        scrollArea = scrollArea,
        scrollContent = scrollContent,
        barRows = barRows,
        pinnedRow = pinnedRow,
        pinnedSeparator = pinnedSeparator,
        scrollOffset = 0,
        mergedData = nil,
        lastUpdateTime = 0,
    }
end

--------------------------------------------------------------------------------
-- Accessors
--------------------------------------------------------------------------------

DMY.HEADER_HEIGHT = HEADER_HEIGHT
DMY.ICON_SIZE = ICON_SIZE
DMY.NAME_WIDTH = NAME_WIDTH
