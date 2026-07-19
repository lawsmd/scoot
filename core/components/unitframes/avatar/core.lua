-- core.lua - public avatar API, zero-touch DB wiring, and secret-safe identity
-- resolution. ApplyStyles() drives ApplyAllUnitFrameAvatars() in the unitFrames
-- block; this module never touches the player frame until the user enables it.
local addonName, addon = ...

addon.Avatar = addon.Avatar or {}
local A = addon.Avatar
local FS = addon.FrameState
local D = addon.AvatarDefaults

local function isSecret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

-- Zero-touch read: return the unit config only if it already exists.
local function getUFDB(unit)
    local db = addon and addon.db and addon.db.profile
    if not db then return nil end
    local uf = rawget(db, "unitFrames")
    return uf and rawget(uf, unit) or nil
end

-- Resolve race/sex/class once, out of combat, guarding every value against
-- secrets. Cache plain strings on PlayerFrame state. Never compare or key a
-- live secret value.
local function resolveIdentity()
    local pf = _G.PlayerFrame
    if not pf then return nil end
    local st = FS.Get(pf)
    if st.avatarIdentity then return st.avatarIdentity end
    if InCombatLockdown and InCombatLockdown() then return nil end

    local race, sex, class

    local ok1, r = pcall(function() return select(2, UnitRace("player")) end)
    if ok1 and type(r) == "string" and not isSecret(r) then race = r end

    local ok2, s = pcall(function() return UnitSex("player") end)
    if ok2 and type(s) == "number" and not isSecret(s) then sex = s end

    local ok3, c = pcall(function() return select(2, UnitClass("player")) end)
    if ok3 and type(c) == "string" and not isSecret(c) then class = c end

    -- Enum.UnitSex: 2 = male, 3 = female. Default to Male when unknown/secret.
    local sexKey = (sex == 3) and "Female" or "Male"
    if not race or not A.HasRace(race) then
        race = (D and D.fallbackRace) or "Human"
    end

    local identity = { race = race, sex = sexKey, class = class }
    st.avatarIdentity = identity
    return identity
end

-- Allow a forced re-resolve (e.g. after a race change service / reload).
function A.ClearIdentity()
    local pf = _G.PlayerFrame
    if pf then FS.SetProp(pf, "avatarIdentity", nil) end
end

function A.GetIdentity()
    return resolveIdentity()
end

local function resolveAvCfg()
    local cfg = getUFDB("Player")
    return cfg and rawget(cfg, "avatar") or nil
end

-- Build the render settings used by both the live frame and the editor preview.
-- Returns a full settings table even before the avatar is enabled, so the editor
-- can preview the default look. Returns nil only if identity can't be resolved.
function A.GetPlayerSettings()
    local id = resolveIdentity()
    if not id then return nil end
    local av = resolveAvCfg() or {}
    return {
        race = id.race,
        sex = id.sex,
        class = id.class,
        -- Single canonical asset size. Ignore any stale per-profile resolution that
        -- older builds may have saved, so the path always points at generated art.
        resolution = (D and D.defaultResolution) or 48,
        slots = av.slots,
    }
end

function addon.ApplyUnitFrameAvatarFor(unit)
    if unit ~= "Player" then return end -- prototype scope: player frame only
    if not addon:IsModuleEnabled("unitFrames", unit) then return end

    local cfg = getUFDB(unit)
    local av = cfg and rawget(cfg, "avatar") or nil

    -- Zero-touch: do nothing visible until the user enables the avatar.
    if not av or not av.enabled then
        A.HidePlayerHost()
        return
    end

    if not A.GetManifest() then return end

    -- Combat: defer all player-frame work to PLAYER_REGEN_ENABLED via the
    -- central pending-styles path.
    if InCombatLockdown and InCombatLockdown() then
        addon._pendingApplyStyles = true
        return
    end

    local settings = A.GetPlayerSettings()
    if not settings then return end

    local host, portrait = A.EnsurePlayerHost()
    if not host then return end

    A.PositionPlayerHost(host, portrait, av)
    A.Render(host, A.BuildLayerList(settings))
    host:Show()
end

function addon.ApplyAllUnitFrameAvatars()
    addon.ApplyUnitFrameAvatarFor("Player")
end
