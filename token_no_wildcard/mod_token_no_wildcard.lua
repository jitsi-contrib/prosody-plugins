--- Plugin to deny access to tokens that use wildcards or regex matches.
--- This limits the scope of all tokens to only the explicitly named room and subdomain.
---
--- To install, add module to main conference muc component.
---

local LOGLEVEL = "info";

local st = require "util.stanza";
local util = module:require 'util';
local is_admin = util.is_admin;

local function verify_no_wildcard_in_token(session, stanza)
    local user_jid = stanza.attr.from;

    -- token not required for admin user.
    if is_admin(user_jid) then
        return true;
    end

    -- Reject if wildcard in room claim
    if session.jitsi_meet_room == '*' then
        module:log(LOGLEVEL, "Reject %s -- wildcard in room claim", user_jid);
        session.send(
            st.error_reply(
                stanza, "cancel", "not-allowed", "Wildcard room in token not allowed"));
        return false;
    end

    -- Reject if wildcard in sub claim
    if session.jitsi_meet_domain == '*' then
        module:log(LOGLEVEL, "Reject %s -- wildcard in sub claim", user_jid);
        session.send(
            st.error_reply(
                stanza, "cancel", "not-allowed", "Wildcard sub in token not allowed"));
        return false;
    end

    -- Reject regex matching of room name
    local room_context = session.jitsi_meet_context_room;
    if room_context and (room_context["regex"] == true or room_context["regex"] == "true") then
        module:log(LOGLEVEL, "Reject %s -- regex match requested in token", user_jid);
        session.send(
            st.error_reply(
                stanza, "cancel", "not-allowed", "Regex support not allowed for token"));
        return false;
    end

    return true;
end

module:hook("muc-room-pre-create", function(event)
    local origin, stanza = event.origin, event.stanza;
    if not verify_no_wildcard_in_token(origin, stanza) then
        return true; -- Returning any value other than nil will halt processing of the event
    end
end, 100);  --- run before mod_token_verification (99)

module:hook("muc-occupant-pre-join", function(event)
    local origin, stanza = event.origin, event.stanza;
    if not verify_no_wildcard_in_token(origin, stanza) then
        return true; -- Returning any value other than nil will halt processing of the event
    end
end, 100); --- run before mod_token_verification (99)
