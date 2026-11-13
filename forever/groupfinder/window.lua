--------------------------------------------------------------------------------
-- forever/groupfinder/window.lua
-- The group finder's window: Blizzard's parent frame rebuilt as a frame the
-- addon owns. The frame, the close button, the eye in the portrait and the
-- side tabs are made from Blizzard's own templates; the tabs' contents are
-- built by the files after this one, each registering a builder. The eye is
-- tinted bronze and carries the addon's mark, so the window is told from
-- Blizzard's at a glance.
--
-- Blizzard's frame is a managed panel. This one is a plain frame at a saved
-- spot, shown and hidden here, closed by Escape through UISpecialFrames: a
-- panel opened or closed from addon code runs Forever's frame controls
-- manager on the addon's path.
--------------------------------------------------------------------------------

local addonName, addon = ...

local LFG = addon.ForeverGroupFinder
local Data = LFG.Data
local Host = LFG.Host
local DB = addon.DB

local UI = {}
LFG.UI = UI

local LAYOUT = LFG.LAYOUT
local POSITION_KEY = "groupFinderWindow"

-- Tab index -> { build = fn(parent) returning the tab's frame, icon, tooltip }.
-- A tab with no builder is not drawn.
UI.tabs = {}

local frame
local eye
local sideTabs = {}
local tabFrames = {}
local selected = 1

function UI.RegisterTab(index, def)
    UI.tabs[index] = def
end

function UI:GetFrame()
    return frame
end

--------------------------------------------------------------------------------
-- Position: one spot for the account
--------------------------------------------------------------------------------

local function RestorePosition()
    local global = DB.Global()
    local saved = global and global[POSITION_KEY]
    frame:ClearAllPoints()
    if type(saved) == "table" and saved.point then
        frame:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point, saved.x or 0, saved.y or 0)
    else
        local d = LAYOUT.window.default
        frame:SetPoint(d[1], UIParent, d[1], d[2], d[3])
    end
end

local function SavePosition()
    local global = DB.Global()
    if not global then return end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    if not point then return end
    global[POSITION_KEY] = { point = point, relativePoint = relativePoint, x = x, y = y }
end

--------------------------------------------------------------------------------
-- The eye
--------------------------------------------------------------------------------

-- Still with no listing up, awake with one, as Blizzard's portrait is
local function UpdateEye()
    if not (eye and eye.SetStaticMode) then return end
    local listed = Data.HasEntry()
    eye:SetStaticMode(not listed)
    if listed then
        eye:StartInitialAnimation()
    else
        eye:StopAnimating()
    end
end

-- Every texture of the eye, its ring, its flipbooks and its glows, grayed and
-- multiplied by the bronze. The eye is this window's own instance of the
-- template; Blizzard's stays green.
local function TintEye(region)
    local tint = LFG.EYE_TINT
    for _, texture in ipairs({ region:GetRegions() }) do
        if texture:IsObjectType("Texture") then
            texture:SetDesaturated(true)
            texture:SetVertexColor(tint[1], tint[2], tint[3])
        end
    end
    for _, child in ipairs({ region:GetChildren() }) do
        TintEye(child)
    end
end

-- The addon's mark on the eye's lower right, in front of it. Each tab frame
-- is a portrait frame whose border and ring sit 500 levels up, so the mark
-- goes above that.
local function BuildMark(anchor)
    local path = (addon.Logo and addon.Logo.bronze) or addon.MinimapIcon
    if not path then return end
    local m = LAYOUT.portrait.mark
    local holder = CreateFrame("Frame", nil, frame)
    holder:SetSize(m.size, m.size)
    holder:SetPoint("CENTER", anchor, "BOTTOMRIGHT", m.x, m.y)
    holder:SetFrameLevel(frame:GetFrameLevel() + m.level)
    local mark = holder:CreateTexture(nil, "OVERLAY")
    mark:SetAllPoints(holder)
    mark:SetTexture(path)
end

local function BuildEye()
    local ok, made = pcall(CreateFrame, "Button", LFG.FRAME_NAME .. "Portrait", frame, "LFGEyeBigTemplate")
    if not ok or not made then
        -- The mark still says whose window this is
        local spot = CreateFrame("Frame", nil, frame)
        spot:SetSize(LAYOUT.portrait.size, LAYOUT.portrait.size)
        spot:SetPoint("CENTER", frame, "TOPLEFT", LAYOUT.portrait.x, LAYOUT.portrait.y)
        BuildMark(spot)
        return
    end
    eye = made
    TintEye(eye)
    BuildMark(eye)
    eye:SetSize(LAYOUT.portrait.size, LAYOUT.portrait.size)
    eye:SetPoint("CENTER", frame, "TOPLEFT", LAYOUT.portrait.x, LAYOUT.portrait.y)
    -- Blizzard's sits in the HIGH strata, over every other panel; this one
    -- stays in the window's strata, above the tab frames
    eye:SetFrameLevel(frame:GetFrameLevel() + 30)
    if eye.OnLoad then eye:OnLoad() end
    eye:SetScript("OnUpdate", eye.OnUpdate)
    eye:SetScript("OnEnter", eye.OnEnter)
    eye:SetScript("OnLeave", eye.OnLeave)
    eye:SetScript("OnClick", eye.OnClick)
    eye:Show()
end

--------------------------------------------------------------------------------
-- Tabs
--------------------------------------------------------------------------------

local function ApplyTabIcon(tab, def)
    local icon = tab.Icon
    if not icon then return end
    icon:SetTexture(def.icon)
    -- Forever's template sizes the icon to the tab's interior (fillToInterior,
    -- set by Blizzard's tab template) and crops it under the tab's mask; a
    -- size set here would undo that
    if tab.UpdateIconInterior then
        tab:UpdateIconInterior()
    else
        local crop = LAYOUT.sideTabs.crop
        icon:SetSize(LAYOUT.sideTabs.icon, LAYOUT.sideTabs.icon)
        icon:SetTexCoord(crop, 1 - crop, crop, 1 - crop)
    end
end

local function UpdateSideTabs()
    for index, tab in pairs(sideTabs) do
        if tab.SetChecked then tab:SetChecked(index == selected) end
        -- A template whose SetChecked swaps the icon for an atlas loses the
        -- file; it goes back on after it
        ApplyTabIcon(tab, UI.tabs[index])
    end
end

function UI:SelectTab(index)
    if not UI.tabs[index] then index = 1 end
    selected = index
    if not frame then return end
    for i, def in pairs(UI.tabs) do
        if i == index and not tabFrames[i] then
            tabFrames[i] = def.build(frame)
        end
        local tabFrame = tabFrames[i]
        if tabFrame then tabFrame:SetShown(i == index) end
    end
    UpdateSideTabs()
end

function UI:GetSelectedTab()
    return selected
end

local function BuildSideTabs()
    local previous
    local order = {}
    for index in pairs(UI.tabs) do order[#order + 1] = index end
    table.sort(order)
    for _, index in ipairs(order) do
        local def = UI.tabs[index]
        local ok, tab = pcall(CreateFrame, "Frame", nil, frame, "LFGVanillaRightTabTemplate")
        if ok and tab then
            tab:SetID(index)
            tab.tooltipText = def.tooltip
            if previous then
                tab:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, LAYOUT.sideTabs.gap)
            else
                tab:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, LAYOUT.sideTabs.y)
            end
            ApplyTabIcon(tab, def)
            -- The template's own handler switches Blizzard's frame; this
            -- one replaces it
            if tab.SetCustomOnMouseUpHandler then
                tab:SetCustomOnMouseUpHandler(function(_, button, upInside)
                    if button == "LeftButton" and upInside then UI:SelectTab(index) end
                end)
            end
            sideTabs[index] = tab
            previous = tab
        end
    end
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local function Build()
    if frame then return true end
    frame = CreateFrame("Frame", LFG.FRAME_NAME, UIParent)
    frame:SetSize(LAYOUT.window.width, LAYOUT.window.height)
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:Hide()
    RestorePosition()
    table.insert(UISpecialFrames, LFG.FRAME_NAME)

    local close = CreateFrame("Button", LFG.FRAME_NAME .. "CloseButton", frame, "UIPanelCloseButtonDefaultAnchors")
    close:SetFrameLevel(frame:GetFrameLevel() + 30)
    -- The template's click closes a managed panel; this frame is not one
    close:SetScript("OnClick", function() UI:Close() end)

    -- The title bar drags the window. Each tab's frame fills the window and
    -- takes the mouse, so the handle stands above them.
    local drag = CreateFrame("Frame", nil, frame)
    drag:SetPoint("TOPLEFT", frame, "TOPLEFT", LAYOUT.titleDrag.left, 0)
    drag:SetPoint("TOPRIGHT", frame, "TOPRIGHT", LAYOUT.titleDrag.right, 0)
    drag:SetHeight(LAYOUT.titleDrag.height)
    drag:SetFrameLevel(frame:GetFrameLevel() + 30)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() frame:StartMoving() end)
    drag:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        SavePosition()
    end)

    BuildEye()
    BuildSideTabs()

    frame:SetScript("OnShow", function()
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
        UpdateEye()
    end)
    frame:SetScript("OnHide", function()
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
        Host.ReleaseComment()
    end)
    return true
end

-- A tab's own frame: Blizzard's portrait frame with no close button, filling
-- the window, as each of Blizzard's three subframes is
function UI.MakeTabFrame(parent)
    local tab = CreateFrame("Frame", nil, parent, "PortraitFrameTemplateNoCloseButton")
    tab:SetAllPoints(parent)
    tab:EnableMouse(true)
    tab:Hide()
    local title = tab.TitleContainer and tab.TitleContainer.TitleText
    if title then title:SetText(LFG_TITLE) end
    return tab
end

--------------------------------------------------------------------------------
-- Open, close, toggle
--------------------------------------------------------------------------------

local function Refuse(message)
    if UIErrorsFrame and message then
        UIErrorsFrame:AddMessage(message, 1, 0.1, 0.1, 1)
    end
end

function UI:Open()
    if InCombatLockdown() then
        Refuse(ERR_NOT_IN_COMBAT)
        return false
    end
    if C_LFGInfo and C_LFGInfo.CanPlayerUsePremadeGroup then
        local canUse, reason = C_LFGInfo.CanPlayerUsePremadeGroup()
        if not canUse then
            Refuse(reason)
            return false
        end
    end
    if not Host.Ready() then
        Refuse(ERR_LFG_NO_LFG_OBJECT)
        return false
    end
    if not Build() then return false end
    frame:Show()
    frame:Raise()
    UI:SelectTab(selected)
    return true
end

function UI:Close()
    if frame and frame:IsShown() then frame:Hide() end
end

function UI:Toggle()
    if frame and frame:IsShown() then
        UI:Close()
    else
        UI:Open()
    end
end

function UI:IsShown()
    return frame ~= nil and frame:IsShown()
end

Data.Listen("entry", function()
    if frame then UpdateEye() end
end)

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

addon:RegisterSlashCommand({
    name = "lfg",
    help = "open or close the group finder window",
    handler = function() UI:Toggle() end,
})

addon:RegisterDebugCommand({
    name = "lfg",
    help = "the group finder window: Blizzard's finder, the comment box's lease, the listing and the form",
    handler = function()
        local lines, push = addon.DebugLines()
        push("window built: %s, shown: %s, tab: %d", tostring(frame ~= nil), tostring(UI:IsShown()), selected)
        push("listing up: %s, may edit: %s, in a home group: %s, chat lockdown: %s",
            tostring(Data.HasEntry()), tostring(Data.CanEdit()), tostring(Data.InHomeGroup()),
            tostring(Data.Lockdown()))
        local entry = Data.Entry()
        if entry then
            push("  listed activities: %s", table.concat(entry.activityIDs, ", "))
        end
        Host.Dump(push)
        if LFG.Listing and LFG.Listing.Dump then LFG.Listing.Dump(push) end
        if LFG.Browse and LFG.Browse.Dump then LFG.Browse.Dump(push) end
        addon.DebugShowWindow(addon.Brand .. " group finder", lines)
    end,
})
