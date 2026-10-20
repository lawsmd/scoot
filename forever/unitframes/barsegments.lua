--------------------------------------------------------------------------------
-- forever/unitframes/barsegments.lua
-- The two bar pieces beside the heal prediction that the client's own frames
-- draw: the temporary max health loss on the health bar, and the mana cost
-- of the spell being cast on the power bar. A spec asks for each by name, so
-- the Modern frames carry them and the Classic ones, which vanilla draws
-- without, do not.
--
-- The max health loss is TempMaxHealthLossMixin's work done here: the loss
-- percent from GetUnitTotalModifiedMaxHealthPercent, the health bar narrowed
-- to what is left, a reverse-fill bar over the rest, and on the player the
-- divider at the seam. The percent is plain on the API's word, and is
-- screened: a secret, a missing function or an error leaves the bar full
-- width and the loss hidden, which is the client's look with no loss. The
-- showTempMaxHealthLoss CVar switches it off, as it switches the client's.
--
-- The mana cost is the Personal Resource Display's segment: reverse fill
-- from the power fill's right end, ranged to the power's max and fed the
-- cost, a plain number, so the bar's own value is never read or reduced.
-- Retail lowers the bar by the cost instead, which is arithmetic on
-- UnitPower.
--
-- Both sit under their bar's mask, as the client masks them.
--------------------------------------------------------------------------------

local addonName, addon = ...

local UF = addon.UnitFrames
local Art = UF.Art

local Segments = {}
UF.BarSegments = Segments

-- The client's own minimum for the divider (TempMaxHealthLossMixin).
local MIN_PERCENT_SHOW_DIVIDER = 0.015

-- ManaCostPredictionBarTemplate's colour, an engine global; the mana
-- prediction blue stands in.
local COST_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"

local function costColor()
    local c = _G.MANAPREDICTIONBLUE or _G.POWERBAR_PREDICTION_COLOR_MANA
    if type(c) == "table" and c.GetRGBA then return c:GetRGBA() end
    return 0, 0.447, 1, 1
end

local function plain(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok or issecretvalue(value) then return nil end
    return value
end

local function unsnapped(tex)
    tex:SetTexelSnappingBias(0)
    tex:SetSnapToPixelGrid(false)
    return tex
end

--------------------------------------------------------------------------------
-- Max health loss
--------------------------------------------------------------------------------

-- spec.Bars.health.loss = {
--     atlas,                   the loss bar's fill
--     y, h,                    the container under the bar: its top below the
--                              bar's and its height, where they differ
--     divider = { atlas, shadow, mask },  the player's seam
-- }
-- The container is the bar's full width, anchored by its top left as the
-- bar is, so it holds still while the bar narrows.
local function buildLoss(inst, def)
    local bar = inst.healthBar
    local s = inst.spec.Bars.health
    local atlas = Art.ResolveAtlasName(def.atlas)
    if not atlas then
        inst.healthLossMissing = def.atlas
        return nil
    end

    local loss = CreateFrame("StatusBar", nil, inst.frame)
    loss:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, def.y or 0)
    loss:SetSize(s.w, def.h or s.h)
    loss:SetFrameLevel(bar:GetFrameLevel())
    loss:SetStatusBarTexture(atlas)
    loss:SetReverseFill(true)
    loss:SetMinMaxValues(0, 1)
    loss:SetValue(0)
    local fill = unsnapped(loss:GetStatusBarTexture())
    if inst.healthMask then fill:AddMaskTexture(inst.healthMask) end
    loss:Hide()

    -- The divider's line spans the container and its mask cuts the one slice
    -- at the seam; the shadow sits on the same spot. Over the bars, on the
    -- art frame. The client stretches the mask 1 unit to close a gap under
    -- this atlas.
    local d = def.divider
    if d then
        local holder = CreateFrame("Frame", nil, inst.artFrame)
        holder:SetPoint("TOPLEFT", loss, "TOPLEFT", 0, 2)
        holder:SetPoint("BOTTOMRIGHT", loss, "BOTTOMRIGHT", 0, -2)
        local line = holder:CreateTexture(nil, "OVERLAY")
        line:SetAllPoints(holder)
        local shadow = holder:CreateTexture(nil, "OVERLAY")
        local mask = holder:CreateMaskTexture()
        if Art.SetAtlas(line, d.atlas, false) and Art.SetAtlas(mask, d.mask, true) then
            Art.SetAtlas(shadow, d.shadow, true)
            mask:SetHeight(mask:GetHeight() + 1)
            line:AddMaskTexture(mask)
            holder.shadow = shadow
            holder.mask = mask
            holder:Hide()
            inst.healthLossDivider = holder
        else
            holder:Hide()
        end
    end
    return loss
end

local function placeDivider(inst, x)
    local d = inst.healthLossDivider
    if not d then return end
    d.shadow:ClearAllPoints()
    d.shadow:SetPoint("CENTER", d, "LEFT", x, 0)
    d.mask:ClearAllPoints()
    d.mask:SetPoint("CENTER", d, "LEFT", x, 0)
    d:SetShown(x ~= 0)
end

-- The fraction of max health lost: 0 when the frame shows no loss.
local function lossFraction(inst)
    if inst.previewStandIn then return 0 end
    if GetCVarBool and GetCVarBool("showTempMaxHealthLoss") == false then return 0 end
    local percent = plain(_G.GetUnitTotalModifiedMaxHealthPercent, inst.unit)
    if type(percent) ~= "number" then return 0 end
    return math.min(math.max(percent, 0), 1)
end

local function paintLoss(inst)
    local loss = inst.healthLoss
    local full = inst.spec.Bars.health.w
    local fraction = lossFraction(inst)
    -- A floor of 1: a zero-width bar has no rect for the fill to anchor to.
    local width = math.max(full * (1 - fraction), 1)
    if width ~= inst.healthWidth then
        inst.healthWidth = width
        inst.healthBar:SetWidth(width)
        -- The heal prediction segments are the bar's width (healprediction.lua,
        -- the host's size).
        if inst.healPrediction then UF.HealPrediction.Apply(inst) end
    end
    loss:SetValue(fraction)
    loss:SetShown(fraction > 0)
    placeDivider(inst, fraction > MIN_PERCENT_SHOW_DIVIDER and full * (1 - fraction) or 0)
end

--------------------------------------------------------------------------------
-- Mana cost
--------------------------------------------------------------------------------

--- The spell the unit is casting and its cost in the power it shows: both
--- plain, and anything else reads as no cost. The Personal Resource
--- Display reads the player's through this too.
function Segments.ReadCost(unit)
    local spellID = plain(function() return select(9, UnitCastingInfo(unit)) end)
    if type(spellID) ~= "number" then return 0 end
    local powerType = plain(UnitPowerType, unit)
    if type(powerType) ~= "number" then return 0 end
    local costs = plain(C_Spell.GetSpellPowerCost, spellID)
    if type(costs) ~= "table" then return 0 end
    for _, info in pairs(costs) do
        if type(info) == "table" and info.type == powerType and type(info.cost) == "number" then
            return info.cost
        end
    end
    return 0
end

-- spec.Bars.power.cost = true, with statusAtlas as the fill, the member
-- the client's ManaCostPredictionBar names. Anchored to the fill on purpose:
-- the segment ends where the fill ends.
local function buildCost(inst)
    local power = inst.powerBar
    local s = inst.spec.Bars.power
    local seg = CreateFrame("StatusBar", nil, power)
    seg:SetFrameLevel(power:GetFrameLevel())
    local atlas = s.statusAtlas and Art.ResolveAtlasName(s.statusAtlas)
    seg:SetStatusBarTexture(atlas or COST_TEXTURE)
    seg:SetStatusBarColor(costColor())
    local fill = unsnapped(seg:GetStatusBarTexture())
    if inst.powerMask then fill:AddMaskTexture(inst.powerMask) end
    seg:SetReverseFill(true)
    seg:SetMinMaxValues(0, 1)
    seg:SetValue(0)
    seg:SetPoint("RIGHT", power:GetStatusBarTexture(), "RIGHT")
    seg:SetSize(s.w, s.h)
    seg:Hide()
    return seg
end

local function paintCost(inst)
    local seg = inst.manaCost
    local cost = 0
    if not inst.previewStandIn and inst.powerBar:IsShown() then
        local ok, value = pcall(Segments.ReadCost, inst.unit)
        if ok and type(value) == "number" then cost = value end
    end
    inst.lastCost = cost
    if cost > 0 then
        seg:SetMinMaxValues(0, UnitPowerMax(inst.unit))
        seg:SetValue(cost)
        seg:Show()
    else
        seg:Hide()
    end
end

--------------------------------------------------------------------------------
-- The painter's calls
--------------------------------------------------------------------------------

-- The events beyond the painter's own; frame.lua registers them on a frame
-- that built either piece, guarded, since a client may lack one.
Segments.LOSS_EVENTS = { "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" }
Segments.COST_EVENTS = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED" }

local COST_EVENT = {}
for _, event in ipairs(Segments.COST_EVENTS) do COST_EVENT[event] = true end

--- Build what the spec asks for. Frame.Build, after the bars and the art
--- frame.
function Segments.Build(inst)
    local bars = inst.spec.Bars
    if bars.health.loss then inst.healthLoss = buildLoss(inst, bars.health.loss) end
    if bars.power.cost then inst.manaCost = buildCost(inst) end
end

--- Repaint both from the unit. Frame.Paint, before the heal prediction,
--- which takes the width the loss leaves.
function Segments.Update(inst)
    if inst.healthLoss then paintLoss(inst) end
    if inst.manaCost then paintCost(inst) end
end

--- The cast events, which repaint the cost alone. True when handled.
function Segments.OnEvent(inst, event)
    if not COST_EVENT[event] then return false end
    if inst.manaCost then paintCost(inst) end
    return true
end

--- Lines for /camelot state.
function Segments.Describe(inst)
    local loss
    if inst.healthLoss then
        loss = string.format("built, width %s", tostring(inst.healthWidth))
    elseif inst.healthLossMissing then
        loss = "atlas missing: " .. inst.healthLossMissing
    else
        loss = "none on this frame"
    end
    local cost = inst.manaCost and ("built, last cost " .. tostring(inst.lastCost or 0)) or "none on this frame"
    return loss, cost
end
