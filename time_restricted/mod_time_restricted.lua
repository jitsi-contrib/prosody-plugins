local LOGLEVEL = "debug"
local MIN = module:get_option_number("conference_max_minutes", 10)
local TIMEOUT = MIN * 60

local is_healthcheck_room = module:require "util".is_healthcheck_room
local it = require "util.iterators"
local st = require "util.stanza"
local timer = require "util.timer"
module:log(LOGLEVEL, "loaded")

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

    module:log(
        LOGLEVEL, "set timeout for conference, %s secs, %s",
        TIMEOUT,
	room.jid
    )

    timer.add_task(TIMEOUT, function()
        if is_healthcheck_room(room.jid) then
            return
        end

        local occupant_count = it.count(room:each_occupant())
        if occupant_count == 0 then
            return
        end

        -- terminate the meeting
        room:set_persistent(false)
        room:destroy(nil, "The meeting has been terminated")
        module:log(LOGLEVEL, "the conference terminated")
    end)
end)
