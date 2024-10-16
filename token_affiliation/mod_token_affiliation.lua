local LOGLEVEL = "debug"

-- Set this parameter in Prosody config if you dont want cascading updates for
-- affiliation. Cascading updates are needed when the authentication is enabled
-- in Jicofo.
local DISABLE_CASCADING_SET = module:get_option_boolean(
    "disable_cascading_set", false
)

local is_admin = require "core.usermanager".is_admin
local is_healthcheck_room = module:require "util".is_healthcheck_room
local timer = require "util.timer"
module:log(LOGLEVEL, "loaded")

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

    local affiliation = "member"
    local context_user = event.origin.jitsi_meet_context_user

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

    local i = 0
    local function setAffiliation()
        room:set_affiliation(true, occupant.bare_jid, affiliation)

        if DISABLE_CASCADING_SET then return end
        if i > 8 then return end

        i = i + 1
        timer.add_task(0.2 * i, setAffiliation)
    end
    setAffiliation()

    module:log(LOGLEVEL, "affiliation: %s", affiliation)
end)
