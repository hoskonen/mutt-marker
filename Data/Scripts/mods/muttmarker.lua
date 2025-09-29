-- [Scripts/mods/muttmarker.lua]
-- Minimal init that spawns our OnUpdate entity after gameplay starts.

MuttMarkerStarter = {}
MuttMarkerStarter.Name = "MuttMarker"
MuttMarkerStarter.Version = "0.1.0"

local function _log(msg)
    System.LogAlways(("[MuttMarker] %s"):format(tostring(msg)))
end

function MuttMarkerStarter:sceneInitListener(actionName, eventName, argTable)
    -- Spawn our heartbeat entity (same pattern as NoHorseTeleportStarter).
    local params = {
        class = "MuttMarker",
        name  = "MuttMarker_Instance",
    }
    local ent = System.SpawnEntity(params)
    if ent then
        _log("spawned entity OK")
    else
        _log("WARN: failed to spawn MuttMarker entity")
    end
end

-- Boot log (lets you see the mod loaded before spawn)
_log(("init loaded (v%s)"):format(MuttMarkerStarter.Version))

-- Initialize after player scene has started (identical event you used)
UIAction.RegisterEventSystemListener(MuttMarkerStarter, "System", "OnGameplayStarted", "sceneInitListener")
