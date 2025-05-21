--- Plugin to allow users to bypass lobby based on the authentication
---
--- This module should be added to the main muc component.
---

local LOGLEVEL = "debug";

local util = module:require 'util';
local is_healthcheck_room = util.is_healthcheck_room;

module:log("info", "loaded");

module:hook("muc-occupant-pre-join", function (event)
    local room, occupant = event.room, event.occupant;

    if is_healthcheck_room(room.jid) then
        return;
    end

    if room._data.lobbyroom == nil then
        module:log(LOGLEVEL, "skip room with no active lobby - %s", room.jid)
        return;
    end

    if event.origin.bosh_responses == nil then
        module:log(LOGLEVEL, "skip for non-bosh client - %s", occupant.bare_jid)
        return
    end

    -- search for authentication response
    for _, v in pairs(event.origin.bosh_responses) do
        if string.match(v, "identity='.-'") then
            module:log(LOGLEVEL, "Bypassing lobby for room %s occupant %s",
                room.jid, occupant.bare_jid);
            occupant.role = 'participant';
            room:set_affiliation(true, occupant.bare_jid, 'member');
            break
        end
    end

end, -3);
--- Run just before lobby(priority -4) and members_only (-5).
--- Must run after token_verification (99), max_occupants (10), allowners (2).
