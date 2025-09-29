-- [Scripts/mods/VorechsMark.lua]
-- Minimal init that spawns our OnUpdate entity after gameplay starts.

VorechsMarkStarter = {}
VorechsMarkStarter.Name = "VorechsMark"
VorechsMarkStarter.Version = "0.1.0"

local function _log(msg)
    System.LogAlways(("[VorechsMark] %s"):format(tostring(msg)))
end

function VorechsMarkStarter:sceneInitListener(actionName, eventName, argTable)
    -- Spawn our heartbeat entity (same pattern as NoHorseTeleportStarter).
    local params = {
        class = "VorechsMark",
        name  = "VorechsMark_Instance",
    }
    local ent = System.SpawnEntity(params)
    if ent then
        _log("spawned entity OK")
    else
        _log("WARN: failed to spawn VorechsMark entity")
    end
end

-- Boot log (lets you see the mod loaded before spawn)
_log(("init loaded (v%s)"):format(VorechsMarkStarter.Version))

-- Initialize after player scene has started (identical event you used)
UIAction.RegisterEventSystemListener(VorechsMarkStarter, "System", "OnGameplayStarted", "sceneInitListener")
