# Token Lobby Bypass For Initiator

This plugin allows the first moderator to bypass the autostarted lobby. It is
expected to be used with [lobby_autostart](../lobby_autostart) module.

The user is considered a moderator if she has a token with owner affiliation.
See [token_affiliation](../token_affiliation) module for more details.

## Installation

- Copy this script to the Prosody plugins folder. It's the following folder on
  Debian:

  ```bash
  cd /usr/share/jitsi-meet/prosody-plugins/
  wget -O mod_token_lobby_bypass_for_initiator.lua https://raw.githubusercontent.com/jitsi-contrib/prosody-plugins/main/token_lobby_bypass_for_initiator/mod_token_lobby_bypass_for_initiator.lua
  ```

- Enable module in your prosody config.

  _/etc/prosody/conf.d/meet.mydomain.com.cfg.lua_

  ```lua
  Component "conference.meet.mydomain.com" "muc"
    modules_enabled = {
      -- ... existing modules
      "lobby_autotart";
      "token_lobby_bypass_for_initiator";
    }
  ```

- Restart the services

  ```bash
  systemctl restart prosody.service
  ```

## A token sample

To allow the initiator to bypass the lobby, set the `affiliation` attribute to
`owner` in `context.user`.

A sample token body:

```json
{
  "room": "myRoomName",
  "context": {
    "user": {
      "name": "myname",
      "email": "myname@mydomain.com",
      "affiliation": "owner"
    }
  },
  "aud": "myapp",
  "iss": "myapp",
  "sub": "meet.mydomain.com",
  "iat": 1601366000,
  "exp": 1601366180
}
```
