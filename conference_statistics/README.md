# Conference Statistics

This Prosody component collects conference statistics and sends one final JSON
document to an HTTP endpoint after the main room and all associated breakout
rooms have been destroyed.

The component groups main and breakout rooms by the Jitsi meeting ID and
collects:

- participant presence time;
- microphone unmuted time;
- dominant speaker time from Jitsi `speakerstats`;
- camera enabled time;
- screen sharing time;
- public group chat messages;
- final poll state, including named voters;
- collection and delivery errors.

All timestamps and durations are expressed as Unix time in milliseconds.

## Participant identity

The preferred participant identifier is `context.user.id` from the JWT. If it
is unavailable, the component falls back to the endpoint or occupant ID.

Reconnects and movements between the main room and breakout rooms are kept as
separate connections under the same participant when the identifier remains
stable. Overlapping intervals are merged before totals are calculated.

Focus, Jibri, Jigasi, transcribers and health-check rooms are excluded.

## Collected media state

Microphone, camera and screen-sharing state is read from the modern Jitsi
`SourceInfo` presence element. The legacy `audiomuted`, `videomuted` and
`videoType` fields are also supported as a compatibility fallback.

The participant object contains both totals and the merged source intervals:

```json
{
  "participant_id": "user-123",
  "display_name": "Example User",
  "presence_ms": 3120000,
  "microphone_unmuted_ms": 1800000,
  "dominant_speaker_ms": 420000,
  "camera_enabled_ms": 2700000,
  "screenshare_enabled_ms": 300000,
  "intervals": {
    "presence": [
      {
        "start_ms": 1787135041199,
        "end_ms": 1787138161199
      }
    ]
  }
}
```

Only public MUC `groupchat` messages are collected. Private messages are not
captured.

## HTTP request

The component sends the final document as a raw JSON request body:

```http
POST <api_prefix>/events/conference/statistics
Content-Type: application/json
Idempotency-Key: <meetingId>
```

The endpoint is expected to process the request idempotently. A typical storage
key is:

```text
conferences/<meetingId>.json
```

The component does not write to S3 directly. An HTTP service can validate the
request and write the document to S3 or another object store.

The component retries network failures, timeouts and configured HTTP response
codes asynchronously. Delivery errors discovered by an attempt are included in
the body of the next attempt, while the `Idempotency-Key` remains unchanged.

## Payload

The root document uses the following structure:

```json
{
  "schema": "jitsi-conference-statistics/v1",
  "meeting_id": "meeting-id",
  "generated_at_ms": 1787138161200,
  "collection_complete": true,
  "errors_dropped": 0,
  "conference": {
    "main_room_jid": "room@conference.meet.mydomain.com",
    "started_at_ms": 1787135041199,
    "ended_at_ms": 1787138161199,
    "duration_ms": 3120000
  },
  "rooms": [],
  "participants": [],
  "chat": [],
  "polls": [],
  "errors": []
}
```

## Installation

Copy the module to a Prosody plugin path. On a Debian-based Jitsi Meet
installation, for example:

```bash
cd /usr/share/jitsi-meet/prosody-plugins/
wget -O mod_conference_statistics_component.lua \
  https://raw.githubusercontent.com/jitsi-contrib/prosody-plugins/main/conference_statistics/mod_conference_statistics_component.lua
```

Add a separate component to the Prosody configuration:

_/etc/prosody/conf.d/meet.mydomain.com.cfg.lua_

```lua
Component "cstatistics.meet.mydomain.com" "conference_statistics_component"
    muc_component = "conference.meet.mydomain.com"
    breakout_component = "breakout.meet.mydomain.com"

    api_prefix = "https://example.com/api"
    api_timeout = 10
    api_retry_count = 5
    api_retry_delay = 1

    api_headers = {
        ["Authorization"] = "Bearer TOKEN";
    }

    api_should_retry_for_code = function (code)
        return code == 408 or code == 429 or code >= 500
    end

    max_chat_messages = 50000
    max_tracked_connections = 10000
    max_errors = 1000
```

Restart Prosody after installing the module:

```bash
systemctl restart prosody.service
```

This is a standalone component. Do **not** add
`conference_statistics_component` to the MUC `modules_enabled` list or to
`XMPP_MUC_MODULES`.

## Jitsi Helm example

Mount the module as a custom Prosody plugin and place the component block in
`prosody.extraEnvs.XMPP_CONFIGURATION`:

```yaml
prosody:
  extraVolumes:
    - name: conference-statistics-plugin
      configMap:
        name: conference-statistics-plugin

  extraVolumeMounts:
    - name: conference-statistics-plugin
      subPath: mod_conference_statistics_component.lua
      mountPath: /prosody-plugins-custom/mod_conference_statistics_component.lua

  extraEnvs:
    XMPP_CONFIGURATION: |
      Component "cstatistics.meet.jitsi" "conference_statistics_component"
        muc_component = "muc.meet.jitsi"
        breakout_component = "breakout.meet.jitsi"

        api_prefix = "https://example.com/api"
        api_timeout = 10
        api_retry_count = 5
        api_retry_delay = 1

        api_should_retry_for_code = function (code)
          return code == 408 or code == 429 or code >= 500
        end
```

If `XMPP_CONFIGURATION` already contains another component, append this block
to the same YAML value. Do not declare `XMPP_CONFIGURATION` twice.

## Operational characteristics

- HTTP requests and retry timers are non-blocking.
- Runtime exceptions in MUC hooks are isolated and recorded in `errors`.
- Statistics are held in memory until the conference ends.
- There is no persistent spool. A Prosody restart or exhausted delivery retries
  can cause statistics to be lost.
- The component executes in the Prosody process and is not process-isolated.
  Very large payloads still consume Prosody memory and CPU while the final JSON
  is assembled and encoded.

Safety limits should be selected according to the expected conference size and
chat activity.
