# Token No Wildcard

This plugin pre-validates tokens and rejects any token that uses wildcards
(`'*'`) for `room` or `sub` claim, or if regex-based matching is requested.

In effect, it insists that all tokens can only be used for one specific room
thus reducing the blast radius should someone accidentally share their token.

## Installation

- Prerequisites:

  - Set up
    [JWT auth](https://github.com/jitsi/lib-jitsi-meet/blob/master/doc/tokens.md)
    and check that it works before proceeding.

- Copy this script to the Prosody plugins folder. It's the following folder on
  Debian:

  ```bash
  cd /usr/share/jitsi-meet/prosody-plugins/
  wget -O mod_token_no_wildcard.lua https://raw.githubusercontent.com/jitsi-contrib/prosody-plugins/main/token_no_wildcard/mod_token_no_wildcard.lua
  ```

- Enable the module in your prosody config

  _/etc/prosody/conf.d/meet.mydomain.com.cfg.lua_

  ```lua
  Component "conference.meet.mydomain.com" "muc"
    modules_enabled = {
      -- ... existing modules
      "token_no_wildcard";
    }
  ```

- Restart the services

  ```bash
  systemctl restart prosody.service
  ```
