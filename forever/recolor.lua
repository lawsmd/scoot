--------------------------------------------------------------------------------
-- forever/recolor.lua
-- Blizzard's gray art turned the Forever bronze at runtime, with no bundled
-- file.
--
-- The texture is drawn twice in the same place. The base is desaturated and
-- multiplied by TINT. A multiply can only darken, so an additive copy carrying
-- LIGHT puts the lit edge back. Both scale with the gray underneath, and the
-- eye sees their sum: TINT + LIGHT * LIGHT_ALPHA = (1.0, 0.68, 0.40), hue 28,
-- the midtone of Forever's own metal.
--
-- forever/unitframes/art.lua carries the same three numbers for its border
-- styles and predates this file. Change them together.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Recolor = {}
addon.Recolor = Recolor

Recolor.TINT = { 0.70, 0.46, 0.26 }
Recolor.LIGHT = { 1.0, 0.73, 0.47 }
Recolor.LIGHT_ALPHA = 0.30

--- The additive copy of a region: same def, one sublevel up, hidden until
--- Apply shows it. `build` is the region reader (addon.UnitFrames.Art.BuildRegion).
function Recolor.BuildLight(build, host, def)
    local copy = {}
    for k, v in pairs(def) do copy[k] = v end
    copy.blend = "ADD"
    copy.sublevel = (def.sublevel or 0) + 1
    copy.hidden = true
    return build(host, copy)
end

--- Dress a base texture and its light in bronze, or return both to the file's
--- own colors. The caller keeps the two on the same file, size and tex coords.
--- `lightAlpha` replaces LIGHT_ALPHA for art whose gray is darker or lighter
--- than the unit frame borders the numbers were tuned on.
function Recolor.Apply(base, light, bronze, lightAlpha)
    local tint, lit = Recolor.TINT, Recolor.LIGHT
    base:SetDesaturated(bronze and true or false)
    if bronze then
        base:SetVertexColor(tint[1], tint[2], tint[3])
    else
        base:SetVertexColor(1, 1, 1)
    end
    if not light then return end
    if bronze then
        light:SetDesaturated(true)
        light:SetVertexColor(lit[1], lit[2], lit[3], lightAlpha or Recolor.LIGHT_ALPHA)
        light:Show()
    else
        light:Hide()
    end
end
