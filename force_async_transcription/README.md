# Force Async Transcription

This plugin enables the async transcription for all rooms. It is needed by
[opus-transcriber-proxy](https://github.com/jitsi/opus-transcriber-proxy).

## Installation

- Prerequisites:
  - Set up the bridge based transcription and test that the bridge reaches
    `opus-transcriber-proxy`.

- Copy this script to the Prosody plugins folder. It's the following folder on
  Debian

  ```bash
  cd /usr/share/jitsi-meet/prosody-plugins/
  wget -O mod_force_async_transcription.lua https://raw.githubusercontent.com/jitsi-contrib/prosody-plugins/main/force_async_transcription/mod_force_async_transcription.lua
  ```

- Enable the module in your prosody config.

  _/etc/prosody/conf.d/meet.mydomain.com.cfg.lua_

  ```lua
  Component "conference.meet.mydomain.com" "muc"
    modules_enabled = {
      -- ... existing modules
      "force_async_transcription";
    }
  ```

- Restart prosody

  ```bash
  systemctl restart prosody.service
  ```
