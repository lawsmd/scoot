-- extraabilities.lua - Extra Abilities (Zone Ability + Extra Action Button) component
local addonName, addon = ...

local Component = addon.ComponentPrototype
local Util = addon.ComponentsUtil

-- State for alpha management
local extraAbilityState = {}
local alphaHooked = {}
local settingAlpha = {}
local buttonsHooked = {}

-- Overlay frames anchored to spell buttons (avoids tainting spell-casting buttons
-- with CreateTexture/border ops that trigger secret value errors in combat)
local buttonOverlays = setmetatable({}, { __mode = "k" })

local function getButtonOverlay(btn)
    if buttonOverlays[btn] then return buttonOverlays[btn] end
    local overlay = CreateFrame("Frame", nil, UIParent)
    overlay:SetFrameStrata("MEDIUM")
    overlay:SetFrameLevel(btn:GetFrameLevel() + 5)
    overlay:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    overlay:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    overlay:EnableMouse(false)
    buttonOverlays[btn] = overlay
    return overlay
end

local function getContainerState()
    if not extraAbilityState.container then
        extraAbilityState.container = {}
    end
    return extraAbilityState.container
end

local function setContainerDesiredAlpha(container, alpha)
    if not container or not container.SetAlpha then return end
    local state = getContainerState()
    state.desiredAlpha = alpha
    settingAlpha[container] = true
    pcall(container.SetAlpha, container, alpha)
    settingAlpha[container] = nil
end

local function hookContainerAlpha(container)
    if not container or alphaHooked[container] then return end
    alphaHooked[container] = true
    hooksecurefunc(container, "SetAlpha", function(self, alpha)
        if settingAlpha[self] then return end
        local state = extraAbilityState.container
        if not state or state.desiredAlpha == nil then return end
        if math.abs(alpha - state.desiredAlpha) > 0.001 then
            settingAlpha[self] = true
            pcall(self.SetAlpha, self, state.desiredAlpha)
            settingAlpha[self] = nil
        end
    end)
end

-- Enumerate all extra ability buttons (Zone Ability + Extra Action Button)
local function enumerateExtraAbilityButtons()
    local buttons = {}

    -- ZoneAbilityFrame buttons
    local zaf = _G.ZoneAbilityFrame
    if zaf and zaf.SpellButtonContainer and zaf.SpellButtonContainer.EnumerateActive then
        for btn in zaf.SpellButtonContainer:EnumerateActive() do
            if btn then
                table.insert(buttons, btn)
            end
        end
    end

    -- ExtraActionButton
    local eab = _G.ExtraActionBarFrame
    if eab and eab.button then
        table.insert(buttons, eab.button)
    end

    return buttons
end

-- Hover detection via polling (avoids HookScript taint on Blizzard frames)
local hoverTicker = nil
local function startHoverDetection(container)
    if hoverTicker then return end
    hoverTicker = C_Timer.NewTicker(0.15, function()
        if not container or not container:IsShown() then return end
        local state = getContainerState()
        if state.desiredAlpha == nil then return end

        local isOver = false
        for _, btn in ipairs(enumerateExtraAbilityButtons()) do
            if btn:IsMouseOver() then isOver = true; break end
        end

        if isOver and not state.isMousedOver then
            state.isMousedOver = true
            setContainerDesiredAlpha(container, 1)
        elseif not isOver and state.isMousedOver then
            state.isMousedOver = false
            setContainerDesiredAlpha(container, state.baseOpacity or 1)
        end
    end)
end

-- Apply styling to extra ability buttons
local function ApplyExtraAbilitiesStyling(self)
    local container = _G.ExtraAbilityContainer
    if not container then return end

    -- Apply scale to container
    local scale = tonumber(self.db.scale) or 100
    if scale < 25 then scale = 25 elseif scale > 150 then scale = 150 end
    local scaleValue = scale / 100
    -- SetScale is protected on Edit Mode-managed frames during combat
    if not InCombatLockdown() then
        pcall(container.SetScale, container, scaleValue)
    end

    -- Apply opacity
    local baseOp = tonumber(self.db.barOpacity) or 100
    if baseOp < 1 then baseOp = 1 elseif baseOp > 100 then baseOp = 100 end

    local oocOp = tonumber(self.db.barOpacityOutOfCombat) or baseOp
    if oocOp < 1 then oocOp = 1 elseif oocOp > 100 then oocOp = 100 end

    local tgtOp = tonumber(self.db.barOpacityWithTarget) or baseOp
    if tgtOp < 1 then tgtOp = 1 elseif tgtOp > 100 then tgtOp = 100 end

    local hasTarget = (UnitExists and UnitExists("target")) and true or false
    local appliedOp = hasTarget and tgtOp or (Util.PlayerInCombat() and baseOp or oocOp)

    hookContainerAlpha(container)
    local state = getContainerState()
    state.component = self
    state.baseOpacity = appliedOp / 100

    -- Start hover detection ticker (replaces HookScript on Blizzard buttons)
    startHoverDetection(container)

    -- Set initial alpha based on current mouse position
    local isOver = false
    for _, btn in ipairs(enumerateExtraAbilityButtons()) do
        if btn:IsMouseOver() then isOver = true; break end
    end
    if isOver then
        state.isMousedOver = true
        setContainerDesiredAlpha(container, 1)
    else
        state.isMousedOver = false
        setContainerDesiredAlpha(container, appliedOp / 100)
    end

    -- Get settings
    local hideBlizzardArt = self.db and self.db.hideBlizzardArt

    -- Migration: convert old toggle settings to unified borderStyle
    if self.db then
        if self.db.borderDisableAll then
            self.db.borderStyle = "hidden"
            self.db.borderDisableAll = nil
            self.db.borderEnable = nil
        elseif self.db.borderEnable then
            if not self.db.borderStyle or self.db.borderStyle == "off" then
                self.db.borderStyle = "square"
            end
            self.db.borderEnable = nil
        elseif self.db.borderEnable == false then
            self.db.borderStyle = self.db.borderStyle or "off"
            self.db.borderEnable = nil
            self.db.borderDisableAll = nil
        end
    end

    local styleKey = (self.db and self.db.borderStyle) or "off"
    if styleKey == "none" then styleKey = "square"; if self.db then self.db.borderStyle = styleKey end end
    local thickness = tonumber(self.db and self.db.borderThickness) or 1
    if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
    local borderInsetH = tonumber(self.db and self.db.borderInsetH) or tonumber(self.db and self.db.borderInset) or 0
    local borderInsetV = tonumber(self.db and self.db.borderInsetV) or tonumber(self.db and self.db.borderInset) or 0
    local tintEnabled = self.db and self.db.borderTintEnable and type(self.db.borderTintColor) == "table"
    local tintColor
    if tintEnabled then
        local c = self.db.borderTintColor or {1,1,1,1}
        tintColor = { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
    end

    -- Text settings
    local chargesCfg = self.db and self.db.textCharges or { size = 16, style = "OUTLINE", color = {1,1,1,1}, offset = { x = 0, y = 0 }, fontFace = "FRIZQT__" }
    local cooldownCfg = self.db and self.db.textCooldown or { size = 16, style = "OUTLINE", color = {1,1,1,1}, offset = { x = 0, y = 0 }, fontFace = "FRIZQT__" }
    local defaultFace = (select(1, GameFontNormal:GetFont()))

    local function applyTextToFontString(fs, cfg, justify, anchorPoint, relTo)
        if not fs or not fs.SetFont then return end
        local size = tonumber(cfg.size) or 14
        local style = cfg.style or "OUTLINE"
        local face = addon.ResolveFontFace and addon.ResolveFontFace(cfg.fontFace or "FRIZQT__") or defaultFace
        pcall(fs.SetDrawLayer, fs, "OVERLAY", 10)
        if addon.ApplyFontStyle then addon.ApplyFontStyle(fs, face, size, style) else fs:SetFont(face, size, style) end
        local c = cfg.color or {1,1,1,1}
        if fs.SetTextColor then pcall(fs.SetTextColor, fs, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1) end
        if justify and fs.SetJustifyH then pcall(fs.SetJustifyH, fs, justify) end
        local ox = (cfg.offset and cfg.offset.x) or 0
        local oy = (cfg.offset and cfg.offset.y) or 0
        if (ox ~= 0 or oy ~= 0) and fs.ClearAllPoints and fs.SetPoint then
            fs:ClearAllPoints()
            fs:SetPoint(anchorPoint or "CENTER", relTo or fs:GetParent(), anchorPoint or "CENTER", ox, oy)
        end
    end

    -- Hide/show ZoneAbilityFrame.Style (the decorative frame around zone abilities)
    local zaf = _G.ZoneAbilityFrame
    if zaf and zaf.Style then
        if hideBlizzardArt then
            pcall(zaf.Style.SetAlpha, zaf.Style, 0)
        else
            pcall(zaf.Style.SetAlpha, zaf.Style, 1)
        end
    end

    -- Hide all existing overlays first (cleanup-first pattern)
    -- Overlays are parented to UIParent so they don't auto-hide with Blizzard buttons
    for btn, overlay in pairs(buttonOverlays) do
        overlay:Hide()
    end

    -- Style each button
    local buttons = enumerateExtraAbilityButtons()
    for _, btn in ipairs(buttons) do
        -- Hide Blizzard art
        if hideBlizzardArt then
            -- Hide NormalTexture on buttons
            if btn.GetNormalTexture then
                local nt = btn:GetNormalTexture()
                if nt and nt.SetAlpha then pcall(nt.SetAlpha, nt, 0) end
            end
            -- Hide style texture on ExtraActionButton
            if btn.style then
                pcall(btn.style.SetAlpha, btn.style, 0)
            end
        else
            -- Restore
            if btn.GetNormalTexture then
                local nt = btn:GetNormalTexture()
                if nt and nt.SetAlpha then pcall(nt.SetAlpha, nt, 1) end
            end
            if btn.style then
                pcall(btn.style.SetAlpha, btn.style, 1)
            end
        end

        -- Border handling (applied to addon-owned overlay to avoid tainting spell buttons)
        local btnVisible = btn.IsVisible and btn:IsVisible()
        if styleKey == "off" or styleKey == "hidden" or not btnVisible then
            local overlay = buttonOverlays[btn]
            if overlay then
                overlay:Hide()
                if addon.Borders and addon.Borders.HideAll then
                    addon.Borders.HideAll(overlay)
                end
            end
        else
            local overlay = getButtonOverlay(btn)
            overlay:Show()
            if styleKey == "square" and addon.Borders and addon.Borders.ApplySquare then
                if addon.Borders.HideAll then addon.Borders.HideAll(overlay) end
                local col = tintEnabled and tintColor or {0, 0, 0, 1}
                addon.Borders.ApplySquare(overlay, {
                    size = thickness,
                    color = col,
                    layer = "OVERLAY",
                    layerSublevel = 7,
                    expandX = 0 - borderInsetH,
                    expandY = 0 - borderInsetV,
                    expandTop = 1 - borderInsetV,
                    expandBottom = -1 - borderInsetV,
                })
            else
                addon.ApplyIconBorderStyle(overlay, styleKey, {
                    thickness = thickness,
                    color = tintColor,
                    tintEnabled = tintEnabled,
                    db = self.db,
                    thicknessKey = "borderThickness",
                    tintColorKey = "borderTintColor",
                    insetH = borderInsetH,
                    insetV = borderInsetV,
                    defaultThickness = (self.settings and self.settings.borderThickness and self.settings.borderThickness.default) or 1,
                })
            end
        end

        -- Text styling - Charges (Count)
        if btn.Count then
            applyTextToFontString(btn.Count, chargesCfg, "CENTER", "BOTTOMRIGHT", btn)
        end

        -- Text styling - Cooldown
        local cdOwner = btn.cooldown or btn.Cooldown or btn.CooldownFrame or nil
        local cdText
        if cdOwner then
            local function findFS(obj)
                if not obj then return nil end
                if obj.GetObjectType and obj:GetObjectType() == "FontString" then return obj end
                if obj.GetRegions then
                    local n = (obj.GetNumRegions and obj:GetNumRegions(obj)) or 0
                    for i = 1, n do
                        local r = select(i, obj:GetRegions())
                        if r and r.GetObjectType and r:GetObjectType() == "FontString" then return r end
                    end
                end
            end
            cdText = findFS(cdOwner)
        end
        if cdText then
            applyTextToFontString(cdText, cooldownCfg, "CENTER", "CENTER", btn)
        end
    end
end

-- Install hooks for dynamic button creation
local function InstallDynamicHooks(comp)
    -- Hook ZoneAbilityFrame button creation
    local zaf = _G.ZoneAbilityFrame
    if zaf and zaf.SpellButtonContainer and zaf.SpellButtonContainer.SetContents then
        if not buttonsHooked.zoneAbility then
            buttonsHooked.zoneAbility = true
            hooksecurefunc(zaf.SpellButtonContainer, "SetContents", function()
                C_Timer.After(0, function()
                    if comp and comp.ApplyStyling then
                        comp:ApplyStyling()
                    end
                end)
            end)
        end
    end

    -- Hook container Hide to immediately hide overlays when Extra Abilities disappear
    local eac = _G.ExtraAbilityContainer
    if eac and not buttonsHooked.containerHide then
        buttonsHooked.containerHide = true
        hooksecurefunc(eac, "Hide", function()
            for btn, overlay in pairs(buttonOverlays) do
                overlay:Hide()
                if addon.Borders and addon.Borders.HideAll then
                    addon.Borders.HideAll(overlay)
                end
            end
        end)
    end

    -- Hook ExtraActionBar updates
    if not buttonsHooked.extraAction and _G.ExtraActionBar_Update then
        buttonsHooked.extraAction = true
        hooksecurefunc("ExtraActionBar_Update", function()
            C_Timer.After(0, function()
                if comp and comp.ApplyStyling then
                    comp:ApplyStyling()
                end
            end)
        end)
    end
end

addon:RegisterComponentInitializer(function(self)
    local extraAbilities = Component:New({
        id = "extraAbilities",
        name = "Extra Abilities",
        frameName = "ExtraAbilityContainer",
        settings = {
            -- Sizing
            scale = { type = "addon", default = 100, ui = {
                label = "Scale", widget = "slider", min = 25, max = 150, step = 5, section = "Sizing", order = 1
            }},
            -- Text - Charges
            textCharges = { type = "addon", default = { size = 16, style = "OUTLINE", color = {1,1,1,1}, offset = { x = 0, y = 0 }, fontFace = "FRIZQT__" }, ui = { hidden = true }},
            -- Text - Cooldown
            textCooldown = { type = "addon", default = { size = 16, style = "OUTLINE", color = {1,1,1,1}, offset = { x = 0, y = 0 }, fontFace = "FRIZQT__" }, ui = { hidden = true }},
            -- Border
            borderStyle = { type = "addon", default = "off", ui = {
                label = "Border Style", widget = "dropdown", section = "Border", order = 1,
                optionsProvider = function()
                    if addon.BuildIconBorderOptionsContainer then
                        return addon.BuildIconBorderOptionsContainer()
                    end
                    return {}
                end
            }},
            borderTintEnable = { type = "addon", default = false, ui = {
                label = "Border Tint", widget = "checkbox", section = "Border", order = 2
            }},
            borderTintColor = { type = "addon", default = {1,1,1,1}, ui = {
                label = "Tint Color", widget = "color", section = "Border", order = 3
            }},
            borderThickness = { type = "addon", default = 1, ui = {
                label = "Border Thickness", widget = "slider", min = 1, max = 8, step = 0.5, section = "Border", order = 4
            }},
            borderInset = { type = "addon", default = 0 },
            borderInsetH = { type = "addon", default = 0 },
            borderInsetV = { type = "addon", default = 0 },
            -- Visibility
            hideBlizzardArt = { type = "addon", default = false, ui = {
                label = "Hide Blizzard Icon Art", widget = "checkbox", section = "Misc", order = 1
            }},
            barOpacity = { type = "addon", default = 100, ui = {
                label = "Opacity in Combat", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 2
            }},
            barOpacityOutOfCombat = { type = "addon", default = 100, ui = {
                label = "Opacity Out of Combat", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 3
            }},
            barOpacityWithTarget = { type = "addon", default = 100, ui = {
                label = "Opacity With Target", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 4
            }},
        },
        ApplyStyling = ApplyExtraAbilitiesStyling,
        OnInitialize = function(comp)
            InstallDynamicHooks(comp)
        end,
    })

    self:RegisterComponent(extraAbilities)

    -- Also install hooks after PLAYER_ENTERING_WORLD since frames may not exist initially
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:SetScript("OnEvent", function()
        C_Timer.After(1, function()
            InstallDynamicHooks(extraAbilities)
        end)
    end)
end)
