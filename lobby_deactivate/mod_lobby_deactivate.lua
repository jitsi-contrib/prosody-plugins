--- Plugin to deactivate the lobby after the first join.
---
--- This module should be added to the main muc component.
---

local LOGLEVEL = "debug"

local it = require "util.iterators"
local is_healthcheck_room = module:require "util".is_healthcheck_room

module:log("info", "loaded")

module:hook("muc-occupant-joined", function (event)
    local room, origin = event.room, event.origin

    if is_healthcheck_room(room.jid) then
        return
    end

    -- do run for focus
    local occupant_count = it.count(room:each_occupant())
    if occupant_count < 2 then
        return
    end

    -- do nothing if already checked
    if room._data.lobby_deactivated then
        return
    end
    room._data.lobby_deactivated = true

    -- do nothing if the lobby is not active
    if room._data.lobbyroom == nil then
        module:log(LOGLEVEL, "no active lobby - %s", room.jid)
        return
    end

    -- deactivate the lobby if it is not enabled explicitly
    local context_room = origin.jitsi_meet_context_room
    if not context_room or context_room["lobby"] ~= true then
        room:set_members_only(false)
        prosody.events.fire_event('destroy-lobby-room', {
            room = room,
            newjid = room.jid,
       })
    end
end, -2)
--- Run just before lobby_bypass (priority -3), lobby(-4) and members_only (-5).
--- Must run after token_verification (99), max_occupants (10), allowners (2).
