# Salvo

A cross-platform multiplayer FPS for iPhone, iPad and Mac. Unity 6 LTS, URP, C#.

**Original IP.** Inspired by the fast, readable competitive shooters that define the genre;
nothing is copied from any of them. See [ORIGINALITY.md](ORIGINALITY.md) for the rules this
project holds itself to, every invented name currently in use, and the fact that **"Salvo" is
a codename that has not been trademark-searched**.

---

## The one decision everything else follows from

**The simulation does not reference `UnityEngine`.**

```
Unity/Assets/Salvo/Sim/       the game. Pure C#. netstandard2.1. No engine.
Unity/Assets/Salvo/Runtime/   Unity presentation: rendering, input, audio, netcode glue.
Sim/                          .NET projects that compile the SAME Sim/ source files.
```

`Sim/` is not a copy — it is the same files, compiled for .NET via a csproj glob. That buys
three things: a dedicated server that does not need Unity, a test suite that does not need a
licence, and a compile-time guardrail, because `Salvo.Sim.asmdef` sets
`noEngineReferences: true` and the build fails if anyone reaches for `UnityEngine`.

Read [ARCHITECTURE.md](ARCHITECTURE.md) before changing anything structural. §6 is the honest
account of what is verified and what is not.

## Running it without Unity

```bash
cd Sim
dotnet test Salvo.Sim.Tests/Salvo.Sim.Tests.csproj          # the simulation's tests
dotnet run  --project Salvo.Headless -- --seconds 700        # plays a full bot match
dotnet run  --project Salvo.Headless -- --help
```

`Salvo.Headless` runs the real `MatchSimulation` with the real content, movement model and
bots — the same code a dedicated server would run — and prints a scoreboard. It **exits
non-zero** if nobody moved, nobody fired, nothing was hit, nobody died, or anyone left the
map, so "it compiled" is never mistaken for "it works".

A 6-bot team deathmatch reaches its own 50-kill limit in ~370 s of match time and about a
second of wall clock.

## Running it in Unity

Open `Unity/` in Unity 6 LTS (6000.0). Then `Salvo → Build Prototype Scene` from the menu bar,
and press Play.

**This has never been done.** There is no Unity in the environment this was written in. The
bridge code under `Runtime/` and `Editor/` is compiled in CI against a stub `UnityEngine`
(`Sim/Salvo.UnityShim`), which proves it is consistent C# that agrees with the simulation —
not that it matches real Unity. Expect to fix something on first open.

## A note on CI

`.github/workflows/ci.yml` is complete and passes locally, but **GitHub Actions will not run
it while this repository is private and the account's Actions billing is blocked.** The first
run failed before starting a single step, with:

> The job was not started because recent account payments have failed or your spending limit
> needs to be increased.

Private repositories bill Actions minutes; public ones get them free. So there are three ways
forward, and the choice is about money and about how visible this source should be, not about
the code:

1. Clear the billing block or raise the spending limit, and CI runs as written.
2. Make the repository public — free unlimited Actions, but the source becomes visible.
3. Leave it, and run the checks locally before pushing. Everything CI does is one command:
   `cd Sim && dotnet test Salvo.Sim.Tests/Salvo.Sim.Tests.csproj` plus the `Salvo.Headless`
   runs listed in the workflow.

Nothing in this repository depends on CI running. It is a safety net, not a build step.

## Documents

| File | What it is for |
| --- | --- |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Why the code is shaped this way. Read §6 for what is actually verified. |
| [PROJECT_PLAN.md](PROJECT_PLAN.md) | 19 phases, each with a definition of done. Performance budgets. Risks. |
| [TODO.md](TODO.md) | Live state. `[x]` is done **and verified**; `[~]` is verified only by reading. |
| [ORIGINALITY.md](ORIGINALITY.md) | What may and may not be borrowed, and the names in use. |

## Non-negotiables

These are constraints, not preferences, and the code is arranged so that breaking them is
difficult rather than merely discouraged.

- **The client is never trusted** for damage, health, ammunition, score, kills, movement
  validation or match results. The only way intent enters `MatchSimulation` is `SubmitInput`,
  which accepts a command and nothing else.
- **Nothing sold confers an advantage.** `Loadout` is simulation state; cosmetics live on the
  presentation-side player record, which the simulation never sees. Attachments must have a
  downside — `AttachmentDefinition.Validate` rejects one that is strictly better than nothing.
- **Bot difficulty degrades senses and hands, never the rules.** There is no damage or health
  knob on `BotDifficultyDefinition` to give one.
- **No hardcoded user-facing strings.** Every display name is a localisation key.
- **No secrets in the repository.** Ever.

## Licence

Not yet chosen. Until one is added, all rights reserved.
