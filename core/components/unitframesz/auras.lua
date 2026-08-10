-- unitframesz/auras.lua - Unit Frames Z: buff/debuff icon rows
--
-- Addon-owned aura icon rows above/below the Z frames. Enumeration rides
-- C_UnitAuras.GetUnitAuraInstanceIDs -- a never-secret table of plain instance
-- IDs, engine-sorted -- so counting, compares and layout math stay plain; every
-- per-icon read flows through a secret-tolerant setter (SetTexture,
-- SetCooldownFromDurationObject, GetAuraApplicationDisplayCount -> SetText).
-- Aura data is used immediately and never stored, compared or table-keyed.
--
-- The rows are UNBOXED: they hang outside the config-derived envelope (the
-- absorb-text precedent, engine.lua computeEnvelope doctrine) and never call
-- applyEnvelope. Rows and icons are children of inst.frame, so they inherit
-- Overall Scale and the opacity trio implicitly -- but they are NOT
-- anchor-protected (only inst.frame itself is, via the secure clickButton), so
-- everything here is legal in combat and no regen queue exists in this file.
--
-- Icons are click-TRANSPARENT by design (user decision 2026-08-05, unchanged):
-- clicks always fall through to the secure click-to-target overlay. Hover
-- tooltips (user decision 2026-08-06, reversing the original no-tooltip
-- stance) ride MOTION-ONLY mouse -- SetMouseClickEnabled(false) +
-- SetMouseMotionEnabled, the CooldownViewerItemMixin:SetTooltipsShown pair.
-- Neither API is HasRestrictions (IsProtectedFunction only, the same class as
-- the Hide/SetPoint calls this file already makes), so the cfg.auraTooltips
-- flip stays combat-legal on these insecure icons and the no-regen-queue
-- doctrine above holds. The tooltip is the global GameTooltip via
-- SetUnitAuraByAuraInstanceID -- the TooltipDataHandler secure delegate
-- re-derives everything from the plain instance ID, so full tooltips render
-- even under combat secrecy -- IsForbidden-guarded in every handler.
--
-- TODO(dispel-tint): C_UnitAuras.GetAuraDispelTypeColor takes a color curve
-- keyed by an undocumented numeric dispel type ID (zero Blizzard call sites,
-- no enum in shipped Lua). Follow-up: a debug harness building a Step color
-- curve with sentinel colors at x = 0..10, evaluated against live known
-- debuffs (Magic/Curse/Disease/Poison/Bleed) to pin the ID map empirically;
-- then per-dispel border tint ships via SetVertexColor (AllowedWhenTainted).

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
-- Snug on purpose, tucked INTO the envelope (user 2026-08-06, three jumps:
-- 5 read as "far too much", 1 still left "considerable dead space", and -3
-- still needed a +12 nudge in-game -- the envelope edge carries reserve slack
-- past the visible ink, and the rows may legally overlap it: they're unboxed
-- children, not envelope content). The -15 rebase makes that verified in-game
-- position the new 0-point of the user-facing Y-Offset (cfg.auraOffsetY, + = up).
local FRAME_GAP = -15  -- px from the frame edge to the first line (negative = inside)
local STACK_MIN = 2    -- GetAuraApplicationDisplayCount: "" below this ("hide at 1 stack")
local STACK_MAX = 99   -- above this the engine renders "*"

local FALLBACK_ICON = 134400  -- INV_Misc_QuestionMark

local ROW_KEYS = { "Buffs", "Debuffs" }  -- cfg key stems: aura<Key><Suffix>

--------------------------------------------------------------------------------
-- Tooltips (motion-only mouse; the CooldownViewer SetTooltipsShown pattern)
--------------------------------------------------------------------------------
-- Handlers are shared file-scope closures wired ONCE at icon creation; whether
-- they can fire is the per-icon mouse-motion flip in applyIconMouse (styleIcon
-- re-applies it every pass, memoized). Aura identity rides plain stamps
-- (auraUnit/auraInstanceID/auraFilter) written by refreshRow and cleared by
-- releaseIcon -- instance IDs are never secret, so no issecretvalue dance, but
-- a released icon has nil stamps and OnEnter must bail. The set call is
-- pcall-wrapped per house doctrine (a stale ID mid-race must not error).

local function iconTooltipSet(icon)
    local ok = pcall(GameTooltip.SetUnitAuraByAuraInstanceID, GameTooltip,
        icon.auraUnit, icon.auraInstanceID, icon.auraFilter)
    if ok then
        GameTooltip:Show()
    else
        GameTooltip:Hide()
    end
end

local function onIconEnter(self)
    if GameTooltip:IsForbidden() then return end
    if not self.auraInstanceID then return end  -- released/stale icon
    -- Edit Mode owns its own tooltip system (ui/v2/editmode/Tooltip.lua): the
    -- preview never talks to GameTooltip, so the frozen live icons stay quiet.
    local inst = self:GetParent().inst
    if inst and inst.previewActive then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    iconTooltipSet(self)
end

local function onIconLeave(self)
    if GameTooltip:IsForbidden() then return end
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end

-- GameTooltip's own OnUpdate calls owner:UpdateTooltip() every 0.2s while
-- shown -- no OnUpdate of ours. A held-open tooltip live-follows the icon's
-- CURRENT stamp, so an aura swap under the cursor re-reads the new aura (the
-- Blizzard aura-button behavior).
local function onIconUpdateTooltip(self)
    if GameTooltip:IsForbidden() then return end
    if not GameTooltip:IsOwned(self) then return end
    if not self.auraInstanceID then
        GameTooltip:Hide()  -- released under a held-open tooltip
        return
    end
    iconTooltipSet(self)
end

-- The cfg.auraTooltips flip, memoized per icon (styleIcon runs for every used
-- icon on every layout pass; the C calls pay only on a real transition).
-- Clicks stay disabled ALWAYS -- the secure click-to-target overlay under the
-- rows keeps every click. The OFF flip drops a tooltip the icon still owns.
local function applyIconMouse(inst, icon)
    local enable = inst.cfg.auraTooltips and true or false
    if icon.mouseMotionOn == enable then return end
    icon.mouseMotionOn = enable
    icon:SetMouseClickEnabled(false)
    icon:SetMouseMotionEnabled(enable)
    if not enable and not GameTooltip:IsForbidden()
        and GameTooltip:IsOwned(icon) then
        GameTooltip:Hide()
    end
end

--------------------------------------------------------------------------------
-- Containers and icon pool
--------------------------------------------------------------------------------

local function ensureRows(inst)
    if not inst.frame then return nil end
    if inst.auraRows then return inst.auraRows end
    local rows = {}
    for _, rowKey in ipairs(ROW_KEYS) do
        local row = CreateFrame("Frame", nil, inst.frame)
        row:EnableMouse(false)
        row:Hide()
        row.icons = {}       -- index-keyed pool; icons are never destroyed
        row.shownIDs = {}    -- last-rendered plain instance-ID array
        row.usedCount = 0
        row.inst = inst      -- OnEnter reads the preview gate through this
        rows[rowKey] = row
    end
    inst.auraRows = rows
    return rows
end

local function acquireIcon(row, i)
    local icon = row.icons[i]
    if icon then return icon end

    icon = CreateFrame("Frame", nil, row)
    icon:EnableMouse(false)
    icon.mouseMotionOn = false  -- applyIconMouse memo; matches the line above
    -- Wired once for the icon's lifetime; applyIconMouse decides whether they
    -- can ever fire.
    icon:SetScript("OnEnter", onIconEnter)
    icon:SetScript("OnLeave", onIconLeave)
    icon.UpdateTooltip = onIconUpdateTooltip

    local tex = icon:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(icon)
    icon.tex = tex

    local cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    cd:SetAllPoints(icon)
    cd:EnableMouse(false)
    cd:SetDrawEdge(false)
    cd:SetDrawSwipe(true)
    cd:SetSwipeColor(0, 0, 0, 0.6)
    cd:SetHideCountdownNumbers(true)
    cd:SetReverse(false)
    icon.cd = cd

    -- Text overlay above the swipe so the stack count stays fully opaque
    -- regardless of drain progress (the groupauras/icons.lua pattern).
    local textOverlay = CreateFrame("Frame", nil, icon)
    textOverlay:SetAllPoints(icon)
    textOverlay:SetFrameLevel((cd:GetFrameLevel() or icon:GetFrameLevel()) + 5)
    icon.textOverlay = textOverlay

    local count = textOverlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
    icon.countFS = count

    icon:Hide()
    row.icons[i] = icon
    return icon
end

local function releaseIcon(icon)
    icon:Hide()
    -- Tooltip stamps: nil means "not showing an aura" -- OnEnter bails and a
    -- held-open tooltip hides on its next UpdateTooltip tick.
    icon.auraUnit = nil
    icon.auraInstanceID = nil
    icon.auraFilter = nil
    icon.cd:Clear()
    -- ClearText, never SetText(""): the FS held a secret display-count string
    -- and only ClearText releases the Text aspect.
    if icon.countFS.ClearText then icon.countFS:ClearText() end
    pcall(icon.tex.SetTexture, icon.tex, nil)
end

--------------------------------------------------------------------------------
-- Styling
--------------------------------------------------------------------------------

local function iconDims(cfg)
    local base = BASE_ICON * (tonumber(cfg.auraIconScale) or 100) / 100
    if addon.IconRatio then
        return addon.IconRatio.CalculateDimensions(base, tonumber(cfg.auraTallWideRatio) or 0)
    end
    return base, base
end

-- Crop (not stretch) non-square icons via texcoords -- the buffs.lua pattern.
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

-- Debuff borders are the bedrock "this is a debuff" indicator (user decision
-- 2026-08-06): always on, always red, independent of the border toggle and the
-- tint. Style and thickness customizations still apply to them. Red matches
-- Blizzard's DebuffTypeColor["none"]; the future dispel-type tint (header
-- TODO) would override per type, with this red as the non-dispellable
-- fallback.
local DEBUFF_RED = { 0.8, 0, 0, 1 }

local function styleIcon(inst, icon, w, h, isDebuff)
    local cfg = inst.cfg
    icon:SetSize(w, h)
    applyCrop(icon.tex, w, h)
    applyIconMouse(inst, icon)

    if (cfg.auraBorderEnable or isDebuff) and addon.ApplyIconBorderStyle then
        local thickness = tonumber(cfg.auraBorderThickness) or 1
        if thickness < 1 then thickness = 1 elseif thickness > 8 then thickness = 8 end
        local tintEnabled = isDebuff or (cfg.auraBorderTintEnable and true or false)
        local color
        if isDebuff then
            color = DEBUFF_RED
        elseif tintEnabled then
            color = {
                cfg.auraBorderTintR or 1, cfg.auraBorderTintG or 1,
                cfg.auraBorderTintB or 1, cfg.auraBorderTintA or 1,
            }
        end
        -- No db/thicknessKey/tintColorKey opts: UFZ cfg is flat scalars and
        -- those opts expect a nested color table to read back from.
        addon.ApplyIconBorderStyle(icon.tex, cfg.auraBorderStyle or "square", {
            thickness = thickness,
            tintEnabled = tintEnabled,
            color = color,
            defaultThickness = 1,
        })
        -- SetPoint anchoring to Textures doesn't always propagate size changes;
        -- resize the wrapper container explicitly (buffs.lua pattern).
        local container = borderContainer(icon.tex)
        if container and container.SetSize then
            container:SetSize(w, h)
        end
    elseif addon.Borders and addon.Borders.HideAll then
        addon.Borders.HideAll(icon.tex)
        local container = borderContainer(icon.tex)
        if container then
            addon.Borders.HideAll(container)
        end
    end
end

--------------------------------------------------------------------------------
-- Enumeration
--------------------------------------------------------------------------------

local function rowFilter(inst, rowKey)
    if rowKey == "Buffs" then
        return inst.cfg.auraOnlyPlayerBuffs and "HELPFUL|PLAYER" or "HELPFUL"
    end
    -- Blizzard TargetFrame parity: nameplate-flagged player DoTs are part of
    -- the target's debuff row; plain HARMFUL for the player's own frame.
    if inst.unit == "player" then
        return "HARMFUL"
    end
    return "HARMFUL|INCLUDE_NAME_PLATE_ONLY"
end

-- Pull the row's instance-ID list: a never-secret table of plain numbers,
-- sorted engine-side (the API default is Unsorted -- pass Default explicitly).
-- Never Lua-sort aura data.
local function pullIDs(inst, rowKey)
    local maxN = tonumber(inst.cfg["aura" .. rowKey .. "Max"]) or 16
    local ok, ids = pcall(C_UnitAuras.GetUnitAuraInstanceIDs, inst.unit,
        rowFilter(inst, rowKey), maxN,
        Enum.UnitAuraSortRule.Default, Enum.UnitAuraSortDirection.Normal)
    if not ok or type(ids) ~= "table" then return nil end
    return ids
end

local function sameIDs(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

--------------------------------------------------------------------------------
-- Content refresh
--------------------------------------------------------------------------------

local function clearRow(row)
    for i = 1, row.usedCount do
        releaseIcon(row.icons[i])
    end
    row.shownIDs = {}
    row.usedCount = 0
    row:Hide()
end

-- Repaint one row's icon content. Returns true when the visible set changed
-- (the caller re-runs layout only then).
local function refreshRow(inst, rowKey)
    local row = inst.auraRows[rowKey]
    local cfg = inst.cfg

    if not cfg["aura" .. rowKey .. "Show"] then
        local wasPopulated = row.usedCount > 0
        clearRow(row)
        return wasPopulated
    end

    local ids = pullIDs(inst, rowKey) or {}
    if sameIDs(ids, row.shownIDs) then return false end

    local unit = inst.unit
    local filter = rowFilter(inst, rowKey)  -- tooltip stamp; same string the pull used
    for i = 1, #ids do
        local iid = ids[i]
        local icon = acquireIcon(row, i)

        -- Tooltip stamps: plain values only (the ID list is never secret, the
        -- filter is our own string). Same-filter matters: the tooltip getter
        -- adds HELPFUL|HARMFUL itself, but INCLUDE_NAME_PLATE_ONLY must ride
        -- along or a nameplate-flagged target DoT won't resolve.
        icon.auraUnit = unit
        icon.auraInstanceID = iid
        icon.auraFilter = filter

        -- Texture: read ONLY .icon from the aura payload -- possibly secret,
        -- and SetTexture accepts secrets. Never touch .applications/.duration/
        -- .dispelName, never compare or table-key anything from it.
        local dOk, data = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, iid)
        if dOk and data then
            pcall(icon.tex.SetTexture, icon.tex, data.icon)
        else
            pcall(icon.tex.SetTexture, icon.tex, FALLBACK_ICON)
        end

        -- Swipe: the duration object is plain userdata holding secrets
        -- internally; clearIfZero=true blanks the swipe on permanent auras.
        local cOk, dur = pcall(C_UnitAuras.GetAuraDuration, unit, iid)
        if cOk and dur then
            pcall(icon.cd.SetCooldownFromDurationObject, icon.cd, dur, true)
        else
            icon.cd:Clear()
        end

        -- Stacks: the engine renders "" below STACK_MIN, so hide-at-one-stack
        -- happens API-side with no comparison here. Release the Text aspect
        -- before every write.
        if icon.countFS.ClearText then icon.countFS:ClearText() end
        local sOk, stackText = pcall(C_UnitAuras.GetAuraApplicationDisplayCount,
            unit, iid, STACK_MIN, STACK_MAX)
        if sOk and stackText ~= nil then
            pcall(icon.countFS.SetText, icon.countFS, stackText)
        end

        icon:Show()
    end

    for i = #ids + 1, row.usedCount do
        releaseIcon(row.icons[i])
    end

    row.shownIDs = ids
    row.usedCount = #ids
    return true
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

-- Geometry for BOTH rows every time -- the same-side stacking couples them.
-- All inputs are plain numbers (cfg + plain ID counts): legal in combat.
--
-- Rows LEFT-align on the content span (UFZ._AuraContentSpan, engine.lua): the
-- leftmost element's left edge -- the centered numbers column on align="left"
-- frames, the name's (ink-true) left edge on align="right" -- not the frame
-- edge, which is the envelope's superset reserve (user report 2026-08-06).
-- Icons fill left-to-right on both handednesses; the span's far end caps the
-- wrap so a full line stays over the content too.
local function layoutRows(inst)
    local rows = inst.auraRows
    if not rows then return end
    local cfg = inst.cfg

    local w, h = iconDims(cfg)
    local left, right
    if UFZ._AuraContentSpan then
        left, right = UFZ._AuraContentSpan(inst)
    else
        left, right = 0, cfg.width or 140
    end
    if right - left < w then
        -- Degenerate span (extreme config): fall back to the whole frame.
        left, right = 0, math.max(right, w)
    end
    local spanW = right - left
    local perLine = math.max(1, math.floor((spanW + ICON_PAD) / (w + ICON_PAD)))

    for _, rowKey in ipairs(ROW_KEYS) do
        local row = rows[rowKey]
        local n = row.usedCount
        if n == 0 or not cfg["aura" .. rowKey .. "Show"] then
            row:Hide()
        else
            local lines = math.ceil(n / perLine)
            row:SetSize(spanW, lines * h + (lines - 1) * LINE_GAP)

            local side = cfg["aura" .. rowKey .. "Loc"] == "top" and "top" or "bottom"
            -- Buffs always sit closer to the frame: on a shared side the
            -- debuff block anchors beyond the buff block instead of the edge.
            local stacked = rowKey == "Debuffs"
                and cfg.auraBuffsShow
                and (cfg.auraBuffsLoc == "top" and "top" or "bottom") == side
                and rows.Buffs.usedCount > 0

            -- The shared Y-Offset shifts both rows' frame anchors (+ = up,
            -- house convention). A stacked debuff block needs none of its own:
            -- it rides the buff row, which already moved.
            local offY = tonumber(cfg.auraOffsetY) or 0

            row:ClearAllPoints()
            if side == "bottom" then
                if stacked then
                    row:SetPoint("TOPLEFT", rows.Buffs, "BOTTOMLEFT", 0, -LINE_GAP)
                else
                    row:SetPoint("TOPLEFT", inst.frame, "BOTTOMLEFT", left, -FRAME_GAP + offY)
                end
            else
                if stacked then
                    row:SetPoint("BOTTOMLEFT", rows.Buffs, "TOPLEFT", 0, LINE_GAP)
                else
                    row:SetPoint("BOTTOMLEFT", inst.frame, "TOPLEFT", left, FRAME_GAP + offY)
                end
            end

            -- Lines grow away from the frame, so line 1 is always the nearest
            -- (the row's frame-side edge).
            for i = 1, n do
                local line = math.floor((i - 1) / perLine)
                local col = (i - 1) % perLine
                local x = col * (w + ICON_PAD)
                local y = line * (h + LINE_GAP)

                local icon = row.icons[i]
                styleIcon(inst, icon, w, h, rowKey == "Debuffs")
                icon:ClearAllPoints()
                if side == "bottom" then
                    icon:SetPoint("TOPLEFT", row, "TOPLEFT", x, -y)
                else
                    icon:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", x, y)
                end
            end

            row:Show()
        end
    end
end

--------------------------------------------------------------------------------
-- Public hooks (the engine.lua seam; every entry nil-safe on the frame)
--------------------------------------------------------------------------------

local function anyRowEnabled(cfg)
    return (cfg.auraBuffsShow or cfg.auraDebuffsShow) and true or false
end

--- Content refresh (the UNIT_AURA path): re-pull, skip-compare, repaint and
--- re-layout only when the visible set changed.
function Auras.Refresh(inst)
    if not inst or not inst.frame then return end
    if not inst.auraRows and not anyRowEnabled(inst.cfg) then return end
    if not ensureRows(inst) then return end
    local changed = refreshRow(inst, "Buffs")
    changed = refreshRow(inst, "Debuffs") or changed
    if changed then layoutRows(inst) end
end

--- Refresh that distrusts the shown-ID cache: target swaps (a new subject can
--- coincidentally reuse ID values), instance-ID re-randomization, filter and
--- limit changes.
function Auras.ForceRefresh(inst)
    if not inst then return end
    local rows = inst.auraRows
    if rows then
        rows.Buffs.shownIDs = {}
        rows.Debuffs.shownIDs = {}
    end
    Auras.Refresh(inst)
end

--- Geometry only (placement setter, applyLayout tail).
function Auras.ApplyLayout(inst)
    if not inst or not inst.auraRows then return end
    layoutRows(inst)
end

--- Styling (scale/shape/border setters). styleIcon runs inside layout.
function Auras.ApplyStyle(inst)
    Auras.ApplyLayout(inst)
end

--- Full pass (_ApplyAll, reset, Copy From, profile switch, mid-session enable).
function Auras.ApplyAll(inst)
    if not inst or not inst.frame then return end
    if not inst.auraRows and not anyRowEnabled(inst.cfg) then return end
    Auras.ForceRefresh(inst)
end

--- The engine's no-unit blank: release everything, hide both rows.
function Auras.HideAll(inst)
    if not inst or not inst.auraRows then return end
    clearRow(inst.auraRows.Buffs)
    clearRow(inst.auraRows.Debuffs)
end

--------------------------------------------------------------------------------
-- Reset watcher
--------------------------------------------------------------------------------
-- Aura instance IDs re-randomize on encounter/challenge/PVP-match transitions
-- (the classauras precedent), and UNIT_AURA is not guaranteed to fire at that
-- moment -- a stale swipe would linger. A full forced re-pull self-heals.

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("ENCOUNTER_START")
watcher:RegisterEvent("CHALLENGE_MODE_START")
watcher:RegisterEvent("PVP_MATCH_ACTIVE")
watcher:SetScript("OnEvent", function()
    for _, inst in pairs(UFZ._instances) do
        if not inst.previewActive then
            Auras.ForceRefresh(inst)
        end
    end
end)
