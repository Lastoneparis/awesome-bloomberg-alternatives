# SALVO — TODO

Updated at the end of every phase. `[x]` means done **and verified**; anything verified only
by reading is marked `[~]` with what is missing.

---

## Phase 1 — Architecture + simulation core  *(complete)*

### Done and verified
- [x] Inspect repository; confirm no Unity project exists
- [x] Confirm toolchain: .NET SDK 8.0.131, NuGet reachable, `dotnet test` works
- [x] Confirm `netstandard2.1` + C# 9 compiles (Unity 6's profile)
- [x] `ARCHITECTURE.md`, `PROJECT_PLAN.md`, `TODO.md`, `ORIGINALITY.md`
- [x] Folder structure
- [x] Decide multiplayer architecture (NGO for session, own tick sim for gameplay)
- [x] Decide Unity version and package set
- [x] Core value types (`Vec3`, `ViewAngles`, `FixedClock`, `ContentId`, `DeterministicRandom`)
- [x] Data definitions: Weapon, Character, Map, World, Faction, GameMode, BotDifficulty,
      Attachment — POCOs behind `IContentCatalog<T>`, each with its own `Validate`
- [x] Collision world (uniform grid over AABB brushes), box sweep, depenetration
- [x] Movement simulation — collide-and-slide, step-up, stances, coyote time, fall damage
- [x] Spawn selection, scored on enemy proximity, line of sight, friends and recent use
- [x] Weapon state machine, ballistics, damage model with hitboxes, lag compensation
- [x] `IGameMode` + Team Deathmatch + Free-For-All
- [x] Bots at four difficulties, constrained to the same input interface as a player
- [x] `MatchSimulation` tying it together
- [x] 63 xUnit tests covering all of the above
- [x] `Salvo.Headless` — plays a full bot match and prints a scoreboard, and **fails** if
      nobody moved, shot, hit, died, or if anyone left the map
- [x] CI workflow: build, tests, bridge compile, four playable-match runs, determinism check
- [x] Unity `Packages/manifest.json` and `ProjectSettings/ProjectVersion.txt`
- [x] Assembly definitions — `Salvo.Sim` has `noEngineReferences: true`, which is the
      architecture's guardrail rather than a comment about it
- [x] `Salvo.Bridge.Check` — compiles the Unity layer against a stub UnityEngine. Verified to
      catch a Sim-side rename by deliberately renaming one.

### Written but NOT verified — no Unity in this environment
- [~] ScriptableObject wrappers over the definitions — compile against the shim only
- [~] `PrototypeHost`, `LocalPlayerInput`, `MapGeometryBuilder`, `SalvoConvert` — compile
      against the shim only; none has run a frame
- [~] Editor menu item that builds the prototype scene from code — never executed. The scene
      it writes has never existed.

The shim is honest about its limits: see `Sim/Salvo.UnityShim/README.md`. A green bridge
build means the code is consistent with itself and with the simulation, **not** that it
matches real Unity 6. Expect to fix something on first open.

---

## Phase 6 — Networking  *(simulation side complete)*

### Done and verified
- [x] Bit-level wire format with explicit field widths and quantisation
- [x] Snapshots with delta encoding against a client-acknowledged baseline
- [x] `SimulatedLink` — deterministic latency, jitter, loss and reordering
- [x] Client prediction with server reconciliation and input replay
- [x] Entity interpolation, short-way-round angles, insertion of late snapshots
- [x] Server-side input queue: one command simulated per tick, with a 2-tick jitter buffer
- [x] `salvo-headless --net` — a real server and real clients over a lossy link, in process

Measured over a 120 s, 10-client team deathmatch:

| Link | Mean error | Worst | Corrections | Downstream |
| --- | --- | --- | --- | --- |
| perfect | 0.001 m | 0.02 m | 0.3% | 22 kbit/s |
| mobile (60 ms, 1% loss) | 0.008 m | 0.49 m | 9.3% | 22 kbit/s |
| poor (150 ms, 5% loss) | 0.045 m | 1.36 m | 45% | 23 kbit/s |

Error is the client's prediction against the server's result *for the same input tick* —
not the gap between their current positions, which is latency times speed and is prediction
working rather than failing. The budget is 64 kbit/s downstream at 10v10.

### Not done
- [ ] No real transport. `SimulatedLink` is in-process; NGO is not wired up.
- [ ] No connection lifecycle: joining mid-match, dropping, rejoining, timing out.
- [ ] Shots are resolved server-side with lag compensation but are **not** predicted on the
      client, so a hit marker will lag by a round trip.
- [ ] Snapshots carry no events. Kills, impacts and sounds are computed but never sent.
- [ ] Nothing is encrypted or authenticated. The wire format trusts its peer entirely.

---

## 5v5 round objective  *(playable)*

- [x] `OverloadMode` — rounds, freeze time, no respawn, arm/disarm with a fuse, elimination,
      sides swapped at half time
- [x] `IGameMode.TryGetObjectiveOrder` — bots play the objective without knowing which mode
      they are in, so a new mode does not mean a new branch inside the AI
- [x] `GameModes.Create` — one place that maps a mode kind to an implementation, and throws
      for a kind with none rather than quietly substituting deathmatch
- [x] Two relay sites on the starter map, with a test that a player can stand in each
- [x] 13 tests for the round lifecycle, which had never run before this mode existed

Measured over a full 13-round match, 10 bots:

| Difficulty | Result | Charges armed | Attacker time on site |
| --- | --- | --- | --- |
| easy | 7-5 attackers | 7 | 122 s |
| normal | 5-7 defenders | 8 | 97 s |
| hard | 5-7 defenders | 9 | 91 s |
| expert | 4-7 defenders | 5 | 85 s |

The first site placement was 14 m from the defenders' spawn and 50 m from the attackers'.
Every test still passed and average bots armed seven times a match, but at higher skill the
defenders simply arrived first: attackers took one round in eight. The format is meant to
favour defenders; a 36 m head start decides it rather than favouring it. Moved to the flanks
near the midpoint, which is what the table above measures.

### Known gaps
- [ ] No buy phase or economy. Everyone starts each round with the same loadout.
- [ ] Bots do not coordinate a push, hold angles, or rotate between sites — they walk to the
      ordered position and fight whatever they meet.
- [ ] No carried-charge model: any attacker can arm, rather than one carrying it.

---

## Second era  *(the architecture test)*

PROJECT_PLAN.md set the bar: if adding an era requires touching the player controller, the
design failed. It did not.

- [x] `IWorldContent` — an era declares its weapons, attachments, factions, characters and
      maps; it does not declare modes or bot difficulties, which are rules and are shared
- [x] `WartimeWorld` — a 1940s era: five weapons, two attachments, two factions, one map
- [x] `Loadouts.TryBuildDefault` — a loadout drawn from the map's own world
- [x] 16 tests, including that each world validates standing alone

**The diff for the whole era touched no file under `Movement/`, `Combat/`, `Modes/`, `AI/`,
`Net/`, `Match/`, `World/`, `Math/` or `Core/`.** Only `Content/` and a new test file.

It is not a reskin, and that is testable rather than asserted. The era pushes on parts of the
data model the modern one never used:

| | Modern | Wartime |
| --- | --- | --- |
| Mean rate of fire | 618 rpm | 305 rpm |
| Mean damage | 27 | 43 |
| Optics available | yes | none — the slot is simply not listed |
| Bolt action | no | yes, with round-by-round reloading |
| Map shape | flat, symmetric, raised centre | a pit with terraced rim |
| Bot hit rate, same difficulty | 56% | 31% |

The hit-rate gap is the data model working: iron sights and higher spread make the same bots
measurably less accurate, with no code aware of which era it is running.

### Known gaps
- [ ] `Loadouts` picks by weapon class round-robin. There is no loadout UI, no saved
      preference, and no per-faction restriction yet.
- [ ] The quarry favours attackers in the objective mode (7-3) where Junction favours
      defenders (4-7 to 5-7). Both are playable; neither has been tuned.
- [ ] Era is content, but there is still only one `MovementTuning`. A heavier era would want
      its own, and the type is ready for it — nothing reads it per world yet.

---

## Progression  *(simulation side complete)*

- [x] `XpCurve` — integer arithmetic, quadratic, capped at level 100
- [x] `PlayerProgress` — career stats, per-weapon stats, unlocks
- [x] `RewardRules` — experience from a finished match, computed server-side only
- [x] `UnlockTable` — what each level grants, validated against the catalogue
- [x] 20 tests

### The rule this phase is built around

**No weapon is ever locked behind a level, and `UnlockTable.Validate` rejects one that is.**

Gating weapons by level is the genre default and it is a fairness problem wearing a
progression costume: a new player meets a veteran carrying something they cannot yet hold, and
the difference is time served rather than skill. The brief forbids *selling* a competitive
advantage; granting one for grinding is the same advantage at a slower price, and worse in one
respect — invisible to anyone auditing the store. Progression grants cosmetics, titles and
attachments, and attachments must already have a downside.

### The reward curve

Participation is the largest component for any ordinary match, on purpose. A kill-weighted
curve rewards whoever was already winning and quietly teaches a team that playing the
objective costs them something. Measured over a 13-round objective match, the top scorer
earned 3026 and the bottom 1116 — a 2.7:1 spread from a 15:1 spread in kills. There is no loss
penalty: losing already costs the win bonus, and taking experience away rewards quitting a
losing game early.

### Known gaps
- [ ] Nothing is persisted. `PlayerProgress` lives in memory; there is no account store.
- [ ] No challenges, dailies, or seasons.
- [ ] No cosmetic content exists yet — the unlock table grants ids nothing renders.
- [ ] Career stats are not surfaced to a client; the snapshot carries none of them.

---

## Live content  *(the correctness half)*

- [x] `ContentManifest` — a fingerprint of a content set, split in two
- [x] `ContentCompatibility` — the gate a client passes before it may join
- [x] `ContentPatch` — content added or rebalanced over a base catalogue, without mutating it
- [x] Manifest exchanged in the `NetServer` handshake
- [x] 23 tests

### Why two hashes

A **simulation** hash covers everything the authoritative simulation reads: damage, spread,
timings, map geometry, mode rules. A mismatch refuses the connection, because two machines
running different weapon statistics produce a match where prediction never settles and damage
numbers disagree — and every symptom of that points at the netcode. Nothing errors. It is the
nastiest bug class this project can have.

A **presentation** hash covers display, model and sound keys. A mismatch is logged and
allowed, because blocking would mean a translation fix could not ship without forcing the
whole fleet to update at the same moment.

The split is tested from both sides: changing `BaseDamage` must move the simulation hash;
changing `DisplayNameKey` must not.

### What a patch may and may not do

A patch **adds** and **replaces**; it cannot remove. Removing a weapon mid-season breaks every
saved loadout referencing it, every replay and every statistics page, and does so server-side
where the player cannot see why. Retiring content means leaving the definition and taking it
out of the pools, which a replace does.

A patch ships **data, not code**. A new weapon, map, attachment or balance number needs no
client update; a new mode's *rules* are an `IGameMode` implementation and do.
`ContentPatch.ValidateAgainst` rejects a patch adding a mode kind nothing in the build
implements, rather than letting it appear in a menu and throw when chosen.

### Not anti-cheat

A modified client can report whatever hash it likes. That is fine and not what this is for:
the server already refuses to take a client's word for damage, health, position or hits, so
altered client content changes what that client *draws* and nothing about what happens. This
catches the honest case — a partial download, a stale build, a patch that reached half the
fleet.

### Known gaps
- [ ] Nothing is downloaded. There is no CDN, no Addressables wiring, no patch transport.
- [ ] No staged rollout, feature flags, or per-region content.
- [ ] The manifest is exchanged but not signed, so it is a correctness check only.
- [ ] No content authoring pipeline: a patch is constructed in code, not loaded from JSON.

---

## Friends and parties  *(data model and rules)*

- [x] `SocialGraph` — friends, pending requests, blocks, account deletion
- [x] `Party` — invitations, leadership migration, ready state, mode-aware size cap
- [x] 25 tests

### Blocking is the load-bearing feature, not friending

Friend lists fail harmlessly. Block lists fail by exposing someone to a person they have
deliberately shut out, so blocking is enforced at the graph level and is stronger than every
other relationship:

- it severs an existing friendship, because a block that leaves one in place does nothing the
  moment any code path consults the friend list instead of the block list — and there will
  always be such a path;
- it cancels pending requests in both directions;
- it is **one-sided in intent, mutual in effect**. A block that only stops the blocked party
  lets the blocker keep sending invitations to someone with no way to refuse them;
- it applies to party invitations, checked against *every* member rather than the leader, and
  re-checked on acceptance so an invitation is not a licence that outlives the block;
- `Party.EnforceBlocks` ejects immediately, so blocking someone you are currently partied with
  works now rather than whenever the party happens to disband.

Each of those was verified by breaking it: making blocks one-directional fails four tests,
and removing the check from party invitations fails two.

### Privacy

The graph stores account ids and nothing else — no names, no history, no timestamps, no
"people you may know". §33 forbids invasive practices and the cheapest way to honour that is
to have nowhere to put the data.

`ForgetAccount` erases in every direction **including other people's block lists**. Keeping
those is the tempting choice, and it is wrong: a deleted id is never reissued, so a retained
entry protects nobody and can only serve as a record of who someone once blocked.

### Known gaps
- [ ] Nothing is persisted or networked. No Unity Lobby, no platform friends, no presence.
- [ ] Reporting is not built. Blocking is personal; reporting goes to moderation and needs a
      service, a queue and a policy — none of which exist.
- [ ] No voice, no text chat, so none of the moderation those need.
- [ ] Party membership does not yet reach matchmaking; `CanQueueFor` answers the question but
      nothing asks it.

---

## Matchmaking  *(rules and balancing)*

- [x] `MatchmakingTicket` — a party in the queue; a solo is a party of one, with no special case
- [x] `Matchmaker` — selection, avoidance, team assignment, map choice, bot fill
- [x] `MatchProposal` — a formed match, usable directly as `MatchSimulation` input
- [x] `salvo-headless --matchmaking` — queues sixty in parties and checks every match formed
- [x] 33 tests

### Four rules, in priority order

The order is the design, because the rules conflict — perfect balance is easy if you may split
parties and ignore blocks.

1. **Blocked players never share a match.** Not merely never share a team: in the same match, A
   still sees B's name, is shot by B, and can be followed by B.
2. **A party is never split.** People queue together to play together.
3. **Teams are even in size**, counting bots.
4. **Teams are close in skill** — the only rule that bends, widening with wait time.

Rule 1 is never relaxed to fill a lobby. That trade — a visible empty queue, which players
understand and metrics record, for an invisible one where somebody is matched with a person
they deliberately avoided and nothing notes it — is not one to make silently. Avoidance is
counted and reported *even when a match forms anyway*, which is the case that matters most: the
queue fills fine, nothing looks wrong, and one player is quietly never matched with anybody.

### Two bugs the volume run found that the unit tests did not

- A ticket the matchmaker selected but could not fit on either side was **removed from the
  queue and placed in no match**. A sixty-player run showed 56 placed and none still waiting.
- A party whose own members had blocked each other passed every check, because avoidance was
  only tested against already-chosen accounts. Such a party should not exist, but the matchmaker
  receives tickets rather than parties and cannot verify where they came from.

Both are now unit-tested, and both safety rules were verified by breaking them: relaxing
avoidance fails five tests, and filling teams in queue order fails the skill-spread test.

### Known gaps
- [ ] Skill is a placeholder derived from career record, not a rating system.
- [ ] No regions, no latency-based matching, no backfill into a match in progress.
- [ ] Nothing consumes `MatchProposal` in production — there is no session service to hand it to.
- [ ] Human team balance is not asserted: with unsplittable parties a lobby of one five-stack
      has no even human split, so bots even the sides and the imbalance is reported, not failed.

---

## Known issues / decisions deferred

- [ ] **Trademark search for "SALVO"** before any public use. Codename only.
- [ ] Ranked needs dedicated servers; Relay is host-authoritative and cheatable by the host
- [ ] Input-based matchmaking pools (touch vs mouse) — decide before ranked
- [ ] Localisation tables exist from the first UI string, not retrofitted
- [ ] Nothing under `Unity/Assets/Salvo/Runtime/` or `Editor/` has run inside Unity
- [ ] Ballistics is hitscan only. `WeaponDefinition.Validate` rejects a weapon with a muzzle
      velocity rather than silently firing it as hitscan — projectiles wait for a phase where
      their interaction with lag compensation can be built and tested properly.
- [ ] Bot navigation is direct steering with local avoidance, not pathfinding. Fine on the
      open arena that ships; a map with a dead end would trap a bot in it. No such map should
      be added before Phase 9.
- [ ] `MapGeometryBuilder` emits every face, including ones buried inside neighbouring
      brushes. Correct, and wasteful; face culling belongs with the rest of the map pipeline.
- [ ] No real network transport. Prediction, reconciliation, interpolation and the wire
      format are built and measured against a simulated lossy link, but nothing has crossed
      a socket. NGO integration is the remaining half of Phase 6.

---

## Repository note

`/CriticalStrike` in this repository is a **separate, earlier Swift/SceneKit project**, not
part of SALVO. It is untouched. Two things about it are worth flagging:

1. Its name is one the brief explicitly says not to reuse. If anything from it is ever
   carried forward, it needs renaming first.
2. Its test suite currently has failures unrelated to SALVO (spawns inside geometry,
   ballistics registration, attachment balance). They are recorded in that project, not
   here.
