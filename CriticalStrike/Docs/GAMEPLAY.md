# Gameplay

## Balance philosophy

Three rules govern every number in `Data/`:

1. **Nothing is strictly better.** Every attachment has a real downside; every perk costs
   something; the highest-damage weapons are the slowest to handle. `WeaponBalanceTests`
   asserts this across the whole roster, so a balance patch that breaks it fails CI.
2. **Skill beats gear.** The gap between the starter rifle and the level-34 sniper is
   about situational fit, not raw power. A headshot with the free pistol kills faster than
   a body shot with anything.
3. **Nothing purchasable affects damage.** Operators carry passives capped at 4%
   (movement, reload) and never touch damage or health beyond a few hit points. Skins are
   cosmetic. There is no gun you can only buy with money.

## Damage

```
damage = base
       × falloff(distance)          flat → linear → flat
       × hitboxMultiplier           head 1.0 (weapon mult applied after), stomach 1.18, leg 0.72
       × headshotMultiplier         if head — 4.0 on a rifle, 2.6 on a sniper
       × penetrationScale^surfaces  0.6^n on a rifle
       × damageScale                double-damage powerup
       × (1 − resistance)           overshield, perks
```

Armour then splits what is left:

```
unblocked = damage × armorPenetration          punches straight through
contested = damage − unblocked
blocked   = contested × 0.55                   stopped by the plate
leaked    = contested − blocked                reaches health anyway
armorDamage = blocked × 0.5                    plate wear
```

If the plate runs out mid-hit the unabsorbed remainder leaks to health, so the last point
of armour never blocks a full round. Armour covers the torso and neck, and the head only
with a helmet — leg shots always go straight through, which is why `hitbox.appliesSlow`
exists as the reward for taking them.

Headshot multipliers are deliberately weapon-specific rather than global. A rifle headshot
is a one-shot kill inside its falloff range; a sniper's 2.6× is lower precisely *because*
its base damage already one-shots the chest.

## Recoil and spread

These are two separate systems, and conflating them is the most common way a shooter ends
up feeling bad.

**Recoil** moves your aim. The first ~30 shots of each automatic weapon follow a
hand-authored spray pattern (`SprayPatterns`) with a small jitter on top. The pattern
climbs straight for five shots, then breaks consistently left and right, which makes it
*learnable*: a player who pulls down and counter-strafes lands a full magazine at 30 metres.
Past the pattern it becomes random. Aiming down sights scales recoil to 72%, crouching to
82%, being airborne to 145%.

**Spread** is the cone the bullet can land in, and it is what movement modifies:

| State | Effect |
| --- | --- |
| Standing still, aiming | `adsSpread` — near zero on a rifle |
| Hip fire | `baseSpread` |
| Moving | + `moveSpreadPenalty × speedRatio` |
| Airborne | + `jumpSpreadPenalty` (large) |
| Crouched | × `crouchSpreadBonus` (0.45–0.7) |
| Each shot | + `spreadPerShot`, capped at `maxSpread` |
| Recovery | − `spreadRecovery` per second |

The crosshair draws the *actual* spread value, converted through the camera's FOV. What you
see is the cone your bullets can land in — there is no cosmetic approximation.

## Penetration

Each round carries a `penetrationPower` budget. Crossing a surface costs
`surface.penetrationCost × brush.thickness`, and damage is multiplied by
`penetrationDamageScale` per surface crossed. Glass costs almost nothing (0.25/unit), wood a
little (1.0), concrete a lot (2.4), metal usually stops everything (3.0). Bodies cost 0.9,
so lining two enemies up with a sniper is a real, rewarded play. Maximum three surfaces.

## Movement

Source-style acceleration and friction, tuned for a thumb rather than a keyboard:

| Value | |
| --- | --- |
| Run / sprint / crouch | 5.4 / 7.1 / 2.6 m/s |
| Ground acceleration | 62 m/s² (forgiving — a stick is not a key) |
| Air acceleration | 24 m/s², capped at 1.6 m/s of air control |
| Jump | 6.3 m/s ≈ 1.05 m |
| Step-up | 0.55 m, attempted before wall sliding |
| Slide | 0.75 s at 1.7× sprint speed, entered from a sprint |
| Fall damage | Nothing under ~4 m; fatal from ~12 m |

Footsteps are distance-based, not time-based, so changing speed changes cadence correctly.
Audibility is a real gameplay value: sprinting is heard at 24 m, walking at 14 m, crouching
at 5 m, and the Light Foot perk multiplies all of it by 0.35. The enemy minimap only shows
players who fire an unsuppressed weapon — everything else is sound.

## Game modes

| Mode | Win condition | Respawn | Notes |
| --- | --- | --- | --- |
| Team Deathmatch | 75 kills | Yes | The baseline |
| Free For All | 30 kills | Yes | Kills heal 25 |
| Bomb Defusal | 8 rounds | No | Buy menu, side swap at halftime, 40 s fuse |
| Domination | 200 points | Yes | Three points, tick score every 5 s |
| Gun Game | Finish the ladder | Yes | 17 weapons, knife to win |
| Search & Rescue | 6 rounds | Via tags | Bomb rules plus teammate revival |
| Kill Confirmed | 65 tags | Yes | Kills only count when collected |
| Hardpoint | 250 points | Yes | Objective rotates every 60 s |
| One in the Chamber | 15 kills | Yes | One health, one bullet, kills reload |
| Zombie Survival | Survive | Wave-based | Buy your way deeper |
| Training | — | Instant | Targets, spray practice, grenade lineups |

Each is a `GameModeRules` implementation. `MatchSimulation` knows about phases, rounds,
spawning and scoring; it knows nothing about bombs or dog tags.

## Bots

Difficulty scales reaction time (0.62 s → 0.14 s), aim error (7.5° → 1.1°), tracking jitter,
burst discipline and grenade use. It never scales damage or health, because a bot that
shoots harder than a player reads as broken rather than difficult.

A bot's perception is honest: a view cone, a real line-of-sight trace, smoke occlusion, and
hearing bounded by the same audibility radius that governs the minimap. A flashed bot
genuinely cannot see. Decoy grenades pull bots exactly as they pull players.

Adaptive difficulty nudges the whole roster within ±2 steps of the chosen level based on
the human's K/D, re-evaluated every 20 seconds. Bounded, so it never feels like the game is
playing itself.

## Aim assist

Two mechanisms, both in input space only:

- **Slowdown** multiplies raw look input by up to 0.45 when the crosshair is near a target.
- **Magnetism** applies a small rotational nudge toward the target — but only while the
  player is actively providing input, and capped at what a thumb could plausibly do.

Bullet magnetism is deliberately *not* implemented (`AimAssist.bulletMagnetismEnabled =
false`). The spread cone is the only thing that decides where a bullet goes, so two players
with different assist settings still have identical weapon behaviour. Auto-fire pulls the
trigger when the crosshair is genuinely over an enemy; it never holds the trigger blind.
