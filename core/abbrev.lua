-- abbrev.lua - Shared number abbreviation
--
-- Two halves, promoted from damagemetersY/data.lua (refactor #31):
--   * FormatCompactNumber: the pure-Lua floor-pair formatter that mirrors the
--     engine's AbbreviateNumbers breakpoint semantics.
--   * CreateAbbrevConfig + GetDefaultAbbrevBreakpoints: the engine-config
--     builder with its restricted-validation retry ladder.
-- Breakpoint tables themselves stay per-consumer where the display shape is a
-- deliberate choice (UnitFramesZ uses lowercase suffixes, a 1e4 base tier, and
-- three fraction sub-tiers per magnitude).
local _, addon = ...

local function FloorPart(n, sig, frac)
    local v = math.floor(n / sig) / frac
    if frac > 1 then
        local s = string.format("%.1f", v)
        return (s:gsub("%.0$", ""))  -- "2.0" → "2", matching engine output
    end
    return string.format("%d", v)
end

-- Mirrors the AbbreviateNumbers breakpoint config (floor-pair semantics).
-- Keep in sync with GetDefaultAbbrevBreakpoints below.
function addon.FormatCompactNumber(n)
    n = tonumber(n)
    if not n or n ~= n or n <= 0 then return "0" end
    if n >= 1e10 then return FloorPart(n, 1e9, 1) .. "B"
    elseif n >= 1e9 then return FloorPart(n, 1e8, 10) .. "B"
    elseif n >= 1e7 then return FloorPart(n, 1e6, 1) .. "M"
    elseif n >= 1e6 then return FloorPart(n, 1e5, 10) .. "M"
    elseif n >= 1e4 then return FloorPart(n, 1e3, 1) .. "K"
    elseif n >= 1e3 then return FloorPart(n, 1e2, 10) .. "K"
    else return string.format("%d", math.floor(n)) end
end

local function BaseBreakpoint()
    -- Floors sub-1K values to whole numbers ("999", not "999.9898...").
    return { breakpoint = 1, abbreviation = "",
             significandDivisor = 1, fractionDivisor = 1,
             abbreviationIsGlobal = false }
end

-- The default breakpoint table: live engine defaults when available, a
-- hand-authored mirror otherwise, plus the base entry that floors sub-1K
-- floats. Every field is required -- omitting significandDivisor is the old
-- DMY sub-1K bug (CreateAbbreviateConfig raised a validation error that pcall
-- swallowed, and the engine's default breakpoints have no base entry, so
-- sub-1K floats passed through raw).
function addon.GetDefaultAbbrevBreakpoints()
    local t
    -- Prefer live engine defaults (locale-correct); copy, never mutate the API table.
    if C_StringUtil and C_StringUtil.GetDefaultAbbreviationBreakpoints then
        local ok, defaults = pcall(C_StringUtil.GetDefaultAbbreviationBreakpoints)
        if ok and type(defaults) == "table" and #defaults > 0 then
            t = {}
            for i, bp in ipairs(defaults) do
                t[i] = { breakpoint = bp.breakpoint, abbreviation = bp.abbreviation,
                         significandDivisor = bp.significandDivisor,
                         fractionDivisor = bp.fractionDivisor,
                         abbreviationIsGlobal = bp.abbreviationIsGlobal }
            end
        end
    end
    if not t then
        -- Hand-authored mirror of the classic paired defaults (enUS-style)
        t = {
            { breakpoint = 1e10, abbreviation = "B", significandDivisor = 1e9, fractionDivisor = 1,  abbreviationIsGlobal = false },
            { breakpoint = 1e9,  abbreviation = "B", significandDivisor = 1e8, fractionDivisor = 10, abbreviationIsGlobal = false },
            { breakpoint = 1e7,  abbreviation = "M", significandDivisor = 1e6, fractionDivisor = 1,  abbreviationIsGlobal = false },
            { breakpoint = 1e6,  abbreviation = "M", significandDivisor = 1e5, fractionDivisor = 10, abbreviationIsGlobal = false },
            { breakpoint = 1e4,  abbreviation = "K", significandDivisor = 1e3, fractionDivisor = 1,  abbreviationIsGlobal = false },
            { breakpoint = 1e3,  abbreviation = "K", significandDivisor = 1e2, fractionDivisor = 10, abbreviationIsGlobal = false },
        }
    end
    t[#t + 1] = BaseBreakpoint()
    -- NumberAbbrevOptions docs: "Order these from largest to smallest."
    table.sort(t, function(a, b) return a.breakpoint > b.breakpoint end)
    return t
end

-- Build an AbbreviateNumbers options table from a breakpoint builder.
-- buildBreakpoints is a function returning a fresh table each call, ordered
-- largest to smallest with the base entry LAST (the retry mutates that entry).
-- Returns opts, errString:
--   opts nil            -> creation failed; errString has both attempts.
--   opts with errString -> the bp=1 attempt failed restricted validation and
--                          the bp=10 retry succeeded; values below 10 then
--                          pass through raw (each consumer documents its own
--                          containment).
function addon.CreateAbbrevConfig(buildBreakpoints)
    if not CreateAbbreviateConfig then
        return nil, "CreateAbbreviateConfig API missing"
    end
    local ok, result = pcall(CreateAbbreviateConfig, buildBreakpoints())
    if ok and result then
        return { config = result }, nil
    end
    local err = "bp=1: " .. tostring(result)
    -- breakpoint=1 may trip restricted validation (NotMultipleOfTen); retry bp=10.
    local retry = buildBreakpoints()
    retry[#retry].breakpoint = 10
    ok, result = pcall(CreateAbbreviateConfig, retry)
    if ok and result then
        return { config = result }, err
    end
    return nil, err .. " | bp=10: " .. tostring(result)
end
