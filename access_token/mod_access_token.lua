local LOGLEVEL = "debug"

local jwt = module:require "luajwtjitsi"
local jid = require "util.jid";
local stanza = require "util.stanza"

local KEY = module:get_option_string("access_token_key", "mysecretkey")
local KEY_FILE = module:get_option_string("access_token_key_file")
local ALG = module:get_option_string("access_token_alg", "HS256")
local EXP = module:get_option_number("access_token_exp", 60)
local NS_ACCESS_TOKEN = "http://jabber.org/protocol/muc#access-token"

module:log(LOGLEVEL, "loaded")

if KEY_FILE then
    local f = io.open(KEY_FILE, "rb")
    KEY = f:read(_VERSION <= "Lua 5.2" and "*a" or "a")
    f.close()
end

local function stanza_handler(event)
    local org, st = event.origin, event.stanza

    if not st then return end
    if st.name ~= "iq" then return end
    if st.attr.type ~= "get" then return end

    local token_request = st:get_child("query", NS_ACCESS_TOKEN)
    if not token_request then return end

    local _, host = jid.split(st.attr.from)
    local room, _ = jid.split(st.attr.to)

    local payload = {
	userJid = st.attr.from,
        host = host,
	room = room,
	exp = os.time() + EXP
    }

    local encoded, _ = jwt.encode(payload, KEY, ALG)
    local token = {
        alg = ALG,
        data = encoded,
    }

    local reply = stanza.reply(st)
    reply:tag("token", token)
    org.send(reply)

    return true
end

module:hook("iq/full", stanza_handler)
