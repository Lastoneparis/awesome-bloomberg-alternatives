namespace Salvo.Sim
{
    public enum Stance : byte { Standing, Crouching }

    /// <summary>
    /// Everything the movement model needs to continue from one tick to the next.
    /// </summary>
    /// <remarks>
    /// A struct, and a complete one: reconciliation works by restoring a past state and
    /// replaying inputs over it, so anything the step function reads must live here or the
    /// replay diverges. That is the reason for the odd-looking members — coyote time, the
    /// jump buffer, the stride accumulator — which look like presentation state but feed back
    /// into the simulation and so have to be rewound with it.
    ///
    /// <see cref="Position"/> is the player's <em>feet</em>, not their centre. Feet are what
    /// spawn points, ground traces and map geometry are expressed in; deriving the centre from
    /// the current height is one line, whereas deriving feet from a centre means every caller
    /// has to know the current stance.
    /// </remarks>
    public struct MovementState
    {
        public Vec3 Position;
        public Vec3 Velocity;
        public ViewAngles View;

        public bool IsGrounded;
        public SurfaceKind GroundSurface;

        /// <summary>0 = standing, 1 = fully crouched. Interpolated, so the hitbox shrinks
        /// smoothly and a crouch cannot teleport the head.</summary>
        public float CrouchAmount;
        public Stance DesiredStance;

        public float TimeSinceGrounded;
        public float JumpBufferRemaining;
        /// <summary>Prevents one held jump key from re-triggering every tick.</summary>
        public bool JumpConsumed;

        /// <summary>Distance walked since the last footstep, in metres.</summary>
        public float StrideDistance;
        /// <summary>Set for one tick when <see cref="StrideDistance"/> wrapped. Presentation
        /// reads it; the server reads it too, because enemies hear footsteps.</summary>
        public bool SteppedThisTick;

        /// <summary>Downward speed at the moment of the last landing, 0 if none this tick.
        /// The damage model, not the movement model, decides what it costs.</summary>
        public float LandingImpactSpeed;

        public float Height =>
            SalvoMath.Lerp(CharacterDefinition.StandingHeight,
                           CharacterDefinition.CrouchingHeight, CrouchAmount);

        /// <summary>Camera and hitbox reference point. 0.12 m below the crown, where eyes are.</summary>
        public Vec3 EyePosition => Position + new Vec3(0f, Height - 0.12f, 0f);

        public Vec3 Centre => Position + new Vec3(0f, Height * 0.5f, 0f);

        public Vec3 HalfExtents =>
            new Vec3(CharacterDefinition.Radius, Height * 0.5f, CharacterDefinition.Radius);

        public Aabb Bounds => new Aabb(
            Position - new Vec3(CharacterDefinition.Radius, 0f, CharacterDefinition.Radius),
            Position + new Vec3(CharacterDefinition.Radius, Height, CharacterDefinition.Radius));

        public float HorizontalSpeed => Velocity.HorizontalLength;

        public static MovementState AtSpawn(SpawnPoint spawn) => new MovementState
        {
            Position = spawn.Position,
            Velocity = Vec3.Zero,
            View = new ViewAngles(0f, spawn.Yaw),
            IsGrounded = true,
            GroundSurface = SurfaceKind.Concrete,
            CrouchAmount = 0f,
            DesiredStance = Stance.Standing,
        };
    }
}
