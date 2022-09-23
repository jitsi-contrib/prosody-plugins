# Token Lobby On-Demand

This plugin dynamically enables lobby when a user joins with `"lobby": true` in token. Token users without 
`"lobby": true` will be excluded from the lobby.

## How is this different from lobby_autostart?

With [lobby_autostart](../lobby_autostart/), all rooms will automatically have lobby activated on creation, and 
you need something like [token_lobby_bypass](../token_lobby_bypass/) to opt users out of lobby.

This module is the opposite; you use a field in the token to opt users into using lobby, and lobby is only activated
when it is required.


## Installation
- Prerequisites:
  - Enable the lobby feature and test that it works as expected when manually activated by a moderator.

  - Set up [JWT auth](https://github.com/jitsi/lib-jitsi-meet/blob/master/doc/tokens.md) and check that it works before 
  proceeding.
  
  - Check that you have `/usr/share/jitsi-meet/prosody-plugins/mod_persistent_lobby.lua`. If it's not there, that means
    your version of Jitsi does not yet include [this PR](https://github.com/jitsi/jitsi-meet/pull/12215) which is required.


- Copy this script to the Prosody plugins folder. It's the following folder on
  Debian:

  ```bash
  cd /usr/share/jitsi-meet/prosody-plugins/
  wget -O mod_token_lobby_ondemand.lua https://raw.githubusercontent.com/jitsi-contrib/prosody-plugins/main/token_lobby_ondemand/mod_token_lobby_ondemand.lua
  ```

- Enable the module in your prosody config, as well as the 'persistent_lobby' module.

  _/etc/prosody/conf.d/meet.mydomain.com.cfg.lua_

  ```lua
  Virtualhost "meet.mydomain.com"
    modules_enabled = {
      -- ...
      "muc_lobby_rooms";
      "persistent_lobby";
    }
  
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

To send a user to the lobby (and activate lobby if it is not yet activated), set the `lobby` attribute to 
boolean `true` in `context.features`.

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
      "lobby": true
    }
  },
  "aud": "myapp",
  "iss": "myapp",
  "sub": "meet.mydomain.com",
  "iat": 1601366000,
  "exp": 1601366180
}
```