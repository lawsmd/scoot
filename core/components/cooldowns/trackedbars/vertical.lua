local addonName, addon = ...

local TB = addon.TB

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
                if TB.verticalModeActive and m.vertStatusBar then
                    pcall(m.vertStatusBar.SetValue, m.vertStatusBar, val)
                end
            end)
        end
        if barFrame.SetMinMaxValues then
            hooksecurefunc(barFrame, "SetMinMaxValues", function(_, minVal, maxVal)
                local m = TB.barItemMirror[child]
                if not m then return end
                if not issecretvalue(minVal) then m.barMin = minVal end
                if not issecretvalue(maxVal) then m.barMax = maxVal end
                if TB.verticalModeActive and m.vertStatusBar then
                    pcall(m.vertStatusBar.SetMinMaxValues, m.vertStatusBar, minVal, maxVal)
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
            hooksecurefunc(barFrame.Duration, "SetText", function(_, text)
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
                if m then m.spellTexture = tex end
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
                if argSecret then
                    local currentShown = self:IsShown()
                    if TB.prevShown[self] ~= currentShown then
                        TB.prevShown[self] = currentShown
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
                        tostring(self:IsShown()),
                        tostring(self):sub(-6))
                end
            end
            if not argSecret then
                TB.prevIsActive[self] = active
            else
                TB.prevIsActive[self] = nil
            end
            if TB.verticalModeActive then
                local comp = addon.Components and addon.Components.trackedBars
                if comp then
                    TB.scheduleVerticalRebuild(comp)
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

    if child.ClearAuraInfo then
        hooksecurefunc(child, "ClearAuraInfo", function(self)
            local hadAuraInstance = TB.lastKnownAuraInstance[self] ~= nil
            TB.lastKnownAuraInstance[self] = nil

            if TB.isItemSuppressed(self) then
                TB.enforceSuppressedVisibility(self)
                return
            end

            if hadAuraInstance and TB.getItemCooldownID(self) then
                TB.suppressItem(self, "ClearAuraInfo")
                if not TB.verticalModeActive then
                    TB.scheduleBackgroundVerification(self)
                end
            end
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
                if unitAuraUpdateInfo and type(unitAuraUpdateInfo) == "table" and type(unitAuraUpdateInfo.addedAuras) == "table" then
                    addedCount = #unitAuraUpdateInfo.addedAuras
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

    stack.barFill = CreateFrame("StatusBar", nil, stack.barRegion)
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
    stack:ClearAllPoints()
    stack:SetParent(UIParent)
    stack.iconTexture:SetTexture(nil)
    stack.applicationsFS:SetText("")
    stack.spellNameFS:SetText("")
    stack.timerFS:SetText("")
    stack.barFill:SetMinMaxValues(0, 1)
    stack.barFill:SetValue(0)
    table.insert(vertStackPool, stack)
end

local function releaseAllVertStacks()
    for i = #activeVertStacks, 1, -1 do
        local entry = activeVertStacks[i]
        local m = TB.barItemMirror[entry.blizzItem]
        if m then m.vertStatusBar = nil end
        TB.blizzItemToStack[entry.blizzItem] = nil
        releaseVertStack(entry.frame)
        activeVertStacks[i] = nil
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

function addon.UpdateVerticalBarText(child, which)
    local mirror = TB.barItemMirror[child]
    if not mirror then return end
    local stack = TB.blizzItemToStack[child]
    if not stack then return end

    if which == "name" then
        stack.spellNameFS:SetText(mirror.nameText or "")
    elseif which == "duration" then
        stack.timerFS:SetText(mirror.durationText or "")
    elseif which == "icon" then
        stack.iconTexture:SetTexture(mirror.spellTexture)
    elseif which == "applications" then
        local txt = mirror.applicationsText or ""
        stack.applicationsFS:SetText(txt)
        stack.applicationsFS:SetShown(txt ~= "" and txt ~= "0" and txt ~= "1")
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
        local fgColorMode = db.styleForegroundColorMode or "default"
        local fgTint = db.styleForegroundTint or {1,1,1,1}
        local fgR, fgG, fgB, fgA = TB.resolveBarColor(fgColorMode, fgTint, 1.0, 0.5, 0.25, 1.0)
        stack.barFill:GetStatusBarTexture():SetVertexColor(fgR, fgG, fgB, fgA)

        -- Background color + opacity
        local bgColorMode = db.styleBackgroundColorMode or "default"
        local bgTint = db.styleBackgroundTint or {0,0,0,1}
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
    local wantBorder = db.borderEnable
    if wantBorder then
        local styleKey = db.borderStyle or "square"
        local thickness = tonumber(db.borderThickness) or 1
        if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
        local tintEnabled = db.borderTintEnable and type(db.borderTintColor) == "table"
        local color
        if tintEnabled then
            local c = db.borderTintColor
            color = { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
        else
            color = {0, 0, 0, 1}
        end
        local insetH = tonumber(db.borderInsetH) or tonumber(db.borderInset) or 0
        local insetV = tonumber(db.borderInsetV) or tonumber(db.borderInset) or 0
        local handled = false
        if addon.BarBorders and addon.BarBorders.ApplyToBarFrame then
            handled = addon.BarBorders.ApplyToBarFrame(stack.barRegion, styleKey, {
                color = color,
                thickness = thickness,
                insetH = insetH,
                insetV = insetV,
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
    local tintRaw = db.iconBorderTintColor
    local tintColor = {1, 1, 1, 1}
    if type(tintRaw) == "table" then
        tintColor = { tintRaw[1] or 1, tintRaw[2] or 1, tintRaw[3] or 1, tintRaw[4] or 1 }
    end
    if iconBorderEnabled and stack.iconRegion:IsShown() then
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
    else
        if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(stack.iconRegion) end
    end

    -- Text styling (using shared helper)
    TB.applyTextStyling(stack.spellNameFS, db.textName, defaultFace)
    TB.applyTextStyling(stack.timerFS, db.textDuration, defaultFace)
    TB.applyTextStyling(stack.applicationsFS, db.textStacks, defaultFace)
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
            if TB.verticalModeActive and alpha > 0 then
                pcall(self.SetAlpha, self, 0)
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
    vertContainer:SetPoint("BOTTOMLEFT", _G["BuffBarCooldownViewer"] or UIParent, "BOTTOMLEFT", 0, 0)
    vertContainer:EnableMouse(false)
    vertContainer:SetSize(1, 1)
    vertContainer:Show()
    return vertContainer
end

function TB.applyVerticalMode(component)
    TB.verticalModeActive = true
    ensureVertContainer()
    local frame = _G[component.frameName]
    if not frame then return end

    local displayMode = TB.getTrackedBarSetting("displayMode") or "both"

    releaseAllVertStacks()

    local children = { frame:GetChildren() }
    for _, child in ipairs(children) do
        if child.GetBarFrame or child.Bar then
            TB.installDataMirrorHooks(child)

            if not TB.visHookedItems[child] then
                hooksecurefunc(child, "Hide", function(self) TB.onItemFrameHide(self, component) end)
                hooksecurefunc(child, "Show", function(self) TB.onItemFrameShow(self, component) end)
                TB.visHookedItems[child] = true
            end

            enforceBlizzItemAlpha(child)

            local skipItem = not child:IsShown()
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
            else

            local stack = acquireVertStack()
            stack:SetParent(vertContainer)

            local mirror = TB.barItemMirror[child] or {}

            local barFrame2 = (child.GetBarFrame and child:GetBarFrame()) or child.Bar
            local iconFrame = (child.GetIconFrame and child:GetIconFrame()) or child.Icon

            if iconFrame and iconFrame.Icon then
                local ok, tex = pcall(iconFrame.Icon.GetTexture, iconFrame.Icon)
                if ok and tex then mirror.spellTexture = tex end
            end

            stack.iconTexture:SetTexture(mirror.spellTexture)
            stack.spellNameFS:SetText(mirror.nameText or "")
            stack.timerFS:SetText(mirror.durationText or "")
            local appText = mirror.applicationsText or ""
            stack.applicationsFS:SetText(appText)
            stack.applicationsFS:SetShown(appText ~= "" and appText ~= "0" and appText ~= "1")

            layoutVerticalStack(stack, displayMode)
            styleVerticalStack(stack, component)

            TB.barItemMirror[child] = mirror
            mirror.vertStatusBar = stack.barFill
            table.insert(activeVertStacks, { blizzItem = child, frame = stack })
            TB.blizzItemToStack[child] = stack

            local initBar = (child.GetBarFrame and child:GetBarFrame()) or child.Bar
            if initBar then
                pcall(function()
                    local min, max = initBar:GetMinMaxValues()
                    stack.barFill:SetMinMaxValues(min, max)
                end)
                pcall(function()
                    local val = initBar:GetValue()
                    stack.barFill:SetValue(val)
                end)
            end

            setupVertStackTooltip(stack, child)

            stack:Show()
            end -- else (skipItem)
        end
    end

    layoutVerticalStacks()
    vertContainer:Show()
end

function TB.removeVerticalMode()
    TB.verticalModeActive = false
    releaseAllVertStacks()
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
                        local comp = addon.Components and addon.Components.trackedBars
                        if comp then TB.applyVerticalMode(comp) end
                    end)
                end
            end
        end)
    end
    vertEditModeHooked = true
end
