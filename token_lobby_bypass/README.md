# Token Lobby Bypass

This plugin allows you to let some users bypass the lobby by setting a flag in their token. 


## Installation

- Set up [JWT auth](https://github.com/jitsi/lib-jitsi-meet/blob/master/doc/tokens.md) and check that it works before 
  proceeding.

- Copy this script to the Prosody plugins folder. It's the following folder on
  Debian:

  ```bash
  cd /usr/share/jitsi-meet/prosody-plugins/
  wget -O mod_token_lobby_bypass.lua https://raw.githubusercontent.com/jitsi-contrib/prosody-plugins/main/token_lobby_bypass/mod_token_lobby_bypass.lua
  ```

- Enable module in your prosody config.

  _/etc/prosody/conf.d/meet.mydomain.com.cfg.lua_

  ```lua
  Component "conference.meet.mydomain.com" "muc"
    modules_enabled = {
      -- ... existing modules
      "token_lobby_bypass";
    }
  ```

- Restart the services

  ```bash
  systemctl restart prosody.service
  ```

## A token sample

To allow a user to bypass the lobby, set the `lobby_bypass` attribute to boolean `true` in `context.features`.

A sample token body:

```json
{
  "room": "myRoomName",
  "context": {
    "user": {
      "name": "myname",
      "email": "myname@mydomain.com",
    },
    "features": {
      "lobby_bypass": true
    }
  },
  "aud": "myapp",
  "iss": "myapp",
  "sub": "meet.mydomain.com",
  "iat": 1601366000,
  "exp": 1601366180
}
```