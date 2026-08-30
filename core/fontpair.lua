-- fontpair.lua - Deep Shadow rendering: a black copy drawn behind a FontString.
--
-- ApplyFontStyle (core/fonts.lua) calls in here for DEEPSHADOW* styles. The
-- copy shares the real string's font file, size, and engine flags, so an
-- OUTLINE/THICKOUTLINE flag dilates the copy the same way; offset (+2, -2) at
-- 0.8 alpha then reads as a fattened silhouette, which the native shadow
-- (never dilated by the engine) cannot produce.
--
-- Only styles applied to Scoot-created FontStrings offer DEEPSHADOW* keys
-- (see the *Paired order tables in core/fonts.lua): mirroring text into the
-- copy needs SetText hooks, and those are cheap and safe on our own strings.
-- Secret text (12.x) cannot be read or escape-stripped, so it is passed to the
-- copy untouched; inline escapes in secret strings would tint the copy, an
-- accepted degradation.
local addonName, addon = ...

addon.FontPair = {}

local OFFSET_X, OFFSET_Y = 2, -2

-- Strip inline escape sequences so colors, textures, and hyperlinks cannot
-- leak into the black copy. Hyperlinks keep their visible text.
function addon.FontPair.StripEscapes(text)
    local s = text
    s = s:gsub("|H.-|h(.-)|h", "%1")      -- hyperlinks: keep the display text
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")  -- |cffRRGGBB / |cAARRGGBB color starts
    s = s:gsub("|r", "")                  -- color ends
    s = s:gsub("|T.-|t", "")              -- texture escapes
    s = s:gsub("|A.-|a", "")              -- atlas escapes
    return s
end

local function mirrorValue(fs, text)
    local companion = fs.__scootPair
    if not companion or not fs.__scootPairActive then return end
    if text == nil then
        companion:SetText("")
    elseif type(issecretvalue) == "function" and issecretvalue(text) then
        pcall(companion.SetText, companion, text)
    else
        companion:SetText(addon.FontPair.StripEscapes(tostring(text)))
    end
end

-- For paths where the final text is not an argument (SetFormattedText, the
-- initial sync). GetText can raise on secret-stamped strings; a failed read
-- leaves the companion as it was.
local function mirrorFromGetText(fs)
    if not fs.__scootPair or not fs.__scootPairActive then return end
    local ok, text = pcall(fs.GetText, fs)
    if ok then mirrorValue(fs, text) end
end

local function onShow(fs)
    local companion = fs.__scootPair
    if companion and fs.__scootPairActive then companion:Show() end
end

local function onHide(fs)
    local companion = fs.__scootPair
    if companion then companion:Hide() end
end

-- Alpha rides along too: holds and fades that hide a string by SetAlpha(0)
-- instead of Hide() must take the copy with them, or the black copy shows
-- alone. Region alpha multiplies the copy's 0.8 text alpha, so the copy is
-- never more visible than its original.
local function onSetAlpha(fs, alpha)
    local companion = fs.__scootPair
    if companion and fs.__scootPairActive then
        pcall(companion.SetAlpha, companion, alpha)
    end
end

-- hooksecurefunc is permanent, so install once per FontString and gate the
-- mirror on __scootPairActive; switching the style away disables mirroring
-- without needing to unhook.
local function installHooks(fs)
    if fs.__scootPairHooked then return end
    fs.__scootPairHooked = true
    hooksecurefunc(fs, "SetText", mirrorValue)
    hooksecurefunc(fs, "SetFormattedText", mirrorFromGetText)
    hooksecurefunc(fs, "Show", onShow)
    hooksecurefunc(fs, "Hide", onHide)
    hooksecurefunc(fs, "SetAlpha", onSetAlpha)
end

-- Create or refresh the companion for fs. engineFlags is the decoded flag
-- string ApplyFontStyle is about to render the real string with.
function addon.FontPair.Apply(fs, face, size, engineFlags)
    local companion = fs.__scootPair
    if not companion then
        local parent = fs.GetParent and fs:GetParent()
        if not parent or not parent.CreateFontString then
            return -- nowhere to draw the copy; the base style still renders
        end
        local layer, sublevel = "ARTWORK", 0
        if fs.GetDrawLayer then
            local l, s = fs:GetDrawLayer()
            if l then layer = l end
            if type(s) == "number" then sublevel = s end
        end
        -- One sublevel below the real string. At the -8 floor the copy shares
        -- the sublevel and creation order decides; default sublevel is 0, so
        -- the floor is a non-case in practice.
        sublevel = math.max(sublevel - 1, -8)
        companion = parent:CreateFontString(nil, layer, nil, sublevel)
        fs.__scootPair = companion
    end

    fs.__scootPairActive = true

    if addon.ApplyFontFile then
        addon.ApplyFontFile(companion, face, size, engineFlags)
    end
    pcall(companion.SetTextColor, companion, 0, 0, 0, 0.8)
    pcall(companion.SetShadowColor, companion, 0, 0, 0, 0)
    pcall(companion.SetShadowOffset, companion, 0, 0)

    -- Box-anchor so justified fixed-width strings mirror correctly.
    companion:ClearAllPoints()
    companion:SetPoint("TOPLEFT", fs, "TOPLEFT", OFFSET_X, OFFSET_Y)
    companion:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", OFFSET_X, OFFSET_Y)
    if fs.GetJustifyH then pcall(companion.SetJustifyH, companion, fs:GetJustifyH()) end
    if fs.GetJustifyV then pcall(companion.SetJustifyV, companion, fs:GetJustifyV()) end
    if fs.GetWordWrap and companion.SetWordWrap then
        pcall(companion.SetWordWrap, companion, fs:GetWordWrap())
    end

    installHooks(fs)
    mirrorFromGetText(fs)

    pcall(companion.SetAlpha, companion, fs:GetAlpha() or 1)
    if fs:IsShown() then companion:Show() else companion:Hide() end
end

-- Called from ApplyFontStyle's non-paired path when a companion exists.
function addon.FontPair.Hide(fs)
    fs.__scootPairActive = nil
    local companion = fs.__scootPair
    if companion then
        companion:Hide()
        companion:SetText("")
    end
end
