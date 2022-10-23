--- Plugin to dynamically enable lobby when required by token, and exclude those without the attribute
---
--- This module should be added to the main muc component.
---

local LOGLEVEL = "debug";

local muc_util = module:require "muc/util";
local valid_affiliations = muc_util.valid_affiliations;
local is_healthcheck_room = module:require "util".is_healthcheck_room;


module:hook("muc-occupant-pre-join", function (event)
    local room, occupant = event.room, event.occupant;

    if is_healthcheck_room(room.jid) then
        return;
    end

    if not event.origin.auth_token then
        module:log(LOGLEVEL, "skip user with no token - %s", occupant.bare_jid)
        return
    end

    local context = event.origin.jitsi_meet_context_user;
    local user_should_use_lobby = (context ~= nil and context["lobby"] == true);
    local lobby_enabled = (room._data.lobbyroom ~= nil);

    if lobby_enabled then
        -- If lobby already enabled, exclude user from lobby if necessary
        if not user_should_use_lobby then
            module:log(LOGLEVEL, "Bypassing lobby for room %s occupant %s", room.jid, occupant.bare_jid);

            occupant.role = 'participant';

            -- set affiliation to "member" if not yet assigned by other plugins
            local affiliation = room:get_affiliation(occupant.bare_jid);
            if valid_affiliations[affiliation or "none"] < valid_affiliations.member then
                module:log(LOGLEVEL, "Setting affiliation for %s -> member", occupant.bare_jid);
                room:set_affiliation(true, occupant.bare_jid, 'member');
            end
        end
    else
        if user_should_use_lobby then
            -- if lobby not yet enabled and user should be subject to it, so we enable it
            prosody.events.fire_event("create-persistent-lobby-room", { room = room; });
        end
    end

end, -3);
--- Run just before lobby(priority -4) and members_only (-5).
--- Must run after token_verification (99), max_occupants (10), allowners (2).
