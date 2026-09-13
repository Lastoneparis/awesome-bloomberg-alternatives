using System.Collections.Generic;
using System.Text;

namespace Salvo.Sim
{
    /// <summary>
    /// A fingerprint of a content set, split by what a difference would actually break.
    /// </summary>
    /// <remarks>
    /// Live content is content that changes without a client rebuild, which means the client and
    /// the server can disagree about it — and a disagreement about weapon statistics is the
    /// nastiest bug class this project can have. Nothing errors. The client predicts a shot with
    /// its own damage number, the server resolves it with a different one, and the result looks
    /// like packet loss, or like the netcode being broken, or like nothing at all until someone
    /// notices a gun killing in three shots for half the lobby and four for the rest.
    ///
    /// <para>So there are two hashes, because the two kinds of difference deserve opposite
    /// responses:</para>
    ///
    /// <list type="bullet">
    /// <item><b>Simulation</b> — anything the authoritative simulation reads: damage, spread,
    /// timings, map geometry, mode rules. A mismatch must refuse the connection. Playing on
    /// differing numbers is worse than not playing.</item>
    /// <item><b>Presentation</b> — display keys, model keys, sound keys. A mismatch means one
    /// side will show a placeholder or a raw id. Worth logging; never worth refusing a match
    /// over, because doing so would mean a translation fix could not ship without forcing
    /// everyone to update at once.</item>
    /// </list>
    ///
    /// <para>The hash is computed from a canonical, sorted rendering of the definitions, so it
    /// depends on the content and not on the order a catalogue happened to enumerate in. That
    /// matters more than it sounds: a hash that changes when nothing did would reject every
    /// client after an unrelated refactor, and one that fails to change when something did is
    /// worse than having none at all.</para>
    /// </remarks>
    public sealed class ContentManifest
    {
        /// <summary>Human-readable version, for support and for telemetry. Not used for
        /// compatibility — the hashes are. A version string is a claim; a hash is evidence.</summary>
        public string Version = "0.0.0";

        public ulong SimulationHash;
        public ulong PresentationHash;

        public int WeaponCount;
        public int AttachmentCount;
        public int MapCount;
        public int WorldCount;
        public int ModeCount;

        public override string ToString() =>
            $"content {Version} sim:{SimulationHash:X16} pres:{PresentationHash:X16} "
            + $"({WorldCount} worlds, {WeaponCount} weapons, {MapCount} maps, {ModeCount} modes)";

        public static ContentManifest Build(GameContent content, string version = "0.0.0")
        {
            if (content == null) throw new System.ArgumentNullException(nameof(content));

            var simulation = new List<string>();
            var presentation = new List<string>();

            foreach (WeaponDefinition w in content.Weapons.All)
            {
                simulation.Add(WeaponSimulationKey(w));
                presentation.Add($"{w.Id}|{w.DisplayNameKey}|{w.ModelKey}|{w.FireSoundKey}|{w.ReloadSoundKey}");
            }
            foreach (AttachmentDefinition a in content.Attachments.All)
            {
                simulation.Add(AttachmentSimulationKey(a));
                presentation.Add($"{a.Id}|{a.DisplayNameKey}|{a.ModelKey}");
            }
            foreach (MapDefinition m in content.Maps.All)
            {
                simulation.Add(MapSimulationKey(m));
                presentation.Add($"{m.Id}|{m.DisplayNameKey}");
            }
            foreach (GameModeDefinition g in content.GameModes.All)
            {
                simulation.Add(ModeSimulationKey(g));
                presentation.Add($"{g.Id}|{g.DisplayNameKey}|{g.DescriptionKey}");
            }
            foreach (BotDifficultyDefinition d in content.BotDifficulties.All)
            {
                simulation.Add(DifficultySimulationKey(d));
                presentation.Add($"{d.Id}|{d.DisplayNameKey}");
            }
            foreach (WorldDefinition world in content.Worlds.All)
            {
                // A world contributes no numbers of its own; its pools decide what can be
                // chosen, which does change what a match can contain.
                simulation.Add($"world|{world.Id}|{Join(world.WeaponPool)}|{Join(world.Maps)}|{Join(world.Factions)}");
                presentation.Add($"{world.Id}|{world.DisplayNameKey}|{world.UiThemeKey}|{world.MusicKey}");
            }
            foreach (FactionDefinition f in content.Factions.All)
            {
                simulation.Add($"faction|{f.Id}|{f.WorldId}|{Join(f.WeaponPool)}|{Join(f.Characters)}");
                presentation.Add($"{f.Id}|{f.DisplayNameKey}|{f.ColourRgb:X6}");
            }
            foreach (CharacterDefinition c in content.Characters.All)
            {
                simulation.Add($"character|{c.Id}|{c.FactionId}");
                presentation.Add($"{c.Id}|{c.DisplayNameKey}|{c.ModelKey}|{c.VoiceKey}");
            }

            return new ContentManifest
            {
                Version = version,
                SimulationHash = HashSorted(simulation),
                PresentationHash = HashSorted(presentation),
                WeaponCount = content.Weapons.All.Count,
                AttachmentCount = content.Attachments.All.Count,
                MapCount = content.Maps.All.Count,
                WorldCount = content.Worlds.All.Count,
                ModeCount = content.GameModes.All.Count,
            };
        }

        // ---- canonical keys ---------------------------------------------------------------

        // Written out field by field rather than reflected over. Reflection would pick up new
        // fields automatically, which sounds like an advantage and is the opposite: it would
        // silently move the hash whenever anyone added a purely cosmetic field, invalidating
        // every client for no reason. Listing them means adding a field is a decision about
        // whether it affects a match.

        private static string WeaponSimulationKey(WeaponDefinition w) => string.Join("|",
            "weapon", w.Id, w.WorldId, (int)w.Class, (int)w.FireMode,
            F(w.BaseDamage), F(w.HeadshotMultiplier), F(w.FalloffStartMetres),
            F(w.FalloffEndMetres), F(w.FalloffFloor), F(w.ArmourPiercing),
            F(w.RoundsPerMinute), w.BurstCount, F(w.BurstDelaySeconds), w.PelletsPerShot,
            w.MagazineSize, w.ReserveAmmo, F(w.ReloadSeconds), F(w.EmptyReloadSeconds),
            w.ReloadsOneRoundAtATime, F(w.DrawSeconds), F(w.HolsterSeconds),
            F(w.MuzzleVelocity), F(w.MaxRangeMetres),
            F(w.HipSpreadRadians), F(w.AdsSpreadRadians), F(w.SpreadPerShot),
            F(w.MaxSpreadRadians), F(w.SpreadRecoveryPerSecond), F(w.SpreadRecoveryDelaySeconds),
            F(w.MovingSpreadPenalty), F(w.AirborneSpreadPenalty), F(w.CrouchSpreadMultiplier),
            F(w.RecoilVerticalRadians), F(w.RecoilHorizontalRadians), F(w.RecoilRecoveryPerSecond),
            SprayKey(w.SprayPattern),
            F(w.AdsSeconds), F(w.MoveSpeedMultiplier), F(w.AdsMoveSpeedMultiplier));

        private static string AttachmentSimulationKey(AttachmentDefinition a) => string.Join("|",
            "attachment", a.Id, (int)a.Slot, Join(a.CompatibleWeapons),
            F(a.DamageMultiplier), F(a.RecoilMultiplier), F(a.HipSpreadMultiplier),
            F(a.AdsSpreadMultiplier), F(a.AdsSpeedMultiplier), F(a.ReloadSpeedMultiplier),
            F(a.MoveSpeedMultiplier), F(a.RangeMultiplier), F(a.FalloffStartMultiplier),
            a.MagazineSizeDelta, a.SuppressesMuzzleFlash, a.HidesFromMinimap);

        private static string MapSimulationKey(MapDefinition m)
        {
            // Geometry is hashed, because a wall that exists on one machine and not the other
            // makes shots pass through cover on exactly one of them.
            var builder = new StringBuilder("map|").Append(m.Id).Append('|').Append(m.WorldId);
            builder.Append('|').Append(BoxKey(m.Bounds));
            for (int i = 0; i < m.Brushes.Count; i++)
            {
                MapBrush b = m.Brushes[i];
                builder.Append('|').Append(BoxKey(b.Box)).Append(',').Append((int)b.Surface)
                       .Append(b.IsClip ? 'c' : '-').Append(b.BlocksSight ? 's' : '-')
                       .Append(b.BlocksBullets ? 'b' : '-');
            }
            for (int i = 0; i < m.Spawns.Count; i++)
            {
                SpawnPoint s = m.Spawns[i];
                builder.Append("|s").Append(V(s.Position)).Append(',').Append(F(s.Yaw))
                       .Append(',').Append((int)s.Team).Append(',').Append(s.Priority);
            }
            for (int i = 0; i < m.Objectives.Count; i++)
                builder.Append("|o").Append(m.Objectives[i].Index).Append(',')
                       .Append(BoxKey(m.Objectives[i].Volume));
            return builder.ToString();
        }

        private static string ModeSimulationKey(GameModeDefinition g) => string.Join("|",
            "mode", g.Id, (int)g.Kind, g.MinPlayers, g.MaxPlayers, g.TeamSize, g.IsTeamBased,
            g.ScoreLimit, F(g.TimeLimitSeconds), g.RoundsToWin, F(g.RoundSeconds),
            F(g.WarmupSeconds), F(g.FreezeSeconds), g.AllowsRespawn, F(g.RespawnDelaySeconds),
            F(g.SpawnProtectionSeconds), g.FriendlyFire, g.HealthRegenerates,
            F(g.RegenDelaySeconds), F(g.RegenPerSecond), F(g.StartingHealth), F(g.StartingArmour));

        private static string DifficultySimulationKey(BotDifficultyDefinition d) => string.Join("|",
            "bot", d.Id, F(d.ReactionSeconds), F(d.AimErrorRadians),
            F(d.TurnSpeedRadiansPerSecond), F(d.TriggerDisciplineChance), F(d.ViewConeDegrees),
            F(d.SightRangeMetres), F(d.HearingRangeMetres), F(d.RetreatTendency),
            F(d.CoverPreference), F(d.ObjectiveFocus));

        // ---- primitives ---------------------------------------------------------------------

        /// <summary>
        /// A float rendered so the same value always produces the same text.
        /// </summary>
        /// <remarks>
        /// Round-trip formatting with the invariant culture. Both halves matter: a culture that
        /// writes a decimal comma would give a French client a different hash from an English
        /// server for identical content, and a lossy format would hash two genuinely different
        /// values the same.
        /// </remarks>
        private static string F(float value) =>
            value.ToString("R", System.Globalization.CultureInfo.InvariantCulture);

        private static string V(Vec3 v) => $"{F(v.X)};{F(v.Y)};{F(v.Z)}";
        private static string BoxKey(Aabb box) => $"{V(box.Min)};{V(box.Max)}";

        private static string Join(ContentId[] ids)
        {
            if (ids == null || ids.Length == 0) return "";
            // Sorted: a pool reordered is the same pool.
            var copy = new string[ids.Length];
            for (int i = 0; i < ids.Length; i++) copy[i] = ids[i].ToString();
            System.Array.Sort(copy, System.StringComparer.Ordinal);
            return string.Join(",", copy);
        }

        private static string SprayKey(SprayPoint[] pattern)
        {
            if (pattern == null || pattern.Length == 0) return "";
            var builder = new StringBuilder();
            // Order matters here, unlike a pool: a spray pattern is a sequence.
            for (int i = 0; i < pattern.Length; i++)
                builder.Append(F(pattern[i].Vertical)).Append(';')
                       .Append(F(pattern[i].Horizontal)).Append(',');
            return builder.ToString();
        }

        /// <summary>
        /// FNV-1a over the sorted entries.
        /// </summary>
        /// <remarks>
        /// Sorting is what makes the hash a property of the content rather than of the order a
        /// catalogue enumerated in. Not cryptographic, and must never be used as if it were: it
        /// detects accidental divergence between a client and a server, not a client that has
        /// deliberately altered its content and wants to lie about it. Defending against that
        /// needs the server to refuse to take the client's word for anything, which is what the
        /// rest of the architecture already does.
        /// </remarks>
        private static ulong HashSorted(List<string> entries)
        {
            entries.Sort(System.StringComparer.Ordinal);
            ulong hash = 14695981039346656037UL;
            for (int i = 0; i < entries.Count; i++)
            {
                string entry = entries[i];
                for (int c = 0; c < entry.Length; c++)
                {
                    hash ^= entry[c];
                    hash *= 1099511628211UL;
                }
                hash ^= '\n';
                hash *= 1099511628211UL;
            }
            return hash;
        }
    }
}
