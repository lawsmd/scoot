-- window.lua - the Group Finder window: a WindowShell the size of Blizzard's
-- Premade Groups panel, one panel shown at a time, kept in step with the
-- panel Blizzard's hidden LFGListFrame has active.
--
-- The window opens by showing Blizzard's panel through its own open call
-- and parking it (core/components/groupfinder/host.lua), and it closes when
-- that panel hides, whoever hid it: the X and the game's Escape hide this
-- frame, whose OnHide hides PVEFrame; the Group Finder key, another left
-- panel and HideUIPanel hide PVEFrame, whose OnHide hook closes this frame.
-- A closing flag makes the second call of each pair a no-op.
--
-- Each panel file registers a builder in UI.panelBuilders; the window
-- builds them on first open, under a content frame the size of Blizzard's
-- panel, and SyncPanel shows the one the window's own view names, else the
-- one LFGListFrame.activePanel names. Blizzard's active panel is never
-- switched from here: a field a click of this window writes through a
-- Blizzard handler is tainted, and Blizzard's event dispatch, which reads
-- the active panel, would run tainted from then on, so that under the
-- chat lockdown its hidden panels could not index the secrets the API
-- hands them. The window shows the Blizzard panel whose boxes it hosts,
-- keeps its view, and ends the view when Blizzard moves its own panel,
-- or opens the search view when Blizzard moves to its search panel.
-- The parts every panel draws, a heading, a bordered box and a button, are
-- the helpers at the end. A button that is off says why in its tooltip, as
-- Blizzard's do; no panel carries a line of text under its box.
local addonName, addon = ...

local GF = addon.GroupFinder
local UI = {}
GF.UI = UI
UI.panelBuilders = {}

local Str = GF.Str
local SS = addon.SecretSafe

local function Controls()
    return addon.UI.Controls
end

local function Theme()
    return addon.UI.Theme
end

local function M()
    return addon.UI.Controls.Metrics()
end

-- The window's measures. The panel is wider than Blizzard's 338, so the
-- activity names and the roster fit on a row, and taller than its 440, so
-- the Dungeons filter's drawer, which stands the window's height, holds
-- its sections with room over for a season's extra one and never scrolls;
-- the rest are Blizzard's numbers, the fallbacks when the client's
-- template table does not answer, and the panel's own positions are where
-- Blizzard's XML puts them
local LAYOUT = {
    -- The list's 400, 28 for the row's sign-up button, and the role
    -- column's 150 (search.roles.width)
    panelWidth = 578,
    panelHeight = 480,
    titleHeight = 36,
    categoryRow = 46,
    buttonWidth = 135,
    -- The parked panel shares the window's strata, and its frame border
    -- stands at level 500 with the mouse on, so the window and its dialog
    -- stand above that
    windowLevel = 600,
    dialogLevel = 700,
    -- boxBottom leaves the button's height and a clear gap under the box
    panel = {
        headingX = 8, headingY = 10,
        boxTop = 40, boxBottom = 44, boxX = 4,
        buttonX = 4, buttonY = 6,
    },
    -- The category rows: the label stands in from the row's bar
    categories = {
        labelX = 6,
    },
    -- The search panel's row of box, refresh and filter, the column the
    -- rows keep on the right for the roster or the status, the lines
    -- under a row's name (a size smaller and stepped in, so the name stands
    -- out), the roster's grid (its line count sets every row's height, so
    -- a group of two stands as tall as a group of five), the counts grid a
    -- larger group shows in its place, and the filter drawer's widths and
    -- text size out of the window's right edge
    search = {
        rowY = 36, rowHeight = 26, gap = 4,
        boxTop = 70,
        filterWidth = 84,
        rightColumn = 160,
        -- The row's sign-up button at its right end, past the roster: the
        -- button's size and a gap
        quickColumn = 28,
        -- The row's + and x: small squares on the thin, quiet border the
        -- listing's applicant actions take, the glyph a size under the
        -- button face and eased at rest, so a column of them does not
        -- glare against the bands; gap is the clear room between an
        -- application's word and countdown and the x beside them, wide
        -- since the column has the room
        action = { size = 22, gap = 12, border = 1, borderAlpha = 0.45, font = 10, labelAlpha = 0.75 },
        -- Clear room between the name's right edge and either column, so
        -- a long name ends short of the icons
        columnGap = 12,
        -- The clear room between an application's word and the countdown
        -- under it; the row is tall, so the two stand apart
        statusGap = 6,
        -- A delisted group's text, at the roster's own dim
        staleAlpha = 0.5,
        nameTop = 14,
        subIndent = 10, subSize = 10,
        -- The roster's text is a size under the sublines, so the longest
        -- spec name with the crown and the rating fits the column; the
        -- crown stands under the rating's height, lifted onto the letters.
        -- The top pad is a line plus the bottom pad, so a row with one slot
        -- open has the same room above its content as below it, and the
        -- name's top sits a point above the first line
        roster = {
            lines = 5, lineHeight = 12, fontSize = 9,
            glyphWidth = 12, gap = 4, iconSize = 10,
            markWidth = 7, markHeight = 5, markY = 1,
            top = 15, bottom = 3,
        },
        -- The counts per role of a raid or another group past the grid:
        -- three lines, larger than the roster's and centred on the row,
        -- in a column as wide as an n/m line, so a raid's longer name
        -- keeps the room the five-line grid takes
        counts = {
            lines = 3, lineHeight = 16, fontSize = 11,
            glyphWidth = 16, gap = 4, iconSize = 13,
            width = 56,
        },
        -- The drawer is wide for the Dungeons filter's two columns and
        -- narrow for the language rows
        filterDrawerWidth = 500, languageDrawerWidth = 220, filterListFont = 11,
        -- Start a Group under the no-results message
        startGroupY = 16,
        -- The role column at the pane's right: the icons stacked down the
        -- top two-thirds of the column (noteSplit), enlarged from the
        -- roster's, and the note's holder across the bottom third, inset
        -- from the column's edges. The note box stands in from the holder's
        -- border by notePad on every side, so typed text clears the border;
        -- the text region inside the box is narrower than the box by
        -- Blizzard's own margin (noteTextInset); its text is a size under
        -- the value face and its bar is scaled down, since both are drawn
        -- for a dialog's wide box
        roles = {
            width = 150, iconSize = 52, iconGap = 22, noteSplit = 2 / 3,
            noteInset = 12, notePad = 6, noteTextInset = 18, noteFont = 11, noteBarScale = 0.75,
        },
    },
    -- The listing form: the dropdowns' row, the captioned title and details
    -- boxes, the playstyle, the requirement rows with an input or the voice
    -- box at their right, and the two options on one line, stacked with a
    -- gap; the details box's text region is narrower than its frame by
    -- Blizzard's own margin plus the holder's inset
    -- The requirement inputs stand under the row's height, on the holder's
    -- one-point border, with clear room between the rows
    create = {
        rowHeight = 22, detailsHeight = 46, captionHeight = 12, captionGap = 3,
        gap = 8, rowGap = 6,
        inputWidth = 64, inputHeight = 18, inputInset = 1, inputFont = 11,
        voiceWidth = 110, checkGap = 6, optionColumn = 200,
        inputMax = 9999, detailsInset = 20, finderRows = 12, coverAlpha = 0.85,
    },
    -- Your listing: the info block, as tall as its lines or the party's
    -- grid at its right, the column names over a rule, and a band per
    -- applicant with a line per member; the columns from the right, the
    -- name taking the rest; the actions column holds the status word,
    -- Invite and the x, small so they do not crowd the line
    viewer = {
        subSize = 10, lineHeight = 12, lineGap = 1, autoGap = 6, headerGap = 8,
        tagGap = 4, tagTop = 2,
        columns = { role = 56, ilvl = 44, rating = 56, actions = 70 },
        memberLine = 20, rowPad = 6, roleIcon = 14, roleGap = 2, nameSize = 11,
        inviteWidth = 48, declineWidth = 18, actionGap = 4, buttonHeight = 18, actionFont = 10,
        -- The two buttons on a thin, quiet border, so a column of them
        -- does not glare against the band
        actionBorder = 1, actionBorderAlpha = 0.45,
    },
    -- The invite dialog: Blizzard's size, taller with the offline notice
    invite = {
        width = 314, height = 210, tallHeight = 250,
        padX = 16, padTop = 10, gap = 10, lineGap = 2,
        roleSize = 16, roleGap = 4, offlineY = 48, buttonWidth = 100, buttonY = 10,
    },
}
UI.LAYOUT = LAYOUT

-- The leader's crown and the role column's icons, drawn on a result row and
-- on the listing's own grid: the addon's flat crown tinted the class color,
-- cut to its edges out of a 64 square; the Raid Manager set the group
-- frames offer, the one Blizzard art in the window
UI.LEADER_MARK = {
    file = addon.MediaPath .. "media\\textures\\crown.png",
    coords = { 0.0625, 0.9375, 0.140625, 0.796875 },
}

function UI.RoleIcons()
    local sets = addon.BarsUtils and addon.BarsUtils.ROLE_ICON_ATLASES
    return type(sets) == "table" and sets.gm or nil
end

-- A template's measure at run time, else the table's
function LAYOUT.Template(name, key, field)
    if C_XMLUtil and C_XMLUtil.GetTemplateInfo then
        local ok, info = pcall(C_XMLUtil.GetTemplateInfo, name)
        if ok and type(info) == "table" then
            local v = info[field or "height"]
            if type(v) == "number" and v > 0 then return v end
        end
    end
    return LAYOUT[key]
end

local frame
local content
local panels = {}

-- Strings on the accent, repainted together
local accentStrings = setmetatable({}, { __mode = "k" })

--------------------------------------------------------------------------------
-- Which Scoot panel Blizzard's active panel names
--------------------------------------------------------------------------------

-- The window's own view first: "search" while it searches, "create" while
-- it lists or edits; else Blizzard's active panel. Blizzard's search panel
-- names the categories: the window's search view is its own, entered by
-- its Find Group and Browse Groups, or by a Blizzard path into the search
-- panel (OnPanelSwitch), and left by its Back, which moves no Blizzard
-- panel; so Blizzard's panel may stay on its search panel after Back,
-- and the twelfth look found Back stuck there while the search panel
-- answered for it
local function ActivePanelKey()
    local lf = LFGListFrame
    if not lf then return "nothing" end
    local active = SS.plainFrame(lf.activePanel)
    if active == lf.NothingAvailable then return "nothing" end
    if UI.view == "create" then return "create" end
    if UI.view == "search" then return "search" end
    if active == lf.ApplicationViewer then return "viewer" end
    if active == lf.CategorySelection or active == lf.SearchPanel then return "categories" end
    if active == lf.EntryCreation then return "create" end
    return "nothing"
end

function UI:SyncPanel()
    if not frame or not frame:IsShown() then return end
    local key = ActivePanelKey()
    if not panels[key] then key = "nothing" end
    for k, panel in pairs(panels) do
        panel:SetShown(k == key)
    end
    self.activeKey = key
    local panel = panels[key]
    if panel and panel.Refresh then panel:Refresh() end
end

function UI:SetView(view)
    UI.view = view
    self:SyncPanel()
end

-- Blizzard moved its own active panel (the listing up, the listing gone,
-- the check on show): the window's view ends with it, and the Blizzard
-- panels the window showed go back out of sight. Blizzard's own ways into
-- its search panel (the quest log's Find Group, the scenario tracker's)
-- run a search the player asked for, so the search view opens on them
function UI:OnPanelSwitch()
    if UI.Create and UI.Create.Close then UI.Create:Close() end
    if UI.Search and UI.Search.Close then UI.Search:Close() end
    UI.view = nil
    local lf = LFGListFrame
    if lf and SS.plainFrame(lf.activePanel) == lf.SearchPanel then UI.view = "search" end
    self:SyncPanel()
end

function UI:GetPanel(key)
    return panels[key]
end

function UI:IsShown()
    return frame ~= nil and frame:IsShown()
end

function UI:GetFrame()
    return frame
end

--------------------------------------------------------------------------------
-- The one panel this file owns: nothing available
--------------------------------------------------------------------------------

local function BuildNothing(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)
    panel:Hide()
    local empty = Controls().CreateEmptyState({ parent = panel, text = "" })
    empty:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -LAYOUT.panel.boxTop)
    empty:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, LAYOUT.panel.boxBottom)
    function panel:Refresh()
        local text
        if IsRestrictedAccount and IsRestrictedAccount() then
            text = Str("ERR_RESTRICTED_ACCOUNT_LFG_LIST_TRIAL", "Not available on this account")
        elseif C_LFGList.HasActivityList and C_LFGList.HasActivityList() then
            text = Str("NO_LFG_LIST_AVAILABLE", "Nothing available")
        else
            text = Str("LFG_LIST_LOADING", "Loading")
        end
        empty:SetMessage(text)
    end
    return panel
end

--------------------------------------------------------------------------------
-- Build, open, close
--------------------------------------------------------------------------------

local function Build()
    local m = M()
    local inset = m.windowInset or 3
    local width = LAYOUT.panelWidth + inset * 2
    local height = LAYOUT.panelHeight + LAYOUT.titleHeight + inset

    frame = addon.UI.WindowShell.Create({
        name = addon.Brand .. "GroupFinderFrame",
        width = width,
        height = height,
        role = "window",
        title = "GROUP FINDER",
        titleFontRole = "header",
        titleSize = 15,
        titleAlign = "center",
        titleHeight = LAYOUT.titleHeight,
        escape = "special",
        onClose = function() UI:Close("button") end,
        positionKey = "groupFinderPosition",
        level = LAYOUT.windowLevel,
    })
    frame:Hide()
    frame._skinName = addon.UI.Skin.ActiveName()

    content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -LAYOUT.titleHeight)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
    frame._content = content

    frame:HookScript("OnHide", function() UI:Close("hide") end)

    panels = {}
    panels.nothing = BuildNothing(content)
    for key, builder in pairs(UI.panelBuilders) do
        panels[key] = builder(content)
    end

    -- The window outlives accent changes and skin switches; the strings
    -- follow the accent, and a new skin drops the frame for a rebuild on
    -- the next open
    Theme():Subscribe("GroupFinderWindow", function(r, g, b)
        for fs in pairs(accentStrings) do
            fs:SetTextColor(r, g, b, 1)
        end
        if frame and frame._skinName ~= addon.UI.Skin.ActiveName() then
            UI:Close("skin")
            UI:Destroy()
        end
    end)
end

function UI:Destroy()
    if not frame then return end
    for _, panel in pairs(panels) do
        if panel.Cleanup then panel:Cleanup() end
    end
    frame:CleanupShell()
    frame:Hide()
    frame:SetParent(nil)
    frame = nil
    content = nil
    panels = {}
end

function UI:Open()
    if frame and frame:IsShown() then return end
    if C_LFGInfo and C_LFGInfo.CanPlayerUseGroupFinder then
        local ok, can = pcall(C_LFGInfo.CanPlayerUseGroupFinder)
        if ok and can == false then return end
    end
    if not LFGListFrame then return end
    if not frame then Build() end
    if not GF.Host.Open() then return end
    GF.Host.InstallHooks()
    self.closing = false
    frame:Show()
    frame:Raise()
    self:SyncPanel()
end

-- reason: "button", "hide" (the frame went away, the game's Escape among
-- the ways), "pveframe" (Blizzard's panel went away first), "skin",
-- "toggle"
function UI:Close(reason)
    if self.closing then return end
    self.closing = true
    if UI.Create and UI.Create.Close then UI.Create:Close() end
    if UI.Search and UI.Search.Close then UI.Search:Close() end
    UI.view = nil
    GF.Host.Close(reason ~= "pveframe")
    if frame and frame:IsShown() then frame:Hide() end
    self.closing = false
end

function UI:Toggle()
    if frame and frame:IsShown() then
        self:Close("toggle")
    else
        self:Open()
    end
end

--------------------------------------------------------------------------------
-- The parts every panel draws
--------------------------------------------------------------------------------

-- A string on the accent, in a font role
function UI.AccentText(parent, role, size)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    Theme():ApplyFont(fs, role or "header", size)
    fs:SetTextColor(Theme():GetAccentColor())
    fs:SetJustifyH("LEFT")
    accentStrings[fs] = true
    return fs
end

-- A dim string in a font role
function UI.DimText(parent, role, size)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    Theme():ApplyFont(fs, role or "desc", size)
    local dr, dg, db = Theme():GetDimTextColor()
    fs:SetTextColor(dr, dg, db, 1)
    fs:SetJustifyH("LEFT")
    return fs
end

-- A string in the primary color
function UI.PrimaryText(parent, role, size)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    Theme():ApplyFont(fs, role or "label", size)
    local pr, pg, pb = Theme():GetPrimaryTextColor()
    fs:SetTextColor(pr, pg, pb, 1)
    fs:SetJustifyH("LEFT")
    return fs
end

-- A caption over a field, dim and small
function UI.MakeCaption(parent, text)
    local fs = UI.DimText(parent, "miniLabel")
    fs:SetText(text or "")
    return fs
end

-- The heading at a panel's top-left, where Blizzard's label sits
function UI.MakeHeading(panel, text)
    local fs = UI.AccentText(panel, "header")
    fs:SetPoint("TOPLEFT", panel, "TOPLEFT", LAYOUT.panel.headingX, -LAYOUT.panel.headingY)
    fs:SetText(text or "")
    return fs
end

-- The box under the heading: the collapsible section's fill inside a closed
-- border, where Blizzard draws its inset; top overrides the panel's
function UI.MakeBox(panel, top)
    local C = Controls()
    local m = M().collapsible or {}
    local box = CreateFrame("Frame", nil, panel)
    box._bg = C.AddBackground(box, { color = "collapsible" })
    box._border = C.CreateBorder(box, {
        thickness = m.borderWidth or 1,
        alpha = m.borderAlpha or 0.6,
        corners = "overlap",
    })
    box:SetPoint("TOPLEFT", panel, "TOPLEFT", LAYOUT.panel.boxX, -(top or LAYOUT.panel.boxTop))
    box:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -LAYOUT.panel.boxX, LAYOUT.panel.boxBottom)
    return box
end

-- tooltip: a string or a function returning one, shown while the button is
-- off as well, which is where a button says why it is off
function UI.MakeButton(parent, text, onClick, width, tooltip)
    return Controls():CreateButton({
        parent = parent,
        text = text,
        width = width,
        onClick = onClick,
        tooltip = tooltip,
    })
end

-- A panel frame the size of the content, hidden until SyncPanel names it
function UI.MakePanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)
    panel:Hide()
    return panel
end

--------------------------------------------------------------------------------
-- Command
--------------------------------------------------------------------------------

addon:RegisterSlashCommand({
    name = "lfg",
    help = "open or close the Group Finder window",
    handler = function()
        if not addon:IsModuleEnabled("groupfinder") then
            return addon.Commands.NotAvailable("Group Finder")
        end
        UI:Toggle()
    end,
})
