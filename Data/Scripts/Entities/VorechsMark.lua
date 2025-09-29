-- [Scripts/Entities/VorechsMark.lua]
-- Barebones entity that ticks every frame and logs at a throttled interval.

VorechsMark                      = VorechsMark or {
    Client     = {},
    Server     = {},
    Properties = { bSaved_by_game = 0, Saved_by_game = 0, bSerialize = 0 },
}

-- ===== Config (rename these in your script) =====
VorechsMark.Config               = {
    debug           = false,
    -- IDs
    compassMarkerId = "VORECHS_MARK", -- the unique id we add/update/remove on the HUD

    -- Icons
    compassIconId   = "dog", -- HUD/compass sprite name
    mapIconId       = "dog", -- Map sprite name

    -- States
    compassState    = 2, -- IMPORTANT: use 2 (discovered) for dog

    -- Labels
    mapLabelKey     = "char_667_uiName",

    allowedDogNames = {
        ["tvez_vorech"] = true,
        ["mutt"] = true,
    },

    -- Feature toggles
    showCompass     = true,
    showMap         = true, -- spoiler-safe default
}

-- ===== State =====
VorechsMark._dogId               = VorechsMark._dogId or nil
VorechsMark._dogGuidStr          = VorechsMark._dogGuidStr or nil -- Text GUID
VorechsMark._dogGuidTbl          = VorechsMark._dogGuidTbl or nil -- Table GUID
VorechsMark._nextScanAt          = VorechsMark._nextScanAt or 0

-- session flag like NoHorseTeleport
VorechsMark.needsDogCompassReadd = true

-- ===== Small helpers =====
local atan2                      = math.atan2 or function(y, x)
    if x > 0 then
        return math.atan(y / x)
    elseif x < 0 then
        return (y >= 0) and (math.atan(y / x) + math.pi) or (math.atan(y / x) - math.pi)
    else
        if y > 0 then
            return math.pi / 2
        elseif y < 0 then
            return -math.pi / 2
        else
            return 0
        end
    end
end

local function _bearingDegAndDistanceToDog()
    local dog = VorechsMark.ResolveDog(); if not (dog and player) then return nil, nil end
    local pp = (player.GetPos and player:GetPos()) or (player.GetWorldPos and player:GetWorldPos())
    local dp = (dog.GetPos and dog:GetPos()) or (dog.GetWorldPos and dog:GetWorldPos())
    if not (pp and dp) then return nil, nil end

    local dir = { x = pp.x - dp.x, y = pp.y - dp.y, z = 0 }
    local ang = atan2(dir.x, dir.y) + (math.pi / 4.0)
    local deg = (math.deg(ang) % 360 + 360) % 360 -- <- normalize!
    local dist = (player.GetDistance and player:GetDistance(dog.id)) or 0
    return deg, dist
end

local function _nowMs()
    local t = System.GetCurrTime and System.GetCurrTime() or 0
    return math.floor((t or 0) * 1000)
end

local function _dbg(tag, msg)
    if not VorechsMark.Config.debug then return end
    System.LogAlways(("[VorechsMark][%s] %s"):format(tag, tostring(msg)))
end

local function _cacheDogGuids(e)
    local okS, s = pcall(function()
        if e.GetGuidString then return e:GetGuidString() end
        if e.GetGUIDString then return e:GetGUIDString() end
        if e.entityGuidStr then return tostring(e.entityGuidStr) end
    end)
    if okS and s and s ~= "" then VorechsMark._dogGuidStr = s end

    local okT, t = pcall(function()
        if e.GetGuid then return e:GetGuid() end
        if e.GetGUID then return e:GetGUID() end
        if e.entityGuid then return e.entityGuid end
    end)
    if okT and t then VorechsMark._dogGuidTbl = t end

    return (VorechsMark._dogGuidStr ~= nil) or (VorechsMark._dogGuidTbl ~= nil)
end

local function _resolveDogByGuid()
    if VorechsMark._dogGuidStr and System.GetEntityByTextGUID then
        local e = System.GetEntityByTextGUID(VorechsMark._dogGuidStr)
        if e and e.class == "Dog" then return e end
    end
    if VorechsMark._dogGuidTbl and System.GetEntityByGUID then
        local e = System.GetEntityByGUID(VorechsMark._dogGuidTbl)
        if e and e.class == "Dog" then return e end
    end
    return nil
end

-- ===== Public: Resolve Mutt entity fast (Cura-Equi style) =====
function VorechsMark.ResolveDog()
    -- 0) cached id
    if VorechsMark._dogId then
        local e = System.GetEntity(VorechsMark._dogId)
        if e and e.class == "Dog" then return e end
    end

    -- 1) GUID (preferred after first bootstrap)
    do
        local e = _resolveDogByGuid()
        if e then
            VorechsMark._dogId = e.id
            return e
        end
    end

    -- 2) Bootstrap by name, cache GUIDs, return
    if System.GetEntityByName then
        for key, _ in pairs(VorechsMark.Config.allowedDogNames) do
            local e = System.GetEntityByName(key)
            if e and e.class == "Dog" then
                VorechsMark._dogId = e.id
                _cacheDogGuids(e) -- harmless if not supported on this build
                return e
            end
        end
    end

    return nil
end

-- === Compass & Map ===
function VorechsMark:AddDogCompassMarker()
    if not VorechsMark.Config.showCompass then
        UIAction.CallFunction("hud", -1, "RemoveCompassMarker", VorechsMark.Config.compassMarkerId)
        VorechsMark.needsDogCompassReadd = true
        return
    end
    local dog = VorechsMark.ResolveDog(); if not dog then return end
    local deg, dist = _bearingDegAndDistanceToDog(); if not deg then return end

    UIAction.CallFunction("hud", -1, "AddCompassMarker",
        VorechsMark.Config.compassMarkerId,
        VorechsMark.Config.compassIconId,
        VorechsMark.Config.compassState, -- 2 = discovered
        -1, -1,
        dist, deg,
        false, false,
        3, 50, 300)
    UIAction.CallFunction("hud", -1, "UpdateCompass", 0)
    VorechsMark.needsDogCompassReadd = false
end

function VorechsMark:UpdateDogCompass()
    if not VorechsMark.Config.showCompass then
        UIAction.CallFunction("hud", -1, "RemoveCompassMarker", VorechsMark.Config.compassMarkerId)
        VorechsMark.needsDogCompassReadd = true
        return
    end

    local dog = VorechsMark.ResolveDog(); if not dog then return end
    local deg, dist = _bearingDegAndDistanceToDog(); if not deg then return end

    if VorechsMark.needsDogCompassReadd then
        UIAction.CallFunction("hud", -1, "AddCompassMarker",
            VorechsMark.Config.compassMarkerId,
            VorechsMark.Config.compassIconId,
            VorechsMark.Config.compassState, -- was 1
            -1, -1, dist, deg, false, false, 3, 50, 300)
        VorechsMark.needsDogCompassReadd = false
    end

    -- Same update packet as horse
    UIAction.SetArray("hud", -1, "CompassMarkers",
        { 1, VorechsMark.Config.compassMarkerId, -1, dist, deg, 0, false, false })
    UIAction.CallFunction("hud", -1, "UpdateCompass", 0)
end

-- Map POI when map opens
function VorechsMark:AddDogMapMarker(elementName, instanceId)
    if not VorechsMark.Config.showMap then return end
    local e = VorechsMark.ResolveDog(); if not (e and e.GetPos) then return end
    local p = e:GetPos()
    local values = { 1, VorechsMark.Config.compassMarkerId, VorechsMark.Config.mapLabelKey,
        VorechsMark.Config.mapIconId, 2, false, 0, p.x, p.y }
    UIAction.SetArray(elementName, instanceId, "PoiMarkers", values)
    UIAction.CallFunction(elementName, instanceId, "AddPoiMarkers")
end

function VorechsMark:AddDogMapMarkerWithDelay(elementName, instanceId, eventName, argTable)
    if not VorechsMark.Config.showMap then return end
    Script.SetTimer(50, function() VorechsMark:AddDogMapMarker(elementName, instanceId) end)
end

-- ===== Lifecycle =====
function VorechsMark:OnReset()
    self.lastPing = 0
    self:Activate(1) -- enable Client:OnUpdate
end

function VorechsMark.Client:OnInit()
    VorechsMark.needsDogCompassReadd = true
    _dbg("Init", "entity client init")
    if not self.bInitialized then
        self:OnReset()
        self.bInitialized = 1
    end
    -- Map listener
    if VorechsMark.Config.showMap then
        UIAction.RegisterElementListener(VorechsMark, "ApseMap", -1, "OnShow", "AddDogMapMarkerWithDelay")
    end
end

-- ===== Per-frame tick =====
function VorechsMark.Client:OnUpdate(frameTime)
    local now = _nowMs()
    if (now - (self.lastPing or 0)) >= (VorechsMark.Config.pingMs or 1000) then
        self.lastPing = now
        _dbg("Tick", "heartbeat ✓")
    end

    if now >= (VorechsMark._nextScanAt or 0) then
        VorechsMark._nextScanAt = now + (VorechsMark.Config.scanMs or 1500)

        local dog = VorechsMark.ResolveDog()
        if dog then
            if not self._dogLogged then
                self._dogLogged = true
                _dbg("Dog", ("resolved '%s' id=%s guid=%s"):format(
                    dog.GetName and dog:GetName() or "<?>",
                    tostring(dog.id),
                    tostring(VorechsMark._dogGuidStr or VorechsMark._dogGuidTbl)))
            end
            if (now - (self.lastDogLog or 0)) >= 3000 then
                self.lastDogLog = now
                _dbg("Dog", "still tracking ✓")
            end
        else
            self._dogLogged = false
            _dbg("Dog", "not found (will retry)")
        end
    end

    -- Ensure marker exists, then update its position/angle
    VorechsMark:UpdateDogCompass()
end
