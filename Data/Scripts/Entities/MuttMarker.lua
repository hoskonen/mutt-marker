-- [Scripts/Entities/MuttMarker.lua]
-- Barebones entity that ticks every frame and logs at a throttled interval.

MuttMarker                      = MuttMarker or {
    Client     = {},
    Server     = {},
    Properties = { bSaved_by_game = 0, Saved_by_game = 0, bSerialize = 0 },
}

-- ===== Config =====
MuttMarker.Config               = {
    debug            = true,
    pingMs           = 1000,    -- log heartbeat every ~1s
    scanMs           = 1500,    -- how often we attempt (re)resolve
    allowedDogNames  = {
        ["tvez_vorech"] = true, -- internal
        ["mutt"]        = true, -- english UI
    },
    dogCompassId     = "PLAYER_DOG",
    dogHudIconId     = "dogcompanion",
    dogIconId        = "dog",
    mapNameKey       = "char_667_uiName",
    showDogOnCompass = true,
}

-- ===== State =====
MuttMarker._dogId               = MuttMarker._dogId or nil
MuttMarker._dogGuidStr          = MuttMarker._dogGuidStr or nil -- Text GUID
MuttMarker._dogGuidTbl          = MuttMarker._dogGuidTbl or nil -- Table GUID
MuttMarker._nextScanAt          = MuttMarker._nextScanAt or 0

-- session flag like NoHorseTeleport
MuttMarker.needsDogCompassReadd = true

-- ===== Small helpers =====
-- Lua 5.1-safe atan2 (same as NoHorseTeleport)
local atan2                     = math.atan2 or function(y, x)
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
    local dog = MuttMarker.ResolveDog(); if not (dog and player) then return nil, nil end
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
    if not MuttMarker.Config.debug then return end
    System.LogAlways(("[MuttMarker][%s] %s"):format(tag, tostring(msg)))
end

local function _cacheDogGuids(e)
    local okS, s = pcall(function()
        if e.GetGuidString then return e:GetGuidString() end
        if e.GetGUIDString then return e:GetGUIDString() end
        if e.entityGuidStr then return tostring(e.entityGuidStr) end
    end)
    if okS and s and s ~= "" then MuttMarker._dogGuidStr = s end

    local okT, t = pcall(function()
        if e.GetGuid then return e:GetGuid() end
        if e.GetGUID then return e:GetGUID() end
        if e.entityGuid then return e.entityGuid end
    end)
    if okT and t then MuttMarker._dogGuidTbl = t end

    return (MuttMarker._dogGuidStr ~= nil) or (MuttMarker._dogGuidTbl ~= nil)
end

local function _resolveDogByGuid()
    if MuttMarker._dogGuidStr and System.GetEntityByTextGUID then
        local e = System.GetEntityByTextGUID(MuttMarker._dogGuidStr)
        if e and e.class == "Dog" then return e end
    end
    if MuttMarker._dogGuidTbl and System.GetEntityByGUID then
        local e = System.GetEntityByGUID(MuttMarker._dogGuidTbl)
        if e and e.class == "Dog" then return e end
    end
    return nil
end

-- ===== Public: Resolve Mutt entity fast (Cura-Equi style) =====
function MuttMarker.ResolveDog()
    -- 0) cached id
    if MuttMarker._dogId then
        local e = System.GetEntity(MuttMarker._dogId)
        if e and e.class == "Dog" then return e end
    end

    -- 1) GUID (preferred after first bootstrap)
    do
        local e = _resolveDogByGuid()
        if e then
            MuttMarker._dogId = e.id
            return e
        end
    end

    -- 2) Bootstrap by name, cache GUIDs, return
    if System.GetEntityByName then
        for key, _ in pairs(MuttMarker.Config.allowedDogNames) do
            local e = System.GetEntityByName(key)
            if e and e.class == "Dog" then
                MuttMarker._dogId = e.id
                _cacheDogGuids(e) -- harmless if not supported on this build
                return e
            end
        end
    end

    return nil
end

-- === Compass & Map ===
function MuttMarker:_ensureDogCompass()
    local e = MuttMarker.ResolveDog()
    if not e then
        UIAction.CallFunction("hud", -1, "RemoveCompassMarker", MuttMarker.Config.dogCompassId)
        self._compassAdded = false -- important: allow re-add later
        return
    end
    if self._compassAdded then return end

    local dist = player and player.GetDistance and player:GetDistance(e.id) or 0
    UIAction.CallFunction(
        "hud", -1, "AddCompassMarker",
        MuttMarker.Config.dogCompassId,
        MuttMarker.Config.dogHudIconId, -- use HUD icon id here
        1,                              -- state: 1 works well (matches horse/Hans patterns)
        -1, -1,                         -- questColor, objNumber
        dist, 0,                        -- distance, initial angle 0
        false, false,                   -- inArea flags
        3, 50, 100                      -- near, layer, far
    )
    self._compassAdded = true
    UIAction.CallFunction("hud", -1, "UpdateCompass", 0) -- force initial draw
end

function MuttMarker:AddDogCompassMarker()
    if not MuttMarker.Config.showDogOnCompass then
        UIAction.CallFunction("hud", -1, "RemoveCompassMarker", MuttMarker.Config.dogCompassId)
        MuttMarker.needsDogCompassReadd = true
        return
    end
    local dog = MuttMarker.ResolveDog(); if not dog then return end
    local deg, dist = _bearingDegAndDistanceToDog(); if not deg then return end

    UIAction.CallFunction("hud", -1, "AddCompassMarker",
        MuttMarker.Config.dogCompassId,
        MuttMarker.Config.dogHudIconId, -- **HUD** icon id (must exist in compass atlas)
        1,                              -- state (horse uses 1)
        -1, -1,                         -- questColor, objNumber
        dist, deg,                      -- distance, heading
        false, false,                   -- inArea flags
        3, 50, 300)                     -- near, layer, far (horse uses 300)
    UIAction.CallFunction("hud", -1, "UpdateCompass", 0)
    MuttMarker.needsDogCompassReadd = false
end

function MuttMarker:UpdateDogCompass()
    if not MuttMarker.Config.showDogOnCompass then
        UIAction.CallFunction("hud", -1, "RemoveCompassMarker", MuttMarker.Config.dogCompassId)
        MuttMarker.needsDogCompassReadd = true
        return
    end

    local dog = MuttMarker.ResolveDog(); if not dog then return end
    local deg, dist = _bearingDegAndDistanceToDog(); if not deg then return end

    if MuttMarker.needsDogCompassReadd then
        UIAction.CallFunction("hud", -1, "AddCompassMarker",
            MuttMarker.Config.dogCompassId,
            MuttMarker.Config.dogHudIconId,
            1, -1, -1, dist, deg, false, false, 3, 50, 300)
        MuttMarker.needsDogCompassReadd = false
    end

    -- Same update packet as horse
    UIAction.SetArray("hud", -1, "CompassMarkers",
        { 1, MuttMarker.Config.dogCompassId, -1, dist, deg, 0, false, false })
    UIAction.CallFunction("hud", -1, "UpdateCompass", 0)
end

-- Map POI when map opens
function MuttMarker:AddDogMapMarker(elementName, instanceId)
    local e = MuttMarker.ResolveDog(); if not (e and e.GetPos) then return end
    local p = e:GetPos()
    local values = { 1, MuttMarker.Config.dogCompassId, MuttMarker.Config.mapNameKey,
        MuttMarker.Config.dogIconId, 2, false, 0, p.x, p.y }
    UIAction.SetArray(elementName, instanceId, "PoiMarkers", values)
    UIAction.CallFunction(elementName, instanceId, "AddPoiMarkers")
end

function MuttMarker:AddDogMapMarkerWithDelay(elementName, instanceId, eventName, argTable)
    Script.SetTimer(50, function() MuttMarker:AddDogMapMarker(elementName, instanceId) end)
end

-- ===== Lifecycle =====
function MuttMarker:OnReset()
    self.lastPing = 0
    self:Activate(1) -- enable Client:OnUpdate
end

function MuttMarker.Client:OnInit()
    MuttMarker.needsDogCompassReadd = true
    _dbg("Init", "entity client init")
    if not self.bInitialized then
        self:OnReset()
        self.bInitialized = 1
    end
    -- Map listener
    UIAction.RegisterElementListener(MuttMarker, "ApseMap", -1, "OnShow", "AddDogMapMarkerWithDelay")

    -- Optional one-shot icon probe
    if MuttMarker.Config.iconProbeOnce then
        Script.SetTimer(500, function() MuttMarker:_debugProbeIconRing() end)
    end

    if not self.bInitialized then
        self:OnReset(); self.bInitialized = 1
    end
end

-- ===== Per-frame tick =====
function MuttMarker.Client:OnUpdate(frameTime)
    local now = _nowMs()
    if (now - (self.lastPing or 0)) >= (MuttMarker.Config.pingMs or 1000) then
        self.lastPing = now
        _dbg("Tick", "heartbeat ✓")
    end

    if now >= (MuttMarker._nextScanAt or 0) then
        MuttMarker._nextScanAt = now + (MuttMarker.Config.scanMs or 1500)

        local dog = MuttMarker.ResolveDog()
        if dog then
            if not self._dogLogged then
                self._dogLogged = true
                _dbg("Dog", ("resolved '%s' id=%s guid=%s"):format(
                    dog.GetName and dog:GetName() or "<?>",
                    tostring(dog.id),
                    tostring(MuttMarker._dogGuidStr or MuttMarker._dogGuidTbl)))
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
    MuttMarker:UpdateDogCompass()
end
