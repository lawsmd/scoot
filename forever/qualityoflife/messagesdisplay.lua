--------------------------------------------------------------------------------
-- forever/qualityoflife/messagesdisplay.lua
-- Moves UIErrorsFrame by the stored offsets (messages.lua). The frame is a
-- plain MessageFrame on UIParent: no secure template, no Edit Mode system,
-- and nothing in Blizzard's Lua re-anchors it, so one SetPoint holds for the
-- session. DeadlyDebuffFrame hangs off its bottom edge and follows it.
--
-- Ships off: at 0 and 0 the frame is never touched, and a return to 0 and 0
-- after a move puts the XML anchor back.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Messages = addon.QualityOfLife.Messages

local moved = false

--- Anchor the frame at the XML spot plus the offsets.
function Messages.Apply()
    local frame = UIErrorsFrame
    if not frame or (frame.IsForbidden and frame:IsForbidden()) then return end
    local x, y = Messages.Offsets()
    if x == 0 and y == 0 and not moved then return end
    local anchor = Messages.XML_ANCHOR
    frame:ClearAllPoints()
    frame:SetPoint(anchor.point, UIParent, anchor.point, anchor.x + x, anchor.y + y)
    moved = x ~= 0 or y ~= 0
end

addon.Events.OnWorldEntered(function() Messages.Apply() end)

-- After a profile switch the frame takes the new profile's offsets. A resync
-- pass keeps the profile it had.
addon.Profiles.RegisterApplyStep("camelotMessages", function(_, ctx)
    if ctx.initial or ctx.resync then return end
    Messages.Apply()
end, 40)
