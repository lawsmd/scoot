--------------------------------------------------------------------------------
-- forever/objectivetracker/overflow.lua
-- The Current Objectives pane's bottom fade: when the pane is too short for
-- every current quest, the last lines it draws fade toward its bottom edge.
--
-- Blizzard's tracker has no scrollbar. A module lays blocks out until one does
-- not fit, then skips that block and every block after it and sets
-- hasSkippedBlocks (ObjectiveTrackerModuleMixin:AddBlock); nothing on screen
-- says so. The fade is that signal.
--
-- A FontString takes no mask and no vertical alpha gradient, so the fade is
-- stepped per region: each objective line, quest name and right-edge frame
-- takes an alpha from how far its center sits above the content's bottom.
-- Block frames are never written: the turn-in animation owns a block's alpha
-- (ObjectiveTrackerAnimBlockMixin). The quest item buttons stand outside the
-- pane (itembutton.lua) and keep full alpha.
--------------------------------------------------------------------------------

local addonName, addon = ...

local OT = addon.ObjectiveTracker

local Overflow = {}
OT.Overflow = Overflow

local MODULE = "CamelotCurrentQuestObjectiveTracker"
local CONTAINER = "CamelotCurrentObjectiveTracker"

local BAND = 48          -- the fade's height above the content's bottom, in the pane's units
local BAND_SHARE = 0.6   -- never more than this share of the drawn content
local FLOOR = 0.15       -- the alpha at the bottom edge

local faded = {}         -- region -> true: every region this file dimmed, restored each pass
local last = { truncated = false, regions = 0 }

local function restore()
    for region in pairs(faded) do
        region:SetAlpha(1)
    end
    wipe(faded)
end

local function centerY(region)
    local top, bottom = region:GetTop(), region:GetBottom()
    if not (top and bottom) then return nil end
    return (top + bottom) / 2
end

local function fade(region, bottom, band)
    if not region:IsShown() then return end
    local y = centerY(region)
    if not y then return end
    local t = (y - bottom) / band
    if t >= 1 then return end
    if t < 0 then t = 0 end
    region:SetAlpha(FLOOR + (1 - FLOOR) * t)
    faded[region] = true
    last.regions = last.regions + 1
end

--- After every layout of the pane's container. Restores the last pass, then
--- fades again while the module skipped a block.
function Overflow.Apply()
    restore()
    last.regions = 0
    local module = _G[MODULE]
    last.truncated = module and module:IsShown() and module:HasSkippedBlocks() and not module:IsCollapsed() or false
    if not last.truncated then return end

    local lastBlock, firstBlock = module.lastBlock, module.firstBlock
    if not (lastBlock and firstBlock) then return end
    local bottom, top = lastBlock:GetBottom(), firstBlock:GetTop()
    if not (bottom and top and top > bottom) then return end
    local band = math.min(BAND, (top - bottom) * BAND_SHARE)

    for _, child in ipairs({ module.ContentsFrame:GetChildren() }) do
        if child.usedLines then
            -- A block: its quest name and its lines, never the block itself.
            if child:IsShown() then
                if child.HeaderText then fade(child.HeaderText, bottom, band) end
                for _, line in ipairs({ child:GetChildren() }) do
                    fade(line, bottom, band)
                end
            end
        else
            -- The POI buttons, the item slots, the progress and timer bars.
            fade(child, bottom, band)
        end
    end

    -- A Deep Shadow copy follows its string's drawn alpha only when told.
    if addon.FontPair and addon.FontPair.RefreshInheritedAlpha then
        addon.FontPair.RefreshInheritedAlpha()
    end
end

local installed = false

--- Once, from Current.Install.
function Overflow.Install()
    if installed then return end
    local container = _G[CONTAINER]
    if not (container and _G[MODULE]) then return end
    installed = true
    hooksecurefunc(container, "Update", Overflow.Apply)
end

function Overflow.Dump(push)
    push("overflow: truncated %s, %d regions faded", tostring(last.truncated), last.regions)
end
