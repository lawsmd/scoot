-- core.lua - Debug output: DebugLines and the copy window every dump opens
local addonName, addon = ...

local SECRET = "<secret>"

-- One value screened for the copy window: nil drops, anything else becomes a
-- string, a secret reads as "<secret>". tostring returns a secret string on a
-- secret scalar without throwing (secrets.md); a secret frame is unmeasured, so
-- tostring is pcall-wrapped. A secret string passes type() and would crash
-- table.concat, so plainString screens it.
local function plain(v)
    local t = type(v)
    if t == "nil" then return nil end
    if t ~= "string" then
        local ok, s = pcall(tostring, v)
        if not ok then return SECRET end
        v = s
    end
    return addon.SecretSafe.plainString(v) or SECRET
end

-- Line builder for a dump. Leading arguments seed the table. Returns the
-- plain table (index it, take #lines, hand it to DebugShowWindow) and one
-- closure: push(s) appends a screened line; push(fmt, ...) formats first, so
-- a literal % in a line with no arguments passes through.
function addon.DebugLines(...)
    local lines = { ... }
    local function push(s, ...)
        if select("#", ...) > 0 then s = string.format(s, ...) end
        s = plain(s)
        if s ~= nil then lines[#lines + 1] = s end
    end
    return lines, push
end

local function ShowDebugCopyWindow(title, text)
    if not addon.DebugCopyWindow then
        local f = CreateFrame("Frame", "ScootDebugCopyWindow", UIParent, "BasicFrameTemplateWithInset")
        f:SetSize(780, 540)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function() f:StartMoving() end)
        f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.title:SetPoint("LEFT", f.TitleBg, "LEFT", 6, 0)
        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -36)
        scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 42)
        local eb = CreateFrame("EditBox", nil, scroll)
        eb:SetMultiLine(true); eb:SetFontObject(ChatFontNormal); eb:SetAutoFocus(false)
        eb:SetWidth(720)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        scroll:SetScrollChild(eb)
        f.EditBox = eb
        local copyBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        copyBtn:SetSize(100, 22)
        copyBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 12)
        copyBtn:SetText("Copy All")
        copyBtn:SetScript("OnClick", function()
            f.EditBox:HighlightText()
            f.EditBox:SetFocus()
        end)
        local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        closeBtn:SetSize(80, 22)
        closeBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
        closeBtn:SetText(CLOSE or "Close")
        closeBtn:SetScript("OnClick", function() f:Hide() end)
        addon.DebugCopyWindow = f
    end
    local f = addon.DebugCopyWindow
    if f.title then f.title:SetText(title or "Scoot Debug") end
    if f.EditBox then f.EditBox:SetText(text or "") end
    f:Show()
    -- Defer focus/highlight to avoid scroll system taint.
    -- These operations trigger Blizzard's scroll callbacks which can
    -- encounter secret values if called synchronously from addon context
    C_Timer.After(0, function()
        if f.EditBox and f:IsShown() then
            f.EditBox:HighlightText()
            f.EditBox:SetFocus()
        end
    end)
end

function addon.DebugShowWindow(title, payload)
    if type(payload) == "table" then
        local ok, text = pcall(table.concat, payload, "\n")
        payload = ok and text or ("[Error building dump: " .. tostring(text) .. "]")
    end
    ShowDebugCopyWindow(title, payload or "")
end
