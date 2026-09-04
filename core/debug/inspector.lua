-- inspector.lua - Table Inspector copy support
local addonName, addon = ...

--[[----------------------------------------------------------------------------
    Table Inspector copy support

    Purpose:
      - Attach a "Copy" button to Blizzard's Table Inspector (/tinspect)
      - Provide /scoot attr command to dump Table Inspector or Frame Stack content

    Usage:
      /scoot attr
----------------------------------------------------------------------------]]--

local function SafeCall(fn, ...)
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
end

-- Secret value handling: some getters return "secret" values that cannot be
-- used in string operations, comparisons, or arithmetic. Detection is done by
-- trying the operation in a pcall. IMPORTANT: Even comparing a secret to nil
-- can fail, so ALL operations must be wrapped in pcall.

-- Returns a guaranteed-safe string, or fallback if the value is a secret
-- IMPORTANT: Even tostring(secret) can return a "tainted" value that
-- passes basic checks but fails in table.concat. The result must be verified
-- is a real Lua string type AND can be used in string operations.
local function safeString(value, fallback)
    fallback = fallback or "<secret>"
    local result
    local ok = pcall(function()
        -- Check if value is nil (comparison can fail on secrets)
        if value == nil then return end
        -- Try to convert to string
        local str = tostring(value)
        -- Verify it is a string type (not a secret wearing one)
        if type(str) ~= "string" then return end
        -- Verify it can be used in string operations
        local test = str .. ""
        -- Verify it has reasonable content (not a weird secret representation)
        if #test < 0 then return end -- length check
        -- Final test: can it be formatted?
        local formatted = string.format("%s", str)
        if type(formatted) ~= "string" then return end
        result = str
    end)
    -- Double-check the result is usable
    if ok and result and type(result) == "string" then
        -- One more pcall to verify the result is truly usable
        local finalOk = pcall(function()
            local _ = result .. ""
            local _ = string.format("%s", result)
        end)
        if finalOk then
            return result
        end
    end
    return fallback
end

-- Alias for compatibility
local function safeToString(value)
    return safeString(value, "<secret>")
end

-- Returns true only if the value can be safely used as a string
local function isUsableValue(value)
    local ok = pcall(function()
        if value == nil then return end
        local str = tostring(value)
        local _ = str .. ""
    end)
    return ok
end

-- Alias for compatibility
local function isUsableString(value)
    return isUsableValue(value)
end

local function GetDebugNameSafe(obj)
    if not obj then return nil end
    local ok, result = pcall(function()
        if not obj.GetDebugName then return nil end
        local name = obj:GetDebugName()
        if name == nil then return nil end
        -- Verify it's usable
        local _ = name .. ""
        return name
    end)
    if ok and result then
        return result
    end
end

local function TableInspectorBuildDump(focusedTable)
    if not focusedTable then return "[No Table Selected]" end

    local out = {}
    local function push(line)
        local safeLine = safeString(line, "[unreadable]")
        if type(safeLine) == "string" then
            table.insert(out, safeLine)
        end
    end

    -- Instead of pairs() iteration (which returns secrets),
    -- call specific known frame methods directly. These are more likely to work.

    push("Frame Information")
    push(string.rep("-", 60))

    -- Try to get basic identity info via explicit method calls
    local function tryGet(label, fn)
        local ok, val = pcall(fn)
        if ok and val ~= nil then
            -- Verify the value is usable (not a secret)
            local strOk, str = pcall(function()
                local s = tostring(val)
                local _ = s .. "" -- verify string ops work
                return s
            end)
            if strOk and str then
                push(label .. ": " .. str)
                return true
            end
        end
        return false
    end

    -- Identity
    tryGet("Name", function() return focusedTable:GetName() end)
    tryGet("DebugName", function() return focusedTable:GetDebugName() end)
    tryGet("ObjectType", function() return focusedTable:GetObjectType() end)

    -- Dimensions (these often work)
    tryGet("Width", function() return focusedTable:GetWidth() end)
    tryGet("Height", function() return focusedTable:GetHeight() end)
    tryGet("Scale", function() return focusedTable:GetScale() end)
    tryGet("EffectiveScale", function() return focusedTable:GetEffectiveScale() end)
    tryGet("Alpha", function() return focusedTable:GetAlpha() end)

    -- Visibility/State
    tryGet("IsShown", function() return focusedTable:IsShown() end)
    tryGet("IsVisible", function() return focusedTable:IsVisible() end)
    tryGet("IsProtected", function() return focusedTable:IsProtected() end)
    tryGet("IsForbidden", function() return focusedTable:IsForbidden() end)

    -- Frame Level/Strata
    tryGet("FrameLevel", function() return focusedTable:GetFrameLevel() end)
    tryGet("FrameStrata", function() return focusedTable:GetFrameStrata() end)

    -- Parent info
    local parent = SafeCall(function() return focusedTable:GetParent() end)
    if parent then
        tryGet("Parent", function() return parent:GetDebugName() or parent:GetName() or "<unnamed>" end)
    end

    -- Build ancestry chain (this is the most useful part for copying frame paths)
    local ancestry = {}
    local current = focusedTable
    local depth = 0
    while current and depth < 20 do
        local name = GetDebugNameSafe(current)
        table.insert(ancestry, 1, name or "<unnamed>")
        current = SafeCall(function() return current:GetParent() end)
        depth = depth + 1
    end

    -- Add a clean "Full Path" line at the top for easy copying
    if #ancestry > 0 then
        push("")
        push("Full Path (for copying):")
        local pathOk, fullPath = pcall(table.concat, ancestry, ".")
        if pathOk and fullPath then
            push(fullPath)
        end
    end

    push("")
    push("Ancestry (indented):")
    for i, name in ipairs(ancestry) do
        local indent = string.rep("  ", i - 1)
        push(indent .. name)
    end

    -- Anchor points (often partially readable)
    -- IMPORTANT: numPoints might be a secret - extract as safe number inside pcall
    local safeNumPoints = 0
    pcall(function()
        local np = focusedTable:GetNumPoints()
        if np and type(np) == "number" and np > 0 then
            safeNumPoints = np
        end
    end)
    if safeNumPoints > 0 then
        push("")
        push("Anchor Points:")
        for i = 1, safeNumPoints do
            local point, relTo, relPoint, x, y = SafeCall(function()
                return focusedTable:GetPoint(i)
            end)
            if point then
                local parts = {}
                -- Point name (usually works)
                local pointOk, pointStr = pcall(tostring, point)
                if pointOk then table.insert(parts, pointStr) end

                -- Relative frame
                if relTo then
                    local relName = GetDebugNameSafe(relTo) or "<frame>"
                    table.insert(parts, "-> " .. relName)
                end

                -- Relative point (may be secret)
                if relPoint then
                    local rpOk, rpStr = pcall(tostring, relPoint)
                    if rpOk then table.insert(parts, "(" .. rpStr .. ")") end
                end

                -- Offsets (often secrets)
                if x and y and type(x) == "number" and type(y) == "number" then
                    local offsetOk, offsetStr = pcall(string.format, "%.1f, %.1f", x, y)
                    if offsetOk then table.insert(parts, "offset: " .. offsetStr) end
                end

                if #parts > 0 then
                    local lineOk, line = pcall(table.concat, parts, " ")
                    if lineOk then push("  [" .. i .. "] " .. line) end
                end
            end
        end
    end

    -- Children (GetDebugName usually works on child references)
    -- Wrap everything in pcall to handle any secret contamination
    pcall(function()
        local children = { focusedTable:GetChildren() }
        if children and #children > 0 then
            push("")
            push("Children:")
            for _, child in ipairs(children) do
                local childName = GetDebugNameSafe(child)
                if childName then
                    push("  " .. childName)
                end
            end
        end
    end)

    -- Regions
    pcall(function()
        local regions = { focusedTable:GetRegions() }
        if regions and #regions > 0 then
            push("")
            push("Regions:")
            for _, region in ipairs(regions) do
                local regionName = GetDebugNameSafe(region)
                local regionType = nil
                pcall(function() regionType = region:GetObjectType() end)
                if regionName or regionType then
                    local desc = regionName or "<unnamed>"
                    if regionType then desc = desc .. " (" .. regionType .. ")" end
                    push("  " .. desc)
                end
            end
        end
    end)

    -- Final assembly
    local ok, result = pcall(table.concat, out, "\n")
    if ok and type(result) == "string" then
        return result
    end
    return "[Error building dump - secret values detected]"
end

-- Separate copy window for Table Inspector (reuse pattern from ShowDebugCopyWindow)
local function ShowTableInspectorCopyWindow(title, text)
    if not addon.TableInspectorCopyWindow then
        local f = CreateFrame("Frame", "ScootTableInspectorCopyWindow", UIParent, "BasicFrameTemplateWithInset")
        f:SetSize(740, 520)
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
        eb:SetWidth(680)
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
        addon.TableInspectorCopyWindow = f
    end
    local f = addon.TableInspectorCopyWindow
    if f.title then f.title:SetText(title or "Copied Output") end
    if f.EditBox then f.EditBox:SetText(text or "") end
    f:Show()
    -- Defer focus/highlight to avoid scroll system taint
    C_Timer.After(0, function()
        if f.EditBox and f:IsShown() then
            f.EditBox:HighlightText()
            f.EditBox:SetFocus()
        end
    end)
end

-- Extract text directly from FrameStackTooltip's displayed lines
-- This reads what Blizzard is showing, bypassing GetDebugName() secrets
-- IMPORTANT: Must be defined before AttachTableInspectorCopyButton which calls it
--
-- CRITICAL: GetText() returns secret values even on Blizzard's own tooltips.
-- All operations (including type() checks) must be wrapped in pcall because
-- comparing or type-checking a secret value throws an error.
local function ExtractFrameStackTooltipText()
    local fs = _G.FrameStackTooltip
    if not fs then return nil end

    local lines = {}

    -- Helper: safely extract text from a FontString, returns nil if secret/unavailable
    local function safeGetText(fontString)
        if not fontString then return nil end
        local result = nil
        pcall(function()
            if not fontString.GetText then return end
            local raw = fontString:GetText()
            -- ALL checks must be inside pcall because type()/comparisons fail on secrets
            if raw == nil then return end
            if type(raw) ~= "string" then return end
            if raw == "" then return end
            -- Final verification: try string operation
            local _ = raw .. ""
            result = raw
        end)
        return result
    end

    -- Try numbered text lines like GameTooltip pattern (most reliable)
    -- FrameStackTooltip has TextLeft1, TextLeft2, etc.
    for i = 1, 30 do
        local leftLine = fs["TextLeft" .. i] or _G["FrameStackTooltipTextLeft" .. i]
        local text = safeGetText(leftLine)
        if text then
            table.insert(lines, text)
        end
    end

    -- Also try LinesContainer if present and nothing was found above
    local linesContainer = fs.LinesContainer
    if linesContainer and #lines == 0 then
        pcall(function()
            local children = { linesContainer:GetChildren() }
            for _, child in ipairs(children) do
                if child and child.GetRegions then
                    local regions = { child:GetRegions() }
                    for _, region in ipairs(regions) do
                        if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                            local text = safeGetText(region)
                            if text then
                                table.insert(lines, text)
                            end
                        end
                    end
                end
            end
        end)
    end

    if #lines > 0 then
        local ok, result = pcall(table.concat, lines, "\n")
        return ok and result or nil
    end
end

-- Track if button is attached
local tableInspectorCopyButtonAttached = false

local function AttachTableInspectorCopyButton()
    if tableInspectorCopyButtonAttached then return end

    local parent = _G.TableAttributeDisplay
    if not parent then return end

    tableInspectorCopyButtonAttached = true

    local btn = CreateFrame("Button", "ScootAttrCopyButton", parent, "UIPanelButtonTemplate")
    btn:SetSize(60, 22)
    btn:SetText("Copy")
    btn:SetPoint("TOPRIGHT", parent, "BOTTOMRIGHT", 0, -2)

    btn:SetScript("OnClick", function()
        local focused = parent.focusedTable
        if not focused then return end

        local dump = TableInspectorBuildDump(focused)
        ShowTableInspectorCopyWindow("Table Attributes", dump)
    end)
end

function addon.AttachTableInspectorCopyButton()
    AttachTableInspectorCopyButton()
end

-- Expose the attribute dump logic for the slash command (/scoot attr)
local function DumpTableAttributes()
    local parent = _G.TableAttributeDisplay
    if parent and parent:IsShown() and parent.focusedTable then
        local dump = TableInspectorBuildDump(parent.focusedTable)
        -- Title is now hardcoded in dump; use simple title for window
        ShowTableInspectorCopyWindow("Table Attributes", dump)
        return true
    end
    -- Fallback: if framestack is active, try to inspect highlight and dump
    local fs = _G.FrameStackTooltip
    if fs and fs.highlightFrame then
        local dump = TableInspectorBuildDump(fs.highlightFrame)
        local name = GetDebugNameSafe(fs.highlightFrame) or "Frame"
        -- Wrap title construction in pcall for safety
        local ok, title = pcall(function() return "Frame Attributes - " .. name end)
        ShowTableInspectorCopyWindow(ok and title or "Frame Attributes", dump)
        return true
    end
    return false
end

addon:RegisterSlashCommand({
    name = "attr", help = "dump the inspected Table Inspector table or Frame Stack frame",
    handler = function()
        if not DumpTableAttributes() then
            addon:Print("No Table Inspector window or highlight frame found to dump.")
        end
    end,
})
