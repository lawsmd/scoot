--------------------------------------------------------------------------------
-- forever/statusbars/mixins.lua
-- The two globals frames.xml names. Each lists Blizzard's mixin first and
-- this one after it, so these keys win and every other key is Blizzard's
-- (Blizzard_StatusTrackingBar/Shared/StatusTrackingManager.lua and the
-- client's StatusTrackingManagerOverrides.lua).
--
-- What is overridden and why:
-- * The manager finds its containers by name. Blizzard's are children with
--   parentArray="barContainers"; Camelot's sit in holders of their own, so
--   Edit Mode and Dynamic Layouts move each bar alone.
-- * A container finds its manager by name, for the same reason, where
--   Blizzard's reads GetParent().
-- * UpdateShownState drops ManageFramePositions and the Edit Mode bottom
--   stack event: both are UIParent's layout pass, which a Camelot call would
--   run tainted, and neither positions a Camelot bar.
-- * GetExpectedWidth multiplies the client's width by the bar's Width setting,
--   which InitializeBars, CheckForLayoutChange and the dividers all read.
-- * RegisterEvents waits for the build. Blizzard's manager draws from its
--   OnLoad, so its first fill fades a visible container in; the Camelot
--   holders are hidden until display.lua shows them, and a fill before that
--   would run the fade on a frame that draws nothing. With the feature off
--   the events are never registered and the holders stay hidden and quiet.
--------------------------------------------------------------------------------

local addonName, addon = ...

CamelotStatusTrackingManagerMixin = {}

function CamelotStatusTrackingManagerMixin:OnLoad()
    self.barContainers = {}
    for index, name in ipairs({ "CamelotStatusBar1", "CamelotStatusBar2" }) do
        local holder = _G[name]
        self.barContainers[index] = holder and holder.Container
    end
    StatusTrackingManagerMixin.OnLoad(self)
end

-- Blizzard's OnLoad calls this; the build calls RegisterBlizzardEvents once
-- the holders draw.
function CamelotStatusTrackingManagerMixin:RegisterEvents()
end

function CamelotStatusTrackingManagerMixin:RegisterBlizzardEvents()
    StatusTrackingManagerMixin.RegisterEvents(self)
end

CamelotStatusTrackingContainerMixin = {}

function CamelotStatusTrackingContainerMixin:GetStatusTrackingManager()
    return _G.CamelotStatusTrackingBarManager
end

-- widthPercent is written by display.lua's width apply; the XML load runs
-- InitializeBars before the saved variables exist, at Blizzard's width.
function CamelotStatusTrackingContainerMixin:GetExpectedWidth()
    local base = StatusTrackingBarContainerMixin.GetExpectedWidth(self)
    return base * (self.widthPercent or 100) / 100
end

function CamelotStatusTrackingContainerMixin:UpdateShownState()
    self:SetShown(self.shownBarIndex ~= StatusTrackingBarInfo.BarsEnum.None or self.isInEditMode)
    local manager = self:GetStatusTrackingManager()
    if manager then manager:CheckForLayoutChange() end
    local SB = addon.StatusBars
    if SB and SB.Display then SB.Display.OnShownBarChanged(self.barIndex) end
end
