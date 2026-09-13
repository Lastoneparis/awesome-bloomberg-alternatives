namespace Salvo.Sim
{
    /// <summary>
    /// The movement model. Pure and deterministic: the same state plus the same input plus the
    /// same world always produces the same next state, on the server, on the predicting client,
    /// and during a replay.
    /// </summary>
    /// <remarks>
    /// It is a static function over an explicit state rather than a stateful object precisely
    /// so that reconciliation is possible: the client replays a dozen ticks per correction,
    /// and an object holding hidden state between calls could not be rewound.
    ///
    /// <para>Deliberately absent: any notion of who the player is. A weapon's
    /// <see cref="WeaponDefinition.MoveSpeedMultiplier"/> reaches this code as a parameter,
    /// not by looking up the player's loadout, so the movement model has no opinion about
    /// combat and combat has no opinion about movement.</para>
    /// </remarks>
    public static class MovementSimulation
    {
        /// <summary>Gap kept between the player box and geometry. Without it, floating-point
        /// error leaves the player exactly touching a wall and the next sweep starts solid.</summary>
        private const float SkinWidth = 0.002f;

        /// <summary>
        /// How far above and below the feet the ground probe reaches. Large enough to survive
        /// the residue the skin width and depenetration leave behind, small enough that a
        /// player is not "grounded" while hovering.
        /// </summary>
        private const float GroundProbe = 0.02f;

        /// <summary>Collide-and-slide iterations per move. Three handles a floor, a wall and
        /// the corner between them; a fourth would only matter in geometry we do not ship.</summary>
        private const int MaxSlides = 3;

        /// <summary>
        /// Advances one player by one fixed tick.
        /// </summary>
        /// <param name="state">Mutated in place.</param>
        /// <param name="input">The command for this tick. Already quantised.</param>
        /// <param name="world">Static level collision.</param>
        /// <param name="tuning">Movement numbers, from content.</param>
        /// <param name="speedMultiplier">
        /// Combined multiplier from the held weapon and whether the player is aiming. Passed in
        /// so this function stays ignorant of weapons.
        /// </param>
        /// <param name="dt">Fixed timestep. Always <see cref="FixedClock.TickInterval"/> in
        /// production; a parameter so tests can probe other rates.</param>
        public static void Step(ref MovementState state, PlayerInput input, CollisionWorld world,
                                MovementTuning tuning, float speedMultiplier, float dt)
        {
            state.SteppedThisTick = false;
            state.LandingImpactSpeed = 0f;

            // The view is taken from the command verbatim. The server does not smooth or
            // filter it: aim is the player's, and any server-side adjustment would show up as
            // the game fighting the stick.
            state.View = input.View;

            UpdateStance(ref state, input, world, tuning, dt);
            bool wasGrounded = state.IsGrounded;

            ApplyJump(ref state, input, tuning, dt);
            ApplyHorizontalControl(ref state, input, tuning, speedMultiplier, dt);

            if (!state.IsGrounded)
            {
                state.Velocity.Y -= tuning.Gravity * dt;
                if (state.Velocity.Y < -tuning.TerminalVelocity)
                    state.Velocity.Y = -tuning.TerminalVelocity;
            }

            // Captured before the move, because landing zeroes the downward velocity and the
            // fall damage model needs the speed the player actually hit the floor at.
            float fallSpeed = -state.Velocity.Y;

            MoveWithCollision(ref state, world, tuning, dt);
            UpdateGrounded(ref state, world, tuning, wasGrounded, fallSpeed, dt);
            UpdateStride(ref state, input, tuning, dt);
        }

        // ---- stance -------------------------------------------------------------------

        private static void UpdateStance(ref MovementState state, PlayerInput input,
                                         CollisionWorld world, MovementTuning tuning, float dt)
        {
            state.DesiredStance = input.Held(InputButtons.Crouch) ? Stance.Crouching : Stance.Standing;

            float target = state.DesiredStance == Stance.Crouching ? 1f : 0f;
            if (target < state.CrouchAmount && !CanStandUp(state, world))
            {
                // Under a low ceiling the player stays crouched however hard they ask not to.
                // Forcing the stance instead of ignoring the input matters: the alternative is
                // growing into the ceiling and being ejected through it.
                target = state.CrouchAmount;
            }

            float rate = tuning.CrouchTransitionSeconds > 0f ? dt / tuning.CrouchTransitionSeconds : 1f;
            state.CrouchAmount = SalvoMath.Clamp01(SalvoMath.MoveTowards(state.CrouchAmount, target, rate));
        }

        private static bool CanStandUp(MovementState state, CollisionWorld world)
        {
            // Shrunk horizontally so that standing flush against a wall does not read as a
            // ceiling, but full height vertically: the whole point is to test the headroom.
            float radius = CharacterDefinition.Radius - SkinWidth;
            var standing = new Aabb(
                state.Position - new Vec3(radius, 0f, radius),
                state.Position + new Vec3(radius, CharacterDefinition.StandingHeight, radius));
            return !world.Overlaps(standing);
        }

        // ---- jumping ------------------------------------------------------------------

        private static void ApplyJump(ref MovementState state, PlayerInput input,
                                      MovementTuning tuning, float dt)
        {
            bool pressed = input.Held(InputButtons.Jump);
            if (!pressed) state.JumpConsumed = false;

            if (pressed && !state.JumpConsumed)
                state.JumpBufferRemaining = tuning.JumpBufferSeconds;
            else
                state.JumpBufferRemaining = SalvoMath.MoveTowards(state.JumpBufferRemaining, 0f, dt);

            bool hasGround = state.IsGrounded || state.TimeSinceGrounded <= tuning.CoyoteSeconds;
            if (state.JumpBufferRemaining <= 0f || !hasGround || state.JumpConsumed) return;

            state.Velocity.Y = tuning.JumpSpeed;
            state.IsGrounded = false;
            state.TimeSinceGrounded = tuning.CoyoteSeconds + 1f; // no second coyote jump
            state.JumpBufferRemaining = 0f;
            state.JumpConsumed = true;
        }

        // ---- horizontal control -------------------------------------------------------

        /// <summary>
        /// The speed this player is allowed to reach, before acceleration is applied.
        /// </summary>
        public static float TargetSpeed(MovementState state, PlayerInput input,
                                        MovementTuning tuning, float speedMultiplier)
        {
            float baseSpeed = tuning.RunSpeed;
            if (input.Held(InputButtons.Walk)) baseSpeed = tuning.WalkSpeed;
            // Crouch blends rather than switches, so half-crouched movement is half-penalised
            // and a player cannot get the crouch hitbox at run speed during the transition.
            baseSpeed = SalvoMath.Lerp(baseSpeed,
                                       System.Math.Min(baseSpeed, tuning.CrouchSpeed),
                                       state.CrouchAmount);

            // Directional penalties are applied to the intended direction, not afterwards, so
            // that a diagonal retreat is penalised proportionally rather than fully.
            float forward = input.MoveForwardAxis;
            float right = input.MoveRightAxis;
            float magnitude = (float)System.Math.Sqrt(forward * forward + right * right);
            if (magnitude < 1e-4f) return 0f;

            // The weights must sum to 1, so they are normalised by the L1 norm, not by the
            // Euclidean magnitude. Dividing by the magnitude gives two weights of 0.707 on a
            // diagonal, which sum to 1.41 and turn a pair of penalties into a 41% speed bonus
            // — the fastest way to cross the map would be to run sideways.
            float absForward = System.Math.Abs(forward);
            float absRight = System.Math.Abs(right);
            float total = absForward + absRight;
            float forwardWeight = absForward / total;
            float rightWeight = absRight / total;
            float directional = forwardWeight * (forward < 0f ? tuning.BackwardMultiplier : 1f)
                              + rightWeight * tuning.StrafeMultiplier;

            return baseSpeed * directional * speedMultiplier * SalvoMath.Clamp01(magnitude);
        }

        private static void ApplyHorizontalControl(ref MovementState state, PlayerInput input,
                                                   MovementTuning tuning, float speedMultiplier,
                                                   float dt)
        {
            ViewAngles view = state.View;
            Vec3 wish = (view.FlatForward * input.MoveForwardAxis + view.Right * input.MoveRightAxis);
            float wishLength = wish.HorizontalLength;
            Vec3 wishDirection = wishLength > 1e-4f ? wish / wishLength : Vec3.Zero;
            float wishSpeed = TargetSpeed(state, input, tuning, speedMultiplier);

            if (state.IsGrounded)
            {
                ApplyFriction(ref state, tuning, dt);
                Accelerate(ref state, wishDirection, wishSpeed, tuning.GroundAcceleration, dt);
            }
            else
            {
                // Air control is capped in absolute terms, not as a fraction of wish speed.
                // That is what stops a player from converting a long fall into unbounded
                // horizontal speed by steering, which is the bunny-hop exploit in one line.
                float airSpeed = System.Math.Min(wishSpeed, tuning.AirSpeedCap);
                Accelerate(ref state, wishDirection, airSpeed, tuning.AirAcceleration, dt);
            }
        }

        private static void ApplyFriction(ref MovementState state, MovementTuning tuning, float dt)
        {
            float speed = state.Velocity.HorizontalLength;
            if (speed < 1e-4f)
            {
                state.Velocity.X = 0f;
                state.Velocity.Z = 0f;
                return;
            }
            // A floor under the drop keeps friction from becoming vanishingly weak at low
            // speed, which is what would leave a player drifting after releasing the stick.
            float drop = System.Math.Max(speed, tuning.WalkSpeed) * tuning.GroundFriction * dt;
            float scale = System.Math.Max(0f, speed - drop) / speed;
            state.Velocity.X *= scale;
            state.Velocity.Z *= scale;
        }

        private static void Accelerate(ref MovementState state, Vec3 direction, float targetSpeed,
                                       float acceleration, float dt)
        {
            if (targetSpeed <= 0f || direction == Vec3.Zero) return;

            // Only the component of existing velocity along the wish direction counts against
            // the cap. Velocity perpendicular to it is untouched, which is what makes turning
            // while at speed feel like turning rather than braking.
            float current = Vec3.Dot(state.Velocity.Flattened, direction);
            float room = targetSpeed - current;
            if (room <= 0f) return;

            // Acceleration is in m/s^2, so the per-tick increment is simply a*dt, capped by
            // the room left under the target. Scaling it by the target speed (as the Quake
            // lineage does) would make a walking player accelerate more slowly than a running
            // one, which reads as the controls going sluggish exactly when precision matters.
            float add = System.Math.Min(acceleration * dt, room);
            state.Velocity.X += direction.X * add;
            state.Velocity.Z += direction.Z * add;
        }

        // ---- collision ----------------------------------------------------------------

        private static void MoveWithCollision(ref MovementState state, CollisionWorld world,
                                              MovementTuning tuning, float dt)
        {
            Vec3 halfExtents = state.HalfExtents;
            Vec3 delta = state.Velocity * dt;
            if (delta == Vec3.Zero) return;

            // Vertical and horizontal are resolved separately. Solving them together makes a
            // player walking into a step lose their horizontal speed to the step's face; split,
            // the horizontal pass can try again from the stepped-up height.
            Vec3 horizontal = delta.Flattened;
            Vec3 vertical = new Vec3(0f, delta.Y, 0f);

            Vec3 beforeStep = state.Position;
            Vec3 velocityBeforeStep = state.Velocity;
            SlideMove(ref state, halfExtents, horizontal, world, clipVelocity: true);
            bool blocked = Vec3.DistanceSquared(state.Position.Flattened, (beforeStep + horizontal).Flattened) > 1e-6f;

            if (blocked && state.IsGrounded && tuning.StepHeight > 0f)
                TryStepUp(ref state, beforeStep, velocityBeforeStep, halfExtents, horizontal, world, tuning);

            SlideMove(ref state, halfExtents, vertical, world, clipVelocity: true);

            // Last line of defence. Sliding keeps the player out of geometry in the ordinary
            // case; this catches the rest — seams, stance changes that grow the box into a
            // ceiling, and a spawn point authored a millimetre inside a brush.
            Vec3 resolved = world.Depenetrate(state.Position + new Vec3(0f, halfExtents.Y, 0f),
                                              halfExtents);
            state.Position = resolved - new Vec3(0f, halfExtents.Y, 0f);
        }

        /// <summary>
        /// Attempts the move again from <paramref name="tuning"/>.StepHeight higher, then drops
        /// back down. Keeps the result only if it got further than the blocked attempt did —
        /// so a wall stays a wall, but a stair tread is walked over without a jump.
        /// </summary>
        private static void TryStepUp(ref MovementState state, Vec3 origin, Vec3 originVelocity,
                                      Vec3 halfExtents, Vec3 horizontal, CollisionWorld world,
                                      MovementTuning tuning)
        {
            Vec3 blockedPosition = state.Position;
            float blockedDistance = Vec3.DistanceSquared(origin.Flattened, blockedPosition.Flattened);

            var stepped = state;
            stepped.Position = origin;
            stepped.Velocity = originVelocity;

            SlideMove(ref stepped, halfExtents, new Vec3(0f, tuning.StepHeight, 0f), world, clipVelocity: false);
            SlideMove(ref stepped, halfExtents, horizontal, world, clipVelocity: true);
            // The drop is slightly longer than the lift so the player settles onto the tread
            // rather than hovering a step-height above it when there was nothing to step onto.
            SlideMove(ref stepped, halfExtents,
                      new Vec3(0f, -(tuning.StepHeight + SkinWidth), 0f), world, clipVelocity: false);

            float steppedDistance = Vec3.DistanceSquared(origin.Flattened, stepped.Position.Flattened);
            if (steppedDistance <= blockedDistance + 1e-6f) return;   // gained nothing: it is a wall

            // Refuse a "step" that is really a launch — this is what stops a player from
            // ratcheting up a vertical surface one tick at a time.
            if (stepped.Position.Y - origin.Y > tuning.StepHeight + SkinWidth * 4f) return;

            state.Position = stepped.Position;
            state.Velocity = stepped.Velocity;
        }

        /// <summary>
        /// Moves by <paramref name="delta"/>, sliding along whatever it hits.
        /// </summary>
        private static void SlideMove(ref MovementState state, Vec3 halfExtents, Vec3 delta,
                                      CollisionWorld world, bool clipVelocity)
        {
            Vec3 remaining = delta;
            for (int iteration = 0; iteration < MaxSlides; iteration++)
            {
                if (remaining.LengthSquared < 1e-10f) return;

                Vec3 centre = state.Position + new Vec3(0f, halfExtents.Y, 0f);
                Vec3 target = centre + remaining;
                TraceHit hit = world.SweepBox(centre, halfExtents, target, out bool startedSolid);

                if (startedSolid && !hit.Hit)
                {
                    // Already inside geometry with nothing ahead to stop us. Moving is the
                    // least-bad option — refusing to move would wedge the player permanently,
                    // and the next tick's sweep gets another chance to resolve it.
                    state.Position += remaining;
                    return;
                }

                if (!hit.Hit)
                {
                    state.Position += remaining;
                    return;
                }

                float travel = System.Math.Max(0f, hit.Fraction * remaining.Length - SkinWidth);
                Vec3 direction = remaining.Normalized;
                state.Position += direction * travel;

                remaining = (remaining * (1f - hit.Fraction)).ClippedAgainst(hit.Normal);
                if (clipVelocity) state.Velocity = state.Velocity.ClippedAgainst(hit.Normal);
            }
        }

        // ---- ground detection ---------------------------------------------------------

        private static void UpdateGrounded(ref MovementState state, CollisionWorld world,
                                           MovementTuning tuning, bool wasGrounded,
                                           float fallSpeed, float dt)
        {
            bool grounded = false;
            if (state.Velocity.Y <= 0.001f)
            {
                Vec3 halfExtents = state.HalfExtents;
                Vec3 centre = state.Position + new Vec3(0f, halfExtents.Y, 0f);
                // The probe starts *above* the player and sweeps down past their feet. Starting
                // at the feet would begin the sweep exactly touching the floor, which is the
                // one configuration a slab test cannot give a useful answer for; lifting first
                // means the probe always has clear air to start in.
                Vec3 lifted = centre + new Vec3(0f, GroundProbe, 0f);
                Vec3 probe = centre - new Vec3(0f, GroundProbe, 0f);
                TraceHit hit = world.SweepBox(lifted, halfExtents, probe, out _);
                grounded = hit.Hit && hit.Normal.Y >= tuning.MaxGroundNormalY;
                if (grounded)
                {
                    state.GroundSurface = hit.Surface;
                    if (state.Velocity.Y < 0f) state.Velocity.Y = 0f;
                }
            }

            if (grounded && !wasGrounded && fallSpeed > 0f)
                state.LandingImpactSpeed = fallSpeed;

            state.IsGrounded = grounded;
            state.TimeSinceGrounded = grounded ? 0f : state.TimeSinceGrounded + dt;
        }

        // ---- footsteps ----------------------------------------------------------------

        private static void UpdateStride(ref MovementState state, PlayerInput input,
                                         MovementTuning tuning, float dt)
        {
            if (!state.IsGrounded) { return; }

            float speed = state.Velocity.HorizontalLength;
            if (speed < 0.35f) { state.StrideDistance = 0f; return; }

            state.StrideDistance += speed * dt;
            float stride = tuning.StrideMetres;
            // Walking covers the same ground in more, quieter steps; the loudness is the
            // caller's business, the cadence is ours.
            if (input.Held(InputButtons.Walk)) stride *= 0.75f;

            if (state.StrideDistance >= stride)
            {
                state.StrideDistance -= stride;
                state.SteppedThisTick = true;
            }
        }
    }
}
