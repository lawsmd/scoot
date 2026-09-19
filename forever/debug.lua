--------------------------------------------------------------------------------
-- forever/debug.lua
-- The /camelot verbs that drive the unit frames without a settings page.
--
-- Each verb registers with the command registry in core/commands.lua, which
-- reads the brand and the slash word from the entry file, so `/camelot` lists
-- these beside the debug commands the borrowed files bring with them. This
-- file loads last on Camelot.toc and binds the slash word at its end.
--
-- Output goes to the copyable window, never to chat.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Art = addon.UnitFrames.Art
local Harness = addon.UnitFrames.Harness

--------------------------------------------------------------------------------
-- state
--------------------------------------------------------------------------------

local function pushInstance(push, key)
    local UF = addon.UnitFrames
    local inst = UF.Frames[key]
    local blizzard = UF.Suppression.FrameName(key)

    push("[%s]", key)
    push("  setting enabled:  %s", tostring(UF.IsEnabled(key)))
    push("  Blizzard frame:   %s, suppressed %s",
        tostring(blizzard), tostring(UF.Suppression.IsSuppressed(key)))
    if not inst then
        push("  not built")
        push("")
        return
    end

    push("  unit:             %s", tostring(inst.unit))
    push("  enabled:          %s", tostring(inst.enabled))
    push("  frame shown:      %s", tostring(inst.frame:IsShown()))
    push("  click shown:      %s", tostring(inst.clickButton:IsShown()))
    push("  watch registered: %s", tostring(inst.watchRegistered))
    push("  preview:          %s, stand-in %s",
        tostring(inst.previewActive), tostring(inst.previewStandIn))
    push("  border file:      %s", tostring(inst.borderKey))

    local w, h = inst.frame:GetSize()
    push("  rect:             %.1f x %.1f at scale %.2f", w, h, inst.frame:GetScale())

    local point, _, relPoint, x, y = inst.frame:GetPoint()
    push("  point:            %s to %s  %.1f, %.1f",
        tostring(point), tostring(relPoint), x or 0, y or 0)

    local flags = Harness.PendingFlags(inst)
    if not flags then
        push("  deferred work:    nothing queued")
    else
        for name, on in pairs(flags) do
            if on then push("  deferred work:    %s", name) end
        end
    end
    push("")
end

local function dumpState(sub)
    local UF = addon.UnitFrames
    local lines, push = addon.DebugLines("=== Camelot unit frames ===", "")

    push("in combat:    %s", tostring(InCombatLockdown()))
    push("border style: %s", tostring(addon.DB.Get("unitFrames.borderStyle")))
    push("")

    for _, key in ipairs(UF.ORDER) do
        if sub == "" or sub == key then pushInstance(push, key) end
    end

    push("Textures")
    for _, key in ipairs(Art.ManifestOrder) do
        local path = Art.Paths[key]
        local id = GetFileIDFromPath and GetFileIDFromPath(path)
        push("  %-18s %s", key, id and ("file " .. id) or "UNRESOLVED")
    end

    push("")
    push("Bars are fed secrets and never read back, so no value appears above.")

    addon.DebugShowWindow("Camelot", lines)
end

--------------------------------------------------------------------------------
-- art
--------------------------------------------------------------------------------

-- A path this client cannot resolve still sets without error and draws nothing,
-- so a blank swatch is the only way a missing file announces itself.
local swatchFrame

local function showArt()
    if not swatchFrame then
        local f = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
        f:SetSize(420, 80 + #Art.ManifestOrder * 30)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function() f:StartMoving() end)
        f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOP", 0, -6)
        title:SetText("Camelot art")

        local y = -36
        for _, key in ipairs(Art.ManifestOrder) do
            local path = Art.Paths[key]

            local tex = f:CreateTexture(nil, "ARTWORK")
            tex:SetSize(48, 24)
            tex:SetPoint("TOPLEFT", 18, y)
            tex:SetTexture(path)

            local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("TOPLEFT", 78, y - 4)
            label:SetJustifyH("LEFT")
            local id = GetFileIDFromPath and GetFileIDFromPath(path)
            label:SetText(("%s  |cff888888%s|r"):format(key, id and ("file " .. id) or "UNRESOLVED"))

            y = y - 30
        end

        swatchFrame = f
    end
    swatchFrame:Show()
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

-- show and hide write the enable setting, which is what a settings page will
-- write: the frame goes, and Blizzard's frame for the unit comes back. A bare
-- word covers every frame.
local function setEnabled(sub, on)
    local UF = addon.UnitFrames
    if sub == "" then
        for _, key in ipairs(UF.ORDER) do UF.SetEnabled(key, on) end
        return
    end
    if not UF.SetEnabled(sub, on) then return addon.Commands.USAGE end
end

addon:RegisterSlashCommand({
    name = "show", help = "[player|target|focus|targettarget|pet] enable a unit frame, or all of them",
    handler = function(sub) return setEnabled(sub, true) end,
})

addon:RegisterSlashCommand({
    name = "hide", help = "[player|target|focus|targettarget|pet] disable a unit frame and hand Blizzard's back",
    handler = function(sub) return setEnabled(sub, false) end,
})

addon:RegisterSlashCommand({
    name = "state", help = "[key] dump the unit frame instances",
    handler = dumpState,
})

addon:RegisterSlashCommand({
    name = "border", help = "stock|tint|bronze: the frame border's colour",
    handler = function(sub)
        if not addon.UnitFrames.SetBorderStyle(sub) then return addon.Commands.USAGE end
    end,
})

addon:RegisterSlashCommand({
    name = "art", help = "draw every texture as a labelled swatch",
    handler = showArt,
})

addon:RegisterSlashCommand({
    name = "db", help = "dump CamelotDB: schema, profile, stored values",
    handler = function() addon.DB.Dump() end,
})

-- /camelot. The registry owns the word, the parse and the dispatch; a bare
-- /camelot opens the settings panel, the one behavior that is this addon's.
addon.Commands.InstallSlash(function()
    if addon.UI and addon.UI.SettingsPanel and addon.UI.SettingsPanel.Toggle then
        addon.UI.SettingsPanel:Toggle()
    end
end)
