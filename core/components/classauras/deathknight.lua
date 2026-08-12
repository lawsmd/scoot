-- classauras/deathknight.lua - Death Knight class aura definitions
local addonName, addon = ...

local CA = addon.ClassAuras

--------------------------------------------------------------------------------
-- Unholy DoTs: shared state and helpers
--------------------------------------------------------------------------------

local VIRULENT_PLAGUE_ID = 191587
local DREAD_PLAGUE_ID    = 1240996
local EXCLAMATION_PATH   = "Interface\\AddOns\\Scoot\\media\\animations\\Exclamation"
local WHITE8X8           = "Interface\\BUTTONS\\WHITE8X8"

local DOT_COLORS = {
    virulentPlague = {0.0, 0.8, 0.2, 1.0},
    dreadPlague    = {0.8, 0.1, 0.1, 1.0},
}

-- Per-icon visual state (indexed by auraId)
local iconState = {}  -- [auraId] = { engineLayers, engineActive }

-- Alert suppression: prevent exclamation for 2s after combat start or target change
local alertSuppressed = false

-- Forward declarations
local EnsureEngineLayers, UpdateDotAlertLayers

--------------------------------------------------------------------------------
-- Icon construction helpers
--------------------------------------------------------------------------------

local function CreateSquareBorders(parent, size)
    local edges = {}
    local thickness = 2
    local r, g, b, a = 0, 0, 0, 1

    edges.Top = parent:CreateTexture(nil, "OVERLAY", nil, 1)
    edges.Top:SetColorTexture(r, g, b, a)
    edges.Top:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    edges.Top:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    edges.Top:SetHeight(thickness)

    edges.Bottom = parent:CreateTexture(nil, "OVERLAY", nil, 1)
    edges.Bottom:SetColorTexture(r, g, b, a)
    edges.Bottom:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    edges.Bottom:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    edges.Bottom:SetHeight(thickness)

    edges.Left = parent:CreateTexture(nil, "OVERLAY", nil, 1)
    edges.Left:SetColorTexture(r, g, b, a)
    edges.Left:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -thickness)
    edges.Left:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, thickness)
    edges.Left:SetWidth(thickness)

    edges.Right = parent:CreateTexture(nil, "OVERLAY", nil, 1)
    edges.Right:SetColorTexture(r, g, b, a)
    edges.Right:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -thickness)
    edges.Right:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, thickness)
    edges.Right:SetWidth(thickness)

    return edges
end

local function ShowBorders(edges)
    if not edges then return end
    for _, tex in pairs(edges) do tex:Show() end
end

local function HideBorders(edges)
    if not edges then return end
    for _, tex in pairs(edges) do tex:Hide() end
end

--------------------------------------------------------------------------------
-- Lifecycle callbacks (called by core.lua hooks)
--------------------------------------------------------------------------------

local function OnContainerCreated(auraId, state)
    -- Always-built Scoot-frame layers: inactive art + exclamation reveal.
    EnsureEngineLayers(auraId, state)
end

local function GetDotContext(auraId)
    local auraDef = CA._registry[auraId]
    if not auraDef then return nil, nil, nil end
    local primaryId = auraDef.anchorTo or auraId
    local comp = addon.Components and addon.Components["classAura_" .. primaryId]
    local db = comp and comp.db
    if not db then
        comp = addon.Components and addon.Components["classAura_" .. auraId]
        db = comp and comp.db
    end
    local spellId = auraDef.auraSpellId
    local color = DOT_COLORS[auraId] or {1, 1, 1, 1}
    return db, spellId, color
end

--------------------------------------------------------------------------------
-- Engine path (12.1 slot engine): layered reveal
--------------------------------------------------------------------------------
-- The engine shows/hides the button on aura presence, and that state is
-- secret, so "missing" visuals cannot be event-driven. Instead they live on
-- the Scoot frame BELOW the AuraContainer: the button's active art covers
-- them while the aura is present, and the engine hiding the button reveals
-- them. Consequences: the exclamation only works at the ON position (offset
-- positions would peek out beside a present aura) and is clipped to the icon
-- rect; larger alert sizes are cropped.

EnsureEngineLayers = function(auraId, state)
    local is = iconState[auraId]
    if is and is.engineLayers then return is end
    is = is or {}
    iconState[auraId] = is

    local container = state.container

    -- Inactive ("missing") art: below the AuraContainer (level +5)
    local inactive = CreateFrame("Frame", nil, container)
    inactive:SetAllPoints(container)
    inactive:SetFrameLevel(container:GetFrameLevel() + 1)
    local inactiveTex = inactive:CreateTexture(nil, "ARTWORK")
    inactiveTex:SetAllPoints(inactive)
    local inactiveEdges = CreateSquareBorders(inactive, 16)
    HideBorders(inactiveEdges)
    inactive:Hide()

    -- Exclamation reveal: above the inactive art, still below the container
    local excHolder = CreateFrame("Frame", nil, container)
    excHolder:SetAllPoints(container)
    excHolder:SetFrameLevel(container:GetFrameLevel() + 3)
    excHolder:SetClipsChildren(true)
    local excTex = excHolder:CreateTexture(nil, "OVERLAY")
    excTex:SetTexture(EXCLAMATION_PATH)
    excTex:SetPoint("CENTER", excHolder, "CENTER", 0, 0)
    excTex:SetSize(16, 16)
    local excAnim = excTex:CreateAnimationGroup()
    excAnim:SetLooping("BOUNCE")
    local fade = excAnim:CreateAnimation("Alpha")
    fade:SetFromAlpha(1.0)
    fade:SetToAlpha(0.0)
    fade:SetDuration(0.5)
    excHolder:Hide()

    is.engineLayers = {
        inactive = inactive,
        inactiveTex = inactiveTex,
        inactiveEdges = inactiveEdges,
        excHolder = excHolder,
        excTex = excTex,
        excAnim = excAnim,
    }
    return is
end

-- Under-button extras, created inside the slot's initializeFrame: the swipe
-- cooldown (engine-driven via SetDurationCooldown) and square-mode edges.
local function DotEngineWire(auraDef, state, entry, button)
    local is = iconState[auraDef.id] or {}
    iconState[auraDef.id] = is

    local swipeFrame = CreateFrame("Frame", nil, button)
    swipeFrame:SetAllPoints(button)
    swipeFrame:SetFrameLevel(button:GetFrameLevel() + 2)
    local cooldown = CreateFrame("Cooldown", nil, swipeFrame, "CooldownFrameTemplate")
    cooldown:SetAllPoints(swipeFrame)
    cooldown:SetReverse(true)
    cooldown:SetDrawBling(false)
    cooldown:SetDrawEdge(false)
    cooldown:SetHideCountdownNumbers(true)
    cooldown:SetSwipeColor(0, 0, 0, 1.0)

    local edges = CreateSquareBorders(button, 16)
    HideBorders(edges)

    is.engineActive = { swipeFrame = swipeFrame, cooldown = cooldown, edges = edges }
end

-- Plain-state visibility for the reveal layers. Everything read here is
-- always readable: db settings, InCombatLockdown, UnitExists, own flags.
UpdateDotAlertLayers = function()
    if CA._isEditModeActive() then return end
    for _, auraId in ipairs({ "virulentPlague", "dreadPlague" }) do
        local auraDef = CA._registry[auraId]
        local state = CA._activeAuras[auraId]
        local is = iconState[auraId]
        local eng = is and is.engineLayers
        if auraDef and auraDef.engineDriven and state and eng then
            local db = GetDotContext(auraId)
            local enabled = db and db.enabled
            local showLayers = enabled and UnitExists("target")
            eng.inactive:SetShown(showLayers and true or false)
            local excEnabled = db and (db.exclamationEnable ~= false)
            if showLayers and excEnabled and InCombatLockdown() and not alertSuppressed then
                eng.excHolder:Show()
                eng.excAnim:Play()
            else
                eng.excAnim:Stop()
                eng.excHolder:Hide()
            end
        end
    end
end

-- Tier 2 apply hook (runs inside the engine gate, button tree touchable).
local function DotEngineApply(auraDef, state, entry)
    local auraId = auraDef.id
    local is = EnsureEngineLayers(auraId, state)
    local eng = is.engineLayers
    local act = is.engineActive
    local db, spellId, color = GetDotContext(auraId)
    local isSquare = (db and db.dotIconStyle) or false

    -- Active texture under the button (ApplyIconMode skips customIconHandling,
    -- and BindForMode cleared the engine icon binding, so this paint sticks)
    local texElem
    for _, elem in ipairs(state.elements or {}) do
        if elem.type == "texture" then texElem = elem; break end
    end
    if texElem then
        if isSquare then
            texElem.widget:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
            texElem.widget:SetDesaturated(false)
        else
            local ok, tex = pcall(C_Spell.GetSpellTexture, spellId)
            if ok and tex and not issecretvalue(tex) then
                texElem.widget:SetTexture(tex)
                texElem.widget:SetDesaturated(false)
            end
        end
        texElem.widget:Show()
    end

    if act then
        if isSquare then ShowBorders(act.edges) else HideBorders(act.edges) end
        local CallBinding = CA.Engine and CA.Engine._CallBinding
        if CallBinding and entry and entry.button then
            if db and db.dotSwipeEnable then
                if isSquare then act.cooldown:SetSwipeTexture(WHITE8X8) end
                act.cooldown:SetSwipeColor(0, 0, 0, 1.0)
                CallBinding(auraDef, entry.button, "SetDurationCooldown", act.cooldown)
            else
                CallBinding(auraDef, entry.button, "ClearDurationCooldown")
                act.cooldown:Clear()
            end
        end
    end

    -- Inactive layer on the Scoot frame
    if isSquare then
        eng.inactiveTex:SetColorTexture(0.15, 0.15, 0.15, 1.0)
        eng.inactiveTex:SetDesaturated(false)
        ShowBorders(eng.inactiveEdges)
    else
        local ok, tex = pcall(C_Spell.GetSpellTexture, spellId)
        if ok and tex and not issecretvalue(tex) then
            eng.inactiveTex:SetTexture(tex)
            eng.inactiveTex:SetDesaturated(true)
        end
        HideBorders(eng.inactiveEdges)
    end

    local excSize = tonumber(db and db.exclamationSize) or 16
    eng.excTex:SetSize(excSize, excSize)

    UpdateDotAlertLayers()
end

-- Edit Mode preview: static layers through the always-built reveal art
-- (the engine button cannot fake an aura).
local function OnEditModeEnter(auraId, state)
    local is = iconState[auraId]
    local eng = is and is.engineLayers
    if eng then
        eng.inactive:Show()
        eng.excAnim:Stop()
        eng.excTex:SetAlpha(1.0)
        eng.excHolder:Show()
    end
end

local function OnEditModeExit(auraId, state)
    local is = iconState[auraId]
    local eng = is and is.engineLayers
    if eng then
        eng.excAnim:Stop()
        eng.excHolder:Hide()
    end
    UpdateDotAlertLayers()
end

--------------------------------------------------------------------------------
-- Full styling pass (called from customRenderer's set handlers and init)
--------------------------------------------------------------------------------

-- Re-apply styling for both VP and DP (Tier 1 inline + gated/queued engine apply).
local function RefreshBothDots()
    local vp = CA._registry["virulentPlague"]
    if vp then CA._ApplyStyling(vp) end
    local dp = CA._registry["dreadPlague"]
    if dp then CA._ApplyStyling(dp) end
end

--------------------------------------------------------------------------------
-- Custom Settings Renderer for Virulent Plague (controls both dots)
--------------------------------------------------------------------------------

local function DotCustomRenderer(contentFrame, inner, h, getSetting, componentId, builder)
    -- Enable toggle
    inner:AddToggle({
        key = "enabled",
        label = "Enable Unholy DoTs Tracker",
        description = "Track Virulent Plague and Dread Plague on your target with dual icons, cooldown swipes, and missing-debuff alerts.",
        emphasized = true,
        get = function() return getSetting("enabled") or false end,
        set = function(val)
            h.setAndApply("enabled", val)
            -- Sync DP enable state; RefreshBothDots restyles both dots
            local dpComp = addon.Components and addon.Components["classAura_dreadPlague"]
            if dpComp and dpComp.db then
                dpComp.db.enabled = val
            end
            RefreshBothDots()
            UpdateDotAlertLayers()
        end,
    })

    -- Tabbed section
    local tabs = {}
    local buildContent = {}

    -- Tab 1: Icons
    table.insert(tabs, { key = "icons", label = "Icons" })
    buildContent.icons = function(tabContent, tabBuilder)
        tabBuilder:AddToggle({
            label = "Squares",
            description = "Show colored squares instead of spell icons.",
            get = function() return getSetting("dotIconStyle") or false end,
            set = function(v)
                h.setAndApply("dotIconStyle", v)
                RefreshBothDots()
                builder:DeferredRefreshAll()
            end,
        })

        tabBuilder:AddToggle({
            label = "Cooldown Swipe",
            description = "Show a cooldown swipe animation over the icon as the debuff expires.",
            get = function() return getSetting("dotSwipeEnable") or false end,
            set = function(v)
                h.setAndApply("dotSwipeEnable", v)
                RefreshBothDots()
            end,
        })

        tabBuilder:Finalize()
    end

    -- Tab 2: Layout
    table.insert(tabs, { key = "layout", label = "Layout" })
    buildContent.layout = function(tabContent, tabBuilder)
        tabBuilder:AddSelector({
            label = "Orientation",
            values = { horizontal = "Horizontal", vertical = "Vertical" },
            order = { "horizontal", "vertical" },
            get = function() return getSetting("dotOrientation") or "horizontal" end,
            set = function(v)
                h.setAndApply("dotOrientation", v)
                -- Re-apply anchor linkage
                local dpAura = CA._registry["dreadPlague"]
                if dpAura then
                    local dpState = CA._activeAuras["dreadPlague"]
                    if dpState then
                        dpState.container:ClearAllPoints()
                        local padding = tonumber(getSetting("dotPadding")) or 4
                        local vpState = CA._activeAuras["virulentPlague"]
                        if vpState then
                            if v == "vertical" then
                                dpState.container:SetPoint("BOTTOM", vpState.container, "TOP", 0, padding)
                            else
                                dpState.container:SetPoint("RIGHT", vpState.container, "LEFT", -padding, 0)
                            end
                        end
                    end
                end
            end,
        })

        tabBuilder:AddSlider({
            label = "Padding",
            description = "Gap between the two icons.",
            min = 0, max = 20, step = 1,
            get = function() return getSetting("dotPadding") or 4 end,
            set = function(v)
                h.setAndApply("dotPadding", v)
                -- Re-apply anchor linkage
                local dpAura = CA._registry["dreadPlague"]
                if dpAura then
                    local dpState = CA._activeAuras["dreadPlague"]
                    if dpState then
                        dpState.container:ClearAllPoints()
                        local orientation = getSetting("dotOrientation") or "horizontal"
                        local vpState = CA._activeAuras["virulentPlague"]
                        if vpState then
                            if orientation == "vertical" then
                                dpState.container:SetPoint("BOTTOM", vpState.container, "TOP", 0, v)
                            else
                                dpState.container:SetPoint("RIGHT", vpState.container, "LEFT", -v, 0)
                            end
                        end
                    end
                end
            end,
            minLabel = "0", maxLabel = "20",
        })

        tabBuilder:Finalize()
    end

    -- Tab 3: Alert
    table.insert(tabs, { key = "alert", label = "Alert" })
    buildContent.alert = function(tabContent, tabBuilder)
        tabBuilder:AddToggle({
            label = "Exclamation Alert",
            description = "Show a blinking exclamation mark when a DoT is missing from the target.",
            get = function() return getSetting("exclamationEnable") ~= false end,
            set = function(val)
                h.setAndApply("exclamationEnable", val)
                RefreshBothDots()
            end,
        })

        tabBuilder:AddSelector({
            label = "Position",
            description = "Where the exclamation appears relative to each icon.",
            values = { ON = "On Icon", LEFT = "Left", RIGHT = "Right", TOP = "Top", BOTTOM = "Bottom" },
            order = { "ON", "LEFT", "RIGHT", "TOP", "BOTTOM" },
            get = function() return getSetting("exclamationPosition") or "ON" end,
            set = function(v)
                h.setAndApply("exclamationPosition", v)
                RefreshBothDots()
            end,
        })

        tabBuilder:AddSlider({
            label = "Alert Size",
            description = "Size of the exclamation mark icon.",
            min = 8, max = 48, step = 1,
            get = function() return getSetting("exclamationSize") or 16 end,
            set = function(v)
                h.setAndApply("exclamationSize", v)
                RefreshBothDots()
            end,
            minLabel = "8", maxLabel = "48",
        })

        tabBuilder:Finalize()
    end

    -- Tab 4: Sizing
    table.insert(tabs, { key = "sizing", label = "Sizing" })
    buildContent.sizing = function(tabContent, tabBuilder)
        tabBuilder:AddSlider({
            label = "Scale",
            description = "Overall scale of the aura frame (25-200%).",
            min = 25, max = 200, step = 5,
            get = function() return getSetting("scale") or 100 end,
            set = function(v)
                h.setAndApply("scale", v)
                -- Sync DP scale
                local dpComp = addon.Components and addon.Components["classAura_dreadPlague"]
                if dpComp and dpComp.db then
                    dpComp.db.scale = v
                end
                local dpAura = CA._registry["dreadPlague"]
                if dpAura then
                    local dpState = CA._activeAuras["dreadPlague"]
                    if dpState then
                        dpState.container:SetScale(math.max(v / 100, 0.25))
                    end
                end
            end,
            minLabel = "25%", maxLabel = "200%",
        })

        tabBuilder:Finalize()
    end

    -- Tab 5: Visibility
    table.insert(tabs, { key = "visibility", label = "Visibility" })
    buildContent.visibility = function(tabContent, tabBuilder)
        tabBuilder:AddDescription(
            "Priority: With Target > In Combat > Out of Combat",
            { color = {1, 0.82, 0}, fontSize = 13, topPadding = 4, bottomPadding = 2 }
        )

        tabBuilder:AddSlider({
            label = "Opacity With Target",
            min = 0, max = 100, step = 1,
            get = function() return getSetting("opacityWithTarget") or 100 end,
            set = function(v)
                h.setAndApply("opacityWithTarget", v)
                local dpComp = addon.Components and addon.Components["classAura_dreadPlague"]
                if dpComp and dpComp.db then dpComp.db.opacityWithTarget = v end
            end,
            minLabel = "Hidden", maxLabel = "100%",
        })

        tabBuilder:AddSlider({
            label = "Opacity in Combat",
            min = 0, max = 100, step = 1,
            get = function() return getSetting("opacityInCombat") or 100 end,
            set = function(v)
                h.setAndApply("opacityInCombat", v)
                local dpComp = addon.Components and addon.Components["classAura_dreadPlague"]
                if dpComp and dpComp.db then dpComp.db.opacityInCombat = v end
            end,
            minLabel = "Hidden", maxLabel = "100%",
        })

        tabBuilder:AddSlider({
            label = "Opacity Out of Combat",
            min = 0, max = 100, step = 1,
            get = function() return getSetting("opacityOutOfCombat") or 100 end,
            set = function(v)
                h.setAndApply("opacityOutOfCombat", v)
                local dpComp = addon.Components and addon.Components["classAura_dreadPlague"]
                if dpComp and dpComp.db then dpComp.db.opacityOutOfCombat = v end
            end,
            minLabel = "Hidden", maxLabel = "100%",
        })

        tabBuilder:Finalize()
    end

    inner:AddTabbedSection({
        tabs = tabs,
        componentId = componentId,
        sectionKey = "dotTabs",
        buildContent = buildContent,
    })

    inner:Finalize()
end

--------------------------------------------------------------------------------
-- Aura Registration
--------------------------------------------------------------------------------

CA.RegisterAuras("DEATHKNIGHT", {
    -- Lesser Ghoul Stacks (existing)
    {
        id = "lesserGhoulStacks",
        label = "Lesser Ghoul Stacks",
        auraSpellId = 1254252,
        cdmSpellId = 1254252,
        cdmBorrow = true,
        engineDriven = true,
        unit = "player",
        filter = "HELPFUL|PLAYER",
        enableLabel = "Enable Lesser Ghoul Stacks Tracker",
        enableDescription = "Show your Lesser Ghoul stacks as a dedicated, customizable aura.",
        editModeName = "Lesser Ghoul Stacks",
        defaultPosition = { point = "CENTER", x = 0, y = -200 },
        defaultBarColor = { 0.0, 0.8, 0.2, 1.0 },  -- unholy green
        elements = {
            { type = "text",    key = "stacks", source = "applications", baseSize = 24, justifyH = "RIGHT" },
            { type = "texture", key = "icon",   customPath = "Interface\\AddOns\\Scoot\\media\\classauras\\PixelZombie", defaultSize = { 32, 32 } },
            { type = "bar",     key = "stackBar", source = "applications", maxValue = 8, fillMode = "fill", defaultSize = { 120, 12 } },
        },
        settings = CA.DefaultSettings({
            textColor = { 0.0, 0.8, 0.2, 1.0 },
            barForegroundTint = { 0.0, 0.8, 0.2, 1.0 },
        }),
    },

    -- Virulent Plague (primary Unholy DoT)
    {
        id = "virulentPlague",
        label = "Unholy DoTs",
        auraSpellId = VIRULENT_PLAGUE_ID,
        cdmBorrow = true,
        engineDriven = true,
        engineApply = DotEngineApply,
        onEngineWire = DotEngineWire,
        unit = "target",
        filter = "HARMFUL|PLAYER",
        enableLabel = "Enable Unholy DoTs Tracker",
        enableDescription = "Track Virulent Plague and Dread Plague as dual icons with cooldown swipes and missing-debuff alerts.",
        editModeName = "Unholy DoTs",
        defaultPosition = { point = "CENTER", x = 10, y = -200 },
        elements = {
            { type = "texture", key = "icon", defaultSize = { 16, 16 } },
        },
        customIconHandling = true,
        onContainerCreated = OnContainerCreated,
        onEditModeEnter = OnEditModeEnter,
        onEditModeExit = OnEditModeExit,
        customRenderer = DotCustomRenderer,
        settings = CA.DefaultSettings({
            -- Novel settings for the dual-dot system
            dotOrientation      = { type = "addon", default = "horizontal" },
            dotPadding          = { type = "addon", default = 4 },
            dotIconStyle        = { type = "addon", default = false },
            dotSwipeEnable      = { type = "addon", default = false },
            exclamationEnable   = { type = "addon", default = true },
            exclamationPosition = { type = "addon", default = "ON" },
            exclamationSize     = { type = "addon", default = 16 },
        }),
    },

    -- Dread Plague (secondary Unholy DoT, anchored to VP)
    {
        id = "dreadPlague",
        label = "Dread Plague",
        auraSpellId = DREAD_PLAGUE_ID,
        cdmBorrow = true,
        engineDriven = true,
        engineApply = DotEngineApply,
        onEngineWire = DotEngineWire,
        unit = "target",
        filter = "HARMFUL|PLAYER",
        anchorTo = "virulentPlague",
        skipEditMode = true,
        hideFromSettings = true,
        defaultPosition = { point = "CENTER", x = -10, y = -200 },
        elements = {
            { type = "texture", key = "icon", defaultSize = { 16, 16 } },
        },
        customIconHandling = true,
        onContainerCreated = OnContainerCreated,
        onEditModeEnter = OnEditModeEnter,
        onEditModeExit = OnEditModeExit,
        settings = CA.DefaultSettings({}),
    },
})

--------------------------------------------------------------------------------
-- Deferred initialization: apply dot visuals after containers are created
--------------------------------------------------------------------------------

local function HideAllExclamations()
    for _, auraId in ipairs({"virulentPlague", "dreadPlague"}) do
        local is = iconState[auraId]
        local eng = is and is.engineLayers
        if eng then
            eng.excAnim:Stop()
            eng.excHolder:Hide()
        end
    end
end

local function SuppressAlerts()
    alertSuppressed = true
    HideAllExclamations()
    C_Timer.After(2, function()
        alertSuppressed = false
        if InCombatLockdown() then
            UpdateDotAlertLayers()
        end
    end)
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
initFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
initFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
initFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        -- Defer to run after core.lua's InitializeContainers + RebuildAll (0.5s timer)
        C_Timer.After(0.8, function()
            -- Ensure DP mirrors VP's enabled state
            local vpComp = addon.Components and addon.Components["classAura_virulentPlague"]
            local dpComp = addon.Components and addon.Components["classAura_dreadPlague"]
            if vpComp and vpComp.db and dpComp and dpComp.db then
                dpComp.db.enabled = vpComp.db.enabled
            end

            RefreshBothDots()
            UpdateDotAlertLayers()
        end)
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Entering combat: suppress alerts for 2s, then rescan
        SuppressAlerts()
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Leaving combat: immediately hide all exclamation alerts
        alertSuppressed = false
        HideAllExclamations()
        UpdateDotAlertLayers()
    elseif event == "PLAYER_TARGET_CHANGED" then
        -- New target: suppress alerts for 2s, then rescan. The alert-layer
        -- update runs after the suppression flag is set, so it only refreshes
        -- the inactive art here; the exclamation returns via the 2s timer.
        if InCombatLockdown() then
            SuppressAlerts()
        end
        UpdateDotAlertLayers()
    end
end)
