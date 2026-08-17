-- customgroups/tracking.lua - Cooldown refresh, opacity pipeline, item ticker
local addonName, addon = ...

local CG = addon.CustomGroups
local activeIcons = CG._activeIcons
local MIN_CD_DURATION = CG._MIN_CD_DURATION

--------------------------------------------------------------------------------
-- Comparator Functions (OPT-10: module-level, eliminate per-call closures)
--------------------------------------------------------------------------------

local function checkItemCD(st, dur, en) return st and dur and dur > MIN_CD_DURATION and en and en ~= 0 end
local function checkCountGt1(c) return c and c > 1 end

-- OPT-10: Module-level helper for compound SetAlphaFromBoolean expression
local function setAlphaFromDurObj(cf, durObj, readyAlpha, cdAlpha)
    cf:SetAlphaFromBoolean(durObj:IsZero(), readyAlpha, cdAlpha)
end

-- Secret-safe desaturation: C++ evaluates secret bool → number, passed to SetDesaturation
local EvalBoolToValue = C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean

-- OPT-10: Scratch table for BuildGroupOpacityCtx (reused instead of allocating)
local opacityCtxScratch = {}

-- Item cooldown ticker handle
local itemTicker = nil

-- Track which FontStrings have been decoupled from parent alpha (weak keys for GC)
local textAlphaDecoupled = setmetatable({}, { __mode = "k" })

--------------------------------------------------------------------------------
-- Spell ID Resolution
--------------------------------------------------------------------------------

local function ResolveSpellID(baseID)
    if C_Spell.GetOverrideSpell then
        local ok, overrideID = pcall(C_Spell.GetOverrideSpell, baseID)
        if ok and type(overrideID) == "number"
           and not (issecretvalue and issecretvalue(overrideID))
           and overrideID ~= 0 then
            return overrideID
        end
    end
    return baseID
end

--------------------------------------------------------------------------------
-- Cooldown Refresh
--------------------------------------------------------------------------------

-- Returns cdInfo (or nil) for use by the merged opacity pipeline.
local function RefreshSpellCooldown(icon)
    if not icon.entry or icon.entry.type ~= "spell" then return nil end
    local spellID = ResolveSpellID(icon.entry.id)
    icon._chargeDesatHandled = nil

    -- Refresh texture to match current override state
    -- GetSpellTexture handles overrides internally via base ID
    local currentTexture = C_Spell.GetSpellTexture(icon.entry.id)
    if currentTexture then
        icon.Icon:SetTexture(currentTexture)
    end

    -- Fetch cdInfo once (used by charge fallthrough and regular path, returned to caller)
    local cdInfo = C_Spell.GetSpellCooldown(spellID)

    -- Charges: maxCharges is non-secret (12.0.1b), currentCharges remains secret
    local chargeInfo = C_Spell.GetSpellCharges(spellID)
    if chargeInfo then
        if chargeInfo.maxCharges and chargeInfo.maxCharges > 1 then
            -- Show charge count (SetText accepts secret values natively)
            icon.CountText:SetText(chargeInfo.currentCharges)
            icon.CountText:Show()

            if chargeInfo.isActive then
                -- Charges recharging — show cooldown swipe via DurationObject (taint-free).
                -- 12.0.5's zero-span-at-max-charges case is handled by the isActive=false
                -- branch below (Cooldown:Clear), so no extra guard is needed here.
                local chargeDurObj = C_Spell.GetSpellChargeDuration(spellID)
                if chargeDurObj then
                    icon.Cooldown:SetCooldownFromDurationObject(chargeDurObj)
                end
                -- Desaturation: all charges spent → 1, otherwise → 0
                -- currentCharges is secret; try direct comparison, fall back to
                -- regular spell CD duration (non-zero when spell is fully unavailable)
                local chargeOk, isZeroCharges = pcall(function() return chargeInfo.currentCharges == 0 end)
                if chargeOk then
                    icon.Icon:SetDesaturation(isZeroCharges and 1 or 0)
                elseif cdInfo and not cdInfo.isOnGCD then
                    local regDurObj = C_Spell.GetSpellCooldownDuration(spellID)
                    if regDurObj and EvalBoolToValue then
                        icon.Icon:SetDesaturation(EvalBoolToValue(regDurObj:IsZero(), 0, 1))
                    else
                        icon.Icon:SetDesaturation(0)
                    end
                else
                    icon.Icon:SetDesaturation(0)
                end
            else
                -- All charges full
                icon.Cooldown:Clear()
                icon.Icon:SetDesaturation(0)
            end
            icon._chargeDesatHandled = true
            return cdInfo
        end
        icon.CountText:Hide()
    else
        icon.CountText:Hide()
    end

    -- Regular cooldown
    if not cdInfo then return nil end

    -- isOnGCD is NeverSecret — always safe
    if cdInfo.isOnGCD then
        return cdInfo
    end

    -- Use DurationObject for taint-free cooldown display (12.0.1b+)
    -- Returns zero-span when inactive; SetCooldownFromDurationObject clears automatically
    local durObj = C_Spell.GetSpellCooldownDuration(spellID)
    if durObj then
        icon.Cooldown:SetCooldownFromDurationObject(durObj)
    else
        icon.Cooldown:Clear()
    end

    return cdInfo
end

-- Returns (ok, isOnCD) for use by the merged opacity pipeline.
local function RefreshItemCooldown(icon)
    if not icon.entry or icon.entry.type ~= "item" then return false, false end
    local itemID = icon.entry.id

    local startTime, duration, isEnabled = C_Container.GetItemCooldown(itemID)
    local ok, isOnCD = pcall(checkItemCD, startTime, duration, isEnabled)

    if ok then
        if isOnCD then
            icon.Cooldown:SetCooldown(startTime, duration)
        else
            icon.Cooldown:Clear()
        end
    elseif startTime and duration then
        -- Secret fallback: pass directly to SetCooldown
        icon.Cooldown:SetCooldown(startTime, duration)
    end

    -- Stack count
    local count = C_Item.GetItemCount(itemID, false, true)
    local countOk, showCount = pcall(checkCountGt1, count)
    if countOk and showCount then
        icon.CountText:SetText(count)
        icon.CountText:Show()
    elseif not countOk and count then
        -- Secret: SetText accepts secret values
        icon.CountText:SetText(count)
        icon.CountText:Show()
    else
        icon.CountText:Hide()
    end

    return ok, isOnCD
end

--------------------------------------------------------------------------------
-- Per-Icon Cooldown Opacity
--------------------------------------------------------------------------------
-- Uses SetAlphaFromBoolean with secret boolean from Duration Object IsZero()
-- to dim icons that are on cooldown. GCD is filtered via isOnGCD (NeverSecret).
-- SetAlphaFromBoolean evaluates secret booleans in C++ without Lua-side inspection.
-- Text opacity can be controlled independently via opacityOnCooldownText.
-- Targets the Cooldown frame (not its FontString) because Blizzard's C++ cooldown
-- renderer resets the FontString's alpha every frame, overriding the styled values.
--------------------------------------------------------------------------------

local function applyCGTextAlpha(cooldownFrame, durObj, containerAlpha, textDimAlpha, isGCD, isOffCooldownMode)
    if not cooldownFrame then return end
    pcall(cooldownFrame.SetIgnoreParentAlpha, cooldownFrame, true)
    textAlphaDecoupled[cooldownFrame] = true
    if isGCD then
        pcall(cooldownFrame.SetAlpha, cooldownFrame, containerAlpha)
    else
        local readyAlpha = containerAlpha
        local cdAlpha = math.min(containerAlpha, textDimAlpha)
        if isOffCooldownMode then readyAlpha, cdAlpha = cdAlpha, readyAlpha end
        pcall(setAlphaFromDurObj, cooldownFrame, durObj, readyAlpha, cdAlpha)
    end
end

local function applyCGTextAlphaItem(cooldownFrame, isOnCD, containerAlpha, textDimAlpha, isOffCooldownMode)
    if not cooldownFrame then return end
    pcall(cooldownFrame.SetIgnoreParentAlpha, cooldownFrame, true)
    textAlphaDecoupled[cooldownFrame] = true
    local readyAlpha = containerAlpha
    local cdAlpha = math.min(containerAlpha, textDimAlpha)
    if isOffCooldownMode then readyAlpha, cdAlpha = cdAlpha, readyAlpha end
    pcall(cooldownFrame.SetAlpha, cooldownFrame, isOnCD and cdAlpha or readyAlpha)
end

local function resetCGTextAlpha(cooldownFrame)
    if cooldownFrame and textAlphaDecoupled[cooldownFrame] then
        pcall(cooldownFrame.SetIgnoreParentAlpha, cooldownFrame, false)
        pcall(cooldownFrame.SetAlpha, cooldownFrame, 1.0)
        textAlphaDecoupled[cooldownFrame] = nil
    end
end

-- Pre-compute per-group opacity constants. Returns nil when both settings are
-- at 100% (fast path: no opacity work needed for this group).
local function BuildGroupOpacityCtx(groupIndex)
    local component = addon.Components["customGroup" .. groupIndex]
    if not component or not component.db then return nil end

    local iconSetting = tonumber(component.db.opacityOnCooldown) or 100
    local textSetting = tonumber(component.db.opacityOnCooldownText) or 100

    if iconSetting >= 100 and textSetting >= 100 then return nil end

    local containerAlpha = CG._getGroupOpacityForState(groupIndex)
    local iconDimAlpha = iconSetting / 100
    if iconSetting < 100 and containerAlpha > 0 and containerAlpha < 1.0 then
        iconDimAlpha = math.min(1.0, iconDimAlpha / containerAlpha)
    end

    local mode = component.db.cooldownOpacityMode
    local isOffCooldownMode = (mode == "offCooldown")

    opacityCtxScratch.iconSetting = iconSetting
    opacityCtxScratch.textSetting = textSetting
    opacityCtxScratch.containerAlpha = containerAlpha
    opacityCtxScratch.needsTextOverride = not isOffCooldownMode and (textSetting ~= iconSetting)
    opacityCtxScratch.iconDimAlpha = iconDimAlpha
    opacityCtxScratch.textDimAlpha = textSetting / 100
    opacityCtxScratch.isOffCooldownMode = isOffCooldownMode
    return opacityCtxScratch
end

-- Apply spell opacity using pre-fetched cdInfo and pre-built ctx.
-- cdInfo comes from RefreshSpellCooldown's return value.
local function ApplySpellOpacityFromState(icon, cdInfo, ctx)
    local spellID = ResolveSpellID(icon.entry.id)

    -- Desaturation: fully C++-evaluated chain (secret-safe in combat)
    if icon._chargeDesatHandled then
        -- Charge path already set correct desaturation state
    elseif not cdInfo or cdInfo.isOnGCD then
        icon.Icon:SetDesaturation(0)
    else
        local durObj = C_Spell.GetSpellCooldownDuration(spellID)
        if durObj and durObj.IsZero and EvalBoolToValue then
            -- IsZero()=true → ready → desat 0; IsZero()=false → on CD → desat 1
            -- All three APIs are AllowedWhenTainted — entire chain stays in C++
            icon.Icon:SetDesaturation(EvalBoolToValue(durObj:IsZero(), 0, 1))
        else
            icon.Icon:SetDesaturation(0)
        end
    end

    if not ctx then
        icon:SetAlpha(1.0)
        if icon.Cooldown then resetCGTextAlpha(icon.Cooldown) end
        return
    end

    if not cdInfo then
        local ra = ctx.isOffCooldownMode and ctx.iconDimAlpha or 1.0
        icon:SetAlpha(ra)
        if ctx.needsTextOverride and icon.Cooldown then resetCGTextAlpha(icon.Cooldown) end
        return
    end

    local isGCD = cdInfo.isOnGCD
    -- Always fetch fresh DurationObject (returns live state each frame)
    local durObj = not isGCD and C_Spell.GetSpellCooldownDuration(spellID) or nil

    -- Pre-compute ready/cd alphas based on mode
    local readyAlpha, cdAlpha = 1.0, ctx.iconDimAlpha
    if ctx.isOffCooldownMode then readyAlpha, cdAlpha = cdAlpha, readyAlpha end

    -- Icon frame opacity
    if ctx.iconSetting >= 100 then
        icon:SetAlpha(1.0)
    elseif isGCD then
        icon:SetAlpha(readyAlpha)
    elseif durObj and durObj.IsZero then
        icon:SetAlphaFromBoolean(durObj:IsZero(), readyAlpha, cdAlpha)
    else
        icon:SetAlpha(readyAlpha)
    end

    -- Text opacity (independent when text != icon setting)
    if ctx.needsTextOverride and icon.Cooldown then
        if isGCD then
            applyCGTextAlpha(icon.Cooldown, nil, ctx.containerAlpha, ctx.textDimAlpha, true, ctx.isOffCooldownMode)
        elseif durObj and durObj.IsZero then
            applyCGTextAlpha(icon.Cooldown, durObj, ctx.containerAlpha, ctx.textDimAlpha, false, ctx.isOffCooldownMode)
        else
            resetCGTextAlpha(icon.Cooldown)
        end
    elseif not ctx.needsTextOverride and icon.Cooldown then
        resetCGTextAlpha(icon.Cooldown)
    end
end

-- Apply item opacity using pre-fetched state and pre-built ctx.
local function ApplyItemOpacityFromState(icon, ok, isOnCD, ctx)
    -- Desaturation (always applied, independent of opacity settings)
    if ok then
        icon.Icon:SetDesaturation(isOnCD and 1 or 0)
    else
        icon.Icon:SetDesaturation(0)
    end

    if not ctx then
        icon:SetAlpha(1.0)
        if icon.Cooldown then resetCGTextAlpha(icon.Cooldown) end
        return
    end

    -- Icon frame opacity (swap dim direction in off-cooldown mode)
    if ok then
        local dimmed = ctx.isOffCooldownMode and (not isOnCD) or (not ctx.isOffCooldownMode and isOnCD)
        icon:SetAlpha(dimmed and ctx.iconDimAlpha or 1.0)
    else
        icon:SetAlpha(1.0)
    end

    -- Text opacity (independent when text != icon setting)
    if ctx.needsTextOverride and icon.Cooldown then
        if ok then
            local effectiveOnCD = ctx.isOffCooldownMode and (not isOnCD) or (not ctx.isOffCooldownMode and isOnCD)
            applyCGTextAlphaItem(icon.Cooldown, effectiveOnCD, ctx.containerAlpha, ctx.textDimAlpha)
        else
            resetCGTextAlpha(icon.Cooldown)
        end
    elseif not ctx.needsTextOverride and icon.Cooldown then
        resetCGTextAlpha(icon.Cooldown)
    end
end

-- Full opacity application (opacity-only path, fetches its own cooldown state).
-- Used by UpdateGroupCooldownOpacities for combat/target change events.
local function ApplyCooldownOpacity(icon, groupIndex, ctx)
    ctx = ctx or BuildGroupOpacityCtx(groupIndex)

    if not icon.entry then
        icon:SetAlpha(1.0)
        if icon.Cooldown then resetCGTextAlpha(icon.Cooldown) end
        return
    end

    if icon.entry.type == "spell" then
        local spellID = ResolveSpellID(icon.entry.id)
        local cdInfo = C_Spell.GetSpellCooldown(spellID)
        ApplySpellOpacityFromState(icon, cdInfo, ctx)
    elseif icon.entry.type == "item" then
        local startTime, duration, isEnabled = C_Container.GetItemCooldown(icon.entry.id)
        local ok, isOnCD = pcall(checkItemCD, startTime, duration, isEnabled)
        ApplyItemOpacityFromState(icon, ok, isOnCD, ctx)
    end
end

--------------------------------------------------------------------------------
-- Public Tracking API
--------------------------------------------------------------------------------

function CG._OnIconCooldownDone(cooldownFrame)
    local icon = cooldownFrame:GetParent()
    if icon and icon.entry and icon._groupIndex then
        icon.Icon:SetDesaturation(0)
        icon._chargeDesatHandled = nil
        ApplyCooldownOpacity(icon, icon._groupIndex)
    end
end

function CG._UpdateGroupCooldownOpacities(groupIndex)
    local ctx = BuildGroupOpacityCtx(groupIndex)
    for _, icon in ipairs(activeIcons[groupIndex]) do
        if icon.entry then
            ApplyCooldownOpacity(icon, groupIndex, ctx)
        end
    end
end

function CG._RefreshAllSpellCooldowns()
    for gi = 1, CG.NUM_GROUPS do
        local ctx = BuildGroupOpacityCtx(gi)
        for _, icon in ipairs(activeIcons[gi]) do
            if icon.entry and icon.entry.type == "spell" then
                local cdInfo = RefreshSpellCooldown(icon)
                ApplySpellOpacityFromState(icon, cdInfo, ctx)
            end
        end
    end
end

function CG._RefreshAllItemCooldowns()
    for gi = 1, CG.NUM_GROUPS do
        local ctx = BuildGroupOpacityCtx(gi)
        for _, icon in ipairs(activeIcons[gi]) do
            if icon.entry and icon.entry.type == "item" then
                local ok, isOnCD = RefreshItemCooldown(icon)
                ApplyItemOpacityFromState(icon, ok, isOnCD, ctx)
            end
        end
    end
end

function CG._RefreshAllCooldowns(groupIndex)
    local ctx = BuildGroupOpacityCtx(groupIndex)
    local icons = activeIcons[groupIndex]
    for _, icon in ipairs(icons) do
        if icon.entry then
            if icon.entry.type == "spell" then
                local cdInfo = RefreshSpellCooldown(icon)
                ApplySpellOpacityFromState(icon, cdInfo, ctx)
            elseif icon.entry.type == "item" then
                local ok, isOnCD = RefreshItemCooldown(icon)
                ApplyItemOpacityFromState(icon, ok, isOnCD, ctx)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Item Ticker Management
--------------------------------------------------------------------------------

function CG._ManageItemTicker(currentGroupItemCount, groupIndex)
    -- Recount items across all groups for ticker management
    local totalItems = 0
    for gi = 1, CG.NUM_GROUPS do
        if gi == groupIndex then
            totalItems = totalItems + currentGroupItemCount
        else
            for _, icon in ipairs(activeIcons[gi]) do
                if icon.entry and icon.entry.type == "item" then
                    totalItems = totalItems + 1
                end
            end
        end
    end

    -- Manage item ticker
    if totalItems > 0 and not itemTicker then
        itemTicker = C_Timer.NewTicker(0.5, function()
            CG._RefreshAllItemCooldowns()
        end)
    elseif totalItems == 0 and itemTicker then
        itemTicker:Cancel()
        itemTicker = nil
    end
end
