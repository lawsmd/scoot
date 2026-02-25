local addonName, addon = ...

local Component = addon.ComponentPrototype
local Util = addon.ComponentsUtil

--------------------------------------------------------------------------------
-- Shared State Namespace (addon.TB)
-- All trackedbars sub-files communicate through this table.
--------------------------------------------------------------------------------

local TB = {}
addon.TB = TB

-- Default mode overlay tracking (weak keys for GC)
TB.trackedBarOverlays = setmetatable({}, { __mode = "k" })

-- Data mirroring for vertical mode (weak keys for GC)
TB.barItemMirror = setmetatable({}, { __mode = "k" })
TB.hookedBarItems = setmetatable({}, { __mode = "k" })
TB.visHookedItems = setmetatable({}, { __mode = "k" })

-- Vertical stack lookup
TB.blizzItemToStack = setmetatable({}, { __mode = "k" })

-- Mode flag (written by vertical.lua, read by all)
TB.verticalModeActive = false

-- Alpha enforcement hooks tracking (weak keys)
TB.alphaEnforcedItems = setmetatable({}, { __mode = "k" })
TB.prevIsActive = setmetatable({}, { __mode = "k" })
TB.prevShown = setmetatable({}, { __mode = "k" })

-- Suppression + aura state tables (weak keys)
TB.recentHide = setmetatable({}, { __mode = "k" })
TB.auraRecentlyCleared = setmetatable({}, { __mode = "k" })
TB.auraRemovedSpellID = setmetatable({}, { __mode = "k" })
TB.barItemFirstSpellID = setmetatable({}, { __mode = "k" })
TB.cachedSpellID = setmetatable({}, { __mode = "k" })
TB.suppressedByRemoval = setmetatable({}, { __mode = "k" })
TB.suppressedCooldownID = setmetatable({}, { __mode = "k" })
TB.pendingAuraAdd = setmetatable({}, { __mode = "k" })
TB.lastKnownAuraInstance = setmetatable({}, { __mode = "k" })
TB.suppressedAt = setmetatable({}, { __mode = "k" })
TB.cascadeTimers = setmetatable({}, { __mode = "k" })

--------------------------------------------------------------------------------
-- Trace System
--------------------------------------------------------------------------------

TB.tbTraceEnabled = false
local tbTraceBuffer = {}
local TB_TRACE_MAX_LINES = 500

function TB.tbTrace(message, ...)
    if not TB.tbTraceEnabled then return end
    local ok, formatted = pcall(string.format, message, ...)
    if not ok then formatted = message end
    if issecretvalue(formatted) then formatted = message .. " [SECRET]" end
    local timestamp = GetTime and GetTime() or 0
    local ok2, line = pcall(string.format, "[%.3f] %s", timestamp, formatted)
    if not ok2 or issecretvalue(line) then return end
    tbTraceBuffer[#tbTraceBuffer + 1] = line
    if #tbTraceBuffer > TB_TRACE_MAX_LINES then
        table.remove(tbTraceBuffer, 1)
    end
end

function addon.SetTBTrace(enabled)
    TB.tbTraceEnabled = enabled
    if enabled then
        addon:Print("Tracked Bars trace: ON")
    else
        addon:Print("Tracked Bars trace: OFF")
    end
end

function addon.ShowTBTraceLog()
    if #tbTraceBuffer == 0 then
        addon:Print("Tracked Bars trace buffer is empty.")
        return
    end
    local safeLines = {}
    for i = 1, #tbTraceBuffer do
        local entry = tbTraceBuffer[i]
        if not issecretvalue(entry) then
            safeLines[#safeLines + 1] = entry
        else
            safeLines[#safeLines + 1] = "[SECRET LINE SKIPPED]"
        end
    end
    local text = table.concat(safeLines, "\n")
    if addon.DebugShowWindow then
        addon.DebugShowWindow("Tracked Bars Trace", text)
    else
        addon:Print("DebugShowWindow not available. Buffer has " .. #tbTraceBuffer .. " lines.")
    end
end

function addon.ClearTBTrace()
    wipe(tbTraceBuffer)
    addon:Print("Tracked Bars trace buffer cleared.")
end

--------------------------------------------------------------------------------
-- Settings Helpers
--------------------------------------------------------------------------------

function TB.getItemCooldownID(item)
    if not item then return nil end
    if item.GetCooldownID then
        local ok, id = pcall(item.GetCooldownID, item)
        if ok and type(id) == "number" and not issecretvalue(id) then
            return id
        end
    end
    local raw = item.cooldownID
    if type(raw) == "number" and not issecretvalue(raw) then
        return raw
    end
    return nil
end

function TB.getTrackedBarMode()
    local comp = addon.Components and addon.Components.trackedBars
    if not comp or not comp.db then return "default" end
    return comp.db.barMode or "default"
end

function TB.getTrackedBarSetting(key)
    local comp = addon.Components and addon.Components.trackedBars
    if not comp or not comp.db then return nil end
    return comp.db[key]
end

--------------------------------------------------------------------------------
-- Shared Styling Helpers (used by default.lua and vertical.lua)
--------------------------------------------------------------------------------

function TB.resolveBarColor(colorMode, tint, defaultR, defaultG, defaultB, defaultA)
    if colorMode == "custom" and type(tint) == "table" then
        return tint[1] or defaultR, tint[2] or defaultG, tint[3] or defaultB, tint[4] or defaultA
    elseif colorMode == "class" and addon.GetClassColorRGB then
        local cr, cg, cb = addon.GetClassColorRGB("player")
        return cr or defaultR, cg or defaultG, cb or defaultB, defaultA
    elseif colorMode == "texture" then
        return 1, 1, 1, 1
    else -- "default"
        return defaultR, defaultG, defaultB, defaultA
    end
end

function TB.applyTextStyling(fontString, cfg, defaultFace)
    if not fontString or not fontString.SetFont then return end
    cfg = cfg or { size = 14, style = "OUTLINE", color = {1,1,1,1} }
    local face = addon.ResolveFontFace and addon.ResolveFontFace(cfg.fontFace or "FRIZQT__") or defaultFace
    if addon.ApplyFontStyle then
        addon.ApplyFontStyle(fontString, face, tonumber(cfg.size) or 14, cfg.style or "OUTLINE")
    else
        fontString:SetFont(face, tonumber(cfg.size) or 14, cfg.style or "OUTLINE")
    end
    local c = addon.ResolveCDMColor(cfg)
    fontString:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
end

--------------------------------------------------------------------------------
-- Forward-Declared Function Slots (populated by other files)
--------------------------------------------------------------------------------

-- Set by vertical.lua
TB.applyVerticalMode = nil
TB.removeVerticalMode = nil
TB.installDataMirrorHooks = nil
TB.hookVertEditMode = nil

-- Set by suppression.lua
TB.isItemSuppressed = nil
TB.enforceSuppressedVisibility = nil
TB.scheduleBackgroundVerification = nil

-- Set by default.lua
TB.getOrCreateBarOverlay = nil
TB.hideBarOverlay = nil

--------------------------------------------------------------------------------
-- OnShow/OnHide Handlers
--------------------------------------------------------------------------------

local vertRebuildPending = false

local function scheduleVerticalRebuild(component)
    if vertRebuildPending then return end
    vertRebuildPending = true
    C_Timer.After(0, function()
        vertRebuildPending = false
        if TB.verticalModeActive and TB.applyVerticalMode then
            TB.applyVerticalMode(component)
        end
    end)
end
TB.scheduleVerticalRebuild = scheduleVerticalRebuild

local function cancelCascade(self)
    local gen = TB.cascadeTimers[self]
    if gen then
        TB.cascadeTimers[self] = gen + 1
    end
end

local function onItemFrameHide(self, component)
    TB.recentHide[self] = GetTime()
    cancelCascade(self)
    TB.auraRemovedSpellID[self] = nil
    if TB.tbTraceEnabled then
        TB.tbTrace("OnHide: id=%s shown=%s", tostring(self):sub(-6), tostring(self:IsShown()))
    end
    if TB.verticalModeActive then
        scheduleVerticalRebuild(component)
    else
        local overlay = TB.trackedBarOverlays[self]
        if overlay then overlay:Hide() end
        pcall(self.SetAlpha, self, 0)
    end
end

local function onItemFrameShow(self, component)
    if TB.tbTraceEnabled then
        local ok, iActive = pcall(function() return self.isActive end)
        TB.tbTrace("OnShow: isActive=%s id=%s hideAge=%s",
            ok and tostring(iActive) or "ERR",
            tostring(self):sub(-6),
            TB.recentHide[self] and string.format("%.3f", GetTime() - TB.recentHide[self]) or "none")
    end
    if TB.verticalModeActive then
        scheduleVerticalRebuild(component)
        return
    end
    local overlay = TB.trackedBarOverlays[self]
    if not overlay then return end

    local ok, isInactive = pcall(function() return self.isActive == false end)
    if ok and not issecretvalue(isInactive) and isInactive then return end

    if TB.isItemSuppressed and TB.isItemSuppressed(self) then
        TB.enforceSuppressedVisibility(self)
        if TB.tbTraceEnabled then
            TB.tbTrace("OnShow(v15): suppressed, keep hidden id=%s", tostring(self):sub(-6))
        end
        return
    end

    -- v15: Show only when not suppressed.
    pcall(function() self:SetAlpha(1) end)
    overlay:Show()

    -- If bounce detected (recent hide), verify in background
    local hideTime = TB.recentHide[self]
    if hideTime and (GetTime() - hideTime) < 0.2 then
        if TB.scheduleBackgroundVerification then
            TB.scheduleBackgroundVerification(self)
        end
    else
        -- Capture spellID for cross-validation
        local okS, spellID = pcall(function() return self:GetSpellID() end)
        if okS and type(spellID) == "number" and not issecretvalue(spellID) then
            TB.barItemFirstSpellID[self] = spellID
        elseif not TB.barItemFirstSpellID[self] and TB.cachedSpellID[self] then
            TB.barItemFirstSpellID[self] = TB.cachedSpellID[self]
        end
        TB.recentHide[self] = nil
        cancelCascade(self)
    end
end

TB.onItemFrameHide = onItemFrameHide
TB.onItemFrameShow = onItemFrameShow

--------------------------------------------------------------------------------
-- TrackedBars Hooks
--------------------------------------------------------------------------------

local trackedBarsHooked = false

local function hookTrackedBars(component)
    if trackedBarsHooked then return end

    local frame = _G[component.frameName]
    if not frame then return end

    if frame.OnAcquireItemFrame then
        hooksecurefunc(frame, "OnAcquireItemFrame", function(viewer, itemFrame)
            -- Always install data mirror hooks (needed for vertical mode)
            if TB.installDataMirrorHooks then
                TB.installDataMirrorHooks(itemFrame)
            end

            -- Cache spellID for combat use (GetSpellID() returns SECRET in combat)
            local okSID, cachedSID = pcall(function() return itemFrame:GetSpellID() end)
            if okSID and type(cachedSID) == "number" and not issecretvalue(cachedSID) then
                TB.cachedSpellID[itemFrame] = cachedSID
            end

            -- Hook visibility changes via OnShow/OnHide
            if not TB.visHookedItems[itemFrame] then
                itemFrame:HookScript("OnHide", function(self) onItemFrameHide(self, component) end)
                itemFrame:HookScript("OnShow", function(self) onItemFrameShow(self, component) end)
                TB.visHookedItems[itemFrame] = true
            end

            if InCombatLockdown and InCombatLockdown() then return end
            local mode = TB.getTrackedBarMode()
            if mode == "vertical" then
                scheduleVerticalRebuild(component)
            else
                C_Timer.After(0, function()
                    if addon.ApplyTrackedBarVisualsForChild then
                        addon.ApplyTrackedBarVisualsForChild(component, itemFrame)
                    end
                end)
            end
        end)
    end

    if frame.RefreshLayout then
        hooksecurefunc(frame, "RefreshLayout", function()
            if InCombatLockdown and InCombatLockdown() then return end
            local mode = TB.getTrackedBarMode()
            if mode == "vertical" then
                scheduleVerticalRebuild(component)
            else
                C_Timer.After(0, function()
                    if not addon or not addon.Components or not addon.Components.trackedBars then return end
                    local comp = addon.Components.trackedBars
                    local f = _G[comp.frameName]
                    if not f then return end
                    for _, child in ipairs({ f:GetChildren() }) do
                        if child:IsShown() and addon.ApplyTrackedBarVisualsForChild then
                            addon.ApplyTrackedBarVisualsForChild(comp, child)
                        end
                    end
                end)
            end
        end)
    end

    -- Hook Edit Mode for vertical mode support
    if TB.hookVertEditMode then
        TB.hookVertEditMode()
    end

    trackedBarsHooked = true
end

--------------------------------------------------------------------------------
-- TrackedBars Component Registration
--------------------------------------------------------------------------------

local function TrackedBarsApplyStyling(component)
    local frame = _G[component.frameName]
    if not frame then return end

    hookTrackedBars(component)

    local mode = TB.getTrackedBarMode()
    if mode == "vertical" then
        if TB.applyVerticalMode then
            TB.applyVerticalMode(component)
        end
    else
        -- Default mode: remove vertical if active, apply overlay styling
        if TB.verticalModeActive and TB.removeVerticalMode then
            TB.removeVerticalMode()
        end
        for _, child in ipairs({ frame:GetChildren() }) do
            if addon.ApplyTrackedBarVisualsForChild then
                addon.ApplyTrackedBarVisualsForChild(component, child)
            end
        end
    end
end

addon:RegisterComponentInitializer(function(self)
    local trackedBars = Component:New({
        id = "trackedBars",
        name = "Tracked Bars",
        frameName = "BuffBarCooldownViewer",
        settings = {
            barMode = { type = "addon", default = "default" },
            iconPadding = { type = "editmode", settingId = 4, default = 3, ui = {
                label = "Icon Padding", widget = "slider", min = 2, max = 10, step = 1, section = "Positioning", order = 1
            }},
            iconBarPadding = { type = "addon", default = 0, ui = {
                label = "Icon/Bar Padding", widget = "slider", min = -20, max = 80, step = 1, section = "Positioning", order = 2
            }},
            positionX = { type = "addon", default = 0, ui = {
                label = "X Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 3
            }},
            positionY = { type = "addon", default = 0, ui = {
                label = "Y Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 4
            }},
            iconSize = { type = "editmode", settingId = 3, default = 100, ui = {
                label = "Bar Scale", widget = "slider", min = 50, max = 200, step = 10, section = "Sizing", order = 1
            }},
            barWidth = { type = "editmode", settingId = 11, default = 100, ui = {
                label = "Bar Width", widget = "slider", min = 50, max = 200, step = 1, section = "Sizing", order = 2
            }},
            styleEnableCustom = { type = "addon", default = true, ui = {
                label = "Enable Custom Textures", widget = "checkbox", section = "Style", order = 0
            }},
            styleForegroundTexture = { type = "addon", default = "bevelled", ui = {
                label = "Foreground Texture", widget = "dropdown", section = "Style", order = 1, optionsProvider = function()
                    if addon.BuildBarTextureOptionsContainer then return addon.BuildBarTextureOptionsContainer() end
                    local c = Settings.CreateControlTextContainer(); c:Add("bevelled", "Bevelled"); return c:GetData()
                end
            }},
            styleBackgroundTexture = { type = "addon", default = "bevelled", ui = {
                label = "Background Texture", widget = "dropdown", section = "Style", order = 2, optionsProvider = function()
                    if addon.BuildBarTextureOptionsContainer then return addon.BuildBarTextureOptionsContainer() end
                    local c = Settings.CreateControlTextContainer(); c:Add("bevelledGrey", "Bevelled Grey"); return c:GetData()
                end
            }},
            styleForegroundColor = { type = "addon", default = {1,1,1,1}, ui = {
                label = "Foreground Color", widget = "color", section = "Style", order = 3
            }},
            styleBackgroundColor = { type = "addon", default = {1,1,1,0.9}, ui = {
                label = "Background Color", widget = "color", section = "Style", order = 4
            }},
            styleBackgroundOpacity = { type = "addon", default = 50, ui = {
                label = "Background Opacity", widget = "slider", min = 0, max = 100, step = 1, section = "Style", order = 5
            }},
            borderEnable = { type = "addon", default = false, ui = {
                label = "Use Custom Border", widget = "checkbox", section = "Border", order = 1
            }},
            borderTintEnable = { type = "addon", default = false, ui = {
                label = "Border Tint", widget = "checkbox", section = "Border", order = 2
            }},
            borderTintColor = { type = "addon", default = {1,1,1,1}, ui = {
                label = "Tint Color", widget = "color", section = "Border", order = 3
            }},
            borderStyle = { type = "addon", default = "square", ui = {
                label = "Border Style", widget = "dropdown", section = "Border", order = 4,
                optionsProvider = function()
                    if addon.BuildBarBorderOptionsContainer then
                        return addon.BuildBarBorderOptionsContainer()
                    end
                    return {}
                end,
            }},
            borderThickness = { type = "addon", default = 1, ui = {
                label = "Border Thickness", widget = "slider", min = 1, max = 8, step = 0.5, section = "Border", order = 5
            }},
            borderInset = { type = "addon", default = 0 },
            borderInsetH = { type = "addon", default = 0 },
            borderInsetV = { type = "addon", default = 0 },
            iconTallWideRatio = { type = "addon", default = 0, ui = {
                label = "Icon Shape", widget = "slider", min = -67, max = 67, step = 1, section = "Icon", order = 1
            }},
            iconBorderEnable = { type = "addon", default = false, ui = {
                label = "Enable Border", widget = "checkbox", section = "Icon", order = 2
            }},
            iconBorderTintEnable = { type = "addon", default = false, ui = {
                label = "Border Tint", widget = "checkbox", section = "Icon", order = 4
            }},
            iconBorderTintColor = { type = "addon", default = {1,1,1,1}, ui = {
                label = "Tint Color", widget = "color", section = "Icon", order = 5
            }},
            iconBorderStyle = { type = "addon", default = "none", ui = {
                label = "Border Style", widget = "dropdown", section = "Icon", order = 6,
                optionsProvider = function()
                    if addon.BuildIconBorderOptionsContainer then
                        return addon.BuildIconBorderOptionsContainer()
                    end
                    return {}
                end
            }},
            iconBorderThickness = { type = "addon", default = 1, ui = {
                label = "Border Thickness", widget = "slider", min = 1, max = 8, step = 0.5, section = "Icon", order = 7
            }},
            iconBorderInset = { type = "addon", default = 0 },
            iconBorderInsetH = { type = "addon", default = 0 },
            iconBorderInsetV = { type = "addon", default = 0 },
            visibilityMode = { type = "editmode", default = "always", ui = {
                label = "Visibility", widget = "dropdown", values = { always = "Always", combat = "Only in Combat", never = "Hidden" }, section = "Misc", order = 1
            }},
            opacity = { type = "editmode", settingId = 5, default = 100, ui = {
                label = "Opacity in Combat", widget = "slider", min = 50, max = 100, step = 1, section = "Misc", order = 2
            }},
            opacityOutOfCombat = { type = "addon", default = 100, ui = {
                label = "Opacity Out of Combat", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 3
            }},
            opacityWithTarget = { type = "addon", default = 100, ui = {
                label = "Opacity With Target", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 4
            }},
            displayMode = { type = "editmode", default = "both", ui = {
                label = "Display Mode", widget = "dropdown", values = { both = "Icon & Name", icon = "Icon Only", name = "Name Only" }, section = "Misc", order = 5
            }},
            hideWhenInactive = { type = "editmode", default = false, ui = {
                label = "Hide when inactive", widget = "checkbox", section = "Misc", order = 6
            }},
            showTimer = { type = "editmode", default = true, ui = {
                label = "Show Timer", widget = "checkbox", section = "Misc", order = 7
            }},
            showTooltip = { type = "editmode", default = true, ui = {
                label = "Show Tooltips", widget = "checkbox", section = "Misc", order = 8
            }},
            supportsText = { type = "addon", default = true },
        },
        ApplyStyling = TrackedBarsApplyStyling,
    })
    self:RegisterComponent(trackedBars)

    -- On-demand state dump: /scoot debug trackedbars dump
    function addon.DumpTBState()
        local comp = addon.Components and addon.Components.trackedBars
        if not comp then addon:Print("No trackedBars component") return end
        local f = _G[comp.frameName]
        if not f then addon:Print("No viewer frame: " .. tostring(comp.frameName)) return end
        local lines = {}
        local function push(s) lines[#lines + 1] = s end
        push("Tracked Bars State Dump")
        push(string.rep("-", 50))
        local ok1, vHWI = pcall(function() return f.hideWhenInactive end)
        push(("Viewer: %s  hideWhenInactive=%s"):format(comp.frameName, ok1 and tostring(vHWI) or "ERR"))
        push("")
        local idx = 0
        for _, child in ipairs({ f:GetChildren() }) do
            if child.GetBarFrame or child.Bar then
                idx = idx + 1
                local ok2, iActive = pcall(function() return child.isActive end)
                local activeSecret = ok2 and issecretvalue(iActive) or false
                local ok3, hwi = pcall(function() return child.hideWhenInactive end)
                local ok4, allow = pcall(function() return child.allowHideWhenInactive end)
                local overlay = TB.trackedBarOverlays[child]
                local oVis = overlay and overlay:IsVisible()
                local bgVis = overlay and overlay.barBg and overlay.barBg:IsVisible()
                local bgA = overlay and overlay.barBg and overlay.barBg:GetAlpha()
                local suppressed = TB.isItemSuppressed and TB.isItemSuppressed(child) or false
                local pendingAdd = TB.pendingAuraAdd[child] ~= nil
                push(("[%d] shown=%s visible=%s isActive=%s(secret=%s)"):format(
                    idx, tostring(child:IsShown()), tostring(child:IsVisible()),
                    ok2 and (activeSecret and "SECRET" or tostring(iActive)) or "ERR",
                    tostring(activeSecret)))
                push(("     hwi=%s allowHWI=%s overlay=%s bgVis=%s bgAlpha=%s suppressed=%s pendingAdd=%s"):format(
                    ok3 and tostring(hwi) or "ERR",
                    ok4 and tostring(allow) or "ERR",
                    tostring(oVis), tostring(bgVis), tostring(bgA), tostring(suppressed), tostring(pendingAdd)))
            end
        end
        push("")
        push("Total items: " .. idx)
        if addon.DebugShowWindow then
            addon.DebugShowWindow("Tracked Bars State", table.concat(lines, "\n"))
        end
    end
end)
