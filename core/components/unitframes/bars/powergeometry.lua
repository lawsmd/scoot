--------------------------------------------------------------------------------
-- bars/powergeometry.lua
-- Player power bar width, height, and offset scaling, out of combat only. The
-- bar's stock width, height, and anchor points are captured once in FrameState,
-- restored first on every pass, then the configured percentages and offsets are
-- re-applied. Target and Focus take the restore path only.
--------------------------------------------------------------------------------

local addonName, addon = ...

addon.BarsPowerGeometry = addon.BarsPowerGeometry or {}
local Geometry = addon.BarsPowerGeometry

local Util = addon.ComponentsUtil
local Resolvers = addon.BarsResolvers
local Textures = addon.BarsTextures
local FS = addon.FrameState

local resolvePowerMask = Resolvers.resolvePowerMask
local ensureMaskOnBarTexture = Textures.ensureMaskOnBarTexture

local function getState(frame)
    return FS.Get(frame)
end

-- The bar's anchor points as { point, relativeTo, relativePoint, x, y } rows.
local function capturePoints(pb)
    local pts = {}
    local n = (pb.GetNumPoints and pb:GetNumPoints()) or 0
    for i = 1, n do
        local p, rel, rp, x, y = pb:GetPoint(i)
        table.insert(pts, { p, rel, rp, x or 0, y or 0 })
    end
    return pts
end

-- Re-anchor pb from captured points with every x moved by dx and every y by dy.
-- dx = dy = 0 restores the capture.
local function shiftPoints(pb, pts, dx, dy)
    if not (pb and pts and pb.ClearAllPoints and pb.SetPoint) then return end
    pcall(pb.ClearAllPoints, pb)
    for _, pt in ipairs(pts) do
        pcall(pb.SetPoint, pb, pt[1], pt[2], pt[3] or pt[1], (pt[4] or 0) + dx, (pt[5] or 0) + dy)
    end
end

-- Re-anchor pb from captured points so the bar grows downward by dy with its
-- top edge fixed: BOTTOM anchors move by the whole dy, CENTER anchors by half.
local function growPointsDown(pb, pts, dy)
    if not (pb and pts and pb.ClearAllPoints and pb.SetPoint) then return end
    pcall(pb.ClearAllPoints, pb)
    for _, pt in ipairs(pts) do
        local p, rel, rp, x, y = pt[1], pt[2], pt[3], pt[4], pt[5]
        local yy = y or 0
        local anchor = tostring(p or "")
        local relp = tostring(rp or "")
        if string.find(anchor, "BOTTOM", 1, true) or string.find(relp, "BOTTOM", 1, true) then
            yy = (y or 0) - (dy or 0)
        elseif string.find(anchor, "CENTER", 1, true) or string.find(relp, "CENTER", 1, true) then
            yy = (y or 0) - ((dy or 0) * 0.5)
        end
        pcall(pb.SetPoint, pb, p, rel, rp or p, x or 0, yy)
    end
end

-- Width: Player only. Pet is excluded (secret values); Target and Focus are
-- not supported and only get their capture restored.
local function applyWidth(unit, pb, cfg, inCombat)
    local canScale = (unit == "Player")

    local pbState = getState(pb)
    if not pbState then return end
    if canScale and not inCombat then
        local pct = tonumber(cfg.powerBarWidthPct) or 100
        local tex = pb.GetStatusBarTexture and pb:GetStatusBarTexture()
        local mask = resolvePowerMask(unit)
        local isMirroredUnit = (unit == "Target" or unit == "Focus")
        local scaleX = math.min(1.5, math.max(0.5, (pct or 100) / 100))

        -- Capture original PB width once
        if pb and not pbState.ufOrigWidth then
            if pb.GetWidth then
                local ok, w = pcall(pb.GetWidth, pb)
                if ok and w and not issecretvalue(w) then pbState.ufOrigWidth = w end
            end
        end

        -- Capture original PB anchors
        if pb and not pbState.ufOrigPoints then
            pbState.ufOrigPoints = capturePoints(pb)
        end

        -- Always restore to the captured baseline first to avoid cumulative offsets.
        if pb and pbState.ufOrigWidth and pb.SetWidth then
            pcall(pb.SetWidth, pb, pbState.ufOrigWidth)
        end
        shiftPoints(pb, pbState.ufOrigPoints, 0, 0)

        if pct > 100 then
            -- Widen the status bar frame
            if pb and pb.SetWidth and pbState.ufOrigWidth then
                pcall(pb.SetWidth, pb, pbState.ufOrigWidth * scaleX)
            end

            -- Reposition the frame to control growth direction
            if pb and pbState.ufOrigWidth then
                local dx = (pbState.ufOrigWidth * (scaleX - 1))
                if dx and dx ~= 0 then
                    if isMirroredUnit then
                        shiftPoints(pb, pbState.ufOrigPoints, -dx, 0)
                    else
                        shiftPoints(pb, pbState.ufOrigPoints, dx, 0)
                    end
                end
            end

            -- DO NOT touch the StatusBar texture - it is managed by the StatusBar widget.
            -- REMOVE the mask entirely when widening - it causes rendering artifacts.
            if tex and mask and tex.RemoveMaskTexture then
                pcall(tex.RemoveMaskTexture, tex, mask)
            end
            -- NOTE: Do NOT call SetValue to "refresh" the texture - it taints the protected StatusBar
            -- and causes "blocked from an action" errors when Blizzard later calls Show().
            -- The StatusBar refreshes automatically when its dimensions change.
        elseif pct < 100 then
            -- Narrow the status bar frame
            if pb and pb.SetWidth and pbState.ufOrigWidth then
                pcall(pb.SetWidth, pb, pbState.ufOrigWidth * scaleX)
            end
            -- Reposition so mirrored bars keep the portrait edge anchored
            if pb and pbState.ufOrigWidth then
                local shrinkDx = pbState.ufOrigWidth * (1 - scaleX)
                if shrinkDx and shrinkDx ~= 0 and isMirroredUnit then
                    shiftPoints(pb, pbState.ufOrigPoints, shrinkDx, 0)
                end
            end
            -- Ensure mask remains applied when narrowing
            if pb and mask then
                ensureMaskOnBarTexture(pb, mask)
            end
        else
            -- Restore power bar frame
            if pb and pbState.ufOrigWidth and pb.SetWidth then
                pcall(pb.SetWidth, pb, pbState.ufOrigWidth)
            end
            shiftPoints(pb, pbState.ufOrigPoints, 0, 0)
            -- Re-apply mask to texture at original dimensions
            if pb and mask then
                ensureMaskOnBarTexture(pb, mask)
            end
        end
    elseif not inCombat then
        -- Not scalable (Target/Focus with default fill): ensure restoration of any prior width/anchors/mask
        local mask = resolvePowerMask(unit)
        -- Restore power bar frame
        if pb and pbState.ufOrigWidth and pb.SetWidth then
            pcall(pb.SetWidth, pb, pbState.ufOrigWidth)
        end
        shiftPoints(pb, pbState.ufOrigPoints, 0, 0)
        -- Re-apply mask to texture at original dimensions
        if pb and mask then
            ensureMaskOnBarTexture(pb, mask)
        end
    end
end

-- Height: Player only, with the same restore-first rule. The stock fill and
-- mask heights are captured alongside the bar's.
local function applyHeight(unit, pb, cfg, inCombat)
    -- Skip all Power Bar height scaling while in combat; defer to the next
    -- out-of-combat styling pass instead to avoid taint.
    if inCombat then return end
    local canScale = (unit == "Player")

    local pbState = getState(pb)
    if not pbState then return end
    if canScale then
        local pct = tonumber(cfg.powerBarHeightPct) or 100
        local widthPct = tonumber(cfg.powerBarWidthPct) or 100
        local tex = pb.GetStatusBarTexture and pb:GetStatusBarTexture()
        local mask = resolvePowerMask(unit)
        local texState = getState(tex)
        local maskState = getState(mask)

        -- Capture originals once (height and anchor points)
        if tex and texState and not texState.origCapturedHeight then
            if tex.GetHeight then
                local ok, h = pcall(tex.GetHeight, tex)
                if ok and h and not issecretvalue(h) then texState.origHeight = h end
            end
            -- Texture anchor points already captured by width scaling
            texState.origCapturedHeight = true
        end
        if mask and maskState and not maskState.origCapturedHeight then
            if mask.GetHeight then
                local ok, h = pcall(mask.GetHeight, mask)
                if ok and h and not issecretvalue(h) then maskState.origHeight = h end
            end
            -- Mask anchor points already captured by width scaling
            maskState.origCapturedHeight = true
        end

        -- Anchor points should already be captured by width scaling
        -- If not, capture them now
        if pb and not pbState.ufOrigPoints then
            pbState.ufOrigPoints = capturePoints(pb)
        end

        local scaleY = math.max(0.5, math.min(2.0, pct / 100))

        -- Capture original PowerBar height once
        if pb and not pbState.ufOrigHeight then
            if pb.GetHeight then
                local ok, h = pcall(pb.GetHeight, pb)
                if ok and h and not issecretvalue(h) then pbState.ufOrigHeight = h end
            end
        end

        -- Always restore to original state first
        if pb and pbState.ufOrigHeight and pb.SetHeight then
            pcall(pb.SetHeight, pb, pbState.ufOrigHeight)
        end
        shiftPoints(pb, pbState.ufOrigPoints, 0, 0)

        if pct ~= 100 then
            -- Scale the status bar frame height
            if pb and pb.SetHeight and pbState.ufOrigHeight then
                pcall(pb.SetHeight, pb, pbState.ufOrigHeight * scaleY)
            end

            -- Reposition the frame to grow downward (keep top fixed)
            if pb and pbState.ufOrigHeight then
                local dy = (pbState.ufOrigHeight * (scaleY - 1))
                if dy and dy ~= 0 then
                    growPointsDown(pb, pbState.ufOrigPoints, dy)
                end
            end

            -- DO NOT touch the StatusBar texture - it is managed by the StatusBar widget.
            -- REMOVE the mask entirely when scaling - it causes rendering artifacts.
            if tex and mask and tex.RemoveMaskTexture then
                pcall(tex.RemoveMaskTexture, tex, mask)
            end

            if Util and Util.ApplyFullPowerSpikeScale then
                Util.ApplyFullPowerSpikeScale(pb, scaleY)
            end
            -- NOTE: Do NOT call SetValue to "refresh" the texture - it taints the protected StatusBar
            -- and causes "blocked from an action" errors when Blizzard later calls Show().
            -- The StatusBar refreshes automatically when its dimensions change.
        else
            -- Restore (already done above in the restore-first step)
            -- Re-apply mask ONLY if both Width and Height are at 100%
            -- (Width scaling removes the mask, so it is not re-applied while Width is still scaled)
            if pb and mask and widthPct == 100 then
                ensureMaskOnBarTexture(pb, mask)
            end

            if Util and Util.ApplyFullPowerSpikeScale then
                Util.ApplyFullPowerSpikeScale(pb, 1)
            end
        end
    else
        -- Not scalable (Target/Focus with default fill): ensure restoration of any prior height/anchors
        -- Restore power bar frame
        if pb and pbState.ufOrigHeight and pb.SetHeight then
            pcall(pb.SetHeight, pb, pbState.ufOrigHeight)
        end
        shiftPoints(pb, pbState.ufOrigPoints, 0, 0)
        if Util and Util.ApplyFullPowerSpikeScale then
            Util.ApplyFullPowerSpikeScale(pb, 1)
        end
    end
end

-- Offsets: additive X and Y over a capture of the bar's points taken on the
-- first pass, after width and height have anchored it. Zero offsets restore
-- that capture.
local function applyOffsets(pb, cfg, inCombat)
    if inCombat then return end
    local offsetX = tonumber(cfg.powerBarOffsetX) or 0
    local offsetY = tonumber(cfg.powerBarOffsetY) or 0

    local pbState = getState(pb)
    if pbState and not pbState.powerBarOrigPoints then
        pbState.powerBarOrigPoints = capturePoints(pb)
    end
    shiftPoints(pb, pbState and pbState.powerBarOrigPoints or nil, offsetX, offsetY)
end

-- Called from applyForUnit (bars.lua) once the unit's power bar has resolved and
-- its textures are styled; inCombat is that pass's cached InCombatLockdown().
function Geometry.apply(unit, pb, cfg, inCombat)
    applyWidth(unit, pb, cfg, inCombat)
    applyHeight(unit, pb, cfg, inCombat)
    applyOffsets(pb, cfg, inCombat)
end

return Geometry
