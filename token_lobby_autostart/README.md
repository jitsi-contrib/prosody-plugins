# Token Lobby Autostart

This plugin automatically enables the lobby for all rooms if
`context.room.lobby_autostart` is not disabled explicitly in the token payload.

See also [lobby_autostart](../lobby_autostart).

> :warning: Do not use this plugin unless you have enabled some mechanism for
> moderators to bypass the lobby, e.g. a plugin to set default passwords to
> rooms, or a plugin to
> [bypass lobby based on token attributes](../token_lobby_bypass/). Otherwise,
> all your users will be stuck in the lobby with nobody to admit them.

## Installation

- Prerequisites:
  - Enable the lobby feature and test that it works as expected when manually
    activated by a moderator.

  - Make sure you have a way for moderators to bypass the lobby. Test that it
    works when lobby is activated manually by another moderator.

- Copy this script to the Prosody plugins folder. It's the following folder on
  Debian

  ```bash
  cd /usr/share/jitsi-meet/prosody-plugins/
  wget -O mod_token_lobby_autostart.lua https://raw.githubusercontent.com/jitsi-contrib/prosody-plugins/main/token_lobby_autostart/mod_token_lobby_autostart.lua
  ```

- Enable the module in your prosody config, as well as the 'persistent_lobby'
  module.

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
      "token_lobby_autostart";
    }
  ```

- Restart prosody

  ```bash
  systemctl restart prosody.service
  ```

## Usage

To disable `lobby_autostart` for a specific meeting, unset the related field in
the token payload:

```json
  "context": {
    "room": {
      "lobby_autostart": false
    }
  }
```

If this field is not exist or is set as `true` then `lobby_autostart` stays
active.
