--- Stop users from changing nick (display name) if name is provided by jisi_meet_context_user


-- For all received presence messages, if jitsi_meet_context_user.name value is set in the session, then we simply
-- override nick with that value.
function on_message(event)
    if event and event["stanza"] then
        if event.origin and event.origin.jitsi_meet_context_user then
            local name = event.origin.jitsi_meet_context_user['name'];

            if name then
                -- first, drop existing 'nick' element
                event.stanza:maptags(
                    function(tag)
                        for k, v in pairs(tag) do
                            if k == "name" and v == "nick" then
                                return nil;
                            end
                        end
                        return tag
                    end
                )

                -- then insert new one using name from user context
                event.stanza:tag("nick", { xmlns = "http://jabber.org/protocol/nick"} ):text(name):up();

                module:log("debug", "Nick replaced in stanza %s", tostring(event.stanza));
            end
        end
    end
end


module:hook("pre-presence/bare", on_message);
module:hook("pre-presence/full", on_message);

module:log("info", "loaded mod_frozen_nick");
