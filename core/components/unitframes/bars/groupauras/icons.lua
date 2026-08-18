--------------------------------------------------------------------------------
-- groupauras/icons.lua
-- Button wiring, styling and geometry for group-frame aura tracking
--
-- Every visual here hangs under an engine-managed AuraButton, so the engine's
-- own show and hide propagate to it and nothing ever asks whether an aura is
-- present. It cannot ask: ApplyVisibility does SetShown(secretwrap(...)) and a
-- truthiness test on that throws.
--
-- Two rules shape the whole file:
--
--   1. Regions are created inside WireButton, which the engine calls from
--      initializeFrame. That is the only moment the button tree is guaranteed
--      touchable, and every region handed to a Set*/Add* binding must be a
--      descendant of its button.
--   2. Geometry never touches a button. Each slot owns a plain Scoot frame,
--      the proxy, that the button SetAllPoints at wire time. Moving and sizing
--      the proxy moves and sizes the button, and a proxy is writable in combat
--      while a button is not.
--
-- Positions are derived from the ENABLED config, not from what is currently up.
-- Aura presence is secret, so an absent aura leaves its position empty rather
-- than letting its neighbours slide over. Each spell therefore always occupies
-- the same spot on every frame.
--
-- Depends on groupauras/core.lua (HA namespace, rainbow engine, registry) and
-- groupauras/engine.lua (containers, slots, the structural gate).
--------------------------------------------------------------------------------

local addonName, addon = ...

local HA = addon.AuraTracking
if not HA then return end

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local BASE_SIZE_RATIO = 0.45  -- Icon base size as a ratio of group frame height
local MIN_ICON_SIZE = 10
local MAX_ICON_SIZE = 64

--------------------------------------------------------------------------------
-- Anchor Maps
--------------------------------------------------------------------------------

-- Inside frame: icon anchors to the matching point on the group frame. 9 values.
-- Outside-frame anchoring was removed in the 12.0.5 rework. Visual conflict with
-- Blizzard's native icons is handled by the Hide Blizzard Buff Icons toggle (the
-- raidFramesDisplayBuffs game setting, 12.1), not by moving Scoot icons out.
HA.INSIDE_ANCHOR_VALUES = {
    TOPLEFT = "Top-Left", TOP = "Top", TOPRIGHT = "Top-Right",
    LEFT = "Left", CENTER = "Center", RIGHT = "Right",
    BOTTOMLEFT = "Bottom-Left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom-Right",
}
table.freeze(HA.INSIDE_ANCHOR_VALUES)
HA.INSIDE_ANCHOR_ORDER = {
    "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT",
}
table.freeze(HA.INSIDE_ANCHOR_ORDER)

-- Horizontal flow direction per anchor. Right-edge anchors grow leftward (rank 2
-- sits to the left of rank 1). All other anchors grow rightward.
local ANCHOR_DIRECTION = {
    TOPLEFT     =  1,
    TOP         =  1,
    TOPRIGHT    = -1,
    LEFT        =  1,
    CENTER      =  1,
    RIGHT       = -1,
    BOTTOMLEFT  =  1,
    BOTTOM      =  1,
    BOTTOMRIGHT = -1,
}
table.freeze(ANCHOR_DIRECTION)

-- Vertical flow direction per anchor. Bottom-edge anchors grow upward (rank 4+
-- wraps to a row ABOVE the first row), keeping icons away from the bottom edge.
-- Every other anchor grows downward. Mirrors Blizzard's Legacy layout, which is
-- BottomRightToTopLeft for buffs.
local ROW_GROWTH_DIR = {
    TOPLEFT     = -1,
    TOP         = -1,
    TOPRIGHT    = -1,
    LEFT        = -1,
    CENTER      = -1,
    RIGHT       = -1,
    BOTTOMLEFT  =  1,
    BOTTOM      =  1,
    BOTTOMRIGHT =  1,
}
table.freeze(ROW_GROWTH_DIR)

-- Wrap to a new row after this many icons. Matches Blizzard's Legacy /
-- BuffsRightDebuffsLeft layout (3 cols x 2 rows = up to 6 buffs).
local COLS_PER_ROW = 3

-- Center-anchor compensation: shift the icon CENTER inward so it sits fully
-- within the frame regardless of scale.
local INSIDE_CENTER_OFFSET = {
    TOPLEFT     = {  1, -1 },  -- push right and down
    TOP         = {  0, -1 },  -- push down
    TOPRIGHT    = { -1, -1 },  -- push left and down
    LEFT        = {  1,  0 },  -- push right
    CENTER      = {  0,  0 },
    RIGHT       = { -1,  0 },  -- push left
    BOTTOMLEFT  = {  1,  1 },  -- push right and up
    BOTTOM      = {  0,  1 },  -- push up
    BOTTOMRIGHT = { -1,  1 },  -- push left and up
}
table.freeze(INSIDE_CENTER_OFFSET)

--------------------------------------------------------------------------------
-- Config readers
--------------------------------------------------------------------------------

local function GetSpellConfig(spellId)
    -- Resolve linked variants to their primary entry's config
    local configId = spellId
    if HA.LINKED_TO_PRIMARY and HA.LINKED_TO_PRIMARY[spellId] then
        configId = HA.LINKED_TO_PRIMARY[spellId]
    end

    local db = addon.db and addon.db.profile
    local gf = db and db.groupFrames
    local ha = gf and gf.auraTracking
    local spells = ha and ha.spells
    if not spells or not spells[configId] then
        return HA.SPELL_DEFAULTS
    end
    return setmetatable(spells[configId], { __index = HA.SPELL_DEFAULTS })
end

HA._GetSpellConfig = GetSpellConfig

local function GetGroupSpacing(anchor)
    local db = addon.db and addon.db.profile
    local at = db and db.groupFrames and db.groupFrames.auraTracking
    local map = at and at.positionGroupSpacing
    if type(map) == "table" and type(map[anchor]) == "number" then
        return map[anchor]
    end
    return 2
end

-- Splits an iconStyle value into its prefix flags and the style underneath.
local function ParseStyle(style)
    style = tostring(style or "spell")
    local isBordered = style:sub(1, 7) == "border:"
    local isWide = style:sub(1, 5) == "wide:"
    local effective = style
    if isBordered then
        effective = style:sub(8)
    elseif isWide then
        effective = style:sub(6)
    end
    return effective, isBordered, isWide
end

--- The own-cast axis rides the PLAYER filter token and nothing else. The
--- candidateFilters isFromPlayerOrPlayerPet field is NOT this: field evidence
--- shows it matches auras cast by any player.
function HA.SlotFilterString(spellId)
    local cfg = GetSpellConfig(spellId)
    if cfg.trackAllSources then return "HELPFUL" end
    return "HELPFUL|PLAYER"
end

--- The animation id a slot must be built with, or nil for a static icon. This
--- is the one part of a slot that cannot be re-styled in place, because an
--- animation's textures exist only if they were created inside initializeFrame.
function HA.SlotAnimId(spellId)
    local effective = ParseStyle(GetSpellConfig(spellId).iconStyle)
    if effective:sub(1, 5) == "anim:" then
        return effective:sub(6)
    end
    return nil
end

--- Final on-screen size for one slot, derived from the group frame's height.
local function SlotSize(entry, spellId)
    local cfg = GetSpellConfig(spellId)
    local frameHeight = entry.frameHeight or 36
    local base = math.max(MIN_ICON_SIZE, frameHeight * BASE_SIZE_RATIO)
    local userScale = (tonumber(cfg.iconScale) or 100) / 100
    local size = math.min(MAX_ICON_SIZE, math.max(MIN_ICON_SIZE, base * userScale))
    local _, _, isWide = ParseStyle(cfg.iconStyle)
    if isWide then return size * 3, size end
    return size, size
end

--------------------------------------------------------------------------------
-- Geometry (TIER 1: proxies only, legal in combat)
--------------------------------------------------------------------------------

local function PlaceProxy(proxy, host, anchor, offsetX, offsetY, w, h)
    proxy:SetSize(w, h)
    proxy:ClearAllPoints()
    local comp = INSIDE_CENTER_OFFSET[anchor] or INSIDE_CENTER_OFFSET.TOPRIGHT
    proxy:SetPoint(
        "CENTER", host, anchor,
        offsetX + comp[1] * w * 0.5,
        offsetY + comp[2] * h * 0.5
    )
end

--- Places every slot proxy on one frame. Buckets by anchor, sorts by priority,
--- offsets each icon from the previous by half-widths plus the anchor's spacing,
--- and wraps every COLS_PER_ROW icons.
---
--- The bucket is the ENABLED config, not the live icons. Presence is secret, so
--- a missing aura holds its place rather than letting the group re-pack.
function HA.LayoutFrame(entry)
    if not entry or not entry.host then return end

    local groups = {}
    for _, item in ipairs(HA.EnabledSpellList()) do
        local cfg = item.config
        local anchor = cfg.anchor or "BOTTOMRIGHT"
        if not HA.INSIDE_ANCHOR_VALUES[anchor] then anchor = "BOTTOMRIGHT" end
        groups[anchor] = groups[anchor] or {}
        table.insert(groups[anchor], {
            spellId = item.spellId,
            config  = cfg,
            rank    = tonumber(cfg.rank) or 1,
        })
    end

    for anchor, members in pairs(groups) do
        table.sort(members, function(a, b)
            if a.rank ~= b.rank then return a.rank < b.rank end
            return a.spellId < b.spellId
        end)

        local spacing = GetGroupSpacing(anchor)
        local xDir = ANCHOR_DIRECTION[anchor] or 1
        local yDir = ROW_GROWTH_DIR[anchor] or -1

        -- Row step uses the first icon's height as the canonical step for this
        -- anchor, so mixed-scale groups still line their rows up.
        local _, rowHeight = SlotSize(entry, members[1].spellId)
        local rowStep = rowHeight + spacing

        local rowCursor = 0   -- running horizontal offset within the current row
        local prevHalfW = 0
        local lastRow = -1

        for idx, member in ipairs(members) do
            local w, h = SlotSize(entry, member.spellId)
            local halfW = w * 0.5
            local row = math.floor((idx - 1) / COLS_PER_ROW)

            if row ~= lastRow then
                rowCursor = 0
                prevHalfW = halfW
                lastRow = row
            else
                rowCursor = rowCursor + prevHalfW + halfW + spacing
                prevHalfW = halfW
            end

            -- Per-icon fine-tune on top of auto-placement. Raw pixels, never
            -- multiplied by the direction: +X is always right, +Y always up.
            local offsetX = rowCursor * xDir + (tonumber(member.config.offsetX) or 0)
            local offsetY = row * rowStep * yDir + (tonumber(member.config.offsetY) or 0)

            local slot = entry.slots[member.spellId]
            if slot and slot.proxy then
                PlaceProxy(slot.proxy, entry.host, anchor, offsetX, offsetY, w, h)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Engine bindings (TIER 2)
--------------------------------------------------------------------------------

local function CallBinding(slot, button, methodName, region, options)
    local fn = button[methodName]
    if not fn then
        HA.Engine.SetResult("bind." .. slot.spellId .. "." .. methodName, "method missing")
        return false
    end
    local ok, err
    if options ~= nil then
        ok, err = pcall(fn, button, region, options)
    elseif region ~= nil then
        ok, err = pcall(fn, button, region)
    else
        ok, err = pcall(fn, button)
    end
    if not ok then
        HA.Engine.SetResult("bind." .. slot.spellId .. "." .. methodName,
            "FAILED: " .. HA.Engine.SafeToString(err))
    end
    return ok
end

--- Binds or clears the engine-driven regions for one slot per its config.
--- Returns true when everything landed; a false leaves the fingerprint
--- unstamped so the drain retries.
function HA.ApplySlotBindings(entry, slot, force)
    local button = slot.button
    if not button then return false end

    local cfg = GetSpellConfig(slot.spellId)
    local effective = ParseStyle(cfg.iconStyle)
    local isAnimated = effective:sub(1, 5) == "anim:"

    -- The engine stamps the matched aura's own icon on a bound texture. Bind
    -- only when the user asked for the spell's icon; for atlas, file and
    -- animated styles the art is Scoot's and must not be overwritten.
    local wantEngineIcon = (effective == "spell")

    local showDuration = cfg.showDuration
    if showDuration == nil then showDuration = true end
    local wantCooldown = showDuration and not isAnimated

    local key = tostring(wantEngineIcon) .. ":" .. tostring(wantCooldown)
    if not force and slot.bindKey == key then return true end

    local ok = true
    if wantEngineIcon then
        ok = CallBinding(slot, button, "SetIcon", slot.icon) and ok
    else
        ok = CallBinding(slot, button, "ClearIcon") and ok
    end

    if wantCooldown then
        ok = CallBinding(slot, button, "SetDurationCooldown", slot.cooldown) and ok
    else
        ok = CallBinding(slot, button, "ClearDurationCooldown") and ok
        pcall(slot.cooldown.Clear, slot.cooldown)
    end

    -- Always bound. The engine renders nothing at or below one application on
    -- its own, which is what the old "applications > 1" test bought.
    ok = CallBinding(slot, button, "SetApplicationCount", slot.count, {}) and ok

    if ok then slot.bindKey = key end
    return ok
end

--------------------------------------------------------------------------------
-- Styling (TIER 2)
--------------------------------------------------------------------------------

-- One string per slot describing everything ApplySlotStyle would apply, stamped
-- ONLY after the work lands. A fingerprint written ahead of a refused call would
-- make the retry skip it and the button would stay wrong for the session.
local function StyleKey(cfg, w, h)
    local c = cfg.iconCustomColor or { 1, 1, 1, 1 }
    local st = rawget(cfg, "stacksText")
    local defaults = HA.STACKS_TEXT_DEFAULTS or {}
    local function stGet(k)
        if st and st[k] ~= nil then return st[k] end
        return defaults[k]
    end
    return table.concat({
        w, h,
        tostring(cfg.iconStyle),
        tostring(cfg.iconColor),
        c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1,
        tostring(cfg.showDuration ~= false),
        tostring(stGet("fontFace")), tostring(stGet("size")), tostring(stGet("style")),
        tostring(stGet("colorMode")), tostring(stGet("anchor")),
        tostring(stGet("offsetX")), tostring(stGet("offsetY")),
    }, ":")
end

local function ApplyIconArt(slot, spellId, effective, isBordered)
    local tex = slot.icon
    local isAnimated = effective:sub(1, 5) == "anim:"

    if isAnimated then
        tex:Hide()
    elseif effective == "spell" then
        tex:Show()
        -- The engine overwrites this on every aura assignment; the static paint
        -- is the pre-match backdrop, and the fallback when the API is unhappy.
        local spellTex
        if pcall(function() spellTex = C_Spell.GetSpellTexture(spellId) end) and spellTex then
            pcall(tex.SetTexture, tex, spellTex)
        else
            local reg = HA.SPELL_REGISTRY_BY_ID and HA.SPELL_REGISTRY_BY_ID[spellId]
            pcall(tex.SetTexture, tex, (reg and reg.textureId) or "Interface\\Icons\\INV_Misc_QuestionMark")
        end
    elseif effective:sub(1, 5) == "file:" then
        tex:Show()
        pcall(tex.SetTexture, tex, effective:sub(6))
    else
        tex:Show()
        if not pcall(tex.SetAtlas, tex, effective) then
            pcall(tex.SetTexture, tex, "Interface\\Icons\\INV_Misc_QuestionMark")
        end
    end

    -- Border variant: same-shape black backing with a 1px inset on the icon.
    local border = slot.border
    if isBordered and border then
        if not pcall(border.SetAtlas, border, effective) then
            border:SetColorTexture(0, 0, 0, 1)
        end
        border:SetDesaturated(true)
        border:SetVertexColor(0, 0, 0, 1)
        border:Show()
        pcall(function()
            tex:ClearAllPoints()
            tex:SetPoint("TOPLEFT", slot.button, "TOPLEFT", 1, -1)
            tex:SetPoint("BOTTOMRIGHT", slot.button, "BOTTOMRIGHT", -1, 1)
        end)
    else
        if border then border:Hide() end
        pcall(function()
            tex:ClearAllPoints()
            tex:SetAllPoints(slot.button)
        end)
    end
end

local function ApplyIconColor(slot, cfg, isAnimated)
    local tex = slot.icon
    local mode = cfg.iconColor or "original"

    if slot.isRainbow then
        HA.UnregisterRainbowIcon(tex)
        slot.isRainbow = false
    end

    if isAnimated then
        local ctrl = slot.anim
        if ctrl then
            if mode == "custom" then
                local c = cfg.iconCustomColor or { 1, 1, 1, 1 }
                ctrl:SetColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
            elseif mode == "rainbow" then
                ctrl.rainbowMode = true
            else
                ctrl:SetColor(1, 1, 1, 1)
            end
        end
        return
    end

    if mode == "original" then
        pcall(tex.SetDesaturated, tex, false)
        pcall(tex.SetVertexColor, tex, 1, 1, 1, 1)
    elseif mode == "rainbow" then
        pcall(tex.SetDesaturated, tex, true)
        HA.RegisterRainbowIcon(tex)
        slot.isRainbow = true
    elseif mode == "custom" then
        pcall(tex.SetDesaturated, tex, true)
        local c = cfg.iconCustomColor or { 1, 1, 1, 1 }
        pcall(tex.SetVertexColor, tex, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    else
        pcall(tex.SetDesaturated, tex, true)
        pcall(tex.SetVertexColor, tex, 1, 1, 1, 1)
    end
end

local function ApplySwipe(slot, spellId, cfg, effective, isAnimated)
    local cd = slot.cooldown
    if not cd then return end

    local showDuration = cfg.showDuration
    if showDuration == nil then showDuration = true end

    if not showDuration or isAnimated then
        pcall(cd.SetDrawSwipe, cd, false)
        return
    end

    pcall(cd.SetDrawSwipe, cd, true)
    pcall(cd.SetSwipeColor, cd, 0, 0, 0, 0.85)
    -- Reverse: the swipe GROWS as the aura drains, so a full icon is fresh.
    pcall(cd.SetReverse, cd, true)
    pcall(cd.SetDrawEdge, cd, false)
    pcall(cd.SetDrawBling, cd, false)

    -- Shape the swipe to the icon so the drain follows its silhouette.
    if effective == "spell" then
        local swipeTex
        pcall(function() swipeTex = C_Spell.GetSpellTexture(spellId) end)
        if not swipeTex then
            local reg = HA.SPELL_REGISTRY_BY_ID and HA.SPELL_REGISTRY_BY_ID[spellId]
            swipeTex = reg and reg.textureId
        end
        if swipeTex then pcall(cd.SetSwipeTexture, cd, swipeTex) end
    elseif effective:sub(1, 5) == "file:" then
        pcall(cd.SetSwipeTexture, cd, effective:sub(6))
    else
        local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(effective)
        if info and (info.file or info.filename) then
            pcall(cd.SetSwipeTexture, cd, info.file or info.filename)
            pcall(function()
                cd:SetTexCoordRange(
                    { x = info.leftTexCoord, y = info.topTexCoord },
                    { x = info.rightTexCoord, y = info.bottomTexCoord }
                )
            end)
        end
    end
end

local function ApplyStacksText(slot, cfg)
    local fs = slot.count
    if not fs then return end

    local st = rawget(cfg, "stacksText")
    local defaults = HA.STACKS_TEXT_DEFAULTS or {}
    local function stGet(k)
        if st and st[k] ~= nil then return st[k] end
        return defaults[k]
    end

    local fontFace = stGet("fontFace") or "FRIZQT__"
    local size     = tonumber(stGet("size")) or 12
    local style    = stGet("style") or "OUTLINE"
    local anchor   = stGet("anchor") or "BOTTOMRIGHT"
    local offsetX  = tonumber(stGet("offsetX")) or 0
    local offsetY  = tonumber(stGet("offsetY")) or 0

    local fontPath = addon.ResolveFontFace and addon.ResolveFontFace(fontFace)
    if fontPath then
        if addon.ApplyFontStyle then
            -- Routes through Scoot's font-style helper so SHADOW and HEAVY
            -- prefixes render the same as every other Scoot text.
            pcall(addon.ApplyFontStyle, fs, fontPath, size, style)
        else
            pcall(fs.SetFont, fs, fontPath, size, style)
        end
    end

    if stGet("colorMode") == "custom" then
        local c = stGet("customColor") or { 1, 1, 1, 1 }
        pcall(fs.SetTextColor, fs, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    else
        pcall(fs.SetTextColor, fs, 1, 1, 1, 1)
    end

    pcall(function()
        fs:ClearAllPoints()
        fs:SetPoint(anchor, slot.button, anchor, offsetX, offsetY)
    end)
end

--- Full visual pass for one slot. Returns true when everything landed.
function HA.ApplySlotStyle(entry, slot, force)
    local button = slot.button
    if not button then return false end

    local cfg = GetSpellConfig(slot.spellId)
    local w, h = SlotSize(entry, slot.spellId)
    local key = StyleKey(cfg, w, h)
    if not force and slot.styleKey == key then return true end

    local effective, isBordered = ParseStyle(cfg.iconStyle)
    local isAnimated = effective:sub(1, 5) == "anim:"

    ApplyIconArt(slot, slot.spellId, effective, isBordered)
    -- Configure before coloring: the controller resolves its color through the
    -- animation definition, which it does not have until it is configured.
    if isAnimated and slot.anim then
        slot.anim:Configure(effective:sub(6), math.min(w, h))
    end
    ApplyIconColor(slot, cfg, isAnimated)
    ApplySwipe(slot, slot.spellId, cfg, effective, isAnimated)
    ApplyStacksText(slot, cfg)

    if slot.anim then
        if isAnimated then slot.anim:Play() else slot.anim:Stop() end
    end

    local ok = HA.ApplySlotBindings(entry, slot, force)
    if ok then slot.styleKey = key end
    return ok
end

--- Every slot on one frame. Returns true when nothing was refused.
function HA.ApplyFrameStyle(entry)
    if not entry or not entry.slots then return true end
    if not HA.Engine.CanDoStructuralWork() then return false end
    local allOk = true
    for _, slot in pairs(entry.slots) do
        if slot.button and not HA.ApplySlotStyle(entry, slot) then allOk = false end
    end
    return allOk
end

--------------------------------------------------------------------------------
-- Button wiring (runs inside initializeFrame)
--------------------------------------------------------------------------------

--- Creates every region for one slot and applies its first style pass. The
--- caller pcalls this: a throw here aborts the engine's whole frame batch.
function HA.WireButton(entry, slot, button)
    -- Anchor to the proxy and never to anything else. This is what makes every
    -- later move and resize legal in combat.
    button:ClearAllPoints()
    button:SetAllPoints(slot.proxy)

    -- Clicks off HERE and only here: a post-creation write is refused exactly
    -- while auras are secret, which is exactly when a live click surface over a
    -- group frame would steal targeting. Motion off too; this feature has no
    -- tooltips and the button's intrinsic one would fire on hover.
    pcall(button.SetMouseClickEnabled, button, false)
    pcall(button.SetMouseMotionEnabled, button, false)

    -- Border backing, under the icon: only the inset margin is ever visible.
    local border = button:CreateTexture(nil, "BACKGROUND", nil, 0)
    border:SetAllPoints(button)
    border:Hide()
    slot.border = border

    local tex = button:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(button)
    slot.icon = tex

    local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cd:SetAllPoints(button)
    cd:EnableMouse(false)
    cd:SetDrawEdge(false)
    cd:SetDrawBling(false)
    cd:SetHideCountdownNumbers(true)
    cd:SetReverse(true)
    cd:SetDrawSwipe(false)
    slot.cooldown = cd

    -- Text above the swipe so the stack count stays opaque at any drain depth.
    -- A child-of-child FontString is accepted: ScootAuras wires its elements
    -- through exactly this shape and that path is verified in game.
    local textHost = CreateFrame("Frame", nil, button)
    textHost:SetAllPoints(button)
    textHost:EnableMouse(false)
    local lok, level = pcall(button.GetFrameLevel, button)
    if lok and type(level) == "number" and not issecretvalue(level) then
        textHost:SetFrameLevel(level + 5)
    end
    slot.textHost = textHost

    local count = textHost:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    slot.count = count

    -- Animated styles need their controller born here or never: a frame created
    -- after initializeFrame can no longer be parented into the button tree.
    if slot.animId and HA.AnimEngine and HA.AnimEngine.CreateOwned then
        slot.anim = HA.AnimEngine.CreateOwned(button)
    end

    -- Style now. A slot is created long after the last full pass in the common
    -- case, and this is the one moment a brand new button is always touchable.
    HA.ApplySlotStyle(entry, slot, true)
end
