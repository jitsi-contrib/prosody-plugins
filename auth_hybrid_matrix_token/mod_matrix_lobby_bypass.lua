-- -----------------------------------------------------------------------------
-- Matrix Lobby Bypass
-- -----------------------------------------------------------------------------
-- This module allows Matrix room members to bypass Jitsi lobby check. The
-- session is known to belong to a Matrix room because
-- mod_auth_hybrid_matrix_token verified the token and the room it refers to
-- before setting the affiliation checked below.
--
-- If the participant is already a valid member of Matrix's room then no need to
-- check her again in Jitsi lobby.
-- -----------------------------------------------------------------------------
local util = module:require 'util'
local is_healthcheck_room = util.is_healthcheck_room
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
