# Conference Statistics

This Prosody component collects conference statistics and sends one final JSON
document to an HTTP endpoint after the main room and all associated breakout
rooms have been destroyed.

It is installed as a standalone Prosody component. It does not modify Jicofo,
JVB, Jibri, or the existing `event_sync` component.

The component associates breakout rooms with their main room and collects:

- participant presence time;
- participant rejoin count;
- microphone unmuted time;
- microphone mute and unmute counts;
- dominant speaker time from Jitsi `speakerstats`;
- camera enabled time and enable/disable counts;
- screen sharing time and start/stop counts;
- public chat message, poll and vote counts;
- public group chat messages (optional, off by default);
- final poll state including named voters (optional, off by default);
- collection and delivery errors.

All timestamps and durations are expressed as Unix time in milliseconds.

## Main and breakout room identity

One document represents one logical conference. Its root `meeting_id` is the
final Jitsi meeting ID of the main room and is also used as the HTTP
`Idempotency-Key`. Participant metrics are conference-wide totals across the
main room and all of its breakout rooms; they are not split per room.

Each `rooms` entry has a `room_id` derived from the node of its XMPP JID. For a
breakout room, this is the same value that `event_sync` reports as
`breakout_room_id`. A breakout entry also contains `breakout_meeting_id`, the
breakout room's own `room._data.meetingId`. Chat and poll entries refer to their
room through `room_id` and `room_jid`.

Jicofo may replace `room._data.meetingId` after room creation. The component
therefore groups rooms in memory by the stable main-room relationship and reads
the final main and breakout meeting IDs as late as possible. It accepts the
main-room links used by current Jitsi modules and falls back to
`speakerStats.sessionId` only when the main meeting ID cannot be read directly.

## Participant identity

The preferred participant identifier is `context.user.id` from the JWT. If it
is unavailable, the component falls back to the endpoint or occupant ID.

Totals are accumulated online per participant and are not stored as connection
or state-change timelines. Overlapping main-room, breakout-room, or reconnect
connections use reference-counted effective state, so their durations are not
counted twice.

`rejoin_count` is incremented when a JWT-identified participant joins with a
new endpoint ID after all previous connections have ended. Moving between
rooms with an endpoint ID already seen for that participant is not a rejoin.
Without a stable JWT user ID, a new endpoint ID is a new participant and cannot
be reliably correlated as a rejoin.

Focus, Jibri, Jigasi, transcribers and health-check rooms are excluded.

## Collected media state

Microphone, camera and screen-sharing state is read from the modern Jitsi
`SourceInfo` presence element. The legacy `audiomuted`, `videomuted` and
`videoType` fields are also supported as a compatibility fallback.

The participant object contains compact totals and transition counters:

```json
{
  "participant_id": "user-123",
  "participant_id_source": "jwt",
  "display_name": "Example User",
  "email": "user@example.com",
  "endpoint_ids": ["endpoint-1", "endpoint-2"],
  "presence_ms": 3120000,
  "rejoin_count": 1,
  "microphone_unmuted_ms": 1800000,
  "microphone_unmute_count": 4,
  "microphone_mute_count": 4,
  "dominant_speaker_ms": 420000,
  "camera_enabled_ms": 2700000,
  "camera_enable_count": 2,
  "camera_disable_count": 2,
  "screenshare_enabled_ms": 300000,
  "screenshare_start_count": 1,
  "screenshare_stop_count": 1,
  "chat_message_count": 1,
  "poll_vote_count": 1
}
```

The initial media state of a connection establishes its baseline and does not
increment a transition counter. Repeated presence stanzas with the same state
also do not increment counters. A connection ending removes its active state
without counting it as a user mute, camera disable, or screen-share stop.

Only public MUC `groupchat` messages are collected. Private messages are not
captured.

## Chat and polls

Chat and poll **content** is not collected unless it is explicitly enabled.
Counts are always reported, so a deployment can measure chat and poll activity
without keeping any message body, question, option text or voter identity:

- `chat_message_count` on the conference and on each room: the number of
  messages sent in it;
- `poll_count` on the conference and on each room: the number of polls;
- `poll_vote_count` on the conference and on each room: the number of votes,
  counting each participant at most once per poll.

Set `include_chat_content = true` to collect the `chat` array and
`include_poll_content = true` to collect the `polls` array. Both default to
`false`. When a section is disabled its array is present but empty.

`max_chat_messages` bounds the message count as well as the stored bodies, so
counting stops once it is reached and a `limit_reached` error is recorded. Poll
and vote counts are bounded by Jitsi's own limit of 128 polls per room.

Content is user-supplied conference material rather than a statistic and the
resulting document is a durable off-box copy of it. Enabling either option
makes the endpoint operator responsible for its retention and deletion.

Each public chat entry contains the stanza/message ID, timestamp, room ID and
JID, sender participant and endpoint IDs, sender display name, and message
body. Messages from the main room and breakout rooms are stored in the same
`chat` array.

A message body longer than `max_chat_message_length` is truncated at a UTF-8
character boundary. Chat content dominates the memory this component holds, so
this limit and `max_chat_messages` together bound the worst case per meeting.

Polls are read from the final `room.polls` state when each room is destroyed.
Each poll contains its creator, question, options, and the current named voters
for every option. If a participant changes a vote, only the final state is
reported.

## HTTP request

The component sends the final document as a raw JSON request body:

```http
POST <api_prefix>/events/conference/statistics
Content-Type: application/json
Idempotency-Key: <main-room-meetingId>
```

The endpoint is expected to process the request idempotently. A typical storage
key is:

```text
conferences/<main-room-meetingId>.json
```

The component does not write to S3 directly. An HTTP service can validate the
request and write the document to S3 or another object store.

The component retries network failures, timeouts and configured HTTP response
codes asynchronously. Delivery errors discovered by an attempt are included in
the body of the next attempt, while the `Idempotency-Key` remains unchanged.

The endpoint is responsible for treating `meeting_id` or `Idempotency-Key` as
the object identity. The component has no persistent delivery spool.

## Payload

Example of a complete successful document:

```json
{
  "schema": "jitsi-conference-statistics/v1",
  "meeting_id": "378f2f94-5e2b-4a31-9ae4-2c99d424fa98",
  "generated_at_ms": 1787138161200,
  "collection_complete": true,
  "errors_dropped": 0,
  "conference": {
    "main_room_jid": "99d75fd4-a65f-4580-865d-0f3a2cd9d800@conference.meet.mydomain.com",
    "started_at_ms": 1787135041199,
    "ended_at_ms": 1787138161199,
    "duration_ms": 3120000,
    "chat_message_count": 1,
    "poll_count": 1,
    "poll_vote_count": 1
  },
  "rooms": [
    {
      "room_id": "99d75fd4-a65f-4580-865d-0f3a2cd9d800",
      "jid": "99d75fd4-a65f-4580-865d-0f3a2cd9d800@conference.meet.mydomain.com",
      "is_breakout": false,
      "started_at_ms": 1787135041199,
      "ended_at_ms": 1787138161199,
      "duration_ms": 3120000,
      "chat_message_count": 0,
      "poll_count": 1,
      "poll_vote_count": 1
    },
    {
      "room_id": "8fcfc934-76d8-40ce-8ef8-bc5d257a164e",
      "jid": "8fcfc934-76d8-40ce-8ef8-bc5d257a164e@breakout.meet.mydomain.com",
      "is_breakout": true,
      "breakout_meeting_id": "b719fb04-64b3-40cd-bfea-0fa48017f132",
      "started_at_ms": 1787136000000,
      "ended_at_ms": 1787136600000,
      "duration_ms": 600000,
      "chat_message_count": 1,
      "poll_count": 0,
      "poll_vote_count": 0
    }
  ],
  "participants": [
    {
      "participant_id": "user-123",
      "participant_id_source": "jwt",
      "display_name": "Example User",
      "email": "user@example.com",
      "endpoint_ids": [
        "endpoint-1",
        "endpoint-2"
      ],
      "presence_ms": 3120000,
      "rejoin_count": 1,
      "microphone_unmuted_ms": 1800000,
      "microphone_unmute_count": 4,
      "microphone_mute_count": 4,
      "dominant_speaker_ms": 420000,
      "camera_enabled_ms": 2700000,
      "camera_enable_count": 2,
      "camera_disable_count": 2,
      "screenshare_enabled_ms": 300000,
      "screenshare_start_count": 1,
      "screenshare_stop_count": 1,
      "chat_message_count": 1,
      "poll_vote_count": 1
    }
  ],
  "chat": [
    {
      "message_id": "message-42",
      "sent_at_ms": 1787136200000,
      "room_id": "8fcfc934-76d8-40ce-8ef8-bc5d257a164e",
      "room_jid": "8fcfc934-76d8-40ce-8ef8-bc5d257a164e@breakout.meet.mydomain.com",
      "sender_participant_id": "user-123",
      "sender_endpoint_id": "endpoint-2",
      "sender_display_name": "Example User",
      "body": "Hello from the breakout room"
    }
  ],
  "polls": [
    {
      "poll_id": "poll-1",
      "room_id": "99d75fd4-a65f-4580-865d-0f3a2cd9d800",
      "room_jid": "99d75fd4-a65f-4580-865d-0f3a2cd9d800@conference.meet.mydomain.com",
      "creator_endpoint_id": "endpoint-1",
      "creator_participant_id": "user-123",
      "creator_name": "Example User",
      "question": "Continue the meeting?",
      "options": [
        {
          "option_index": 1,
          "text": "Yes",
          "voters": [
            {
              "voter_id": "endpoint-1",
              "participant_id": "user-123",
              "name": "Example User"
            }
          ]
        },
        {
          "option_index": 2,
          "text": "No",
          "voters": []
        }
      ]
    }
  ],
  "errors": []
}
```

`collection_complete` is `false` if the component recorded an error or dropped
errors because `max_errors` was reached. Error entries are deduplicated and
contain their occurrence count and first/last timestamps:

```json
{
  "code": "http_response_error",
  "stage": "delivery",
  "message": "Endpoint returned HTTP 500",
  "first_at_ms": 1787138161300,
  "last_at_ms": 1787138162300,
  "count": 2,
  "context": {
    "attempt": "1",
    "http_status": "500"
  },
  "last_context": {
    "attempt": "2",
    "http_status": "500"
  }
}
```

Optional fields such as `email`, display names, participant mappings, or error
contexts may be absent when Prosody cannot resolve them. Empty collections are
encoded as JSON arrays, not objects.

## Installation

### Debian-based Jitsi Meet

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

    include_chat_content = false
    include_poll_content = false

    max_chat_messages = 2000
    max_chat_message_length = 4096
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

## Configuration

| Option | Required | Default | Description |
| --- | --- | --- | --- |
| `muc_component` | yes | none | JID of the main conference MUC component. |
| `breakout_component` | yes | none | JID of the breakout-room MUC component. |
| `api_prefix` | yes | none | Endpoint base URL without a trailing slash. |
| `api_timeout` | no | `20` | HTTP request timeout in seconds. |
| `api_retry_count` | no | `3` | Additional attempts after the initial request. |
| `api_retry_delay` | no | `1` | Delay between attempts in seconds. |
| `api_headers` | no | `{}` | Additional HTTP request headers. |
| `api_should_retry_for_code` | no | 408, 429, 5xx | Function deciding which HTTP status codes are retryable. |
| `include_chat_content` | no | `false` | Collect chat message bodies. Counts are reported either way. |
| `include_poll_content` | no | `false` | Collect poll questions, options and named voters. Counts are reported either way. |
| `max_chat_messages` | no | `2000` | Maximum collected public chat messages per meeting. |
| `max_chat_message_length` | no | `4096` | Maximum collected bytes per chat message body. |
| `max_tracked_connections` | no | `10000` | Maximum accepted participant connection sessions per meeting. |
| `max_errors` | no | `1000` | Maximum distinct error entries per meeting. |

Network failures and timeouts are always retryable while attempts remain.
Other 4xx responses are final unless the configured retry predicate includes
them. Reaching a safety limit records a `limit_reached` error in the payload.

## Jitsi Helm example

Mount the module as a custom Prosody plugin and place the component block in
`prosody.extraEnvs.XMPP_CONFIGURATION`:

Create the ConfigMap from the canonical module file, for example:

```bash
kubectl -n jitsi create configmap conference-statistics-plugin \
  --from-file=mod_conference_statistics_component.lua=conference_statistics/mod_conference_statistics_component.lua
```

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

The module file is mounted as
`/prosody-plugins-custom/mod_conference_statistics_component.lua`; the
component block loads it by the provider name `conference_statistics_component`.

## Operational characteristics

- HTTP requests and retry timers are non-blocking.
- Runtime exceptions in MUC hooks are isolated and recorded in `errors`.
- Hook handlers always return `nil`, so a statistics failure does not stop the
  MUC event chain.
- Compact participant totals, active connections, chat, polls, and errors are
  held in memory until the conference ends. Closed connection and media-state
  timelines are not retained.
- There is no persistent spool. A Prosody restart or exhausted delivery retries
  can cause statistics to be lost.
- The component executes in the Prosody process and is not process-isolated.
  Final JSON assembly and encoding are synchronous, so very large payloads
  still consume Prosody memory and CPU at conference finalization.
- If all delivery attempts fail, the endpoint cannot receive the final
  `delivery_exhausted` error because no persistent spool or second error sink
  is configured. The failure is written to the Prosody log.

Safety limits should be selected according to the expected conference size and
chat activity. Chat content will normally dominate memory use after participant
timelines have been removed, so `max_chat_messages` multiplied by
`max_chat_message_length` is the figure to size against.
