# Token Affiliation

This plugin sets the occupant's affiliation according to the token content.

## Installation

- Copy this script to the Prosody plugins folder. It's the following folder on
  Debian:

  ```bash
  cd /usr/share/jitsi-meet/prosody-plugins/
  wget -O mod_token_affiliation.lua https://raw.githubusercontent.com/jitsi-contrib/prosody-plugins/main/token_affiliation/mod_token_affiliation.lua
  ```

- Enable module in your prosody config.

  _/etc/prosody/conf.d/meet.mydomain.com.cfg.lua_

  ```lua
  Component "conference.meet.mydomain.com" "muc"
    modules_enabled = {
      "token_verification";
      "token_affiliation";
  ```

- Disable auto-ownership on Jicofo and let the module set the affiliations
  according to the token content.

  ```bash
  hocon -f /etc/jitsi/jicofo/jicofo.conf \
      set jicofo.conference.enable-auto-owner false
  ```

  For old versions, you may set the same value by adding the following line to
  `/etc/jitsi/jicofo/sip-communicator.properties`

  ```conf
  org.jitsi.jicofo.DISABLE_AUTO_OWNER=true
  ```

- If exists, remove or comment `org.jitsi.jicofo.auth.URL` line in
  `/etc/jitsi/jicofo/sip-communicator.properties`

  ```conf
  #org.jitsi.jicofo.auth.URL=...
  ```

- Restart the services

  ```bash
  systemctl restart prosody.service
  systemctl restart jicofo.service
  ```

## A token sample

Set `affiliation` in token. The value may be `owner` or `member`.

A sample token body:

```json
{
  "aud": "myapp",
  "iss": "myapp",
  "sub": "meet.mydomain.com",
  "iat": 1601366000,
  "exp": 1601366180,
  "room": "*",
  "context": {
    "user": {
      "name": "myname",
      "email": "myname@mydomain.com",
      "affiliation": "owner"
    }
  }
}
```

You may create test tokens on [jitok](https://jitok.emrah.com/).
