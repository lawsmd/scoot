--------------------------------------------------------------------------------
-- forever/personalresourcedisplay/mixins.lua
-- CamelotPersonalResourceDisplayMixin, the one global frames.xml names in a
-- mixin= attribute, so it has to exist before the XML parses.
--
-- The layout half of Blizzard's PersonalResourceDisplayMixin, transcribed:
-- the setters its Edit Mode calls to size the frame, and the reflow behind
-- them. Everything that reads a unit is left out, because those reads
-- return secrets in this addon's context; display.lua feeds the bars
-- instead. The alternate power bar and the class container are not in the
-- Camelot tree, so their branches are gone too.
--
-- Two departures from the transcription. Where Blizzard reads a bar's
-- height back, this keeps the number it set: a StatusBar fed a secret can
-- throw on its own geometry getters. And each bar lives in a plain
-- container the setters size and fills it on both anchors, so a border
-- anchored to the container reads plain geometry (style.lua, "Borders").
--------------------------------------------------------------------------------

CamelotPersonalResourceDisplayMixin = {}

-- Blizzard's GetMinimumBarPadding and GetMinimumFrameHeight.
local MINIMUM_PADDING = 4
local MINIMUM_FRAME_HEIGHT = 15

function CamelotPersonalResourceDisplayMixin:OnLoad()
    -- The XML width, before any child is fed: a plain read.
    self.defaultBarWidth = self:GetWidth()
    self.barWidthPercent = 100
    self.healthBarHeight = self.HealthBarsContainer:GetHeight()
    self.powerBarHeight = self.PowerBarContainer:GetHeight()
    self.barPadding = 0

    -- Blizzard's SetupHealthBar: the loss bar over the container's width.
    local container = self.HealthBarsContainer
    container.TempMaxHealthLoss:InitializeMaxHealthLossBar(container, container.healthBar)

    self:UpdateBarWidth()
    self:UpdatePowerBarAnchor()
    self:UpdateFrameHeight()
end

function CamelotPersonalResourceDisplayMixin:GetBarPadding()
    return (self.barPadding or 0) + MINIMUM_PADDING
end

function CamelotPersonalResourceDisplayMixin:UpdateBarWidth()
    local width = self.defaultBarWidth * (self.barWidthPercent or 100) / 100
    self:SetWidth(width)
    self.HealthBarsContainer:SetWidth(width)
    self.PowerBarContainer:SetWidth(width)
end

function CamelotPersonalResourceDisplayMixin:SetBarWidth(barWidthPercent)
    self.barWidthPercent = barWidthPercent
    self:UpdateBarWidth()
end

function CamelotPersonalResourceDisplayMixin:SetHealthBarHeight(barHeight)
    self.healthBarHeight = barHeight
    self.HealthBarsContainer:SetHeight(barHeight)
    self:UpdateFrameHeight()
end

function CamelotPersonalResourceDisplayMixin:SetPowerBarHeight(barHeight)
    self.powerBarHeight = barHeight
    self.PowerBarContainer:SetHeight(barHeight)
    self:UpdateFrameHeight()
end

function CamelotPersonalResourceDisplayMixin:UpdatePowerBarAnchor()
    self.PowerBarContainer:ClearAllPoints()
    if self.hideHealth then
        self.PowerBarContainer:SetPoint("TOP", self, "TOP", 0, 0)
    else
        self.PowerBarContainer:SetPoint("TOP", self.HealthBarsContainer, "BOTTOM", 0, -self:GetBarPadding())
    end
end

function CamelotPersonalResourceDisplayMixin:SetBarPadding(padding)
    self.barPadding = padding
    self:UpdatePowerBarAnchor()
    self:UpdateFrameHeight()
end

function CamelotPersonalResourceDisplayMixin:SetHideHealth(hideHealth)
    self.hideHealth = hideHealth
    self.HealthBarsContainer:SetShown(not hideHealth)
    self:UpdatePowerBarAnchor()
    self:UpdateFrameHeight()
end

function CamelotPersonalResourceDisplayMixin:SetHidePower(hidePower)
    self.hidePower = hidePower
    self.PowerBarContainer:SetShown(not hidePower)
    self:UpdateFrameHeight()
end

function CamelotPersonalResourceDisplayMixin:UpdateFrameHeight()
    local totalHeight = 0
    if not self.hideHealth then
        totalHeight = totalHeight + (self.healthBarHeight or 0)
    end
    if not self.hidePower then
        if not self.hideHealth then
            totalHeight = totalHeight + self:GetBarPadding()
        end
        totalHeight = totalHeight + (self.powerBarHeight or 0)
    end
    self:SetHeight(math.max(totalHeight, MINIMUM_FRAME_HEIGHT))
end
