-- EditorWindow.lua - The pop-up ScootAura editor
--
-- Stateless: no save button, edits apply instantly, X or ESC closes. A new
-- tracker starts as a session-local draft; it materializes the moment the
-- three content choices are made AND a spell ID validates. Closing before
-- that discards the draft and leaves saved variables untouched.
--
-- Strata: DIALOG level 120. Above the settings window (DIALOG 100), below
-- every Selector dropdown, Flyout and picker (FULLSCREEN_DIALOG).
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.ScootAuraEditor = {}
local Editor = addon.UI.ScootAuraEditor

-- Size targets, clamped to the screen at init; the region splits are
-- recomputed from the final size so the quadrants scale with the window.
local WINDOW_W, WINDOW_H = 1450, 940
local TITLE_H = 40
local TOP_H = 423
local TOP_LEFT_W = 797
local BOTTOM_LEFT_W = 667
local PAD = 10
-- Gap between the quadrant top and the selector block (the builder adds its
-- own 8 px first-row offset beneath this).
local SELECTORS_TOP_GAP = 24
local TITLE_ICON = 16      -- rename pencil, duplicate copy
local TITLE_ICON_GAP = 5   -- name glyphs to the first icon, and icon to icon

local frame
local session
local widgets = {}   -- static widgets built once at init

-- Per-region builders, replaced wholesale on every dynamic render
local selBuilder, tabsBuilder, prevBuilder
local cdmPicker
local refreshPending = false
local validationToken = 0

local function SAU() return addon.ScootAuras end
local function Helpers() return addon.UI.Settings.Helpers end

--------------------------------------------------------------------------------
-- Session settings context (the draft seam)
--------------------------------------------------------------------------------

local defaultsCache
local function DefaultFor(key)
    if not defaultsCache then defaultsCache = SAU().DefaultSettings() end
    local def = defaultsCache[key]
    return def and def.default
end

local function CurrentTracker()
    return session and session.trackerId and SAU().GetTracker(session.trackerId) or nil
end

local ctx = {}

function ctx.get(key)
    if not session then return DefaultFor(key) end
    if session.trackerId then
        local v = Helpers().getSetting(SAU().GetComponentId(session.trackerId), key)
        if v == nil then v = DefaultFor(key) end
        return v
    end
    local v = session.draft.styling[key]
    if v == nil and ctx.shape() == "bar" then
        -- Bar drafts see the bar-shape starting values the stamp will write
        -- at materialization, so controls and preview agree pre- and post-.
        local o = SAU().BarShapeStartingValues[key]
        if o ~= nil then v = o end
    end
    if v == nil and ctx.kind() == "missingbuff" then
        local o = SAU().MissingKindStartingValues[key]
        if o ~= nil then v = o end
    end
    if v == nil then v = DefaultFor(key) end
    return v
end

function ctx.setAndApply(key, value)
    if not session then return end
    if session.trackerId then
        local h = Helpers().CreateComponentHelpers(SAU().GetComponentId(session.trackerId))
        h.setAndApplyComponent(key, value)
    else
        session.draft.styling[key] = value
    end
end

function ctx.shape()
    local tracker = CurrentTracker()
    if tracker then return tracker.shape end
    return (session and session.draft.content.shape) or "icon"
end

function ctx.kind()
    local tracker = CurrentTracker()
    if tracker then return tracker.kind end
    return (session and session.draft.content.kind) or "buff"
end

function ctx.refresh()
    Editor.DeferredRefresh()
end

-- For value-only edits (sliders, colors, fonts, anchors): re-renders the
-- preview without rebuilding the tab body. A tab rebuild re-measures every
-- row over two frames, which reads as a flicker on each arrow click.
function ctx.refreshPreview()
    Editor.DeferredPreviewRefresh()
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function RefreshList()
    if addon.ScootAurasUI and addon.ScootAurasUI.RefreshList then
        addon.ScootAurasUI.RefreshList()
    end
end

local function CurrentName()
    local tracker = CurrentTracker()
    if tracker then return SAU().DisplayName(tracker) end
    local c = session and session.draft.content
    if c and c.name then return c.name end
    return "New Aura Tracker"
end

-- Icon as the Aura List and the CDM picker show it (SAU.DescribeSpell: the
-- CDM override chain, so a base spell wears its talent's art and name).
local function PlainSpellTexture(spellId)
    return SAU()._SpellIcon(spellId)
end

--------------------------------------------------------------------------------
-- Materialization (draft -> tracker)
--------------------------------------------------------------------------------

local function TryMaterialize()
    if not session or session.trackerId then return end
    local c = session.draft.content
    if not (c.kind and c.unit and c.shape and session.validated) then return end

    local id, err = SAU().CreateTracker({
        spellId = session.validated.spellId,
        kind = c.kind,
        unit = c.unit,
        shape = c.shape,
        name = c.name,
        onlyInCombat = c.onlyInCombat,
    })
    if not id then
        session.statusOverride = err or "Could not create the tracker."
        return
    end

    -- Draft styling lands in the fresh component db, then one restyle pass.
    local db = addon:EnsureComponentDB(SAU().GetComponentId(id))
    if db then
        for k, v in pairs(session.draft.styling) do db[k] = v end
    end
    session.trackerId = id
    session.draft = nil
    local tracker = SAU().GetTracker(id)
    if tracker and SAU()._ApplyStyling then SAU()._ApplyStyling(id, tracker) end
    RefreshList()
end

--------------------------------------------------------------------------------
-- Spell validation ladder: tonumber -> DoesSpellExist -> async hydration
--------------------------------------------------------------------------------

local function ApplyValidatedSpell()
    if not session or not session.validated then return end
    if session.trackerId then
        SAU().SetTrackerContent(session.trackerId, { spellId = session.validated.spellId })
        RefreshList()
    else
        TryMaterialize()
    end
end

local function ValidateSpell(spellId)
    if not session then return end
    validationToken = validationToken + 1
    local token = validationToken
    session.validated = nil
    session.statusOverride = nil

    spellId = tonumber(spellId)
    if not spellId or spellId <= 0 or spellId ~= math.floor(spellId) then
        session.statusOverride = "Enter a spell ID, or pick one from the catalog below."
        Editor.DeferredRefresh()
        return
    end

    local ok, exists = pcall(C_Spell.DoesSpellExist, spellId)
    if not ok or not exists then
        session.statusOverride = "No spell exists with ID " .. spellId .. "."
        Editor.DeferredRefresh()
        return
    end

    session.statusOverride = "Checking spell " .. spellId .. "..."
    Editor.DeferredRefresh()

    local SpellObj = _G.Spell
    if not (SpellObj and SpellObj.CreateFromSpellID) then
        -- No hydration path; DoesSpellExist already passed, accept it.
        local name, icon = SAU().DescribeSpell(spellId)
        session.validated = { spellId = spellId, name = name, icon = icon }
        session.statusOverride = nil
        session.timerEpoch = {}
        ApplyValidatedSpell()
        Editor.DeferredRefresh()
        return
    end

    local spell = SpellObj:CreateFromSpellID(spellId)
    spell:ContinueOnSpellLoad(function()
        if token ~= validationToken or not session then return end
        -- Hydrated now; describe through the shared resolver so the chip
        -- matches the picker cell that was clicked.
        local name, icon = SAU().DescribeSpell(spellId)
        session.validated = {
            spellId = spellId,
            name = name,
            icon = icon,
        }
        session.statusOverride = nil
        session.timerEpoch = {}
        ApplyValidatedSpell()
        Editor.DeferredRefresh()
    end)
end

--------------------------------------------------------------------------------
-- Window construction (once)
--------------------------------------------------------------------------------

local function SavePosition()
    if not (addon.db and addon.db.global and frame) then return end
    local point, _, relPoint, x, y = frame:GetPoint()
    addon.db.global.scootAuraEditorPosition = { point = point, relPoint = relPoint, x = x, y = y }
end

local function RestorePosition()
    frame:ClearAllPoints()
    local pos = addon.db and addon.db.global and addon.db.global.scootAuraEditorPosition
    if pos and pos.point and pos.x and pos.y then
        frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    end
end

local function CreateSeparator(parent)
    local theme = addon.UI.Theme
    local tex = parent:CreateTexture(nil, "BORDER", nil, 1)
    local ar, ag, ab = theme:GetAccentColor()
    tex:SetColorTexture(ar, ag, ab, 0.25)
    return tex
end

local function InitializeFrame()
    if frame then return end
    local Window = addon.UI.Window
    local theme = addon.UI.Theme
    local ar, ag, ab = theme:GetAccentColor()

    WINDOW_W = math.min(WINDOW_W, math.floor((UIParent:GetWidth() or 1600) * 0.92))
    WINDOW_H = math.min(WINDOW_H, math.floor((UIParent:GetHeight() or 980) * 0.90))
    TOP_H = math.floor(WINDOW_H * 0.45)
    TOP_LEFT_W = math.floor(WINDOW_W * 0.55)
    BOTTOM_LEFT_W = math.floor(WINDOW_W * 0.46)

    -- Modal dim behind the editor, dialog-style: DIALOG 110 darkens and
    -- mouse-blocks everything below (settings panel included), the editor at
    -- 120 floats above it.
    local dim = CreateFrame("Frame", "ScootAuraEditorDim", UIParent)
    dim:SetFrameStrata("DIALOG")
    dim:SetFrameLevel(110)
    dim:SetAllPoints(UIParent)
    dim:EnableMouse(true)
    dim:Hide()
    local dimTex = dim:CreateTexture(nil, "BACKGROUND")
    dimTex:SetAllPoints()
    dimTex:SetColorTexture(0, 0, 0, 0.80)
    widgets.dim = dim

    frame = Window:Create("ScootAuraEditorFrame", UIParent, WINDOW_W, WINDOW_H)
    frame:SetFrameLevel(120)
    frame:HookScript("OnShow", function() dim:Show() end)
    frame:HookScript("OnHide", function() dim:Hide() end)
    frame:Hide()
    RestorePosition()

    -- Title bar: drag surface + name + rename + close
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetHeight(TITLE_H)
    titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        SavePosition()
    end)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY")
    titleText:SetFont(theme:GetFont("HEADER"), 16, "")
    titleText:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
    titleText:SetTextColor(ar, ag, ab, 1)
    widgets.titleText = titleText

    -- Title icons: the rename pencil, then the duplicate copy for a tracker in
    -- a group. Both float right of the centered title; drafts hide them.
    -- Leveled above the carousel viewport (+2) and its name buttons (+3).
    local function TitleIcon(atlas, tooltip)
        local btn = CreateFrame("Button", nil, titleBar)
        btn:SetSize(TITLE_ICON, TITLE_ICON)
        btn:SetFrameLevel(titleBar:GetFrameLevel() + 6)
        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetAtlas(atlas)
        tex:SetDesaturated(true)
        tex:SetVertexColor(ar, ag, ab)
        tex:SetAlpha(0.35)
        btn:SetScript("OnEnter", function(self)
            tex:SetAlpha(0.8)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(tooltip, 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            tex:SetAlpha(0.35)
            GameTooltip:Hide()
        end)
        return btn
    end

    local renameBtn = TitleIcon("Pencil-Icon", "Rename")
    local duplicateBtn = TitleIcon("friends-icon-battlenet-copy", "Duplicate into this group")
    widgets.renameBtn = renameBtn
    widgets.duplicateBtn = duplicateBtn

    -- Both icons follow whichever name is centered: the plain title, or the
    -- carousel's selected member when the tracker is in a group. They anchor to
    -- the text rather than the carousel's padded hit box, so they sit against
    -- the glyphs and stay clear of the neighboring names.
    local function AnchorTitleIcons()
        local target = widgets.carouselActive and widgets.carousel.selectedAnchor or titleText
        renameBtn:ClearAllPoints()
        renameBtn:SetPoint("LEFT", target, "RIGHT", TITLE_ICON_GAP, 0)
        duplicateBtn:ClearAllPoints()
        duplicateBtn:SetPoint("LEFT", renameBtn, "RIGHT", TITLE_ICON_GAP, 0)
    end
    widgets.AnchorTitleIcons = AnchorTitleIcons

    -- Duplicating is a group action, so that icon also needs widgets.inGroup.
    local function SetTitleIconsShown(shown)
        renameBtn:SetShown(shown)
        duplicateBtn:SetShown(not not (shown and widgets.inGroup))
    end
    widgets.SetTitleIconsShown = SetTitleIconsShown

    -- Copies the open tracker into its group beside itself, then edits the copy.
    duplicateBtn:SetScript("OnClick", function()
        local tracker = CurrentTracker()
        if not (tracker and tracker.groupId) then return end
        local newId = SAU().DuplicateTrackerInGroup(session.trackerId)
        if not newId then return end
        GameTooltip:Hide()
        RefreshList()
        Editor.Open(newId)
    end)

    -- Group carousel: the title name becomes a spinnable strip of the group's
    -- members. Selection defers a frame so the release frame stays smooth.
    local carousel = addon.UI.ScootAuraTitleCarousel.Create(titleBar, {
        width = math.min(math.floor(WINDOW_W * 0.62), WINDOW_W - 120),
        font = theme:GetFont("HEADER"),
        arrowFont = theme:GetFont("BUTTON"),
        color = { ar, ag, ab },
        dimColor = { theme.TEXT_DIM.r, theme.TEXT_DIM.g, theme.TEXT_DIM.b },
        selectedRoom = 2 * (TITLE_ICON_GAP + TITLE_ICON),
        onSelect = function(trackerId)
            C_Timer.After(0, function()
                if session and session.trackerId ~= trackerId and SAU().GetTracker(trackerId) then
                    Editor.Open(trackerId)
                end
            end)
        end,
        onMotion = function(moving)
            if not widgets.carouselActive or widgets.renameBox:IsShown() then return end
            if moving then
                SetTitleIconsShown(false)
            else
                AnchorTitleIcons()
                SetTitleIconsShown(true)
            end
        end,
    })
    widgets.carousel = carousel
    widgets.carouselActive = false

    -- Whichever title surface is live swaps out for the rename box
    local function SetTitleShown(shown)
        if widgets.carouselActive then
            if shown then carousel:Show() else carousel:Hide() end
        else
            titleText:SetShown(shown)
        end
    end

    local renameBox = CreateFrame("EditBox", nil, titleBar, "InputBoxTemplate")
    renameBox:SetSize(220, 20)
    renameBox:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
    renameBox:SetJustifyH("CENTER")
    renameBox:SetAutoFocus(false)
    renameBox:SetMaxLetters(40)
    renameBox:SetFrameLevel(titleBar:GetFrameLevel() + 10)
    renameBox:SetFont(theme:GetFont("HEADER"), 14, "")
    if renameBox.Left then renameBox.Left:Hide() end
    if renameBox.Right then renameBox.Right:Hide() end
    if renameBox.Middle then renameBox.Middle:Hide() end
    renameBox:Hide()
    widgets.renameBox = renameBox

    local function CommitRename()
        local name = renameBox:GetText()
        renameBox:Hide()
        SetTitleShown(true)
        SetTitleIconsShown(true)
        if type(name) ~= "string" or name == "" then return end
        if session and session.trackerId then
            SAU().RenameTracker(session.trackerId, name)
            RefreshList()
        end
        Editor.DeferredRefresh()
    end

    renameBtn:SetScript("OnClick", function()
        renameBox:SetText(CurrentName())
        SetTitleShown(false)
        SetTitleIconsShown(false)
        renameBox:Show()
        renameBox:SetFocus()
        renameBox:HighlightText()
    end)
    renameBox:SetScript("OnEnterPressed", CommitRename)
    renameBox:SetScript("OnEscapePressed", function()
        renameBox:Hide()
        SetTitleShown(true)
        SetTitleIconsShown(true)
    end)
    renameBox:SetScript("OnEditFocusLost", function()
        if renameBox:IsShown() then
            renameBox:Hide()
            SetTitleShown(true)
            SetTitleIconsShown(true)
        end
    end)

    -- Close X
    local closeBtn = CreateFrame("Button", nil, frame)
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
    closeBtn:SetFrameLevel(frame:GetFrameLevel() + 10)
    closeBtn:RegisterForClicks("AnyUp")
    local closeBg = closeBtn:CreateTexture(nil, "BACKGROUND", nil, -7)
    closeBg:SetAllPoints()
    closeBg:SetColorTexture(ar, ag, ab, 1)
    closeBg:Hide()
    local closeTxt = closeBtn:CreateFontString(nil, "OVERLAY")
    closeTxt:SetFont(theme:GetFont("BUTTON"), 14, "")
    closeTxt:SetPoint("CENTER", 0, 0)
    closeTxt:SetText("X")
    closeTxt:SetTextColor(ar, ag, ab, 1)
    closeBtn:SetScript("OnEnter", function()
        closeBg:Show()
        closeTxt:SetTextColor(0, 0, 0, 1)
    end)
    closeBtn:SetScript("OnLeave", function()
        closeBg:Hide()
        closeTxt:SetTextColor(ar, ag, ab, 1)
    end)
    closeBtn:SetScript("OnClick", function() Editor.Close() end)

    -- Region frames
    local topLeft = CreateFrame("Frame", nil, frame)
    topLeft:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -TITLE_H)
    topLeft:SetSize(TOP_LEFT_W, TOP_H)
    widgets.topLeft = topLeft

    -- Selector block host: fixed width, centered horizontally and pinned to
    -- the top of the quadrant. The builder's Finalize() sets its height, so
    -- the progressive reveal (and per-kind extra fields) grows downward.
    local selectorsHost = CreateFrame("Frame", nil, topLeft)
    selectorsHost:SetSize(640, 100)
    selectorsHost:SetPoint("TOP", topLeft, "TOP", 0, -SELECTORS_TOP_GAP)
    widgets.selectorsHost = selectorsHost

    local topRight = CreateFrame("Frame", nil, frame)
    topRight:SetPoint("TOPLEFT", frame, "TOPLEFT", TOP_LEFT_W + PAD * 2 + 1, -TITLE_H)
    topRight:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -TITLE_H)
    topRight:SetHeight(TOP_H)
    widgets.topRight = topRight

    -- Static quadrant label; the preview row itself carries no label
    local previewLabel = topRight:CreateFontString(nil, "OVERLAY")
    previewLabel:SetFont(theme:GetFont("LABEL"), 13, "")
    previewLabel:SetPoint("TOPLEFT", topRight, "TOPLEFT", 10, -10)
    previewLabel:SetText("Preview:")
    previewLabel:SetTextColor(ar, ag, ab, 1)
    widgets.previewLabel = previewLabel

    -- Preview builder host: Finalize() resizes this frame, not the quadrant,
    -- so the quadrant keeps its full rect.
    local previewHost = CreateFrame("Frame", nil, topRight)
    previewHost:SetPoint("TOPLEFT", topRight, "TOPLEFT", 0, -32)
    previewHost:SetPoint("TOPRIGHT", topRight, "TOPRIGHT", 0, -32)
    previewHost:SetHeight(100)
    widgets.previewHost = previewHost

    local bottomLeft = CreateFrame("Frame", nil, frame)
    bottomLeft:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(TITLE_H + TOP_H + 1))
    bottomLeft:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, PAD)
    bottomLeft:SetWidth(BOTTOM_LEFT_W)
    widgets.bottomLeft = bottomLeft

    local bottomRight = CreateFrame("Frame", nil, frame)
    bottomRight:SetPoint("TOPLEFT", frame, "TOPLEFT", BOTTOM_LEFT_W + PAD * 2 + 1, -(TITLE_H + TOP_H + 1))
    bottomRight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD)
    widgets.bottomRight = bottomRight

    -- Separators (all but the title underline hide while a draft is undecided)
    local sepH = CreateSeparator(frame)
    sepH:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(TITLE_H + TOP_H))
    sepH:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(TITLE_H + TOP_H))
    sepH:SetHeight(1)
    widgets.sepH = sepH

    local sepTop = CreateSeparator(frame)
    sepTop:SetPoint("TOPLEFT", frame, "TOPLEFT", TOP_LEFT_W + PAD + 4, -(TITLE_H + 4))
    sepTop:SetWidth(1)
    sepTop:SetHeight(TOP_H - 8)
    widgets.sepTop = sepTop

    local sepBottom = CreateSeparator(frame)
    sepBottom:SetPoint("TOPLEFT", frame, "TOPLEFT", BOTTOM_LEFT_W + PAD + 4, -(TITLE_H + TOP_H + 5))
    sepBottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", BOTTOM_LEFT_W + PAD + 4, PAD + 4)
    sepBottom:SetWidth(1)
    widgets.sepBottom = sepBottom

    local sepTitle = CreateSeparator(frame)
    sepTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -TITLE_H + 2)
    sepTitle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -TITLE_H + 2)
    sepTitle:SetHeight(1)

    -- Spell region statics in the bottom-left quadrant (built once; an
    -- EditBox must survive re-renders)
    local spellExplainer = bottomLeft:CreateFontString(nil, "OVERLAY")
    spellExplainer:SetFont(theme:GetFont("LABEL"), 12, "")
    spellExplainer:SetPoint("TOPLEFT", bottomLeft, "TOPLEFT", 8, -20)
    spellExplainer:SetText("Select a Spell to track from the CDM list below, or enter its ID:")
    local dimR, dimG, dimB = theme:GetDimTextColor()
    spellExplainer:SetTextColor(dimR, dimG, dimB, 1)

    local spellBox = addon.UI.Controls:CreateSingleLineEditBox({
        parent = bottomLeft,
        width = 90,
        fontSize = 12,
        maxLetters = 7,
        numeric = true,
        justifyH = "CENTER",
    })
    spellBox:SetPoint("LEFT", spellExplainer, "RIGHT", 8, 0)
    spellBox:SetOnChange(function(text)
        if not session or text == "" then return end
        local tracker = CurrentTracker()
        local current = (session.validated and session.validated.spellId)
            or (tracker and tracker.spellId)
        if tonumber(text) == current then return end
        ValidateSpell(text)
    end)
    widgets.spellBox = spellBox

    -- Chip on its own line beneath the explainer + ID box, centered as a
    -- pair; the vertical space is reserved statically (blank until a spell is
    -- chosen). The icon's anchor is recomputed from the measured name width.
    local chipIcon = bottomLeft:CreateTexture(nil, "ARTWORK")
    chipIcon:SetSize(28, 28)
    chipIcon:SetPoint("TOPLEFT", bottomLeft, "TOP", -14, -46)
    chipIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    chipIcon:Hide()
    widgets.chipIcon = chipIcon

    local chipName = bottomLeft:CreateFontString(nil, "OVERLAY")
    chipName:SetFont(theme:GetFont("LABEL"), 15, "")
    chipName:SetPoint("LEFT", chipIcon, "RIGHT", 6, 0)
    chipName:SetJustifyH("LEFT")
    chipName:SetTextColor(0.9, 0.9, 0.9, 1)
    chipName:Hide()
    widgets.chipName = chipName

    local statusText = bottomLeft:CreateFontString(nil, "OVERLAY")
    statusText:SetFont(theme:GetFont("LABEL"), 11, "")
    statusText:SetPoint("TOPLEFT", bottomLeft, "TOPLEFT", 8, -80)
    statusText:SetPoint("TOPRIGHT", bottomLeft, "TOPRIGHT", -8, -80)
    statusText:SetJustifyH("LEFT")
    statusText:SetTextColor(1, 0.82, 0, 1)
    widgets.statusText = statusText

    -- CDM catalog fills the rest of the spell region
    local catalogHost = CreateFrame("Frame", nil, bottomLeft)
    catalogHost:SetPoint("TOPLEFT", bottomLeft, "TOPLEFT", 4, -98)
    catalogHost:SetPoint("BOTTOMRIGHT", bottomLeft, "BOTTOMRIGHT", -4, 4)
    cdmPicker = addon.UI.ScootAuraCDMPicker.Attach(catalogHost, {
        onPick = function(spellId)
            spellBox:SetText(tostring(spellId))
            ValidateSpell(spellId)
        end,
    })

    -- Tabs region scroll (bottom-right quadrant)
    local tabsScroll, tabsChild = addon.UI.ScootAuraCDMPicker.CreateScrollRegion(bottomRight)
    tabsScroll:SetPoint("TOPLEFT", bottomRight, "TOPLEFT", 0, -4)
    tabsScroll:SetPoint("BOTTOMRIGHT", bottomRight, "BOTTOMRIGHT", 0, 0)
    widgets.tabsScroll = tabsScroll
    widgets.tabsChild = tabsChild

    -- ESC closes (combat-safe attach)
    addon.EscapeKey.Attach(frame, function() Editor.Close() end)
end

--------------------------------------------------------------------------------
-- Dynamic regions
--------------------------------------------------------------------------------

local KIND_LABELS = { buff = "a Buff", debuff = "a Debuff", missingbuff = "a Missing Buff" }
local KIND_ORDER = { "buff", "debuff", "missingbuff" }
local UNIT_LABELS = {
    player = "Myself", group = "My Group", target = "My Target", focus = "My Focus",
}
-- Units listed for a kind but not yet offered: shown dimmed and inert.
local COMING_SOON_UNITS = {}
-- "Horizontal Bar" leaves room in the same selector for vertical bars and
-- circles later; the internal shape key stays "bar".
local SHAPE_LABELS = { icon = "an Icon", bar = "a Horizontal Bar", shape = "a Shape" }
local SHAPE_ORDER = { "icon", "bar", "shape" }
-- A missing-buff tracker is a reminder: icon, text, or both.
local MISSING_SHAPE_LABELS = { icon = "an Icon", text = "Text", icontext = "an Icon & Text" }
local MISSING_SHAPE_ORDER = { "icon", "text", "icontext" }
local ONLY_IN_COMBAT_LABELS = { yes = "Yes", no = "No" }
local ONLY_IN_COMBAT_ORDER = { "yes", "no" }

local function ContentValue(field)
    local tracker = CurrentTracker()
    if tracker then return tracker[field] end
    -- Raw read: a draft's `false` (Only in Combat = No) must survive.
    if session and session.draft then return session.draft.content[field] end
    return nil
end

local function SetContent(field, value)
    if not session then return end
    if session.trackerId then
        SAU().SetTrackerContent(session.trackerId, { [field] = value })
        RefreshList()
    else
        local c = session.draft.content
        c[field] = value
        -- A raid buff goes up between pulls, so a reminder that only shows in
        -- combat would arrive after the moment to act on it. Myself keeps the
        -- Yes default; an explicit choice already made is left alone.
        if field == "unit" and value == "group" and c.onlyInCombat == nil then
            c.onlyInCombat = false
        end
        -- A kind flip can strand the chosen unit or shape; force a re-choose.
        if field == "kind" then
            local units = SAU().VALID_UNITS[value]
            if c.unit and not (units and units[c.unit]) then
                c.unit = nil
            end
            local shapes = SAU().VALID_SHAPES_BY_KIND[value]
            if c.shape and not (shapes and shapes[c.shape]) then
                c.shape = nil
            end
        end
        TryMaterialize()
    end
    Editor.DeferredRefresh()
end

local function UnitOptions(kind)
    local values, order, disabled = {}, {}, nil
    for _, unit in ipairs({ "player", "group", "target", "focus" }) do
        if SAU().VALID_UNITS[kind] and SAU().VALID_UNITS[kind][unit] then
            values[unit] = UNIT_LABELS[unit]
            table.insert(order, unit)
        end
    end
    for _, entry in ipairs(COMING_SOON_UNITS[kind] or {}) do
        values[entry.key] = entry.label
        table.insert(order, entry.key)
        disabled = disabled or {}
        disabled[entry.key] = true
    end
    return values, order, disabled
end

local function ShapeOptions(kind)
    if kind == "missingbuff" then
        return MISSING_SHAPE_LABELS, MISSING_SHAPE_ORDER
    end
    return SHAPE_LABELS, SHAPE_ORDER
end

-- One selector with an unset state: draft selectors start on "Choose".
-- opts.disabledOptions lists keys that are shown but inert.
local function AddChoiceSelector(builder, label, valueMap, order, current, onSet, opts)
    local values = {}
    for k, v in pairs(valueMap) do values[k] = v end
    local fullOrder = {}
    if not current then
        values.choose = "Choose..."
        table.insert(fullOrder, "choose")
    end
    for _, k in ipairs(order) do table.insert(fullOrder, k) end

    builder:AddSelector({
        label = label,
        labelAlign = "field",
        noBottomBorder = true,
        width = 340,
        sizeScale = 1.3,
        values = values,
        order = fullOrder,
        disabledOptions = opts and opts.disabledOptions or nil,
        get = function() return current or "choose" end,
        set = function(v)
            if v ~= "choose" then onSet(v) end
        end,
    })
end

local function RenderSelectors()
    if selBuilder then selBuilder:Cleanup() end
    local SettingsBuilder = addon.UI.SettingsBuilder
    selBuilder = SettingsBuilder:CreateFor(widgets.selectorsHost)

    local kind = ContentValue("kind")
    local unit = ContentValue("unit")
    local shape = ContentValue("shape")

    AddChoiceSelector(selBuilder, "I want to track...",
        KIND_LABELS, KIND_ORDER, kind,
        function(v) SetContent("kind", v) end)

    if kind then
        local uValues, uOrder, uDisabled = UnitOptions(kind)
        AddChoiceSelector(selBuilder, "On...", uValues, uOrder, unit,
            function(v) SetContent("unit", v) end,
            { disabledOptions = uDisabled })
    end

    if kind and unit then
        local sValues, sOrder = ShapeOptions(kind)
        AddChoiceSelector(selBuilder, "Shown as...",
            sValues, sOrder, shape,
            function(v) SetContent("shape", v) end)
    end

    -- Per-kind extras. Missing-buff: whether the reminder may show out of
    -- combat. Defaults to Yes, so it never sits on "Choose".
    if kind == "missingbuff" and unit and shape then
        local onlyInCombat = ContentValue("onlyInCombat")
        local current = (onlyInCombat == false) and "no" or "yes"
        AddChoiceSelector(selBuilder, "Only in Combat?",
            ONLY_IN_COMBAT_LABELS, ONLY_IN_COMBAT_ORDER, current,
            function(v) SetContent("onlyInCombat", v == "yes") end)
    end

    selBuilder:Finalize()
end

local function RenderTabs()
    if tabsBuilder then tabsBuilder:Cleanup() end
    local SettingsBuilder = addon.UI.SettingsBuilder
    local child = widgets.tabsChild
    local w = widgets.tabsScroll:GetWidth()
    child:SetWidth((w and w > 0) and w or (WINDOW_W - BOTTOM_LEFT_W - PAD * 3 - 1))

    tabsBuilder = SettingsBuilder:CreateFor(child)
    tabsBuilder:SetOnRefresh(function() Editor.DeferredRefresh() end)

    local Tabs = addon.UI.Settings.ScootAuraEditorTabs
    local tabs, buildContent = Tabs.BuildTabSet(ctx)
    tabsBuilder:AddTabbedSection({
        tabs = tabs,
        componentId = "scootAuraEditor",
        sectionKey = "editorTabs",
        maxTabsPerRow = 7,
        buildContent = buildContent,
    })
    tabsBuilder:Finalize()
    if widgets.tabsScroll.UpdateThumb then widgets.tabsScroll.UpdateThumb() end
end

local function RenderPreview()
    if prevBuilder then prevBuilder:Cleanup() end
    local SettingsBuilder = addon.UI.SettingsBuilder

    -- No preview until a spell is chosen: without one there is nothing real
    -- to show, and the engine's fallback is the player's spec icon.
    local tracker = CurrentTracker()
    if not ((session and session.validated) or tracker) then
        return
    end

    prevBuilder = SettingsBuilder:CreateFor(widgets.previewHost)

    local shape = ctx.shape()
    local mode, shapeAtlas, shapeColor, shapeDrain
    if shape == "bar" then
        mode = ctx.get("barShowIcon") and "iconbar" or "bar"
    elseif shape == "shape" then
        mode = "icon"
        shapeAtlas = SAU()._AtlasFromShapeKey(ctx.get("shapeStyle") or "border:SquareMask") or "SquareMask"
        shapeDrain = ctx.get("shapeShowDrain") ~= false
        if (ctx.get("shapeColorMode") or "class") == "class" then
            local cc = RAID_CLASS_COLORS[SAU()._playerClassToken]
            shapeColor = cc and { cc.r, cc.g, cc.b, 1 } or { 1, 1, 1, 1 }
        else
            shapeColor = ctx.get("shapeTint") or { 1, 1, 1, 1 }
        end
    else
        mode = "icon"
    end

    local iconTexture
    if session and session.validated then
        iconTexture = session.validated.icon
    elseif tracker then
        iconTexture = PlainSpellTexture(tracker.spellId)
    end

    if ctx.kind() == "missingbuff" then
        -- The reminder as it looks while the buff is missing: the spell icon
        -- and/or the aura name, laid out around each other by the Aura Name
        -- tab's keys. The generic preview speaks in duration-text keys, so map
        -- them onto nameText* and pin the position outside the icon.
        local spellId = (session and session.validated and session.validated.spellId)
            or (tracker and tracker.spellId)
        local nameText = spellId and SAU().DescribeSpell(spellId) or CurrentName()
        if ctx.get("missingSuffix") == true then
            nameText = nameText .. " missing!"
        end
        local showText = (shape ~= "icon")
        local keys = { _showCAText = showText or nil }
        if showText then
            keys.textFont = "nameTextFont"
            keys.textStyle = "nameTextStyle"
            keys.textSize = "nameTextSize"
            keys.textColor = "nameTextColor"
            keys.textOuterAnchor = "nameTextOuterAnchor"
            keys.textOffsetX = "nameTextOffsetX"
            keys.textOffsetY = "nameTextOffsetY"
            keys.textPosition = "__missingTextPosition"
            keys.hideText = "__missingHideText"
        end
        prevBuilder:AddPreview({
            componentId = session and session.trackerId
                and SAU().GetComponentId(session.trackerId) or "scootAuraDraft",
            mode = (shape == "text") and "text" or "icon",
            iconTexture = iconTexture,
            settingKeys = keys,
            caTextSource = "duration",
            caTextLiteral = showText and nameText or nil,
            rowHeight = 200,
            previewScale = 1,
            maxRowHeight = 340,
            getSetting = function(key)
                if key == "__missingTextPosition" then return "outside" end
                if key == "__missingHideText" then return false end
                return ctx.get(key)
            end,
            noBottomBorder = true,
            noHover = true,
            noLabel = true,
        })
        prevBuilder:Finalize()
        return
    end

    prevBuilder:AddPreview({
        componentId = session and session.trackerId
            and SAU().GetComponentId(session.trackerId) or "scootAuraDraft",
        mode = mode,
        iconTexture = iconTexture,
        settingKeys = { _showCAText = true },
        caTextSource = "duration",
        previewNameLabel = CurrentName(),
        rowHeight = 200,
        previewScale = 1,
        maxRowHeight = 340,
        getSetting = ctx.get,
        shapeAtlas = shapeAtlas,
        shapeColor = shapeColor,
        shapeDrain = shapeDrain,
        noBottomBorder = true,
        noHover = true,
        noLabel = true,
        timerEpoch = session and session.timerEpoch,
    })

    prevBuilder:Finalize()
end

-- Centers the icon + name pair on the chip line. The name has no right
-- anchor, so it is measured and clamped instead of clipped.
local function PositionChip()
    local iconSize, gap, pad = 28, 6, 16
    local maxW = (widgets.bottomLeft:GetWidth() or BOTTOM_LEFT_W) - pad * 2
    local nameW = widgets.chipName:GetStringWidth() or 0
    local maxNameW = maxW - iconSize - gap
    if nameW > maxNameW then
        widgets.chipName:SetWidth(maxNameW)
        nameW = maxNameW
    else
        widgets.chipName:SetWidth(0)
    end
    local pairW = iconSize + gap + nameW
    widgets.chipIcon:ClearAllPoints()
    widgets.chipIcon:SetPoint("TOPLEFT", widgets.bottomLeft, "TOP", -pairW / 2, -46)
end

local function UpdateSpellRegion()
    if not session then return end
    local tracker = CurrentTracker()

    if not widgets.spellBox:HasFocus() then
        local shownId
        if session.validated then
            shownId = session.validated.spellId
        elseif tracker then
            shownId = tracker.spellId
        end
        widgets.spellBox:SetText(shownId and tostring(shownId) or "")
    end

    local chipSpellId, chipLabel
    if session.validated then
        chipSpellId = session.validated.spellId
        chipLabel = session.validated.name
    elseif tracker then
        chipSpellId = tracker.spellId
        chipLabel = SAU()._PlainSpellName(tracker.spellId)
    end
    if chipSpellId then
        widgets.chipIcon:SetTexture(PlainSpellTexture(chipSpellId))
        widgets.chipName:SetText(chipLabel or "")
        PositionChip()
        widgets.chipIcon:Show()
        widgets.chipName:Show()
        -- Re-center once rendered: the string width can read short before the
        -- font file loads (same deferred-measure caveat as the tab strip).
        C_Timer.After(0, function()
            if widgets.chipName:IsShown() then PositionChip() end
        end)
    else
        widgets.chipIcon:Hide()
        widgets.chipName:Hide()
    end

    local status = session.statusOverride
    if not status then
        if tracker then
            local Engine = SAU().Engine
            if Engine and not Engine.IsWired(session.trackerId) and Engine.HasPendingWork() then
                status = "Tracking applies when combat or instance restrictions end."
            else
                status = ""
            end
        else
            -- The static explainer beside the ID box carries the hint; this
            -- line is reserved for errors, progress, and the queued notice.
            status = ""
        end
    end
    widgets.statusText:SetText(status)
end

-- A draft has nothing to rename or copy yet: static title, no icons. They
-- appear with the tracker, and the duplicate one only for a tracker in a group.
-- Never touched while the rename box is open (a deferred refresh mid-rename
-- must not re-show an icon over it). A tracker in a group of two or more gets
-- the member carousel instead of the plain title; the icons wait until the
-- strip is at rest.
local function UpdateTitle()
    if widgets.renameBox:IsShown() then return end
    local tracker = CurrentTracker()
    local gid = tracker and tracker.groupId
    widgets.inGroup = gid ~= nil
    if gid and widgets.carousel:SetContext(gid, session.trackerId) then
        widgets.carouselActive = true
        widgets.titleText:Hide()
        widgets.carousel:Show()
        widgets.AnchorTitleIcons()
        widgets.SetTitleIconsShown(widgets.carousel:IsSettled())
        return
    end
    widgets.carouselActive = false
    widgets.carousel:Hide()
    widgets.titleText:Show()
    widgets.AnchorTitleIcons()
    if tracker then
        widgets.titleText:SetText(CurrentName())
        widgets.SetTitleIconsShown(true)
    else
        widgets.titleText:SetText("Creating a new Aura Tracker")
        widgets.SetTitleIconsShown(false)
    end
end

-- The three content choices gate the other quadrants: an undecided draft
-- shows only the selectors, so a first-time user has one thing to look at.
local needCatalogRefresh = false
local catalogKind          -- kind the catalog was last built for

local function ContentReady()
    if CurrentTracker() then return true end
    local c = session and session.draft and session.draft.content
    return (c and c.kind and c.unit and c.shape) and true or false
end

local function SetQuadrantsShown(shown)
    local regions = {
        widgets.topRight, widgets.bottomLeft, widgets.bottomRight,
        widgets.sepH, widgets.sepTop, widgets.sepBottom,
    }
    for _, region in ipairs(regions) do
        if shown then region:Show() else region:Hide() end
    end
end

local function RenderDynamic()
    if not frame or not frame:IsShown() then return end
    RenderSelectors()
    UpdateTitle()

    if not ContentReady() then
        SetQuadrantsShown(false)
        return
    end
    if not widgets.topRight:IsShown() then
        SetQuadrantsShown(true)
        needCatalogRefresh = true
    end
    -- The catalog carries extra cells for some kinds (missing-buff: class
    -- buff and forms), so a kind change rebuilds it.
    local kind = ctx.kind()
    if needCatalogRefresh or kind ~= catalogKind then
        needCatalogRefresh = false
        catalogKind = kind
        if cdmPicker then cdmPicker.Refresh(kind) end
    end
    RenderTabs()
    RenderPreview()
    UpdateSpellRegion()
end

function Editor.DeferredRefresh()
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(0, function()
        refreshPending = false
        RenderDynamic()
    end)
end

-- Preview-only variant for value edits. A pending full refresh covers it.
local previewRefreshPending = false
function Editor.DeferredPreviewRefresh()
    if previewRefreshPending or refreshPending then return end
    previewRefreshPending = true
    C_Timer.After(0, function()
        previewRefreshPending = false
        if frame and frame:IsShown() and widgets.topRight:IsShown() then
            RenderPreview()
        end
    end)
end

--------------------------------------------------------------------------------
-- Open / close
--------------------------------------------------------------------------------

--- Opens the editor for an existing tracker (id) or a fresh draft (nil).
function Editor.Open(trackerId)
    if not (addon.ScootAuras and addon.ScootAuras.IsModuleActive()) then return end
    InitializeFrame()

    if trackerId and SAU().GetTracker(trackerId) then
        session = { trackerId = trackerId }
    else
        session = { draft = { content = {}, styling = {} } }
    end
    -- Countdown anchor for the preview: rebuilds resume the running cycle;
    -- only opening the editor or validating a different spell restarts it.
    session.timerEpoch = {}
    validationToken = validationToken + 1

    -- Show first: region rects resolve on show, and the catalog grid and tab
    -- scroll child size themselves from measured widths. RenderDynamic runs
    -- the catalog refresh once the quadrants are visible.
    frame:Show()
    needCatalogRefresh = true
    RenderDynamic()
end

function Editor.Close()
    if frame then frame:Hide() end
    if widgets.carousel then widgets.carousel:Reset() end
    session = nil
    validationToken = validationToken + 1
end

function Editor.IsOpen()
    return frame ~= nil and frame:IsShown()
end

-- Public entry points (the settings panel closes the editor from its OnHide)
function addon.ShowScootAuraEditor(trackerId)
    Editor.Open(trackerId)
end

function addon.CloseScootAuraEditor()
    Editor.Close()
end

return Editor
