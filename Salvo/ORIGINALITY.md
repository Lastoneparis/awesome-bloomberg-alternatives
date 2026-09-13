# Originality

The brief is unambiguous: this must be **original IP**. It may be *inspired by* the fast,
readable competitive shooters that define the genre; it may not *copy* any of them.

This file exists because "don't copy anything" is easy to agree with and hard to apply at
2 a.m. when a placeholder needs a name. The rules below are meant to be applicable without
judgement calls.

---

## What is off limits

Nothing may be taken from any existing game, in any form:

- **Assets** — models, textures, sounds, music, animations, fonts, icons, logos.
- **Maps** — no recreations, no "inspired by" layouts that are recognisably a specific map,
  no reused callout names.
- **Weapons** — no real-world weapon names or trademarked designations, and no another
  game's fictional designations. Stats may sit in the same range as the genre's; that is
  physics and balance, not copying.
- **Characters and factions** — no names, likenesses, insignia, voice lines or backstories.
- **UI** — no recreated layouts, no copied iconography, no lifted colour schemes.
- **Text** — no copied strings, mode descriptions, tips or tutorial wording.
- **Mode names** — including internal identifiers. `GameModeKind` originally had
  `SearchAndDestroy` and `GunGame`, both names of specific existing games' modes; they are now
  `RoundObjective` and `WeaponLadder`. An enum value is not user-facing until somebody makes it
  so, which is not a reason to leave a borrowed name in the source.
- **Code** — none, from any source whose licence does not permit it. Including snippets.

## What is fine

- **Genre conventions.** A 5v5 bomb-defusal mode, hitscan rifles, a buy phase, spray
  patterns, a crouch key. These are the vocabulary of the genre, not anyone's property.
- **Physical reality.** A rifle bullet loses energy over distance; a shotgun spreads; armour
  absorbs. Modelling reality is not copying whoever modelled it first.
- **Published technique.** Client-side prediction, server reconciliation, entity
  interpolation, lag compensation. These are documented, widely implemented engineering
  methods.
- **Numbers in the genre's range.** A 30-round magazine and 600 rpm are not distinctive.

## The names we have chosen

All invented for this project:

| Kind | Names |
| --- | --- |
| Codename | **Salvo** — placeholder. **Not cleared for use.** See below. |
| Weapons | Kestrel (carbine), Hornet (SMG), Anvil (shotgun), Pike (sidearm), Cleaver (melee) |
| Factions | Meridian Company, Ashwood Collective |
| Map | Junction |
| Objective mode | Overload; its sites are Relay A and Relay B |
| Wartime weapons | Warden (bolt-action), Thistle (SMG), Ridgeback (semi-auto), Kettle (sidearm), Spade (melee) |
| Wartime factions | Ironvale Brigade, Sablewood Corps |
| Wartime map | Quarry |
| Teams | Alpha, Bravo — deliberately generic; the faction is content, the team is a side |

The weapon names are common English nouns chosen to suggest a role rather than to resemble
any real designation. `Team.Alpha` / `Team.Bravo` exist in the simulation precisely so that
no faction identity is baked into the engine: a world can field any two factions it likes.

## On the 1940s era specifically

The wartime world is a *register*, not a depiction. No real nation, unit, insignia, place or
weapon appears in it, and none may. The factions are invented and deliberately not analogues
of real belligerents; the weapons are invented designations for generic archetypes (a
bolt-action rifle, a submachine gun); the map is a stone quarry rather than a recreation of
anywhere. `WorldDefinition.EraYear` is 1944 for sorting and UI only — no gameplay branches on
it, and it is not a claim about history.

If a future era moves closer to a real conflict, that judgement needs making deliberately and
in the open, not arrived at one asset at a time.

## Before any public use

**The name "Salvo" has not been trademark-searched.** It is a codename and should be treated
as one. Someone must run a proper search — at minimum USPTO, EUIPO and the App Store — and
the project should expect to rename. Nothing in the codebase depends on the name: it appears
in namespaces, folder names and the two markdown documents, and a rename is a find-and-replace
rather than a refactor. That is deliberate, and worth keeping true.

The same applies to every weapon and faction name above before they appear in a shipped build.

## How this is enforced

Partly by review, and partly by structure:

- `WeaponDefinition.DisplayNameKey` and every other user-facing string is a **localisation
  key**, never a literal. A key like `weapon.kestrel.name` cannot accidentally be a
  trademarked string, and every piece of shown text has to be written deliberately, once, in
  a table someone can read end to end.
- The simulation has no art, audio or model data at all — only content **keys**. Anything
  that could infringe lives in assets that do not exist yet, which is the right time to set
  the rule.
- `StarterContent.cs` is the single file where all current names live. One file to audit.

## If something is uncertain

Do not ship it. Rename it, or leave the key unresolved and raise it. An originality problem
found before release is an afternoon; found after, it is a takedown.
