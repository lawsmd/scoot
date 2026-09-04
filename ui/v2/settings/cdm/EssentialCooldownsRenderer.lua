-- EssentialCooldownsRenderer.lua - Essential Cooldowns settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.CDM = addon.UI.Settings.CDM or {}
addon.UI.Settings.CDM.EssentialCooldowns = {}

local EssentialCooldowns = addon.UI.Settings.CDM.EssentialCooldowns
local SettingsBuilder = addon.UI.SettingsBuilder

function EssentialCooldowns.Render(panel, scrollContent)
    -- Clear any existing content
    panel:ClearContent()

    -- Create builder for this content area
    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    -- Store reference to this function for re-rendering on expand/collapse
    builder:SetOnRefresh(function()
        EssentialCooldowns.Render(panel, scrollContent)
    end)

    local Helpers = addon.UI.Settings.Helpers
    local h = Helpers.CreateComponentHelpers("essentialCooldowns")
    local getSetting, setSetting = h.get, h.set
    local syncEditModeSetting = h.sync

    -- Collapsible section: Positioning
    builder:AddCollapsibleSection({
        title = "Positioning",
        componentId = "essentialCooldowns",
        sectionKey = "positioning",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            -- Use centralized setting patterns for orientation-dependent settings
            local OrientationPatterns = addon.UI.SettingPatterns.Orientation

            -- Get current orientation for initial values
            local currentOrientation = getSetting("orientation") or "H"
            local initialDirValues, initialDirOrder = OrientationPatterns.getDirectionOptions(currentOrientation)

            -- Center Anchor toggle - changes how the first row expands
            inner:AddToggle({
                key = "centerAnchor",
                label = "Center Icons on Edit Mode Anchor",
                description = "Centers icons on the anchor point. Useful when sharing profiles across characters with different cooldown counts.",
                get = function() return getSetting("centerAnchor") or false end,
                set = function(v)
                    setSetting("centerAnchor", v)
                    if addon.RefreshCDMCenterAnchor then
                        addon.RefreshCDMCenterAnchor("essentialCooldowns")
                    end
                end,
            })

            -- Center Additional Rows toggle - changes how overflow rows are positioned
            inner:AddToggle({
                key = "centerAdditionalRows",
                label = "Center Additional Rows",
                description = "Centers overflow rows under the first row for a balanced appearance.",
                get = function() return getSetting("centerAdditionalRows") or false end,
                set = function(v)
                    setSetting("centerAdditionalRows", v)
                    if addon.RefreshCDMCenterAnchor then
                        addon.RefreshCDMCenterAnchor("essentialCooldowns")
                    end
                end,
            })

            inner:AddSelector({
                key = "orientation",
                label = "Orientation",
                description = "Horizontal arranges icons left-to-right, Vertical arranges top-to-bottom.",
                values = addon.Catalogs.Orientation.values,
                order = addon.Catalogs.Orientation.order,
                get = function() return getSetting("orientation") or "H" end,
                set = function(v)
                    setSetting("orientation", v)
                    syncEditModeSetting("orientation")

                    -- Dynamically update dependent controls
                    local dirSelector = inner:GetControl("iconDirection")
                    if dirSelector then
                        local newValues, newOrder = OrientationPatterns.getDirectionOptions(v)
                        dirSelector:SetOptions(newValues, newOrder)
                    end

                    local columnsSlider = inner:GetControl("columnsRows")
                    if columnsSlider then
                        columnsSlider:SetLabel(OrientationPatterns.getColumnsLabel(v))
                    end

                    -- Update centering for new orientation if either feature is enabled
                    if (getSetting("centerAnchor") or getSetting("centerAdditionalRows")) and addon.RefreshCDMCenterAnchor then
                        addon.RefreshCDMCenterAnchor("essentialCooldowns")
                    end
                end,
                -- Prevent rapid changes during Edit Mode sync (orientation changes trigger
                -- expensive Apply operations; allow 400ms for sync to complete)
                syncCooldown = 0.4,
            })

            inner:AddSlider({
                key = "columnsRows",
                label = OrientationPatterns.getColumnsLabel(currentOrientation),
                description = OrientationPatterns.getColumnsDescription(currentOrientation),
                min = 1,
                max = 20,
                step = 1,
                get = function() return getSetting("columns") or 12 end,
                set = function(v) setSetting("columns", v) end,
                minLabel = "1",
                maxLabel = "20",
                -- Debounced Edit Mode sync for slider performance
                debounceKey = "UI_essentialCooldowns_columns",
                debounceDelay = 0.2,
                onEditModeSync = function(newValue)
                    syncEditModeSetting("columns")
                end,
            })

            inner:AddSelector({
                key = "iconDirection",
                label = "Icon Direction",
                description = "Direction icons grow from the anchor point.",
                values = initialDirValues,
                order = initialDirOrder,
                get = function() return getSetting("direction") or "right" end,
                set = function(v)
                    setSetting("direction", v)
                    syncEditModeSetting("direction")
                end,
                -- Prevent rapid changes during Edit Mode sync
                syncCooldown = 0.4,
            })

            inner:AddSlider({
                label = "Icon Padding",
                description = "Space between cooldown icons in pixels.",
                min = 2,
                max = 14,
                step = 1,
                get = function() return getSetting("iconPadding") or 2 end,
                set = function(v) setSetting("iconPadding", v) end,
                minLabel = "2px",
                maxLabel = "14px",
                -- Debounced Edit Mode sync for slider performance
                debounceKey = "UI_essentialCooldowns_iconPadding",
                debounceDelay = 0.2,
                onEditModeSync = function(newValue)
                    syncEditModeSetting("iconPadding")
                end,
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Sizing
    builder:AddCollapsibleSection({
        title = "Sizing",
        componentId = "essentialCooldowns",
        sectionKey = "sizing",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            -- Icon Size (Scale) - Edit Mode setting
            inner:AddSlider({
                label = "Icon Size (Scale)",
                description = "Scale the icons in Edit Mode (50-200%).",
                min = 50,
                max = 200,
                step = 10,
                get = function() return getSetting("iconSize") or 100 end,
                set = function(v) setSetting("iconSize", v) end,
                minLabel = "50%",
                maxLabel = "200%",
                debounceKey = "UI_essentialCooldowns_iconSize",
                debounceDelay = 0.2,
                onEditModeSync = function(newValue)
                    syncEditModeSetting("iconSize")
                end,
            })

            -- Icon Shape (Tall/Wide Ratio)
            inner:AddSlider({
                label = "Icon Shape",
                description = "Adjust icon aspect ratio. Center = square icons.",
                min = -67,
                max = 67,
                step = 1,
                get = function() return getSetting("tallWideRatio") or 0 end,
                set = function(v)
                    setSetting("tallWideRatio", v)
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end,
                minLabel = "Wide",
                maxLabel = "Tall",
            })

            -- Swipe Inset
            inner:AddSlider({
                label = "Swipe Inset",
                description = "Shrinks the cooldown swipe area inward to prevent protrusion outside borders on non-square icons.",
                min = 0, max = 10, step = 1,
                get = function() return getSetting("swipeInset") or 0 end,
                set = function(v)
                    setSetting("swipeInset", v)
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end,
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Icons
    builder:AddCollapsibleSection({
        title = "Icons",
        componentId = "essentialCooldowns",
        sectionKey = "icons",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Icon Zoom",
                description = "Crops icon edges inward to reduce visible rounded corners from Blizzard's icon mask.",
                min = 0, max = 30, step = 1,
                get = function() return getSetting("iconZoom") or 0 end,
                set = function(v)
                    setSetting("iconZoom", v)
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end,
                minLabel = "0%", maxLabel = "30%",
            })

            inner:AddToggle({
                label = "Square Cooldown Swipe",
                description = "Replaces the circular cooldown animation with a square one.",
                get = function() return getSetting("squareCooldownSwipe") or false end,
                set = function(v)
                    setSetting("squareCooldownSwipe", v)
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end,
            })

            inner:AddToggle({
                label = "Hide Decorative Ring",
                description = "Hides Blizzard's ornamental ring overlay around each icon.",
                get = function() return getSetting("hideDecorativeRing") or false end,
                set = function(v)
                    setSetting("hideDecorativeRing", v)
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end,
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Animations
    builder:AddCollapsibleSection({
        title = "Animations",
        componentId = "essentialCooldowns",
        sectionKey = "animations",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            -- Preview animation state (shared between preview row and tab controls)
            local PREVIEW_SIZE = 42
            local PREVIEW_ROW_HEIGHT = 72
            local startCtrl, previewTicker
            local animsRunning = false
            local iconFrame  -- set below in preview row creation

            local PROC_START_PREVIEW_ANIM_IDS = {
                flashPulse = "procStartFlashPulse",
                scaleBurst = "procStartScaleBurst",
                ringExpand = "procStartRingExpand",
                crossFlare = "procStartCrossFlare",
                diamondBurst = "procStartDiamondBurst",
                starburst = "procStartStarburst",
                pixelScatter = "procStartPixelScatter",
                spinFade = "procStartSpinFade",
                cornerBrackets = "procStartCornerBrackets",
                doubleRing = "procStartDoubleRing",
            }

            local function startAnimations()
                if animsRunning or not iconFrame then return end
                animsRunning = true

                -- Proc loop preview
                local procLoopStyle = getSetting("procLoopStyle") or "default"
                if procLoopStyle ~= "default" and addon.PixelGlow then
                    addon.PixelGlow.StartForIcon(iconFrame, {
                        style = (procLoopStyle == "pixelDots") and "dots" or "dashes",
                        colorMode = getSetting("procLoopColor") or "custom",
                        customColor = getSetting("procLoopCustomColor") or {1, 0.84, 0, 1},
                        speed = getSetting("procLoopSpeed") or 25,
                        iconW = PREVIEW_SIZE, iconH = PREVIEW_SIZE,
                        insetH = 0, insetV = 0,
                    })
                end

                -- Proc start preview
                local procStartStyle = getSetting("procStartStyle") or "default"
                local animId = PROC_START_PREVIEW_ANIM_IDS[procStartStyle]
                if animId and addon.ProcStart then
                    startCtrl = addon.ProcStart.CreatePreviewController(animId, iconFrame)
                    if startCtrl then
                        startCtrl:SetSize(PREVIEW_SIZE, PREVIEW_SIZE)
                        startCtrl:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
                        startCtrl:SetFrameLevel(iconFrame:GetFrameLevel() + 10)

                        -- Apply particle scale
                        local pScale = getSetting("procStartScale") or 1
                        local meta = addon.ProcStart.ANIM_META and addon.ProcStart.ANIM_META[animId]
                        if pScale > 1 and meta and meta.supportsScale then
                            local textures = startCtrl:GetTextures()
                            if textures then
                                for _, tex in ipairs(textures) do
                                    local w, h = tex:GetSize()
                                    if w and w > 0 and h and h > 0 then
                                        tex:SetSize(w * pScale, h * pScale)
                                    end
                                end
                            end
                        end

                        -- Apply color
                        local colorMode = getSetting("procStartColor") or "custom"
                        local customColor = getSetting("procStartCustomColor") or {1, 1, 1, 1}
                        local textures = startCtrl:GetTextures()
                        if textures then
                            local cr, cg, cb, ca = addon.ResolveColorRGBA(colorMode, customColor)
                            for _, tex in ipairs(textures) do
                                tex:SetVertexColor(cr, cg, cb, ca)
                            end
                        end

                        startCtrl:Play()
                        previewTicker = C_Timer.NewTicker(3, function()
                            if startCtrl and iconFrame and iconFrame:IsShown() then
                                startCtrl:Play()
                            end
                        end)
                    end
                end
            end

            local function stopAnimations()
                if not animsRunning then return end
                animsRunning = false
                if previewTicker then previewTicker:Cancel(); previewTicker = nil end
                if startCtrl then startCtrl:Destroy(); startCtrl = nil end
                if iconFrame and addon.PixelGlow then
                    addon.PixelGlow.ReleaseForIcon(iconFrame)
                end
            end

            local function restartAnimations()
                stopAnimations()
                if contentFrame:IsShown() then
                    startAnimations()
                end
            end

            -- Preview row
            do
                local theme = addon.UI.Theme
                local row = CreateFrame("Frame", nil, contentFrame)
                row:SetHeight(PREVIEW_ROW_HEIGHT)

                local labelFS = row:CreateFontString(nil, "OVERLAY")
                labelFS:SetFont(theme:GetFont("LABEL"), 13, "")
                labelFS:SetPoint("LEFT", row, "LEFT", 12, 0)
                labelFS:SetText("Preview:")
                local ar, ag, ab = theme:GetAccentColor()
                labelFS:SetTextColor(ar, ag, ab, 1)

                iconFrame = CreateFrame("Frame", nil, row)
                iconFrame:SetSize(PREVIEW_SIZE, PREVIEW_SIZE)
                iconFrame:SetPoint("CENTER", row, "CENTER", 0, 0)

                local specIndex = GetSpecialization and GetSpecialization()
                local iconTexture = 134400
                if specIndex then
                    local _, _, _, specIcon = GetSpecializationInfo(specIndex)
                    if specIcon then iconTexture = specIcon end
                end
                local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
                iconTex:SetAllPoints()
                iconTex:SetTexture(iconTexture)
                iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

                local iconBg = iconFrame:CreateTexture(nil, "BACKGROUND")
                iconBg:SetAllPoints()
                iconBg:SetColorTexture(0, 0, 0, 0.6)

                local bottomBorder = row:CreateTexture(nil, "BORDER", nil, -1)
                bottomBorder:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
                bottomBorder:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
                bottomBorder:SetHeight(1)
                bottomBorder:SetColorTexture(ar, ag, ab, 0.2)

                contentFrame:HookScript("OnShow", function() startAnimations() end)
                contentFrame:HookScript("OnHide", function() stopAnimations() end)
                if contentFrame:IsShown() then
                    startAnimations()
                end

                row.Cleanup = function(self) stopAnimations() end
                row:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 8, inner._currentY)
                row:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -8, inner._currentY)
                table.insert(inner._controls, row)
                inner._currentY = inner._currentY - PREVIEW_ROW_HEIGHT
            end

            inner:AddTabbedSection({
                tabs = {
                    { key = "procStart", label = "Proc Start" },
                    { key = "procLoop", label = "Proc Loop" },
                    { key = "cooldownEnds", label = "Cooldown Ends" },
                },
                componentId = "essentialCooldowns",
                sectionKey = "animationTabs",
                buildContent = {
                    procStart = function(tabContent, tabBuilder)
                        tabBuilder:AddSelector({
                            label = "Proc Start Style",
                            values = {
                                default = "Default (Blizzard)",
                                none = "None",
                                flashPulse = "Flash Pulse",
                                scaleBurst = "Scale Burst",
                                ringExpand = "Ring Expand",
                                crossFlare = "Cross Flare",
                                diamondBurst = "Diamond Burst",
                                starburst = "Starburst",
                                pixelScatter = "Pixel Scatter",
                                spinFade = "Spin Fade",
                                cornerBrackets = "Corner Brackets",
                                doubleRing = "Double Ring",
                            },
                            order = { "default", "none", "flashPulse", "scaleBurst", "ringExpand", "crossFlare", "diamondBurst", "starburst", "pixelScatter", "spinFade", "cornerBrackets", "doubleRing" },
                            get = function() return getSetting("procStartStyle") or "default" end,
                            set = function(v)
                                setSetting("procStartStyle", v)
                                restartAnimations()
                            end,
                            infoIcon = {
                                tooltipTitle = "Proc Start Style",
                                tooltipText = "The proc start is a brief burst animation (~0.5s) that plays when a spell procs, before the continuous proc loop glow begins. Code-only animations use no custom textures.",
                            },
                        })
                        tabBuilder:AddSelectorColorPicker({
                            label = "Start Color",
                            values = {
                                custom = "Custom",
                                class = "Class Color",
                            },
                            order = { "custom", "class" },
                            get = function() return getSetting("procStartColor") or "custom" end,
                            set = function(v)
                                setSetting("procStartColor", v)
                                restartAnimations()
                            end,
                            getColor = function()
                                local c = getSetting("procStartCustomColor") or {1, 1, 1, 1}
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                setSetting("procStartCustomColor", {r, g, b, a})
                                restartAnimations()
                            end,
                            customValue = "custom",
                            hasAlpha = false,
                            disabled = function()
                                local s = getSetting("procStartStyle") or "default"
                                return s == "default" or s == "none"
                            end,
                        })
                        tabBuilder:AddSlider({
                            label = "Particle Scale",
                            min = 1.0, max = 3.0, step = 0.25,
                            precision = 2,
                            displaySuffix = "x",
                            get = function() return getSetting("procStartScale") or 1 end,
                            set = function(v)
                                setSetting("procStartScale", v)
                                restartAnimations()
                            end,
                            minLabel = "1x",
                            maxLabel = "3x",
                            disabled = function()
                                local s = getSetting("procStartStyle") or "default"
                                return s == "default" or s == "none"
                            end,
                        })
                        tabBuilder:Finalize()
                    end,
                    procLoop = function(tabContent, tabBuilder)
                        tabBuilder:AddSelector({
                            label = "Proc Loop Style",
                            values = {
                                default = "Default (Blizzard)",
                                pixelDots = "Pixel Dots",
                                pixelDashes = "Pixel Dashes",
                            },
                            order = { "default", "pixelDots", "pixelDashes" },
                            get = function() return getSetting("procLoopStyle") or "default" end,
                            set = function(v)
                                setSetting("procLoopStyle", v)
                            end,
                            infoIcon = {
                                tooltipTitle = "Proc Loop Style",
                                tooltipText = "Replaces Blizzard's flipbook proc glow with a code-generated pixel animation. Pixel Dots uses 16 small squares, Pixel Dashes uses 8 longer segments. Both rotate around the icon perimeter.",
                            },
                        })
                        tabBuilder:AddSelectorColorPicker({
                            label = "Glow Color",
                            values = {
                                custom = "Custom",
                                class = "Class Color",
                                rainbow = "Rainbow",
                            },
                            order = { "custom", "class", "rainbow" },
                            get = function() return getSetting("procLoopColor") or "custom" end,
                            set = function(v)
                                setSetting("procLoopColor", v)
                            end,
                            getColor = function()
                                local c = getSetting("procLoopCustomColor") or {1, 0.84, 0, 1}
                                return c[1] or 1, c[2] or 0.84, c[3] or 0, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                setSetting("procLoopCustomColor", {r, g, b, a})
                            end,
                            customValue = "custom",
                            hasAlpha = false,
                            disabled = function() return (getSetting("procLoopStyle") or "default") == "default" end,
                        })
                        tabBuilder:AddSlider({
                            label = "Animation Speed",
                            min = -20,
                            max = 70,
                            step = 5,
                            get = function() return getSetting("procLoopSpeed") or 25 end,
                            set = function(v)
                                setSetting("procLoopSpeed", v)
                            end,
                            minLabel = "Slow",
                            maxLabel = "Fast",
                            disabled = function() return (getSetting("procLoopStyle") or "default") == "default" end,
                        })
                        tabBuilder:AddInsetPair({
                            label = "Glow Inset", min = -5, max = 10, minLabel = false, maxLabel = false,
                            disabled = function() return (getSetting("procLoopStyle") or "default") == "default" end,
                            get = function(axis) return getSetting(axis == "h" and "procLoopInsetH" or "procLoopInsetV") end,
                            set = function(axis, v) setSetting(axis == "h" and "procLoopInsetH" or "procLoopInsetV", v) end,
                        })
                        tabBuilder:Finalize()
                    end,
                    cooldownEnds = function(tabContent, tabBuilder)
                        tabBuilder:AddDescription("Future animations for cooldown completion events will appear here.")
                        tabBuilder:Finalize()
                    end,
                },
            })
            inner:Finalize()
        end,
    })

    -- Collapsible section: Border
    builder:AddCollapsibleSection({
        title = "Border",
        componentId = "essentialCooldowns",
        sectionKey = "border",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            local get, set = Helpers.CreateIconBorderAccessors(getSetting, setSetting, "border", { insetDefault = -1 })
            inner:AddIconBorderBlock({
                get = get, set = set, apply = Helpers.applyStyles,
                enableToggle = { description = "Enable custom border styling for cooldown icons." },
                style = { description = "Choose the visual style for icon borders." },
                tint = { description = "Apply a custom tint color to the icon border." },
                thickness = { description = "Thickness of the border in pixels." },
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Text (contains tabbed sub-sections)
    builder:AddCollapsibleSection({
        title = "Text",
        componentId = "essentialCooldowns",
        sectionKey = "text",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            local function applyText()
                if addon and addon.ApplyStyles then
                    C_Timer.After(0, function() addon:ApplyStyles() end)
                end
            end

            inner:AddTabbedSection({
                tabs = {
                    { key = "charges", label = "Charges" },
                    { key = "cooldowns", label = "Cooldowns" },
                    { key = "bindings", label = "Keybinds", infoIcon = {
                        tooltipTitle = "Keybind Labels",
                        tooltipText = "Addon-generated text showing your keybind for each ability. Enable with the toggle below.",
                    }},
                },
                componentId = "essentialCooldowns",
                sectionKey = "textTabs",
                buildContent = {
                    charges = function(tabContent, tabBuilder)
                        -- Charge/stack text is a Blizzard FontString styled in
                        -- place, so the plain style order applies (no paired
                        -- Deep Shadow styles).
                        local s = Helpers.CreateSubTableHelpers("essentialCooldowns", "textStacks", { apply = applyText })
                        tabBuilder:AddTextStyleBlock({
                            get = s.get, set = s.set, apply = applyText,
                            defaults = { size = 16 },
                            font = { description = "The font used for charges/stacks text." },
                            size = { min = 6, max = 32, minLabel = "6", maxLabel = "32" },
                        })
                        tabBuilder:Finalize()
                    end,
                    cooldowns = function(tabContent, tabBuilder)
                        -- Cooldown text is a Blizzard FontString styled in
                        -- place; plain style order, same as charges.
                        local s = Helpers.CreateSubTableHelpers("essentialCooldowns", "textCooldown", { apply = applyText })
                        tabBuilder:AddTextStyleBlock({
                            get = s.get, set = s.set, apply = applyText,
                            font = { description = "The font used for cooldown timer text." },
                            size = { min = 6, max = 32, minLabel = "6", maxLabel = "32" },
                        })
                        tabBuilder:Finalize()
                    end,
                    bindings = function(tabContent, tabBuilder)
                        local s = Helpers.CreateSubTableHelpers("essentialCooldowns", "textBindings", { apply = applyText })

                        -- Enable toggle
                        tabBuilder:AddToggle({
                            label = "Show Keybinds",
                            description = "Display keybind text on cooldown icons.",
                            get = function() return not not s.get("enabled") end,
                            set = function(v) s.setAndApply("enabled", v) end,
                        })

                        -- Keybind text is Scoot-drawn, so the paired Deep
                        -- Shadow styles are offered here
                        tabBuilder:AddTextStyleBlock({
                            get = s.get, set = s.set, apply = applyText,
                            defaults = { size = 12 },
                            font = { description = "The font used for keybind text." },
                            style = { order = Helpers.fontStyleOrderPaired },
                            size = { min = 6, max = 32, minLabel = "6", maxLabel = "32" },
                            alignment = { kind = "anchor9", default = "TOPLEFT" },
                        })

                        tabBuilder:Finalize()
                    end,
                },
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Visibility & Misc
    builder:AddCollapsibleSection({
        title = "Visibility & Misc",
        componentId = "essentialCooldowns",
        sectionKey = "misc",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            -- Priority system header + explainer (dynamic based on mode)
            local cdMode = getSetting("cooldownOpacityMode") or "onCooldown"
            local isOffCD = (cdMode == "offCooldown")
            local modeWord = isOffCD and "Off Cooldown" or "On Cooldown"

            inner:AddDescription("Priority System", { color = {1, 0.82, 0}, fontSize = 14, topPadding = 4 })
            inner:AddDescription("In Combat > With Target > Out of Combat. Only the highest active condition applies. "
                .. modeWord .. " competes with the result \226\128\148 whichever is the stronger dim takes effect.", { color = {1, 0.82, 0}, topPadding = -8, bottomPadding = -4 })

            -- Mode selector: On Cooldown vs Off Cooldown
            inner:AddSelector({
                label = "Reduce Opacity While...",
                values = { onCooldown = "On Cooldown", offCooldown = "Off Cooldown" },
                order = { "onCooldown", "offCooldown" },
                get = function() return getSetting("cooldownOpacityMode") or "onCooldown" end,
                set = function(v)
                    setSetting("cooldownOpacityMode", v == "onCooldown" and nil or v)
                    if addon and addon.RefreshCDMCooldownOpacity then
                        addon.RefreshCDMCooldownOpacity("EssentialCooldownViewer", "essentialCooldowns")
                    end
                    builder:DeferredRefreshAll()
                end,
            })

            -- Opacity slider(s): DualSlider (icon+text) for on-CD mode, single Slider for off-CD mode
            if isOffCD then
                inner:AddSlider({
                    label = "Opacity While off Cooldown",
                    description = "Dim icons when ready (off cooldown).",
                    min = 0, max = 100, step = 1,
                    get = function() return getSetting("opacityOnCooldown") or 100 end,
                    set = function(v)
                        setSetting("opacityOnCooldown", v)
                        if addon and addon.RefreshCDMCooldownOpacity then
                            addon.RefreshCDMCooldownOpacity("EssentialCooldownViewer", "essentialCooldowns")
                        end
                    end,
                    minLabel = "Hidden", maxLabel = "100%",
                })
            else
                inner:AddDualSlider({
                    label = "Opacity While on Cooldown",
                    description = "Dim icons when on cooldown. Text slider keeps the countdown timer readable.",
                    sliderA = {
                        axisLabel = "Icon",
                        min = 0, max = 100, step = 1,
                        get = function() return getSetting("opacityOnCooldown") or 100 end,
                        set = function(v)
                            setSetting("opacityOnCooldown", v)
                            if addon and addon.RefreshCDMCooldownOpacity then
                                addon.RefreshCDMCooldownOpacity("EssentialCooldownViewer", "essentialCooldowns")
                            end
                        end,
                        minLabel = "Hidden", maxLabel = "100%",
                    },
                    sliderB = {
                        axisLabel = "Text",
                        min = 0, max = 100, step = 1,
                        get = function() return getSetting("opacityOnCooldownText") or 100 end,
                        set = function(v)
                            setSetting("opacityOnCooldownText", v)
                            if addon and addon.RefreshCDMCooldownOpacity then
                                addon.RefreshCDMCooldownOpacity("EssentialCooldownViewer", "essentialCooldowns")
                            end
                        end,
                        minLabel = "Hidden", maxLabel = "100%",
                    },
                })
            end

            local get, set = Helpers.CreateFlatAccessors(getSetting, setSetting, addon.Opacity.Keys.Plain)
            inner:AddStateOpacityBlock({
                get = get, set = set, combatMin = 50, min = 0,
                apply = function()
                    if addon and addon.RefreshCDMViewerOpacity then
                        addon.RefreshCDMViewerOpacity("essentialCooldowns")
                    end
                end,
                -- The combat value is the Edit Mode setting: no refresh, the sync applies.
                combat = {
                    apply = false,
                    debounceKey = "UI_essentialCooldowns_opacity",
                    debounceDelay = 0.2,
                    onEditModeSync = function() syncEditModeSetting("opacity") end,
                },
            })

            -- Visibility Mode selector (Edit Mode setting)
            inner:AddSelector({
                label = "Visibility",
                description = "When the cooldown tracker is visible.",
                values = addon.Catalogs.Visibility.values,
                order = addon.Catalogs.Visibility.order,
                get = function() return getSetting("visibilityMode") or "always" end,
                set = function(v)
                    setSetting("visibilityMode", v)
                    syncEditModeSetting("visibilityMode")
                end,
                syncCooldown = 0.4,
            })

            -- Show Timer toggle (Edit Mode setting)
            inner:AddToggle({
                label = "Show Timer",
                description = "Display cooldown timer text on icons.",
                get = function() return getSetting("showTimer") ~= false end,
                set = function(v)
                    setSetting("showTimer", v)
                    syncEditModeSetting("showTimer")
                end,
            })

            -- Show Tooltips toggle (Edit Mode setting)
            inner:AddToggle({
                label = "Show Tooltips",
                description = "Display tooltips when hovering over icons.",
                get = function() return getSetting("showTooltip") ~= false end,
                set = function(v)
                    setSetting("showTooltip", v)
                    syncEditModeSetting("showTooltip")
                end,
            })

            inner:Finalize()
        end,
    })

    -- Finalize the layout
    builder:Finalize()
end

addon.UI.SettingsPanel:RegisterRenderer("essentialCooldowns", function(panel, scrollContent)
    EssentialCooldowns.Render(panel, scrollContent)
end)

return EssentialCooldowns
