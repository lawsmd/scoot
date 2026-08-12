-- classauras/cdmborrow.lua - CDM icon hiding and rescan logic
local addonName, addon = ...

local CA = addon.ClassAuras

-- Local aliases (resolved at load time — core.lua loads first)
local GetDB = CA._GetDB
local playerClassToken = CA._playerClassToken

--------------------------------------------------------------------------------
-- CDM Borrow: Hide CDM icons via SetAlphaFromBoolean
--------------------------------------------------------------------------------
-- When a class aura takes over display, the corresponding CDM icon is hidden
-- to avoid duplicates. Display itself is engine-side (engine.lua); this file
-- only manages the CDM icon's alpha state.

local cdmBorrow = {
    hookInstalled = false,
}
-- Track which CDM item frames already have Show/SetShown hooks installed
local hookedItemFrames = setmetatable({}, { __mode = "k" })
-- Track CDM item frames hidden via SetAlphaFromBoolean -- itemFrame -> auraId
local hiddenItemFrames = setmetatable({}, { __mode = "k" })

-- Module-level function for pcall: checks if child's linked spells contain spellId
local function checkLinkedSpells(child, spellId)
    local ci = child:GetCooldownInfo()
    if ci and ci.linkedSpellIDs then
        for _, lid in ipairs(ci.linkedSpellIDs) do
            if lid == spellId then return true end
        end
    end
    return false
end

local function searchViewer(children, spellId)
    if not children then return nil end
    for _, child in ipairs(children) do
        -- GetBaseSpellID() is a plain Lua table read (self.cooldownInfo.spellID),
        -- populated by Blizzard's untainted code -- returns real data even in combat.
        local idOk, childSpellId = pcall(child.GetBaseSpellID, child)
        if idOk and not issecretvalue(childSpellId) and childSpellId == spellId then
            return child
        end
    end
    -- Fallback: search linkedSpellIDs (e.g., 188389 Flame Shock is linked under base 470411)
    for _, child in ipairs(children) do
        local ciOk, found = pcall(checkLinkedSpells, child, spellId)
        if ciOk and found then
            return child
        end
    end
    return nil
end

-- Per-invocation children cache: built once per RescanForCDMBorrow call
local viewerChildrenCache = {}

local function getViewerChildren(viewerName)
    if viewerChildrenCache[viewerName] ~= nil then
        return viewerChildrenCache[viewerName]
    end
    local viewer = _G[viewerName]
    if not viewer then
        viewerChildrenCache[viewerName] = false
        return false
    end
    local ok, children = pcall(function() return { viewer:GetChildren() } end)
    if ok and children then
        viewerChildrenCache[viewerName] = children
        return children
    end
    viewerChildrenCache[viewerName] = false
    return false
end

local function FindCDMItemForSpell(spellId)
    -- Search icon layout first (most common), then bar layout
    local iconChildren = getViewerChildren("BuffIconCooldownViewer")
    local barChildren = getViewerChildren("BuffBarCooldownViewer")
    return searchViewer(iconChildren, spellId)
        or searchViewer(barChildren, spellId)
end

local function BindCDMBorrowTarget(itemFrame, aura)
    -- Install Show/SetShown hooks to re-apply alpha when CDM redisplays the icon
    if not hookedItemFrames[itemFrame] then
        hookedItemFrames[itemFrame] = true

        hooksecurefunc(itemFrame, "Show", function(self)
            if hiddenItemFrames[self] then
                self:SetAlphaFromBoolean(false, 1, 0)
            end
        end)

        hooksecurefunc(itemFrame, "SetShown", function(self, shown)
            if shown and hiddenItemFrames[self] then
                self:SetAlphaFromBoolean(false, 1, 0)
            end
        end)
    end

    -- Apply or remove CDM icon hiding. Hide only when this aura's engine
    -- wiring succeeded this session (a plain per-session boolean, never
    -- presence-derived): a failed or not-yet-built engine aura renders
    -- nothing, and hiding Blizzard's icon too would blank both displays.
    local db = GetDB(aura)
    local wantHide = db and db.enabled and (db.hideFromCDM ~= false)
        and CA.Engine.IsWired(aura.id)
    if wantHide then
        itemFrame:SetAlphaFromBoolean(false, 1, 0)
        hiddenItemFrames[itemFrame] = aura.id
    elseif hiddenItemFrames[itemFrame] then
        itemFrame:SetAlphaFromBoolean(true, 1, 0)
        hiddenItemFrames[itemFrame] = nil
    end
end

local function RestoreHiddenCDMFrames(auraId)
    for frame, id in pairs(hiddenItemFrames) do
        if id == auraId then
            frame:SetAlphaFromBoolean(true, 1, 0)
            hiddenItemFrames[frame] = nil
        end
    end
end

-- Clears every hidden-frame mapping and restores alpha. Used after Blizzard's
-- CooldownViewerMixin:RefreshLayout shuffles the item pool (12.0.5+), which
-- reassigns pooled frames to different auras and makes our per-frame mapping
-- stale. Callers should schedule a rescan afterward to re-hide the correct frames.
local function ResetAllHiddenFrames()
    for frame in pairs(hiddenItemFrames) do
        pcall(frame.SetAlphaFromBoolean, frame, true, 1, 0)
    end
    wipe(hiddenItemFrames)
end

local function RescanForCDMBorrow()
    local auras = CA._classAuras[playerClassToken]
    if not auras then return end

    -- Clear per-invocation children cache (rebuilt lazily via getViewerChildren)
    wipe(viewerChildrenCache)

    for _, aura in ipairs(auras) do
        if aura.cdmBorrow then
            local state = CA._activeAuras[aura.id]
            if state then
                local db = GetDB(aura)
                if not db or not db.enabled then
                    RestoreHiddenCDMFrames(aura.id)
                elseif UnitExists(aura.unit) then
                    local cdmId = aura.cdmSpellId or aura.auraSpellId
                    local itemFrame = FindCDMItemForSpell(cdmId)
                    if not itemFrame and aura.cdmSpellId and aura.auraSpellId then
                        itemFrame = FindCDMItemForSpell(aura.auraSpellId)
                    end
                    if itemFrame then
                        BindCDMBorrowTarget(itemFrame, aura)
                    else
                        -- CDM icon may be gone due to target switch; restore
                        -- the hide binding so a pool-recycled frame stays visible.
                        RestoreHiddenCDMFrames(aura.id)
                    end
                end
            end
        end
    end
end

-- Rescan debounce: coalesces multiple CDM events in one frame into a single rescan
local rescanPending = false
local function ScheduleRescan()
    if rescanPending then return end
    rescanPending = true
    C_Timer.After(0, function()
        rescanPending = false
        RescanForCDMBorrow()
    end)
end

-- Global-mixin hooks that keep the alpha-hide bindings correct across CDM
-- frame-pool recycling. These are mixin-table hooks on Blizzard globals (safe
-- per Rule 11 — not system-frame tree members), installed once.
local function InstallMixinHooks()
    if cdmBorrow.hookInstalled then return end

    -- Hook RefreshData to catch icon pool recycling (for CDM icon alpha re-find)
    local buffMixin = _G.CooldownViewerBuffIconItemMixin
    if buffMixin and buffMixin.RefreshData then
        hooksecurefunc(buffMixin, "RefreshData", function()
            ScheduleRescan()
        end)
    end

    -- Hook OnAuraInstanceInfoCleared (for CDM icon alpha re-find)
    local baseMixin = _G.CooldownViewerItemMixin
    if baseMixin and baseMixin.OnAuraInstanceInfoCleared then
        hooksecurefunc(baseMixin, "OnAuraInstanceInfoCleared", function()
            ScheduleRescan()
        end)
    end

    -- Hook RefreshLayout: 12.0.5 added an early-exit in CooldownViewerMixin:OnUnitAura
    -- for isFullUpdate that calls self:RefreshLayout(). RefreshLayout does
    -- itemFramePool:ReleaseAll() then re-acquires frames, reassigning pooled
    -- Lua frame objects to different auras. Our hiddenItemFrames map goes stale
    -- across this -- clear it and let the subsequent rescan re-hide the right frames.
    local viewerMixin = _G.CooldownViewerMixin
    if viewerMixin and viewerMixin.RefreshLayout then
        hooksecurefunc(viewerMixin, "RefreshLayout", function()
            ResetAllHiddenFrames()
            ScheduleRescan()
        end)
    end

    cdmBorrow.hookInstalled = true
end

--------------------------------------------------------------------------------
-- Namespace Promotions
--------------------------------------------------------------------------------

CA._RescanForCDMBorrow = RescanForCDMBorrow
CA._InstallMixinHooks = InstallMixinHooks

-- Expose for debug
CA._cdmBorrow = cdmBorrow
CA._rescanForCDMBorrow = function() RescanForCDMBorrow() end
