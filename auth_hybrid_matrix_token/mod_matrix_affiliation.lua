-- -----------------------------------------------------------------------------
-- Matrix Affiliation (downgrade only)
-- -----------------------------------------------------------------------------
-- This module updates the affiliation of participants if the room belongs to
-- a Matrix room. That is decided by mod_auth_hybrid_matrix_token, which sets
-- the Matrix context on the session once it has verified the token and the
-- room it refers to.
--
-- This module assumes that the authentication is already enabled on Jicofo. So
-- every participants who have a valid token will become moderator (owner) by
-- default (this is not what we want).
--
-- This module downgrades the affiliation level (from owner to member) of
-- the participant if she is not an admin in the related Matrix room.
-- -----------------------------------------------------------------------------
local util = module:require 'util';
local is_admin = util.is_admin;
local is_healthcheck_room = util.is_healthcheck_room
local timer = require "util.timer"
local LOGLEVEL = "debug"

-- Set this parameter in Prosody config if you dont want cascading updates for
-- affiliation. Cascading updates are needed when the authentication is enabled
-- in Jicofo.
local DISABLE_CASCADING_SET = module:get_option_boolean(
    "disable_cascading_set", true
)

module:hook("muc-occupant-joined", function (event)
    local room, occupant, session = event.room, event.occupant, event.origin

    if is_healthcheck_room(room.jid) or is_admin(occupant.bare_jid) then
        module:log(LOGLEVEL, "skip affiliation, %s", occupant.jid)
        return
    end

    if not session.auth_token then
        module:log(LOGLEVEL, "skip affiliation, no token")
        return
    end

    if session.matrix_affiliation_checked then
        module:log(LOGLEVEL, "skip affiliation, already checked")
        return
    end

    -- mod_auth_hybrid_matrix_token compares the decoded room name against the
    -- room ID in the token and rejects the session when they differ, so a
    -- session that carries the Matrix context is in a Matrix room. Deriving
    -- that from the room name here would only repeat a weaker test, and it
    -- misses room IDs from room version 12 on, which have no server part.
    if not session.jitsi_meet_context_matrix then
        module:log(LOGLEVEL, "skip affiliation, not a Matrix room")
        return
    end

    if session.matrix_affiliation == "owner" then
        module:log(LOGLEVEL, "skip downgrading, valid Matrix owner")
        return
    end

    -- All users who have a valid token are set as owner by jicofo when
    -- auhentication is enabled on jicofo. Downgrade the affiliation for all
    -- users who are not a Matrix owner (even they have a valid token).
    -- A timer is used because Jicofo will update the affiliation after this
    -- internal authentication phase is completed. It should be overwritten.
    local i = 0
    local function setAffiliation()
        room:set_affiliation(true, occupant.bare_jid, "member")

        if DISABLE_CASCADING_SET then return end
        if i > 8 then return end

        i = i + 1
        timer.add_task(0.2 * i, setAffiliation)
    end
    setAffiliation()
    session.matrix_affiliation_checked = true

    module:log( "info",
        "affiliation is downgraded, occupant: %s",
        occupant.bare_jid
    )
end)
