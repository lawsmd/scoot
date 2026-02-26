-- Taint Debugging Module for Scoot
-- Tracks all Edit Mode operations and captures stack traces when taint errors occur
local addonName, addon = ...

addon.TaintDebug = addon.TaintDebug or {}
local TD = addon.TaintDebug

-- Configuration
local MAX_LOG_ENTRIES = 200
local TAINT_ERROR_PATTERN = "blocked from an action"

-- State
TD._enabled = false
TD._actionLog = {}  -- { timestamp, action, stack, extra }
TD._errorLog = {}   -- { timestamp, message, stack }
TD._originalErrorHandler = nil

--------------------------------------------------------------------------------
-- Utilities
--------------------------------------------------------------------------------

local function GetTimestamp()
    -- High-precision timestamp using debugprofilestop (microseconds since UI load)
    local ms = debugprofilestop and debugprofilestop() or 0
    local secs = math.floor(ms / 1000)
    local frac = math.floor(ms % 1000)
    return string.format("%d.%03d", secs, frac)
end

local function GetShortStack(skipLevels)
    -- Get a compact stack trace, skipping the logging infrastructure
    local stack = debugstack(skipLevels or 3, 12, 0)
    if not stack then return "no stack" end
    -- Trim to just the relevant parts (remove full paths, keep file:line)
    local lines = {}
    for line in stack:gmatch("[^\n]+") do
        -- Simplify paths: keep just filename:line
        local simplified = line:gsub(".*/Interface/AddOns/Scoot/", "Scoot/")
        simplified = simplified:gsub(".*/Interface/AddOns/", "")
        simplified = simplified:gsub("^%s+", "")  -- trim leading whitespace
        if simplified ~= "" and not simplified:match("taintdebug%.lua") then
            table.insert(lines, simplified)
        end
        if #lines >= 8 then break end  -- Keep stack traces manageable
    end
    return table.concat(lines, "\n    ")
end

local function TrimLog(log)
    while #log > MAX_LOG_ENTRIES do
        table.remove(log, 1)
    end
end

--------------------------------------------------------------------------------
-- Action Logging
--------------------------------------------------------------------------------

function TD.LogAction(action, extra)
    if not TD._enabled then return end
    local entry = {
        timestamp = GetTimestamp(),
        action = action,
        stack = GetShortStack(3),
        extra = extra,
        combat = InCombatLockdown and InCombatLockdown() or false,
    }
    table.insert(TD._actionLog, entry)
    TrimLog(TD._actionLog)
end

function TD.LogError(message, stack)
    local entry = {
        timestamp = GetTimestamp(),
        message = message,
        stack = stack or GetShortStack(3),
        combat = InCombatLockdown and InCombatLockdown() or false,
    }
    table.insert(TD._errorLog, entry)
    TrimLog(TD._errorLog)
end

--------------------------------------------------------------------------------
-- Custom Error Handler
--------------------------------------------------------------------------------

local function ScootErrorHandler(msg)
    -- Always capture taint-related errors, even if full logging is disabled
    local isTaintError = msg and (
        msg:find(TAINT_ERROR_PATTERN) or
        msg:find("forbidden") or
        msg:find("protected function") or
        msg:find("ADDON_ACTION_BLOCKED")
    )
    
    if isTaintError then
        local stack = debugstack(2, 20, 0)  -- Capture deep stack for taint errors
        TD.LogError(msg, stack)
        
        -- Also log to taint.log-style output for correlation
        local timestamp = GetTimestamp()
        local logEntry = string.format(
            "\n=== TAINT ERROR CAPTURED ===\nTime: %s\nMessage: %s\nStack:\n%s\n============================\n",
            timestamp, tostring(msg), tostring(stack)
        )
        
        -- Store for later retrieval
        TD._lastTaintError = {
            timestamp = timestamp,
            message = msg,
            stack = stack,
            recentActions = {},
        }
        
        -- Capture the last N actions for context
        local actionCount = math.min(10, #TD._actionLog)
        for i = #TD._actionLog - actionCount + 1, #TD._actionLog do
            if TD._actionLog[i] then
                table.insert(TD._lastTaintError.recentActions, TD._actionLog[i])
            end
        end
    end
    
    -- Call original handler
    if TD._originalErrorHandler then
        return TD._originalErrorHandler(msg)
    end
end

--------------------------------------------------------------------------------
-- Wrapper Factory for Edit Mode Operations
--------------------------------------------------------------------------------

-- Wrap a function to log its calls
local function WrapWithLogging(name, originalFunc)
    return function(...)
        TD.LogAction(name, nil)
        return originalFunc(...)
    end
end

-- Wrap a method on an object
local function WrapMethodWithLogging(obj, methodName, logName)
    if not obj or type(obj[methodName]) ~= "function" then return end
    local original = obj[methodName]
    obj[methodName] = function(self, ...)
        TD.LogAction(logName or methodName, nil)
        return original(self, ...)
    end
    return original
end

--------------------------------------------------------------------------------
-- Enable/Disable Taint Debugging
--------------------------------------------------------------------------------

function TD.Enable()
    if TD._enabled then
        addon:Print("Taint debugging is already enabled.")
        return
    end
    
    TD._enabled = true
    TD._actionLog = {}
    TD._errorLog = {}
    
    -- Install custom error handler
    TD._originalErrorHandler = geterrorhandler()
    seterrorhandler(ScootErrorHandler)
    
    -- Enable WoW's built-in taint logging (persists in Config.wtf)
    if SetCVar then
        SetCVar("taintLog", "2")  -- Level 2 = verbose
    end
    
    -- Wrap Edit Mode operations (only if not already wrapped)
    if addon.EditMode and not TD._wrappedEditMode then
        TD._wrappedEditMode = true
        
        -- Wrap key functions
        local EM = addon.EditMode
        if EM.SetSetting then
            local orig = EM.SetSetting
            EM.SetSetting = function(frame, settingId, value)
                TD.LogAction("EditMode.SetSetting", string.format("frame=%s id=%s val=%s", 
                    tostring(frame and frame:GetName()), tostring(settingId), tostring(value)))
                return orig(frame, settingId, value)
            end
            TD._origSetSetting = orig
        end
        
        if EM.SaveOnly then
            local orig = EM.SaveOnly
            EM.SaveOnly = function()
                TD.LogAction("EditMode.SaveOnly", nil)
                return orig()
            end
            TD._origSaveOnly = orig
        end
        
        if EM.LoadLayouts then
            local orig = EM.LoadLayouts
            EM.LoadLayouts = function()
                TD.LogAction("EditMode.LoadLayouts", nil)
                return orig()
            end
            TD._origLoadLayouts = orig
        end
        
        if EM.WriteSetting then
            local orig = EM.WriteSetting
            EM.WriteSetting = function(frame, settingId, value, opts)
                TD.LogAction("EditMode.WriteSetting", string.format("frame=%s id=%s val=%s", 
                    tostring(frame and frame:GetName()), tostring(settingId), tostring(value)))
                return orig(frame, settingId, value, opts)
            end
            TD._origWriteSetting = orig
        end
    end
    
    -- Wrap LibEditModeOverride methods
    local LEO = LibStub and LibStub("LibEditModeOverride-1.0", true)
    if LEO and not TD._wrappedLEO then
        TD._wrappedLEO = true
        
        if LEO.SetFrameSetting then
            local orig = LEO.SetFrameSetting
            LEO.SetFrameSetting = function(self, frame, settingId, value)
                TD.LogAction("LEO:SetFrameSetting", string.format("frame=%s id=%s val=%s", 
                    tostring(frame and frame:GetName()), tostring(settingId), tostring(value)))
                return orig(self, frame, settingId, value)
            end
            TD._origLEOSetFrameSetting = orig
        end
        
        if LEO.SaveOnly then
            local orig = LEO.SaveOnly
            LEO.SaveOnly = function(self)
                TD.LogAction("LEO:SaveOnly", nil)
                return orig(self)
            end
            TD._origLEOSaveOnly = orig
        end
    end
    
    addon:Print("Taint debugging ENABLED. WoW taintLog CVar set to 2 (verbose).")
    addon:Print("Use '/scoot taint log' to view captured data.")
    addon:Print("Use '/scoot taint off' to disable.")
end

function TD.Disable()
    if not TD._enabled then
        addon:Print("Taint debugging is not currently enabled.")
        return
    end
    
    TD._enabled = false
    
    -- Restore original error handler
    if TD._originalErrorHandler then
        seterrorhandler(TD._originalErrorHandler)
        TD._originalErrorHandler = nil
    end
    
    -- Restore wrapped Edit Mode functions
    if TD._wrappedEditMode and addon.EditMode then
        local EM = addon.EditMode
        if TD._origSetSetting then EM.SetSetting = TD._origSetSetting end
        if TD._origSaveOnly then EM.SaveOnly = TD._origSaveOnly end
        if TD._origLoadLayouts then EM.LoadLayouts = TD._origLoadLayouts end
        if TD._origWriteSetting then EM.WriteSetting = TD._origWriteSetting end
        TD._wrappedEditMode = false
    end
    
    -- Restore wrapped LEO functions
    local LEO = LibStub and LibStub("LibEditModeOverride-1.0", true)
    if TD._wrappedLEO and LEO then
        if TD._origLEOSetFrameSetting then LEO.SetFrameSetting = TD._origLEOSetFrameSetting end
        if TD._origLEOSaveOnly then LEO.SaveOnly = TD._origLEOSaveOnly end
        TD._wrappedLEO = false
    end
    
    addon:Print("Taint debugging DISABLED.")
    addon:Print("Note: WoW taintLog CVar remains at 2. Set to 0 manually if desired: /console taintLog 0")
end

--------------------------------------------------------------------------------
-- Log Export
--------------------------------------------------------------------------------

function TD.GetFormattedLog()
    local lines = {}
    
    table.insert(lines, "==========================================")
    table.insert(lines, "SCOOT TAINT DEBUG LOG")
    table.insert(lines, "==========================================")
    table.insert(lines, "")
    table.insert(lines, string.format("Logging enabled: %s", tostring(TD._enabled)))
    table.insert(lines, string.format("In combat: %s", tostring(InCombatLockdown and InCombatLockdown())))
    table.insert(lines, string.format("Time (ms since UI load): %s", GetTimestamp()))
    table.insert(lines, "")
    
    -- Last captured taint error (most important!)
    table.insert(lines, "==========================================")
    table.insert(lines, "LAST CAPTURED TAINT ERROR")
    table.insert(lines, "==========================================")
    if TD._lastTaintError then
        local err = TD._lastTaintError
        table.insert(lines, string.format("Time: %s", err.timestamp))
        table.insert(lines, string.format("Message: %s", err.message))
        table.insert(lines, "")
        table.insert(lines, "Stack trace:")
        table.insert(lines, err.stack or "no stack")
        table.insert(lines, "")
        table.insert(lines, "Actions immediately before error:")
        for i, action in ipairs(err.recentActions or {}) do
            table.insert(lines, string.format("  [%s] %s (combat=%s)", 
                action.timestamp, action.action, tostring(action.combat)))
            if action.extra then
                table.insert(lines, string.format("         %s", action.extra))
            end
        end
    else
        table.insert(lines, "No taint errors captured yet.")
    end
    table.insert(lines, "")
    
    -- All error log entries
    table.insert(lines, "==========================================")
    table.insert(lines, "ALL ERROR LOG ENTRIES (" .. #TD._errorLog .. ")")
    table.insert(lines, "==========================================")
    for i, entry in ipairs(TD._errorLog) do
        table.insert(lines, string.format("[%s] (combat=%s) %s", 
            entry.timestamp, tostring(entry.combat), entry.message))
        if entry.stack then
            table.insert(lines, "  Stack:")
            for stackLine in entry.stack:gmatch("[^\n]+") do
                table.insert(lines, "    " .. stackLine)
            end
        end
        table.insert(lines, "")
    end
    
    -- Action log
    table.insert(lines, "==========================================")
    table.insert(lines, "ACTION LOG (" .. #TD._actionLog .. " entries)")
    table.insert(lines, "==========================================")
    for i, entry in ipairs(TD._actionLog) do
        table.insert(lines, string.format("[%s] %s (combat=%s)", 
            entry.timestamp, entry.action, tostring(entry.combat)))
        if entry.extra then
            table.insert(lines, string.format("  Details: %s", entry.extra))
        end
        if entry.stack then
            table.insert(lines, "  Stack:")
            for stackLine in entry.stack:gmatch("[^\n]+") do
                table.insert(lines, "    " .. stackLine)
            end
        end
        table.insert(lines, "")
    end
    
    -- Instructions for finding taint.log
    table.insert(lines, "==========================================")
    table.insert(lines, "ADDITIONAL TAINT DATA")
    table.insert(lines, "==========================================")
    table.insert(lines, "WoW's taint.log file location:")
    table.insert(lines, "  _retail_/Logs/taint.log")
    table.insert(lines, "")
    table.insert(lines, "To enable verbose WoW taint logging manually:")
    table.insert(lines, "  /console taintLog 2")
    table.insert(lines, "")
    table.insert(lines, "To disable WoW taint logging:")
    table.insert(lines, "  /console taintLog 0")
    
    return table.concat(lines, "\n")
end

function TD.ShowLog()
    local logText = TD.GetFormattedLog()
    if addon.DebugShowWindow then
        addon.DebugShowWindow("Scoot Taint Debug Log", logText)
    elseif addon.DebugCopyWindow then
        -- Fallback to existing debug window
        local f = addon.DebugCopyWindow
        if f.title then f.title:SetText("Scoot Taint Debug Log") end
        if f.EditBox then f.EditBox:SetText(logText) end
        f:Show()
        if f.EditBox then f.EditBox:HighlightText(); f.EditBox:SetFocus() end
    else
        addon:Print("Debug window not available.")
    end
end

function TD.ClearLog()
    TD._actionLog = {}
    TD._errorLog = {}
    TD._lastTaintError = nil
    addon:Print("Taint debug logs cleared.")
end

--------------------------------------------------------------------------------
-- Status Check
--------------------------------------------------------------------------------

function TD.Status()
    addon:Print("Taint Debug Status:")
    addon:Print(string.format("  Enabled: %s", tostring(TD._enabled)))
    addon:Print(string.format("  Action log entries: %d", #TD._actionLog))
    addon:Print(string.format("  Error log entries: %d", #TD._errorLog))
    addon:Print(string.format("  Last taint error: %s", TD._lastTaintError and TD._lastTaintError.timestamp or "none"))
    
    -- Check WoW's taintLog CVar
    local taintLogCVar = GetCVar and GetCVar("taintLog") or "unknown"
    addon:Print(string.format("  WoW taintLog CVar: %s", taintLogCVar))
end

--------------------------------------------------------------------------------
-- Slash Command Handler
--------------------------------------------------------------------------------

function TD.HandleSlashCommand(args)
    local subcmd = args[2] and string.lower(args[2]) or ""
    
    if subcmd == "on" or subcmd == "enable" then
        TD.Enable()
    elseif subcmd == "off" or subcmd == "disable" then
        TD.Disable()
    elseif subcmd == "log" or subcmd == "show" then
        TD.ShowLog()
    elseif subcmd == "clear" then
        TD.ClearLog()
    elseif subcmd == "status" then
        TD.Status()
    else
        addon:Print("Taint Debug Commands:")
        addon:Print("  /scoot taint on     - Enable taint debugging")
        addon:Print("  /scoot taint off    - Disable taint debugging")
        addon:Print("  /scoot taint log    - Show captured taint data (copyable)")
        addon:Print("  /scoot taint clear  - Clear all logs")
        addon:Print("  /scoot taint status - Show current status")
    end
end

