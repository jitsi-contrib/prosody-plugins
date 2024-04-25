# Lobby Deactivate

This plugin deactivates the lobby after the first join.

It is expected to be used with [lobby_autostart](../lobby_autostart). It keeps
the lobby active for unauthorized users but deactivates it when an authorized
user joins the meeting.

## Installation

- Copy this script to the Prosody plugins folder. It's the following folder on
  Debian

  ```bash
  cd /usr/share/jitsi-meet/prosody-plugins/
  wget -O mod_lobby_deactivate.lua https://raw.githubusercontent.com/jitsi-contrib/prosody-plugins/main/mod_lobby_deactivate/mod_lobby_deactivate.lua
  ```

- Enable module in your prosody config.

  _/etc/prosody/conf.d/meet.mydomain.com.cfg.lua_

  ```lua
  Component "conference.meet.mydomain.com" "muc"
    modules_enabled = {
      ...
      ...
      "lobby_deactivate";
    }
  ```

- Restart the services

  ```bash
  systemctl restart prosody.service
  systemctl restart jicofo.service
  ```

## Sponsors

[![Nordeck](/images/nordeck.png)](https://nordeck.net/)
