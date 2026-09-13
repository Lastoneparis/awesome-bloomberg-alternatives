import Foundation

/// Every sound in the game, by the name the rest of the code already asks for.
///
/// `AudioEngine` looks sounds up by string — `sfx_ar_vanguard_fire`, `sfx_step_metal`,
/// `amb_desert_wind`. This resolves those names to synthesised audio, so nothing has to be
/// recorded and, more usefully, a weapon's report is derived from the same `WeaponData` the
/// damage model reads: a slower, heavier, harder-hitting round genuinely produces a lower,
/// longer, louder report, and rebalancing a weapon rebalances how it sounds.
///
/// A bundled file of the same name still wins, so real recordings can be dropped in later
/// without touching any of this.
public enum SoundBank {

    /// Resolves a sound name. Returns nil for a name with no recipe, which the caller
    /// treats exactly as it treats a missing file: silence, no crash.
    public static func sound(named name: String) -> Waveform? {
        if let weaponSound = weaponSound(named: name) { return weaponSound }
        if name.hasPrefix("sfx_step_") {
            return footstep(surface: surface(from: String(name.dropFirst("sfx_step_".count))),
                            seed: hash(name))
        }
        if name.hasPrefix("sfx_impact_") {
            return impact(surface: surface(from: String(name.dropFirst("sfx_impact_".count))),
                          seed: hash(name))
        }
        if name.hasPrefix("amb_") { return ambience(named: name) }
        if name == "mus_victory" { return victorySting(won: true) }
        if name == "mus_defeat" { return victorySting(won: false) }
        if name.hasPrefix("mus_") { return music(named: name) }

        switch name {
        case "sfx_hitmarker": return hitMarker(headshot: false)
        case "sfx_headshot": return hitMarker(headshot: true)
        case "sfx_kill": return killConfirm()
        case "sfx_death": return death()
        case "sfx_dryfire": return dryFire()
        case "sfx_reload_empty": return reload(weight: 1.4, shells: false, seed: hash(name))
        case "sfx_grenade_bounce": return grenadeBounce(seed: hash(name))
        case "sfx_explosion": return explosion(seed: hash(name))
        case "sfx_flash": return flashbang()
        case "sfx_smoke": return smoke(seed: hash(name))
        case "sfx_fire_loop": return fireLoop(seed: hash(name))
        case "sfx_pickup": return pickup()
        case "sfx_jump": return jump()
        case "sfx_land": return land(seed: hash(name))
        case "sfx_ui_click", "ui_equip", "ui_attach": return uiClick()
        case "sfx_ui_back": return uiBack()

        // ── Combat feedback ──
        case "sfx_kill_headshot": return killConfirm(headshot: true)
        case "sfx_take_damage": return takeDamage()
        case "sfx_weapon_swap": return weaponSwap()
        case "sfx_grenade_throw": return grenadeThrow()
        case "sfx_flash_ring": return flashRing()
        case "sfx_first_blood": return fanfare(intervals: [0, 4, 7, 12], seconds: 0.7, bright: true)

        // ── Objectives and round flow ──
        case "sfx_round_start": return fanfare(intervals: [0, 7], seconds: 0.55, bright: false)
        case "sfx_bomb_planted": return beacon(frequency: 880, beeps: 3, spacing: 0.16)
        case "sfx_bomb_defused": return fanfare(intervals: [0, 5, 9], seconds: 0.6, bright: true)
        case "sfx_bomb_explode": return explosion(seed: hash(name))
        case "sfx_objective_captured": return fanfare(intervals: [0, 4, 7], seconds: 0.5, bright: true)
        case "sfx_ping": return beacon(frequency: 1320, beeps: 1, spacing: 0.1)

        // ── Menus ──
        case "sfx_purchase", "ui_purchase": return fanfare(intervals: [0, 7, 12],
                                                           seconds: 0.45, bright: true)
        case "ui_crate_open": return crateOpen()
        case "sfx_error": return errorBuzz()

        default:
            // Killstreak announcements: one step higher and one step brighter each time,
            // so a five-streak is audibly a bigger deal than a two-streak.
            if name.hasPrefix("sfx_streak_"), let step = Int(name.dropFirst("sfx_streak_".count)) {
                let clamped = MathUtil.clamp(Float(step), 1, 5)
                return fanfare(intervals: [0, 4, 7, 12], seconds: 0.5 + clamped * 0.06,
                               bright: true, transpose: clamped * 2)
            }
            return nil
        }
    }

    /// Every name this bank can produce without being told a weapon or a surface. Used by
    /// the warm-up so the first shot of a match never waits on synthesis.
    public static let fixedNames: [String] = [
        "sfx_hitmarker", "sfx_headshot", "sfx_kill", "sfx_kill_headshot", "sfx_death",
        "sfx_dryfire", "sfx_reload_empty", "sfx_grenade_bounce", "sfx_grenade_throw",
        "sfx_explosion", "sfx_flash", "sfx_flash_ring", "sfx_smoke", "sfx_fire_loop",
        "sfx_pickup", "sfx_jump", "sfx_land", "sfx_take_damage", "sfx_weapon_swap",
        "sfx_first_blood", "sfx_round_start", "sfx_bomb_planted", "sfx_bomb_defused",
        "sfx_bomb_explode", "sfx_objective_captured", "sfx_ping", "sfx_error",
        "sfx_purchase", "sfx_ui_click", "sfx_ui_back",
        "sfx_streak_1", "sfx_streak_2", "sfx_streak_3", "sfx_streak_4", "sfx_streak_5",
        "ui_equip", "ui_attach", "ui_purchase", "ui_crate_open"
    ]

    // MARK: - Weapons

    private static func weaponSound(named name: String) -> Waveform? {
        guard name.hasPrefix("sfx_") else { return nil }
        let body = String(name.dropFirst(4))
        if body.hasSuffix("_fire") {
            let id = WeaponID(String(body.dropLast(5)))
            guard let weapon = WeaponDatabase.weapon(id) else { return nil }
            return gunshot(for: weapon)
        }
        if body.hasSuffix("_reload") {
            let id = WeaponID(String(body.dropLast(7)))
            guard let weapon = WeaponDatabase.weapon(id) else { return nil }
            return reload(weight: weapon.weight, shells: weapon.shellByShellReload,
                          seed: hash(name))
        }
        return nil
    }

    /// A gunshot is four layers, and leaving any one out is immediately audible: the crack
    /// of the muzzle blast, the body of the expanding gas, a low thump you feel more than
    /// hear, and the room reflecting it back.
    public static func gunshot(for weapon: WeaponData) -> Waveform {
        let seed = hash(weapon.id.value)
        if weapon.weaponClass == .melee { return melee(seed: seed) }

        // Calibre, inferred from the data that already exists. A round that does more
        // damage at a lower rate of fire is a bigger round, and bigger rounds are lower
        // and longer.
        let power = MathUtil.clamp(weapon.baseDamage / 40, 0.35, 2.2)
        let cadence = MathUtil.clamp(weapon.roundsPerMinute / 600, 0.4, 2.0)
        let size = MathUtil.clamp(power / cadence, 0.3, 2.4)
        let length = MathUtil.clamp(0.16 + size * 0.22, 0.14, 0.62)

        // ── Crack: the supersonic snap, all top end, gone in ten milliseconds ──
        var shot = Synth.envelope(
            Synth.filter(Synth.noise(seconds: 0.05, seed: seed), mode: .highPass,
                         cutoff: 2600, resonance: 1.1),
            attack: 0.0004, decay: 0.02, curve: 4).gained(0.85)

        // ── Body: the blast itself, a wide noise burst dulling as it decays ──
        let bodyCutoffStart = 5200 / (0.6 + size)
        let body = Synth.envelope(
            Synth.sweepingLowPass(Synth.noise(seconds: length, seed: seed &+ 11),
                                  from: bodyCutoffStart, to: bodyCutoffStart * 0.28,
                                  resonance: 1.3),
            attack: 0.0008, hold: 0.004, decay: length * 0.8, curve: 2.6)
        shot.mix(body, gain: 1.0)

        // ── Thump: the low end, and the layer that is easiest to overdo. A phone speaker
        // reproduces almost nothing below about 200 Hz, so energy down there is inaudible
        // and still takes the headroom the crack needs; keep it as a punch in the low
        // mids rather than a sub. Pistols have almost none of it, an LMG has the most.
        let thump = Synth.envelope(
            Synth.sweep(from: 400 / (0.6 + size), to: 90 / (0.4 + size * 0.3),
                        seconds: length * 0.9, wave: .sine, curve: 3),
            attack: 0.001, decay: length * 0.7, curve: 2.2)
        shot.mix(thump, gain: 0.22 + size * 0.12)

        // ── Mechanical action: the bolt, quieter and a fraction later ──
        let action = Synth.envelope(
            Synth.filter(Synth.noise(seconds: 0.04, seed: seed &+ 23), mode: .bandPass,
                         cutoff: 3200, resonance: 2.4),
            attack: 0.0005, decay: 0.03, curve: 3)
        shot.mix(action, at: 0.012, gain: 0.18)

        // Shotguns get a second, detuned blast layered under the first: the report of
        // several pellets leaving at once is wider than one round.
        if weapon.weaponClass == .shotgun {
            let second = Synth.envelope(
                Synth.sweepingLowPass(Synth.noise(seconds: length, seed: seed &+ 37),
                                      from: 2400, to: 500, resonance: 1.0),
                attack: 0.001, hold: 0.006, decay: length, curve: 2.2)
            shot.mix(second, at: 0.003, gain: 0.7)
        }

        // ── Room: a short tail, longer for the louder weapons ──
        var tailed = Synth.room(Synth.saturate(shot, drive: 1.6 + size * 0.5),
                                size: 0.7 + size * 0.5, decay: 0.34 + size * 0.1,
                                mix: 0.30)
        // Clear the sub that no phone will reproduce, so normalising scales what is
        // actually audible instead of scaling to a peak nobody can hear.
        tailed = Synth.filter(tailed, mode: .highPass, cutoff: 62, resonance: 0.6)
        return tailed.normalized(to: MathUtil.clamp(0.62 + size * 0.14, 0.6, 0.95))
            .trimmedSilence()
            .faded(inSeconds: 0.0002, outSeconds: 0.03)
            .sanitized()
    }

    public static func melee(seed: UInt64) -> Waveform {
        // A knife swing is air, not impact: a band of noise rushing past.
        let swing = Synth.envelope(
            Synth.filter(Synth.noise(seconds: 0.22, seed: seed), mode: .bandPass,
                         cutoff: 1400, resonance: 3.2),
            attack: 0.05, decay: 0.14, curve: 2)
        return swing.normalized(to: 0.5).faded().sanitized()
    }

    /// Reload: two or three mechanical events spaced out, rather than one noise. The
    /// spacing is what makes it read as a magazine coming out and another going in.
    public static func reload(weight: Float, shells: Bool, seed: UInt64) -> Waveform {
        var out = Waveform(seconds: shells ? 0.8 : 1.05)
        let pitch = MathUtil.clamp(1.4 / max(0.4, weight), 0.6, 1.8)

        func clack(at time: Float, cutoff: Float, decay: Float, gain: Float, seed: UInt64) {
            let click = Synth.envelope(
                Synth.filter(Synth.noise(seconds: decay * 2, seed: seed), mode: .bandPass,
                             cutoff: cutoff * pitch, resonance: 3.0),
                attack: 0.0006, decay: decay, curve: 3)
            // A metal part stopping rings briefly; without this it is a dull tap.
            let ring = Synth.decay(
                Synth.tone(frequency: cutoff * pitch * 1.6, seconds: decay * 1.4, wave: .sine),
                halfLife: decay * 0.35)
            out.mix(click, at: time, gain: gain)
            out.mix(ring, at: time, gain: gain * 0.22)
        }

        if shells {
            // Shell-by-shell: one shell in, and the pump.
            clack(at: 0.02, cutoff: 2100, decay: 0.05, gain: 0.8, seed: seed)
            clack(at: 0.30, cutoff: 1500, decay: 0.09, gain: 0.9, seed: seed &+ 5)
        } else {
            clack(at: 0.02, cutoff: 1800, decay: 0.07, gain: 0.75, seed: seed)        // release
            clack(at: 0.34, cutoff: 1200, decay: 0.10, gain: 0.55, seed: seed &+ 5)   // mag out
            clack(at: 0.62, cutoff: 1600, decay: 0.11, gain: 0.95, seed: seed &+ 9)   // mag in
            clack(at: 0.86, cutoff: 2600, decay: 0.07, gain: 0.8, seed: seed &+ 13)   // bolt
        }
        return out.normalized(to: 0.62).faded().sanitized()
    }

    public static func dryFire() -> Waveform {
        let click = Synth.envelope(
            Synth.filter(Synth.noise(seconds: 0.06, seed: 0xDF1), mode: .bandPass,
                         cutoff: 3400, resonance: 4),
            attack: 0.0004, decay: 0.035, curve: 4)
        return click.normalized(to: 0.4).faded().sanitized()
    }

    // MARK: - Surfaces

    /// Footsteps carry more competitive information than anything else in the mix, so each
    /// surface has to be distinguishable in a quarter of a second, through gunfire.
    public static func footstep(surface: SurfaceKind, seed: UInt64) -> Waveform {
        let step: Waveform
        switch surface {
        case .metal:
            // A struck panel: a band of noise plus a ringing partial.
            var hit = Synth.envelope(
                Synth.filter(Synth.noise(seconds: 0.22, seed: seed), mode: .bandPass,
                             cutoff: 2400, resonance: 2.6),
                attack: 0.0008, decay: 0.1, curve: 3)
            hit.mix(Synth.decay(Synth.tone(frequency: 880, seconds: 0.3), halfLife: 0.07),
                    gain: 0.28)
            hit.mix(Synth.decay(Synth.tone(frequency: 1470, seconds: 0.25), halfLife: 0.05),
                    gain: 0.16)
            step = hit
        case .wood:
            var hit = Synth.envelope(
                Synth.filter(Synth.noise(seconds: 0.16, seed: seed), mode: .bandPass,
                             cutoff: 900, resonance: 2.0),
                attack: 0.0008, decay: 0.07, curve: 3)
            hit.mix(Synth.decay(Synth.tone(frequency: 220, seconds: 0.16), halfLife: 0.035),
                    gain: 0.3)
            step = hit
        case .grass, .fabric:
            step = Synth.envelope(
                Synth.filter(Synth.noise(seconds: 0.2, seed: seed), mode: .highPass,
                             cutoff: 2200, resonance: 0.8),
                attack: 0.006, decay: 0.12, curve: 2)
        case .dirt, .sand:
            step = Synth.envelope(
                Synth.filter(Synth.noise(seconds: 0.18, seed: seed), mode: .bandPass,
                             cutoff: 700, resonance: 1.0),
                attack: 0.004, decay: 0.1, curve: 2.2)
        case .water:
            // A splash is a rising filter, not a falling one: the fine spray arrives last.
            step = Synth.envelope(
                Synth.sweepingLowPass(Synth.noise(seconds: 0.3, seed: seed),
                                      from: 700, to: 6000, resonance: 0.9),
                attack: 0.004, decay: 0.22, curve: 1.7)
        case .glass:
            var hit = Synth.envelope(
                Synth.filter(Synth.noise(seconds: 0.2, seed: seed), mode: .highPass,
                             cutoff: 4200, resonance: 1.2),
                attack: 0.0006, decay: 0.12, curve: 3)
            hit.mix(Synth.decay(Synth.tone(frequency: 3100, seconds: 0.25), halfLife: 0.05),
                    gain: 0.2)
            step = hit
        case .tile:
            var hit = Synth.envelope(
                Synth.filter(Synth.noise(seconds: 0.18, seed: seed), mode: .bandPass,
                             cutoff: 3000, resonance: 2.2),
                attack: 0.0006, decay: 0.07, curve: 3.5)
            hit.mix(Synth.decay(Synth.tone(frequency: 1650, seconds: 0.2), halfLife: 0.03),
                    gain: 0.18)
            step = hit
        case .concrete, .plastic, .flesh:
            step = Synth.envelope(
                Synth.filter(Synth.noise(seconds: 0.16, seed: seed), mode: .bandPass,
                             cutoff: 1400, resonance: 1.6),
                attack: 0.0008, decay: 0.075, curve: 3)
        }
        return step.normalized(to: 0.45).faded().sanitized()
    }

    /// A round hitting a wall: the same materials, harder and shorter.
    public static func impact(surface: SurfaceKind, seed: UInt64) -> Waveform {
        var hit = footstep(surface: surface, seed: seed &+ 101)
        hit = Synth.envelope(hit, attack: 0.0003, decay: 0.09, curve: 4)
        // The spall: grit thrown off the surface, always there and always brief.
        let grit = Synth.envelope(
            Synth.filter(Synth.noise(seconds: 0.09, seed: seed &+ 7), mode: .highPass,
                         cutoff: 3800),
            attack: 0.0003, decay: 0.06, curve: 3.5)
        hit.mix(grit, gain: 0.5)
        return hit.normalized(to: 0.55).faded().sanitized()
    }

    // MARK: - Feedback

    /// The hit marker is the most repeated sound in the game — thousands of times a
    /// session — so it has to be short, bright, and completely unlike anything else.
    public static func hitMarker(headshot: Bool) -> Waveform {
        let base: Float = headshot ? 1760 : 1180
        var tick = Synth.envelope(Synth.tone(frequency: base, seconds: 0.07),
                                  attack: 0.0006, decay: 0.05, curve: 4)
        tick.mix(Synth.envelope(Synth.tone(frequency: base * 1.5, seconds: 0.06),
                                attack: 0.0006, decay: 0.04, curve: 4), gain: 0.5)
        if headshot {
            // A second, higher tick: the difference has to survive a firefight.
            tick.mix(Synth.envelope(Synth.tone(frequency: base * 2, seconds: 0.06),
                                    attack: 0.0006, decay: 0.04, curve: 4),
                     at: 0.045, gain: 0.55)
        }
        return tick.normalized(to: headshot ? 0.6 : 0.45).faded().sanitized()
    }

    public static func killConfirm(headshot: Bool = false) -> Waveform {
        var chime = Waveform(seconds: headshot ? 0.55 : 0.42)
        let notes: [Float] = headshot ? [784, 1046, 1318, 1568] : [784, 1046, 1318]
        for (index, frequency) in notes.enumerated() {
            chime.mix(Synth.envelope(Synth.tone(frequency: frequency, seconds: 0.3),
                                     attack: 0.002, decay: 0.24, curve: 3),
                      at: Float(index) * 0.045, gain: 0.6 - Float(index) * 0.08)
        }
        return chime.normalized(to: headshot ? 0.62 : 0.55).faded().sanitized()
    }

    /// An arpeggiated chord, which is what almost every positive announcement in a shooter
    /// is underneath. `intervals` are semitones above the root.
    public static func fanfare(intervals: [Float], seconds: Float, bright: Bool,
                               transpose: Float = 0) -> Waveform {
        var out = Waveform(seconds: seconds + 0.25)
        let root: Float = (bright ? 523.25 : 392) * pow(2, transpose / 12)
        let step = seconds / Float(max(1, intervals.count)) * 0.55
        for (index, interval) in intervals.enumerated() {
            let frequency = root * pow(2, interval / 12)
            var note = Synth.envelope(Synth.tone(frequency: frequency, seconds: seconds * 0.8),
                                      attack: 0.004, decay: seconds * 0.7, curve: 2.6)
            // A fifth above at low level: one sine per note sounds like a test tone.
            note.mix(Synth.envelope(Synth.tone(frequency: frequency * 1.5, seconds: seconds * 0.6),
                                    attack: 0.004, decay: seconds * 0.5, curve: 3),
                     gain: 0.22)
            out.mix(note, at: Float(index) * step, gain: 0.55 - Float(index) * 0.05)
        }
        return out.normalized(to: 0.5).trimmedSilence().faded().sanitized()
    }

    /// A repeating electronic beep — a planted bomb, a ping on the map.
    public static func beacon(frequency: Float, beeps: Int, spacing: Float) -> Waveform {
        var out = Waveform(seconds: spacing * Float(beeps) + 0.2)
        for index in 0..<max(1, beeps) {
            var beep = Synth.envelope(Synth.tone(frequency: frequency, seconds: 0.12),
                                      attack: 0.002, hold: 0.03, decay: 0.08, curve: 2.5)
            beep.mix(Synth.envelope(Synth.tone(frequency: frequency * 2, seconds: 0.1),
                                    attack: 0.002, decay: 0.07, curve: 3), gain: 0.25)
            out.mix(beep, at: Float(index) * spacing, gain: 0.6)
        }
        return out.normalized(to: 0.45).trimmedSilence().faded().sanitized()
    }

    /// Taking a hit: a short dull thud with a band of noise, deliberately unpleasant and
    /// deliberately nothing like the hit marker, which means the opposite thing.
    public static func takeDamage() -> Waveform {
        var out = Synth.envelope(
            Synth.filter(Synth.noise(seconds: 0.22, seed: 0xDA11), mode: .bandPass,
                         cutoff: 380, resonance: 1.8),
            attack: 0.001, decay: 0.16, curve: 3)
        out.mix(Synth.envelope(Synth.sweep(from: 320, to: 120, seconds: 0.18, wave: .triangle),
                               attack: 0.001, decay: 0.14, curve: 2.4), gain: 0.6)
        return out.normalized(to: 0.55).faded().sanitized()
    }

    public static func weaponSwap() -> Waveform {
        var out = Waveform(seconds: 0.4)
        out.mix(Synth.envelope(Synth.filter(Synth.noise(seconds: 0.1, seed: 0x5AA1),
                                            mode: .bandPass, cutoff: 2200, resonance: 3),
                               attack: 0.0006, decay: 0.06, curve: 3.5), at: 0, gain: 0.7)
        out.mix(Synth.envelope(Synth.filter(Synth.noise(seconds: 0.12, seed: 0x5AA2),
                                            mode: .bandPass, cutoff: 1500, resonance: 3),
                               attack: 0.0006, decay: 0.08, curve: 3.5), at: 0.14, gain: 0.9)
        return out.normalized(to: 0.45).trimmedSilence().faded().sanitized()
    }

    public static func grenadeThrow() -> Waveform {
        // Cloth and air, not metal: the pin and the arm, not the impact.
        let out = Synth.envelope(
            Synth.filter(Synth.noise(seconds: 0.26, seed: 0x67A1), mode: .bandPass,
                         cutoff: 1900, resonance: 1.6),
            attack: 0.01, decay: 0.18, curve: 2.2)
        return out.normalized(to: 0.4).faded().sanitized()
    }

    /// The ring after a flashbang, played dry in the player's own ears rather than in the
    /// world. Long, and the only sound in the game allowed to be annoying.
    public static func flashRing() -> Waveform {
        var out = Synth.decay(Synth.tone(frequency: 4300, seconds: 4.5), halfLife: 1.3)
        out.mix(Synth.decay(Synth.tone(frequency: 6450, seconds: 3.5), halfLife: 0.9), gain: 0.4)
        out.mix(Synth.decay(Synth.tone(frequency: 2870, seconds: 3.0), halfLife: 0.7), gain: 0.2)
        return out.normalized(to: 0.5).faded(inSeconds: 0.02, outSeconds: 0.8).sanitized()
    }

    public static func crateOpen() -> Waveform {
        // A rising sweep into a chord: the sound of something being revealed.
        var out = Synth.envelope(
            Synth.filter(Synth.sweep(from: 200, to: 2400, seconds: 0.6, wave: .sawtooth,
                                     curve: 0.6), mode: .lowPass, cutoff: 3200, resonance: 1.4),
            attack: 0.05, decay: 0.5, curve: 1.4)
        out.mix(fanfare(intervals: [0, 4, 7, 12], seconds: 0.6, bright: true), at: 0.55, gain: 1.0)
        return out.normalized(to: 0.5).trimmedSilence().faded().sanitized()
    }

    public static func errorBuzz() -> Waveform {
        var out = Synth.envelope(Synth.tone(frequency: 160, seconds: 0.16, wave: .square),
                                 attack: 0.002, decay: 0.12, curve: 2)
        out.mix(Synth.envelope(Synth.tone(frequency: 240, seconds: 0.14, wave: .square),
                               attack: 0.002, decay: 0.1, curve: 2), at: 0.08, gain: 0.7)
        return out.normalized(to: 0.35).faded().sanitized()
    }

    public static func death() -> Waveform {
        // Falling, dull, and long enough to register as final.
        var out = Synth.envelope(
            Synth.sweep(from: 320, to: 70, seconds: 0.9, wave: .triangle, curve: 2),
            attack: 0.005, decay: 0.8, curve: 2)
        out.mix(Synth.envelope(Synth.filter(Synth.noise(seconds: 0.6, seed: 0xDEAD),
                                            mode: .lowPass, cutoff: 700),
                               attack: 0.004, decay: 0.5, curve: 2.5), gain: 0.4)
        return out.normalized(to: 0.6).faded().sanitized()
    }

    public static func explosion(seed: UInt64) -> Waveform {
        // Low sweep for the pressure wave, wide noise for the blast, a long dulling tail.
        // Same rule as the gunshot: keep the pressure wave in the low mids, where a phone
        // can actually reproduce it, rather than at a sub frequency that only shows up on
        // the peak meter.
        var blast = Synth.envelope(
            Synth.sweep(from: 240, to: 58, seconds: 1.1, wave: .sine, curve: 2.4),
            attack: 0.002, decay: 0.9, curve: 2)
        blast.mix(Synth.envelope(
            Synth.sweepingLowPass(Synth.noise(seconds: 1.2, seed: seed),
                                  from: 4200, to: 260, resonance: 1.1),
            attack: 0.001, hold: 0.01, decay: 1.1, curve: 2.2), gain: 0.9)
        // Debris, arriving after the blast rather than with it.
        blast.mix(Synth.envelope(Synth.filter(Synth.noise(seconds: 0.7, seed: seed &+ 3),
                                              mode: .highPass, cutoff: 3000),
                                 attack: 0.02, decay: 0.6, curve: 2),
                  at: 0.09, gain: 0.22)
        var tailed = Synth.room(Synth.saturate(blast, drive: 3.5), size: 1.6, decay: 0.5, mix: 0.42)
        tailed = Synth.filter(tailed, mode: .highPass, cutoff: 55, resonance: 0.6)
        return tailed.normalized(to: 0.95).trimmedSilence()
            .faded(inSeconds: 0.0004, outSeconds: 0.15).sanitized()
    }

    public static func flashbang() -> Waveform {
        var out = Synth.envelope(
            Synth.filter(Synth.noise(seconds: 0.5, seed: 0xF1A5), mode: .highPass, cutoff: 1800),
            attack: 0.0004, decay: 0.35, curve: 3)
        // The ring afterwards. This is the sound the player remembers.
        out.mix(Synth.decay(Synth.tone(frequency: 4300, seconds: 3.2), halfLife: 0.9),
                gain: 0.32)
        out.mix(Synth.decay(Synth.tone(frequency: 6450, seconds: 2.6), halfLife: 0.7),
                gain: 0.14)
        return out.normalized(to: 0.8).faded(inSeconds: 0.0004, outSeconds: 0.4).sanitized()
    }

    public static func smoke(seed: UInt64) -> Waveform {
        let hiss = Synth.envelope(
            Synth.filter(Synth.noise(seconds: 2.4, seed: seed), mode: .bandPass,
                         cutoff: 5200, resonance: 0.8),
            attack: 0.06, hold: 1.4, decay: 0.9, curve: 1.6)
        return hiss.normalized(to: 0.4).faded(inSeconds: 0.02, outSeconds: 0.2).sanitized()
    }

    public static func fireLoop(seed: UInt64) -> Waveform {
        var fire = Synth.filter(Synth.noise(seconds: 3, seed: seed), mode: .lowPass,
                                cutoff: 1100, resonance: 0.8).gained(0.5)
        // Crackle: short bright transients scattered through the bed.
        var random = DeterministicRandom(seed: seed &+ 77)
        for _ in 0..<60 {
            let pop = Synth.envelope(
                Synth.filter(Synth.noise(seconds: 0.05, seed: random.next()), mode: .bandPass,
                             cutoff: random.float(in: 1800...5200), resonance: 3),
                attack: 0.0004, decay: 0.03, curve: 4)
            fire.mix(pop, at: random.float(in: 0...2.6), gain: random.float(in: 0.2...0.7))
        }
        return fire.loopable(crossfadeSeconds: 0.4).normalized(to: 0.5).sanitized()
    }

    public static func grenadeBounce(seed: UInt64) -> Waveform {
        var bounce = Synth.envelope(
            Synth.filter(Synth.noise(seconds: 0.12, seed: seed), mode: .bandPass,
                         cutoff: 2800, resonance: 3.5),
            attack: 0.0005, decay: 0.07, curve: 4)
        bounce.mix(Synth.decay(Synth.tone(frequency: 1240, seconds: 0.2), halfLife: 0.04),
                   gain: 0.3)
        return bounce.normalized(to: 0.45).faded().sanitized()
    }

    public static func pickup() -> Waveform {
        var out = Waveform(seconds: 0.26)
        out.mix(Synth.envelope(Synth.tone(frequency: 880, seconds: 0.12),
                               attack: 0.002, decay: 0.09, curve: 3), gain: 0.5)
        out.mix(Synth.envelope(Synth.tone(frequency: 1320, seconds: 0.14),
                               attack: 0.002, decay: 0.11, curve: 3), at: 0.06, gain: 0.5)
        return out.normalized(to: 0.45).faded().sanitized()
    }

    public static func jump() -> Waveform {
        let out = Synth.envelope(
            Synth.filter(Synth.noise(seconds: 0.12, seed: 0x7411), mode: .bandPass,
                         cutoff: 1100, resonance: 1.4),
            attack: 0.002, decay: 0.08, curve: 2.5)
        return out.normalized(to: 0.32).faded().sanitized()
    }

    public static func land(seed: UInt64) -> Waveform {
        var out = Synth.envelope(
            Synth.filter(Synth.noise(seconds: 0.22, seed: seed), mode: .lowPass,
                         cutoff: 900, resonance: 1.2),
            attack: 0.001, decay: 0.15, curve: 3)
        out.mix(Synth.envelope(Synth.sweep(from: 150, to: 55, seconds: 0.2, wave: .sine),
                               attack: 0.002, decay: 0.16, curve: 2.4), gain: 0.5)
        return out.normalized(to: 0.5).faded().sanitized()
    }

    public static func uiClick() -> Waveform {
        let out = Synth.envelope(Synth.tone(frequency: 1500, seconds: 0.04),
                                 attack: 0.001, decay: 0.03, curve: 3)
        return out.normalized(to: 0.3).faded().sanitized()
    }

    public static func uiBack() -> Waveform {
        let out = Synth.envelope(Synth.tone(frequency: 700, seconds: 0.05),
                                 attack: 0.001, decay: 0.04, curve: 3)
        return out.normalized(to: 0.3).faded().sanitized()
    }

    // MARK: - Ambience and music

    /// Ambience is a bed, not an event: it has to loop for a whole match without anyone
    /// noticing the seam or getting tired of it.
    public static func ambience(named name: String) -> Waveform {
        let seed = hash(name)
        #if DEBUG
        // Unoptimised, a full-length bed takes long enough to make the test suite and a
        // debug launch painful. Shortened, not truncated: still comfortably longer than a
        // listener notices, so the tests that check bed length stay meaningful. Release is
        // unaffected, exactly as with the texture resolutions.
        let seconds: Float = 7
        #else
        let seconds: Float = 8
        #endif
        var bed: Waveform

        switch name {
        case "amb_desert_wind", "amb_wind", "amb_blizzard":
            let harsh = name == "amb_blizzard"
            // Wind is noise through a filter whose cutoff wanders. A static filter sounds
            // like tape hiss; the wander is the whole effect.
            bed = Synth.noise(seconds: seconds, seed: seed)
            bed = Synth.filter(bed, mode: .bandPass,
                               cutoff: harsh ? 900 : 520, resonance: harsh ? 1.4 : 1.0)
            var random = DeterministicRandom(seed: seed &+ 3)
            for _ in 0..<7 {
                let gust = Synth.envelope(
                    Synth.filter(Synth.noise(seconds: random.float(in: 1.2...2.6),
                                             seed: random.next()),
                                 mode: .bandPass, cutoff: random.float(in: 700...2200),
                                 resonance: 1.6),
                    attack: 0.5, decay: 1.4, curve: 1.6)
                bed.mix(gust, at: random.float(in: 0...5.5), gain: random.float(in: 0.25...0.6))
            }
        case "amb_industrial", "amb_hum":
            // A room tone: mains hum, its harmonics, and a wide noise floor underneath.
            bed = Synth.filter(Synth.noise(seconds: seconds, seed: seed),
                               mode: .lowPass, cutoff: 420).gained(0.4)
            for (harmonic, gain) in [(50, 0.5), (100, 0.28), (150, 0.12), (237, 0.07)] {
                bed.mix(Synth.tone(frequency: Float(harmonic), seconds: seconds), gain: Float(gain))
            }
            if name == "amb_industrial" {
                // Machinery: a slow pulse, so the room sounds like it is running.
                var random = DeterministicRandom(seed: seed &+ 9)
                var time: Float = 0
                while time < seconds - 0.4 {
                    bed.mix(Synth.envelope(Synth.filter(Synth.noise(seconds: 0.3,
                                                                    seed: random.next()),
                                                        mode: .bandPass, cutoff: 320,
                                                        resonance: 2.5),
                                           attack: 0.02, decay: 0.24, curve: 2),
                            at: time, gain: 0.3)
                    time += 1.35
                }
            }
        case "amb_city_night":
            bed = Synth.filter(Synth.noise(seconds: seconds, seed: seed),
                               mode: .lowPass, cutoff: 700).gained(0.45)
            bed.mix(Synth.tone(frequency: 62, seconds: seconds), gain: 0.18)
            // Distant traffic, passing rather than static.
            var random = DeterministicRandom(seed: seed &+ 21)
            for _ in 0..<5 {
                let pass = Synth.envelope(
                    Synth.filter(Synth.noise(seconds: 2.2, seed: random.next()),
                                 mode: .lowPass, cutoff: random.float(in: 300...900)),
                    attack: 0.9, decay: 1.2, curve: 1.5)
                bed.mix(pass, at: random.float(in: 0...5.5), gain: random.float(in: 0.15...0.35))
            }
        default:
            bed = Synth.filter(Synth.noise(seconds: seconds, seed: seed),
                               mode: .lowPass, cutoff: 600).gained(0.35)
        }

        return bed.loopable(crossfadeSeconds: 1.2).normalized(to: 0.32).sanitized()
    }

    /// Menu and match music: a tension bed rather than a tune. A generated melody would be
    /// worse than none, and in a competitive shooter the music has to stay under the
    /// footsteps anyway.
    public static func music(named name: String) -> Waveform {
        let seed = hash(name)
        let bpm: Float = name == "mus_menu" ? 84 : 96
        let beat = 60 / bpm
        #if DEBUG
        let bars = 3
        #else
        let bars = 8
        #endif
        let seconds = beat * 4 * Float(bars)
        // Keys chosen so the five maps do not all sound the same. A2 rather than A1: an
        // octave lower measured beautifully and would have been inaudible, because a phone
        // speaker reproduces almost nothing below 200 Hz and the drone's fundamental has
        // to land inside that.
        let root: Float
        switch name {
        case "mus_sandstorm": root = 110.0   // A2
        case "mus_refinery": root = 98.0     // G2
        case "mus_downtown": root = 116.5    // A#2
        case "mus_vault": root = 87.3        // F2
        case "mus_frostline": root = 123.5   // B2
        default: root = 103.8                // G#2
        }

        var track = Waveform(seconds: seconds)
        // Drone: root and fifth, detuned slightly so they beat against each other.
        for (ratio, gain) in [(1.0, 0.5), (1.5, 0.22), (2.0, 0.16), (1.003, 0.2)] {
            track.mix(Synth.tone(frequency: root * Float(ratio), seconds: seconds,
                                 wave: .triangle), gain: Float(gain))
        }
        // Pulse on the beat, which is what makes it read as music rather than a drone.
        var random = DeterministicRandom(seed: seed)
        var beatIndex = 0
        var time: Float = 0
        while time < seconds - beat {
            let accent = beatIndex % 4 == 0
            let pulse = Synth.envelope(
                Synth.sweep(from: root * (accent ? 4 : 3), to: root * 2,
                            seconds: beat * 0.8, wave: .triangle, curve: 2),
                attack: 0.004, decay: beat * 0.55, curve: 2.6)
            track.mix(pulse, at: time, gain: accent ? 0.3 : 0.16)
            // A filtered tick off the beat, for movement.
            if beatIndex % 2 == 1 {
                track.mix(Synth.envelope(
                    Synth.filter(Synth.noise(seconds: 0.12, seed: random.next()),
                                 mode: .bandPass, cutoff: 4200, resonance: 3),
                    attack: 0.001, decay: 0.08, curve: 3), at: time + beat * 0.5, gain: 0.08)
            }
            beatIndex += 1
            time += beat
        }
        let shaped = Synth.filter(track, mode: .lowPass, cutoff: 2600, resonance: 0.8)
        return shaped.loopable(crossfadeSeconds: beat * 2).normalized(to: 0.42).sanitized()
    }

    /// End of match. Major and rising, or minor and falling — the two most legible
    /// musical gestures there are, and the screen behind them says the rest.
    public static func victorySting(won: Bool) -> Waveform {
        let intervals: [Float] = won ? [0, 4, 7, 12] : [0, -3, -8, -12]
        var out = fanfare(intervals: intervals, seconds: 1.6, bright: won, transpose: won ? 0 : -5)
        // A pad underneath, so it reads as music rather than as another announcement.
        let root: Float = won ? 261.6 : 174.6
        let layers: [(ratio: Float, gain: Float)] = [(1, 0.4), (won ? 1.5 : 1.19, 0.25), (2, 0.18)]
        for (ratio, gain) in layers {
            out.mix(Synth.envelope(Synth.tone(frequency: root * ratio, seconds: 2.4,
                                              wave: .triangle),
                                   attack: 0.08, hold: 0.6, decay: 1.6, curve: 1.8),
                    gain: gain)
        }
        return out.normalized(to: 0.55).trimmedSilence()
            .faded(inSeconds: 0.01, outSeconds: 0.3).sanitized()
    }

    // MARK: - Helpers

    private static func surface(from name: String) -> SurfaceKind {
        for kind in SurfaceKind.allCases where String(describing: kind) == name { return kind }
        return .concrete
    }

    /// FNV-1a, so a name always produces the same sound across runs and devices.
    public static func hash(_ text: String) -> UInt64 {
        var value: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            value ^= UInt64(byte)
            value = value &* 0x100000001b3
        }
        return value
    }
}
