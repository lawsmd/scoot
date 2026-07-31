-- settingspanel/renderers.lua - Renderer registry with self-registration support
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.SettingsPanel = addon.UI.SettingsPanel or {}
local UIPanel = addon.UI.SettingsPanel

-- Renderer Registry
-- Renderer files self-register via RegisterRenderer() at load time.

UIPanel._renderers = {}

function UIPanel:RegisterRenderer(key, renderFn)
    self._renderers[key] = renderFn
end

-- Debug Menu (inline renderer)

UIPanel:RegisterRenderer("debugMenu", function(self, scrollContent)
    local Controls = addon.UI.Controls
    local Theme = addon.UI.Theme

    self._debugMenuControls = self._debugMenuControls or {}
    for _, ctrl in ipairs(self._debugMenuControls) do
        if ctrl.Cleanup then ctrl:Cleanup() end
        if ctrl.Hide then ctrl:Hide() end
        if ctrl.SetParent then ctrl:SetParent(nil) end
    end
    self._debugMenuControls = {}

    local headerLabel = scrollContent:CreateFontString(nil, "OVERLAY")
    Theme:ApplyLabelFont(headerLabel, 14)
    headerLabel:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, 0)
    headerLabel:SetText("Developer Testing Tools")
    local ar, ag, ab = Theme:GetAccentColor()
    headerLabel:SetTextColor(ar, ag, ab, 1)
    table.insert(self._debugMenuControls, headerLabel)

    local yOffset = -30

    local descLabel = scrollContent:CreateFontString(nil, "OVERLAY")
    Theme:ApplyValueFont(descLabel, 11)
    descLabel:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset)
    descLabel:SetPoint("RIGHT", scrollContent, "RIGHT", -20, 0)
    descLabel:SetText("These options are for addon development and testing. Use with caution.")
    descLabel:SetTextColor(0.7, 0.7, 0.7, 1)
    descLabel:SetJustifyH("LEFT")
    descLabel:SetWordWrap(true)
    table.insert(self._debugMenuControls, descLabel)

    yOffset = yOffset - 50

    local secretCVars = {
        "secretCombatRestrictionsForced",
        "secretChallengeModeRestrictionsForced",
        "secretEncounterRestrictionsForced",
        "secretMapRestrictionsForced",
        "secretPvPMatchRestrictionsForced",
    }

    local toggle = Controls:CreateToggle({
        parent = scrollContent,
        label = "Force Secret Restrictions",
        description = "Enables all secret restriction CVars to simulate combat/instance restrictions for testing taint behavior.",
        get = function()
            local val = GetCVar("secretCombatRestrictionsForced")
            return val == "1"
        end,
        set = function(enabled)
            local newVal = enabled and "1" or "0"
            for _, cvar in ipairs(secretCVars) do
                pcall(SetCVar, cvar, newVal)
            end
        end,
    })
    toggle:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset)
    toggle:SetPoint("RIGHT", scrollContent, "RIGHT", 0, 0)
    table.insert(self._debugMenuControls, toggle)

    yOffset = yOffset - 70

    local bugSackToggle = Controls:CreateToggle({
        parent = scrollContent,
        label = "Keep BugSack Button Separate",
        description = "Keep BugSack's minimap button visible outside the addon button container.",
        get = function()
            return addon.db and addon.db.profile and addon.db.profile.bugSackButtonSeparate
        end,
        set = function(enabled)
            if addon.db and addon.db.profile then
                addon.db.profile.bugSackButtonSeparate = enabled
                local minimapComp = addon.Components and addon.Components["minimapStyle"]
                if minimapComp and minimapComp.ApplyStyling then
                    minimapComp:ApplyStyling()
                end
            end
        end,
    })
    bugSackToggle:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset)
    bugSackToggle:SetPoint("RIGHT", scrollContent, "RIGHT", 0, 0)
    table.insert(self._debugMenuControls, bugSackToggle)

    yOffset = yOffset - 70

    --------------------------------------------------------------------------
    -- TEMP: UFZ health text font switcher
    --------------------------------------------------------------------------
    -- Remove once the Unit Frames Z health block font is chosen. Clickable
    -- front-end for the '/scoot debug healthtext' font and layout commands --
    -- the command grammar got too long to keep retyping while comparing faces
    -- in content.
    --------------------------------------------------------------------------

    local htHeader = scrollContent:CreateFontString(nil, "OVERLAY")
    Theme:ApplyLabelFont(htHeader, 13)
    htHeader:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset)
    htHeader:SetText("TEMP - Health Text Fonts (UFZ)")
    htHeader:SetTextColor(ar, ag, ab, 1)
    table.insert(self._debugMenuControls, htHeader)

    yOffset = yOffset - 24

    if not addon.DebugHealthTextGetConfig then
        local htMissing = scrollContent:CreateFontString(nil, "OVERLAY")
        Theme:ApplyValueFont(htMissing, 11)
        htMissing:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset)
        htMissing:SetPoint("RIGHT", scrollContent, "RIGHT", -20, 0)
        htMissing:SetText("Health text harness not loaded -- /reload and reopen this panel.")
        htMissing:SetTextColor(0.7, 0.7, 0.7, 1)
        htMissing:SetJustifyH("LEFT")
        htMissing:SetWordWrap(true)
        table.insert(self._debugMenuControls, htMissing)
        yOffset = yOffset - 40
    else
        local htDesc = scrollContent:CreateFontString(nil, "OVERLAY")
        Theme:ApplyValueFont(htDesc, 11)
        htDesc:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset)
        htDesc:SetPoint("RIGHT", scrollContent, "RIGHT", -20, 0)
        htDesc:SetText("Applies live to the health text test frame (shows it if hidden). Candidates is the Modified-tab variant set; Browse covers every registered font for scouting new bake candidates.")
        htDesc:SetTextColor(0.7, 0.7, 0.7, 1)
        htDesc:SetJustifyH("LEFT")
        htDesc:SetWordWrap(true)
        table.insert(self._debugMenuControls, htDesc)

        yOffset = yOffset - 60

        local candDropdown, browseRow

        local candidateOrder = {
            "ANTON", "ANTON_WIDE_120", "ANTON_WIDE_150", "ANTON_WIDE_180",
            "ANTON_TALL_90", "ANTON_TALL_80", "ANTON_TALL_70",
            "RUBIK_MONO_ONE", "RUBIK_MONO_ONE_WIDE_120", "RUBIK_MONO_ONE_WIDE_150", "RUBIK_MONO_ONE_WIDE_180",
            "RUBIK_MONO_ONE_TALL_90", "RUBIK_MONO_ONE_TALL_80", "RUBIK_MONO_ONE_TALL_70",
            "TOMORROW_BLACK", "TOMORROW_BLACK_WIDE_120", "TOMORROW_BLACK_WIDE_150", "TOMORROW_BLACK_WIDE_180",
            "TOMORROW_BLACK_TALL_90", "TOMORROW_BLACK_TALL_80", "TOMORROW_BLACK_TALL_70",
            "BUNGEE", "BUNGEE_WIDE_120", "BUNGEE_WIDE_150", "BUNGEE_WIDE_180",
            "BUNGEE_TALL_90", "BUNGEE_TALL_80", "BUNGEE_TALL_70",
        }
        local candidateValues = {}
        local registeredOrder = {}
        for _, key in ipairs(candidateOrder) do
            if addon.Fonts and addon.Fonts[key] then
                candidateValues[key] = (addon.FontDisplayNames and addon.FontDisplayNames[key]) or key
                table.insert(registeredOrder, key)
            end
        end

        local candLabel = scrollContent:CreateFontString(nil, "OVERLAY")
        Theme:ApplyLabelFont(candLabel, 12)
        candLabel:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 12, yOffset)
        candLabel:SetText("Candidates")
        candLabel:SetTextColor(1, 1, 1, 0.9)
        table.insert(self._debugMenuControls, candLabel)

        candDropdown = Controls:CreateDropdown({
            parent = scrollContent,
            values = candidateValues,
            order = registeredOrder,
            width = 200,
            placeholder = "Pick a font...",
            get = function()
                local htCfg = addon.DebugHealthTextGetConfig and addon.DebugHealthTextGetConfig()
                return htCfg and htCfg.face or nil
            end,
            set = function(key)
                if addon.DebugHealthTextSetFont then
                    addon.DebugHealthTextSetFont(key)
                end
                if browseRow and browseRow.Refresh then browseRow:Refresh() end
            end,
        })
        candDropdown:SetPoint("LEFT", candLabel, "LEFT", 128, 0)
        table.insert(self._debugMenuControls, candDropdown)

        yOffset = yOffset - 34

        browseRow = Controls:CreateFontSelector({
            parent = scrollContent,
            label = "Browse All Fonts",
            description = "Full registry with in-font previews. Faces picked here also apply live.",
            get = function()
                local htCfg = addon.DebugHealthTextGetConfig and addon.DebugHealthTextGetConfig()
                return htCfg and htCfg.face or "ANTON_WIDE_180"
            end,
            set = function(key)
                if addon.DebugHealthTextSetFont then
                    addon.DebugHealthTextSetFont(key)
                end
                if candDropdown and candDropdown.Refresh then candDropdown:Refresh() end
            end,
        })
        browseRow:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset)
        browseRow:SetPoint("RIGHT", scrollContent, "RIGHT", -20, 0)
        table.insert(self._debugMenuControls, browseRow)

        yOffset = yOffset - 70

        -- Value Squish: the bottom value row only, onto the current family's
        -- cap-pinned TALL bakes -- family-matched, so switching the main face
        -- re-targets the value row with no re-selection here.
        local squishLabel = scrollContent:CreateFontString(nil, "OVERLAY")
        Theme:ApplyLabelFont(squishLabel, 12)
        squishLabel:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 12, yOffset)
        squishLabel:SetText("Value Squish")
        squishLabel:SetTextColor(1, 1, 1, 0.9)
        table.insert(self._debugMenuControls, squishLabel)

        local squishDropdown = Controls:CreateDropdown({
            parent = scrollContent,
            values = {
                ["off"] = "Off (follow main face)",
                ["90"]  = "0.90 tall",
                ["80"]  = "0.80 tall",
                ["70"]  = "0.70 tall",
            },
            order = { "off", "90", "80", "70" },
            width = 200,
            placeholder = "Pick a squish...",
            get = function()
                local htCfg = addon.DebugHealthTextGetConfig and addon.DebugHealthTextGetConfig()
                return htCfg and htCfg.valSquish or nil
            end,
            set = function(key)
                if addon.DebugHealthTextSetValSquish then
                    addon.DebugHealthTextSetValSquish(key)
                end
            end,
        })
        squishDropdown:SetPoint("LEFT", squishLabel, "LEFT", 128, 0)
        table.insert(self._debugMenuControls, squishDropdown)

        yOffset = yOffset - 44

        -- Value font size: pairs with the squish dropdown -- the ratio hunt is
        -- point size vs squish level, so both knobs live together. Half-point
        -- steps; the setter snaps to 0.5.
        local valSizeSlider = Controls:CreateSlider({
            parent = scrollContent,
            label = "Value Font Size",
            description = "Point size of the bottom value row, in 0.5 steps. Works with any squish level, including Off.",
            min = 6,
            max = 30,
            step = 0.5,
            precision = 1,
            width = 140,
            get = function()
                local htCfg = addon.DebugHealthTextGetConfig and addon.DebugHealthTextGetConfig()
                return htCfg and htCfg.valSize or 13
            end,
            set = function(val)
                if addon.DebugHealthTextSetValSize then
                    addon.DebugHealthTextSetValSize(val)
                end
            end,
        })
        if valSizeSlider then
            valSizeSlider:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset)
            valSizeSlider:SetPoint("RIGHT", scrollContent, "RIGHT", -20, 0)
            table.insert(self._debugMenuControls, valSizeSlider)
            yOffset = yOffset - 74
        end

        -- Name position: the shipped-menu representation. X is 'nameoffset'
        -- (distance from the numbers' frame edge to the name's near edge --
        -- bigger pushes the name away from the number column); Y is 'namey'
        -- (nudge from the row-gap midline the name centers on, + = up).
        local namePosSlider = Controls:CreateDualSlider({
            parent = scrollContent,
            label = "Name Position",
            sliderA = {
                axisLabel = "X",
                min = 0,
                max = 250,
                step = 1,
                get = function()
                    local htCfg = addon.DebugHealthTextGetConfig and addon.DebugHealthTextGetConfig()
                    return htCfg and htCfg.nameOffset or 100
                end,
                set = function(val)
                    if addon.DebugHealthTextSetNameOffset then
                        addon.DebugHealthTextSetNameOffset(val)
                    end
                end,
            },
            sliderB = {
                axisLabel = "Y",
                min = -60,
                max = 60,
                step = 1,
                get = function()
                    local htCfg = addon.DebugHealthTextGetConfig and addon.DebugHealthTextGetConfig()
                    return htCfg and htCfg.nameY or 0
                end,
                set = function(val)
                    if addon.DebugHealthTextSetNameY then
                        addon.DebugHealthTextSetNameY(val)
                    end
                end,
            },
        })
        if namePosSlider then
            namePosSlider:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset)
            namePosSlider:SetPoint("RIGHT", scrollContent, "RIGHT", -20, 0)
            table.insert(self._debugMenuControls, namePosSlider)
            yOffset = yOffset - 62
        end

        -- Row gap slider: front-end for 'gap'. 0.1 px steps -- under a
        -- fractional UI scale sub-px anchor offsets land on different physical
        -- pixels, so the fine steps are the real tuning knob, not decoration.

        local rowGapSlider = Controls:CreateSlider({
            parent = scrollContent,
            label = "Number Row Gap",
            description = "Vertical gap between the percent row and the value row, in 0.1 px steps. Negative overlaps the rows.",
            min = -10,
            max = 10,
            step = 0.1,
            precision = 1,
            width = 140,
            get = function()
                local htCfg = addon.DebugHealthTextGetConfig and addon.DebugHealthTextGetConfig()
                return htCfg and htCfg.gap or 1
            end,
            set = function(val)
                if addon.DebugHealthTextSetGap then
                    addon.DebugHealthTextSetGap(val)
                end
            end,
        })
        if rowGapSlider then
            rowGapSlider:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset)
            rowGapSlider:SetPoint("RIGHT", scrollContent, "RIGHT", -20, 0)
            table.insert(self._debugMenuControls, rowGapSlider)
            yOffset = yOffset - 74
        end

        local htToggleBtn = Controls:CreateButton({
            parent = scrollContent,
            text = "Show / Hide Test Frame",
            width = 220,
            onClick = function()
                if addon.DebugHealthTextToggle then
                    addon.DebugHealthTextToggle()
                end
            end,
        })
        if htToggleBtn then
            htToggleBtn:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset)
            table.insert(self._debugMenuControls, htToggleBtn)
            yOffset = yOffset - 34
        end
    end

    yOffset = yOffset - 20

    scrollContent:SetHeight(math.abs(yOffset) + 20)
end)
