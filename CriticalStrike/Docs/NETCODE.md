# Netcode

## The shape of it

```
Client                                   Server
──────                                   ──────
build InputCommand (64Hz)
predict locally  ──────────────┐
send last 8 commands (unreliable) ──────► validate (AntiCheat)
                                          re-simulate authoritatively
                                          record lag-compensation frame
                               ┌───────── broadcast delta snapshot (20Hz)
apply to interpolation buffer ◄┘
reconcile local player
render: local = predicted, remote = interpolated
```

The client is authoritative over nothing. It sends *intent* — a move vector, view angles
and a button mask — and the server re-runs the same `MovementSystem.step` the client just
ran. A modified client that sends `moveForward = 12` gets it clamped; one that sends a
teleport gets nothing, because position is never transmitted from client to server at all.

## Prediction and reconciliation

The local player moves the instant a thumb does, because the client simulates its own
movement immediately and keeps every unacknowledged input in `PredictionSystem.pending`.

When an authoritative position arrives, the client snaps to it and replays the inputs the
server had not yet processed. Normally the replayed result matches what was already on
screen and nothing visible happens. When it does not:

- **Error < 0.35 m** — the difference is kept as a `smoothingOffset` and decayed over a few
  frames. The player never sees a teleport; they see their character drift a few centimetres.
- **Error ≥ 0.35 m** — a hard correction. Rare, and a real desync worth seeing.

Sequence numbers are compared wrap-safely (`Int16(bitPattern: a &- b)`), so a 16-bit
sequence space rolling over mid-match is a non-event.

## Interpolation

Everyone else is rendered from `InterpolationBuffer` on a 100 ms delay. That buys enough
slack to absorb mobile jitter, at the cost of aiming 100 ms in the past — which is exactly
what lag compensation then gives back.

The playback clock eases toward its target (8% per snapshot) instead of snapping, so a
latency change produces smooth motion rather than a stutter. Running past the end of the
buffer extrapolates with dead reckoning, capped at 200 ms, so a stalled connection never
sends players sliding through walls.

## Lag compensation

The server records every player's hit volumes each tick for one second. When a shot
arrives, it rewinds every target by:

```
rewind = clamp(roundTripTime / 2 + interpolationDelay, 0, 0.25)
```

and resolves the shot against the world as the shooter actually saw it, interpolating
between recorded frames. That is why a player on 120 ms does not have to lead by a body
width.

The 250 ms cap is the whole defence against a client faking latency to shoot people who are
long gone. It is deliberately generous enough for a bad 4G connection and no more.

## Snapshots

Snapshots are hand-packed, not `Codable`. Mobile data is metered and lossy, so:

- Positions are quantized to 16/14/16 bits over the map's bounds — about 1.5 mm.
- Angles are 12 bits over 2π — 0.09°, below the precision any aim input has.
- Each player carries an 11-bit changed-field mask against the client's last *acknowledged*
  snapshot. A player who did not move costs 19 bits.
- The baseline only advances when the client acknowledges it, so a lost snapshot never
  corrupts the delta chain — the next one simply deltas against the older baseline.
- A baseline mismatch is detected on decode and the client drops the packet and waits for a
  full snapshot rather than rendering garbage.

`SnapshotTests.testDeltaEncodingIsSmallerThanFull` asserts the compression actually works,
which is the kind of thing that silently regresses.

## Transports

| Transport | Use | Why |
| --- | --- | --- |
| `LoopbackTransport` | Offline matches, tests | Configurable latency and packet loss, so the netcode is tested without a network |
| `WebSocketTransport` | Online | The only thing that reliably crosses carrier NAT and captive portals without a relay |
| `LANTransport` | Same Wi-Fi | Network.framework + Bonjour: no server, no account, no internet |

The core only knows the `NetTransport` protocol. Swapping in a QUIC or WebRTC transport is
a new file, not a refactor.

## Anti-cheat

`AntiCheat` is not DRM and does not pretend to be. It makes the obvious client-side hacks
fail by construction:

| Hack | Why it fails |
| --- | --- |
| Speed hack | `deltaTime > 0.12` is rejected; the server owns the clock anyway |
| Teleport | Position is never sent by the client |
| Rapid fire | The weapon state machine owns the cooldown; excess requests are counted |
| Aimbot | Sustained angular velocity above 28 rad/s over many ticks is rejected |
| Wallhack | Not preventable client-side; mitigated by only sending what the mode allows |

Five violations kick. A `suspicionScore` (accuracy, headshot streaks) is exposed for backend
review — never for an automatic ban, because false positives on a legitimately good player
are far more damaging than a slow manual review.
