-- vertical.lua - Tracked Bars vertical mode: data mirroring and stack layout
--
-- 12.1 combat contract (aura data is secret in instances/M+/PvP combat):
--   * Stacks stay live through forwarded hook data: SetValue/SetMinMaxValues and
--     SetText args (secret or plain) are forwarded raw to Scoot widgets, and the
--     SetIsActive arg drives stack visibility via SetAlphaFromBoolean -- the
--     engine branches on the secret, Lua never does.
--   * Rebuilds remain allowed in combat; every read in the build path is
--     guarded and fails OPEN (a secret state builds the stack and lets the
--     alpha mirror decide). A stack darkened by a secret keeps its layout slot
--     until the next plain-state rebuild (restriction-lift watcher in
--     suppression.lua).
--   * Stack-count text under secrecy shows Blizzard's raw text ("" unless the
--     count is > 1), matching Blizzard's own display.
--   * Suppression (the anti-linger authority) is suspended while auras are
--     secret; bar appear/disappear timing is Blizzard's engine timing.
--   * Membership changes mid-combat ride Blizzard's own signals (Show/Hide,
--     SetIsActive, RefreshLayout); anything Blizzard cannot surface mid-combat,
--     this module cannot either. Style/settings changes still defer to regen
--     via the core _pendingApplyStyles path.
local addonName, addon = ...

local TB = addon.TB
local getState = addon.ComponentsUtil._getState

--------------------------------------------------------------------------------
-- Vertical Mode: Data Mirroring Hooks
--------------------------------------------------------------------------------

function TB.installDataMirrorHooks(child)
    if TB.hookedBarItems[child] then return end
    TB.hookedBarItems[child] = true

    local mirror = TB.barItemMirror[child]
    if not mirror then
        mirror = {}
        TB.barItemMirror[child] = mirror
    end

    local barFrame = (child.GetBarFrame and child:GetBarFrame()) or child.Bar
    if barFrame then
        if barFrame.SetValue then
            hooksecurefunc(barFrame, "SetValue", function(_, val)
                local m = TB.barItemMirror[child]
                if not m then return end
                if not issecretvalue(val) then
                    m.barValue = val
                    m.valueTime = GetTime()
                end
                if TB.verticalModeActive then
                    if m.vertStatusBar then
                        pcall(m.vertStatusBar.SetValue, m.vertStatusBar, val)
                    end
                    if m.vertLockBar then
                        pcall(m.vertLockBar.SetValue, m.vertLockBar, val)
                    end
                end
            end)
        end
        if barFrame.SetMinMaxValues then
            hooksecurefunc(barFrame, "SetMinMaxValues", function(_, minVal, maxVal)
                local m = TB.barItemMirror[child]
                if not m then return end
                if not issecretvalue(minVal) then m.barMin = minVal end
                if not issecretvalue(maxVal) then m.barMax = maxVal end
                if not TB.verticalModeActive then return end
                -- B mirrors Blizzard 1:1.
                if m.vertStatusBar then
                    pcall(m.vertStatusBar.SetMinMaxValues, m.vertStatusBar, minVal, maxVal)
                end
                -- A locks to the first range after activation. Blizzard's
                -- deactivation write is a literal plain (0, 0)
                -- (CooldownViewer.lua RefreshCooldownInfo) and releases the
                -- lock. Bookkeeping runs even with no stack built so the lock
                -- follows the aura, not the pooled stack. Branch only on the
                -- plain boolean m.lockHeld: m.lockedMax may hold a secret.
                if not TB.vertLockCadence then return end
                local plainZero = (not issecretvalue(maxVal))
                    and type(maxVal) == "number" and maxVal == 0
                if plainZero then
                    m.lockHeld = false
                    m.lockedMin, m.lockedMax = nil, nil
                elseif m.lockHeld then
                    return
                else
                    m.lockHeld = true
                    m.lockedMin, m.lockedMax = minVal, maxVal
                end
                if TB.tbTraceEnabled then
                    TB.tbTrace("Lock: %s max=%s id=%s",
                        plainZero and "clear" or "take",
                        issecretvalue(maxVal) and "SECRET" or tostring(maxVal),
                        tostring(child):sub(-6))
                end
                if m.vertLockBar then
                    pcall(m.vertLockBar.SetMinMaxValues, m.vertLockBar, minVal, maxVal)
                end
            end)
        end
        if barFrame.Name and barFrame.Name.SetText then
            hooksecurefunc(barFrame.Name, "SetText", function(_, text)
                local m = TB.barItemMirror[child]
                if m then m.nameText = text end
                if TB.verticalModeActive then
                    addon.UpdateVerticalBarText(child, "name")
                end
            end)
        end
        if barFrame.Duration and barFrame.Duration.SetText then
            hooksecurefunc(barFrame.Duration, "SetText", function(self, text)
                local m = TB.barItemMirror[child]
                if m then m.durationText = text end
                if TB.verticalModeActive then
                    addon.UpdateVerticalBarText(child, "duration")
                end
            end)
        end
    end

    local iconFrame = (child.GetIconFrame and child:GetIconFrame()) or child.Icon
    if iconFrame then
        if iconFrame.Icon and iconFrame.Icon.SetTexture then
            hooksecurefunc(iconFrame.Icon, "SetTexture", function(_, tex)
                local m = TB.barItemMirror[child]
                -- Texture is cooldown-derived and should stay plain; keeping the
                -- last plain value beats storing a secret that is later truthy-tested.
                if m and not issecretvalue(tex) then m.spellTexture = tex end
                if TB.verticalModeActive then
                    addon.UpdateVerticalBarText(child, "icon")
                end
            end)
        end
        if iconFrame.Applications and iconFrame.Applications.SetText then
            hooksecurefunc(iconFrame.Applications, "SetText", function(_, text)
                local m = TB.barItemMirror[child]
                if m then m.applicationsText = text end
                if TB.verticalModeActive then
                    addon.UpdateVerticalBarText(child, "applications")
                end
            end)
        end
    end

    -- Hook active state changes to trigger vertical rebuild on deactivation
    if child.SetIsActive then
        hooksecurefunc(child, "SetIsActive", function(self, active)
            local argSecret = issecretvalue(active)
            if TB.tbTraceEnabled then
                local prev = TB.prevIsActive[self]
                local shouldLog = false
                -- 12.1: shown state can itself be secret under aura restriction;
                -- branching or tostring on it would throw inside this hook body.
                local okShown, curShown = pcall(self.IsShown, self)
                local shownPlain = okShown and not issecretvalue(curShown)
                local shownStr = shownPlain and tostring(curShown) or "SECRET"
                if argSecret then
                    local dedupeKey = shownPlain and curShown or "SECRET"
                    if TB.prevShown[self] ~= dedupeKey then
                        TB.prevShown[self] = dedupeKey
                        shouldLog = true
                    end
                else
                    local changed = prev == nil
                    if not changed then
                        local okCmp, isDiff = pcall(function() return active ~= prev end)
                        changed = not okCmp or isDiff
                    end
                    shouldLog = changed
                end
                if shouldLog then
                    TB.tbTrace("SetIsActive: arg=%s(secret=%s) prev=%s shown=%s id=%s",
                        argSecret and "SECRET" or tostring(active), tostring(argSecret),
                        prev == nil and "nil" or tostring(prev),
                        shownStr,
                        tostring(self):sub(-6))
                end
            end
            if not argSecret then
                TB.prevIsActive[self] = active
            else
                TB.prevIsActive[self] = nil
            end
            if TB.verticalModeActive then
                -- Engine-side liveness: SetAlphaFromBoolean accepts a secret
                -- boolean, so the stack tracks Blizzard's active state on the
                -- engine's timing even while aura data is secret.
                local stack = TB.blizzItemToStack[self]
                if stack then
                    pcall(stack.SetAlphaFromBoolean, stack, active, 1, 0)
                end
                local comp = addon.Components and addon.Components.trackedBars
                if comp then
                    if not argSecret then
                        TB.scheduleVerticalRebuild(comp)
                    elseif not stack then
                        -- Restricted combat: the item went (secretly) active with
                        -- no stack yet -- it was inactive at the last plain-state
                        -- rebuild. Build one now; once the stack exists, secret
                        -- calls are pure alpha forwards (the viewer pump fires
                        -- every frame -- never rebuild per secret call).
                        TB.scheduleVerticalRebuild(comp)
                    end
                end
            end
        end)
    end

    -- v15: Hook RefreshData to track aura-instance transitions and enforce suppression.
    if child.RefreshData then
        hooksecurefunc(child, "RefreshData", function(self)
            local prevAuraInstance = TB.lastKnownAuraInstance[self]
            local auraInstance = self.auraInstanceID
            local hasAuraInstance = type(auraInstance) == "number" and not issecretvalue(auraInstance)
            local hasLiveInstance = false
            if hasAuraInstance then
                hasLiveInstance = TB.hasLiveAuraInstance(self)
            end
            local auraSpellID = self.auraSpellID
            local hasAuraSpellID = type(auraSpellID) == "number" and not issecretvalue(auraSpellID)

            if hasLiveInstance then
                TB.lastKnownAuraInstance[self] = auraInstance
            else
                TB.lastKnownAuraInstance[self] = nil
            end

            if TB.isItemSuppressed(self) then
                local addSeenAt = TB.pendingAuraAdd[self]
                local addRelevant = type(addSeenAt) == "table" and addSeenAt.relevant == true
                local hasPendingAdd = type(addSeenAt) == "table"
                local supAge = TB.suppressedAt[self] and (GetTime() - TB.suppressedAt[self]) or 0
                local inCombat = InCombatLockdown and InCombatLockdown()
                local bounceAge = TB.recentHide[self] and (GetTime() - TB.recentHide[self]) or math.huge

                if hasLiveInstance and addRelevant then
                    TB.restoreSuppressedItem(self, "RefreshData+AuraAddedValidated")
                elseif inCombat and hasLiveInstance and hasPendingAdd then
                    TB.restoreSuppressedItem(self, "RefreshData+CombatLiveAuraPendingAdd")
                elseif inCombat and hasLiveInstance and supAge > 1.0 and bounceAge > 0.5 then
                    TB.restoreSuppressedItem(self, "RefreshData+CombatLiveAuraFallback")
                else
                    TB.enforceSuppressedVisibility(self)
                    if TB.tbTraceEnabled and hasAuraInstance and type(addSeenAt) == "table" and addSeenAt.relevant == false then
                        TB.tbTrace("Suppression(v15f): ignore non-relevant add inCombat=%s supAge=%.3f hasAuraSpell=%s liveAura=%s id=%s",
                            tostring(inCombat), supAge, tostring(hasAuraSpellID), tostring(hasLiveInstance), tostring(self):sub(-6))
                    end
                end
                return
            end

            -- Fallback path for missed removal signals
            local inCombat = InCombatLockdown and InCombatLockdown()
            local okShown, isShown = pcall(self.IsShown, self)
            local shouldCheckShown = (not okShown) or isShown
            if (not inCombat) and shouldCheckShown and prevAuraInstance and (not hasLiveInstance) and TB.getItemCooldownID(self) then
                TB.suppressItem(self, "RefreshDataLostAuraInstance")
                if not TB.verticalModeActive then
                    TB.scheduleBackgroundVerification(self)
                end
            end
        end)
    end

    -- ClearAuraInfo was renamed ClearAuraInstanceInfo in 12.0.0, so the old hook
    -- has been silently dead since then. The renamed method fires on every
    -- aura-instance SWAP too (SetAuraInstanceInfo clears before assigning the new
    -- instance), so the removal decision must be deferred one tick and re-checked.
    local clearMethodName
    if type(child.ClearAuraInstanceInfo) == "function" then
        clearMethodName = "ClearAuraInstanceInfo"
    elseif type(child.ClearAuraInfo) == "function" then
        clearMethodName = "ClearAuraInfo"
    end
    if clearMethodName then
        hooksecurefunc(child, clearMethodName, function(self)
            -- A new aura instance (removal, or a swap with no inactive gap:
            -- target change, fresh application) starts a new cadence lock.
            -- Blizzard never fires this on a same-instance refresh
            -- (CooldownViewerItemData.lua SetAuraInstanceInfo identity guard).
            local lockMirror = TB.barItemMirror[self]
            if lockMirror then
                lockMirror.lockHeld = false
                lockMirror.lockedMin, lockMirror.lockedMax = nil, nil
            end

            local hadAuraInstance = TB.lastKnownAuraInstance[self] ~= nil
            TB.lastKnownAuraInstance[self] = nil
            if not hadAuraInstance then return end

            C_Timer.After(0, function()
                if addon.AurasSecretNow and addon.AurasSecretNow() then return end
                -- Swap-fire guard: a live instance now means this was a swap,
                -- not a removal.
                if TB.hasLiveAuraInstance(self) then return end

                if TB.isItemSuppressed(self) then
                    TB.enforceSuppressedVisibility(self)
                    return
                end

                if TB.getItemCooldownID(self) then
                    TB.suppressItem(self, "ClearAuraInstanceInfo")
                    if not TB.verticalModeActive then
                        TB.scheduleBackgroundVerification(self)
                    end
                end
            end)
        end)
    end

    if child.OnUnitAuraRemovedEvent then
        hooksecurefunc(child, "OnUnitAuraRemovedEvent", function(self)
            local ok, spellID = pcall(function() return self:GetSpellID() end)
            if ok and type(spellID) == "number" and not issecretvalue(spellID) then
                TB.auraRemovedSpellID[self] = spellID
            elseif TB.cachedSpellID[self] then
                TB.auraRemovedSpellID[self] = TB.cachedSpellID[self]
            else
                TB.auraRemovedSpellID[self] = nil
            end

            TB.pendingAuraAdd[self] = nil
            TB.suppressItem(self, "OnUnitAuraRemovedEvent")

            local spStr = TB.auraRemovedSpellID[self] and tostring(TB.auraRemovedSpellID[self]) or "?"
            if TB.tbTraceEnabled then
                TB.tbTrace("AuraRemoved(v15): spell=%s id=%s", spStr, tostring(self):sub(-6))
            end
            if not TB.verticalModeActive then TB.scheduleBackgroundVerification(self) end
        end)
    end

    if child.OnUnitAuraAddedEvent then
        hooksecurefunc(child, "OnUnitAuraAddedEvent", function(self, unitAuraUpdateInfo)
            if not TB.isItemSuppressed(self) then return end

            -- 12.1: while auras are secret the add cannot be validated (payload
            -- and instance ID are secret), so a suppressed item could never
            -- restore mid-combat. Fail open; Blizzard's own item visibility and
            -- the SetIsActive alpha mirror are the authority under restriction.
            if addon.AurasSecretNow and addon.AurasSecretNow() then
                TB.restoreSuppressedItem(self, "SecretAuraAddFailOpen")
                return
            end

            local relevantAdd, matchedSpellID = TB.getRelevantAddedAuraInfo(self, unitAuraUpdateInfo)
            TB.pendingAuraAdd[self] = {
                at = GetTime(),
                relevant = relevantAdd,
                spellID = matchedSpellID,
            }
            local auraInstance = self.auraInstanceID
            local hasAuraInstance = type(auraInstance) == "number" and not issecretvalue(auraInstance)
            local hasLiveInstance = false
            if hasAuraInstance then
                hasLiveInstance = TB.hasLiveAuraInstance(self)
            end
            local auraSpellID = self.auraSpellID
            local hasAuraSpellID = type(auraSpellID) == "number" and not issecretvalue(auraSpellID)

            if hasLiveInstance then
                TB.lastKnownAuraInstance[self] = auraInstance
            end

            if relevantAdd and hasLiveInstance then
                TB.restoreSuppressedItem(self, "OnUnitAuraAddedEventValidated")
                if not TB.verticalModeActive then TB.scheduleBackgroundVerification(self) end
            end

            if TB.tbTraceEnabled then
                local addedCount = 0
                if not issecretvalue(unitAuraUpdateInfo) and type(unitAuraUpdateInfo) == "table" then
                    local addedList = unitAuraUpdateInfo.addedAuras
                    if not issecretvalue(addedList) and type(addedList) == "table" then
                        addedCount = #addedList
                    end
                end
                TB.tbTrace("AuraAdded(v15e): pending addAuras=%d relevant=%s matchSpell=%s hasAuraInst=%s liveAura=%s hasAuraSpell=%s id=%s",
                    addedCount, tostring(relevantAdd), tostring(matchedSpellID),
                    tostring(hasAuraInstance), tostring(hasLiveInstance), tostring(hasAuraSpellID), tostring(self):sub(-6))
            end
        end)
    end
end

--------------------------------------------------------------------------------
-- Vertical Mode: Stack Frame Creation
--------------------------------------------------------------------------------

local vertStackPool = {}
local activeVertStacks = {}
local vertContainer = nil

local function createVerticalStack()
    local stack = CreateFrame("Frame", nil, UIParent)
    -- Explicit level even though the stack is reparented to vertContainer on apply
    -- (SetParent must not be able to leave a stale/floor level -- iconRegion below
    -- is mouse-live and needs to outrank the overlays it may sit under).
    addon.Strata.ApplyHUD(stack, 36)
    stack:EnableMouse(false)

    stack.iconRegion = CreateFrame("Frame", nil, stack)
    stack.iconRegion:EnableMouse(true)
    stack.iconTexture = stack.iconRegion:CreateTexture(nil, "ARTWORK")
    stack.iconTexture:SetAllPoints(stack.iconRegion)
    stack.applicationsFS = stack.iconRegion:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    stack.applicationsFS:SetPoint("BOTTOMRIGHT", stack.iconRegion, "BOTTOMRIGHT", -2, 2)
    stack.applicationsFS:SetJustifyH("RIGHT")

    stack.barRegion = CreateFrame("Frame", nil, stack)
    stack.barRegion:EnableMouse(false)

    stack.barBg = stack.barRegion:CreateTexture(nil, "BACKGROUND", nil, 0)
    stack.barBg:SetAllPoints(stack.barRegion)

    -- Lock bar "A": invisible cadence reference for the "lock drain to original
    -- duration" option. It receives every forwarded SetValue but only the first
    -- SetMinMaxValues after activation, so its fill drains at the original
    -- cadence. Alpha 0, never Hide(): a hidden StatusBar stops laying out its
    -- fill texture and the clip rect below would freeze.
    stack.barLock = CreateFrame("StatusBar", nil, stack.barRegion)
    stack.barLock:SetAllPoints(stack.barRegion)
    stack.barLock:SetOrientation("VERTICAL")
    stack.barLock:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    stack.barLock:SetMinMaxValues(0, 1)
    stack.barLock:SetValue(1)
    stack.barLock:SetAlpha(0)
    stack.barLock:EnableMouse(false)

    -- Clip frame: the visible fill is barFill's rect intersected with this
    -- rect. Anchored to A's fill texture when locking (buildOneVerticalItem),
    -- to barRegion otherwise. Visible = min(A, B) = remaining / max(orig, cur).
    stack.barClip = CreateFrame("Frame", nil, stack.barRegion)
    stack.barClip:SetClipsChildren(true)
    stack.barClip:SetAllPoints(stack.barRegion)
    stack.barClip:EnableMouse(false)

    stack.barFill = CreateFrame("StatusBar", nil, stack.barClip)
    stack.barFill:SetAllPoints(stack.barRegion)
    stack.barFill:SetOrientation("VERTICAL")
    stack.barFill:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    stack.barFill:SetMinMaxValues(0, 1)
    stack.barFill:SetValue(0)

    stack.spellNameFrame = CreateFrame("Frame", nil, stack.barRegion)
    stack.spellNameFS = stack.spellNameFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    stack.spellNameFS:SetAllPoints(stack.spellNameFrame)
    stack.spellNameFS:SetJustifyH("CENTER")
    stack.spellNameFS:SetJustifyV("MIDDLE")

    -- Explicit levels: barFill moved one level deeper (under barClip), so pin
    -- the order barBg (barRegion) < fill < spell name < border (base + 5, see
    -- styleVerticalStack). Offsets shift with the stack on SetParent.
    local base = stack.barRegion:GetFrameLevel()
    stack.barLock:SetFrameLevel(base + 1)
    stack.barClip:SetFrameLevel(base + 1)
    stack.barFill:SetFrameLevel(base + 2)
    stack.spellNameFrame:SetFrameLevel(base + 3)

    local ag = stack.spellNameFrame:CreateAnimationGroup()
    local rot = ag:CreateAnimation("Rotation")
    rot:SetDegrees(-90)
    rot:SetDuration(0)
    rot:SetEndDelay(2147483647)
    ag:Play()
    stack.spellNameAG = ag

    stack.timerFS = stack:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    stack.timerFS:SetJustifyH("CENTER")

    stack:Hide()
    return stack
end

local function acquireVertStack()
    local stack = table.remove(vertStackPool)
    if not stack then
        stack = createVerticalStack()
    end
    return stack
end

local function releaseVertStack(stack)
    if not stack then return end
    stack:Hide()
    -- A stack darkened by the SetIsActive alpha mirror must not be reused
    -- invisible after combat.
    stack:SetAlpha(1)
    stack:ClearAllPoints()
    stack:SetParent(UIParent)
    stack.iconTexture:SetTexture(nil)
    stack.applicationsFS:SetText("")
    stack.spellNameFS:SetText("")
    stack.timerFS:SetText("")
    stack.barFill:SetMinMaxValues(0, 1)
    stack.barFill:SetValue(0)
    stack.barLock:SetMinMaxValues(0, 1)
    stack.barLock:SetValue(1)
    table.insert(vertStackPool, stack)
end

local function releaseAllVertStacks()
    for i = #activeVertStacks, 1, -1 do
        local entry = activeVertStacks[i]
        local m = TB.barItemMirror[entry.blizzItem]
        -- The cadence lock fields (lockHeld/lockedMin/lockedMax) stay: the
        -- lock follows the aura across rebuilds; only the widget links drop.
        if m then
            m.vertStatusBar = nil
            m.vertLockBar = nil
        end
        TB.blizzItemToStack[entry.blizzItem] = nil
        releaseVertStack(entry.frame)
        activeVertStacks[i] = nil
    end
end

local function clearAllVertLocks()
    for _, m in pairs(TB.barItemMirror) do
        m.lockHeld = false
        m.lockedMin, m.lockedMax = nil, nil
    end
end

--------------------------------------------------------------------------------
-- Vertical Mode: Layout and Sizing
--------------------------------------------------------------------------------

local function layoutVerticalStack(stack, displayMode)
    if not stack then return end
    local iconSize = tonumber(TB.getTrackedBarSetting("iconSize")) or 100
    local scale = iconSize / 100
    local barWidth = tonumber(TB.getTrackedBarSetting("barWidth")) or 100
    local barHeight = barWidth * scale
    local iconBarPad = tonumber(TB.getTrackedBarSetting("iconBarPadding")) or 0
    local stackWidth = 30 * scale
    local iconDim = stackWidth

    local iconRatio = tonumber(TB.getTrackedBarSetting("iconTallWideRatio")) or 0
    local iconW, iconH = iconDim, iconDim
    if addon.IconRatio then
        iconW, iconH = addon.IconRatio.GetDimensionsForComponent("trackedBars", iconRatio)
        iconW = (iconW or 30) * scale
        iconH = (iconH or 30) * scale
    else
        iconW = iconDim
        iconH = iconDim
    end
    iconW = math.max(8, iconW)
    iconH = math.max(8, iconH)
    stackWidth = iconW

    displayMode = displayMode or "both"
    local showIcon = (displayMode ~= "name")
    local showName = (displayMode ~= "icon")

    stack.iconRegion:SetShown(showIcon)
    stack.spellNameFS:SetShown(showName)

    local yOff = 0

    if showIcon then
        stack.iconRegion:SetSize(iconW, iconH)
        stack.iconRegion:ClearAllPoints()
        stack.iconRegion:SetPoint("BOTTOM", stack, "BOTTOM", 0, 0)
        yOff = iconH + iconBarPad

        -- Icon zoom texcoord
        local iconZoomVal = tonumber(TB.getTrackedBarSetting("iconZoom")) or 0
        if stack.iconTexture then
            local l, r, t, b = addon.CalculateIconTexCoords(iconW / iconH, iconZoomVal, 0)
            pcall(stack.iconTexture.SetTexCoord, stack.iconTexture, l, r, t, b)
        end

        -- Hide decorative ring on vertical icon
        local iconHideRing = TB.getTrackedBarSetting("iconHideDecorativeRing")
        if iconHideRing and stack.iconRegion then
            pcall(function()
                for _, region in ipairs({ stack.iconRegion:GetRegions() }) do
                    if region:IsObjectType("Texture") and region ~= stack.iconTexture then
                        local atlas = region:GetAtlas()
                        if atlas == "UI-HUD-CoolDownManager-IconOverlay" then
                            region:SetAlpha(0)
                        end
                    end
                end
            end)
        end
    end

    stack.barRegion:ClearAllPoints()
    stack.barRegion:SetSize(stackWidth, barHeight)
    stack.barRegion:SetPoint("BOTTOM", stack, "BOTTOM", 0, yOff)

    stack.spellNameFrame:ClearAllPoints()
    stack.spellNameFrame:SetSize(barHeight, stackWidth)
    stack.spellNameFrame:SetPoint("CENTER", stack.barRegion, "CENTER")

    stack.timerFS:ClearAllPoints()
    stack.timerFS:SetPoint("BOTTOM", stack.barRegion, "TOP", 0, 2)

    local timerHeight = 16 * scale
    local totalHeight = (showIcon and (iconH + iconBarPad) or 0) + barHeight + timerHeight + 2
    stack:SetSize(stackWidth, totalHeight)
end

local function layoutVerticalStacks()
    if not vertContainer then return end
    local padding = tonumber(TB.getTrackedBarSetting("iconPadding")) or 3
    local xOffset = 0
    for _, entry in ipairs(activeVertStacks) do
        entry.frame:ClearAllPoints()
        entry.frame:SetPoint("BOTTOMLEFT", vertContainer, "BOTTOMLEFT", xOffset, 0)
        xOffset = xOffset + entry.frame:GetWidth() + padding
    end
    vertContainer:SetSize(math.max(1, xOffset), 1)
end

--------------------------------------------------------------------------------
-- Vertical Mode: Fill + Text Updates
--------------------------------------------------------------------------------

-- Forwarding a secret string to SetText is legal (AllowedWhenTainted); what
-- throws is any Lua-side branch on it -- including the bare `value or ""`.
local function setTextSecretSafe(fs, value)
    if issecretvalue(value) then
        fs:SetText(value)
    else
        fs:SetText(value or "")
    end
end

local function setApplicationsText(fs, value)
    if issecretvalue(value) then
        -- Blizzard's GetApplicationsText returns a plain "" for counts <= 1 and
        -- a secret number only for counts > 1, so "value is secret" literally
        -- means "there is a stack count worth showing".
        fs:SetText(value)
        fs:SetShown(true)
    else
        local txt = value or ""
        fs:SetText(txt)
        fs:SetShown(txt ~= "" and txt ~= "0" and txt ~= "1")
    end
end

function addon.UpdateVerticalBarText(child, which)
    local mirror = TB.barItemMirror[child]
    if not mirror then return end
    local stack = TB.blizzItemToStack[child]
    if not stack then return end

    if which == "name" then
        setTextSecretSafe(stack.spellNameFS, mirror.nameText)
    elseif which == "duration" then
        setTextSecretSafe(stack.timerFS, mirror.durationText)
    elseif which == "icon" then
        stack.iconTexture:SetTexture(mirror.spellTexture)
    elseif which == "applications" then
        setApplicationsText(stack.applicationsFS, mirror.applicationsText)
    end
end

--------------------------------------------------------------------------------
-- Vertical Mode: Style Application (uses shared helpers from init.lua)
--------------------------------------------------------------------------------

local function styleVerticalStack(stack, component)
    if not stack or not component or not component.db then return end
    local db = component.db
    local defaultFace = select(1, GameFontNormal:GetFont())

    -- Bar textures
    local useCustom = db.styleEnableCustom ~= false
    if useCustom then
        local fgKey = db.styleForegroundTexture or "bevelled"
        local bgKey = db.styleBackgroundTexture or "bevelled"
        local fgPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(fgKey)
        local bgPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(bgKey)

        if fgPath then
            stack.barFill:SetStatusBarTexture(fgPath)
        else
            stack.barFill:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        end

        if bgPath then
            stack.barBg:SetTexture(bgPath)
        else
            stack.barBg:SetColorTexture(0, 0, 0, 1)
        end

        -- Foreground color
        local fgColorMode = rawget(db, "styleForegroundColorMode") or "default"
        local fgTint = rawget(db, "styleForegroundTint") or {1,1,1,1}
        local fgR, fgG, fgB, fgA = TB.resolveBarColor(fgColorMode, fgTint, 1.0, 0.5, 0.25, 1.0)
        stack.barFill:GetStatusBarTexture():SetVertexColor(fgR, fgG, fgB, fgA)

        -- Background color + opacity
        local bgColorMode = rawget(db, "styleBackgroundColorMode") or "default"
        local bgTint = rawget(db, "styleBackgroundTint") or {0,0,0,1}
        local bgOpacity = tonumber(db.styleBackgroundOpacity) or 50
        bgOpacity = math.max(0, math.min(100, bgOpacity)) / 100
        local bgR, bgG, bgB, bgA = TB.resolveBarColor(bgColorMode, bgTint, 0, 0, 0, 1)
        stack.barBg:SetVertexColor(bgR, bgG, bgB, bgA)
        stack.barBg:SetAlpha(bgOpacity)

        stack.barFill:Show()
        stack.barBg:Show()
    else
        stack.barFill:SetStatusBarTexture("UI-HUD-CoolDownManager-Bar")
        stack.barFill:GetStatusBarTexture():SetVertexColor(1.0, 0.5, 0.25, 1.0)
        stack.barBg:SetAtlas("UI-HUD-CoolDownManager-Bar-BG")
        stack.barBg:SetVertexColor(1, 1, 1, 1)
        stack.barBg:SetAlpha(1)
        stack.barFill:Show()
        stack.barBg:Show()
    end

    -- Border on bar
    local borderStyle = db.borderStyle or "blizzardDefault"
    -- Backward compat: honor legacy borderEnable for users who had it on
    -- before UI restructure but never set a borderStyle explicitly
    if rawget(db, "borderEnable") == true and not rawget(db, "borderStyle") then
        borderStyle = "square"
    end
    local wantBorder = borderStyle ~= "blizzardDefault"
    if wantBorder then
        local thickness = tonumber(db.borderThickness) or 1
        if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
        local tintEnabled = db.borderTintEnable and type(rawget(db, "borderTintColor")) == "table"
        local color
        if tintEnabled then
            local c = rawget(db, "borderTintColor")
            color = { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
        else
            color = {0, 0, 0, 1}
        end
        local insetH = tonumber(db.borderInsetH) or tonumber(db.borderInset) or 0
        local insetV = tonumber(db.borderInsetV) or tonumber(db.borderInset) or 0
        local handled = false
        if addon.BarBorders and addon.BarBorders.ApplyToBarFrame then
            handled = addon.BarBorders.ApplyToBarFrame(stack.barRegion, borderStyle, {
                color = color,
                thickness = thickness,
                insetH = insetH,
                insetV = insetV,
                hiddenEdges = db.borderHiddenEdges,
            })
        end
        if not handled then
            if addon.Borders and addon.Borders.ApplySquare then
                addon.Borders.ApplySquare(stack.barRegion, {
                    size = thickness,
                    color = color,
                    layer = "OVERLAY",
                    layerSublevel = 7,
                    levelOffset = 5,
                    containerParent = stack.barRegion,
                    expandX = 1,
                    expandY = 2,
                    skipDimensionCheck = true,
                    hiddenEdges = db.borderHiddenEdges,
                })
            end
        end
    else
        if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(stack.barRegion) end
        if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(stack.barRegion) end
    end

    -- Icon border
    local iconBorderEnabled = not not db.iconBorderEnable
    local iconStyle = tostring(db.iconBorderStyle or "none")
    local iconThickness = tonumber(db.iconBorderThickness) or 1
    iconThickness = math.max(1, math.min(16, iconThickness))
    local iconBorderInsetH = tonumber(db.iconBorderInsetH) or tonumber(db.iconBorderInset) or 0
    local iconBorderInsetV = tonumber(db.iconBorderInsetV) or tonumber(db.iconBorderInset) or 0
    local iconTintEnabled = not not db.iconBorderTintEnable
    local tintRaw = rawget(db, "iconBorderTintColor")
    if iconBorderEnabled and stack.iconRegion:IsShown() then
        local iconState = getState(stack.iconRegion)
        local lb = iconState and iconState.lastIconBorder
        local tintColor
        if not lb
            or lb.style ~= iconStyle
            or lb.thickness ~= iconThickness
            or lb.tintEnabled ~= iconTintEnabled
            or lb.insetH ~= iconBorderInsetH
            or lb.insetV ~= iconBorderInsetV
            or (iconTintEnabled and (
                not lb.tintR or lb.tintR ~= (type(tintRaw) == "table" and tintRaw[1] or 1)
                or lb.tintG ~= (type(tintRaw) == "table" and tintRaw[2] or 1)
                or lb.tintB ~= (type(tintRaw) == "table" and tintRaw[3] or 1)
                or lb.tintA ~= (type(tintRaw) == "table" and tintRaw[4] or 1)
            ))
        then
            tintColor = {1, 1, 1, 1}
            if type(tintRaw) == "table" then
                tintColor = { tintRaw[1] or 1, tintRaw[2] or 1, tintRaw[3] or 1, tintRaw[4] or 1 }
            end
            addon.ApplyIconBorderStyle(stack.iconRegion, iconStyle, {
                thickness = iconThickness,
                insetH = iconBorderInsetH,
                insetV = iconBorderInsetV,
                color = iconTintEnabled and tintColor or nil,
                tintEnabled = iconTintEnabled,
                db = db,
                thicknessKey = "iconBorderThickness",
                tintColorKey = "iconBorderTintColor",
                defaultThickness = 1,
            })
            if iconState then
                iconState.lastIconBorder = {
                    style = iconStyle,
                    thickness = iconThickness,
                    tintEnabled = iconTintEnabled,
                    insetH = iconBorderInsetH,
                    insetV = iconBorderInsetV,
                    tintR = type(tintRaw) == "table" and tintRaw[1] or 1,
                    tintG = type(tintRaw) == "table" and tintRaw[2] or 1,
                    tintB = type(tintRaw) == "table" and tintRaw[3] or 1,
                    tintA = type(tintRaw) == "table" and tintRaw[4] or 1,
                }
            end
        end
    else
        if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(stack.iconRegion) end
        local iconState = getState(stack.iconRegion)
        if iconState then iconState.lastIconBorder = nil end
    end

    -- Text styling — only when user has explicitly configured text settings
    if rawget(db, "textName") then
        TB.applyTextStyling(stack.spellNameFS, db.textName, defaultFace)
    end
    if rawget(db, "textDuration") then
        TB.applyTextStyling(stack.timerFS, db.textDuration, defaultFace)
    end
    if rawget(db, "textStacks") then
        TB.applyTextStyling(stack.applicationsFS, db.textStacks, defaultFace)
    end
end

--------------------------------------------------------------------------------
-- Vertical Mode: Tooltip Forwarding
--------------------------------------------------------------------------------

local function setupVertStackTooltip(stack, blizzBarItem)
    stack.iconRegion:SetScript("OnEnter", function()
        pcall(function()
            if blizzBarItem and blizzBarItem.OnEnter then
                blizzBarItem:OnEnter()
            end
        end)
    end)
    stack.iconRegion:SetScript("OnLeave", function()
        pcall(function()
            if blizzBarItem and blizzBarItem.OnLeave then
                blizzBarItem:OnLeave()
            end
        end)
    end)
end

--------------------------------------------------------------------------------
-- Vertical Mode: Blizzard Item Alpha Enforcement
--------------------------------------------------------------------------------

local function enforceBlizzItemAlpha(child)
    pcall(child.SetAlpha, child, 0)
    if TB.alphaEnforcedItems[child] then return end
    TB.alphaEnforcedItems[child] = true
    if child.SetAlpha then
        hooksecurefunc(child, "SetAlpha", function(self, alpha)
            -- issecretvalue: comparing a secret alpha throws. Skipping the
            -- re-assert on a secret is safe: Scoot's own writes are always plain 0.
            -- The reentrancy flag stands in for the "0 stops recursion" property,
            -- which is unreadable when the incoming alpha is secret.
            if TB._alphaReasserting then return end
            if TB.verticalModeActive and not issecretvalue(alpha) and alpha > 0 then
                TB._alphaReasserting = true
                pcall(self.SetAlpha, self, 0)
                TB._alphaReasserting = false
            end
        end)
    end
end

local function restoreBlizzItemAlpha(child)
    pcall(child.SetAlpha, child, 1)
end

--------------------------------------------------------------------------------
-- Vertical Mode: Apply/Remove
--------------------------------------------------------------------------------

local function ensureVertContainer()
    if vertContainer then return vertContainer end
    vertContainer = CreateFrame("Frame", nil, UIParent)
    addon.Strata.ApplyHUD(vertContainer, 35)
    vertContainer:SetPoint("BOTTOMLEFT", _G["BuffBarCooldownViewer"] or UIParent, "BOTTOMLEFT", 0, 0)
    vertContainer:EnableMouse(false)
    vertContainer:SetSize(1, 1)
    vertContainer:Show()
    addon.RegisterPetBattleFrame(vertContainer)
    return vertContainer
end

local function buildOneVerticalItem(child, component, displayMode)
    TB.installDataMirrorHooks(child)

    if not TB.visHookedItems[child] then
        hooksecurefunc(child, "Hide", function(self) TB.onItemFrameHide(self, component) end)
        hooksecurefunc(child, "Show", function(self) TB.onItemFrameShow(self, component) end)
        TB.visHookedItems[child] = true
    end

    enforceBlizzItemAlpha(child)

    -- 12.1: shown state can be secret under aura restriction. Fail OPEN (build
    -- the stack) and let the SetIsActive alpha mirror drive its visibility;
    -- only a plain-false shown state skips.
    local okShown, shownVal = pcall(child.IsShown, child)
    local shownIsSecret = okShown and issecretvalue(shownVal)
    local skipItem = false
    if okShown and not shownIsSecret then
        skipItem = not shownVal
    end
    if not skipItem then
        local ok, isInactive = pcall(function() return child.isActive == false end)
        if ok and not issecretvalue(isInactive) and isInactive then
            skipItem = true
        end
    end
    if not skipItem and TB.isItemSuppressed(child) then
        skipItem = true
    end
    if skipItem then
        -- Don't create a vertical stack for hidden or inactive items
        return
    end

    local stack = acquireVertStack()
    stack:SetParent(vertContainer)

    local mirror = TB.barItemMirror[child] or {}
    TB.barItemMirror[child] = mirror

    -- Register bookkeeping before the fallible build steps so a mid-build
    -- failure leaves the stack reclaimable by the next releaseAllVertStacks
    -- instead of orphaned (a pooled stack starts hidden, so nothing shows).
    table.insert(activeVertStacks, { blizzItem = child, frame = stack })
    TB.blizzItemToStack[child] = stack

    local iconFrame = (child.GetIconFrame and child:GetIconFrame()) or child.Icon

    if iconFrame and iconFrame.Icon then
        local ok, tex = pcall(iconFrame.Icon.GetTexture, iconFrame.Icon)
        if ok and not issecretvalue(tex) and tex then mirror.spellTexture = tex end
    end

    stack.iconTexture:SetTexture(mirror.spellTexture)
    setTextSecretSafe(stack.spellNameFS, mirror.nameText)
    setTextSecretSafe(stack.timerFS, mirror.durationText)
    setApplicationsText(stack.applicationsFS, mirror.applicationsText)

    layoutVerticalStack(stack, displayMode)
    styleVerticalStack(stack, component)

    mirror.vertStatusBar = stack.barFill
    local lockOn = TB.vertLockCadence
    mirror.vertLockBar = lockOn and stack.barLock or nil

    -- Clip B to A's fill when locking; otherwise the clip is the whole bar.
    stack.barClip:ClearAllPoints()
    if lockOn then
        stack.barClip:SetAllPoints(stack.barLock:GetStatusBarTexture())
    else
        stack.barClip:SetAllPoints(stack.barRegion)
    end

    local initBar = (child.GetBarFrame and child:GetBarFrame()) or child.Bar
    if initBar then
        -- Separate pcalls: an A failure must never block B (today's behavior).
        local okRange, min, max = pcall(initBar.GetMinMaxValues, initBar)
        if okRange then
            pcall(stack.barFill.SetMinMaxValues, stack.barFill, min, max)
            if lockOn then
                if mirror.lockHeld then
                    pcall(stack.barLock.SetMinMaxValues, stack.barLock, mirror.lockedMin, mirror.lockedMax)
                else
                    pcall(stack.barLock.SetMinMaxValues, stack.barLock, min, max)
                    -- Plain (0, 0) = inactive; any other number (secret
                    -- included; type() is plain on secrets) is the cadence
                    -- for this activation.
                    local hasRange = type(max) == "number"
                    local plainZero = hasRange and (not issecretvalue(max)) and max == 0
                    if hasRange and not plainZero then
                        mirror.lockHeld = true
                        mirror.lockedMin, mirror.lockedMax = min, max
                    end
                end
            end
        end
        local okVal, val = pcall(initBar.GetValue, initBar)
        if okVal then
            pcall(stack.barFill.SetValue, stack.barFill, val)
            if lockOn then
                pcall(stack.barLock.SetValue, stack.barLock, val)
            end
        end
    end

    setupVertStackTooltip(stack, child)

    stack:Show()

    -- Seed the liveness channel when the plain reads were unavailable: the
    -- engine resolves the secret boolean C-side; subsequent SetIsActive
    -- forwards keep it current.
    if shownIsSecret then
        pcall(stack.SetAlphaFromBoolean, stack, shownVal, 1, 0)
    elseif not okShown then
        local rawActive = child.isActive
        if issecretvalue(rawActive) then
            pcall(stack.SetAlphaFromBoolean, stack, rawActive, 1, 0)
        end
    end
end

function TB.applyVerticalMode(component)
    TB.verticalModeActive = true
    -- Cached for the per-tick hooks; refreshed before every build so a
    -- settings change reaches the hooks through this rebuild.
    TB.vertLockCadence = TB.getTrackedBarSetting("verticalLockCadence") == true
    if not TB.vertLockCadence then clearAllVertLocks() end
    ensureVertContainer()
    local frame = _G[component.frameName]
    if not frame then return end

    local displayMode = TB.getTrackedBarSetting("displayMode") or "both"

    releaseAllVertStacks()

    local children = { frame:GetChildren() }
    for _, child in ipairs(children) do
        if child.GetBarFrame or child.Bar then
            -- Per-child containment: release-first ordering means an uncaught
            -- throw here would leave the whole viewer rendered as nothing.
            local ok, err = pcall(buildOneVerticalItem, child, component, displayMode)
            if not ok and TB.tbTraceEnabled then
                TB.tbTrace("applyVerticalMode: item build failed err=%s id=%s",
                    tostring(err), tostring(child):sub(-6))
            end
        end
    end

    layoutVerticalStacks()
    vertContainer:Show()
end

function TB.removeVerticalMode()
    TB.verticalModeActive = false
    releaseAllVertStacks()
    clearAllVertLocks()
    if vertContainer then
        vertContainer:Hide()
    end

    local comp = addon.Components and addon.Components.trackedBars
    if comp then
        local frame = _G[comp.frameName]
        if frame then
            for _, child in ipairs({ frame:GetChildren() }) do
                if TB.isItemSuppressed(child) then
                    TB.enforceSuppressedVisibility(child)
                else
                    restoreBlizzItemAlpha(child)
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Vertical Mode: Edit Mode Integration
--------------------------------------------------------------------------------

local vertEditModeHooked = false

function TB.hookVertEditMode()
    if vertEditModeHooked then return end
    local viewer = _G["BuffBarCooldownViewer"]
    if not viewer then return end
    if viewer.SetIsEditing then
        hooksecurefunc(viewer, "SetIsEditing", function(self, isEditing)
            if isEditing then
                if TB.verticalModeActive then
                    if vertContainer then vertContainer:Hide() end
                    for _, child in ipairs({ self:GetChildren() }) do
                        pcall(child.SetAlpha, child, 1)
                    end
                end
            else
                if TB.getTrackedBarMode() == "vertical" then
                    C_Timer.After(0, function()
                        -- Edit Mode sample data writes a plain max through the
                        -- same hooks; drop any lock it took before rebuilding.
                        clearAllVertLocks()
                        local comp = addon.Components and addon.Components.trackedBars
                        if comp then TB.applyVerticalMode(comp) end
                    end)
                end
            end
        end)
    end
    vertEditModeHooked = true
end
