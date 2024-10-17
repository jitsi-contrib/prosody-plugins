-- -----------------------------------------------------------------------------
-- Matrix Lobby Bypass
-- -----------------------------------------------------------------------------
-- This module allows Matrix room members to bypass Jitsi lobby check if the
-- meeting room is created by Element's Jitsi widget. This module checks Jitsi
-- room name to understand if this room is created by widget or not...
--
-- There are two possible formats for Jitsi room names created by widget:
-- - jitsi_room_name should match "^jitsi[a-z]{24}$" (regex) or
-- - base32.decode(jitsi_room_name) should match "^!.*:.*[.].*" (regex)
--
-- If the participant is already a valid member of Matrix's room then no need to
-- check her again in Jitsi lobby.
-- -----------------------------------------------------------------------------
local basexx = require 'basexx'
local is_healthcheck_room = module:require "util".is_healthcheck_room
local jid_split = require "util.jid".split
local LOGLEVEL = "debug"

module:hook("muc-occupant-pre-join", function (event)
    local room, occupant, stanza = event.room, event.occupant, event.stanza
    local MUC_NS = "http://jabber.org/protocol/muc"

    if is_healthcheck_room(room.jid) then
        return
    end

    if not event.origin.auth_token then
        module:log(LOGLEVEL, "skip lobby_bypass, no token")
        return
    end

    if not event.origin.matrix_affiliation then
        module:log(LOGLEVEL, "skip lobby_bypass, not a Matrix user")
        return
    end

    local roomName, _ = jid_split(room.jid)
    local isMatrixRoomName = string.match(
        roomName,
        "^jitsi%l%l%l%l%l%l%l%l%l%l%l%l%l%l%l%l%l%l%l%l%l%l%l%l$"
    )

    -- if it doesnt match the first format, check the second possible format
    if not isMatrixRoomName then
        local roomId = basexx.from_base32(roomName)
        if not roomId then
            module:log(LOGLEVEL, "skip lobby_bypass, cannot decode the name")
            return
        end

        local isMatrixRoomId = string.match(roomId, "^!.*:.*[.].*")
        if not isMatrixRoomId then
            module:log(LOGLEVEL, "skip lobby_bypass, not a Matrix room")
            return
        end
    end

    -- bypass room password if exists
    local room_password = room:get_password()
    if room_password then
        local join = stanza:get_child("x", MUC_NS)

        if not join then
            join = stanza:tag("x", { xmlns = MUC_NS })
        end

        join:tag("password", { xmlns = MUC_NS }):text(room_password)
    end

    -- bypass lobby if exists
    local affiliation = room:get_affiliation(occupant.bare_jid)
    if not affiliation or affiliation == 0 then
        occupant.role = 'participant'
        room:set_affiliation(true, occupant.bare_jid, 'member')
    end
end, -2)
--- Run just before lobby_bypass (priority -3), lobby(-4) and members_only (-5).
--- Must run after token_verification (99), max_occupants (10), allowners (2).
