--------------------------------------------------------------------------------
-- forever/unitframes/auras.lua
-- The buff and debuff icons on the Classic unit frames, on addon.AuraRow.
--
-- Vanilla's layout, from TargetFrame.lua, TargetFrame.xml, PetFrame.xml and
-- the target of target template on origin/classic_era:
--   * target and focus: up to 32 buffs and 16 debuffs in lines that wrap at
--     122, under the frame, or over it with buffsOnTop. A friendly unit lists
--     its buffs first; a hostile one its debuffs.
--   * target of target: four debuffs in a 2 by 2 grid off the right edge.
--   * pet: four debuffs in a row under the bars.
--   * player: none. Vanilla's player auras are BuffFrame's. The rows here are
--     a Camelot addition, off by default, laid out as the target's.
-- Each icon carries a reversed cooldown swipe and a stack count over 1. A
-- debuff wears UI-Debuff-Overlays in its dispel school's color, and a buff the
-- player can steal or purge wears the additive Stealable glow.
--
-- Two things vanilla does that the container cannot: the smaller icon for another caster's aura, and the hostile
-- NPC filter that hides other players' debuffs. Both need a per-aura read,
-- and the container keeps its aura data to itself; nothing here reads one.
--
-- The containers are children of inst.frame, so the unit watch that hides the
-- frame hides them, and the Dynamic Layouts opacity rides along.
--------------------------------------------------------------------------------

local addonName, addon = ...

local UF = addon.UnitFrames
local AuraRow = addon.AuraRow
local Settings = UF.Settings

local Auras = {}
UF.Auras = Auras

local DEBUFF_BORDER = "Interface\\Buttons\\UI-Debuff-Overlays"
local DEBUFF_BORDER_COORDS = { 0.296875, 0.5703125, 0, 0.515625 }
local STEALABLE_GLOW = "Interface\\TargetingFrame\\UI-TargetingFrame-Stealable"
-- The glow is 24 on a 21 icon in TargetBuffFrameTemplate.
local STEALABLE_SCALE = 24 / 21
-- TargetBuffFrameTemplate puts the count 3 past the icon's corner and the
-- debuff template 5, which clears its border.
local COUNT_X = { Buffs = 3, Debuffs = 5 }

local UnitIsFriend = _G.UnitIsFriend

local function plain(fn, ...)
    local ok, value = pcall(fn, ...)
    if not ok or issecretvalue(value) then return nil end
    return value
end

local function get(inst, ...)
    return Settings.Aura(inst.key, ...)
end

local function isFull(inst)
    return Settings.SURFACE[inst.key].auras == "full"
end

local function groupsOf(inst)
    return isFull(inst) and { "Buffs", "Debuffs" } or { "Debuffs" }
end

local function iconDims(inst)
    local size = tonumber(get(inst, "iconSize")) or Settings.AURA_DEFAULTS[inst.key].iconSize
    local shape = tonumber(get(inst, "shape")) or 0
    if shape ~= 0 and addon.IconRatio then
        return addon.IconRatio.CalculateDimensions(size, shape)
    end
    return size, size
end

-- Crop, not stretch, a non-square icon. The engine only ever sets the texture
-- on a bound icon, so the coordinates survive every aura.
local function cropIcon(tex, w, h)
    local aspect = w / h
    local l, r, t, b = 0, 1, 0, 1
    if aspect > 1 then
        local cut = (1 - 1 / aspect) / 2
        t, b = cut, 1 - cut
    elseif aspect < 1 then
        local cut = (1 - aspect) / 2
        l, r = cut, 1 - cut
    end
    tex:SetTexCoord(l, r, t, b)
end

--------------------------------------------------------------------------------
-- Settings reads
--------------------------------------------------------------------------------

local function friendly(inst)
    return plain(UnitIsFriend, "player", inst.unit) ~= false
end

local function rowShown(inst, group)
    if inst.previewStandIn then return false end
    if not get(inst, "enabled") then return false end
    return get(inst, group:lower(), "show") ~= false
end

local function rowMax(inst, group)
    return tonumber(get(inst, group:lower(), "max")) or 0
end

local function rowFilter(inst, group)
    local mine = get(inst, group:lower(), "onlyMine")
    if group == "Buffs" then
        return mine and "HELPFUL|PLAYER" or "HELPFUL"
    end
    if mine then return "HARMFUL|PLAYER" end
    -- RefreshDebuffs in AuraUtil: a hostile target of target shows the
    -- player's own debuffs alone.
    if inst.key == "targettarget" and not friendly(inst) then
        return "HARMFUL|PLAYER"
    end
    -- Nameplate-flagged debuffs belong to the target's row, as in vanilla.
    if inst.key == "target" or inst.key == "focus" then
        return "HARMFUL|INCLUDE_NAME_PLATE_ONLY"
    end
    return "HARMFUL"
end

--------------------------------------------------------------------------------
-- Buttons (tier 2)
--------------------------------------------------------------------------------

local function oneColorMap(r, g, b)
    local map = AuraRow.DispelColorMap()
    for k in pairs(map) do map[k] = CreateColor(r, g, b, 1) end
    return map
end

-- The dispel textures register in one pass, cleared first: AddDispelTypeTexture
-- appends. If the clear is refused the adds are skipped too, or entries pile up.
local function registerDispel(inst, group, button)
    local parts = button.camelotAura
    if not pcall(button.ClearDispelTypeTextures, button) then return end
    if group == "Debuffs" then
        local map
        if get(inst, "debuffs", "dispelColors") ~= false then
            map = AuraRow.DispelColorMap()
        else
            map = oneColorMap(0.8, 0, 0)
        end
        pcall(button.AddDispelTypeTexture, button, parts.border, {
            style = AuraRow.DISPEL_PRESERVE,
            showWhenHarmful = true,
            showWhenHelpful = false,
            showWithoutDispelType = true,
            customDispelColorMap = map,
        })
    elseif get(inst, "buffs", "stealable") ~= false and inst.unit ~= "player" then
        pcall(button.AddDispelTypeTexture, button, parts.glow, {
            style = AuraRow.DISPEL_PRESERVE,
            showWhenHarmful = false,
            showWhenHelpful = true,
            showWithoutDispelType = true,
            stealableFilter = AuraRow.STEALABLE_ONLY,
            customDispelColorMap = oneColorMap(1, 1, 1),
        })
    end
end

local function styleCount(inst, fs)
    local key = inst.key
    fs:SetFontObject("NumberFontNormalSmall")
    local face = get(inst, "count", "fontFace")
    local size = tonumber(get(inst, "count", "size"))
    local style = get(inst, "count", "style")
    if face or size or style then
        local objFace, objSize, objFlags = fs:GetFont()
        local path = face and addon.ResolveFontFace(face) or objFace
        if style then
            addon.ApplyFontStyle(fs, path, size or objSize, style)
        else
            fs:SetFont(path, size or objSize, objFlags)
        end
    end
    local r, g, b, a = addon.ResolveColorRGBA("custom", get(inst, "count", "color"),
        { fbR = 1, fbG = 1, fbB = 1, fbA = 1 })
    fs:SetTextColor(r, g, b, a)
    fs:SetShown(not get(inst, "count", "hidden"))
    local group = fs.camelotGroup
    fs:ClearAllPoints()
    fs:SetPoint("BOTTOMRIGHT", fs:GetParent(), "BOTTOMRIGHT",
        COUNT_X[group] + (tonumber(Settings.Aura(key, "count", "offsetX")) or 0),
        tonumber(Settings.Aura(key, "count", "offsetY")) or 0)
end

local function styleButton(inst, group, button)
    local parts = button.camelotAura
    local w, h = iconDims(inst)
    button:SetSize(w, h)
    cropIcon(parts.icon, w, h)

    local swipe = get(inst, "swipe") ~= false
    parts.cooldown:SetDrawSwipe(swipe)
    parts.cooldown:SetDrawEdge(swipe)

    pcall(button.SetMouseMotionEnabled, button, get(inst, "tooltips") ~= false)

    if parts.border then
        parts.border:SetSize(w + 2, h + 2)
    end
    if parts.glow then
        parts.glow:SetSize(w * STEALABLE_SCALE, h * STEALABLE_SCALE)
    end
    styleCount(inst, parts.count)
    registerDispel(inst, group, button)
end

-- Runs inside initializeFrame, once per button, where the tree can always be
-- touched. Everything handed to a binding is created on the button.
local function wireButton(inst, group, button)
    -- Clicks fall through to the secure click child; motion stays for the
    -- button's own tooltip. Only legal here.
    pcall(button.SetMouseClickEnabled, button, false)

    local parts = {}
    button.camelotAura = parts

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(button)
    button:SetIcon(icon)
    parts.icon = icon

    local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cd:SetAllPoints(button)
    cd:EnableMouse(false)
    cd:SetReverse(true)
    cd:SetHideCountdownNumbers(true)
    button:SetDurationCooldown(cd)
    parts.cooldown = cd

    -- Over the swipe, so the count and the border stay whole as it darkens.
    -- The border and the glow take ARTWORK, under the count in OVERLAY.
    local top = CreateFrame("Frame", nil, button)
    top:SetAllPoints(button)
    top:EnableMouse(false)
    top:SetFrameLevel(cd:GetFrameLevel() + 1)

    local count = top:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    count:SetJustifyH("RIGHT")
    count.camelotGroup = group
    button:SetApplicationCount(count, {})
    parts.count = count

    if group == "Debuffs" then
        local border = top:CreateTexture(nil, "ARTWORK")
        border:SetTexture(DEBUFF_BORDER)
        border:SetTexCoord(unpack(DEBUFF_BORDER_COORDS))
        border:SetPoint("CENTER", button, "CENTER")
        border:SetVertexColor(0.8, 0, 0)
        parts.border = border
    else
        local glow = top:CreateTexture(nil, "ARTWORK")
        glow:SetTexture(STEALABLE_GLOW)
        glow:SetBlendMode("ADD")
        glow:SetPoint("CENTER", button, "CENTER")
        glow:Hide()
        parts.glow = glow
    end

    styleButton(inst, group, button)
end

local function styleAll(inst)
    for group, row in pairs(inst.auraRows or {}) do
        for _, button in ipairs(row.buttons) do
            local ok, err = pcall(styleButton, inst, group, button)
            if not ok then AuraRow.results[inst.key .. ".style"] = tostring(err) end
        end
    end
end

--------------------------------------------------------------------------------
-- Layout (tier 1)
--------------------------------------------------------------------------------

local function layoutOpts(inst, w, h, anchorPoint, growY, maxLineSize)
    local spec = inst.spec.Auras
    return {
        anchorPoint = anchorPoint,
        growY = growY,
        maxLineSize = maxLineSize,
        layout = {
            elementSpacing = spec.spacing,
            lineSpacing = spec.lineSpacing,
            elementWidth = w,
            elementHeight = h,
        },
    }
end

-- The target's two blocks: the first at vanilla's start, the second anchored
-- beyond the first container. A container is never measured; its rect is
-- secret. An empty container lays out at no size, so the second block then
-- sits where the first would have.
local function layoutFull(inst)
    local spec, rows = inst.spec.Auras, inst.auraRows
    local w, h = iconDims(inst)
    local above = get(inst, "position") == "above"
    local anchorPoint = above and "BOTTOMLEFT" or "TOPLEFT"
    local growY = above and AuraRow.DIR_UP or AuraRow.DIR_DOWN
    local width = math.max(tonumber(get(inst, "rowWidth")) or 122, w)

    local first, second = "Buffs", "Debuffs"
    if not friendly(inst) then first, second = "Debuffs", "Buffs" end
    -- A row that is off has no place in the stack.
    if not rowShown(inst, first) then first, second = second, nil end
    if second and not rowShown(inst, second) then second = nil end

    for _, group in ipairs({ "Buffs", "Debuffs" }) do
        AuraRow.SetLayout(rows[group], layoutOpts(inst, w, h, anchorPoint, growY, width))
    end
    if above then
        AuraRow.SetPoint(rows[first], "BOTTOMLEFT", inst.frame, "TOPLEFT", spec.x, spec.mirrorY)
        if second then
            AuraRow.SetPoint(rows[second], "BOTTOMLEFT", rows[first].container, "TOPLEFT", 0, spec.blockGap)
        end
    else
        AuraRow.SetPoint(rows[first], "TOPLEFT", inst.frame, "BOTTOMLEFT", spec.x, spec.y)
        if second then
            AuraRow.SetPoint(rows[second], "TOPLEFT", rows[first].container, "BOTTOMLEFT", 0, -spec.blockGap)
        end
    end
end

-- The small frames' fixed set: a grid perLine icons wide.
local function layoutSmall(inst)
    local spec, row = inst.spec.Auras, inst.auraRows.Debuffs
    local w, h = iconDims(inst)
    local lineSize = spec.perLine * w + (spec.perLine - 1) * spec.spacing
    AuraRow.SetLayout(row, layoutOpts(inst, w, h, "TOPLEFT", AuraRow.DIR_DOWN, lineSize))
    AuraRow.SetPoint(row, spec.point, inst.frame, spec.relPoint, spec.x, spec.y)
end

local function layout(inst)
    if isFull(inst) then layoutFull(inst) else layoutSmall(inst) end
end

local function configure(inst)
    for _, group in ipairs(groupsOf(inst)) do
        AuraRow.Configure(inst.auraRows[group], rowFilter(inst, group), rowMax(inst, group),
            rowShown(inst, group))
    end
end

local function complete(inst)
    local rows = inst.auraRows
    if not rows then return false end
    for _, group in ipairs(groupsOf(inst)) do
        if not rows[group] then return false end
    end
    return true
end

--------------------------------------------------------------------------------
-- Build (tier 2)
--------------------------------------------------------------------------------

local function build(inst)
    inst.auraRows = inst.auraRows or {}
    local w, h = iconDims(inst)
    for _, group in ipairs(groupsOf(inst)) do
        if not inst.auraRows[group] then
            local row = AuraRow.Build(inst.frame, {
                tag = inst.key .. "." .. group,
                unit = inst.unit,
                group = group,
                filter = rowFilter(inst, group),
                max = rowMax(inst, group),
                layout = { elementSpacing = inst.spec.Auras.spacing,
                           lineSpacing = inst.spec.Auras.lineSpacing,
                           elementWidth = w, elementHeight = h },
                wire = function(button) wireButton(inst, group, button) end,
            })
            inst.auraRows[group] = row
        end
    end
end

--------------------------------------------------------------------------------
-- Entry points
--------------------------------------------------------------------------------

--- The settings pass, and the build at the frame's own. Nothing is built while
--- the rows are off: the player's stay unbuilt until the page turns them on.
function Auras.Apply(inst)
    if not (inst and inst.spec.Auras) then return end
    if not complete(inst) then
        if not get(inst, "enabled") then return end
        -- The deferred build finishes the pass itself, now or at the lift.
        AuraRow.Defer("camelotAuras.build." .. inst.key, function()
            build(inst)
            if complete(inst) then Auras.Apply(inst) end
        end)
        return
    end
    layout(inst)
    configure(inst)
    AuraRow.Defer("camelotAuras.style." .. inst.key, function() styleAll(inst) end)
end

--- A new subject, a show, or the Edit Mode stand-in coming or going: re-order
--- the blocks for the unit's reaction, and re-show and kick every row. Tier 1,
--- so it is legal in combat.
function Auras.Refresh(inst)
    if not complete(inst) then return end
    layout(inst)
    configure(inst)
end

--- Re-read the auras of a unit the client sends no UNIT_AURA for. The target
--- of target's poll calls it.
function Auras.Kick(inst)
    if not complete(inst) then return end
    for _, group in ipairs(groupsOf(inst)) do
        if rowShown(inst, group) then AuraRow.Kick(inst.auraRows[group]) end
    end
end

--- A line for /camelot state.
function Auras.Describe(inst)
    if not inst.spec.Auras then return "no aura rows" end
    if not complete(inst) then
        return get(inst, "enabled") and "not built yet" or "off, not built"
    end
    local parts = {}
    for _, group in ipairs(groupsOf(inst)) do
        local row = inst.auraRows[group]
        parts[#parts + 1] = string.format("%s %s, %d buttons, %s", group,
            rowShown(inst, group) and "shown" or "hidden", #row.buttons, rowFilter(inst, group))
    end
    return table.concat(parts, "; ")
end
