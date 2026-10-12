--------------------------------------------------------------------------------
-- forever/actionbars/endcaps.lua
-- The end caps: an upright gryphon (Alliance) or wyvern (Horde) on each side
-- of a cluster with End Caps on, hidden for a neutral character. A cap is 90
-- percent of the container's height times the cluster's End Cap Scale,
-- centered on it vertically, with its inner edge on the container's outer
-- edge. The caps are sized, never scaled, so a larger cap grows outward and
-- the inner anchor holds at every scale. Each is a region of the container,
-- so a drag, a dynamic scale and a fade carry them.
--
-- One file per creature ships, facing right for the left cap; the right cap
-- is the same file mirrored through its texture coordinates.
--------------------------------------------------------------------------------

local _, addon = ...

local ActionBars = addon.ActionBars
local EndCaps = {}
ActionBars.EndCaps = EndCaps

-- The cap's height as a share of the cluster's, at End Cap Scale 100.
local HEIGHT_SHARE = 0.9

-- The art sits in the top left of a 512 x 1024 canvas; w and h are its
-- pixel size there. inset is how far the cap reaches over the bar, as a
-- share of its own width: the gryphon's inner edge is flat, the wyvern's is
-- its outermost spikes, and the eye pass decides whether either moves.
local CANVAS_W, CANVAS_H = 512, 1024
local MEDIA = addon.MediaPath .. "forever\\media\\actionbars\\"
local ART = {
    Alliance = { file = MEDIA .. "gryphon.png", w = 446, h = 880, inset = 0 },
    Horde = { file = MEDIA .. "wyvern.png", w = 512, h = 880, inset = 0 },
}

local caps = {} -- container -> { left, right }

local function Cap(container)
    local pair = caps[container]
    if not pair then
        pair = {}
        for _, side in ipairs({ "left", "right" }) do
            local t = container:CreateTexture(nil, "ARTWORK")
            t:SetSnapToPixelGrid(false)
            t:SetTexelSnappingBias(0)
            pair[side] = t
        end
        caps[container] = pair
    end
    return pair
end

function EndCaps.Hide(container)
    local pair = caps[container]
    if not pair then return end
    pair.left:Hide()
    pair.right:Hide()
end

--- Size, anchor and show the pair beside a laid-out container, or hide it.
--- Returns the line /camelot actionbars prints under the cluster.
function EndCaps.Apply(cluster, container)
    local art = cluster.endCaps and ART[UnitFactionGroup("player") or ""]
    if not art then
        EndCaps.Hide(container)
        return cluster.endCaps and "end caps hidden: no faction" or "end caps off"
    end

    local h = container:GetHeight() * HEIGHT_SHARE * (cluster.endCapScale or 100) / 100
    local w = h * art.w / art.h
    local u, v = art.w / CANVAS_W, art.h / CANVAS_H
    local inset = art.inset * w

    local pair = Cap(container)
    local left, right = pair.left, pair.right
    for _, t in ipairs({ left, right }) do
        t:SetTexture(art.file)
        t:SetSize(w, h)
        t:ClearAllPoints()
        t:Show()
    end
    left:SetTexCoord(0, u, 0, v)
    left:SetPoint("RIGHT", container, "LEFT", inset, 0)
    right:SetTexCoord(u, 0, 0, v)
    right:SetPoint("LEFT", container, "RIGHT", -inset, 0)

    return string.format("end caps %.0fx%.0f %s, scale %d", w, h,
        art == ART.Alliance and "gryphon" or "wyvern", cluster.endCapScale or 100)
end

-- A neutral Pandaren who picks a side gets the side's caps.
addon.Events.On(ActionBars.OWNER, "NEUTRAL_FACTION_SELECT_RESULT", function()
    if ActionBars.Clusters and ActionBars.Clusters.IsBuilt() then
        ActionBars.Clusters.Rebuild()
    end
end)
