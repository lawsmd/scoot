--------------------------------------------------------------------------------
-- bars/textures.lua
-- Texture application functions for unit frame status bars
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Get utilities
local Utils = addon.BarsUtils

-- Reference to FrameState module for safe property storage (avoids writing to Blizzard frames)
local FS = nil
local function ensureFS()
    if not FS then FS = addon.FrameState end
    return FS
end

local function getState(frame)
    local fs = ensureFS()
    return fs and fs.Get(frame) or nil
end

local function getProp(frame, key)
    local st = getState(frame)
    return st and st[key] or nil
end

local function setProp(frame, key, value)
    local st = getState(frame)
    if st then
        st[key] = value
    end
end

-- Create module namespace
addon.BarsTextures = addon.BarsTextures or {}
local Textures = addon.BarsTextures

--------------------------------------------------------------------------------
-- Health Value Color Curve ("Color by Value" Feature)
--------------------------------------------------------------------------------
-- Uses C_CurveUtil.CreateColorCurve() with UnitHealthPercent() to safely color
-- health bars based on remaining health percentage. This pattern is secret-safe
-- because Blizzard evaluates the secret health percentage internally and returns
-- a non-secret color object.
--
-- Gradient: Green (100%) -> Yellow (50%) -> Red (0%)
--------------------------------------------------------------------------------

local healthValueCurve = nil

local function getHealthValueCurve()
    if not healthValueCurve then
        if not _G.C_CurveUtil then
            if addon.DebugPrint then addon.DebugPrint("getHealthValueCurve: C_CurveUtil not available") end
            return nil
        end
        if not _G.C_CurveUtil.CreateColorCurve then
            if addon.DebugPrint then addon.DebugPrint("getHealthValueCurve: CreateColorCurve not available") end
            return nil
        end

        healthValueCurve = C_CurveUtil.CreateColorCurve()
        if not healthValueCurve then
            if addon.DebugPrint then addon.DebugPrint("getHealthValueCurve: CreateColorCurve returned nil") end
            return nil
        end

        -- Linear interpolation between color points
        if healthValueCurve.SetType and _G.Enum and _G.Enum.LuaCurveType then
            local ok, err = pcall(healthValueCurve.SetType, healthValueCurve, Enum.LuaCurveType.Linear)
            if not ok and addon.DebugPrint then addon.DebugPrint("getHealthValueCurve: SetType failed - " .. tostring(err)) end
        end

        -- Add color points: Red at 0%, Yellow at 50%, Green at 100%
        -- UnitHealthPercent returns 0-1 range (normalized), so use 0.0, 0.5, 1.0 as x values
        if healthValueCurve.AddPoint and _G.CreateColor then
            local ok1, err1 = pcall(healthValueCurve.AddPoint, healthValueCurve, 0.0, CreateColor(1, 0, 0, 1))    -- Red at 0%
            local ok2, err2 = pcall(healthValueCurve.AddPoint, healthValueCurve, 0.5, CreateColor(1, 1, 0, 1))    -- Yellow at 50%
            local ok3, err3 = pcall(healthValueCurve.AddPoint, healthValueCurve, 1.0, CreateColor(0, 1, 0, 1))    -- Green at 100%
            if addon.DebugPrint then
                if not ok1 then addon.DebugPrint("getHealthValueCurve: AddPoint(0) failed - " .. tostring(err1)) end
                if not ok2 then addon.DebugPrint("getHealthValueCurve: AddPoint(50) failed - " .. tostring(err2)) end
                if not ok3 then addon.DebugPrint("getHealthValueCurve: AddPoint(100) failed - " .. tostring(err3)) end
            end
        end

        if addon.DebugPrint then addon.DebugPrint("getHealthValueCurve: created curve with " .. (healthValueCurve.GetPointCount and healthValueCurve:GetPointCount() or "?") .. " points") end
    end
    return healthValueCurve
end

-- Expose getter for other modules
function Textures.getHealthValueCurve()
    return getHealthValueCurve()
end

--------------------------------------------------------------------------------
-- Health Value Dark Color Curve ("Color by Value (Dark)" Feature)
--------------------------------------------------------------------------------
-- Same API pattern as the standard curve, but with dark gray at 100% health
-- instead of green. This provides a "damage indicator" style where healthy
-- units are muted and damaged units stand out.
--
-- Gradient: Dark Gray (100%) -> Yellow (50%) -> Red (0%)
-- The 0.23 gray value is a standard dark health bar tint for visual consistency.
--------------------------------------------------------------------------------

local healthValueDarkCurve = nil

local function getHealthValueDarkCurve()
    if not healthValueDarkCurve then
        if not _G.C_CurveUtil then
            if addon.DebugPrint then addon.DebugPrint("getHealthValueDarkCurve: C_CurveUtil not available") end
            return nil
        end
        if not _G.C_CurveUtil.CreateColorCurve then
            if addon.DebugPrint then addon.DebugPrint("getHealthValueDarkCurve: CreateColorCurve not available") end
            return nil
        end

        healthValueDarkCurve = C_CurveUtil.CreateColorCurve()
        if not healthValueDarkCurve then
            if addon.DebugPrint then addon.DebugPrint("getHealthValueDarkCurve: CreateColorCurve returned nil") end
            return nil
        end

        -- Linear interpolation between color points
        if healthValueDarkCurve.SetType and _G.Enum and _G.Enum.LuaCurveType then
            local ok, err = pcall(healthValueDarkCurve.SetType, healthValueDarkCurve, Enum.LuaCurveType.Linear)
            if not ok and addon.DebugPrint then addon.DebugPrint("getHealthValueDarkCurve: SetType failed - " .. tostring(err)) end
        end

        -- Add color points: Red at 0%, Yellow at 50%, Green at 99.99%, Dark Gray at 100%
        -- The 99.99% green point ensures the curve matches the regular curve for virtually
        -- all values. Only exactly 100% shows dark gray - the 0.01% transition is imperceptible.
        -- Dark gray (0.23, 0.23, 0.23) is a standard dark health bar tint
        if healthValueDarkCurve.AddPoint and _G.CreateColor then
            local ok1, err1 = pcall(healthValueDarkCurve.AddPoint, healthValueDarkCurve, 0.0, CreateColor(1, 0, 0, 1))       -- Red at 0%
            local ok2, err2 = pcall(healthValueDarkCurve.AddPoint, healthValueDarkCurve, 0.5, CreateColor(1, 1, 0, 1))       -- Yellow at 50%
            local ok3, err3 = pcall(healthValueDarkCurve.AddPoint, healthValueDarkCurve, 0.9999, CreateColor(0, 1, 0, 1))    -- Green at 99.99% (matches regular curve)
            local ok4, err4 = pcall(healthValueDarkCurve.AddPoint, healthValueDarkCurve, 1.0, CreateColor(0.23, 0.23, 0.23, 1)) -- Dark gray at 100%
            if addon.DebugPrint then
                if not ok1 then addon.DebugPrint("getHealthValueDarkCurve: AddPoint(0) failed - " .. tostring(err1)) end
                if not ok2 then addon.DebugPrint("getHealthValueDarkCurve: AddPoint(50) failed - " .. tostring(err2)) end
                if not ok3 then addon.DebugPrint("getHealthValueDarkCurve: AddPoint(99.99) failed - " .. tostring(err3)) end
                if not ok4 then addon.DebugPrint("getHealthValueDarkCurve: AddPoint(100) failed - " .. tostring(err4)) end
            end
        end

        if addon.DebugPrint then addon.DebugPrint("getHealthValueDarkCurve: created curve with " .. (healthValueDarkCurve.GetPointCount and healthValueDarkCurve:GetPointCount() or "?") .. " points") end
    end
    return healthValueDarkCurve
end

-- Expose dark curve getter for other modules
function Textures.getHealthValueDarkCurve()
    return getHealthValueDarkCurve()
end

-- Apply value-based color to a health bar texture using UnitHealthPercent
-- @param bar: The StatusBar frame
-- @param unit: Unit token ("player", "target", "party1", etc.)
-- @param overlay: Optional overlay texture to color instead of bar texture
-- @param useDark: If true, use dark gray at 100% instead of green
function Textures.applyValueBasedColor(bar, unit, overlay, useDark)
    if not bar or not unit then return end

    -- Get the appropriate health value color curve
    local curve = useDark and getHealthValueDarkCurve() or getHealthValueCurve()
    if not curve then
        if addon.DebugPrint then addon.DebugPrint("applyValueBasedColor: curve is nil") end
        return
    end

    -- Use UnitHealthPercent with the curve to get a color
    -- This is secret-safe because Blizzard evaluates the secret percentage internally
    if not _G.UnitHealthPercent then
        if addon.DebugPrint then addon.DebugPrint("applyValueBasedColor: UnitHealthPercent not found") end
        return
    end

    local ok, color = pcall(UnitHealthPercent, unit, false, curve)
    if not ok then
        if addon.DebugPrint then addon.DebugPrint("applyValueBasedColor: pcall failed - " .. tostring(color)) end
        return
    end

    if not color then
        if addon.DebugPrint then addon.DebugPrint("applyValueBasedColor: UnitHealthPercent returned nil") end
        return
    end

    -- Check if the result is a color object or a number
    if type(color) == "number" then
        if addon.DebugPrint then addon.DebugPrint("applyValueBasedColor: got number " .. color .. " instead of color") end
        return
    end

    if not color.GetRGB then
        if addon.DebugPrint then addon.DebugPrint("applyValueBasedColor: color has no GetRGB method, type=" .. type(color)) end
        return
    end

    local r, g, b = color:GetRGB()

    -- Note: GetRGB() could theoretically return secret values, but
    -- UnitHealthPercent with a color curve should return a clean color object.
    -- The pcall wrappers on SetVertexColor below handle any edge cases.

    -- Color ALL relevant textures to handle cases where HealthBarTexture and
    -- GetStatusBarTexture() are different objects, or where multiple textures
    -- need coloring. This fixes the "white layer on top" issue at full opacity.
    local texturesColored = 0

    -- Use FrameState to prevent recursion (SetStatusBarColor triggers hooks that call back here)
    local barState = ensureFS() and ensureFS().Get(bar)
    if barState and barState.applyingValueBasedColor then
        return -- Already applying, prevent recursion
    end
    if barState then barState.applyingValueBasedColor = true end

    -- 1. Color the overlay if provided
    if overlay and overlay.SetVertexColor then
        pcall(overlay.SetVertexColor, overlay, r, g, b, 1)
        texturesColored = texturesColored + 1
    end

    -- When the overlay system is active (rectActive=true), it handles all visual display.
    -- Skip ALL modifications to Blizzard's textures - touching them triggers internal
    -- re-renders that "wake up" the hidden full-size bar and break height reduction.
    local overlaySystemActive = barState and barState.rectActive

    if not overlaySystemActive then
        -- 2. Color GetStatusBarTexture() result
        local statusBarTex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
        if statusBarTex and statusBarTex.SetVertexColor and statusBarTex ~= overlay then
            pcall(statusBarTex.SetVertexColor, statusBarTex, r, g, b, 1)
            texturesColored = texturesColored + 1
        end

        -- 3. Color bar.HealthBarTexture if it's a different object (Blizzard's named child)
        local namedTex = bar.HealthBarTexture
        if namedTex and namedTex.SetVertexColor and namedTex ~= overlay and namedTex ~= statusBarTex then
            pcall(namedTex.SetVertexColor, namedTex, r, g, b, 1)
            texturesColored = texturesColored + 1
        end

        -- 4. Also set the StatusBar's color directly (affects how it renders the fill)
        if bar.SetStatusBarColor then
            pcall(bar.SetStatusBarColor, bar, r, g, b)
            texturesColored = texturesColored + 1
        end
    end

    if barState then barState.applyingValueBasedColor = nil end

    if addon.DebugPrint and texturesColored > 0 then
        addon.DebugPrint(string.format("applyValueBasedColor: colored %d textures for %s (r=%.2f g=%.2f b=%.2f)", texturesColored, unit, r, g, b))
    end
end

--------------------------------------------------------------------------------
-- Color Reapply Loop (Fix for Stuck Colors at 100%)
--------------------------------------------------------------------------------
-- Schedules multiple unconditional color reapplies at staggered intervals.
-- This brute-force approach catches timing edge cases where UnitHealthPercent()
-- doesn't reflect the new health value immediately (API timing lag).
--
-- Why brute-force instead of smart validation:
-- GetVertexColor() returns "secret values" that error on arithmetic,
-- making color comparison impossible. Unconditional reapply avoids reading colors.
--
-- Intervals: 50ms, 100ms, 200ms, 350ms, 500ms - ensures at least one reapply
-- occurs after UnitHealthPercent has updated to the correct value.
--------------------------------------------------------------------------------

local pendingValidations = setmetatable({}, { __mode = "k" }) -- Weak keys for GC

-- Schedule a color validation loop for a health bar
-- @param bar: The StatusBar frame
-- @param unit: Unit token ("player", "target", "party1", etc.)
-- @param overlay: Optional overlay texture to validate/color
-- @param useDark: If true, use dark gray at 100% instead of green
function Textures.scheduleColorValidation(bar, unit, overlay, useDark)
    if not bar or not unit then return end

    -- Prevent duplicate validations for the same bar
    if pendingValidations[bar] then
        return
    end

    -- NOTE: The time-based cooldown was removed because it caused stuck colors.
    -- When health changed rapidly (e.g., damaged to 20% then healed to 100% within
    -- 600ms), the cooldown blocked the second event from getting its own validation
    -- loop, leaving colors stuck until the next health change.
    --
    -- The cooldown was originally added (pre-anchor-fix) to prevent blinking when
    -- ApplyStyles() was called repeatedly. The anchor-based fix now handles that
    -- case, so the cooldown is no longer needed.
    --
    -- The pendingValidations check below still prevents truly duplicate validations
    -- for the same bar when the SAME event causes multiple calls.

    pendingValidations[bar] = true

    -- SIMPLIFIED APPROACH: Due to secret value issues, color comparison is unreliable.
    -- Instead of smart validation, use a brute-force approach:
    -- Unconditionally reapply color at multiple intervals to catch timing edge cases.
    -- This ensures the correct color is eventually applied even if UnitHealthPercent
    -- is initially stale (e.g., when healing to exactly 100%).
    -- Extended delays to catch edge cases where API updates are slow.
    local delays = { 0.05, 0.1, 0.2, 0.35, 0.5 }  -- 50ms, 100ms, 200ms, 350ms, 500ms
    local completed = 0

    for _, delay in ipairs(delays) do
        C_Timer.After(delay, function()
            completed = completed + 1
            -- Only clear pending flag after all attempts complete
            if completed >= #delays then
                pendingValidations[bar] = nil
            end
            -- Unconditionally reapply - let applyValueBasedColor handle everything
            if addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
                addon.BarsTextures.applyValueBasedColor(bar, unit, overlay, useDark)
            end
        end)
    end
end

--------------------------------------------------------------------------------
-- Mask Enforcement
--------------------------------------------------------------------------------

-- Ensure mask is properly applied to bar texture (re-apply after texture changes)
function Textures.ensureMaskOnBarTexture(bar, mask)
    if not bar or not mask or not bar.GetStatusBarTexture then return end
    local tex = bar:GetStatusBarTexture()
    if not tex or not tex.AddMaskTexture then return end
    -- Re-apply mask to the current texture instance and enforce Blizzard's texel snapping settings
    pcall(tex.AddMaskTexture, tex, mask)
    if tex.SetTexelSnappingBias then pcall(tex.SetTexelSnappingBias, tex, 0) end
    if tex.SetSnapToPixelGrid then pcall(tex.SetSnapToPixelGrid, tex, false) end
    if tex.SetHorizTile then pcall(tex.SetHorizTile, tex, false) end
    if tex.SetVertTile then pcall(tex.SetVertTile, tex, false) end
    if tex.SetTexCoord then pcall(tex.SetTexCoord, tex, 0, 1, 0, 1) end
end

--------------------------------------------------------------------------------
-- Status Bar Texture Application
--------------------------------------------------------------------------------

-- Apply texture and color to a status bar (health/power/cast)
-- @param bar: The StatusBar frame
-- @param textureKey: Texture key from settings (or "default")
-- @param colorMode: "default", "custom", "class", "texture", "value"
-- @param tint: Color table {r, g, b, a} for custom color mode
-- @param unitForClass: Unit to get class color from
-- @param barKind: "health", "power", "altpower", or "cast"
-- @param unitForPower: Unit to get power color from
-- @param combatSafe: If true, allows application during combat (for visual-only changes)
function Textures.applyToBar(bar, textureKey, colorMode, tint, unitForClass, barKind, unitForPower, combatSafe)
    if not bar or type(bar.GetStatusBarTexture) ~= "function" then return end

    -- Combat safety: touching protected StatusBars (SetStatusBarTexture / SetVertexColor / CreateTexture)
    -- during combat can taint the execution context and later cause unrelated protected calls to be blocked.
    -- Callers should queue a post-combat reapply instead.
    --
    -- Exception: some callers (e.g., Cast Bar visual-only refresh) intentionally re-apply ONLY
    -- cosmetic texture/color changes during combat to keep styling persistent while avoiding
    -- combat-unsafe layout operations. Those callers may pass combatSafe=true.
    if not combatSafe and InCombatLockdown and InCombatLockdown() then
        return
    end

    -- "value" and "valueDark" modes use dynamic updates via hooks, not static color.
    -- Apply custom texture if selected, then apply initial value-based color.
    if colorMode == "value" or colorMode == "valueDark" then
        local useDark = (colorMode == "valueDark")
        local isCustom = type(textureKey) == "string" and textureKey ~= "" and textureKey ~= "default"
        local resolvedPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(textureKey)
        if isCustom and resolvedPath then
            if bar.SetStatusBarTexture then
                setProp(bar, "ufInternalTextureWrite", true)
                pcall(bar.SetStatusBarTexture, bar, resolvedPath)
                setProp(bar, "ufInternalTextureWrite", nil)
            end
        end
        -- Apply initial value-based color using the unit token (unitForClass parameter)
        -- This ensures the bar isn't left white when the setting is first enabled
        if unitForClass then
            Textures.applyValueBasedColor(bar, unitForClass, nil, useDark)
        end
        return
    end
    
    -- Power bars with default texture + default color: be completely hands-off.
    -- Blizzard dynamically updates power bar texture AND vertex color when power type changes
    -- (e.g., Druid switching between Mana/Energy forms). Touching ANYTHING here risks
    -- overwriting Blizzard's correctly-set state with stale captured values. By returning
    -- early, Blizzard's native system handles everything.
    local isDefaultTexture = (textureKey == nil or textureKey == "" or textureKey == "default")
    local isDefaultColor = (colorMode == nil or colorMode == "" or colorMode == "default")
    if (barKind == "power" or barKind == "altpower") and isDefaultTexture and isDefaultColor then
        return
    end
    
    local tex = bar:GetStatusBarTexture()
    -- Capture original once
    if not getProp(bar, "ufOrigCaptured") then
        if tex and tex.GetAtlas then
            local ok, atlas = pcall(tex.GetAtlas, tex)
            if ok and atlas then setProp(bar, "ufOrigAtlas", atlas) end
        end
        if tex and tex.GetTexture then
            local ok, path = pcall(tex.GetTexture, tex)
            if ok and path then
                -- Some Blizzard status bars use atlases; GetAtlas may return nil while GetTexture returns the atlas token.
                -- Prefer treating such strings as atlases when possible to avoid spritesheet rendering on restore.
                local isAtlas = false
                if type(path) == "string" and _G.C_Texture and _G.C_Texture.GetAtlasInfo then
                    local infoOk, info = pcall(_G.C_Texture.GetAtlasInfo, path)
                    isAtlas = infoOk and info ~= nil
                end
                if isAtlas then
                    local existingAtlas = getProp(bar, "ufOrigAtlas")
                    if not existingAtlas then setProp(bar, "ufOrigAtlas", path) end
                else
                    setProp(bar, "ufOrigPath", path)
                end
            end
        end
        if tex and tex.GetVertexColor then
            local ok, r, g, b, a = pcall(tex.GetVertexColor, tex)
            if ok then setProp(bar, "ufOrigVertex", { r or 1, g or 1, b or 1, a or 1 }) end
        end
        setProp(bar, "ufOrigCaptured", true)
    end

    local isCustom = type(textureKey) == "string" and textureKey ~= "" and textureKey ~= "default"
    local resolvedPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(textureKey)
    if isCustom and resolvedPath then
        if bar.SetStatusBarTexture then
            -- Mark this write so any SetStatusBarTexture hook can ignore it (avoid recursion)
            setProp(bar, "ufInternalTextureWrite", true)
            pcall(bar.SetStatusBarTexture, bar, resolvedPath)
            setProp(bar, "ufInternalTextureWrite", nil)
        end
        -- Re-fetch the current texture after swapping to ensure subsequent operations target the new texture
        tex = bar:GetStatusBarTexture()
        local r, g, b, a = 1, 1, 1, 1
        if colorMode == "custom" and type(tint) == "table" then
            r, g, b, a = tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1
        elseif colorMode == "class" then
            if addon.GetClassColorRGB then
                local cr, cg, cb = addon.GetClassColorRGB(unitForClass or "player")
                r, g, b, a = cr or 1, cg or 1, cb or 1, 1
            end
        elseif colorMode == "texture" then
            -- Apply white (no tint) to preserve texture's original colors
            r, g, b, a = 1, 1, 1, 1
        elseif colorMode == "default" or colorMode == "power" then
            -- When using a custom texture, "Default" should tint to the stock bar color
            -- ("power" is a legacy alias for "default" on power bars)
            if barKind == "cast" then
                -- Stock cast bar yellow from CastingBarFrame mixin.
                r, g, b, a = 1.0, 0.7, 0.0, 1
            elseif barKind == "health" and addon.GetDefaultHealthColorRGB then
                local hr, hg, hb = addon.GetDefaultHealthColorRGB()
                r, g, b, a = hr or 0, hg or 1, hb or 0, 1
            elseif (barKind == "power" or barKind == "altpower") and addon.GetPowerColorRGB then
                -- Power and Alternate Power bars both use the player's power color for Default.
                local pr, pg, pb = addon.GetPowerColorRGB(unitForPower or unitForClass or "player")
                r, g, b, a = pr or 1, pg or 1, pb or 1, 1
            else
                local ov = getProp(bar, "ufOrigVertex")
                if type(ov) == "table" then r, g, b, a = ov[1] or 1, ov[2] or 1, ov[3] or 1, ov[4] or 1 end
            end
        end
        if tex and tex.SetVertexColor then pcall(tex.SetVertexColor, tex, r, g, b, a) end
    else
        -- Default texture path. If the user selected Class/Custom color, avoid restoring
        -- Blizzard's green/colored atlas because vertex-color multiplies and distorts hues.
        -- Instead, use a neutral white fill and apply the desired color; keep the stock mask.
        local r, g, b, a = 1, 1, 1, 1
        local wantsNeutral = (colorMode == "custom" and type(tint) == "table") or (colorMode == "class")
        if wantsNeutral then
            if colorMode == "custom" then
                r, g, b, a = tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1
            elseif colorMode == "class" and addon.GetClassColorRGB then
                local cr, cg, cb = addon.GetClassColorRGB(unitForClass or "player")
                r, g, b, a = cr or 1, cg or 1, cb or 1, 1
            end
            if tex and tex.SetColorTexture then pcall(tex.SetColorTexture, tex, 1, 1, 1, 1) end
        else
            -- Default color: restore Blizzard's original fill
            -- Note: Power bars with default texture + default color already returned early above.
            if getProp(bar, "ufOrigCaptured") then
                local origAtlas = getProp(bar, "ufOrigAtlas")
                local origPath = getProp(bar, "ufOrigPath")
                if origAtlas then
                    if tex and tex.SetAtlas then
                        pcall(tex.SetAtlas, tex, origAtlas, true)
                    elseif bar.SetStatusBarTexture then
                        setProp(bar, "ufInternalTextureWrite", true)
                        pcall(bar.SetStatusBarTexture, bar, origAtlas)
                        setProp(bar, "ufInternalTextureWrite", nil)
                    end
                elseif origPath then
                    local treatAsAtlas = _G.C_Texture and _G.C_Texture.GetAtlasInfo and _G.C_Texture.GetAtlasInfo(origPath) ~= nil
                    if treatAsAtlas and tex and tex.SetAtlas then
                        pcall(tex.SetAtlas, tex, origPath, true)
                    elseif bar.SetStatusBarTexture then
                        setProp(bar, "ufInternalTextureWrite", true)
                        pcall(bar.SetStatusBarTexture, bar, origPath)
                        setProp(bar, "ufInternalTextureWrite", nil)
                    end
                end
            end
            if barKind == "cast" then
                -- Use Blizzard's stock cast bar yellow as the default color.
                -- Based on Blizzard_CastingBarFrame.lua (CastingBarFrameMixin).
                r, g, b, a = 1.0, 0.7, 0.0, 1
            else
                local ov = getProp(bar, "ufOrigVertex") or {1,1,1,1}
                r, g, b, a = ov[1] or 1, ov[2] or 1, ov[3] or 1, ov[4] or 1
            end
        end
        if tex and tex.SetVertexColor then pcall(tex.SetVertexColor, tex, r, g, b, a) end
    end
end

--------------------------------------------------------------------------------
-- Background Texture Application
--------------------------------------------------------------------------------

-- Apply background texture and color to a bar
function Textures.applyBackgroundToBar(bar, backgroundTextureKey, backgroundColorMode, backgroundTint, backgroundOpacity, unit, barKind)
    if not bar then return end

    -- Combat safety: creating/modifying textures on protected frames during combat can taint.
    if InCombatLockdown and InCombatLockdown() then
        return
    end
    
    -- Ensure a background texture frame exists at an appropriate sublevel so it appears
    -- behind the status bar fill but remains visible for cast bars.
    --
    -- For generic unit frame bars (health/power), the background is kept very low in the
    -- BACKGROUND stack (-8) so any stock art sits above it if present.
    --
    -- For CastingBarFrame-based bars (Player/Target/Focus cast bars), Blizzard defines a
    -- `Background` texture at BACKGROUND subLevel=2 (see CastingBarFrameBaseTemplate in
    -- Blizzard source). An earlier implementation created ScooterModBG at subLevel=-8,
    -- which meant the stock Background completely covered the overlay and made Scooter
    -- backgrounds effectively invisible even though the region existed in the frame hierarchy.
    --
    -- To keep behaviour consistent with other bars while making cast bar backgrounds
    -- visible, ScooterModBG is rendered above the stock Background (subLevel=3) but still
    -- on the BACKGROUND layer so the status bar fill and FX remain on top.
    local scooterBG = getProp(bar, "ScooterModBG")
    if not scooterBG then
        local layer = "BACKGROUND"
        local sublevel = -8
        if barKind == "cast" then
            sublevel = 3
        elseif unit == "Party" or unit == "Raid" then
            -- CompactUnitFrame health bars: parent's background is at sublevel 0.
            -- Use sublevel 1 to draw above it (combined with hiding parent bg).
            sublevel = 1
        end
        scooterBG = bar:CreateTexture(nil, layer, nil, sublevel)
        setProp(bar, "ScooterModBG", scooterBG)
        scooterBG:SetAllPoints(bar)
    elseif barKind == "cast" then
        -- If ScooterModBG was created earlier (e.g., before cast styling was enabled),
        -- make sure it sits above the stock Background for CastingBarFrame.
        local _, currentSub = scooterBG:GetDrawLayer()
        if currentSub == nil or currentSub < 3 then
            scooterBG:SetDrawLayer("BACKGROUND", 3)
        end
    elseif unit == "Party" or unit == "Raid" then
        -- Ensure party/raid frames use the correct sublevel
        local _, currentSub = scooterBG:GetDrawLayer()
        if currentSub == nil or currentSub < 1 then
            scooterBG:SetDrawLayer("BACKGROUND", 1)
        end
    end
    
    -- Get opacity (default 50% based on Blizzard's dead/ghost state alpha)
    local opacity = tonumber(backgroundOpacity) or 50
    opacity = math.max(0, math.min(100, opacity)) / 100
    
    -- Check if we're using a custom background texture
    local isCustomTexture = type(backgroundTextureKey) == "string" and backgroundTextureKey ~= "" and backgroundTextureKey ~= "default"
    local resolvedPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(backgroundTextureKey)
    
    if isCustomTexture and resolvedPath then
        -- Apply custom texture
        pcall(scooterBG.SetTexture, scooterBG, resolvedPath)

        -- Apply color based on mode
        local r, g, b, a = 1, 1, 1, 1
        if backgroundColorMode == "custom" and type(backgroundTint) == "table" then
            r, g, b, a = backgroundTint[1] or 1, backgroundTint[2] or 1, backgroundTint[3] or 1, backgroundTint[4] or 1
        elseif backgroundColorMode == "texture" then
            -- Apply white (no tint) to preserve texture's original colors
            r, g, b, a = 1, 1, 1, 1
        elseif backgroundColorMode == "default" then
            r, g, b, a = Utils.getDefaultBackgroundColor(unit, barKind)
        end

        -- Multiply tint alpha by opacity for correct transparency
        local finalAlpha = (a or 1) * opacity
        if scooterBG.SetVertexColor then
            pcall(scooterBG.SetVertexColor, scooterBG, r, g, b, finalAlpha)
        end
        scooterBG:Show()
        
        -- Hide Blizzard's stock Background texture when using a custom texture.
        -- CastingBarFrame-based bars (Player/Target/Focus cast bars) have a stock
        -- Background texture at BACKGROUND sublevel 2. Without hiding it, the stock
        -- background shows through since ScooterModBG sits at sublevel 3.
        -- Use SetAlpha(0) instead of Hide() to avoid fighting Blizzard's internal logic.
        if bar.Background and bar.Background.SetAlpha then
            pcall(bar.Background.SetAlpha, bar.Background, 0)
        end
        -- CompactUnitFrame-style health bars (party/raid frames) have the background
        -- on the PARENT frame (frame.background), not on the health bar itself.
        -- That must be hidden too, otherwise it covers ScooterModBG.
        local parentFrame = bar.GetParent and bar:GetParent()
        if parentFrame and parentFrame.background and parentFrame.background.SetAlpha then
            pcall(parentFrame.background.SetAlpha, parentFrame.background, 0)
        end
    else
        -- Default: always show the addon background with default black color
        -- Blizzard's stock Background texture is not relied upon since it's hidden by default
        pcall(scooterBG.SetTexture, scooterBG, nil)

        local r, g, b, a = Utils.getDefaultBackgroundColor(unit, barKind)
        if backgroundColorMode == "custom" and type(backgroundTint) == "table" then
            r, g, b, a = backgroundTint[1] or 1, backgroundTint[2] or 1, backgroundTint[3] or 1, backgroundTint[4] or 1
        end

        -- Multiply tint alpha by opacity for correct transparency
        local finalAlpha = (a or 1) * opacity
        if scooterBG.SetColorTexture then
            pcall(scooterBG.SetColorTexture, scooterBG, r, g, b, finalAlpha)
        end
        scooterBG:Show()

        -- Hide Blizzard's stock Background textures when applying custom opacity.
        -- Even with "default" texture, ScooterModBG provides the background with
        -- the user's configured opacity - Blizzard's opaque backgrounds must not
        -- cover it.
        if bar.Background and bar.Background.SetAlpha then
            pcall(bar.Background.SetAlpha, bar.Background, 0)
        end
        -- CompactUnitFrame-style health bars (party/raid frames) have the background
        -- on the PARENT frame (frame.background), not on the health bar itself.
        local parentFrame = bar.GetParent and bar:GetParent()
        if parentFrame and parentFrame.background and parentFrame.background.SetAlpha then
            pcall(parentFrame.background.SetAlpha, parentFrame.background, 0)
        end
    end
end

-- Expose helpers to addon namespace for other modules (Cast Bar styling, etc.)
addon._ApplyToStatusBar = Textures.applyToBar
addon._ApplyBackgroundToStatusBar = Textures.applyBackgroundToBar

return Textures
