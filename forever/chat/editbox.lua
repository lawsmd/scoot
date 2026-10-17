--------------------------------------------------------------------------------
-- forever/chat/editbox.lua
-- Blizzard's edit box under Camelot's window. The box stays Blizzard's,
-- ChatFrame1EditBox, because the slash commands that act on the world live
-- in a table private to Blizzard's chat addon and an addon-made box runs its
-- Enter press tainted. Its own OnLoad parents it to UIParent and anchors it
-- to ChatFrame1's bottom edge; this file re-anchors it to the holder, puts
-- the Text settings' font on it and scales it with the holder.
--
-- Nothing else touches the box. No HookScript on it, no hook on UpdateHeader
-- or AddHistoryLine, no SetAttribute, no SetText: the chat-state functions
-- write the box's chatType attribute after they dispatch its scripts, every
-- send reads that attribute back, and a tainted write there makes every
-- later send a tainted caller that a chat messaging lockdown swallows. No
-- alpha write either: Blizzard writes the box's alpha on every activate and
-- deactivate, and the idle box is hidden in the classic chat style.
--
-- The EventRegistry callbacks the box fires run through securecallfunction
-- on 12.1.5, but an earlier build showed a callback tainting its dispatch
-- loop, so they stay behind chat.editBoxCallbacks, off, until the beta has
-- answered; while on they only record the box's state for /camelot chat.
--------------------------------------------------------------------------------

local addonName, addon = ...

local CR = addon.ChatReplica
local Style = CR.Style

local EditBox = {}
CR.EditBox = EditBox

-- Blizzard's own offsets: TOPLEFT of the frame's BOTTOMLEFT at (-5, -2),
-- RIGHT to the scroll bar's RIGHT at 8 (FloatingChatFrame.xml:540-545).
local LEFT_INSET = -5
local RIGHT_INSET = 8

local state = { shown = nil, focused = nil, sends = 0, callbacks = false }

local function box()
    return _G.ChatFrame1EditBox
end

--- The anchors: the holder's bottom corners, or the strip's top corners when
--- the box sits above the tabs.
function EditBox.Anchor()
    local b, holder = box(), Style.Frame()
    if not (b and holder) then return end
    local gutter = Style.SCROLL_GUTTER
    pcall(function()
        b:ClearAllPoints()
        if Style.EditBoxAbove() then
            local strip = holder.Strip
            b:SetPoint("BOTTOMLEFT", strip, "TOPLEFT", LEFT_INSET, Style.EDIT_BOX_GAP)
            b:SetPoint("BOTTOMRIGHT", strip, "TOPRIGHT", gutter + RIGHT_INSET - 7, Style.EDIT_BOX_GAP)
        else
            b:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", LEFT_INSET, -Style.EDIT_BOX_GAP)
            b:SetPoint("TOPRIGHT", holder, "BOTTOMRIGHT", gutter + RIGHT_INSET - 7, -Style.EDIT_BOX_GAP)
        end
    end)
end

--- The Text settings' font on the box and on its header string.
function EditBox.ApplyFont()
    local b = box()
    if not b then return end
    local face, size, style = Style.FontFace(), Style.FontSize(), Style.FontStyle()
    pcall(addon.ApplyFontStyle, b, face, size, style)
    local header = _G[b:GetName() .. "Header"]
    if header then pcall(addon.ApplyFontStyle, header, face, size, style) end
end

--- The holder's scale, so the box's text and height follow Scale and the
--- adapter's scale channel.
function EditBox.SetScale(scale)
    local b = box()
    if not b or type(scale) ~= "number" then return end
    pcall(b.SetScale, b, scale)
end

function EditBox.Apply()
    local holder = Style.Frame()
    if not (box() and holder) then return end
    EditBox.Anchor()
    EditBox.ApplyFont()
    EditBox.SetScale(holder:GetScale())
    EditBox.ApplyCallbacks()
end

--------------------------------------------------------------------------------
-- The EventRegistry callbacks
--------------------------------------------------------------------------------

local CALLBACKS = {
    ["ChatFrame.OnEditBoxShow"] = function() state.shown = true end,
    ["ChatFrame.OnEditBoxHide"] = function() state.shown = false end,
    ["ChatFrame.OnEditBoxFocusGained"] = function() state.focused = true end,
    ["ChatFrame.OnEditBoxFocusLost"] = function() state.focused = false end,
    ["ChatFrame.OnEditBoxPreSendText"] = function() state.sends = state.sends + 1 end,
}

function EditBox.ApplyCallbacks()
    local want = Style.Get("editBoxCallbacks") == true
    if want == state.callbacks then return end
    local registry = EventRegistry
    if not (registry and registry.RegisterCallback) then return end
    state.callbacks = want
    for event, fn in pairs(CALLBACKS) do
        if want then
            pcall(registry.RegisterCallback, registry, event, fn, CR.OWNER)
        elseif registry.UnregisterCallback then
            pcall(registry.UnregisterCallback, registry, event, CR.OWNER)
        end
    end
end

--- Lines for /camelot chat.
function EditBox.Describe(push)
    local b = box()
    if not b then
        push("  edit box: absent")
        return
    end
    local ok, text = pcall(function()
        local parent = b:GetParent()
        local point, rel, relPoint, x, y = b:GetPoint(1)
        return string.format("parent %s, point %s to %s %s (%.1f, %.1f), scale %.2f, strata %s, shown %s",
            parent and parent:GetName() or tostring(parent), tostring(point),
            rel and rel.GetName and rel:GetName() or tostring(rel), tostring(relPoint), x or 0, y or 0,
            b:GetScale(), tostring(b:GetFrameStrata()), tostring(b:IsShown()))
    end)
    push("  edit box: %s", ok and text or ("unreadable: " .. tostring(text)))
    local okP, isProtected, explicitly = pcall(b.IsProtected, b)
    push("  edit box protected: %s", okP and string.format("%s (explicit %s)", tostring(isProtected), tostring(explicitly)) or "unreadable")
    push("  edit box callbacks: %s; shown %s, focused %s, sends %d", tostring(state.callbacks),
        tostring(state.shown), tostring(state.focused), state.sends)
end
