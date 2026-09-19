-- apply_all.lua - Global Font / Bar Texture values behind the media tokens
local addonName, addon = ...

addon.ApplyAll = addon.ApplyAll or {}
local ApplyAll = addon.ApplyAll

--------------------------------------------------------------------------------
-- Global media store
--------------------------------------------------------------------------------
-- The Global Font / Bar Texture tokens (addon.MediaTokens) resolve against
-- these account-wide values via ResolveFontFace / ResolveBarTexturePath.
-- Setters reject tokens so a global can never point at another token.

local function globalMedia()
    local db = addon.db
    return db and db.global and db.global.media
end

local function setGlobalValue(field, value)
    if type(value) ~= "string" or value == ""
        or (addon.IsMediaToken and addon.IsMediaToken(value)) then
        return false
    end
    local media = globalMedia()
    if not media then
        return false
    end
    media[field] = value
    return true
end

function ApplyAll:GetGlobalHeaderFont()
    local media = globalMedia()
    return (media and media.headerFont) or "GAME_DEFAULT"
end

function ApplyAll:GetGlobalBodyFont()
    local media = globalMedia()
    return (media and media.bodyFont) or "GAME_DEFAULT"
end

function ApplyAll:GetGlobalBarTexture()
    local media = globalMedia()
    return (media and media.barTexture) or "default"
end

function ApplyAll:SetGlobalHeaderFont(fontKey)
    return setGlobalValue("headerFont", fontKey)
end

function ApplyAll:SetGlobalBodyFont(fontKey)
    return setGlobalValue("bodyFont", fontKey)
end

function ApplyAll:SetGlobalBarTexture(textureKey)
    return setGlobalValue("barTexture", textureKey)
end

--------------------------------------------------------------------------------
-- Pending selections (runtime only)
--------------------------------------------------------------------------------
-- The Apply All pages stage values here; nothing persists until Apply commits
-- them to db.global.media. Reads fall back to the committed values, so a
-- freshly opened page shows the current globals.

local pending = {}

function ApplyAll:GetPendingHeaderFont()
    return pending.headerFont or self:GetGlobalHeaderFont()
end

function ApplyAll:SetPendingHeaderFont(fontKey)
    pending.headerFont = fontKey
end

function ApplyAll:GetPendingBodyFont()
    return pending.bodyFont or self:GetGlobalBodyFont()
end

function ApplyAll:SetPendingBodyFont(fontKey)
    pending.bodyFont = fontKey
end

function ApplyAll:GetPendingBarTexture()
    return pending.barTexture or self:GetGlobalBarTexture()
end

function ApplyAll:SetPendingBarTexture(textureKey)
    pending.barTexture = textureKey
end

--------------------------------------------------------------------------------
-- Apply
--------------------------------------------------------------------------------

local function buildResult(success, changed, reason)
    return {
        ok = success,
        changed = changed or 0,
        reason = reason,
    }
end

-- Validates every slot before writing any, so a rejected value never leaves
-- the globals half-committed. `changed` counts slots whose value differs; the
-- caller skips ReloadUI when it is zero.
local function commit(slots)
    local media = globalMedia()
    if not media then
        return buildResult(false, 0, "noDatabase")
    end
    for _, slot in ipairs(slots) do
        local value = slot.value
        if type(value) ~= "string" or value == "" then
            return buildResult(false, 0, "noSelection")
        end
        if addon.IsMediaToken and addon.IsMediaToken(value) then
            return buildResult(false, 0, "tokenValue")
        end
    end
    local changed = 0
    for _, slot in ipairs(slots) do
        if media[slot.field] ~= slot.value then
            media[slot.field] = slot.value
            changed = changed + 1
        end
    end
    return buildResult(changed > 0, changed, changed > 0 and nil or "noChanges")
end

function ApplyAll:ApplyFonts(headerKey, bodyKey)
    local result = commit({
        { field = "headerFont", value = headerKey or self:GetPendingHeaderFont() },
        { field = "bodyFont", value = bodyKey or self:GetPendingBodyFont() },
    })
    if result.ok then
        pending.headerFont, pending.bodyFont = nil, nil
    end
    return result
end

function ApplyAll:ApplyBarTextures(textureKey)
    local result = commit({
        { field = "barTexture", value = textureKey or self:GetPendingBarTexture() },
    })
    if result.ok then
        pending.barTexture = nil
    end
    return result
end

--------------------------------------------------------------------------------
-- Migration
--------------------------------------------------------------------------------

-- One-shot upgrade from the sweep-era Apply All: seed the Body/Bar globals
-- from the last swept values (what the user last applied everywhere), then
-- drop the dead per-profile applyAll tables. The flag is deliberately absent
-- from the registered defaults so AceDB never dedupes it away.
--
-- Scoot-only. Its one caller is core/init.lua, and it reads db.sv.profiles
-- and profile.applyAll, both ScootDB shapes. A TOC that does not load
-- core/init.lua never calls it.
function ApplyAll:RunTokenMigration()
    local db = addon.db
    if not db or not db.global then
        return
    end
    if rawget(db.global, "applyAllTokenMigration") then
        return
    end

    local media = globalMedia()
    local profile = db.profile
    local old = profile and rawget(profile, "applyAll")
    if media and old then
        local font = old.lastFontApplied and old.lastFontApplied.value
        if type(font) == "string" and font ~= "" and font ~= "FRIZQT__"
            and not (addon.IsMediaToken and addon.IsMediaToken(font)) then
            media.bodyFont = font
        end
        local texture = old.lastTextureApplied and old.lastTextureApplied.value
        if type(texture) == "string" and texture ~= "" and texture ~= "default"
            and not (addon.IsMediaToken and addon.IsMediaToken(texture)) then
            media.barTexture = texture
        end
    end

    local profiles = db.sv and db.sv.profiles
    if type(profiles) == "table" then
        for _, p in pairs(profiles) do
            if type(p) == "table" then
                p.applyAll = nil
            end
        end
    end

    db.global.applyAllTokenMigration = true
end

addon:RegisterDebugCommand({
    name = "media", help = "Global Font / Bar Texture values and stored token counts",
    handler = function()
        local lines, push = addon.DebugLines("=== Global media ===", "")
        local header = ApplyAll:GetGlobalHeaderFont()
        local body = ApplyAll:GetGlobalBodyFont()
        local texture = ApplyAll:GetGlobalBarTexture()
        push("Global Header Font: %s -> %s", header, tostring(addon.ResolveFontFace(header)))
        push("Global Body Font: %s -> %s", body, tostring(addon.ResolveFontFace(body)))
        push("Global Bar Texture: %s -> %s", texture, tostring(addon.Media.ResolveBarTexturePath(texture)))

        -- The walk is shape-agnostic: it counts token strings anywhere under
        -- the active profile, whatever containers the host keeps there.
        local counts, visited = {}, {}
        local function walk(tbl)
            if type(tbl) ~= "table" or visited[tbl] then return end
            visited[tbl] = true
            for _, child in pairs(tbl) do
                if type(child) == "table" then
                    walk(child)
                elseif addon.IsMediaToken and addon.IsMediaToken(child) then
                    counts[child] = (counts[child] or 0) + 1
                end
            end
        end
        walk(addon.db and addon.db.profile)
        local parts = {}
        for token, n in pairs(counts) do
            parts[#parts + 1] = ("%s x%d"):format(token, n)
        end
        push("")
        if #parts == 0 then
            push("No token values stored in the active profile.")
        else
            table.sort(parts)
            push("Stored tokens: " .. table.concat(parts, ", "))
        end
        addon.DebugShowWindow("Media", lines)
    end,
})
