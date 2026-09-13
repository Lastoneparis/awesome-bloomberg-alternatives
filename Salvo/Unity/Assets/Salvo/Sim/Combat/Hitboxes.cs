namespace Salvo.Sim
{
    /// <summary>Which part of a player a shot landed on.</summary>
    public enum HitRegion : byte
    {
        None = 0,
        Head = 1,
        /// <summary>Chest and arms. See <see cref="PlayerHitboxes"/> for why the arms are in
        /// here rather than counted as limbs.</summary>
        Torso = 2,
        /// <summary>Legs. Reduced damage, so that clipping someone's shin as they cross a gap
        /// is a worse outcome than catching them in the chest.</summary>
        Legs = 3,
    }

    /// <summary>
    /// The boxes a player can be shot in, in world space.
    /// </summary>
    /// <remarks>
    /// Three stacked boxes, not a skeleton. This is a deliberate and load-bearing simplification.
    ///
    /// <para>A per-bone hitbox mesh would mean the authoritative server has to evaluate
    /// animation — which means the server has to run the animation system, which means it has
    /// to be Unity, which contradicts the whole architecture (see ARCHITECTURE.md). It would
    /// also make hit registration depend on animation blend state, so two clients showing
    /// slightly different poses would disagree about whether a shot connected. Boxes derived
    /// purely from position, stance and pitch are reproducible from a snapshot, which is what
    /// lag compensation requires.</para>
    ///
    /// <para><b>The boxes are stacked, never nested.</b> Each owns a slice of the character's
    /// height and the full body width within it. An earlier version modelled the torso as a
    /// narrow chest with a wider "limbs" box around it for the arms — which meant the wider box
    /// enclosed the narrower one, so every shot from every angle hit limbs and the torso region
    /// was unreachable. Headshots worked; chest shots silently did not exist. Nesting boxes and
    /// then taking the nearest hit cannot work, because the enclosing box is always nearer.</para>
    ///
    /// <para>The price of stacking is that arms count as torso. That is the honest trade: an
    /// arm hit doing chest damage is a small unfairness, whereas a region no bullet can ever
    /// reach is a broken damage model.</para>
    /// </remarks>
    public struct PlayerHitboxes
    {
        public Aabb Head;
        public Aabb Torso;
        public Aabb Legs;

        /// <summary>Cheap rejection volume covering all three. Tested first so that most
        /// players in a lag-compensated trace are dismissed with one box test.</summary>
        public Aabb Whole;

        // Fractions of the character's current height. A 1.8 m character gives a 0.23 m head,
        // which is about life-size — headshots should reward aim, not be a lottery.
        private const float HeadBottomFraction = 0.87f;
        private const float TorsoBottomFraction = 0.45f;

        private const float HeadHalfWidth = 0.115f;

        /// <summary>
        /// Builds the boxes for a player at a given position, height and pitch.
        /// </summary>
        /// <remarks>
        /// Pitch leans the head forward and down, because a player looking at their feet with
        /// a head floating at full standing height is the classic way to be shot in a head
        /// that is not visibly there. The lean is small and purely geometric — no animation,
        /// so the server can reproduce it exactly.
        /// </remarks>
        public static PlayerHitboxes For(Vec3 feet, float height, ViewAngles view)
        {
            float headBottom = height * HeadBottomFraction;
            float torsoBottom = height * TorsoBottomFraction;
            float radius = CharacterDefinition.Radius;

            // Looking down pitches the head forward by up to ~12 cm; looking up tucks it back.
            float lean = (float)System.Math.Sin(view.Pitch) * 0.12f;
            Vec3 headOffset = view.FlatForward * lean;

            Vec3 headCentre = feet + new Vec3(0f, (headBottom + height) * 0.5f, 0f) + headOffset;
            var head = Aabb.FromCentre(headCentre,
                                       new Vec3(HeadHalfWidth * 2f, height - headBottom,
                                                HeadHalfWidth * 2f));

            var torso = new Aabb(
                new Vec3(feet.X - radius, feet.Y + torsoBottom, feet.Z - radius),
                new Vec3(feet.X + radius, feet.Y + headBottom, feet.Z + radius));

            var legs = new Aabb(
                new Vec3(feet.X - radius, feet.Y, feet.Z - radius),
                new Vec3(feet.X + radius, feet.Y + torsoBottom, feet.Z + radius));

            return new PlayerHitboxes
            {
                Head = head,
                Torso = torso,
                Legs = legs,
                Whole = new Aabb(
                    Vec3.Min(Vec3.Min(head.Min, torso.Min), legs.Min),
                    Vec3.Max(Vec3.Max(head.Max, torso.Max), legs.Max)),
            };
        }

        public static PlayerHitboxes For(MovementState state) =>
            For(state.Position, state.Height, state.View);

        /// <summary>
        /// Traces a ray against this player and reports the nearest region it struck.
        /// </summary>
        /// <remarks>
        /// Nearest wins, not most valuable. The boxes are stacked so they only meet at their
        /// shared faces, but a ray angled steeply down the body can still clip two of them; in
        /// that case the one it reaches first is the one it hit. Preferring the head would turn
        /// every steep shot into a headshot.
        /// </remarks>
        public bool Raycast(Vec3 origin, Vec3 direction, float maxDistance,
                            out float distance, out HitRegion region)
        {
            distance = float.MaxValue;
            region = HitRegion.None;

            if (!Whole.Raycast(origin, direction, maxDistance, out _, out _)) return false;

            if (Head.Raycast(origin, direction, maxDistance, out float headDistance, out _)
                && headDistance < distance)
            {
                distance = headDistance;
                region = HitRegion.Head;
            }
            if (Torso.Raycast(origin, direction, maxDistance, out float torsoDistance, out _)
                && torsoDistance < distance)
            {
                distance = torsoDistance;
                region = HitRegion.Torso;
            }
            if (Legs.Raycast(origin, direction, maxDistance, out float legDistance, out _)
                && legDistance < distance)
            {
                distance = legDistance;
                region = HitRegion.Legs;
            }

            if (region == HitRegion.None) { distance = 0f; return false; }
            return true;
        }
    }

    public static class HitRegionExtensions
    {
        /// <summary>
        /// Damage multiplier for a region. The head multiplier is not here — it belongs to the
        /// weapon (<see cref="WeaponDefinition.HeadshotMultiplier"/>), because how much a
        /// headshot is worth is a balance decision per weapon, not a property of skulls.
        /// </summary>
        public static float DamageMultiplier(this HitRegion region) => region switch
        {
            HitRegion.Torso => 1.0f,
            HitRegion.Legs => 0.75f,
            _ => 1.0f,
        };
    }
}
