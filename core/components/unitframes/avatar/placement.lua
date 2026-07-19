-- placement.lua - creates and anchors the avatar host overlay on the player
-- frame without re-parenting or writing to Blizzard tables. The host is a child
-- of PlayerFrameContainer, so it follows Edit Mode moves and scale changes.
local addonName, addon = ...

addon.Avatar = addon.Avatar or {}
local A = addon.Avatar
local FS = addon.FrameState
local D = addon.AvatarDefaults

local function resolvePlayerPortrait()
    local pf = _G.PlayerFrame
    if not pf then return nil, nil end
    local container = pf.PlayerFrameContainer
    local portrait = container and container.PlayerPortrait
    return container, portrait
end

local function displaySize(cfg)
    local base = (D and D.baseDisplaySize) or 48
    local scale = (cfg.scalePct or 100) / 100
    return base * scale
end

-- Create (once) and return the host overlay plus the portrait it anchors to.
function A.EnsurePlayerHost()
    local pf = _G.PlayerFrame
    if not pf then return nil end
    if pf.IsForbidden and pf:IsForbidden() then return nil end
    local container, portrait = resolvePlayerPortrait()
    if not container or not portrait then return nil end

    local st = FS.Get(pf)
    local host = st.avatarHost
    if not host then
        host = CreateFrame("Frame", nil, container)
        local lvl = (container.GetFrameLevel and container:GetFrameLevel() or 1) + 10
        host:SetFrameLevel(lvl)
        st.avatarHost = host
    end
    return host, portrait
end

function A.PositionPlayerHost(host, portrait, cfg)
    if not host or not portrait then return end
    cfg = cfg or {}
    local size = displaySize(cfg)
    host:SetSize(size, size)
    host:ClearAllPoints()

    local side = cfg.side or (D and D.defaultSide) or "left"
    local gap = cfg.gap or (D and D.defaultGap) or 2
    local ox = cfg.offsetX or 0
    local oy = cfg.offsetY or 0

    if side == "right" then
        host:SetPoint("LEFT", portrait, "RIGHT", gap + ox, oy)
    elseif side == "over" then
        host:SetPoint("CENTER", portrait, "CENTER", ox, oy)
    else
        host:SetPoint("RIGHT", portrait, "LEFT", -gap + ox, oy)
    end
end

function A.HidePlayerHost()
    local pf = _G.PlayerFrame
    local host = pf and FS.GetProp(pf, "avatarHost")
    if host then host:Hide() end
end
