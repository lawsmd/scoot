-- EditorWindow.lua - The pop-up ScootAura editor
--
-- Stateless: no save button, edits apply instantly, X or ESC closes. A new
-- tracker starts as a session-local draft; it materializes the moment the
-- three content choices are made AND a spell ID validates. Closing before
-- that discards the draft and leaves saved variables untouched.
--
-- Strata: DIALOG level 210. Above the settings window (DIALOG 100), below
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
-- Light plate behind the preview, inset from the top-right quadrant; the top
-- inset clears the "Preview:" label.
local PREVIEW_BACKDROP_COLOR = { 0.48, 0.48, 0.48, 0.55 }
local PREVIEW_BACKDROP_INSET = 8
local PREVIEW_BACKDROP_TOP = 30
local PREVIEW_BACKDROP_RADIUS = 12
local TITLE_ICON = 16      -- rename, duplicate, load on, delete
-- Icon to icon, and the underline's break past each end of the row. Even, so
-- the row's half width is a whole pixel.
local TITLE_ICON_GAP = 8
-- Icon names: the flat glyphs the Aura List uses for the same actions. The
-- delete art falls back to the gold X where the client has no lone trash can.
local SPEC_ATLAS = "ui-questtrackerbutton-filter"
local DELETE_ATLAS = { "common-icon-delete", "common-icon-yellowx" }

local frame
local session
local widgets = {}   -- static widgets built once at init

-- Per-region builders, replaced wholesale on every dynamic render
local selBuilder, tabsBuilder
-- The preview quadrant: the open tracker's group as a strip (PreviewStrip.lua)
local previewStrip
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
    if v == nil then
        -- A draft reads the starting values its kind and shape stamp at
        -- materialization (core.lua), so controls and preview agree pre-
        -- and post-.
        for _, stamp in ipairs(SAU().StartingValueStamps(ctx.kind(), ctx.shape())) do
            if stamp[key] ~= nil then
                v = stamp[key]
                break
            end
        end
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

-- Resolved token ("none" when unset); the Icon tab reads it to keep the icon
-- controls editable while a bar-icon missing visual consumes them.
function ctx.missingVisual()
    local tracker = CurrentTracker()
    if tracker then return SAU().MissingVisualFor(tracker) end
    local c = session and session.draft.content
    if not (c and c.kind and c.shape) then return "none" end
    return SAU().CoerceMissingVisual(c.kind, c.shape, c.missingVisual) or "none"
end

-- The "Show it..." rule on the Spell Cooldown kind, "always" when unset.
function ctx.showWhen()
    local tracker = CurrentTracker()
    if tracker then return SAU().ShowWhenFor(tracker) end
    local c = session and session.draft.content
    return (c and SAU().CoerceShowWhen(c.kind, c.showWhen)) or "always"
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

-- The title row's spec fly-out edits the tracker it opened on, so it closes
-- when the editor closes or moves to another tracker.
local function CloseEditorSpecFlyout()
    local SpecFlyout = addon.UI.ScootAuraSpecFlyout
    if SpecFlyout and SpecFlyout.IsDetached() then SpecFlyout.Close() end
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
    if not (c.kind and c.unit and c.shape) then return end
    -- A kind with no spell (Class Power) materializes on the three choices
    -- alone; every other kind waits for a validated spell.
    local needsSpell = SAU().KindNeedsSpell(c.kind)
    if needsSpell and not session.validated then return end

    local id, err = SAU().CreateTracker({
        spellId = needsSpell and session.validated.spellId or nil,
        kind = c.kind,
        unit = c.unit,
        shape = c.shape,
        name = c.name,
        onlyInCombat = c.onlyInCombat,
        onlyInInstances = c.onlyInInstances,
        missingVisual = c.missingVisual,
        showWhen = c.showWhen,
        maxStacks = c.maxStacks,
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
        ApplyValidatedSpell()
        Editor.DeferredRefresh()
    end)
end

--------------------------------------------------------------------------------
-- Window construction (once)
--------------------------------------------------------------------------------

-- The position is saved through the tracker core, which knows where each
-- host keeps it.
local function SavePosition()
    local SAU = addon.ScootAuras
    if not (frame and SAU and SAU.SetEditorPosition) then return end
    local point, _, relPoint, x, y = frame:GetPoint()
    SAU.SetEditorPosition({ point = point, relPoint = relPoint, x = x, y = y })
end

local function RestorePosition()
    frame:ClearAllPoints()
    local SAU = addon.ScootAuras
    local pos = SAU and SAU.GetEditorPosition and SAU.GetEditorPosition()
    if pos and pos.point and pos.x and pos.y then
        frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    end
end

local function CreateSeparator(parent)
    local tex = parent:CreateTexture(nil, "BORDER", nil, 1)
    -- The shared accent registry paints it now and repaints it later, so the
    -- four separators need no entry in the window's own repaint below.
    addon.UI.Controls.RegisterThemedFill(tex, 0.25)
    return tex
end

-- A rounded rect with a fixed corner radius: a full-height center column, a
-- strip down each side between the corners, and a quarter of a white circle
-- in each corner. No piece overlaps another, so a translucent color stays even.
local CIRCLE_TEXTURE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local PLATE_CORNERS = {
    { "TOPLEFT", 0, 0.5, 0, 0.5 },
    { "TOPRIGHT", 0.5, 1, 0, 0.5 },
    { "BOTTOMLEFT", 0, 0.5, 0.5, 1 },
    { "BOTTOMRIGHT", 0.5, 1, 0.5, 1 },
}

local function CreateRoundedPlate(owner, rect, radius, color)
    local r, g, b, a = color[1], color[2], color[3], color[4]

    local center = owner:CreateTexture(nil, "BACKGROUND")
    center:SetPoint("TOPLEFT", rect, "TOPLEFT", radius, 0)
    center:SetPoint("BOTTOMRIGHT", rect, "BOTTOMRIGHT", -radius, 0)
    center:SetColorTexture(r, g, b, a)

    local left = owner:CreateTexture(nil, "BACKGROUND")
    left:SetPoint("TOPLEFT", rect, "TOPLEFT", 0, -radius)
    left:SetPoint("BOTTOMRIGHT", rect, "BOTTOMLEFT", radius, radius)
    left:SetColorTexture(r, g, b, a)

    local right = owner:CreateTexture(nil, "BACKGROUND")
    right:SetPoint("TOPRIGHT", rect, "TOPRIGHT", 0, -radius)
    right:SetPoint("BOTTOMLEFT", rect, "BOTTOMRIGHT", -radius, radius)
    right:SetColorTexture(r, g, b, a)

    for _, c in ipairs(PLATE_CORNERS) do
        local corner = owner:CreateTexture(nil, "BACKGROUND")
        corner:SetSize(radius, radius)
        corner:SetPoint(c[1], rect, c[1], 0, 0)
        corner:SetTexture(CIRCLE_TEXTURE)
        corner:SetTexCoord(c[2], c[3], c[4], c[5])
        corner:SetVertexColor(r, g, b, a)
    end
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

    -- Modal dim behind the editor, dialog-style: the dim darkens and
    -- mouse-blocks everything below, the editor floats ten levels above it,
    -- both in the DIALOG strata under the fly-outs, the popup lists, the
    -- pickers and the modal dialog on FULLSCREEN_DIALOG. The settings panel
    -- is DIALOG 100 and its widgets climb from there (the shared button
    -- control adds 15, info icons another 10); a skin that draws the panel
    -- on a Blizzard template puts its border and title plate on child
    -- frames five hundred levels up, with the toolbar standing on the
    -- border. The panel's overlay level is the step over whichever art the
    -- skin drew, so the dim clears the whole tree from there: 200 on the
    -- flat panel, past 690 on the template.
    local panel = addon.UI.SettingsPanel
    local panelFrame = panel and panel.frame
    local overlay = panelFrame and panelFrame.GetOverlayLevel and panelFrame:GetOverlayLevel() or 110
    local dimLevel = overlay + 90
    local dim = CreateFrame("Frame", addon.Brand .. "AuraEditorDim", UIParent)
    dim:SetFrameStrata("DIALOG")
    dim:SetFrameLevel(dimLevel)
    dim:SetAllPoints(UIParent)
    dim:EnableMouse(true)
    dim:Hide()
    local dimTex = dim:CreateTexture(nil, "BACKGROUND")
    dimTex:SetAllPoints()
    dimTex:SetColorTexture(0, 0, 0, 0.80)
    -- The wash is the modal dialog's piece, so a skin tunes both at once.
    addon.UI.Chrome.ApplyOpacity("dialogDimmer", dimTex)
    widgets.dim = dim

    -- The surface is the subWindow role: the panel's own flat window on a
    -- skin that draws windows flat, and the skin's panel template at the
    -- editor's size where it has one, the title on the plate and the close
    -- button in the template's corner.
    frame = Window:Create(addon.Brand .. "AuraEditorFrame", UIParent, WINDOW_W, WINDOW_H,
        { role = "subWindow", template = true })
    frame:SetFrameLevel(dimLevel + 10)
    local onTemplate = frame._chromeSpec ~= nil and frame._chromeSpec.kind == "template"
    frame:HookScript("OnShow", function() dim:Show() end)
    frame:HookScript("OnHide", function() dim:Hide() end)
    frame:Hide()
    RestorePosition()

    -- Title bar: drag surface + name + rename + close. On a template the
    -- bar is the title plate's own band, so the name, the carousel and the
    -- rename box land on the plate, and it sits a level over the border
    -- art the template draws on a child frame of its own; the template's
    -- close button keeps its corner above it.
    local titleBar = CreateFrame("Frame", nil, frame)
    if onTemplate and frame.TitleContainer then
        titleBar:SetPoint("TOPLEFT", frame.TitleContainer, "TOPLEFT", 0, 0)
        titleBar:SetPoint("BOTTOMRIGHT", frame.TitleContainer, "BOTTOMRIGHT", 0, 0)
        titleBar:SetFrameLevel(frame:GetOverlayLevel())
    else
        titleBar:SetHeight(TITLE_H)
        titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    end
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

    -- Title underline, in two pieces so it breaks around the icon row
    -- (SetTitleIconsShown sets the inner ends). A template's plate and the
    -- streak band under it already part the title from the quadrants.
    local lineY = -TITLE_H + 2
    local sepTitleL = CreateSeparator(frame)
    sepTitleL:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, lineY)
    sepTitleL:SetHeight(1)
    local sepTitleR = CreateSeparator(frame)
    sepTitleR:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, lineY)
    sepTitleR:SetHeight(1)
    if onTemplate then
        sepTitleL:Hide()
        sepTitleR:Hide()
    end

    -- Title icons: rename, duplicate (a tracker in a group only), load on,
    -- and delete, in one row centered under the name and set into the
    -- underline. Drafts hide them. Leveled above the carousel viewport (+2)
    -- and its name buttons (+3).
    -- glyphScale draws the art larger than its button, for an atlas with
    -- more empty margin than its neighbors; the row spacing stays even.
    local function TitleIcon(atlas, tooltip, glyphScale)
        local btn = CreateFrame("Button", nil, titleBar)
        btn:SetSize(TITLE_ICON, TITLE_ICON)
        btn:SetFrameLevel(titleBar:GetFrameLevel() + 6)
        local tex = btn:CreateTexture(nil, "ARTWORK")
        local glyph = TITLE_ICON * (glyphScale or 1)
        tex:SetSize(glyph, glyph)
        tex:SetPoint("CENTER", btn, "CENTER", 0, 0)
        for _, name in ipairs(type(atlas) == "table" and atlas or { atlas }) do
            if pcall(tex.SetAtlas, tex, name) and tex:GetAtlas() then break end
        end
        tex:SetDesaturated(true)
        tex:SetVertexColor(ar, ag, ab)
        tex:SetAlpha(0.35)
        btn._tex = tex
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

    local renameBtn = TitleIcon("Pencil-Icon", "Rename", 1.25)
    local duplicateBtn = TitleIcon("friends-icon-battlenet-copy", "Duplicate into this group")
    local specBtn = TitleIcon(SPEC_ATLAS, "Load on...")
    local deleteBtn = TitleIcon(DELETE_ATLAS, "Delete")
    local titleIcons = { renameBtn, duplicateBtn, specBtn, deleteBtn }

    -- The row's center sits on the underline. The name above it is centered
    -- in the bar, plain or in the carousel, so the row needs no re-anchor
    -- when the carousel moves.
    local iconRow = CreateFrame("Frame", nil, titleBar)
    iconRow:SetSize(1, TITLE_ICON)
    iconRow:SetPoint("CENTER", titleBar, "BOTTOM", 0, 2)

    -- Duplicating is a group action, so that icon also needs widgets.inGroup.
    -- The row packs whichever icons show, and the underline breaks around it.
    local function SetTitleIconsShown(shown)
        local visible = {}
        for _, btn in ipairs(titleIcons) do
            local on = shown and (btn ~= duplicateBtn or widgets.inGroup)
            btn:SetShown(not not on)
            if on then visible[#visible + 1] = btn end
        end
        local rowW = #visible * (TITLE_ICON + TITLE_ICON_GAP) - TITLE_ICON_GAP
        for i, btn in ipairs(visible) do
            btn:ClearAllPoints()
            btn:SetPoint("LEFT", iconRow, "CENTER", -rowW / 2 + (i - 1) * (TITLE_ICON + TITLE_ICON_GAP), 0)
        end
        local half = #visible > 0 and (rowW / 2 + TITLE_ICON_GAP) or 0
        sepTitleL:SetPoint("TOPRIGHT", frame, "TOP", -half, lineY)
        sepTitleR:SetPoint("TOPLEFT", frame, "TOP", half, lineY)
    end
    widgets.SetTitleIconsShown = SetTitleIconsShown

    -- The spec fly-out hangs from the editor rather than a list row, so it
    -- carries no reanchor key and the Aura List's re-render leaves it open.
    specBtn:SetScript("OnClick", function()
        local id = session and session.trackerId
        local SpecFlyout = addon.UI.ScootAuraSpecFlyout
        if not (id and SpecFlyout) then return end
        GameTooltip:Hide()
        SpecFlyout.OpenFor(specBtn, {
            title = "Load this aura on...",
            detached = true,
            get = function()
                local tracker = SAU().GetTracker(id)
                return tracker and tracker.specs
            end,
            toggle = function(specID)
                SAU().ToggleTrackerSpec(id, specID)
                Editor.DeferredRefresh()
            end,
        })
    end)

    deleteBtn:SetScript("OnClick", function()
        local tracker = CurrentTracker()
        if not tracker then return end
        local id = session.trackerId
        GameTooltip:Hide()
        addon.UI.Controls:ConfirmDialog(
            "Delete '" .. SAU().DisplayName(tracker) .. "'? Its styling and saved position are removed too.",
            function()
                Editor.Close()
                SAU().DeleteTracker(id)
                RefreshList()
            end)
    end)

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
        -- The icons sit under the name, so nothing is held clear beside it.
        selectedRoom = 0,
        onSelect = function(trackerId)
            C_Timer.After(0, function()
                if session and session.trackerId ~= trackerId and SAU().GetTracker(trackerId) then
                    Editor.Open(trackerId)
                end
            end)
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

    -- Close X: on a template, the one the closeButton role gives (the
    -- template's own in its corner, or the role's fallback placed at the
    -- skin's corner offsets); the house X otherwise.
    local closeBtn, closeTxt
    if onTemplate then
        local btn, closeSpec = addon.UI.Controls:CreateCloseButton({
            parent = frame,
            onClick = function() Editor.Close() end,
        })
        if btn then
            if not (closeSpec and closeSpec.kind == "window") then
                local corner = addon.UI.Controls.Metrics().closeButton
                btn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", corner.x, corner.y)
                btn:SetFrameLevel(frame:GetOverlayLevel())
            end
            closeBtn = btn
        end
    end
    if not closeBtn then
        closeBtn = CreateFrame("Button", nil, frame)
        closeBtn:SetSize(24, 24)
        closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
        closeBtn:SetFrameLevel(frame:GetFrameLevel() + 10)
        closeBtn:RegisterForClicks("AnyUp")
        local closeBg = closeBtn:CreateTexture(nil, "BACKGROUND", nil, -7)
        closeBg:SetAllPoints()
        addon.UI.Controls.RegisterThemedFill(closeBg, 1)
        closeBg:Hide()
        closeTxt = closeBtn:CreateFontString(nil, "OVERLAY")
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
            -- Read here rather than closing over the color the window was
            -- built with: the accent can change between the two.
            local r, g, b = addon.GetAccentColorRGB()
            closeTxt:SetTextColor(r, g, b, 1)
        end)
        closeBtn:SetScript("OnClick", function() Editor.Close() end)
    end

    -- Region frames
    local topLeft = CreateFrame("Frame", nil, frame)
    topLeft:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -TITLE_H)
    topLeft:SetSize(TOP_LEFT_W, TOP_H)
    widgets.topLeft = topLeft

    -- Selector block host: fixed width, pinned to the top of the quadrant.
    -- The builder's Finalize() sets its height, so the progressive reveal
    -- (and per-kind extra fields) grows downward. It sits 40 px right of
    -- center: the fields anchor to its right edge, and that moves them into
    -- the room left before the preview divider.
    local selectorsHost = CreateFrame("Frame", nil, topLeft)
    selectorsHost:SetSize(640, 100)
    selectorsHost:SetPoint("TOP", topLeft, "TOP", 40, -SELECTORS_TOP_GAP)
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

    -- A black border on an icon or bar disappears against the window's own
    -- dark ground, so the preview sits on a light plate. The frame holds the
    -- plate's rect only; its art goes on the quadrant, beneath every child.
    local previewBackdrop = CreateFrame("Frame", nil, topRight)
    previewBackdrop:SetPoint("TOPLEFT", topRight, "TOPLEFT", PREVIEW_BACKDROP_INSET, -PREVIEW_BACKDROP_TOP)
    previewBackdrop:SetPoint("BOTTOMRIGHT", topRight, "BOTTOMRIGHT", -PREVIEW_BACKDROP_INSET, PREVIEW_BACKDROP_INSET)
    CreateRoundedPlate(topRight, previewBackdrop, PREVIEW_BACKDROP_RADIUS, PREVIEW_BACKDROP_COLOR)
    widgets.previewBackdrop = previewBackdrop

    -- The preview strip fills the plate: the open tracker's group laid out
    -- as on screen, or a strip of one. A click on a neighbour opens that
    -- tracker one frame later, so the click frame stays smooth; the strip
    -- and the title carousel then glide to it from their own SetContext.
    previewStrip = addon.UI.ScootAuraPreviewStrip.Create(topRight, previewBackdrop, {
        onSelect = function(trackerId)
            C_Timer.After(0, function()
                if session and session.trackerId ~= trackerId and SAU().GetTracker(trackerId) then
                    Editor.Open(trackerId)
                end
            end)
        end,
    })
    widgets.previewStrip = previewStrip

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

    -- Spell region statics in the bottom-left quadrant (built once; an
    -- EditBox must survive re-renders)
    local spellExplainer = bottomLeft:CreateFontString(nil, "OVERLAY")
    spellExplainer:SetFont(theme:GetFont("LABEL"), 12, "")
    spellExplainer:SetPoint("TOPLEFT", bottomLeft, "TOPLEFT", 8, -20)
    spellExplainer:SetText("Select a Spell to track from the CDM list below, or enter its ID:")
    local dimR, dimG, dimB = theme:GetDimTextColor()
    spellExplainer:SetTextColor(dimR, dimG, dimB, 1)
    widgets.spellExplainer = spellExplainer

    -- Stands in for the whole spell region on a kind that tracks no spell.
    local kindNote = bottomLeft:CreateFontString(nil, "OVERLAY")
    kindNote:SetFont(theme:GetFont("LABEL"), 12, "")
    kindNote:SetPoint("TOPLEFT", bottomLeft, "TOPLEFT", 8, -20)
    kindNote:SetPoint("TOPRIGHT", bottomLeft, "TOPRIGHT", -8, -20)
    kindNote:SetJustifyH("LEFT")
    kindNote:SetJustifyV("TOP")
    kindNote:SetWordWrap(true)
    kindNote:SetTextColor(dimR, dimG, dimB, 1)
    kindNote:Hide()
    widgets.kindNote = kindNote

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
    widgets.catalogHost = catalogHost
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

    -- The window is built once and kept for the session, so its chrome follows
    -- the accent rather than freezing at the color of the first open. The
    -- separators, the close button's hover fill and the scroll thumbs are on
    -- the shared Controls registry already; this covers the rest.
    theme:Subscribe("ScootAuraEditor", function(r, g, b)
        titleText:SetTextColor(r, g, b, 1)
        for _, btn in ipairs(titleIcons) do btn._tex:SetVertexColor(r, g, b) end
        previewLabel:SetTextColor(r, g, b, 1)
        -- The house X is black under the pointer; OnLeave picks up the new
        -- color. A template's X is the client's own art.
        if closeTxt and not closeBtn:IsMouseOver() then
            closeTxt:SetTextColor(r, g, b, 1)
        end
        widgets.carousel:SetAccent(r, g, b)
    end)

    -- The preview strip keeps a loaded group to the members that load in the
    -- current spec, so a spec change while the editor is open re-reads the
    -- set. Deferred a frame, as the engine's own pass is: the event can arrive
    -- before GetSpecialization reports the new spec.
    addon.Events.On("ScootAuraEditor", "PLAYER_SPECIALIZATION_CHANGED", function(_, unit)
        if unit and unit ~= "player" then return end
        if frame:IsShown() then Editor.DeferredPreviewRefresh() end
    end)

    -- ESC closes (combat-safe attach)
    addon.EscapeKey.Attach(frame, function() Editor.Close() end)
end

--------------------------------------------------------------------------------
-- Dynamic regions
--------------------------------------------------------------------------------

-- The duration kinds and the stacks kinds read as two measures of one aura.
-- The cooldown leads the list.
local KIND_LABELS = {
    cooldown = "a Spell's Cooldown",
    buff = "a Buff's duration", debuff = "a Debuff's duration",
    buffstacks = "the stacks of a Buff", debuffstacks = "the stacks of a Debuff",
    missingbuff = "a Missing Buff", classpower = "my Class Power",
    classresource = "my Class Resource",
}
local KIND_ORDER = {
    "cooldown", "buff", "debuff", "buffstacks", "debuffstacks", "missingbuff", "classpower", "classresource",
}
-- What the spell region says for a kind that tracks no spell.
local KIND_NOTES = {
    classpower = "Class Power tracks the resource your character runs on: Energy, Rage, Mana, Focus, "
        .. "Runic Power, Insanity, Fury, Maelstrom or Astral Power. It follows the display power, so a "
        .. "Druid's tracker changes with the form. There is no spell to pick.",
    classresource = "Class Resource tracks the points your character builds and spends: Combo Points for a "
        .. "Rogue or a Druid in Cat Form, Runes, Arcane Charges, Holy Power, Chi, Soul Shards or Essence. It "
        .. "follows your specialization and form, so there is nothing to pick. A character whose spec has no "
        .. "such resource shows nothing.",
}
local UNIT_LABELS = {
    player = "Myself", group = "My Group", target = "My Target", focus = "My Focus",
}
-- Units listed for a kind but not yet offered: shown dimmed and inert.
local COMING_SOON_UNITS = {}
-- The two bars share every setting and tab; "vbar" stands the bar on its
-- icon. Circles would join the same selector.
local SHAPE_LABELS = { icon = "an Icon", bar = "a Horizontal Bar", vbar = "a Vertical Bar", shape = "a Shape" }
local SHAPE_ORDER = { "icon", "bar", "vbar", "shape" }
-- A missing-buff tracker is a reminder: icon, text, or both.
local MISSING_SHAPE_LABELS = { icon = "an Icon", text = "Text", icontext = "an Icon & Text" }
local MISSING_SHAPE_ORDER = { "icon", "text", "icontext" }
-- A Class Power tracker is the bar, or the number alone (the "text" token).
local CLASS_POWER_SHAPE_LABELS = { bar = "a Bar", text = "a Number" }
local CLASS_POWER_SHAPE_ORDER = { "bar", "text" }
-- A Class Resource tracker is a segmented bar, or one shape per point. "Shapes",
-- since an icon in this editor is the aura's own art.
local CLASS_RESOURCE_SHAPE_LABELS = { bar = "a Bar", icons = "a Group of Shapes" }
local CLASS_RESOURCE_SHAPE_ORDER = { "bar", "icons" }
-- A Spell Cooldown tracker is the icon with the swipe, or the bar with the fill.
local COOLDOWN_SHAPE_LABELS = { icon = "an Icon", bar = "a Horizontal Bar", vbar = "a Vertical Bar" }
local COOLDOWN_SHAPE_ORDER = { "icon", "bar", "vbar" }
-- A stacks tracker is the icon carrying the count, the segmented bar, one
-- shape per stack (stacks.lua), or the count alone.
local STACK_SHAPE_LABELS = {
    icon = "an Icon", bar = "a Bar", icons = "a Group of Shapes", text = "a Floating Number",
}
local STACK_SHAPE_ORDER = { "icon", "bar", "icons", "text" }
-- Shared by both missing-buff gate rows.
local YES_NO_LABELS = { yes = "Yes", no = "No" }
local YES_NO_ORDER = { "yes", "no" }
-- "Show it..." on the Spell Cooldown kind (the tokens live in core.lua).
local SHOW_WHEN_LABELS = {
    always = "Always", oncooldown = "Only while on Cooldown", ready = "Only while Ready",
}
local SHOW_WHEN_ORDER = { "always", "oncooldown", "ready" }
-- "When it's missing, show..." per shape (buff and debuff; the tokens and their
-- per-shape validity live in core.lua). Every visual is a reveal: art beneath
-- the engine button, uncovered when the slot empties.
local MISSING_VISUAL_LABELS_ICON = {
    none = "Nothing",
    desat = "a Desaturated Icon",
    blink = "a Blinking Icon",
    blinkdesat = "a Blinking, Desaturated Icon",
}
local MISSING_VISUAL_ORDER_ICON = { "none", "desat", "blink", "blinkdesat" }
local MISSING_VISUAL_LABELS_BAR = {
    none = "Nothing",
    emptybar = "an Empty Bar",
    blinkemptybar = "a Blinking Empty Bar",
    blinkicon = "a Blinking Icon",
    blinkdesaticon = "a Blinking, Desaturated Icon",
}
local MISSING_VISUAL_ORDER_BAR = { "none", "emptybar", "blinkemptybar", "blinkicon", "blinkdesaticon" }
local MISSING_VISUAL_LABELS_SHAPE = {
    none = "Nothing",
    desat = "a Desaturated Shape",
    blink = "a Blinking Shape",
    blinkdesat = "a Blinking, Desaturated Shape",
}
local MISSING_VISUAL_ORDER_SHAPE = { "none", "desat", "blink", "blinkdesat" }
-- "When stacks are 0, show..." per shape on the stacks kinds: Nothing, or the
-- shape at 0, which is the default (core.lua STACK_MISSING_VISUALS_BY_SHAPE).
local STACK_MISSING_VISUALS = {
    icon  = { values = { none = "Nothing", desat = "a Desaturated Icon" }, order = { "none", "desat" } },
    bar   = { values = { none = "Nothing", emptybar = "an Empty Bar" }, order = { "none", "emptybar" } },
    icons = { values = { none = "Nothing", desatpips = "Desaturated Shapes" }, order = { "none", "desatpips" } },
    text  = { values = { none = "Nothing", zero = "a Gray \"0\"" }, order = { "none", "zero" } },
}

-- Sub-options for one missing-state visual, opened by the gear that sits
-- inside the "When it's missing, show..." field
-- (ui/v2/controls/SelectorGear.lua). One page table shared by every token that
-- offers it, so Icon and Shape build one panel body between them.
--
-- The slider writes through ctx.setAndApply, which restyles the tracker
-- without re-rendering the selectors, then refreshes the preview alone. A
-- page that called ctx.refresh() would destroy the gear its own fly-out is
-- anchored to.
local MISSING_OPACITY_PAGE = {
    tooltip = "Options for this missing-state visual",
    width = 310,
    height = 112,
    build = function(page)
        local Controls = addon.UI.Controls
        local theme = addon.UI.Theme

        local slider = Controls:CreateSlider({
            parent = page,
            label = "Opacity",
            min = 0, max = 100, step = 1,
            width = 110,
            inputWidth = 40,
            minLabel = "Hidden",
            maxLabel = "100%",
            get = function() return ctx.get("missingVisualOpacity") or 100 end,
            set = function(v)
                ctx.setAndApply("missingVisualOpacity", v)
                ctx.refreshPreview()
            end,
        })
        if not slider then return end
        slider:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
        slider:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)

        local hint = page:CreateFontString(nil, "OVERLAY")
        hint:SetFont(theme:GetFont("VALUE"), 11, "")
        hint:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 12, -2)
        hint:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", -12, -2)
        hint:SetJustifyH("LEFT")
        hint:SetWordWrap(true)
        hint:SetText("Applies to the missing-state art alone. The tracker's own opacity multiplies with it.")
        local dimR, dimG, dimB = theme:GetDimTextColor()
        hint:SetTextColor(dimR, dimG, dimB, 1)
    end,
}

-- Gear config for the missing-state selector, or nil when no token in this
-- shape's list carries sub-options. Visibility falls out of the pages table:
-- a token with a page shows the gear, a token without one does not.
local function MissingVisualGear(order)
    local pages
    for _, token in ipairs(order) do
        local traits = SAU().MissingVisualTraits(token)
        if traits and traits.opacity then
            pages = pages or {}
            pages[token] = MISSING_OPACITY_PAGE
        end
    end
    if not pages then return nil end
    return { direction = "DOWN", gap = 8, pages = pages }
end

-- Sub-option for both Class Power shapes, opened by the gear inside the
-- "Shown as..." field: the number as a percentage of the maximum instead of
-- the value. One page table for both tokens, so they share one panel body.
-- The toggle writes through ctx.setAndApply and refreshes the preview alone;
-- a page that re-rendered the selectors would destroy the gear its own
-- fly-out is anchored to.
local POWER_PERCENT_PAGE = {
    tooltip = "Options for the number",
    width = 310,
    height = 56,
    build = function(page)
        local Controls = addon.UI.Controls
        local toggle = Controls:CreateToggle({
            parent = page,
            label = "Show as a percentage",
            get = function() return ctx.get("powerTextPercent") == true end,
            set = function(v)
                ctx.setAndApply("powerTextPercent", v and true or false)
                ctx.refreshPreview()
            end,
        })
        if not toggle then return end
        toggle:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
        toggle:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
    end,
}

local function ClassPowerShapeGear()
    return {
        direction = "DOWN", gap = 8,
        pages = { bar = POWER_PERCENT_PAGE, text = POWER_PERCENT_PAGE },
    }
end

-- The stacks tracker as ResolveMaxStacks reads it: the live record, or the
-- draft's spell and override.
local function StackTrackerView()
    local tracker = CurrentTracker()
    if tracker then return tracker end
    local c = session and session.draft and session.draft.content
    return {
        kind = c and c.kind,
        spellId = session and session.validated and session.validated.spellId or nil,
        maxStacks = c and c.maxStacks,
    }
end

-- Writes the segment count without re-rendering the selectors, which would
-- destroy the gear the fly-out hangs from. A value equal to the detected one
-- clears the override, so the tracker follows the spell again.
local function SetMaxStacks(v)
    if not session then return end
    v = math.floor(tonumber(v) or SAU().DEFAULT_MAX_STACKS)
    local detected = SAU().DetectMaxStacks(StackTrackerView().spellId)
    local stored = (detected and v == detected) and false or v
    if session.trackerId then
        SAU().SetTrackerContent(session.trackerId, { maxStacks = stored })
    else
        session.draft.content.maxStacks = stored or nil
    end
    ctx.refreshPreview()
end

-- Sub-option for the stacks kinds' segmented shapes, opened by the gear
-- inside the "Shown as..." field: how many segments or shapes stand for a
-- full stack count. The spell says, where it can (core.lua DetectMaxStacks).
local MAX_STACKS_PAGE = {
    tooltip = "Options for the stack count",
    -- Wider than the opacity page: "Max Stacks" needs the room before the
    -- slider, which keeps the same width.
    width = 350,
    height = 112,
    build = function(page)
        local Controls = addon.UI.Controls
        local theme = addon.UI.Theme
        local slider = Controls:CreateSlider({
            parent = page,
            label = "Max Stacks",
            min = 1, max = SAU().MAX_STACK_PIPS, step = 1,
            width = 110,
            inputWidth = 40,
            minLabel = "1",
            maxLabel = tostring(SAU().MAX_STACK_PIPS),
            get = function() return (SAU().ResolveMaxStacks(StackTrackerView())) end,
            set = SetMaxStacks,
        })
        if not slider then return end
        slider:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
        slider:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)

        local hint = page:CreateFontString(nil, "OVERLAY")
        theme:ApplyFont(hint, "value", 11)
        hint:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 12, -2)
        hint:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", -12, -2)
        hint:SetJustifyH("LEFT")
        hint:SetWordWrap(true)
        local detected = SAU().DetectMaxStacks(StackTrackerView().spellId)
        hint:SetText(detected
            and ("Detected from the spell: " .. detected .. ".")
            or "Not detected from the spell; set it by hand.")
        local dimR, dimG, dimB = theme:GetDimTextColor()
        hint:SetTextColor(dimR, dimG, dimB, 1)
    end,
}

local function StackShapeGear()
    return {
        direction = "DOWN", gap = 8,
        pages = { bar = MAX_STACKS_PAGE, icons = MAX_STACKS_PAGE },
    }
end

-- Kinds whose shape options carry an in-field gear; a kind without a row
-- shows none.
local SHAPE_GEAR_BY_KIND = {
    classpower = ClassPowerShapeGear,
    buffstacks = StackShapeGear,
    debuffstacks = StackShapeGear,
}

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
            -- A kind with one possible unit (Class Power) has no "On..." row:
            -- the draft seeds that unit here. The seed is not a choice the
            -- user made, so a flip to a kind that offers the row clears it.
            if c.unitSeeded then
                c.unit = nil
                c.unitSeeded = nil
            end
            local sole = SAU().SoleUnitForKind(value)
            if sole then
                c.unit = sole
                c.unitSeeded = true
            end
            -- Same for the combat gate: a kind that starts ungated seeds No,
            -- and a flip to a gated kind takes the seed back.
            if c.combatSeeded then
                c.onlyInCombat = nil
                c.combatSeeded = nil
            end
            if not SAU().KindStartsGated(value) and c.onlyInCombat == nil then
                c.onlyInCombat = false
                c.combatSeeded = true
            end
            local shapes = SAU().VALID_SHAPES_BY_KIND[value]
            if c.shape and not (shapes and shapes[c.shape]) then
                c.shape = nil
            end
            if not SAU().KindTracksStacks(value) then
                c.maxStacks = nil
            end
            -- "Show it..." belongs to the Spell Cooldown kind: seeded so the
            -- row carries a value, cleared on a flip away.
            c.showWhen = SAU().CoerceShowWhen(value, c.showWhen)
        end
        -- The missing-state token follows the write path's rule (core.lua
        -- CoerceMissingVisual): "Nothing" is absence on a duration kind and
        -- a stored "none" on a stacks kind; a kind or shape flip that
        -- strands the token clears it, or falls to the stacks shape's default.
        if field == "kind" or field == "shape" or field == "missingVisual" then
            if c.kind and c.shape then
                c.missingVisual = SAU().CoerceMissingVisual(c.kind, c.shape, c.missingVisual)
            elseif c.missingVisual == "none"
                or (c.kind and not SAU().KindSupportsMissingVisual(c.kind)) then
                c.missingVisual = nil
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
    if SAU().KindTracksStacks(kind) then
        return STACK_SHAPE_LABELS, STACK_SHAPE_ORDER
    elseif kind == "missingbuff" then
        return MISSING_SHAPE_LABELS, MISSING_SHAPE_ORDER
    elseif kind == "classpower" then
        return CLASS_POWER_SHAPE_LABELS, CLASS_POWER_SHAPE_ORDER
    elseif kind == "classresource" then
        return CLASS_RESOURCE_SHAPE_LABELS, CLASS_RESOURCE_SHAPE_ORDER
    elseif kind == "cooldown" then
        return COOLDOWN_SHAPE_LABELS, COOLDOWN_SHAPE_ORDER
    end
    return SHAPE_LABELS, SHAPE_ORDER
end

local function MissingVisualOptions(kind, shape)
    if SAU().KindTracksStacks(kind) then
        local set = STACK_MISSING_VISUALS[shape] or STACK_MISSING_VISUALS.icon
        return set.values, set.order
    end
    if SAU().IsBarShape(shape) then
        return MISSING_VISUAL_LABELS_BAR, MISSING_VISUAL_ORDER_BAR
    elseif shape == "shape" then
        return MISSING_VISUAL_LABELS_SHAPE, MISSING_VISUAL_ORDER_SHAPE
    end
    return MISSING_VISUAL_LABELS_ICON, MISSING_VISUAL_ORDER_ICON
end

-- One selector with an unset state: draft selectors start on "Choose".
-- opts.disabledOptions lists keys that are shown but inert; opts.gear is an
-- in-field gear config (ui/v2/controls/SelectorGear.lua).
-- Rows queue here and FlushChoiceSelectors adds them, so every field takes
-- the width the widest one needs: a field sizes itself to its longest option
-- (and its gear), and one wider field breaks the column the labels align to.
local pendingSelectors = {}

local function AddChoiceSelector(builder, label, valueMap, order, current, onSet, opts)
    local values = {}
    for k, v in pairs(valueMap) do values[k] = v end
    local fullOrder = {}
    if not current then
        values.choose = "Choose..."
        table.insert(fullOrder, "choose")
    end
    for _, k in ipairs(order) do table.insert(fullOrder, k) end

    table.insert(pendingSelectors, {
        label = label,
        labelAlign = "field",
        noBottomBorder = true,
        width = 290,
        sizeScale = 1.1,
        values = values,
        order = fullOrder,
        disabledOptions = opts and opts.disabledOptions or nil,
        gear = opts and opts.gear or nil,
        get = function() return current or "choose" end,
        set = function(v)
            if v ~= "choose" then onSet(v) end
        end,
    })
end

local function FlushChoiceSelectors(builder)
    local Controls = addon.UI.Controls
    local width = 0
    for _, spec in ipairs(pendingSelectors) do
        local S = spec.sizeScale
        width = math.max(width, (Controls.FieldNeed("selector", spec.values, {
            order = spec.order, floor = spec.width, scale = S,
            size = math.floor(12 * S + 0.5), gear = spec.gear ~= nil,
        })))
    end
    for _, spec in ipairs(pendingSelectors) do
        spec.width = width
        builder:AddSelector(spec)
    end
    pendingSelectors = {}
end

local function RenderSelectors()
    if selBuilder then selBuilder:Cleanup() end
    local SettingsBuilder = addon.UI.SettingsBuilder
    selBuilder = SettingsBuilder:CreateFor(widgets.selectorsHost)

    local kind = ContentValue("kind")
    local unit = ContentValue("unit")
    local shape = ContentValue("shape")

    -- A live tracker created without a spell cannot turn into a spell kind
    -- in place (there is nothing to validate), so those options show dimmed
    -- and inert. One that carries a spell from before a kind flip keeps them.
    local live = CurrentTracker()
    local kindDisabled
    if live and not SAU().KindNeedsSpell(live.kind) and not live.spellId then
        kindDisabled = {}
        for _, k in ipairs(KIND_ORDER) do
            if SAU().KindNeedsSpell(k) then kindDisabled[k] = true end
        end
    end
    AddChoiceSelector(selBuilder, "I want to track...",
        KIND_LABELS, KIND_ORDER, kind,
        function(v) SetContent("kind", v) end,
        { disabledOptions = kindDisabled })

    -- A kind with one possible unit (Class Power: the player) has no row to
    -- show; SetContent seeded that unit on the kind pick.
    if kind and not SAU().SoleUnitForKind(kind) then
        local uValues, uOrder, uDisabled = UnitOptions(kind)
        AddChoiceSelector(selBuilder, "On...", uValues, uOrder, unit,
            function(v) SetContent("unit", v) end,
            { disabledOptions = uDisabled })
    end

    if kind and unit then
        local sValues, sOrder = ShapeOptions(kind)
        -- Class Power's shapes carry the gear with the percent toggle, and a
        -- stacks kind's segmented shapes the max stacks; a kind without a row
        -- in SHAPE_GEAR_BY_KIND shows none.
        local gearFn = SHAPE_GEAR_BY_KIND[kind]
        AddChoiceSelector(selBuilder, "Shown as...",
            sValues, sOrder, shape,
            function(v) SetContent("shape", v) end,
            { gear = gearFn and gearFn() or nil })
    end

    -- Missing-state visual, on the kinds that show one aura's state. Options
    -- follow the kind and the shape; the row always carries a value, so it
    -- never sits on "Choose". A stacks kind asks about a count of 0.
    if kind and unit and shape and SAU().KindSupportsMissingVisual(kind) then
        local mValues, mOrder = MissingVisualOptions(kind, shape)
        -- The resolver, not the raw field, so a stale token reads as it
        -- renders.
        local missingCurrent = ctx.missingVisual()
        local missingLabel = SAU().KindTracksStacks(kind)
            and "When stacks are 0, show..." or "When it's missing, show..."
        AddChoiceSelector(selBuilder, missingLabel,
            mValues, mOrder, missingCurrent,
            function(v) SetContent("missingVisual", v) end,
            { gear = MissingVisualGear(mOrder) })
    end

    -- "Show it..." on the Spell Cooldown kind: always, only while the spell
    -- is on cooldown, or only while it is ready. The row always carries a
    -- value (core.lua CoerceShowWhen), so it never sits on "Choose".
    if kind and unit and shape and SAU().KindHasShowWhen(kind) then
        AddChoiceSelector(selBuilder, "Show it...",
            SHOW_WHEN_LABELS, SHOW_WHEN_ORDER, ctx.showWhen(),
            function(v) SetContent("showWhen", v) end)
    end

    -- Extras. Every kind gates on combat; the instance gate is missing-buff
    -- only. Both carry a value rather than nil, so neither sits on "Choose".
    if kind and unit and shape then
        local combatCurrent
        if session and session.trackerId then
            -- A tracker saved before its kind carried the field reads through
            -- the same resolver the gate does, so the selector never shows Yes
            -- on a tracker that is in fact ungated.
            combatCurrent = SAU().OnlyInCombat(CurrentTracker()) and "yes" or "no"
        else
            combatCurrent = (ContentValue("onlyInCombat") == false) and "no" or "yes"
        end
        AddChoiceSelector(selBuilder, "Only in Combat?",
            YES_NO_LABELS, YES_NO_ORDER, combatCurrent,
            function(v) SetContent("onlyInCombat", v == "yes") end)
    end

    if kind == "missingbuff" and unit and shape then
        -- Dungeons, raids, delves, scenarios, battlegrounds and arenas. Unlike
        -- the combat gate this one defaults to No, so an existing reminder
        -- keeps showing everywhere until the user asks for otherwise.
        local onlyInInstances = ContentValue("onlyInInstances")
        local instanceCurrent = (onlyInInstances == true) and "yes" or "no"
        AddChoiceSelector(selBuilder, "Only in Instances?",
            YES_NO_LABELS, YES_NO_ORDER, instanceCurrent,
            function(v) SetContent("onlyInInstances", v == "yes") end)
    end

    FlushChoiceSelectors(selBuilder)
    selBuilder:Finalize()
end

local function RenderTabs()
    if tabsBuilder then tabsBuilder:Cleanup() end
    local SettingsBuilder = addon.UI.SettingsBuilder
    local child = widgets.tabsChild
    local w = widgets.tabsScroll:GetWidth()
    w = (w and w > 0) and w or (WINDOW_W - BOTTOM_LEFT_W - PAD * 3 - 1)
    child:SetWidth(w - (widgets.tabsScroll._barReserve or 0))

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

-- The Class Power colors, as classpower.lua resolves them for the HUD.
local CLASS_POWER_FILL_COLOR_OPTS = { barKind = "power", unitForPower = "player" }
local CLASS_POWER_TEXT_COLOR_OPTS = { classPowerMode = true, lightenMana = true, unitForPower = "player" }

--------------------------------------------------------------------------------
-- Preview views
--------------------------------------------------------------------------------

-- What a preview is built from: the settings read path and the content facts
-- the option builders below need, for the open tracker, the draft, or a
-- neighbour in the open tracker's group. The strip builds one member from
-- one view.
local function TrackerView(trackerId)
    local tracker = SAU().GetTracker(trackerId)
    if not tracker then return nil end
    local componentId = SAU().GetComponentId(trackerId)
    return {
        trackerId = trackerId,
        componentId = componentId,
        kind = tracker.kind,
        shape = tracker.shape,
        spellId = tracker.spellId,
        get = function(key)
            local v = Helpers().getSetting(componentId, key)
            if v == nil then v = DefaultFor(key) end
            return v
        end,
        missingVisual = SAU().MissingVisualFor(tracker),
        name = SAU().DisplayName(tracker),
        iconTexture = tracker.spellId and PlainSpellTexture(tracker.spellId) or nil,
        stackTracker = tracker,
    }
end

-- The open tracker, wearing the validated spell's art while a re-pick is in
-- flight, or the draft, which reads through ctx.
local function SessionView()
    if not session then return nil end
    if session.trackerId then
        local view = TrackerView(session.trackerId)
        if view and session.validated then
            view.spellId = session.validated.spellId
            view.iconTexture = session.validated.icon
        end
        return view
    end
    local validated = session.validated
    return {
        componentId = "scootAuraDraft",
        kind = ctx.kind(),
        shape = ctx.shape(),
        spellId = validated and validated.spellId or nil,
        get = ctx.get,
        missingVisual = ctx.missingVisual(),
        name = CurrentName(),
        iconTexture = validated and validated.icon or nil,
        stackTracker = StackTrackerView(),
    }
end

--------------------------------------------------------------------------------
-- Preview options, one builder per kind family. Each returns the
-- Controls:CreatePreview options for a view, less parent and timerEpoch,
-- which the strip supplies.
--------------------------------------------------------------------------------

-- The Class Power preview: the bar held at a fixed fraction in the resolved
-- power color, with the number in its mode's color (white on Default). The
-- generic preview knows the aura color modes only, so the read path hands it
-- Custom with the resolved tint, and turns off everything the kind never
-- shows.
local function ClassPowerPreviewOptions(view)
    local fillR, fillG, fillB = addon.ResolveColorRGBA("power", nil, CLASS_POWER_FILL_COLOR_OPTS)
    local textR, textG, textB = addon.ResolveColorRGBA("classPower", nil, CLASS_POWER_TEXT_COLOR_OPTS)
    local get = view.get
    local isBar = (view.shape == "bar")
    local function getSetting(key)
        if key == "barForegroundColorMode" then return "custom" end
        if key == "barForegroundTint" and get("barForegroundColorMode") ~= "custom" then
            return { fillR, fillG, fillB, 1 }
        end
        if key == "textColor" then
            local mode = get("textColorMode")
            if mode == "power" then return { textR, textG, textB, 1 } end
            if mode ~= "custom" then return { 1, 1, 1, 1 } end
        end
        if key == "barShowIcon" then return false end
        if key == "hideNameText" or key == "hideStackText" then return true end
        -- The Hide toggle is a bar option; the number alone always shows.
        if key == "hideText" and not isBar then return false end
        return get(key)
    end
    local percent = get("powerTextPercent") == true
    local ClassPower = SAU().ClassPower
    return {
        componentId = view.componentId,
        mode = isBar and "bar" or "text",
        settingKeys = { _showCAText = true },
        caTextSource = "duration",
        caTextLiteral = "75",
        -- The sign is its own smaller string, as on the HUD (classpower.lua).
        caTextSuffix = percent and { text = "%", sizeFor = ClassPower and ClassPower.SignSize } or nil,
        fillFraction = 0.75,
        rowHeight = 200,
        previewScale = 1,
        maxRowHeight = 340,
        getSetting = getSetting,
        noHover = true,
        noLabel = true,
    }
end

-- The Class Resource colors: the resource's own color from the module (the
-- display power's when the module is absent), the class color, or the tint.
local function ResourceColorRGB()
    local CR = SAU().ClassResource
    if CR and CR.ResourceColorRGB then
        local r, g, b = CR.ResourceColorRGB()
        if r then return r, g, b end
    end
    return addon.ResolveColorRGBA("power", nil, CLASS_POWER_FILL_COLOR_OPTS)
end

local function ResolveResourceFill(get, mode, tintKey)
    if mode == "custom" then
        local c = get(tintKey) or { 1, 1, 1, 1 }
        return { c[1] or 1, c[2] or 1, c[3] or 1, 1 }
    elseif mode == "class" then
        local r, g, b = addon.GetClassColorRGB("player")
        return r and { r, g, b, 1 } or { 1, 1, 1, 1 }
    end
    local r, g, b = ResourceColorRGB()
    return { r or 1, g or 1, b or 1, 1 }
end

-- The combo point tail for the preview sample: one color per pip from the
-- module's scheme, when the character's resource carries it and the toggle
-- is on; nil otherwise. The sample then shows four full, so the blended
-- point and the backdrop both show.
local PREVIEW_PIP_COUNT = 5
local PREVIEW_PIP_FILLED = 3
local PREVIEW_PIP_FILLED_TAIL = 4

local function ResourcePipColors(get, fill)
    local CR = SAU().ClassResource
    local rec = CR and CR.CurrentResource and CR.CurrentResource()
    local res = rec and rec.res
    if not (res and res.variedTail and CR.TailColorAt) then return nil end
    if get("variedLastPoints") == false then return nil end
    local colors = {}
    for i = 1, PREVIEW_PIP_COUNT do
        local r, g, b = CR.TailColorAt(i, PREVIEW_PIP_COUNT, fill[1], fill[2], fill[3])
        colors[i] = { r, g, b, 1 }
    end
    return colors
end

-- The Class Resource preview: five points with three full (four with the
-- combo point tail on), as the segmented bar or the icon row, with the fill
-- color resolved here and handed over as a custom tint, since the control
-- knows the aura color modes alone.
local function ClassResourcePreviewOptions(view)
    local get = view.get
    if view.shape == "icons" then
        local key = get("pipStyle") or "border:SquareMask"
        local tint = get("pipBackdropTint") or { 0, 0, 0, 1 }
        local opacity = (tonumber(get("pipBackdropOpacity")) or 100) / 100
        local fill = ResolveResourceFill(get, get("pipColorMode"), "pipTint")
        local pipColors = ResourcePipColors(get, fill)
        return {
            componentId = view.componentId,
            mode = "pips",
            pipShape = "icons",
            pipCount = PREVIEW_PIP_COUNT,
            pipFilled = pipColors and PREVIEW_PIP_FILLED_TAIL or PREVIEW_PIP_FILLED,
            pipAtlas = SAU()._AtlasFromShapeKey(key) or "SquareMask",
            pipBorderWidth = SAU().Pips.BorderWidth(key, tonumber(get("pipSize")) or 16),
            pipColor = fill,
            pipColors = pipColors,
            pipBackdropColor = { tint[1] or 0, tint[2] or 0, tint[3] or 0, opacity },
            rowHeight = 200,
            previewScale = 1,
            maxRowHeight = 340,
            getSetting = get,
            noHover = true,
            noLabel = true,
        }
    end
    local fill = ResolveResourceFill(get, get("barForegroundColorMode"), "barForegroundTint")
    local pipColors = ResourcePipColors(get, fill)
    local function getSetting(key)
        if key == "barForegroundColorMode" then return "custom" end
        if key == "barForegroundTint" then return fill end
        if key == "barShowIcon" then return false end
        if key == "hideNameText" or key == "hideStackText" then return true end
        return get(key)
    end
    return {
        componentId = view.componentId,
        mode = "pips",
        pipShape = "bar",
        pipCount = PREVIEW_PIP_COUNT,
        pipFilled = pipColors and PREVIEW_PIP_FILLED_TAIL or PREVIEW_PIP_FILLED,
        pipColors = pipColors,
        rowHeight = 200,
        previewScale = 1,
        maxRowHeight = 340,
        getSetting = getSetting,
        noHover = true,
        noLabel = true,
    }
end

-- The stacks preview: the count one short of the maximum, as the number on
-- the icon, the segmented bar, or the shape row. Shapes and a bar fill read
-- the class color or a tint, resolved here and handed over as Custom.
local function StackFill(get, mode, tintKey)
    if mode == "custom" then
        local c = get(tintKey) or { 1, 1, 1, 1 }
        return { c[1] or 1, c[2] or 1, c[3] or 1, 1 }
    end
    local r, g, b = addon.GetClassColorRGB("player")
    return r and { r, g, b, 1 } or { 1, 1, 1, 1 }
end

-- The stack count drawn through the preview's duration-text slot.
local STACK_TEXT_KEYS = {
    _showCAText = true,
    textFont = "stackTextFont", textStyle = "stackTextStyle", textSize = "stackTextSize",
    textColor = "stackTextColor", textPosition = "stackTextPosition",
    textInnerAnchor = "stackTextInnerAnchor", textOuterAnchor = "stackTextOuterAnchor",
    textOffsetX = "stackTextOffsetX", textOffsetY = "stackTextOffsetY", hideText = "hideStackText",
}

local function StacksPreviewOptions(view)
    local get, shape = view.get, view.shape
    local n = SAU().ResolveMaxStacks(view.stackTracker)
    local sample = math.max(1, n - 1)
    if shape == "icons" then
        local key = get("pipStyle") or "border:SquareMask"
        local tint = get("pipBackdropTint") or { 0, 0, 0, 1 }
        local opacity = (tonumber(get("pipBackdropOpacity")) or 100) / 100
        return {
            componentId = view.componentId,
            mode = "pips",
            pipShape = "icons",
            pipCount = n,
            pipFilled = sample,
            pipAtlas = SAU()._AtlasFromShapeKey(key) or "SquareMask",
            pipBorderWidth = SAU().Pips.BorderWidth(key, tonumber(get("pipSize")) or 16),
            pipColor = StackFill(get, get("pipColorMode"), "pipTint"),
            pipBackdropColor = { tint[1] or 0, tint[2] or 0, tint[3] or 0, opacity },
            rowHeight = 200,
            previewScale = 1,
            maxRowHeight = 340,
            getSetting = function(key2)
                -- The live row floors spacing at 0 (stacks.lua).
                if key2 == "pipSpacing" then
                    return math.max(0, tonumber(get("pipSpacing")) or 2)
                end
                return get(key2)
            end,
            noHover = true,
            noLabel = true,
        }
    elseif shape == "bar" then
        local fill = StackFill(get, get("barForegroundColorMode"), "barForegroundTint")
        return {
            componentId = view.componentId,
            mode = "pips",
            pipShape = "bar",
            pipCount = n,
            pipFilled = sample,
            rowHeight = 200,
            previewScale = 1,
            maxRowHeight = 340,
            getSetting = function(key2)
                if key2 == "barForegroundColorMode" then return "custom" end
                if key2 == "barForegroundTint" then return fill end
                if key2 == "barShowIcon" then return false end
                if key2 == "hideNameText" or key2 == "hideStackText" then return true end
                return get(key2)
            end,
            noHover = true,
            noLabel = true,
        }
    elseif shape == "text" then
        -- The Floating Number: the count alone, always shown (layout.lua).
        return {
            componentId = view.componentId,
            mode = "text",
            settingKeys = STACK_TEXT_KEYS,
            caTextSource = "applications",
            caTextLiteral = tostring(sample),
            rowHeight = 200,
            previewScale = 1,
            maxRowHeight = 340,
            getSetting = function(key2)
                if key2 == "hideStackText" then return false end
                return get(key2)
            end,
            noHover = true,
            noLabel = true,
        }
    end
    return {
        componentId = view.componentId,
        mode = "icon",
        iconTexture = view.iconTexture,
        settingKeys = STACK_TEXT_KEYS,
        caTextSource = "applications",
        caTextLiteral = tostring(sample),
        rowHeight = 200,
        previewScale = 1,
        maxRowHeight = 340,
        getSetting = get,
        noHover = true,
        noLabel = true,
    }
end

-- The Spell Cooldown kind: the generic preview (the 15 s countdown and the
-- bar fill) with the template's dark swipe over the icon.
local function CooldownPreviewOptions(view)
    local shape = view.shape
    local mode = "icon"
    if SAU().IsBarShape(shape) then
        mode = view.get("barShowIcon") and "iconbar" or "bar"
    end
    return {
        componentId = view.componentId,
        mode = mode,
        iconTexture = view.iconTexture,
        settingKeys = { _showCAText = true },
        caTextSource = "duration",
        previewNameLabel = view.name,
        rowHeight = 200,
        previewScale = 1,
        maxRowHeight = 340,
        getSetting = view.get,
        iconCooldown = not SAU().IsBarShape(shape),
        barVertical = (shape == "vbar"),
        noHover = true,
        noLabel = true,
    }
end

-- The Missing Buff reminder as it looks while the buff is missing: the spell
-- icon and/or the aura name, laid out around each other by the Aura Name
-- tab's keys. The generic preview speaks in duration-text keys, so map them
-- onto nameText* and pin the position outside the icon.
local function MissingBuffPreviewOptions(view)
    local get, shape = view.get, view.shape
    local nameText = view.spellId and SAU().DescribeSpell(view.spellId) or view.name
    if get("missingSuffix") == true then
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
    return {
        componentId = view.componentId,
        mode = (shape == "text") and "text" or "icon",
        iconTexture = view.iconTexture,
        settingKeys = keys,
        caTextSource = "duration",
        caTextLiteral = showText and nameText or nil,
        rowHeight = 200,
        previewScale = 1,
        maxRowHeight = 340,
        getSetting = function(key)
            if key == "__missingTextPosition" then return "outside" end
            if key == "__missingHideText" then return false end
            return get(key)
        end,
        noHover = true,
        noLabel = true,
    }
end

-- The aura kinds: an icon with the swipe, a bar with or without its icon, or
-- a shape with its drain, each with the 15 s countdown.
local function GenericPreviewOptions(view)
    local get, shape = view.get, view.shape
    local mode, shapeAtlas, shapeColor, shapeDrain, iconSwipe, iconSwipeBackdropAlpha
    local iconSwipeBackdropShade, iconSwipeLine
    if SAU().IsBarShape(shape) then
        mode = get("barShowIcon") and "iconbar" or "bar"
    elseif shape == "shape" then
        mode = "icon"
        shapeAtlas = SAU()._AtlasFromShapeKey(get("shapeStyle") or "border:SquareMask") or "SquareMask"
        shapeDrain = get("shapeShowDrain") ~= false
        if (get("shapeColorMode") or "class") == "class" then
            local r, g, b = addon.GetClassColorRGB("player")
            shapeColor = r and { r, g, b, 1 } or { 1, 1, 1, 1 }
        else
            shapeColor = get("shapeTint") or { 1, 1, 1, 1 }
        end
    else
        mode = "icon"
        iconSwipe = get("iconShowSwipe") ~= false
            and (get("iconMode") or "default") == "default"
        if iconSwipe then
            -- Under a Desaturated missing visual the elapsed share shows the
            -- reveal, which carries its own opacity.
            local traits = SAU().MissingVisualTraits(view.missingVisual)
            local pct = (traits and traits.opacity and tonumber(get("missingVisualOpacity"))) or 100
            iconSwipeBackdropAlpha = math.max(0, math.min(100, pct)) / 100
            -- Swipe Darkness applies with or without a reveal.
            iconSwipeBackdropShade = 1 - SAU().SwipeDarkness(get("iconSwipeDarkness"))
            local r, g, b, a = SAU().SwipeLineColor(get("iconSwipeLineColor"))
            iconSwipeLine = { r, g, b, a, texture = SAU().SWIPE_LINE_TEXTURE }
        end
    end
    return {
        componentId = view.componentId,
        mode = mode,
        iconTexture = view.iconTexture,
        settingKeys = { _showCAText = true },
        caTextSource = "duration",
        previewNameLabel = view.name,
        rowHeight = 200,
        previewScale = 1,
        maxRowHeight = 340,
        getSetting = get,
        shapeAtlas = shapeAtlas,
        shapeColor = shapeColor,
        shapeDrain = shapeDrain,
        iconSwipe = iconSwipe,
        iconSwipeBackdropAlpha = iconSwipeBackdropAlpha,
        iconSwipeBackdropShade = iconSwipeBackdropShade,
        iconSwipeLine = iconSwipeLine,
        barVertical = (shape == "vbar"),
        noHover = true,
        noLabel = true,
    }
end

-- Kinds that draw their own preview instead of the generic aura one.
local KIND_PREVIEWS = {
    classpower = ClassPowerPreviewOptions,
    classresource = ClassResourcePreviewOptions,
    buffstacks = StacksPreviewOptions,
    debuffstacks = StacksPreviewOptions,
    cooldown = CooldownPreviewOptions,
    missingbuff = MissingBuffPreviewOptions,
}

-- The preview options for one view, or nil while a kind that needs a spell
-- has none: without one there is nothing real to show, and the control's
-- fallback is the player's spec icon. A kind with no spell previews as soon
-- as its shape is chosen.
local function PreviewOptions(view)
    if SAU().KindNeedsSpell(view.kind) and not view.spellId then return nil end
    return (KIND_PREVIEWS[view.kind] or GenericPreviewOptions)(view)
end

-- The preview quadrant: the open tracker's group as the strip lays it out,
-- or a strip of one. The strip builds each member from its own view and,
-- on a value edit, rebuilds the selected member alone.
local function RenderPreview()
    local view = SessionView()
    if not (view and PreviewOptions(view)) then
        previewStrip:Reset()
        return
    end

    local selectedId = session.trackerId or "draft"
    local tracker = CurrentTracker()
    local gid = tracker and tracker.groupId
    local members = gid and addon.UI.ScootAuraTitleCarousel.Members(gid) or nil
    local key, spacing, grow
    if members then
        key = gid
        local group = SAU().GetGroup(gid)
        -- A loaded group (the Aura List's Loaded block) shows the members that
        -- load in the current spec, as the live group does, plus the open one
        -- whatever its spec list. A group that is off or not loaded for this
        -- spec shows every member.
        if SAU().IsGroupActive(gid, group) then
            local kept = {}
            for _, m in ipairs(members) do
                if m.id == selectedId or SAU().SpecAllows(SAU().GetTracker(m.id)) then
                    kept[#kept + 1] = m
                end
            end
            members = kept
        end
        for _, m in ipairs(members) do
            local member = SAU().GetTracker(m.id)
            m.spellId = member and member.spellId or nil
        end
        local settings = group and group.settings or {}
        spacing = tonumber(settings.spacing) or 4
        grow = settings.grow or "RIGHT"
    else
        key = session.trackerId and ("t" .. session.trackerId) or "draft"
        members = { { id = selectedId, name = view.name, enabled = true, spellId = view.spellId } }
    end

    previewStrip:SetContext({
        key = key,
        members = members,
        selectedId = selectedId,
        spacing = spacing,
        grow = grow,
        build = function(cell, id, epoch)
            local memberView = (id == selectedId) and view or TrackerView(id)
            local options = memberView and PreviewOptions(memberView)
            if not options then return nil end
            options.parent = cell
            options.timerEpoch = epoch
            return addon.UI.Controls:CreatePreview(options)
        end,
    })
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

-- Centers the explainer and the ID box as a pair over the pane; a pair wider
-- than the pane starts at its left inset instead.
local function PositionSpellPrompt()
    local paneW = widgets.bottomLeft:GetWidth() or BOTTOM_LEFT_W
    local textW = widgets.spellExplainer:GetStringWidth() or 0
    local pairW = textW + 8 + (widgets.spellBox:GetWidth() or 0)
    widgets.spellExplainer:ClearAllPoints()
    if textW <= 0 or pairW > paneW - 16 then
        widgets.spellExplainer:SetPoint("TOPLEFT", widgets.bottomLeft, "TOPLEFT", 8, -20)
    else
        widgets.spellExplainer:SetPoint("TOPLEFT", widgets.bottomLeft, "TOP", -pairW / 2, -20)
    end
end

-- The spell region (explainer, ID box, chip, status, catalog) serves the
-- kinds that track a spell; a kind without one shows its note in its place.
local function SetSpellRegionShown(shown)
    widgets.spellExplainer:SetShown(shown)
    widgets.spellBox:SetShown(shown)
    widgets.statusText:SetShown(shown)
    widgets.catalogHost:SetShown(shown)
    if not shown then
        widgets.chipIcon:Hide()
        widgets.chipName:Hide()
    end
    widgets.kindNote:SetShown(not shown)
    if shown then
        PositionSpellPrompt()
        C_Timer.After(0, PositionSpellPrompt)
    end
end

local function UpdateSpellRegion()
    if not session then return end
    local tracker = CurrentTracker()

    local kind = ctx.kind()
    local spellKind = SAU().KindNeedsSpell(kind)
    SetSpellRegionShown(spellKind)
    if not spellKind then
        widgets.kindNote:SetText(KIND_NOTES[kind] or "")
        return
    end

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

-- A draft has nothing to rename, copy, load or delete yet: static title, no
-- icons. They appear with the tracker, and the duplicate one only for a
-- tracker in a group. Never touched while the rename box is open (a deferred
-- refresh mid-rename must not re-show an icon over it). A tracker in a group
-- of two or more gets the member carousel instead of the plain title.
local function UpdateTitle()
    if widgets.renameBox:IsShown() then return end
    local tracker = CurrentTracker()
    local gid = tracker and tracker.groupId
    widgets.inGroup = gid ~= nil
    if gid and widgets.carousel:SetContext(gid, session.trackerId) then
        widgets.carouselActive = true
        widgets.titleText:Hide()
        widgets.carousel:Show()
        widgets.SetTitleIconsShown(true)
        return
    end
    widgets.carouselActive = false
    widgets.carousel:Hide()
    widgets.titleText:Show()
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
    if SAU().KindNeedsSpell(kind) and (needCatalogRefresh or kind ~= catalogKind) then
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
    CloseEditorSpecFlyout()

    if trackerId and SAU().GetTracker(trackerId) then
        session = { trackerId = trackerId }
    else
        session = { draft = { content = {}, styling = {} } }
    end
    validationToken = validationToken + 1

    -- Show first: region rects resolve on show, and the catalog grid and tab
    -- scroll child size themselves from measured widths. RenderDynamic runs
    -- the catalog refresh once the quadrants are visible.
    frame:Show()
    needCatalogRefresh = true
    RenderDynamic()
end

function Editor.Close()
    -- Hiding an ancestor does not reliably fire OnLeave on a hovered catalog
    -- cell, which would leave its tooltip on screen.
    addon.UI.ScootAuraCDMPicker.HideTooltip()
    CloseEditorSpecFlyout()
    if frame then frame:Hide() end
    if widgets.carousel then widgets.carousel:Reset() end
    if previewStrip then previewStrip:Reset() end
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

-- /scoot debug fit walks the open editor beside the settings page.
addon.UI.Controls.RegisterFitRoot("scootaura editor", function() return frame end)

return Editor
