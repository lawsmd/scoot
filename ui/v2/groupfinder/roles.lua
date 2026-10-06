-- roles.lua - the role column at the search pane's right: the three role
-- icons the player signs up with, and the note that goes with every
-- application.
--
-- The roles are the client's own, read with GetLFGRoles and written with
-- SetLFGRoles from an icon's click as Blizzard's role buttons do, so the
-- choice holds across sessions and matches Blizzard's own dialog and the
-- Dungeon Finder; a role the class cannot fill is locked. The icons are
-- the Raid Manager set the rows draw, uncolored and stacked down the
-- column: a chosen role on the accent, an open one dim, a locked one
-- dimmer and taking no click. The note is Blizzard's own box across the
-- column's bottom third, hosted for the panel's life: its dialog frame is
-- held shown out of sight (core/components/groupfinder/host.lua) and the
-- C side reads the text on ApplyToGroup. A row's sign-up button
-- is off while no role is chosen, and says so in its tooltip; the column
-- carries no text of its own.
local addonName, addon = ...

local GF = addon.GroupFinder
local UI = GF.UI
local LAYOUT = UI.LAYOUT
local Host = GF.Host
local Str = GF.Str

local Roles = {}
UI.Roles = Roles

local ROLE_ORDER = { "TANK", "HEALER", "DAMAGER" }

-- The icon's alpha by state; a hovered open role comes up toward chosen
local ALPHA = { on = 1, off = 0.45, hover = 0.7, locked = 0.18 }

local function Controls()
    return addon.UI.Controls
end

local function Theme()
    return addon.UI.Theme
end

local function M()
    return addon.UI.Controls.Metrics()
end

local column
local holder
local icons = {}        -- role -> its button
local available = {}    -- role -> the class can fill it
local chosen = {}       -- role -> chosen, as last read or clicked
local onChange

local function RoleWord(role)
    local word = _G[role]
    return type(word) == "string" and word or role
end

local function Paint(role)
    local button = icons[role]
    if not button then return end
    local theme = Theme()
    local avail = available[role] == true
    local icon = button._icon
    if avail and chosen[role] then
        local r, g, b = theme:GetAccentColor()
        icon:SetVertexColor(r, g, b, 1)
        icon:SetAlpha(ALPHA.on)
    else
        local r, g, b = theme:GetDimTextColor()
        icon:SetVertexColor(r, g, b, 1)
        icon:SetAlpha(avail and ALPHA.off or ALPHA.locked)
    end
    button:SetEnabled(avail)
end

local function PaintAll()
    for _, role in ipairs(ROLE_ORDER) do Paint(role) end
end

local function MakeIcon(tray, role, index)
    local L = LAYOUT.search.roles
    local button = CreateFrame("Button", nil, tray)
    button:SetSize(L.iconSize, L.iconSize)
    button:SetPoint("TOP", tray, "TOP", 0, -(index - 1) * (L.iconSize + L.iconGap))
    button:SetMotionScriptsWhileDisabled(true)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(button)
    local atlases = UI.RoleIcons()
    if atlases and atlases[role] then
        icon:SetAtlas(atlases[role])
    end
    icon:SetDesaturated(true)
    button._icon = icon
    button:SetScript("OnClick", function() Roles:Toggle(role) end)
    button:SetScript("OnEnter", function(b)
        if available[role] and not chosen[role] then icon:SetAlpha(ALPHA.hover) end
        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        GameTooltip:SetText(RoleWord(role))
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function(b)
        if GameTooltip:GetOwner() == b then GameTooltip:Hide() end
        Paint(role)
    end)
    icons[role] = button
    return button
end

-- The column down the box's right edge, inside its border: a rule on its
-- left, the icons stacked and centred in its top two-thirds, the note's
-- holder across the bottom third. The split is taken from the window's
-- measures, since the column's own height resolves after the build
-- opts.onChange  called after a click changed the choice
function Roles.Build(box, opts)
    opts = opts or {}
    local C = Controls()
    local L = LAYOUT.search.roles
    local m = M().collapsible or {}
    local bw = m.borderWidth or 1
    onChange = opts.onChange

    column = CreateFrame("Frame", nil, box)
    column:SetWidth(L.width)
    column:SetPoint("TOPRIGHT", box, "TOPRIGHT", -bw, -bw)
    column:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -bw, bw)
    column._rule = C.CreateBorder(column, { sides = { "LEFT" }, thickness = bw, alpha = m.borderAlpha or 0.6 })

    local boxHeight = LAYOUT.panelHeight - LAYOUT.search.boxTop - LAYOUT.panel.boxBottom
    local noteTop = math.floor(boxHeight * L.noteSplit + 0.5)

    local tray = CreateFrame("Frame", nil, column)
    tray:SetSize(L.iconSize, #ROLE_ORDER * L.iconSize + (#ROLE_ORDER - 1) * L.iconGap)
    tray:SetPoint("CENTER", column, "TOP", 0, -noteTop / 2)
    for i, role in ipairs(ROLE_ORDER) do
        MakeIcon(tray, role, i)
    end

    holder = CreateFrame("Frame", nil, column)
    Host.DressHolder(holder)
    holder:SetPoint("TOPLEFT", column, "TOPLEFT", L.noteInset, -noteTop)
    holder:SetPoint("BOTTOMRIGHT", column, "BOTTOMRIGHT", -L.noteInset, L.noteInset)

    PaintAll()
    return column
end

-- The roles the class can fill, and the client's own choice among them
function Roles:Refresh()
    if not column then return end
    local tank, healer, dps = C_LFGList.GetAvailableRoles()
    available.TANK, available.HEALER, available.DAMAGER = tank == true, healer == true, dps == true
    local _, t, h, d = GetLFGRoles()
    chosen.TANK, chosen.HEALER, chosen.DAMAGER = t == true, h == true, d == true
    PaintAll()
end

-- A click flips the role and writes the set back, as Blizzard's role
-- buttons do; the client's role update reads it back through Refresh
function Roles:Toggle(role)
    if not available[role] then return end
    chosen[role] = not chosen[role]
    PlaySound(chosen[role] and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    local leader = GetLFGRoles()
    SetLFGRoles(leader, chosen.TANK == true, chosen.HEALER == true, chosen.DAMAGER == true)
    PaintAll()
    if onChange then onChange() end
end

-- The three roles as an application carries them: a chosen role the class
-- can fill, as Blizzard's Sign Up masks each by its button being shown
function Roles:GetRoles()
    return (available.TANK and chosen.TANK) == true,
        (available.HEALER and chosen.HEALER) == true,
        (available.DAMAGER and chosen.DAMAGER) == true
end

function Roles:HasRole()
    local tank, healer, damage = self:GetRoles()
    return tank or healer or damage
end

-- The reason a sign-up is off for the roles, or nil
function Roles:Block()
    if self:HasRole() then return nil end
    return Str("LFG_LIST_MUST_SELECT_ROLE", "Choose at least one role")
end

-- Blizzard's note box into the holder, its dialog frame shown first so the
-- box renders; the text region takes its width here, since it took its
-- own once at load, and its text and bar come down to the holder's size
function Roles:TakeNote()
    if not holder then return end
    local dialog = LFGListApplicationDialog
    if not (dialog and dialog.Description) then return end
    if not Host.ShowDialogFrame() then return end
    local L = LAYOUT.search.roles
    Host.Take("note", dialog.Description, holder, {
        editBox = dialog.Description.EditBox,
        artKeys = Host.SCROLL_BOX_ART,
        editBoxWidth = L.width - 2 * L.noteInset - L.noteTextInset,
        fontSize = L.noteFont,
        scrollBarScale = L.noteBarScale,
    })
end

function Roles:ReleaseNote()
    Host.Release("note")
    Host.HideDialogFrame()
end

GF.Listen("roles", function()
    if column and column:IsVisible() then Roles:Refresh() end
end)
