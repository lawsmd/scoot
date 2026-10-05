-- EmptyState.lua - the strip a list shows in place of rows: a centred
-- message in the desc role, dim, and a busy state that ticks dots after it
-- while something is on its way.
--
-- opts:
--   parent      required
--   text        the message
--   fontRole    default "desc"
--   padX        what the text keeps off the frame's edges; default 16
--   period      the dots' step in seconds; default 0.4
--
-- Returns a frame the caller anchors, carrying _text and the methods
-- SetMessage(text), GetMessage(), SetBusy(busy, text). The ticker stops
-- while the frame is hidden and starts again when it shows busy.
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Controls = addon.UI.Controls or {}
local Controls = addon.UI.Controls

local DOTS = { ".", "..", "..." }

function Controls.CreateEmptyState(opts)
    if not opts or not opts.parent then return nil end
    local Theme = addon.UI.Theme
    local padX = opts.padX or 16
    local period = opts.period or 0.4

    local frame = CreateFrame("Frame", opts.name, opts.parent)
    local text = frame:CreateFontString(nil, "OVERLAY")
    Theme:ApplyFont(text, opts.fontRole or "desc")
    text:SetPoint("TOPLEFT", frame, "TOPLEFT", padX, 0)
    text:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -padX, 0)
    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")
    text:SetWordWrap(true)
    local dr, dg, db = Theme:GetDimTextColor()
    text:SetTextColor(dr, dg, db, 1)
    frame._text = text
    frame._message = opts.text or ""
    frame._busy = false
    frame._phase = 0

    local function Paint()
        if frame._busy then
            text:SetText(frame._message .. DOTS[(frame._phase % #DOTS) + 1])
        else
            text:SetText(frame._message)
        end
    end

    local function Stop()
        if frame._ticker then
            frame._ticker:Cancel()
            frame._ticker = nil
        end
    end

    local function Start()
        if frame._ticker or not frame:IsShown() then return end
        frame._ticker = C_Timer.NewTicker(period, function()
            frame._phase = frame._phase + 1
            Paint()
        end)
    end

    function frame:SetMessage(value)
        self._message = value or ""
        Paint()
    end

    function frame:GetMessage()
        return self._message
    end

    function frame:SetBusy(busy, value)
        self._busy = busy and true or false
        if value ~= nil then self._message = value end
        self._phase = 0
        if self._busy then Start() else Stop() end
        Paint()
    end

    frame:HookScript("OnHide", Stop)
    frame:HookScript("OnShow", function(self)
        if self._busy then Start() end
    end)

    Paint()
    return frame
end
