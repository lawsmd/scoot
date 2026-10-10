-- pvebutton.lua - a button on Blizzard's PVEFrame that opens the window
--
-- It stands level with the tabs, its right edge on PVEFrame's right edge.
-- The button is placed from an OnShow hook, after Blizzard's own pass has
-- set the tabs. The button is Scoot's own frame under PVEFrame and
-- writes nothing to Blizzard's; while the window is up, the parked PVEFrame
-- takes the button off screen with it.
local addonName, addon = ...

local GF = addon.GroupFinder
local PVEButton = {}
GF.PVEButton = PVEButton

local button

-- The height of the tabs' middle over PVEFrame's bottom edge, read from the
-- first tab's rect; a hidden tab keeps its rect
local function TabMiddle(pve)
    local tab = _G.PVEFrameTab1
    if not tab then return nil end
    local ok, top, bottom, frameBottom = pcall(function()
        return tab:GetTop(), tab:GetBottom(), pve:GetBottom()
    end)
    if not ok or type(top) ~= "number" or type(bottom) ~= "number" or type(frameBottom) ~= "number" then
        return nil
    end
    return (top + bottom) / 2 - frameBottom
end

-- Right edge on PVEFrame's right edge, level with the tabs
local function Place()
    local pve = _G.PVEFrame
    button:ClearAllPoints()
    local middle = TabMiddle(pve)
    if middle then
        button:SetPoint("RIGHT", pve, "BOTTOMRIGHT", 0, middle)
    else
        button:SetPoint("TOPRIGHT", pve, "BOTTOMRIGHT", 0, 0)
    end
end

local function Wanted()
    return addon:IsModuleEnabled("groupfinder") and GF.Setting("pveButton") ~= false
end

function PVEButton.Refresh()
    if not button then return end
    if Wanted() then
        Place()
        button:Show()
        -- The width measured at creation, under a hidden PVEFrame, comes up
        -- short of the label; measure again once the frame draws. The right
        -- anchor keeps the right edge where it is.
        C_Timer.After(0, function()
            if button:IsShown() then button:SetText(button._text) end
        end)
    else
        button:Hide()
    end
end

local function Create()
    local pve = _G.PVEFrame
    if button or not pve then return end
    local Controls = addon.UI and addon.UI.Controls
    if not Controls then return end
    -- The tab's own height, short of its art's transparent foot
    local tab = _G.PVEFrameTab1
    local okH, tabHeight = pcall(function() return tab and tab:GetHeight() end)
    local height = (okH and type(tabHeight) == "number" and tabHeight > 8) and (tabHeight - 4) or nil
    button = Controls:CreateButton({
        parent = pve,
        text = "Scoot Group Finder",
        height = height,
        borderAlpha = 0.8,
        name = "ScootPVEGroupFinderButton",
        onClick = function()
            if GF.UI then GF.UI:Open() end
        end,
    })
    if not button then return end
    button:SetAlpha(0.8)
    local okL, level = pcall(pve.GetFrameLevel, pve)
    if okL and type(level) == "number" then
        button:SetFrameLevel(level + 10)
    end
    pve:HookScript("OnShow", PVEButton.Refresh)
    PVEButton.Refresh()
end

-- From the component's initializer, so the button exists only while the
-- module is on
function PVEButton.Install()
    addon.Events.OnAddonLoaded("Blizzard_GroupFinder", Create)
end
