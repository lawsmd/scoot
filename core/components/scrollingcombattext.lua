local addonName, addon = ...

local Component = addon.ComponentPrototype

-- Track state for font change detection
local sctDamageState = {
    initialLoadComplete = false,
    lastKnownFont = nil,
    damageTextFontApplied = false, -- Track if DAMAGE_TEXT_FONT has been set this session
}

-- Show combat font restart warning using Scoot's custom dialog system
-- (Avoids tainting StaticPopupDialogs which can block protected functions like ForceQuit)
local function showCombatFontRestartWarning()
    if addon.Dialogs and addon.Dialogs.Show then
        addon.Dialogs:Show("SCOOT_COMBAT_FONT_RESTART")
    end
end

local function clampPercent(value)
    local num = tonumber(value) or 100
    if num < 50 then
        num = 50
    elseif num > 150 then
        num = 150
    end
    return math.floor(num + 0.5)
end

local function applyWorldTextStyling(self)
    if not self or not self.db then
        return
    end

    local db = self.db

    local fontKey = db.fontFace or "FRIZQT__"
    local resolve = addon.ResolveFontFace or function(_)
        return (select(1, _G.GameFontNormal:GetFont()))
    end
    local face = resolve(fontKey)
    if not face or face == "" then
        face = (select(1, _G.GameFontNormal:GetFont()))
    end

    -- Check if font changed from user interaction (not during init or profile switches)
    if sctDamageState.initialLoadComplete and not addon._profileSwitchInProgress then
        if sctDamageState.lastKnownFont and sctDamageState.lastKnownFont ~= fontKey then
            -- Font was changed by user, show the restart warning
            showCombatFontRestartWarning()
        end
    end
    sctDamageState.lastKnownFont = fontKey

    local scalePercent = clampPercent(db.fontScale or 100)
    db.fontScale = scalePercent
    db.fontStyle = nil

    -- Set _G.DAMAGE_TEXT_FONT ONLY during initial addon load (ApplyEarlyComponentStyles).
    -- The C++ engine reads this global once at game startup to determine world damage text font.
    -- Setting it during early init (before any secure code runs) is safe from taint.
    -- Setting it later (e.g., during gameplay events) would cause taint propagation.
    -- After initial load, font changes require a full game restart to take effect.
    if not sctDamageState.damageTextFontApplied then
        _G.DAMAGE_TEXT_FONT = face
        sctDamageState.damageTextFontApplied = true
        if addon.LogWorldTextFont then
            addon.LogWorldTextFont("applyWorldTextStyling:DAMAGE_TEXT_FONT set", {
                face = face,
            })
        end
    end

    if addon.LogWorldTextFont then
        addon.LogWorldTextFont("applyWorldTextStyling:start", {
            face = face,
            requestedScale = scalePercent,
        })
    end

    local targets = {
        _G.CombatTextFont,
        _G.CombatTextFontOutline,
    }
    local touched = {}
    for _, fontObj in ipairs(targets) do
        if type(fontObj) == "table" and fontObj.GetFont and fontObj.SetFont and not touched[fontObj] then
            touched[fontObj] = true
            local ok, _, size, existingFlags = pcall(fontObj.GetFont, fontObj)
            if not ok then
                size = nil
                existingFlags = nil
            end
            size = tonumber(size) or 24
            pcall(fontObj.SetFont, fontObj, face, size, existingFlags)
            if addon.LogWorldTextFont then
                addon.LogWorldTextFont("applyWorldTextStyling:SetFont", {
                    target = fontObj.GetName and fontObj:GetName() or tostring(fontObj),
                    size = size,
                    flags = existingFlags,
                    face = face,
                })
            end
        end
    end

    local scalar = scalePercent / 100
    local scaledValue = string.format("%.2f", scalar)
    if _G.C_CVar and _G.C_CVar.SetCVar then
        _G.C_CVar.SetCVar("WorldTextScale", scaledValue)
    elseif _G.SetCVar then
        pcall(_G.SetCVar, "WorldTextScale", scaledValue)
    end
    if addon.LogWorldTextFont then
        addon.LogWorldTextFont("applyWorldTextStyling:WorldTextScale", { scale = scaledValue })
    end

    -- Mark initial load as complete after first styling pass
    if not sctDamageState.initialLoadComplete then
        sctDamageState.initialLoadComplete = true
    end
end

addon:RegisterComponentInitializer(function(self)
    local sctDamage = Component:New({
        id = "sctDamage",
        name = "Damage Numbers",
        frameName = nil,
        applyDuringInit = true,
        settings = {
            fontFace = { type = "addon", default = "FRIZQT__", ui = {
                label = "Font",
                widget = "dropdown",
                section = "Font",
                order = 1,
                optionsProvider = function()
                    if addon.BuildFontOptionsContainer then
                        return addon.BuildFontOptionsContainer()
                    end
                    return {}
                end,
            }},
            fontScale = { type = "addon", default = 100, ui = {
                label = "Font Scale",
                widget = "slider",
                min = 50,
                max = 150,
                step = 1,
                section = "Font",
                order = 2,
                format = "percent",
            }},
        },
        ApplyStyling = applyWorldTextStyling,
    })

    self:RegisterComponent(sctDamage)
end)


