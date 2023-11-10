# Security On-Demand

This plugin dynamically enables/disables lobby or set/unset password for the
meeting room. The participant can update these values if they have permission to
join the meeting room.

## Installation

- Prerequisites:

  - Enable the lobby feature and test that it works as expected when manually
    activated by a moderator.

  - Set up
    [JWT auth](https://github.com/jitsi/lib-jitsi-meet/blob/master/doc/tokens.md)
    and check that it works before proceeding.

  - Check that you have
    `/usr/share/jitsi-meet/prosody-plugins/mod_persistent_lobby.lua`. If it's
    not there, that means your version of Jitsi does not yet include
    [this PR](https://github.com/jitsi/jitsi-meet/pull/12215) which is required.

- Copy this script to the Prosody plugins folder. It's the following folder on
  Debian:

  ```bash
  cd /usr/share/jitsi-meet/prosody-plugins/
  wget -O mod_token_security_ondemand.lua https://raw.githubusercontent.com/jitsi-contrib/prosody-plugins/main/token_security_ondemand/mod_token_security_ondemand.lua
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
      "token_security_ondemand";
    }
  ```

- Restart the services

  ```bash
  systemctl restart prosody.service
  ```

## Token samples

A sample token body to activate lobby and set a password for a room:

```json
{
  "room": "myRoomName",
  "context": {
    "user": {
      "name": "myname",
      "email": "myname@mydomain.com"
    },
    "room": {
      "lobby": true,
      "password": "mypassword"
    }
  },
  "aud": "myapp",
  "iss": "myapp",
  "sub": "meet.mydomain.com",
  "iat": 1601366000,
  "exp": 1601366180
}
```

To enable lobby:

```json
  "context": {
    "room": {
      "lobby": true
    }
  }
```

To disable lobby:

```json
  "context": {
    "room": {
      "lobby": false
    }
  }
```

To set a password:

```json
  "context": {
    "room": {
      "password": "mypassword"
    }
  }
```

To unset password:

```json
  "context": {
    "room": {
      "password": ""
    }
  }
```

To allow a participant to bypass security checks:

```json
  "context": {
    "user": {
      "security_bypass": true
    }
  }
```
