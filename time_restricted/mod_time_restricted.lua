local LOGLEVEL = "debug"
local MIN = module:get_option_number("conference_max_minutes", 10)
local TIMEOUT = MIN * 60

local is_admin = require "core.usermanager".is_admin
local is_healthcheck_room = module:require "util".is_healthcheck_room
local st = require "util.stanza"
local timer = require "util.timer"
module:log(LOGLEVEL, "loaded")

local function _is_admin(jid)
    return is_admin(jid, module.host)
end

module:hook("muc-room-created", function (event)
    local room = event.room

    if is_healthcheck_room(room.jid) then
        module:log(LOGLEVEL, "skip restriction")
        return
    end

    -- announce the expiration time
    room:broadcast_message(
         st.message({ type="groupchat", from=room.jid })
         :tag("body")
         :text("The conference will be terminated in "..MIN.." min"))

    module:log(LOGLEVEL, "set timeout for conference, %s secs, %s",
                         TIMEOUT, room.jid)

    timer.add_task(TIMEOUT, function()
        if is_healthcheck_room(room.jid) then
            return
        end

        -- kick all participants
        for _, p in room:each_occupant() do
            if not _is_admin(p.jid) then
                room:set_affiliation(true, p.jid, "outcast")
                module:log(LOGLEVEL, "kick the occupant, %s", p.jid)
            end
        end

        module:log(LOGLEVEL, "the conference terminated")
    end)
end)
