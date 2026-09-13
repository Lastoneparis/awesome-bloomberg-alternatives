# Package set

Unity 6 LTS (6000.0 LTS). The version in `../ProjectSettings/ProjectVersion.txt` is the one
this manifest was written for; Unity will offer to upgrade the project on first open, and
that is fine for patch releases within 6000.0.

## Why each package is here

| Package | Why |
| --- | --- |
| `render-pipelines.universal` | URP. The only pipeline with a credible mobile story; HDRP is not a mobile target and the built-in pipeline is on its way out. |
| `inputsystem` | One input map serving touch, gamepad, keyboard and mouse. The old `Input` class cannot express a touch layout and a gamepad layout as the same action. |
| `netcode.gameobjects` | Transport, connection and session. See ARCHITECTURE.md §3 for why NGO rather than Netcode for Entities, Fusion or Mirror — and for why we still run our own tick simulation on top of it. |
| `services.authentication` | Anonymous and platform sign-in. Required by Lobby and Relay. |
| `services.lobby` | Party and match assembly before a session exists. |
| `services.relay` | NAT traversal. Note that Relay is host-authoritative, which is a real limitation and is discussed honestly in ARCHITECTURE.md §4. |
| `services.multiplayer` | The umbrella SDK the above three are converging into; pinned so the transition is a deliberate change rather than a surprise. |
| `addressables` | Content loading. Worlds are downloadable, so content cannot live in `Resources`. |
| `localization` | §22 forbids hardcoded user-facing strings. Every `DisplayNameKey` in the simulation is a key for this. |
| `test-framework` | Play-mode tests for the Unity layer. Edit-mode tests for the simulation are run by `Sim/Salvo.Sim.Tests` instead, which does not need Unity at all. |

## Deliberately absent

- **Cinemachine** — a first-person camera is a transform follow. Cinemachine earns its place on
  third-person and cutscene work, neither of which exists here.
- **DOTS / Entities** — the player counts in the brief (2–10, later 10v10) are two orders of
  magnitude below where ECS pays for its complexity.
- **Any analytics or attribution SDK** — §33 and §34. Nothing that tracks a player goes in
  without a stated purpose and consent, and none is needed yet.
- **Mirror, FishNet, Photon** — evaluated and not chosen; see ARCHITECTURE.md §3.

## Unverified

This file and `manifest.json` have not been opened by Unity in this environment — there is no
Unity here. The version numbers were chosen to be mutually consistent for Unity 6000.0 LTS, but
the first person to open the project should expect to resolve at least one version bump, and
should treat that as expected rather than as a fault.
