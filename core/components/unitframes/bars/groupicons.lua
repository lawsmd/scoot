--------------------------------------------------------------------------------
-- bars/groupicons.lua
-- Role icon and group lead icon customization for the party and raid frames.
-- One set of CompactUnitFrame hooks serves both families; family state is read
-- at call time through the module tables, so this file loads before either
-- family core.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Utils = addon.BarsUtils

-- Direct upvalue to the event-driven guard (editmode/core.lua loads first in TOC).
local isEditModeActive = addon.EditMode.IsEditModeActiveOrOpening

-- Weak tables for roleIcon:Show() post-hook (maps roleIcon → frame, tracks hooked icons)
local _roleIconToFrame = setmetatable({}, { __mode = "kv" })
local _hookedRoleIcons = setmetatable({}, { __mode = "k" })

-- Named function for role icon customization (also used by safety net and fallbacks)
local function applyCustomRoleIcon(frame)
    if isEditModeActive() then return end
    if not frame then return end
    if frame.IsForbidden and frame:IsForbidden() then return end

    -- Only process frames Scoot styles
    if not Utils.isPartyFrame(frame) and not Utils.isRaidFrame(frame) then return end

    -- Check if Scoot has active overlays
    local db = addon and addon.db and addon.db.profile
    local groupFrames = db and rawget(db, "groupFrames") or nil
    if not groupFrames then return end
    local cfg = Utils.isPartyFrame(frame) and rawget(groupFrames, "party")
             or Utils.isRaidFrame(frame) and rawget(groupFrames, "raid")
             or nil
    if not cfg then return end

    local okR, roleIcon = pcall(function() return frame.roleIcon end)
    if not okR or not roleIcon then return end

    -- Kept off addon.Enforce: restyle hook; re-applies atlas, scale, and position, not just a hide.
    -- Install Show hook (once per roleIcon) to re-apply after Blizzard atlas resets.
    -- Blizzard's CompactUnitFrame_UpdateRoleIcon calls SetAtlas(default) then Show()
    -- then SetSize(secret) which errors, so the post-hook never fires. This Show hook
    -- fires BEFORE the SetSize error, so the custom atlas is applied reliably.
    _roleIconToFrame[roleIcon] = frame
    if not _hookedRoleIcons[roleIcon] then
        _hookedRoleIcons[roleIcon] = true
        pcall(function()
            hooksecurefunc(roleIcon, "Show", function(self)
                local f = _roleIconToFrame[self]
                if f then pcall(applyCustomRoleIcon, f) end
            end)
        end)
    end

    -- Desaturation from DB toggle (applied at the very end)
    local shouldDesaturate = rawget(cfg, "roleIconDesaturate") and true or false

    -- A) Draw layer elevation (only when Scoot overlays active)
    local hasOverlay = (cfg.healthBarTexture and cfg.healthBarTexture ~= "default")
                    or (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default")
    if not hasOverlay then
        local textCfg = rawget(cfg, "textPlayerName") or nil
        hasOverlay = textCfg and Utils.hasCustomTextSettings(textCfg)
    end
    if hasOverlay and roleIcon.SetDrawLayer then
        pcall(roleIcon.SetDrawLayer, roleIcon, "OVERLAY", 6)
    end

    -- B) Custom positioning (independent of icon set)
    do
        local anchor = rawget(cfg, "roleIconAnchor")
        if anchor and anchor ~= "default" and roleIcon.IsShown and roleIcon:IsShown() then
            local offsetX = tonumber(rawget(cfg, "roleIconOffsetX")) or 0
            local offsetY = tonumber(rawget(cfg, "roleIconOffsetY")) or 0
            pcall(roleIcon.ClearAllPoints, roleIcon)
            pcall(roleIcon.SetPoint, roleIcon, anchor, frame, anchor, offsetX, offsetY)
        end
    end

    -- B2) Visibility filtering (no early returns — B3 and C must always run)
    do
        local vis = rawget(cfg, "roleIconVisibility")
        if vis and roleIcon.IsShown and roleIcon:IsShown() then
            if vis == "hideAll" then
                pcall(roleIcon.SetAlpha, roleIcon, 0)
            elseif vis == "hideDPS" then
                local unit
                local okU, u = pcall(function() return frame.displayedUnit or frame.unit end)
                if okU and u then unit = u end
                if unit then
                    local okRole, role = pcall(UnitGroupRolesAssigned, unit)
                    local isDamager = false
                    if okRole and role then
                        pcall(function()
                            if type(role) == "string" and role == "DAMAGER" then isDamager = true end
                        end)
                    end
                    if isDamager then
                        pcall(roleIcon.SetAlpha, roleIcon, 0)
                    else
                        pcall(roleIcon.SetAlpha, roleIcon, 1)
                    end
                else
                    -- Couldn't determine unit: ensure visible
                    pcall(roleIcon.SetAlpha, roleIcon, 1)
                end
            elseif vis == "showAll" then
                -- Restore from previously hidden state
                pcall(roleIcon.SetAlpha, roleIcon, 1)
            end
        end
    end

    -- B3) Scale
    do
        local scale = tonumber(rawget(cfg, "roleIconScale"))
        if scale then
            local size = 17 * scale / 100
            pcall(roleIcon.SetSize, roleIcon, size, size)
        end
    end

    -- C) Custom icon set swap (independent of overlay state)
    local iconSet = rawget(cfg, "roleIconSet")
    local skipSwap = false
    if not iconSet or iconSet == "default" then
        skipSwap = true
    end
    -- NOTE: Do NOT skip swap when roleIcon:IsShown() is false.
    -- Blizzard may momentarily hide the icon during UpdateRoleIcon; setting
    -- the texture while hidden ensures the custom icon shows when re-shown.

    if not skipSwap then
        local unit
        local okU, u = pcall(function() return frame.displayedUnit or frame.unit end)
        if okU and u then unit = u end

        if unit then
            -- Don't override vehicle icons (pcall wraps boolean test on potentially secret return)
            local isVehicle = false
            pcall(function()
                if UnitInVehicle(unit) and UnitHasVehicleUI(unit) then
                    isVehicle = true
                end
            end)

            if not isVehicle then
                local okRole, role = pcall(UnitGroupRolesAssigned, unit)
                -- Wrap comparison in pcall: role may be a secret value in tainted contexts
                local validRole = nil
                if okRole and role then
                    pcall(function()
                        if type(role) == "string" and role ~= "NONE" then validRole = role end
                    end)
                end
                if validRole then
                    local atlases = Utils.ROLE_ICON_ATLASES and Utils.ROLE_ICON_ATLASES[iconSet]
                    if atlases and atlases[validRole] then
                        pcall(roleIcon.SetAtlas, roleIcon, atlases[validRole])
                    end
                end
            end
        end
    end

    -- Final: apply desaturation state (always runs, cleans up stale state too)
    pcall(roleIcon.SetDesaturated, roleIcon, shouldDesaturate)
end

-- Expose for cross-file access
addon._applyCustomRoleIcon = applyCustomRoleIcon

-- Hook CompactUnitFrame_UpdateRoleIcon to:
-- A) Elevate roleIcon draw layer above Scoot overlay containers
-- B) Swap to custom icon set if configured
if not addon._RoleIconVisibilityHookInstalled then
    addon._RoleIconVisibilityHookInstalled = true
    if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateRoleIcon then
        _G.hooksecurefunc("CompactUnitFrame_UpdateRoleIcon", applyCustomRoleIcon)
    end
end

-- Safety net: re-apply custom role icons on roster/role events
-- Needed because Blizzard's CompactUnitFrame_UpdateRoleIcon may error on
-- tainted roleIcon widgets (secret value from GetHeight), causing the
-- post-hook to never fire. This directly applies without going through
-- Blizzard's function.
if not addon._RoleIconSafetyNetInstalled then
    addon._RoleIconSafetyNetInstalled = true
    local safetyNetTimer = nil
    local function onRoleIconEvent(event, unit)
        if isEditModeActive() then return end
        -- Filter unit-specific events to party units only
        if unit and event ~= "GROUP_ROSTER_UPDATE" and event ~= "PLAYER_ROLES_ASSIGNED" then
            if unit ~= "player" and not unit:match("^party%d$") then return end
        end
        local db = addon and addon.db and addon.db.profile
        local gf = db and rawget(db, "groupFrames") or nil
        if not gf then return end
        local pCfg = rawget(gf, "party")
        local rCfg = rawget(gf, "raid")
        local hasAny = (pCfg and (rawget(pCfg, "roleIconSet") or rawget(pCfg, "roleIconAnchor") or rawget(pCfg, "roleIconVisibility")
                              or rawget(pCfg, "roleIconDesaturate") or rawget(pCfg, "roleIconScale")
                              or rawget(pCfg, "roleIconOffsetX") or rawget(pCfg, "roleIconOffsetY")))
                    or (rCfg and (rawget(rCfg, "roleIconSet") or rawget(rCfg, "roleIconAnchor") or rawget(rCfg, "roleIconVisibility")
                              or rawget(rCfg, "roleIconDesaturate") or rawget(rCfg, "roleIconScale")
                              or rawget(rCfg, "roleIconOffsetX") or rawget(rCfg, "roleIconOffsetY")))
        if not hasAny then return end
        if safetyNetTimer then safetyNetTimer:Cancel() end
        safetyNetTimer = C_Timer.NewTimer(0.15, function()
            safetyNetTimer = nil
            if isEditModeActive() then return end
            -- Direct apply (bypasses Blizzard's function which may error on tainted roleIcon)
            for i = 1, 5 do
                local f = _G["CompactPartyFrameMember" .. i]
                if f then pcall(applyCustomRoleIcon, f) end
            end
            for i = 1, 40 do
                local f = _G["CompactRaidFrame" .. i]
                if f then pcall(applyCustomRoleIcon, f) end
            end
            for g = 1, 8 do
                for m = 1, 5 do
                    local f = _G["CompactRaidGroup" .. g .. "Member" .. m]
                    if f then pcall(applyCustomRoleIcon, f) end
                end
            end
        end)
    end
    addon.Events.On("UnitFrames:GroupIcons", "GROUP_ROSTER_UPDATE", onRoleIconEvent)
    addon.Events.On("UnitFrames:GroupIcons", "PLAYER_ROLES_ASSIGNED", onRoleIconEvent)
    addon.Events.On("UnitFrames:GroupIcons", "UNIT_PET", onRoleIconEvent)
    addon.Events.On("UnitFrames:GroupIcons", "UNIT_NAME_UPDATE", onRoleIconEvent)
end

-- Re-apply role icons after Edit Mode exit transition window (1.0s _exitingEditMode flag).
-- During the transition, Blizzard rebuilds frames (resetting atlas to default) but the
-- Show hook and safety net are suppressed by isEditModeActive(). This fires after the
-- flag clears so custom icons are restored.
if not addon._RoleIconEditModeExitInstalled and _G.EventRegistry then
    addon._RoleIconEditModeExitInstalled = true
    EventRegistry:RegisterCallback("EditMode.Exit", function()
        C_Timer.After(1.1, function()
            if isEditModeActive() then return end
            if addon.ApplyPartyRoleIcons then addon.ApplyPartyRoleIcons() end
            if addon.ApplyRaidRoleIcons then addon.ApplyRaidRoleIcons() end
        end)
    end, "ScootRoleIconEditModeExit")
end

--------------------------------------------------------------------------
-- Group Lead Icon
--------------------------------------------------------------------------

local function applyGroupLeadIcon(frame)
    if isEditModeActive() then return end
    if not frame then return end
    if frame.IsForbidden and frame:IsForbidden() then return end

    local isParty = Utils.isPartyFrame(frame)
    local isRaid  = Utils.isRaidFrame(frame)
    if not isParty and not isRaid then return end

    -- DB read via rawget (no AceDB metamethods)
    local db = addon and addon.db and addon.db.profile
    local groupFrames = db and rawget(db, "groupFrames") or nil
    if not groupFrames then return end
    local cfg = isParty and rawget(groupFrames, "party")
             or isRaid  and rawget(groupFrames, "raid")
             or nil
    if not cfg then return end

    -- Feature disabled? Hide existing icon and bail
    local show = rawget(cfg, "groupLeadIconShow")
    local state = isParty and addon.BarsPartyFrames and addon.BarsPartyFrames._ensureState(frame)
               or isRaid  and addon.BarsRaidFrames and addon.BarsRaidFrames._ensureState(frame)
               or nil

    if not show then
        if state and state.groupLeadIcon then
            pcall(state.groupLeadIcon.Hide, state.groupLeadIcon)
        end
        return
    end

    -- Unit detection (secret-safe)
    local unit
    local okU, u = pcall(function() return frame.displayedUnit or frame.unit end)
    if okU and u then unit = u end
    if not unit then
        if state and state.groupLeadIcon then
            pcall(state.groupLeadIcon.Hide, state.groupLeadIcon)
        end
        return
    end

    -- Leader check (secret-safe: guard type)
    local okL, isLeader = pcall(UnitIsGroupLeader, unit)
    if not okL or type(isLeader) ~= "boolean" or not isLeader then
        if state and state.groupLeadIcon then
            pcall(state.groupLeadIcon.Hide, state.groupLeadIcon)
        end
        return
    end

    -- Lazy creation — stored in state table, NOT on frame (taint-safe)
    if not state then return end
    if not state.groupLeadIcon then
        local okC, tex = pcall(frame.CreateTexture, frame, nil, "OVERLAY", nil, 7)
        if not okC or not tex then return end
        pcall(tex.SetAtlas, tex, "UI-HUD-UnitFrame-Player-Group-LeaderIcon")
        state.groupLeadIcon = tex
    end

    local icon = state.groupLeadIcon

    -- Icon set (desaturation)
    local iconSet = rawget(cfg, "groupLeadIconSet") or "default"
    pcall(icon.SetDesaturated, icon, iconSet == "desaturated")

    -- Scale (base 16px)
    local scale = tonumber(rawget(cfg, "groupLeadIconScale")) or 100
    local size = 16 * scale / 100
    pcall(icon.SetSize, icon, size, size)

    -- Position
    local anchor = rawget(cfg, "groupLeadIconAnchor") or "TOPLEFT"
    local offsetX = tonumber(rawget(cfg, "groupLeadIconOffsetX")) or 0
    local offsetY = tonumber(rawget(cfg, "groupLeadIconOffsetY")) or 0
    pcall(icon.ClearAllPoints, icon)
    pcall(icon.SetPoint, icon, anchor, frame, anchor, offsetX, offsetY)

    -- Show
    pcall(icon.Show, icon)
end

-- Expose for cross-file access
addon._applyGroupLeadIcon = applyGroupLeadIcon

-- Hook CompactUnitFrame_UpdateRoleIcon to also apply group lead icon.
-- Fires during CompactUnitFrame_UpdateAll for every compact frame,
-- providing reliable timing after unit assignment.
if not addon._GroupLeadIconRoleIconHookInstalled then
    addon._GroupLeadIconRoleIconHookInstalled = true
    if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateRoleIcon then
        _G.hooksecurefunc("CompactUnitFrame_UpdateRoleIcon", function(frame)
            if isEditModeActive() then return end
            if not frame then return end
            local isParty = Utils.isPartyFrame(frame)
            local isRaid  = Utils.isRaidFrame(frame)
            if not isParty and not isRaid then return end
            local db = addon and addon.db and addon.db.profile
            local gf = db and rawget(db, "groupFrames") or nil
            if not gf then return end
            local cfg = isParty and rawget(gf, "party")
                     or isRaid  and rawget(gf, "raid")
                     or nil
            if not cfg or not rawget(cfg, "groupLeadIconShow") then return end
            pcall(applyGroupLeadIcon, frame)
        end)
    end
end

-- Event frame: PARTY_LEADER_CHANGED / GROUP_ROSTER_UPDATE
if not addon._GroupLeadIconEventInstalled then
    addon._GroupLeadIconEventInstalled = true
    local leadIconTimer = nil
    local function onLeadIconEvent()
        if isEditModeActive() then return end
        -- Early-out if feature is off in both party and raid
        local db = addon and addon.db and addon.db.profile
        local gf = db and rawget(db, "groupFrames") or nil
        if not gf then return end
        local pCfg = rawget(gf, "party")
        local rCfg = rawget(gf, "raid")
        local hasAny = (pCfg and rawget(pCfg, "groupLeadIconShow"))
                    or (rCfg and rawget(rCfg, "groupLeadIconShow"))
        if not hasAny then return end
        -- Debounce 0.15s
        if leadIconTimer then leadIconTimer:Cancel() end
        leadIconTimer = C_Timer.NewTimer(0.15, function()
            leadIconTimer = nil
            if isEditModeActive() then return end
            for i = 1, 5 do
                local f = _G["CompactPartyFrameMember" .. i]
                if f then pcall(applyGroupLeadIcon, f) end
            end
            for i = 1, 40 do
                local f = _G["CompactRaidFrame" .. i]
                if f then pcall(applyGroupLeadIcon, f) end
            end
            for g = 1, 8 do
                for m = 1, 5 do
                    local f = _G["CompactRaidGroup" .. g .. "Member" .. m]
                    if f then pcall(applyGroupLeadIcon, f) end
                end
            end
        end)
    end
    addon.Events.On("UnitFrames:GroupIcons", "PARTY_LEADER_CHANGED", onLeadIconEvent)
    addon.Events.On("UnitFrames:GroupIcons", "GROUP_ROSTER_UPDATE", onLeadIconEvent)
end

-- SetUnit hook: deferred to avoid taint
if not addon._GroupLeadSetUnitHookInstalled then
    addon._GroupLeadSetUnitHookInstalled = true
    if _G.hooksecurefunc and _G.CompactUnitFrame_SetUnit then
        _G.hooksecurefunc("CompactUnitFrame_SetUnit", function(frame)
            if isEditModeActive() then return end
            if not frame then return end
            -- Only fire if feature is active for this frame type
            local isParty = Utils.isPartyFrame(frame)
            local isRaid  = Utils.isRaidFrame(frame)
            if not isParty and not isRaid then return end
            local db = addon and addon.db and addon.db.profile
            local gf = db and rawget(db, "groupFrames") or nil
            if not gf then return end
            local cfg = isParty and rawget(gf, "party")
                     or isRaid  and rawget(gf, "raid")
                     or nil
            if not cfg or not rawget(cfg, "groupLeadIconShow") then return end
            C_Timer.After(0, function()
                pcall(applyGroupLeadIcon, frame)
            end)
        end)
    end
end
