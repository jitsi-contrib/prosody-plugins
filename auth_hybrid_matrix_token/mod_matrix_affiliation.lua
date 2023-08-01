-- -----------------------------------------------------------------------------
-- Matrix Affiliation (downgrade only)
-- -----------------------------------------------------------------------------
-- This module updates the affiliation of participants if the room is created
-- by Element's Jitsi widget. This module checks Jitsi room name to understand
-- if this room is created by widget or not...
--
-- base32.decode(jitsi_room_name) should match "!.*:.*[.].*" (regex) for related
-- rooms.
--
-- This module assumes that the authentication is already enabled on Jicofo. So
-- every participants who have a valid token will become moderator (owner) by
-- default (this is not what we want).
--
-- This module downgrades the affiliation level (from owner to member) of
-- the participant if she is not an admin in the related Matrix room.
-- -----------------------------------------------------------------------------
local basexx = require 'basexx'
local is_admin = require "core.usermanager".is_admin
local is_healthcheck_room = module:require "util".is_healthcheck_room
local jid = require 'util.jid';
local timer = require "util.timer"
local LOGLEVEL = "debug"

local function _is_admin(jid)
    return is_admin(jid, module.host)
end

module:hook("muc-occupant-joined", function (event)
    local room, occupant = event.room, event.occupant

    if is_healthcheck_room(room.jid) or _is_admin(occupant.jid) then
        module:log(LOGLEVEL, "skip affiliation, %s", occupant.jid)
        return
    end

    if not event.origin.auth_token then
        module:log(LOGLEVEL, "skip affiliation, no token")
        return
    end

    local roomName, _ = jid.split(room.jid)
    local roomId = basexx.from_base32(roomName)
    if not roomId then
        module:log(LOGLEVEL, "skip affiliation, cannot decode the room name")
        return
    end

    local isMatrixRoom = string.match(roomId, "!.*:.*[.].*")
    if not isMatrixRoom then
        module:log(LOGLEVEL, "skip affiliation, not a Matrix room")
        return
    end

    if event.origin.matrix_affiliation == "owner" then
        module:log(LOGLEVEL, "skip downgrading, valid Matrix owner")
        return
    end

    -- All users who have a valid token are set as owner by jicofo when
    -- auhentication is enabled on jicofo. Downgrade the affiliation for all
    -- users who are not a Matrix owner (even they have a valid token).
    -- A timer is used because Jicofo will update the affiliation after this
    -- internal authentication phase is completed. It should be overwritten.
    local i = 0.0
    while (i < 2.0) do
        timer.add_task(i, function()
            room:set_affiliation(true, occupant.bare_jid, "member")
        end)
        i = i + 0.2
    end
    module:log( "info",
	"affiliation is downgraded, occupant: %s",
	occupant.bare_jid
    )
end)
