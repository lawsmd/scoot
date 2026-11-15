--------------------------------------------------------------------------------
-- forever/minimap/tracking.lua
-- The tracking button: Blizzard's magnifying glass in its image, a child of
-- the holder, opening Blizzard's own tracking menu (Find Herbs, Find
-- Minerals, the townsfolk). Placed like the text: "dock" is Blizzard's spot
-- left of the header plate, else one of the nine points on the map.
--
-- The menu is built from the parked button's generator, read and never
-- written: MiniMapTrackingButtonMixin:OnLoad hands it to SetupMenu, which
-- keeps it as menuGenerator. The visible replica button owns the menu, so Menu does
-- not close it for an owner that is hidden, and nothing is stored on the
-- parked cluster's tree.
--------------------------------------------------------------------------------

local addonName, addon = ...

local MR = addon.MinimapReplica
local Style = MR.Style

local Tracking = {}
MR.Tracking = Tracking

-- Blizzard's frame is 17 by 17 with the 13 by 14 button centred in it
-- (Blizzard_Minimap/Mainline/Minimap.xml, Tracking).
local BASE_SIZE = 17
local BUTTON_W, BUTTON_H = 13, 14

-- The text's rule for a nine-point position (text.lua, placeMapText).
local INSET_X = 6
local TOP_DROP = 6

local frame

local function blizzardButton()
    local cluster = _G.MinimapCluster
    return cluster and cluster.Tracking and cluster.Tracking.Button
end

local function generator()
    local b = blizzardButton()
    return b and b.menuGenerator
end

local function trackingDisabled()
    if not (C_GameRules and C_GameRules.IsGameRuleActive and Enum.GameRule and Enum.GameRule.IngameTrackingDisabled) then
        return false
    end
    local ok, disabled = pcall(C_GameRules.IsGameRuleActive, Enum.GameRule.IngameTrackingDisabled)
    return ok and disabled == true
end

local function closeMenu(self)
    if self.menu then
        self.menu:Close()
        self.menu = nil
    end
end

local function onClick(self)
    if self.menu then
        closeMenu(self)
        return
    end
    local gen = generator()
    local variants = _G.MenuVariants
    if not (gen and Menu and MenuUtil and variants) then return end
    local desc = MenuUtil.CreateRootMenuDescription(variants.GetDefaultMenuMixin())
    Menu.PopulateDescription(gen, self, desc)
    local anchor = AnchorUtil.CreateAnchor("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
    local menu = Menu.GetManager():OpenMenu(self, desc, anchor)
    if menu then
        self.menu = menu
        menu:SetClosedCallback(function() self.menu = nil end)
    end
end

-- Blizzard's tooltip, plus the entries that are on now.
local function onEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(_G.TRACKING or "Tracking", 1, 1, 1)
    local active = 0
    if C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo then
        local okN, n = pcall(C_Minimap.GetNumTrackingTypes)
        for i = 1, (okN and n or 0) do
            local ok, info = pcall(C_Minimap.GetTrackingInfo, i)
            if ok and info and info.active and info.name then
                GameTooltip:AddLine(info.name, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
                active = active + 1
            end
        end
    end
    if active == 0 and _G.MINIMAP_TRACKING_TOOLTIP_NONE then
        GameTooltip:AddLine(_G.MINIMAP_TRACKING_TOOLTIP_NONE, nil, nil, nil, true)
    end
    GameTooltip:Show()
end

--- The button, once, from display.lua's Build.
function Tracking.Build(holder)
    if frame then return end
    frame = CreateFrame("Frame", nil, holder)
    frame:SetSize(BASE_SIZE, BASE_SIZE)
    frame:SetFrameLevel(holder:GetFrameLevel() + 4)
    frame.Background = frame:CreateTexture(nil, "BACKGROUND")
    frame.Background:SetAtlas("ui-hud-minimap-button")
    frame.Background:SetAllPoints(frame)

    local button = CreateFrame("Button", nil, frame)
    button:SetPoint("CENTER")
    button:SetNormalAtlas("ui-hud-minimap-tracking-up")
    button:SetPushedAtlas("ui-hud-minimap-tracking-down")
    button:SetHighlightAtlas("ui-hud-minimap-tracking-mouseover")
    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", onEnter)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnHide", closeMenu)
    frame.Button = button
    frame:Hide()
end

function Tracking.Apply()
    local holder = Style.Frame()
    if not (holder and frame) then return end

    if Style.Get("trackingHide") == true or trackingDisabled() or not generator() then
        frame:Hide()
        return
    end

    local size = tonumber(Style.Get("trackingSize")) or BASE_SIZE
    local k = size / BASE_SIZE
    frame:SetSize(size, size)
    frame.Button:SetSize(BUTTON_W * k, BUTTON_H * k)

    local position = Style.Get("trackingPosition") or "dock"
    frame:ClearAllPoints()
    if position == "dock" then
        frame:SetPoint("RIGHT", holder.Header, "LEFT", -2, 0)
        frame:SetShown(Style.Get("dockHide") ~= true)
        return
    end
    local x = tonumber(Style.Get("trackingOffsetX")) or 0
    local y = tonumber(Style.Get("trackingOffsetY")) or 0
    if position:find("LEFT") then
        x = x + INSET_X
    elseif position:find("RIGHT") then
        x = x - INSET_X
    end
    if position:find("TOP") then y = y - TOP_DROP end
    frame:SetPoint(position, holder, position, x, y)
    frame:Show()
end

--- The frame, for the mail indicator's dock position.
function Tracking.Frame()
    return frame
end

--- Lines for /camelot map.
function Tracking.Describe(push)
    push("  tracking: position %s, hide %s, size %s, generator %s, rule off %s, shown %s",
        tostring(Style.Get("trackingPosition")), tostring(Style.Get("trackingHide")),
        tostring(Style.Get("trackingSize")), tostring(generator() ~= nil),
        tostring(trackingDisabled()), tostring(frame and frame:IsShown()))
end
