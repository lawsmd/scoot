-- notes.lua - Notes Component: persistent on-screen text fields styled like GameTooltip
local addonName, addon = ...

local MAX_NOTES = 5
local MAX_WIDTH = 300
local MIN_WIDTH = 120
local PADDING = 12
local HEADER_BODY_GAP = 8
local INDICATOR_GAP = 4

-- Default tooltip background color (matches Blizzard's TOOLTIP_DEFAULT_BACKGROUND_COLOR)
local DEFAULT_BG_COLOR = { 0.09, 0.09, 0.19 }

local noteFrames = {}

--------------------------------------------------------------------------------
-- Font Resolution (reads from Tooltip component)
--------------------------------------------------------------------------------

local function GetTooltipDB()
    local comp = addon.Components and addon.Components["tooltip"]
    return comp and comp.db
end

local function ResolveFontFace(faceKey)
    if addon.ResolveFontFace then
        return addon.ResolveFontFace(faceKey)
    end
    return select(1, _G.GameFontNormal:GetFont())
end

local function ApplyHeaderFont(fontString, noteDb)
    local tooltipDb = GetTooltipDB()
    local cfg = tooltipDb and type(tooltipDb.textTitle) == "table" and tooltipDb.textTitle or {}
    local face = ResolveFontFace(cfg.fontFace or "FRIZQT__")
    local size = tonumber(cfg.size) or 14
    local style = cfg.style or "OUTLINE"
    pcall(fontString.SetFont, fontString, face, size, style)

    local c = noteDb and noteDb.headerColor or { 0.1, 1.0, 0.1, 1 }
    fontString:SetTextColor(c[1] or 0.1, c[2] or 1.0, c[3] or 0.1, c[4] or 1)
end

local function ApplyBodyFont(fontString, noteDb)
    local tooltipDb = GetTooltipDB()
    local cfg = tooltipDb and type(tooltipDb.textEverythingElse) == "table" and tooltipDb.textEverythingElse or {}
    local face = ResolveFontFace(cfg.fontFace or "FRIZQT__")
    local size = tonumber(cfg.size) or 12
    local style = cfg.style or "OUTLINE"
    pcall(fontString.SetFont, fontString, face, size, style)

    local c = noteDb and noteDb.bodyColor or { 1, 1, 1, 1 }
    fontString:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
end

--------------------------------------------------------------------------------
-- NineSlice Border Tint (reads from Tooltip component)
--------------------------------------------------------------------------------

local function ApplyBorderTint(nineSlice)
    if not nineSlice or not nineSlice.SetBorderColor then return end
    local tooltipDb = GetTooltipDB()
    if tooltipDb and tooltipDb.borderTintEnable then
        local c = tooltipDb.borderTintColor or { 1, 1, 1, 1 }
        nineSlice:SetBorderColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    else
        nineSlice:SetBorderColor(1, 1, 1, 1)
    end
end

--------------------------------------------------------------------------------
-- Note Frame Creation
--------------------------------------------------------------------------------

local function GetSettingKey(index, key)
    return "note" .. index .. key
end

local function GetNoteSetting(db, index, key)
    if not db then return nil end
    return db[GetSettingKey(index, key)]
end

local UpdateCollapseState -- forward declaration

local function CreateNoteFrame(index)
    local frame = CreateFrame("Frame", "ScootNote" .. index, UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetSize(MIN_WIDTH, 40)

    -- Default position (staggered vertically, overwritten by saved Edit Mode position)
    local yStagger = -100 + (index - 1) * 60
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, yStagger)

    -- NineSlice child for tooltip border
    local nineSlice = CreateFrame("Frame", nil, frame, "NineSlicePanelTemplate")
    nineSlice:SetAllPoints(frame)
    nineSlice:SetFrameLevel(frame:GetFrameLevel())

    local layout = NineSliceUtil.GetLayout("TooltipDefaultLayout")
    if layout then
        NineSliceUtil.ApplyLayout(nineSlice, layout)
        NineSliceUtil.DisableSharpening(nineSlice)
    end

    -- Background fill
    local bgColor = TOOLTIP_DEFAULT_BACKGROUND_COLOR
    local bgR, bgG, bgB
    if bgColor and bgColor.GetRGB then
        bgR, bgG, bgB = bgColor:GetRGB()
    else
        bgR, bgG, bgB = DEFAULT_BG_COLOR[1], DEFAULT_BG_COLOR[2], DEFAULT_BG_COLOR[3]
    end
    nineSlice:SetCenterColor(bgR, bgG, bgB, 1)

    frame._nineSlice = nineSlice

    -- Collapse indicator Texture (atlas chevron)
    local indicator = frame:CreateTexture(nil, "OVERLAY")
    indicator:SetAtlas("questlog-icon-shrink")
    indicator:SetSize(12, 12)
    indicator:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -PADDING)
    indicator:SetAlpha(0.6)
    frame._collapseIndicator = indicator

    -- Header FontString (anchored to right of indicator)
    local header = frame:CreateFontString(nil, "OVERLAY")
    header:SetFont(select(1, GameFontNormal:GetFont()), 14, "OUTLINE")
    header:SetPoint("LEFT", indicator, "RIGHT", INDICATOR_GAP, 0)
    header:SetJustifyH("LEFT")
    header:SetWordWrap(false)
    frame._header = header

    -- Body FontString
    local body = frame:CreateFontString(nil, "OVERLAY")
    body:SetFont(select(1, GameFontNormal:GetFont()), 12, "OUTLINE")
    body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -HEADER_BODY_GAP)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetWordWrap(true)
    frame._body = body

    -- Toggle button covering header row
    local toggleBtn = CreateFrame("Button", nil, frame)
    toggleBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    toggleBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    toggleBtn:SetPoint("BOTTOM", header, "BOTTOM", 0, -PADDING)
    toggleBtn:SetFrameLevel(nineSlice:GetFrameLevel() + 1)
    toggleBtn:RegisterForClicks("LeftButtonUp")
    toggleBtn:SetScript("OnClick", function()
        local comp = addon.Components["notes"]
        if not comp or not comp.db then return end
        local key = GetSettingKey(index, "Collapsed")
        comp.db[key] = not comp.db[key]
        UpdateCollapseState(frame, index)
    end)
    toggleBtn:SetScript("OnEnter", function()
        indicator:SetAlpha(1.0)
    end)
    toggleBtn:SetScript("OnLeave", function()
        indicator:SetAlpha(0.6)
    end)
    frame._toggleBtn = toggleBtn

    frame:Hide()
    noteFrames[index] = frame
    return frame
end

--------------------------------------------------------------------------------
-- Auto-sizing
--------------------------------------------------------------------------------

local function UpdateNoteSize(frame)
    if not frame then return end
    local header = frame._header
    local body = frame._body
    local indicator = frame._collapseIndicator
    local indicatorWidth = indicator and (indicator:GetWidth() or 0) or 0

    -- Set width constraint for body text wrapping
    local headerWidth = header:GetStringWidth() or 0
    local bodyWidth = body:GetStringWidth() or 0
    local contentWidth = math.max(headerWidth, math.min(bodyWidth, MAX_WIDTH))
    contentWidth = math.max(MIN_WIDTH, math.min(contentWidth, MAX_WIDTH))

    body:SetWidth(contentWidth)

    -- Recalculate after width constraint
    C_Timer.After(0, function()
        if not frame or not frame:IsShown() then return end
        local hh = header:GetStringHeight() or 0
        local hasHeader = header:GetText() and header:GetText() ~= ""

        local extraLeft = indicatorWidth + INDICATOR_GAP

        if frame._isCollapsed then
            -- Collapsed: header only, no body
            local totalH = PADDING * 2
            if hasHeader then
                totalH = totalH + hh
            else
                totalH = totalH + (indicator and indicator:GetHeight() or 0)
            end
            local collapsedContentW = headerWidth
            collapsedContentW = math.max(MIN_WIDTH, math.min(collapsedContentW, MAX_WIDTH))
            local finalWidth = collapsedContentW + extraLeft + PADDING * 2
            frame:SetSize(finalWidth, totalH)
        else
            -- Expanded: full layout
            local bh = body:GetStringHeight() or 0
            local hasBody = body:GetText() and body:GetText() ~= ""

            local totalH = PADDING * 2
            if hasHeader then
                totalH = totalH + hh
            end
            if hasHeader and hasBody then
                totalH = totalH + HEADER_BODY_GAP
            end
            if hasBody then
                totalH = totalH + bh
            end

            local finalWidth = contentWidth + extraLeft + PADDING * 2
            frame:SetSize(finalWidth, totalH)
        end
    end)
end

--------------------------------------------------------------------------------
-- Collapse State
--------------------------------------------------------------------------------

UpdateCollapseState = function(frame, index)
    if not frame then return end
    local comp = addon.Components["notes"]
    local db = comp and comp.db
    local collapsed = db and GetNoteSetting(db, index, "Collapsed") or false

    frame._isCollapsed = collapsed

    if collapsed then
        frame._body:Hide()
        frame._collapseIndicator:SetAtlas("questlog-icon-expand")
        -- Center indicator+header vertically in collapsed frame
        frame._collapseIndicator:ClearAllPoints()
        frame._collapseIndicator:SetPoint("LEFT", frame, "LEFT", PADDING, 0)
    else
        frame._body:Show()
        frame._collapseIndicator:SetAtlas("questlog-icon-shrink")
        -- Restore top-left anchoring for expanded layout
        frame._collapseIndicator:ClearAllPoints()
        frame._collapseIndicator:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -PADDING)
    end

    UpdateNoteSize(frame)
end

--------------------------------------------------------------------------------
-- Position Persistence (LibEditMode)
--------------------------------------------------------------------------------

local function SaveNotePosition(index, layoutName, point, x, y)
    if not addon.db or not addon.db.profile then return end
    addon.db.profile.notePositions = addon.db.profile.notePositions or {}
    addon.db.profile.notePositions[index] = addon.db.profile.notePositions[index] or {}
    addon.db.profile.notePositions[index][layoutName] = {
        point = point,
        x = x,
        y = y,
    }
end

local function RestoreNotePosition(index, layoutName)
    local frame = noteFrames[index]
    if not frame then return end

    local positions = addon.db and addon.db.profile and addon.db.profile.notePositions
    local notePositions = positions and positions[index]
    local pos = notePositions and notePositions[layoutName]

    if pos and pos.point then
        frame:ClearAllPoints()
        frame:SetPoint(pos.point, pos.x or 0, pos.y or 0)
    end
end

local editModeInitialized = false

local function InitializeEditMode()
    if editModeInitialized then return end
    local lib = LibStub("LibEditMode", true)
    if not lib then return end

    local db = addon.Components["notes"] and addon.Components["notes"].db
    if not db then return end

    local registeredAny = false

    for i = 1, MAX_NOTES do
        local frame = noteFrames[i]
        if frame then
            frame.editModeName = "Note " .. i

            local noteIndex = i
            local yStagger = -100 + (i - 1) * 60
            local dp = { point = "CENTER", x = 0, y = yStagger }

            lib:AddFrame(frame, function(f, layoutName, point, x, y)
                if point and x and y then
                    f:ClearAllPoints()
                    f:SetPoint(point, x, y)
                end
                if layoutName then
                    local savedPoint, _, _, savedX, savedY = f:GetPoint(1)
                    if savedPoint then
                        SaveNotePosition(noteIndex, layoutName, savedPoint, savedX, savedY)
                    else
                        SaveNotePosition(noteIndex, layoutName, point, x, y)
                    end
                end
            end, {
                point = dp.point,
                x = dp.x,
                y = dp.y,
            }, nil)

            registeredAny = true
        end
    end

    if registeredAny then
        lib:RegisterCallback("layout", function(layoutName, layoutIndex)
            for i = 1, MAX_NOTES do
                RestoreNotePosition(i, layoutName)
            end
        end)

        lib:RegisterCallback("enter", function()
            -- Show all enabled notes during edit mode
            local noteDb = addon.Components["notes"] and addon.Components["notes"].db
            if not noteDb then return end
            for i = 1, MAX_NOTES do
                local enabled = GetNoteSetting(noteDb, i, "Enabled")
                local frame = noteFrames[i]
                if frame and enabled then
                    frame:Show()
                end
            end
        end)

        lib:RegisterCallback("exit", function()
            -- Re-apply to reflect current state
            local comp = addon.Components["notes"]
            if comp and comp.ApplyStyling then
                comp:ApplyStyling()
            end
        end)
    end

    editModeInitialized = true
end

--------------------------------------------------------------------------------
-- ApplyStyling
--------------------------------------------------------------------------------

local function ApplyNotesStyling(self)
    local db = self.db
    if not db then return end

    local anyEnabled = false

    for i = 1, MAX_NOTES do
        local enabled = GetNoteSetting(db, i, "Enabled")

        if not enabled then
            local frame = noteFrames[i]
            if frame then frame:Hide() end
        else
            anyEnabled = true

            -- Create frame lazily
            local frame = noteFrames[i]
            if not frame then
                frame = CreateNoteFrame(i)
            end

            -- Set text
            local headerText = GetNoteSetting(db, i, "HeaderText") or ""
            local bodyText = GetNoteSetting(db, i, "BodyText") or ""

            frame._header:SetText(headerText)
            frame._body:SetText(bodyText)

            -- Apply font styling from tooltip component
            ApplyHeaderFont(frame._header, {
                headerColor = GetNoteSetting(db, i, "HeaderColor"),
            })
            ApplyBodyFont(frame._body, {
                bodyColor = GetNoteSetting(db, i, "BodyColor"),
            })

            -- Indicator tint: slightly desaturated white
            frame._collapseIndicator:SetVertexColor(0.85, 0.85, 0.85, 1)
            frame._collapseIndicator:SetAlpha(0.6)

            -- Apply border tint from tooltip component
            ApplyBorderTint(frame._nineSlice)

            -- Apply scale
            local scale = GetNoteSetting(db, i, "Scale") or 1.0
            frame:SetScale(math.max(0.25, math.min(2.0, scale)))

            -- Update size, restore collapse state, and show
            UpdateNoteSize(frame)
            frame:Show()
            UpdateCollapseState(frame, i)
        end
    end

    -- Initialize edit mode once we have frames
    if anyEnabled and not editModeInitialized then
        C_Timer.After(0, InitializeEditMode)
    end
end

--------------------------------------------------------------------------------
-- Component Registration
--------------------------------------------------------------------------------

addon:RegisterComponentInitializer(function(self)
    local Component = addon.ComponentPrototype

    -- Build flat settings for all 5 notes
    local settings = {}
    for i = 1, MAX_NOTES do
        settings[GetSettingKey(i, "Enabled")]     = { type = "addon", default = false }
        settings[GetSettingKey(i, "HeaderText")]   = { type = "addon", default = "" }
        settings[GetSettingKey(i, "BodyText")]     = { type = "addon", default = "" }
        settings[GetSettingKey(i, "Scale")]        = { type = "addon", default = 1.0 }
        settings[GetSettingKey(i, "HeaderColor")]  = { type = "addon", default = { 0.1, 1.0, 0.1, 1 } }
        settings[GetSettingKey(i, "BodyColor")]    = { type = "addon", default = { 1, 1, 1, 1 } }
        settings[GetSettingKey(i, "Collapsed")]    = { type = "addon", default = false }
    end

    local notesComponent = Component:New({
        id = "notes",
        name = "Notes",
        settings = settings,
        ApplyStyling = ApplyNotesStyling,
    })

    self:RegisterComponent(notesComponent)
end)
