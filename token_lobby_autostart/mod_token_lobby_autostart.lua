-- This module auto-activates lobby for all rooms if lobby_autostart is not
-- disabled explicitly in the token payload.
--
-- IMPORTANT: do not use this unless you have some mechanism for moderators to
--            bypass the lobby, otherwise everybody stops at the lobby with
--            nobody to admit them.
--
-- This module should be added to the main muc component.
--

local LOGLEVEL = "debug"
local util = module:require "util";
local is_admin = util.is_admin;
local is_healthcheck_room = util.is_healthcheck_room;


module:hook("muc-room-pre-create", function (event)
    local room = event.room

    if is_healthcheck_room(room.jid) then
        return
    end

    room._data.auto_lobby_deactivated = false

    prosody.events.fire_event("create-persistent-lobby-room", { room = room; })
end);

module:hook("muc-occupant-pre-join", function (event)
    local session, room, occupant = event.origin, event.room, event.occupant;

    if is_admin(occupant.bare_jid) or is_healthcheck_room(room.jid) then
        return
    end

    -- do nothing if already deactivated
    if room._data.lobby_deactivated then
        return
    end

    if not session.auth_token then
        module:log(LOGLEVEL, "skip deactivating, no token")
        return
    end

    local context_room = event.origin.jitsi_meet_context_room
    if not context_room then
        module:log(LOGLEVEL, "skip deactivating, no context")
        return
    end

    if context_room["lobby_autostart"] ~= false then
        module:log(LOGLEVEL, "skip deactivating, lobby_autostart is enabled")
        return
    end

    room:set_members_only(false)

    local role = room:get_default_role(room:get_affiliation(occupant.bare_jid))
    occupant.role = role or 'participant';

    prosody.events.fire_event('destroy-lobby-room', {
        room = room,
        newjid = room.jid,
    })

    room._data.lobby_deactivated = true

    module:log(LOGLEVEL, "lobby_autostart is deactivated")
end, -2);
--- Run just before token_lobby_ondemand(-3), lobby(-4) and members_only (-5).
--- Must run after token_verification (99), max_occupants (10), allowners (2).
