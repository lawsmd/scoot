--------------------------------------------------------------------------------
-- forever/actionbars/suppression.lua
-- Which Blizzard bar each Camelot bar stands in for, and how it is taken off
-- screen, through addon.NativeFrame under one owner. The seven multibars are
-- parked under the hidden holder. The main bar is dimmed instead: it is the
-- native keybind target, so it stays in Blizzard's parent chain, and Edit
-- Mode's layout pass re-parents system frames in combat. Forever's end caps
-- are children of the main bar, but each is an Edit Mode system whose
-- selection box ignores its parent's alpha, so the dimmed bar left two empty
-- boxes in Edit Mode; both caps are parked.
--
-- Nothing is released: the Features switch lands at reload, and a feature
-- off at login never claims. The pet bar and the stance bar stay
-- Blizzard's in this phase. The micro menu and the bag bar are parked whole:
-- Camelot's twins click Blizzard's buttons inside them, and Click reaches a
-- hidden button.
--------------------------------------------------------------------------------

local _, addon = ...

local ActionBars = addon.ActionBars
local Suppression = {}
ActionBars.Suppression = Suppression

local OWNER = ActionBars.OWNER

local BLIZZARD_FRAME = {
    { name = "MainActionBar",      method = "alpha" },
    { name = "MultiBarBottomLeft", method = "park" },
    { name = "MultiBarBottomRight", method = "park" },
    { name = "MultiBarRight",      method = "park" },
    { name = "MultiBarLeft",       method = "park" },
    { name = "MultiBar5",          method = "park" },
    { name = "MultiBar6",          method = "park" },
    { name = "MultiBar7",          method = "park" },
    -- The micro and bag twins click these buttons where they are parked.
    { name = "MicroMenuContainer", method = "park" },
    { name = "BagsBar",            method = "park" },
    -- MainActionBar.EndCaps, from the client's MainMenuBarEndCaps template;
    -- the caps have no global names. Camelot draws its own (endcaps.lua).
    { name = "MainActionBar.EndCaps.LeftEndCap",  method = "park", key = "LeftEndCap", optional = true },
    { name = "MainActionBar.EndCaps.RightEndCap", method = "park", key = "RightEndCap", optional = true },
}

local function Resolve(row)
    if not row.key then return _G[row.name] end
    local caps = MainActionBar and MainActionBar.EndCaps
    return caps and caps[row.key] or nil
end

local applied = false
local mouseOff = false

-- The dimmed main bar keeps its twelve buttons, and alpha leaves them
-- clickable under a cluster that has moved away. The native keys never
-- click them: the binding functions call the secure click handler on the
-- button directly, so mouse off costs nothing there. A write on a
-- protected frame, so out of combat only, and once.
local function MouseOff()
    local bar = MainActionBar
    if mouseOff or not bar then return end
    for _, button in ipairs(bar.actionButtons or {}) do
        button:EnableMouse(false)
    end
    mouseOff = true
end

--- Claim every frame in the table, once. A frame that does not exist yet is
--- skipped and the next pass tries again; an optional one, absent from a
--- client that ships no such frame, holds nothing up.
function Suppression.Apply()
    if not ActionBars.IsEnabled() then return end
    local all = true
    for _, row in ipairs(BLIZZARD_FRAME) do
        local frame = Resolve(row)
        if frame then
            if not addon.NativeFrame:IsSuppressed(frame) then
                addon.NativeFrame:Suppress(frame, OWNER, row.method)
            end
        elseif not row.optional then
            all = false
        end
    end
    applied = all
    addon.Events.RunOutOfCombat(MouseOff, "camelotActionBars.mouseOff")
end

function Suppression.IsMouseOff()
    return mouseOff
end

--- Re-assert every claim. NativeFrame skips the re-parent while the Edit Mode
--- manager is open, so entering defers a claim and leaving pays it.
function Suppression.Reassert()
    if not applied then return end
    addon.NativeFrame:Reapply()
end

function Suppression.IsApplied()
    return applied
end

--- The rows /camelot actionbars prints: each frame's parent, alpha, level and
--- shown state; the end caps' rows read their parent from the table.
function Suppression.Report(push)
    local function row(label, frame)
        if not frame then
            push("  %-22s absent", label)
            return
        end
        local parent = frame:GetParent()
        push("  %-22s parent %-24s alpha %.2f level %3d shown %s visible %s",
            label, parent and parent:GetName() or tostring(parent), frame:GetAlpha(),
            frame:GetFrameLevel(), tostring(frame:IsShown()), tostring(frame:IsVisible()))
    end
    for _, r in ipairs(BLIZZARD_FRAME) do
        row((r.key or r.name) .. " (" .. r.method .. ")", Resolve(r))
    end
end
