--------------------------------------------------------------------------------
-- bars/altpower.lua
-- Player alternate power bar (AlternatePowerBar) styling: hide toggle, fill and
-- background, borders on the shared Use Custom Borders switch, the percent and
-- value texts with their hide enforcement and anchor baselines, and width,
-- height, and offset scaling out of combat.
--------------------------------------------------------------------------------

local addonName, addon = ...

addon.BarsAltPower = addon.BarsAltPower or {}
local AltPower = addon.BarsAltPower

-- APB text opts for ResolveColorRGBA (classPower with the mana lighten; no dkSpec)
local apbTextColorOpts = { classPowerMode = true, lightenMana = true }

-- Font half and Zero-Touch gate opts for the APB text
local apbTextFontOpts = { size = 14 }
local apbTextCustomizationOpts = { alignment = true }

local Util = addon.ComponentsUtil
local Resolvers = addon.BarsResolvers
local Textures = addon.BarsTextures
local FS = addon.FrameState

-- Secret-value safe helpers (shared module)
local safeOffset = addon.SecretSafe.safeOffset

-- Hide-enforcement hooks (core/enforce.lua) for the alternate power texts.
-- The flags stay in FrameState and the keys read them live; Show and SetText
-- re-assert at once, SetAlpha after a stack break, all bailing in Edit Mode.
local Enforce = addon.Enforce
local ALT_POWER_TEXT_OPTS = {
    methods = { "Show", "SetAlpha", "SetText" },
    timing = { SetAlpha = "defer" },
    skipInEditMode = true,
    when = function(fs) return FS.Get(fs).altPowerTextHidden == true end,
}
local ALT_POWER_TEXT_CENTER_OPTS = {
    methods = { "SetText" },
    skipInEditMode = true,
    when = function(fs) return FS.Get(fs).altPowerTextCenterHidden == true end,
}

local resolveAlternatePowerBar = Resolvers.resolveAlternatePowerBar
local applyToBar = Textures.applyToBar
local applyBackgroundToBar = Textures.applyBackgroundToBar

local function getState(frame)
    return FS.Get(frame)
end

local function getProp(frame, key)
    local st = FS.Get(frame)
    return st and st[key] or nil
end

local function setProp(frame, key, value)
    local st = FS.Get(frame)
    if st then
        st[key] = value
    end
end

-- Anchor baselines for the percent, value, and center texts, keyed by slot.
local altPowerTextBaselines = {}

-- Helper: Apply visibility using SetAlpha (combat-safe) instead of SetShown (taint-prone).
-- Hooks Show(), SetAlpha(), and SetText() to re-enforce BOTH alpha=0 AND font styling when Blizzard updates.
local function applyAltPowerTextVisibility(fs, hidden)
    if not fs then return end
    local st = getState(fs)
    if not st then return end
    if hidden then
        if fs.SetAlpha then pcall(fs.SetAlpha, fs, 0) end
        Enforce.Install(fs, "altPowerText", ALT_POWER_TEXT_OPTS)
        st.altPowerTextHidden = true
    else
        st.altPowerTextHidden = false
        if fs.SetAlpha then pcall(fs.SetAlpha, fs, 1) end
    end
end

-- Styling (font/size/style/color/offset) using stable baseline anchors
local function ensureBaseline(fs, key, apb)
    altPowerTextBaselines[key] = altPowerTextBaselines[key] or {}
    local b = altPowerTextBaselines[key]
    if b.point == nil then
        if fs and fs.GetPoint then
            local p, relTo, rp, x, y = fs:GetPoint(1)
            -- Store raw values; sanitization happens at use time
            b.point = p
            b.relTo = relTo or (fs.GetParent and fs:GetParent()) or apb
            b.relPoint = rp
            b.x = x
            b.y = y
        else
            b.point, b.relTo, b.relPoint, b.x, b.y =
                "CENTER", (fs and fs.GetParent and fs:GetParent()) or apb, "CENTER", 0, 0
        end
    end
    return b
end

local function applyAltTextStyle(fs, styleCfg, baselineKey, apb)
    if not fs or not styleCfg then return end
    if not addon.HasTextCustomization(styleCfg, apbTextCustomizationOpts) then
        return
    end
    addon.ApplyTextFont(fs, styleCfg, apbTextFontOpts)
    -- Determine effective color based on colorMode. dkSpecMode stays off:
    -- this dialect never resolved dkSpec (APB text offers classPower only)
    local colorMode = styleCfg.colorMode or "default"
    local cr2, cg2, cb2, ca2 = addon.ResolveColorRGBA(colorMode, styleCfg.color, apbTextColorOpts)
    if fs.SetTextColor then
        pcall(fs.SetTextColor, fs, cr2, cg2, cb2, ca2)
    end

    -- Apply text alignment using two-point anchoring (matches text.lua pattern).
    -- Makes SetJustifyH work correctly without needing GetWidth() (which can
    -- trigger secret value errors on unit frame StatusBars).
    -- Check for both :right and -right patterns to handle all key formats
    local defaultAlign = "LEFT"
    if baselineKey and (baselineKey:find(":right", 1, true) or baselineKey:find("-right", 1, true)) then
        defaultAlign = "RIGHT"
    elseif baselineKey and (baselineKey:find(":center", 1, true) or baselineKey:find("-center", 1, true)) then
        defaultAlign = "CENTER"
    end
    local alignment = styleCfg.alignment or defaultAlign
    local parentBar = fs:GetParent()

    local ox = (styleCfg.offset and tonumber(styleCfg.offset.x)) or 0
    local oy = (styleCfg.offset and tonumber(styleCfg.offset.y)) or 0

    -- Get baseline Y position for vertical offset
    local b = ensureBaseline(fs, baselineKey, apb)
    local yOffset = safeOffset(b.y) + oy

    -- Use two-point anchoring to span the parent bar width.
    if fs.ClearAllPoints and fs.SetPoint and parentBar then
        fs:ClearAllPoints()
        -- Anchor both left and right edges to span the bar
        local leftPad = 2 + ox
        local rightPad = -2 + ox
        pcall(fs.SetPoint, fs, "LEFT", parentBar, "LEFT", leftPad, yOffset)
        pcall(fs.SetPoint, fs, "RIGHT", parentBar, "RIGHT", rightPad, yOffset)
    end

    if fs.SetJustifyH then
        pcall(fs.SetJustifyH, fs, alignment)
    end

    -- Force text redraw to apply alignment visually (secret-value safe)
    if fs and fs.GetText and fs.SetText then
        local ok, txt = pcall(fs.GetText, fs)
        if ok and txt and type(txt) == "string" then
            fs:SetText("")
            fs:SetText(txt)
        else
            -- Fallback: toggle alpha to force redraw without needing text value
            local okAlpha, alpha = pcall(function() return fs.GetAlpha and fs:GetAlpha() end)
            if okAlpha and alpha then
                pcall(fs.SetAlpha, fs, 0)
                pcall(fs.SetAlpha, fs, alpha)
            end
        end
    end
end

-- Called from applyForUnit (bars.lua) for the Player once its power bar has
-- resolved; inCombat is that pass's cached InCombatLockdown(). Zero-Touch: the
-- bar is styled only when db.unitFrames.Player.altPowerBar exists.
function AltPower.applyForPlayer(cfg, inCombat)
    if not (addon.UnitFrames_PlayerHasAlternatePowerBar and addon.UnitFrames_PlayerHasAlternatePowerBar()) then return end
    local apb = resolveAlternatePowerBar()
    if not apb then return end
    local acfg = rawget(cfg, "altPowerBar")
    if not acfg then return end
    local unit = "Player"

    -- Optional hide toggle
    local altHidden = (acfg.hidden == true)
    if apb.GetAlpha and getProp(apb, "origAltAlpha") == nil then
        local ok, a = pcall(apb.GetAlpha, apb)
        setProp(apb, "origAltAlpha", ok and (a or 1) or 1)
    end
    if altHidden then
        if apb.SetAlpha then pcall(apb.SetAlpha, apb, 0) end
    else
        local origAlpha = getProp(apb, "origAltAlpha")
        if origAlpha and apb.SetAlpha then
            pcall(apb.SetAlpha, apb, origAlpha)
        end
    end

    -- Foreground texture / color
    local altTexKey = acfg.texture or "default"
    local altColorMode = acfg.colorMode or "default"
    local altTint = acfg.tint
    applyToBar(apb, altTexKey, altColorMode, altTint, "player", "altpower", "player")

    -- Background texture / color / opacity
    local altBgTexKey = acfg.backgroundTexture or "default"
    local altBgColorMode = acfg.backgroundColorMode or "default"
    local altBgOpacity = acfg.backgroundOpacity or 50
    applyBackgroundToBar(apb, altBgTexKey, altBgColorMode, acfg.backgroundTint, altBgOpacity, unit, "altpower")

    -- Hide texture only (bar visible=false but text visible=true)
    local altHideTextureOnly = (acfg.hideTextureOnly == true)
    if Util and Util.SetPowerBarTextureOnlyHidden then
        Util.SetPowerBarTextureOnlyHidden(apb, altHideTextureOnly and not altHidden)
    end

    -- Clear custom borders when texture-only hide is enabled (so only text remains)
    if altHideTextureOnly and not altHidden then
        if addon.BarBorders and addon.BarBorders.ClearBarFrame then
            addon.BarBorders.ClearBarFrame(apb)
        end
        if addon.Borders and addon.Borders.HideAll then
            addon.Borders.HideAll(apb)
        end
    end

    -- Determine if all visuals should be hidden (when bar is fully hidden or texture-only hidden)
    local hideAllVisuals = altHidden or altHideTextureOnly

    -- Full power spike animations
    if Util and Util.SetFullPowerSpikeHidden then
        Util.SetFullPowerSpikeHidden(apb, acfg.hideFullSpikes == true or hideAllVisuals)
    end

    -- Power feedback flash
    if Util and Util.SetPowerFeedbackHidden then
        Util.SetPowerFeedbackHidden(apb, acfg.hideFeedback == true or hideAllVisuals)
    end

    -- Spark/glow indicator
    if Util and Util.SetPowerBarSparkHidden then
        Util.SetPowerBarSparkHidden(apb, acfg.hideSpark == true or hideAllVisuals)
    end

    -- Mana cost prediction overlay
    if Util and Util.SetManaCostPredictionHidden then
        Util.SetManaCostPredictionHidden(apb, acfg.hideManaCostPrediction == true or hideAllVisuals)
    end

    -- Custom border (shares global Use Custom Borders; Alt Power has its own style/tint/thickness/inset)
    do
        -- Global unit-frame switch; borders only draw when this is enabled.
        -- Skip borders when bar is hidden or texture-only mode (only text should remain).
        local useCustomBorders = not not cfg.useCustomBorders
        if useCustomBorders and not altHidden and not altHideTextureOnly then
            -- Style resolution: prefer Alternate Power–specific, then Power, then Health.
            local styleKey = acfg.borderStyle
                or cfg.powerBarBorderStyle
                or cfg.healthBarBorderStyle
            local hiddenEdges = acfg.borderHiddenEdges
                or cfg.powerBarBorderHiddenEdges
                or cfg.healthBarBorderHiddenEdges

            -- Tint enable: prefer Alternate Power–specific, then Power, then Health.
            local tintEnabled
            if acfg.borderTintEnable ~= nil then
                tintEnabled = not not acfg.borderTintEnable
            elseif cfg.powerBarBorderTintEnable ~= nil then
                tintEnabled = not not cfg.powerBarBorderTintEnable
            else
                tintEnabled = not not cfg.healthBarBorderTintEnable
            end

            -- Tint color: prefer Alternate Power–specific, then Power, then Health.
            local baseTint = type(acfg.borderTintColor) == "table" and acfg.borderTintColor
                or cfg.powerBarBorderTintColor
                or cfg.healthBarBorderTintColor
            local tintColor = type(baseTint) == "table" and {
                baseTint[1] or 1,
                baseTint[2] or 1,
                baseTint[3] or 1,
                baseTint[4] or 1,
            } or { 1, 1, 1, 1 }

            -- Thickness / inset: prefer Alternate Power–specific, then Power, then Health.
            local thickness = tonumber(acfg.borderThickness)
                or tonumber(cfg.powerBarBorderThickness)
                or tonumber(cfg.healthBarBorderThickness)
                or 1
            if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end

            local insetH, insetV
            if acfg.borderInsetH ~= nil or acfg.borderInsetV ~= nil then
                insetH = tonumber(acfg.borderInsetH) or tonumber(acfg.borderInset) or 0
                insetV = tonumber(acfg.borderInsetV) or tonumber(acfg.borderInset) or 0
            elseif cfg.powerBarBorderInsetH ~= nil or cfg.powerBarBorderInsetV ~= nil or cfg.powerBarBorderInset ~= nil then
                insetH = tonumber(cfg.powerBarBorderInsetH) or tonumber(cfg.powerBarBorderInset) or 0
                insetV = tonumber(cfg.powerBarBorderInsetV) or tonumber(cfg.powerBarBorderInset) or 0
            else
                insetH = tonumber(cfg.healthBarBorderInsetH) or tonumber(cfg.healthBarBorderInset) or 0
                insetV = tonumber(cfg.healthBarBorderInsetV) or tonumber(cfg.healthBarBorderInset) or 0
            end

            if styleKey == "none" or styleKey == nil then
                if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(apb) end
                if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(apb) end
            else
                local styleDef = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey)
                local color
                if tintEnabled then
                    color = tintColor
                else
                    if styleDef then
                        color = { 1, 1, 1, 1 }
                    else
                        color = { 0, 0, 0, 1 }
                    end
                end

                local handled = false
                if addon.BarBorders and addon.BarBorders.ApplyToBarFrame then
                    if addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(apb) end
                    handled = addon.BarBorders.ApplyToBarFrame(apb, styleKey, {
                        color = color,
                        thickness = thickness,
                        levelOffset = 1,
                        containerParent = (apb and apb:GetParent()) or nil,
                        insetH = insetH,
                        insetV = insetV,
                        hiddenEdges = hiddenEdges,
                    })
                end

                if not handled then
                    if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(apb) end
                    if addon.Borders and addon.Borders.ApplySquare then
                        local sqColor = tintEnabled and tintColor or { 0, 0, 0, 1 }
                        local baseY = (thickness <= 1) and 0 or 1
                        local baseX = 1
                        local expandY = baseY - insetV
                        local expandX = baseX - insetH
                        if expandX < -6 then expandX = -6 elseif expandX > 6 then expandX = 6 end
                        if expandY < -6 then expandY = -6 elseif expandY > 6 then expandY = 6 end
                        addon.Borders.ApplySquare(apb, {
                            size = thickness,
                            color = sqColor,
                            layer = "OVERLAY",
                            layerSublevel = 3,
                            expandX = expandX,
                            expandY = expandY,
                            hiddenEdges = hiddenEdges,
                        })
                    end
                end
            end
        else
            -- Global custom borders disabled: clear any previous Alternate Power border.
            if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(apb) end
            if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(apb) end
        end
    end

    -- % Text and Value Text (AlternatePowerBar.LeftText / RightText)
    do
        local leftFS = apb.LeftText
        local rightFS = apb.RightText
        -- Also resolve the center TextString (used in NUMERIC display mode)
        -- Ensures styling persists when Blizzard switches between BOTH and NUMERIC modes
        local textStringFS = apb.TextString or apb.text


        -- NOTE: SetFont/SetFontObject hooks removed for performance reasons.
        -- Font persistence is handled by the Character Frame hook in text.lua.

        -- Visibility: respect both the bar-wide hidden flag and the per-text toggles.
        local percentHidden = (acfg.percentHidden == true)
        local valueHidden = (acfg.valueHidden == true)

        applyAltPowerTextVisibility(leftFS, altHidden or percentHidden)
        applyAltPowerTextVisibility(rightFS, altHidden or valueHidden)

        -- The center TextString: SetText re-asserts the hidden state only
        Enforce.Install(textStringFS, "altPowerTextCenter", ALT_POWER_TEXT_CENTER_OPTS)


        if leftFS then
            applyAltTextStyle(leftFS, acfg.textPercent or {}, "Player:altpower-left", apb)
        end
        if rightFS then
            applyAltTextStyle(rightFS, acfg.textValue or {}, "Player:altpower-right", apb)
        end
        -- Style center TextString using Value settings (used in NUMERIC display mode)
        -- If Value text is hidden (or entire bar is hidden), also hide center text
        if textStringFS then
            local centerHidden = altHidden or valueHidden
            local tsState = getState(textStringFS)
            if centerHidden then
                if textStringFS.SetAlpha then pcall(textStringFS.SetAlpha, textStringFS, 0) end
                if tsState then tsState.altPowerTextCenterHidden = true end
            else
                if tsState and tsState.altPowerTextCenterHidden then
                    if textStringFS.SetAlpha then pcall(textStringFS.SetAlpha, textStringFS, 1) end
                    tsState.altPowerTextCenterHidden = nil
                end
                applyAltTextStyle(textStringFS, acfg.textValue or {}, "Player:altpower-center", apb)
            end
        end
    end

    -- Width / height scaling (simple frame SetWidth/SetHeight based on %),
    -- plus additive X/Y offsets applied from the captured baseline points.
    if not inCombat then
        local apbState = getState(apb)
        if not apbState then return end
        -- Capture originals once
        if not apbState.ufOrigWidth then
            if apb.GetWidth then
                local ok, w = pcall(apb.GetWidth, apb)
                if ok and w and not issecretvalue(w) then apbState.ufOrigWidth = w end
            end
        end
        if not apbState.ufOrigHeight then
            if apb.GetHeight then
                local ok, h = pcall(apb.GetHeight, apb)
                if ok and h and not issecretvalue(h) then apbState.ufOrigHeight = h end
            end
        end
        if not apbState.ufOrigPoints then
            local pts = {}
            local n = (apb.GetNumPoints and apb:GetNumPoints()) or 0
            for i = 1, n do
                local p, rel, rp, x, y = apb:GetPoint(i)
                table.insert(pts, { p, rel, rp, x or 0, y or 0 })
            end
            apbState.ufOrigPoints = pts
        end

        local wPct = tonumber(acfg.widthPct) or 100
        local hPct = tonumber(acfg.heightPct) or 100
        local scaleX = math.max(0.5, math.min(1.5, wPct / 100))
        local scaleY = math.max(0.5, math.min(2.0, hPct / 100))

        -- Restore baseline first
        if apbState.ufOrigWidth and apb.SetWidth then
            pcall(apb.SetWidth, apb, apbState.ufOrigWidth)
        end
        if apbState.ufOrigHeight and apb.SetHeight then
            pcall(apb.SetHeight, apb, apbState.ufOrigHeight)
        end
        if apbState.ufOrigPoints and apb.ClearAllPoints and apb.SetPoint then
            pcall(apb.ClearAllPoints, apb)
            for _, pt in ipairs(apbState.ufOrigPoints) do
                pcall(apb.SetPoint, apb, pt[1] or "CENTER", pt[2], pt[3] or pt[1] or "CENTER", pt[4] or 0, pt[5] or 0)
            end
        end

        -- Apply width/height scaling (from center)
        if apbState.ufOrigWidth and apb.SetWidth then
            pcall(apb.SetWidth, apb, apbState.ufOrigWidth * scaleX)
        end
        if apbState.ufOrigHeight and apb.SetHeight then
            pcall(apb.SetHeight, apb, apbState.ufOrigHeight * scaleY)
        end

        -- Apply positioning offsets relative to the original anchor points.
        local offsetX = tonumber(acfg.offsetX) or 0
        local offsetY = tonumber(acfg.offsetY) or 0
        if apbState.ufOrigPoints and apb.ClearAllPoints and apb.SetPoint then
            pcall(apb.ClearAllPoints, apb)
            for _, pt in ipairs(apbState.ufOrigPoints) do
                local baseX = pt[4] or 0
                local baseY = pt[5] or 0
                local newX = baseX + offsetX
                local newY = baseY + offsetY
                pcall(apb.SetPoint, apb, pt[1] or "CENTER", pt[2], pt[3] or pt[1] or "CENTER", newX, newY)
            end
        end
    end
end

return AltPower
