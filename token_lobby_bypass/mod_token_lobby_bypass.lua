--- Plugin to allow users to bypass lobby based on attribute in JWT.
---
--- This module should be added to the main muc component.
---

local LOGLEVEL = "debug";

local muc_util = module:require "muc/util";
local valid_affiliations = muc_util.valid_affiliations;
local is_healthcheck_room = module:require "util".is_healthcheck_room;

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

    if not event.origin.auth_token then
        module:log(LOGLEVEL, "skip user with no token - %s", occupant.bare_jid)
        return
    end

    local context = event.origin.jitsi_meet_context_user;

    if context then
        if context['lobby_bypass'] == true then
            module:log(LOGLEVEL, "Bypassing lobby for room %s occupant %s", room.jid, occupant.bare_jid);

            occupant.role = 'participant';

            -- set affiliation to "member" if not yet assigned by other plugins
            local affiliation = room:get_affiliation(occupant.bare_jid);
            if valid_affiliations[affiliation or "none"] < valid_affiliations.member then
                module:log(LOGLEVEL, "Setting affiliation for %s -> member", occupant.bare_jid);
                room:set_affiliation(true, occupant.bare_jid, 'member');
            end
        end
    end

end, -3);
--- Run just before lobby(priority -4) and members_only (-5).
--- Must run after token_verification (99), max_occupants (10), allowners (2).
