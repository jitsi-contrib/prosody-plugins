--- Plugin to allow the initiator to bypass the lobby. The initiator is the
--- first user joining the room with moderator/owner right.
---
--- This module should be added to the main muc component.
---

local LOGLEVEL = "debug"

local util = module:require "util"
local is_admin = util.is_admin
local is_healthcheck_room = util.is_healthcheck_room

module:log("info", "loaded")

module:hook("muc-room-pre-create", function (event)
    local room = event.room

    if is_healthcheck_room(room.jid) then
        return
    end

    room._data.initiator_joined = false
end);

module:hook("muc-occupant-pre-join", function (event)
    local session, room, occupant = event.origin, event.room, event.occupant

    if is_admin(occupant.bare_jid) or is_healthcheck_room(room.jid) then
        return
    end

    -- do nothing if initiator has already joined.
    if room._data.initiator_joined then
        return
    end

    if room._data.lobbyroom == nil then
        module:log(LOGLEVEL, "skip room with no active lobby - %s", room.jid)
        return
    end

    if not session.auth_token then
        module:log(LOGLEVEL, "skip user with no token - %s", occupant.bare_jid)
        return
    end

    local affiliation = "member"
    local context_user = session.jitsi_meet_context_user

    if context_user then
        if context_user["affiliation"] == "owner" then
            affiliation = "owner"
        elseif context_user["affiliation"] == "moderator" then
            affiliation = "owner"
        elseif context_user["affiliation"] == "teacher" then
            affiliation = "owner"
        elseif context_user["moderator"] == "true" then
            affiliation = "owner"
        elseif context_user["moderator"] == true then
            affiliation = "owner"
        end
    end

    if affiliation ~= "owner" then
        module:log(
	    LOGLEVEL,
	    "skip user with no owner status - %s",
	    occupant.bare_jid
	)
        return
    end

    occupant.role = 'participant'
    room:set_affiliation(true, occupant.bare_jid, affiliation)
    module:log(
        LOGLEVEL,
	"Bypassing lobby for room %s occupant %s",
	room.jid, occupant.bare_jid
    )

    room._data.initiator_joined = true
end, -3);
--- Run just before lobby(priority -4) and members_only (-5).
--- Must run after token_verification (99), max_occupants (10), allowners (2).
