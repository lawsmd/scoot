--------------------------------------------------------------------------------
-- forever/debug.lua
-- /camelot, the only way to drive the frame while there is no settings page.
--
-- The command registry in core/ is not on Camelot.toc. It wants addon.Print,
-- addon.DebugDump and addon.DebugDumpTargets from the other addon's entry file,
-- and its help title is a brand literal, so borrowing it would cost three stubs
-- and still read wrong. Four verbs do not justify that; this is written out and
-- the registry stays a later promotion.
--
-- Output goes to the copyable window, never to chat.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Art = addon.UnitFrames.Art
local Harness = addon.UnitFrames.Harness

local USAGE = {
    "/camelot show    build and show the player frame",
    "/camelot hide    hide it",
    "/camelot state   dump the instance",
    "/camelot art     draw every texture as a labelled swatch",
}

--------------------------------------------------------------------------------
-- state
--------------------------------------------------------------------------------

local function dumpState()
    local lines, push = addon.DebugLines("=== Camelot player frame ===", "")

    local Player = addon.UnitFrames.Player
    local inst = Player and Player.inst
    if not inst then
        push("No instance built. Run /camelot show first.")
        addon.DebugShowWindow("Camelot", lines)
        return
    end

    push("unit:             %s", tostring(inst.unit))
    push("enabled:          %s", tostring(inst.enabled))
    push("frame shown:      %s", tostring(inst.frame:IsShown()))
    push("watch registered: %s", tostring(inst.watchRegistered))
    push("in combat:        %s", tostring(InCombatLockdown()))

    local w, h = inst.frame:GetSize()
    push("rect:             %.1f x %.1f at scale %.2f", w, h, inst.frame:GetScale())

    local point, _, relPoint, x, y = inst.frame:GetPoint()
    push("point:            %s to %s  %.1f, %.1f",
        tostring(point), tostring(relPoint), x or 0, y or 0)

    push("")
    push("Deferred work")
    local flags = Harness.PendingFlags(inst)
    if not flags then
        push("  nothing queued")
    else
        for name, on in pairs(flags) do
            if on then push("  queued: %s", name) end
        end
    end

    push("")
    push("Textures")
    for _, key in ipairs(Art.ManifestOrder) do
        local path = Art.Paths[key]
        local id = GetFileIDFromPath and GetFileIDFromPath(path)
        push("  %-14s %s", key, id and ("file " .. id) or "UNRESOLVED")
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
        f:SetSize(420, 80 + #Art.ManifestOrder * 46)
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
            tex:SetSize(64, 32)
            tex:SetPoint("TOPLEFT", 18, y)
            tex:SetTexture(path)

            local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("TOPLEFT", 94, y - 4)
            label:SetJustifyH("LEFT")
            local id = GetFileIDFromPath and GetFileIDFromPath(path)
            label:SetText(("%s  |cff888888%s|r"):format(key, id and ("file " .. id) or "UNRESOLVED"))

            y = y - 46
        end

        swatchFrame = f
    end
    swatchFrame:Show()
end

--------------------------------------------------------------------------------
-- Dispatch
--------------------------------------------------------------------------------

local function usage()
    local lines = addon.DebugLines("=== /camelot ===", "")
    for _, line in ipairs(USAGE) do
        lines[#lines + 1] = line
    end
    addon.DebugShowWindow("Camelot", lines)
end

local function dispatch(msg)
    local verb = (msg or ""):lower():match("^%s*(%S*)")
    local Player = addon.UnitFrames.Player

    if verb == "show" then
        Player.SetShown(true)
    elseif verb == "hide" then
        Player.SetShown(false)
    elseif verb == "state" then
        dumpState()
    elseif verb == "art" then
        showArt()
    else
        usage()
    end
end

-- Kept off addon.Commands: the command registry is not on this addon's TOC, for
-- the reasons at the top of this file. Promoting it retires these two lines.
SLASH_CAMELOT1 = "/camelot"
SlashCmdList.CAMELOT = dispatch
