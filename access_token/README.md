# Access Token

This plugin provides a token that proves its owner is a participant in the
`Jitsi` meeting room.

Let's say you have an API service and you want to allow the user to send
requests if they are an active user of a meeting. In this case, you may use this
module.

## Installation

- Copy this script to the Prosody plugins folder. It's the following folder on
  Debian:

  ```bash
  cd /usr/share/jitsi-meet/prosody-plugins/
  wget -O mod_access_token.lua https://raw.githubusercontent.com/jitsi-contrib/prosody-plugins/main/access_token/mod_access_token.lua
  ```

- Enable module in your prosody config.

  _/etc/prosody/conf.d/meet.mydomain.com.cfg.lua_

  ```lua
  Component "conference.meet.mydomain.com" "muc"
    modules_enabled = {
      ...
      ...
      "access_token";
    }

    access_token_key = "mysecretkey"
    access_token_alg = "HS256"
    access_token_exp = 60
  ```

- Restart the services

  ```bash
  systemctl restart prosody.service
  ```

## Token request

Send an `XMPP query` to get the token.

A sample `javascript` code:

```javascript
<script>
function getToken() {
  const NS_ACCESS_TOKEN = "http://jabber.org/protocol/muc#access-token";
  const iq = $iq({
    type: "get",
    to: APP.conference._room.room.focusMucJid,
  });

  iq.c("query", { xmlns: NS_ACCESS_TOKEN });

  APP.connection.xmpp.connection.sendIQ(iq, (result) => {
    const token_data = $(result).find("token").attr("data");

    console.log(`token: ${token_data}`);
  }, (error) => {
    console.error(error);
  });
}
</script>
```

Put this into `/usr/share/jitsi-meet/body.html` and run the following command on
the browser console after joining the meeting:

```javascript
getToken()
```

## Sponsors

[![Nordeck](/images/nordeck.png)](https://nordeck.net/)
