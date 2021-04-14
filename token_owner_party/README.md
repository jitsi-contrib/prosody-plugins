# Token Owner Party

This plugin prevents the unauthorized users to create a room and terminates the
conference when the owner leaves. It's designed to run with `token_verification`
and `token_affiliation` plugins.

## Installation

- Copy this script to the Prosody plugins folder. It's the following folder on
  Debian

  _/usr/share/jitsi-meet/prosody-plugins/_

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

- For most scenarios you may want to disable auto-ownership on Jicofo. Add the
  following line to `/etc/jitsi/jicofo/sip-communicator.properties`

  ```conf
  org.jitsi.jicofo.DISABLE_AUTO_OWNER=true
  ```

- Restart the services

  ```bash
  systemctl restart prosody.service
  systemctl restart jicofo.service
  ```
