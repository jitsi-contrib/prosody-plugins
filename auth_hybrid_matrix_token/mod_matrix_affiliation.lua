-- -----------------------------------------------------------------------------
-- Matrix Affiliation (downgrade only)
-- -----------------------------------------------------------------------------
-- This module updates the affiliation of participants if the room is created
-- by Element's Jitsi widget. This module checks Jitsi room name to understand
-- if this room is created by widget or not...
--
-- There are two possible formats for Jitsi room names created by widget:
-- - jitsi_room_name should match "^jitsi[a-z]{24}$" (regex) or
-- - base32.decode(jitsi_room_name) should match "^!.*:.*[.].*" (regex)
--
-- This module assumes that the authentication is already enabled on Jicofo. So
-- every participants who have a valid token will become moderator (owner) by
-- default (this is not what we want).
--
-- This module downgrades the affiliation level (from owner to member) of
-- the participant if she is not an admin in the related Matrix room.
-- -----------------------------------------------------------------------------
local basexx = require 'basexx'
local util = module:require 'util';
local is_admin = util.is_admin;
local is_healthcheck_room = util.is_healthcheck_room
local jid_split = require "util.jid".split
local timer = require "util.timer"
local LOGLEVEL = "debug"

-- Set this parameter in Prosody config if you dont want cascading updates for
-- affiliation. Cascading updates are needed when the authentication is enabled
-- in Jicofo.
local DISABLE_CASCADING_SET = module:get_option_boolean(
    "disable_cascading_set", false
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

    if session.token_affiliation_checked then
        module:log(LOGLEVEL, "skip affiliation, already checked")
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
            module:log(LOGLEVEL, "skip affiliation, cannot decode the name")
            return
        end

        local isMatrixRoomId = string.match(roomId, "^!.*:.*[.].*")
        if not isMatrixRoomId then
            module:log(LOGLEVEL, "skip affiliation, not a Matrix room")
            return
        end
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
    session.token_affiliation_checked = true

    module:log( "info",
        "affiliation is downgraded, occupant: %s",
        occupant.bare_jid
    )
end)
