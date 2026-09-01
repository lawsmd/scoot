-- secretsafe.lua - pcall wrappers for Blizzard "secret value" safety
local addonName, addon = ...

addon.SecretSafe = addon.SecretSafe or {}
local SS = addon.SecretSafe

-- Nil-safe, secret-safe tonumber with arithmetic test.
-- Returns nil if the value is secret or not convertible to a number.
function SS.safeNumber(v)
    local okNil, isNil = pcall(function() return v == nil end)
    if okNil and isNil then return nil end
    local n = v
    if type(n) ~= "number" then
        local ok, conv = pcall(tonumber, n)
        if ok and type(conv) == "number" then
            n = conv
        else
            return nil
        end
    end
    local ok = pcall(function() return n + 0 end)
    if not ok then
        return nil
    end
    return n
end

-- Like safeNumber but returns 0 instead of nil (for offset values).
function SS.safeOffset(v)
    local okNil, isNil = pcall(function() return v == nil end)
    if okNil and isNil then return 0 end
    local n = v
    if type(n) ~= "number" then
        local ok, conv = pcall(tonumber, n)
        if ok and type(conv) == "number" then
            n = conv
        else
            return 0
        end
    end
    local ok = pcall(function() return n + 0 end)
    if not ok then
        return 0
    end
    return n
end

-- Safe string check for anchor tokens ("CENTER", "TOPLEFT", etc.).
-- Returns fallback if the value is not a usable string.
function SS.safePointToken(v, fallback)
    if type(v) ~= "string" then return fallback end
    local ok, nonEmpty = pcall(function() return v ~= "" end)
    if ok and nonEmpty then return v end
    return fallback
end

-- Safe GetWidth with StatusBar exclusion.
-- StatusBars can trigger internal update code during GetWidth() that
-- surfaces secret value errors. Returns nil if width is unavailable.
function SS.safeGetWidth(frame)
    if not frame or not frame.GetWidth then return nil end
    if frame.GetObjectType then
        local okT, t = pcall(frame.GetObjectType, frame)
        if okT and t == "StatusBar" then
            return nil
        end
    end
    local ok, w = pcall(frame.GetWidth, frame)
    if not ok then return nil end
    if type(w) ~= "number" then return nil end
    local okArith = pcall(function() return w + 0 end)
    if not okArith then return nil end
    return w
end

-- pcall-guarded function call with fallback.
function SS.safeGetter(func, fallback)
    if not func then return fallback end
    local ok, result = pcall(func)
    return ok and result or fallback
end

-- safeGetter + safeNumber, defaults to 0.
function SS.safeDimension(func)
    local value = SS.safeGetter(func, nil)
    local num = SS.safeNumber(value)
    return num or 0
end

-- Screen a frame handle that arrived from Blizzard.
-- Globals we hook (CooldownFrame_Set, CompactUnitFrame_*, UnitFramePortrait_Update) are
-- also called by Blizzard's secure-environment and forbidden-object-table code. Those
-- frames reach our tainted callbacks as secret values. Indexing one throws, comparing one
-- throws, and using one as a table key marks that table secret forever.
-- type() and issecretvalue() are the only operations legal on a secret, and a truthiness
-- test is not proof of plainness, so screen with both.
function SS.plainFrame(v)
    if type(v) ~= "table" then return nil end
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, v)
        if not ok or secret then return nil end
    end
    return v
end

-- Same screen for a string read off a Blizzard frame. A secret string throws on every
-- string.* call except concat and format, so :match and table-key use both need this.
function SS.plainString(v)
    if type(v) ~= "string" then return nil end
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, v)
        if not ok or secret then return nil end
    end
    return v
end
