# Token Owner Party

This plugin prevents the unauthorized users to create a room and terminates the
conference when the owner leaves. It's designed to run with `token_verification`
and `token_affiliation` plugins.

If you have the `muc_wait_for_host` module then don't use this module, check
[owner_restricted](../owner_restricted) instead.

> **Warning**: This plugin doesn't work correctly with breakout rooms.

## Installation

- Copy this script to the Prosody plugins folder. It's the following folder on
  Debian

  ```bash
  cd /usr/share/jitsi-meet/prosody-plugins/
  wget -O mod_token_owner_party.lua https://raw.githubusercontent.com/jitsi-contrib/prosody-plugins/main/token_owner_party/mod_token_owner_party.lua
  ```

- Enable module in your prosody config.

  _/etc/prosody/conf.d/meet.mydomain.com.cfg.lua_

  ```lua
  Component "conference.meet.mydomain.com" "muc"
    modules_enabled = {
      ...
      ...
      "token_verification";
      "token_affiliation";
      "token_owner_party";
    }
    party_check_timeout = 20
  ```

- For most scenarios you may want to disable auto-ownership on Jicofo.

  ```bash
  hocon -f /etc/jitsi/jicofo/jicofo.conf \
      set jicofo.conference.enable-auto-owner false
  ```

- Restart the services

  ```bash
  systemctl restart prosody.service
  systemctl restart jicofo.service
  ```
