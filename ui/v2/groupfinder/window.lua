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
-- panel, and SyncPanel shows the one LFGListFrame.activePanel names. The
-- parts every panel draws, a heading, a bordered box and a button, are the
-- helpers at the end. A button that is off says why in its tooltip, as
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
-- activity names and the roster fit on a row; the rest are Blizzard's
-- numbers, the fallbacks when the client's template table does not answer,
-- and the panel's own positions are where Blizzard's XML puts them
local LAYOUT = {
    panelWidth = 400,
    panelHeight = 440,
    titleHeight = 36,
    categoryRow = 46,
    dialogWidth = 306,
    dialogHeight = 203,
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
        -- Clear room between the name's right edge and either column, so
        -- a long name ends short of the icons
        columnGap = 12,
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
    },
}
UI.LAYOUT = LAYOUT

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

local function ActivePanelKey()
    local lf = LFGListFrame
    if not lf then return "nothing" end
    local active = SS.plainFrame(lf.activePanel)
    if not active then return "nothing" end
    if active == lf.CategorySelection then return "categories" end
    if active == lf.SearchPanel then return "search" end
    if active == lf.NothingAvailable then return "nothing" end
    return "placeholder"
end

function UI:SyncPanel()
    if not frame or not frame:IsShown() then return end
    local key = ActivePanelKey()
    if not panels[key] then key = "placeholder" end
    for k, panel in pairs(panels) do
        panel:SetShown(k == key)
    end
    self.activeKey = key
    local panel = panels[key]
    if panel and panel.Refresh then panel:Refresh() end
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
-- The two panels this file owns: nothing available, and the stand-in for the
-- listing and creation panels
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

-- The listing and creation panels are drawn by Blizzard's window until the
-- window draws them; this hands the player over and back
local function BuildPlaceholder(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)
    panel:Hide()
    local empty = Controls().CreateEmptyState({
        parent = panel,
        text = "Your listing is shown in the game's own window.",
    })
    empty:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -LAYOUT.panel.boxTop)
    empty:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, LAYOUT.panel.boxBottom)
    local button = UI.MakeButton(panel, "Open the game's window", function()
        UI:Close("handback")
    end)
    button:SetPoint("BOTTOM", panel, "BOTTOM", 0, LAYOUT.panel.buttonY)
    function panel:Refresh() end
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
    panels.placeholder = BuildPlaceholder(content)
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
-- the ways), "pveframe" (Blizzard's panel went away first), "handback"
-- (Blizzard's panel stays up and visible), "skin", "toggle"
function UI:Close(reason)
    if self.closing then return end
    self.closing = true
    if UI.SignUp and UI.SignUp.Hide then UI.SignUp:Hide() end
    GF.Host.Close(reason ~= "pveframe" and reason ~= "handback")
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
