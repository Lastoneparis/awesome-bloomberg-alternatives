namespace Salvo.Sim
{
    /// <summary>
    /// Every number the movement model uses. A class rather than constants because movement
    /// feel is content: a WWII world can be heavier than a sci-fi one without a code change,
    /// and a training mode can turn gravity down. It is deliberately <em>not</em> per-character
    /// (see <see cref="CharacterDefinition"/>) — every player on the server moves by the same
    /// rules, or the game is pay-to-win.
    /// </summary>
    public class MovementTuning
    {
        /// <summary>Metres per second on flat ground at full stick.</summary>
        public float RunSpeed = 5.6f;

        /// <summary>Speed while holding walk. Quiet, and the reason walking exists.</summary>
        public float WalkSpeed = 2.6f;

        public float CrouchSpeed = 2.1f;

        /// <summary>
        /// Fraction of run speed retained when moving backwards. Below 1 so that pushing into
        /// a fight and retreating from one are different decisions.
        /// </summary>
        public float BackwardMultiplier = 0.82f;
        public float StrafeMultiplier = 0.92f;

        /// <summary>Metres per second squared. High: a shooter wants response, not momentum.</summary>
        public float GroundAcceleration = 62f;
        public float GroundFriction = 8.5f;

        /// <summary>
        /// Air acceleration is small but non-zero. Zero feels like being on rails; large
        /// values reproduce the bunny-hopping of the engines this genre grew out of, which is
        /// a skill ceiling we are deliberately not building a mobile game around.
        /// </summary>
        public float AirAcceleration = 9f;
        public float AirSpeedCap = 1.1f;

        public float Gravity = 19.6f;
        /// <summary>Chosen for a ~1.05 m apex, which clears the 1 m crate module.</summary>
        public float JumpSpeed = 6.4f;
        public float TerminalVelocity = 60f;

        /// <summary>Height of a step the player walks over rather than bumps into.</summary>
        public float StepHeight = 0.45f;

        /// <summary>
        /// Slopes steeper than this are walls. cos(46°): shallow enough that stairs and ramps
        /// are walkable, steep enough that the player cannot climb a crate by nudging it.
        /// </summary>
        public float MaxGroundNormalY = 0.695f;

        /// <summary>Seconds after leaving a ledge during which a jump still works.</summary>
        public float CoyoteSeconds = 0.1f;

        /// <summary>Seconds a jump press is remembered while airborne.</summary>
        public float JumpBufferSeconds = 0.12f;

        /// <summary>Seconds to change stance. Non-instant so crouch-spam is not a dodge.</summary>
        public float CrouchTransitionSeconds = 0.18f;

        /// <summary>Fall speed below which landing costs nothing.</summary>
        public float SafeFallSpeed = 11f;
        /// <summary>Fall speed at which landing is lethal.</summary>
        public float LethalFallSpeed = 26f;

        /// <summary>Metres travelled per footstep sound at run speed.</summary>
        public float StrideMetres = 2.1f;

        public MovementTuning Clone() => (MovementTuning)MemberwiseClone();

        public void Validate(System.Collections.Generic.List<string> problems)
        {
            if (RunSpeed <= 0f) problems.Add("RunSpeed must be positive.");
            if (WalkSpeed >= RunSpeed)
                problems.Add("WalkSpeed is not slower than RunSpeed — walking would be free stealth.");
            if (CrouchSpeed > WalkSpeed)
                problems.Add("CrouchSpeed exceeds WalkSpeed — crouching would be the fast quiet option.");
            if (Gravity <= 0f) problems.Add("Gravity must be positive.");
            if (JumpSpeed <= 0f) problems.Add("JumpSpeed must be positive.");
            if (StepHeight < 0f) problems.Add("StepHeight cannot be negative.");
            if (StepHeight >= CharacterDefinition.CrouchingHeight)
                problems.Add("StepHeight is at least a crouched player's height — players would walk onto each other's heads.");
            if (MaxGroundNormalY <= 0f || MaxGroundNormalY >= 1f)
                problems.Add("MaxGroundNormalY must be between 0 and 1 exclusive.");
            if (LethalFallSpeed <= SafeFallSpeed)
                problems.Add("LethalFallSpeed is not above SafeFallSpeed — every fall would be lethal.");
            if (AirSpeedCap < 0f) problems.Add("AirSpeedCap cannot be negative.");
        }
    }
}
