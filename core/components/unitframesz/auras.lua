-- unitframesz/auras.lua - Unit Frames Z: buff/debuff icon rows
--
-- Rows are Blizzard AuraContainer intrinsics (12.1), one container per row per
-- instance, parented inside inst.frame. The container does tracking, filtering
-- and sorting in secure C and hands back buttons through initializeFrame; the
-- addon supplies regions and never reads aura data at all. That is the whole
-- point: 12.1 made C_UnitAuras.GetUnitAuraInstanceIDs return a SECRET vector
-- while auras are secret (combat, encounters, M+, PvP), so the old Lua pull
-- went blind exactly when the rows mattered. Nothing here can go blind,
-- because nothing here reads.
--
-- TOPOLOGY B, the shape ScootAuras uses: the container is a child
-- of inst.frame, so Overall Scale and the opacity trio are inherited rather
-- than synced. Container frame levels are left at their defaults -- a child
-- lands at parent+1 and its buttons at parent+2, which reproduces the previous
-- rows' levels exactly (frame 10 / click overlay 11 / icons 12) with no
-- GetFrameLevel read.
--
-- The rows stay UNBOXED: they hang outside the config-derived envelope (the
-- absorb-text precedent, engine.lua computeEnvelope doctrine) and never call
-- applyEnvelope. Container geometry is never read back either -- a grouped
-- container self-sizes through secretwrap, so its rect is SECRET. Every number
-- here comes from cfg, and the debuff row reaches its stacked position by
-- ANCHORING to the buff container rather than measuring it.
--
-- TIER SPLIT (scootauras/engine.lua doctrine). Tier 1 is always legal:
-- container SetPoint/Show/Hide/SetEnabled, SetAuraGroup*, SetFlowLayout*.
-- Tier 2 touches the button tree, which carries
-- DenyTaintedAccessWhenAurasAreSecret, and runs only inside
-- CanDoStructuralWork(); otherwise it queues and drains on the restriction
-- lift. Gate on aura SECRECY as well as lockdown: an encounter can restrict
-- auras without a lockdown.
--
-- Icons stay click-TRANSPARENT: clicks
-- fall through to the secure click-to-target overlay. SetMouseClickEnabled is
-- called INSIDE initializeFrame because that is the only reliably legal
-- moment; a post-creation write to a button is denied precisely while auras
-- are secret. Motion stays on, so the button's intrinsic tooltip works. There
-- is no SetScript("OnEnter") on it, and there cannot be: AuraButton carries the
-- UntrustedScriptExecution forbidden aspect.
--
-- Debuff borders are the bedrock "this is a debuff" indicator, and are now
-- colored by DISPEL SCHOOL. One solid ring texture per
-- debuff button, registered via AddDispelTypeTexture with the PreserveAsset
-- style so the engine keeps the Scoot art, plus an EXPLICIT customDispelColorMap.
--
-- The map is not optional. PreserveAsset on its own calls
-- AuraUtil.SetAuraBorderColor, which resolves a missing dispel type through
-- DEBUFF_DISPLAY_INFO["None"] -> DEBUFF_TYPE_NONE_COLOR, and in game that
-- renders BLACK, not the debuff red this file used to hardcode. The earlier
-- reading that "None is Blizzard's own red" was wrong, and it was wrong in the
-- way that matters: it was inferred from source and never verified, then used
-- to justify deleting the color map. It renders black on an
-- undispellable enemy debuff. customDispelColorMap is applied after the style
-- pass, so supplying it puts the color back under Scoot's control and keeps the
-- undispellable case identical to what shipped before.

local addonName, addon = ...

local UFZ = addon.UnitFramesZ
UFZ.Auras = UFZ.Auras or {}
local Auras = UFZ.Auras

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local BASE_ICON = 20   -- px per icon at Icon Scale 100
local ICON_PAD  = 3    -- px between icons on a line
local LINE_GAP  = 4    -- px between wrapped lines AND between the two row blocks
-- Snug on purpose, tucked INTO the envelope (three jumps:
-- 5 read as "far too much", 1 still left "considerable dead space", and -3
-- still needed a +12 nudge in-game -- the envelope edge carries reserve slack
-- past the visible ink, and the rows may legally overlap it: they're unboxed
-- children, not envelope content). The -15 rebase makes that settled
-- position the new 0-point of the user-facing Y-Offset (cfg.auraOffsetY, + = up).
local FRAME_GAP = -15  -- px from the frame edge to the first line (negative = inside)

local ROW_KEYS = { "Buffs", "Debuffs" }  -- cfg key stems: aura<Key><Suffix>

-- Pre-paint color for the dispel ring, and the value the engine's own "None"
-- fallback resolves to. Kept so a ring is never white for the frame between
-- creation and its first engine paint.
local DEBUFF_RED = { 0.8, 0, 0, 1 }

-- Dispel-school colors for the debuff ring, supplied EXPLICITLY rather than
-- left to PreserveAsset's own lookup (see the header). Keys must match
-- GetDispelTypeMapKey exactly: auraData.dispelName, or "None" when it is nil.
local DISPEL_FALLBACK_RGB = {
    Magic   = { 0.20, 0.60, 1.00 },
    Curse   = { 0.60, 0.00, 1.00 },
    Disease = { 0.60, 0.40, 0.00 },
    Poison  = { 0.00, 0.60, 0.00 },
    Bleed   = { 1.00, 0.20, 0.20 },
}

-- Prefer the client's live table so the schools match every other debuff border
-- in the game, and fall back to the long-stable literals if it is absent. The
-- values must be Color objects: the engine calls color:GetRGBA() on whatever
-- the map hands back.
local function dispelColorMap()
    local live = rawget(_G, "DebuffTypeColor")
    local map = {}
    for key, rgb in pairs(DISPEL_FALLBACK_RGB) do
        local c = live and live[key]
        if type(c) == "table" and type(c.r) == "number" then
            map[key] = CreateColor(c.r, c.g, c.b, 1)
        else
            map[key] = CreateColor(rgb[1], rgb[2], rgb[3], 1)
        end
    end
    -- Undispellable keeps the exact red this row has always used.
    map.None = CreateColor(DEBUFF_RED[1], DEBUFF_RED[2], DEBUFF_RED[3], DEBUFF_RED[4])
    return map
end

-- Engine enums that live as PLAIN GLOBALS, not under Enum. Defaults match
-- Blizzard's own so a missing global degrades instead of erroring.
local SORT_DEFAULT = (AuraContainerSortMethod and AuraContainerSortMethod.Default) or 0
local SORT_NORMAL  = (AuraContainerSortDirection and AuraContainerSortDirection.Normal) or 0

local FLOW_AXIS = AnchorUtil and AnchorUtil.FlowLayoutAxis
local FLOW_HORIZONTAL = (FLOW_AXIS and FLOW_AXIS.Horizontal) or 0
local FLOW_DIR = AnchorUtil and AnchorUtil.FlowDirection
local DIR_RIGHT = (FLOW_DIR and FLOW_DIR.Right) or 1
local DIR_DOWN  = (FLOW_DIR and FLOW_DIR.Down) or -1
local DIR_UP    = (FLOW_DIR and FLOW_DIR.Up) or 1

local DISPEL_STYLE = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
local DISPEL_PRESERVE = (DISPEL_STYLE and DISPEL_STYLE.PreserveAsset) or 3

--------------------------------------------------------------------------------
-- Telemetry (the scootauras/engine.lua Record/SetResult pattern)
--------------------------------------------------------------------------------

local results = {}   -- [key] = latest observation string
local log = {}       -- ring of { seq, tag, detail }
local logSeq = 0
local LOG_MAX = 64

local function SafeToString(v)
    if issecretvalue(v) then return "<SECRET>" end
    local ok, s = pcall(tostring, v)
    return ok and s or "<tostring failed>"
end

local function Record(tag, detail)
    logSeq = logSeq + 1
    log[(logSeq % LOG_MAX) + 1] = { t = GetTime(), seq = logSeq, tag = tag, detail = detail }
end

local function SetResult(key, value)
    results[key] = value
end

Auras._results = results
Auras._log = log

local function instTag(inst)
    return tostring(inst and (inst.frameKey or inst.unitKey) or "?")
end

--------------------------------------------------------------------------------
-- Gate and pending queue
--------------------------------------------------------------------------------

-- Structural/styling work on the button tree is denied while auras are secret,
-- and secrecy is NOT the same condition as combat lockdown: an encounter can
-- restrict auras with no lockdown at all. Gate on both.
function Auras.CanDoStructuralWork()
    if InCombatLockdown() then return false end
    if addon.AurasSecretNow and addon.AurasSecretNow() then return false end
    return true
end

-- Instances whose Tier 2 pass was refused. Keyed by the instance table itself
-- (instances are long-lived and re-pointed rather than replaced).
local pendingStyle = {}
Auras._pendingStyle = pendingStyle

--------------------------------------------------------------------------------
-- Config readers
--------------------------------------------------------------------------------

local function iconDims(cfg)
    local base = BASE_ICON * (tonumber(cfg.auraIconScale) or 100) / 100
    if addon.IconRatio then
        return addon.IconRatio.CalculateDimensions(base, tonumber(cfg.auraTallWideRatio) or 0)
    end
    return base, base
end

local function borderThickness(cfg)
    local t = tonumber(cfg.auraBorderThickness) or 1
    if t < 1 then return 1 elseif t > 8 then return 8 end
    return t
end

local function rowFilter(inst, rowKey)
    if rowKey == "Buffs" then
        -- "Only my buffs" is the PLAYER filter token and nothing else. The
        -- candidateFilters isFromPlayerOrPlayerPet field is NOT this: field
        -- evidence shows it matches auras from ANY player.
        return inst.cfg.auraOnlyPlayerBuffs and "HELPFUL|PLAYER" or "HELPFUL"
    end
    -- Blizzard TargetFrame parity: nameplate-flagged player DoTs are part of
    -- the target's debuff row; plain HARMFUL for the player's own frame.
    if inst.unit == "player" then
        return "HARMFUL"
    end
    return "HARMFUL|INCLUDE_NAME_PLATE_ONLY"
end

local function rowMax(inst, rowKey)
    return tonumber(inst.cfg["aura" .. rowKey .. "Max"]) or (rowKey == "Buffs" and 16 or 8)
end

local function rowShown(cfg, rowKey)
    return cfg["aura" .. rowKey .. "Show"] and true or false
end

-- Edit Mode's subject-less stand-in suppresses both rows. It is held on the
-- instance rather than acted on once, so every later re-assert (ForceRefresh,
-- the drain, a settings pass) honors it instead of racing the preview back on.
local function rowVisible(inst, rowKey)
    if inst.auraStandIn then return false end
    return rowShown(inst.cfg, rowKey)
end

local function rowSide(cfg, rowKey)
    return cfg["aura" .. rowKey .. "Loc"] == "top" and "top" or "bottom"
end

local function anyRowEnabled(cfg)
    return (cfg.auraBuffsShow or cfg.auraDebuffsShow) and true or false
end

-- Crop (not stretch) non-square icons via texcoords -- the buffs.lua pattern.
-- The engine only ever calls SetTexture on a bound icon, so a texcoord set
-- here survives every aura assignment.
local function applyCrop(tex, w, h)
    local aspect = w / h
    local left, right, top, bottom = 0, 1, 0, 1
    if aspect > 1.0 then
        local cropOffset = (1.0 - (1.0 / aspect)) / 2.0
        top = cropOffset
        bottom = 1.0 - cropOffset
    elseif aspect < 1.0 then
        local cropOffset = (1.0 - aspect) / 2.0
        left = cropOffset
        right = 1.0 - cropOffset
    end
    pcall(tex.SetTexCoord, tex, left, right, top, bottom)
end

local function borderContainer(tex)
    local state = addon.FrameState and addon.FrameState.Get(tex)
    return state and state.ScootIconBorderContainer
end

--------------------------------------------------------------------------------
-- Per-button styling (TIER 2)
--------------------------------------------------------------------------------

-- One string per button describing everything styleButton would apply. Stamped
-- ONLY after the work lands: a fingerprint written ahead of a denied call would
-- make the retry skip it, and the button would stay wrong for the session.
local function styleKey(cfg, w, h)
    return table.concat({
        w, h,
        borderThickness(cfg),
        tostring(cfg.auraBorderStyle or "square"),
        tostring(cfg.auraBorderEnable and true or false),
        tostring(cfg.auraBorderTintEnable and true or false),
        cfg.auraBorderTintR or 1, cfg.auraBorderTintG or 1,
        cfg.auraBorderTintB or 1, cfg.auraBorderTintA or 1,
        tostring(cfg.auraTooltips and true or false),
    }, ":")
end

-- Returns true when the button is fully styled, false when anything was
-- refused. A false propagates so the caller leaves its own fingerprint
-- unstamped and the drain re-enters.
local function styleButton(inst, rowKey, button, w, h, key)
    if button.scootStyleKey == key then return true end

    local cfg = inst.cfg
    local isDebuff = (rowKey == "Debuffs")
    local ok = true

    if not pcall(button.SetSize, button, w, h) then ok = false end

    local tex = button.scootIcon
    if tex then applyCrop(tex, w, h) end

    if isDebuff then
        -- The ring IS the debuff border: always on, thickness from the shared
        -- slider, color from the engine's dispel school.
        local ring = button.scootDispelRing
        if ring then
            local t = borderThickness(cfg)
            ring:ClearAllPoints()
            ring:SetPoint("TOPLEFT", button, "TOPLEFT", -t, t)
            ring:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", t, -t)
        end
    elseif cfg.auraBorderEnable and addon.ApplyIconBorderStyle and tex then
        local tintEnabled = cfg.auraBorderTintEnable and true or false
        local color
        if tintEnabled then
            color = {
                cfg.auraBorderTintR or 1, cfg.auraBorderTintG or 1,
                cfg.auraBorderTintB or 1, cfg.auraBorderTintA or 1,
            }
        end
        -- No db/thicknessKey/tintColorKey opts: UFZ cfg is flat scalars and
        -- those opts expect a nested color table to read back from.
        local bOk = pcall(addon.ApplyIconBorderStyle, tex, cfg.auraBorderStyle or "square", {
            thickness = borderThickness(cfg),
            tintEnabled = tintEnabled,
            color = color,
            defaultThickness = 1,
        })
        if not bOk then ok = false end
        -- SetPoint anchoring to Textures doesn't always propagate size changes;
        -- resize the wrapper container explicitly (buffs.lua pattern).
        local container = borderContainer(tex)
        if container and container.SetSize then
            pcall(container.SetSize, container, w, h)
            pcall(container.EnableMouse, container, false)
        end
        -- The count's host was levelled at button + 5 when the button was wired, which
        -- is exactly where the border container lands; equal levels fall back to
        -- creation order and the container is created later, so it would win. Re-level
        -- the host above whatever the border actually got.
        local countFS = button.scootCount
        if countFS and countFS.GetParent then
            local okHost, host = pcall(countFS.GetParent, countFS)
            local borderLevel = addon.GetIconBorderLevel and addon.GetIconBorderLevel(tex)
            if okHost and host and host ~= button and borderLevel then
                pcall(host.SetFrameLevel, host, borderLevel + 1)
            end
        end
    elseif tex and addon.Borders and addon.Borders.HideAll then
        addon.Borders.HideAll(tex)
        local container = borderContainer(tex)
        if container then addon.Borders.HideAll(container) end
    end

    -- Tooltips ride the button's own intrinsic OnEnter (AuraButton carries the
    -- UntrustedScriptExecution aspect, so SetScript is not an option). Combat
    -- is exactly when this now works, so never hide it there.
    local wantTips = cfg.auraTooltips and true or false
    if wantTips then
        if not pcall(button.SetTooltipAnchorPoint, button, "ANCHOR_BOTTOMRIGHT") then ok = false end
        if not pcall(button.SetHideTooltipInCombat, button, false) then ok = false end
    end
    if not pcall(button.SetMouseMotionEnabled, button, wantTips) then ok = false end
    -- Configuring a button's tooltip re-arms its mouse as a side effect, so the
    -- click-through flag is re-asserted after the tooltip calls, every pass.
    if not pcall(button.SetMouseClickEnabled, button, false) then ok = false end

    if ok then button.scootStyleKey = key end
    return ok
end

--------------------------------------------------------------------------------
-- Button wiring (runs inside initializeFrame, where the tree is touchable)
--------------------------------------------------------------------------------

-- Every region handed to a Set*/Add* binding must be a DESCENDANT of its
-- button (ValidateInboundScriptObject -> RegionUtil.IsDescendantOf) or the
-- binding is rejected outright. Everything below is created on the button.
--
-- Batches of 10 buttons are created as the pool grows, each firing this, so it
-- must be idempotent and must read CURRENT config rather than captured values.
local function wireButton(inst, rowKey, button)
    if button.scootWired then return end
    button.scootWired = true

    local isDebuff = (rowKey == "Debuffs")
    local cfg = inst.cfg
    local w, h = iconDims(cfg)

    -- The flow layout RESERVES elementWidth/elementHeight but does not size the
    -- element: CustomAuraContainerFlowLayoutMixin:ApplyElementLayout discards
    -- the width/height it computes, unlike Blizzard's TargetFrame override.
    -- The button is sized here or it is not sized at all.
    button:SetSize(w, h)

    -- Clicks off HERE and only here. A post-creation write is denied while
    -- auras are secret, which is exactly combat, which is exactly when a live
    -- click surface over the frame would steal targeting. Motion stays on for
    -- the intrinsic tooltip.
    pcall(button.SetMouseClickEnabled, button, false)

    local tex = button:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(button)
    applyCrop(tex, w, h)
    local iconOk, iconErr = pcall(button.SetIcon, button, tex)
    SetResult("wire.icon", iconOk and "ok" or ("FAILED: " .. SafeToString(iconErr)))
    button.scootIcon = tex

    local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cd:SetAllPoints(button)
    cd:EnableMouse(false)
    cd:SetDrawEdge(false)
    cd:SetDrawSwipe(true)
    cd:SetSwipeColor(0, 0, 0, 0.6)
    cd:SetHideCountdownNumbers(true)
    -- Reverse: the swipe GROWS as the aura drains, so a full icon is fresh and a
    -- dark one is about to fall off. This is a duration display, not a cooldown.
    -- false was carried over from the pre-12.1 file and was wrong there too; it
    -- made UFZ the only aura row in the addon running backwards
    -- (groupauras/icons.lua and the unit frame container pilot both use true, as
    -- do Blizzard's own nameplate, private aura and Cooldown Manager buff
    -- templates). Only visible once the engine started driving the swipe for
    -- real: the pre-12.1 degrade froze the row, so nothing drained to notice.
    cd:SetReverse(true)
    local cdOk, cdErr = pcall(button.SetDurationCooldown, button, cd)
    SetResult("wire.cooldown", cdOk and "ok" or ("FAILED: " .. SafeToString(cdErr)))
    button.scootCooldown = cd

    -- Text above the swipe so the stack count stays opaque regardless of drain
    -- progress (the groupauras/icons.lua pattern). A child-of-child FontString
    -- is accepted: scootauras wires its elements through exactly this shape and
    -- that path is proven.
    local textHost = CreateFrame("Frame", nil, button)
    textHost:SetAllPoints(button)
    textHost:EnableMouse(false)
    local lvlOk, lvl = pcall(button.GetFrameLevel, button)
    if lvlOk and type(lvl) == "number" and not issecretvalue(lvl) then
        textHost:SetFrameLevel(lvl + 5)
    end
    local countFS = textHost:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    countFS:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    -- No options table needed: ApplyApplicationCount renders nothing at or
    -- below one application on its own, which is what the old STACK_MIN = 2
    -- bought. (The old STACK_MAX = 99 "*" cap has no engine equivalent; counts
    -- above 99 now render as real numbers.)
    local cntOk, cntErr = pcall(button.SetApplicationCount, button, countFS, {})
    SetResult("wire.count", cntOk and "ok" or ("FAILED: " .. SafeToString(cntErr)))
    button.scootCount = countFS

    if isDebuff then
        -- One solid ring, sized purely by anchor inset: no texcoord math, so it
        -- is exact at any thickness and any icon aspect. BACKGROUND draws under
        -- the ARTWORK icon, so only the inset margin is ever visible.
        local ring = button:CreateTexture(nil, "BACKGROUND")
        ring:SetColorTexture(DEBUFF_RED[1], DEBUFF_RED[2], DEBUFF_RED[3], DEBUFF_RED[4])
        button.scootDispelRing = ring

        -- AddDispelTypeTexture APPENDS, so a re-registration must clear first;
        -- if the clear is refused the add must be skipped too, or entries
        -- accumulate on every pass.
        local clearOk = pcall(button.ClearDispelTypeTextures, button)
        if clearOk then
            -- The style field MUST resolve: the BorderWithIcon default would
            -- stamp Blizzard atlas art over the Scoot asset.
            local dOk, dErr = pcall(button.AddDispelTypeTexture, button, ring, {
                style = DISPEL_PRESERVE,
                showWhenHarmful = true,
                showWhenHelpful = false,
                showWithoutDispelType = true,
                customDispelColorMap = dispelColorMap(),
            })
            if dOk then
                SetResult("wire.dispel", "ok (school colors)")
            else
                -- The color map is the only part that can plausibly be
                -- rejected: its Color objects have to survive securecopy and
                -- the C options validator. Do NOT retry without it, because
                -- PreserveAsset with no map is exactly the path that renders
                -- black. Leaving the ring unregistered is strictly better: it
                -- keeps the static red from SetColorTexture and rides the
                -- button's own show/hide, which is the pre-12.1 behavior.
                pcall(button.ClearDispelTypeTextures, button)
                SetResult("wire.dispel",
                    "color map REJECTED, static red ring kept: " .. SafeToString(dErr))
            end
        else
            SetResult("wire.dispel", "skipped: ClearDispelTypeTextures refused")
        end
    end

    local entry = inst.auraContainers and inst.auraContainers[rowKey]
    if entry then
        entry.buttons[#entry.buttons + 1] = button
    end

    -- Style it NOW. The engine grows its pool in batches as auras arrive, so a
    -- button can be born long after the last ApplyStyle pass; without this it
    -- would render at defaults until something else triggered one. This sits
    -- inside initializeFrame, where the tree is guaranteed touchable, so this
    -- is the one moment a brand-new button can always be styled.
    styleButton(inst, rowKey, button, w, h, styleKey(cfg, w, h))
    Record("wired", rowKey)
end

--------------------------------------------------------------------------------
-- Container build and layout
--------------------------------------------------------------------------------

-- Buffs always sit closer to the frame: on a shared side the debuff container
-- anchors beyond the buff container instead of the frame edge. No count test is
-- needed any more -- an empty container lays out at zero size, so its far edge
-- coincides with its anchored edge and the debuff row lands exactly where the
-- unstacked case would have put it. The anchor answers the question the old
-- usedCount branch used to ask.
local function isStacked(cfg)
    return rowShown(cfg, "Buffs") and rowSide(cfg, "Buffs") == rowSide(cfg, "Debuffs")
end

local function contentSpan(inst, w)
    local left, right
    if UFZ._AuraContentSpan then
        left, right = UFZ._AuraContentSpan(inst)
    else
        left, right = 0, inst.cfg.width or 140
    end
    if right - left < w then
        -- Degenerate span (extreme config): fall back to the whole frame.
        left, right = 0, math.max(right, w)
    end
    return left, right - left
end

-- Flow options + group layout + the container's own anchor. All Tier 1: none of
-- these touch the button tree.
local function applyContainerLayout(inst, rowKey)
    local containers = inst.auraContainers
    local entry = containers and containers[rowKey]
    if not entry or not entry.container then return end
    local container = entry.container
    local cfg = inst.cfg

    local w, h = iconDims(cfg)
    local left, spanW = contentSpan(inst, w)
    local side = rowSide(cfg, rowKey)

    -- Line 1 nearest the frame, later lines growing away from it: the anchor
    -- point and the growth direction together, instead of a per-icon grid.
    pcall(container.SetFlowLayoutAxis, container, FLOW_HORIZONTAL)
    pcall(container.SetFlowLayoutAnchorPoint, container, side == "top" and "BOTTOMLEFT" or "TOPLEFT")
    pcall(container.SetFlowLayoutGrowthDirection, container, DIR_RIGHT,
        side == "top" and DIR_UP or DIR_DOWN)
    pcall(container.SetFlowLayoutPadding, container, 0, 0, 0, 0)
    -- The wrap width, replacing the old perLine arithmetic.
    pcall(container.SetFlowLayoutMaximumLineSize, container, spanW)
    pcall(container.SetAuraGroupLayout, container, rowKey, {
        elementSpacing = ICON_PAD,
        lineSpacing = LINE_GAP,
        elementWidth = w,
        elementHeight = h,
    })

    -- The shared Y-Offset shifts both rows' frame anchors (+ = up, house
    -- convention). A stacked debuff block needs none of its own: it rides the
    -- buff container, which already moved.
    local offY = tonumber(cfg.auraOffsetY) or 0
    local buffEntry = containers.Buffs
    local stacked = rowKey == "Debuffs" and isStacked(cfg)
        and buffEntry and buffEntry.container or nil

    local point, relTo, relPoint, x, y
    if side == "bottom" then
        if stacked then
            point, relTo, relPoint, x, y = "TOPLEFT", stacked, "BOTTOMLEFT", 0, -LINE_GAP
        else
            point, relTo, relPoint, x, y = "TOPLEFT", inst.frame, "BOTTOMLEFT", left, -FRAME_GAP + offY
        end
    else
        if stacked then
            point, relTo, relPoint, x, y = "BOTTOMLEFT", stacked, "TOPLEFT", 0, LINE_GAP
        else
            point, relTo, relPoint, x, y = "BOTTOMLEFT", inst.frame, "TOPLEFT", left, FRAME_GAP + offY
        end
    end

    -- AddAuraGroup stamps UntrustedLayoutScriptExecution on the container, and
    -- Blizzard's note on that line warns it makes a container awkward to anchor
    -- from addon context. Both Scoot regions carry the aspect, so the stacked anchor
    -- is legal, but a refusal would strand a row at its parent's origin with no
    -- error to show for it. Guard and record rather than assume.
    local aOk, aErr = pcall(function()
        container:ClearAllPoints()
        container:SetPoint(point, relTo, relPoint, x, y)
    end)
    SetResult("anchor." .. rowKey, aOk
        and ("ok: " .. point .. " -> " .. (stacked and "buff container" or "frame"))
        or ("FAILED: " .. SafeToString(aErr)))
end

-- Filter string and frame cap are live-reconfigurable and Tier 1. Groups can
-- never be removed (the engine's pooled frames would become unreachable), so a
-- row is retired by SetEnabled(false) + Hide, never by rebuilding.
local function applyGroupConfig(inst, rowKey)
    local entry = inst.auraContainers and inst.auraContainers[rowKey]
    if not entry or not entry.container then return end
    local container = entry.container
    local shown = rowVisible(inst, rowKey)

    pcall(container.SetAuraGroupFilterString, container, rowKey, rowFilter(inst, rowKey))
    pcall(container.SetAuraGroupMaxFrameCount, container, rowKey, rowMax(inst, rowKey))
    pcall(container.SetAuraGroupSortMethod, container, rowKey, SORT_DEFAULT, SORT_NORMAL)
    pcall(container.SetEnabled, container, shown)
    if shown then
        -- Guarded because ForceRefresh routes every subject change through
        -- here: a throw on this path would take the whole event handler with
        -- it, not just one row.
        pcall(container.Show, container)
        -- A hidden container stops tracking entirely and re-syncs on show, but
        -- kick anyway so a re-enable never waits for the next aura event.
        pcall(container.UpdateAllAuras, container)
    else
        pcall(container.Hide, container)
    end
end

local function buildContainer(inst, rowKey)
    local ok, container = pcall(CreateFrame, "AuraContainer", nil, inst.frame, "CustomAuraContainerTemplate")
    if not ok or not container then
        SetResult("build." .. rowKey .. ".container", "FAILED: " .. SafeToString(container))
        Record("build-fail", rowKey)
        return nil
    end
    SetResult("build." .. rowKey .. ".container", "ok")

    -- The engine drains parse/layout from an OnUpdate and needs a renderable
    -- rect from the first dirty mark; it replaces the size on every pass.
    container:SetSize(1, 1)
    container:Hide()

    local entry = { container = container, buttons = {} }
    inst.auraContainers[rowKey] = entry

    local cfg = inst.cfg
    local w, h = iconDims(cfg)
    local gOk, gErr = pcall(container.AddAuraGroup, container, rowKey, rowFilter(inst, rowKey), {
        maxFrameCount = rowMax(inst, rowKey),
        sortMethod = SORT_DEFAULT,
        sortDirection = SORT_NORMAL,
        -- Never candidateFilters.maxDuration: any non-nil value implicitly
        -- hides permanent auras.
        initializeFrame = function(button)
            local wok, werr = pcall(wireButton, inst, rowKey, button)
            if not wok then
                SetResult("wire." .. rowKey, "FAILED: " .. SafeToString(werr))
                Record("wire-fail", rowKey)
            end
        end,
        layout = {
            elementSpacing = ICON_PAD,
            lineSpacing = LINE_GAP,
            elementWidth = w,
            elementHeight = h,
        },
    })
    SetResult("build." .. rowKey .. ".group", gOk and "ok" or ("FAILED: " .. SafeToString(gErr)))
    if not gOk then
        Record("group-fail", rowKey)
        return entry
    end

    -- SetUnit LAST, and only after the group exists. SetUnit re-evaluates the
    -- container's event registrations and those are gated on the container
    -- having content: unit-first leaves UNIT_AURA unregistered, so the
    -- container would populate once and then never update again.
    local uOk, uErr = pcall(container.SetUnit, container, inst.unit)
    SetResult("build." .. rowKey .. ".setunit",
        uOk and ("ok: " .. tostring(inst.unit)) or ("FAILED: " .. SafeToString(uErr)))
    pcall(container.UpdateAllAuras, container)

    Record("built", rowKey)
    return entry
end

local function containersComplete(inst)
    local c = inst.auraContainers
    return (c and c.Buffs and c.Debuffs) and true or false
end

-- Idempotent. Containers are created once per instance and never destroyed:
-- Blizzard exposes no group removal, and rebuilding leaks a frame batch each
-- time. Caller must hold the structural-work gate.
local function ensureContainers(inst)
    if not inst.frame then return nil end
    inst.auraContainers = inst.auraContainers or {}
    for _, rowKey in ipairs(ROW_KEYS) do
        if not inst.auraContainers[rowKey] then
            buildContainer(inst, rowKey)
        end
    end
    return inst.auraContainers
end

local function styleAllButtons(inst)
    local containers = inst.auraContainers
    if not containers then return true end
    local cfg = inst.cfg
    local w, h = iconDims(cfg)
    local key = styleKey(cfg, w, h)
    local allOk = true
    for _, rowKey in ipairs(ROW_KEYS) do
        local entry = containers[rowKey]
        if entry then
            for _, button in ipairs(entry.buttons) do
                if not styleButton(inst, rowKey, button, w, h, key) then allOk = false end
            end
        end
    end
    return allOk
end

--------------------------------------------------------------------------------
-- Public hooks (the engine.lua seam; every entry nil-safe on the frame)
--------------------------------------------------------------------------------

--- Subject changed. This RE-ASSERTS each row's shown and enabled state and then
--- kicks. It must not be a bare kick, for two independent reasons, and missing
--- either one blanks the rows:
---
---   * update()'s no-unit branch runs HideAll, and hiding a container drops its
---     event registrations outright: ShouldRegisterForDynamicEvents is
---     IsVisible() and IsEnabled(). UpdateAllAuras on a hidden container
---     neither re-registers it nor draws anything, so a row hidden by clearing
---     the target stayed dead until a reload. That is the "they show until I
---     clear my target, then never again" report.
---   * SetUnit early-outs on an unchanged token and the engine does not
---     re-parse on a target swap while the frame stays shown, so a new subject
---     needs the explicit kick or the row keeps the old unit's auras.
---
--- Every call this makes is Tier 1, so it is legal mid-combat.
function Auras.ForceRefresh(inst)
    if not inst or not inst.auraContainers then return end
    for _, rowKey in ipairs(ROW_KEYS) do
        applyGroupConfig(inst, rowKey)
    end
end

--- Geometry only (placement setters, applyLayout tail). Tier 1 throughout.
function Auras.ApplyLayout(inst)
    if not inst or not inst.auraContainers then return end
    -- Buffs first: the debuff container may anchor to it.
    applyContainerLayout(inst, "Buffs")
    applyContainerLayout(inst, "Debuffs")
end

--- Styling (scale/shape/border/tooltip setters). TIER 2: queues when the
--- button tree is untouchable and re-runs on the restriction-lift drain.
function Auras.ApplyStyle(inst)
    if not inst or not inst.auraContainers then return end
    -- Layout first and unconditionally: it is Tier 1, and the flow layout's
    -- size reservation must track the icon-scale change even in the window
    -- where the buttons themselves cannot be resized yet.
    Auras.ApplyLayout(inst)
    if not Auras.CanDoStructuralWork() then
        pendingStyle[inst] = true
        Record("style-queued", instTag(inst))
        return
    end
    if not styleAllButtons(inst) then
        pendingStyle[inst] = true
        Record("style-refused", instTag(inst))
    end
end

--- Full pass (_ApplyAll, reset, Copy From, profile switch, mid-session enable).
function Auras.ApplyAll(inst)
    if not inst or not inst.frame then return end
    -- Zero-touch: nothing is built until a row is turned on.
    if not inst.auraContainers and not anyRowEnabled(inst.cfg) then return end

    -- Only the BUILD is Tier 2 (its buttons carry the access restriction), so
    -- that half waits for an open window and the rest runs now. A partial build
    -- is retried rather than latched, which is why completeness is per-row.
    if not containersComplete(inst) then
        if Auras.CanDoStructuralWork() then
            ensureContainers(inst)
        else
            pendingStyle[inst] = true
            Record("build-queued", instTag(inst))
        end
    end
    if not inst.auraContainers then return end

    -- Tier 1: filter string, frame cap, sort and enabled state all land
    -- immediately, so a row switched off mid-combat stops drawing at once.
    for _, rowKey in ipairs(ROW_KEYS) do
        applyGroupConfig(inst, rowKey)
    end
    Auras.ApplyStyle(inst)
end

--- The engine's no-unit blank, for a frame that stays shown without a subject.
--- Hiding a container also drops its event registrations, so on its own this is
--- a one-way door. ForceRefresh is what re-opens it, and every path that
--- re-acquires a subject runs through there.
function Auras.HideAll(inst)
    if not inst or not inst.auraContainers then return end
    for _, rowKey in ipairs(ROW_KEYS) do
        local entry = inst.auraContainers[rowKey]
        if entry and entry.container then entry.container:Hide() end
    end
end

--- Edit Mode: the stand-in has no subject, and engine buttons cannot be made to
--- fake auras. A previewed frame that DOES have a unit keeps its live rows,
--- which is the more accurate preview of the two.
function Auras.SetPreviewStandIn(inst, standIn)
    if not inst then return end
    -- Stamped on the instance, not acted on once: ForceRefresh now re-asserts
    -- row visibility on every subject change, so a preview that only hid the
    -- containers would be undone by the next one. Stamped even before the
    -- containers exist, so a build during a preview comes up suppressed.
    inst.auraStandIn = standIn and true or false
    if not inst.auraContainers then return end
    for _, rowKey in ipairs(ROW_KEYS) do
        applyGroupConfig(inst, rowKey)
    end
end

--------------------------------------------------------------------------------
-- Restriction-lift drain
--------------------------------------------------------------------------------
-- Tier 2 work refused while auras were secret is parked and re-run here. Aura
-- secrecy lifts on more edges than combat ends on, so the watcher listens to
-- all of them and re-probes rather than assuming. Fails open: a drain that
-- finds nothing queued costs one table walk.

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:RegisterEvent("ENCOUNTER_END")
watcher:RegisterEvent("ZONE_CHANGED_NEW_AREA")
watcher:SetScript("OnEvent", function()
    if not Auras.CanDoStructuralWork() then return end
    local queued = pendingStyle
    pendingStyle = {}
    Auras._pendingStyle = pendingStyle
    for inst in pairs(queued) do
        if inst.frame and not inst.previewActive then
            Auras.ApplyAll(inst)
        end
    end
    -- Instance IDs re-randomize across encounter and zone transitions and the
    -- container is not guaranteed an event at that moment; a kick is cheap.
    for _, inst in pairs(UFZ._instances) do
        if not inst.previewActive then Auras.ForceRefresh(inst) end
    end
    Record("drain", "lift")
end)
