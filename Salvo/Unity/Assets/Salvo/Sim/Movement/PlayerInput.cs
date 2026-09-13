using System;

namespace Salvo.Sim
{
    /// <summary>
    /// The buttons a player can hold on a given tick.
    /// </summary>
    /// <remarks>
    /// A bitfield rather than a struct of bools because this crosses the wire 64 times a
    /// second per player: one byte instead of nine.
    /// </remarks>
    [Flags]
    public enum InputButtons : ushort
    {
        None = 0,
        Fire = 1 << 0,
        Aim = 1 << 1,
        Jump = 1 << 2,
        Crouch = 1 << 3,
        Walk = 1 << 4,      // deliberately quiet, slower movement
        Reload = 1 << 5,
        Use = 1 << 6,
        NextWeapon = 1 << 7,
        PrevWeapon = 1 << 8,
        Melee = 1 << 9,
        Grenade = 1 << 10,
    }

    /// <summary>
    /// One tick's worth of intent from one player. This is the <em>only</em> thing a client
    /// is allowed to tell the server about its own player (§13: never trust the client for
    /// movement validation). The server runs the same movement code on this input and the
    /// result it computes is authoritative; the client's own prediction is a guess that gets
    /// corrected.
    /// </summary>
    /// <remarks>
    /// Every field is quantised, and that is not an optimisation — it is a correctness
    /// requirement. Client and server must run the simulation on <em>bit-identical</em>
    /// inputs or prediction and reconciliation disagree on every single tick and the player
    /// rubber-bands forever. So the wire format is the source of truth: the client quantises
    /// its raw input, predicts using the quantised value, and sends that same value.
    /// <see cref="Quantised"/> does exactly that and is the only way a command should be
    /// constructed from analogue input.
    /// </remarks>
    public struct PlayerInput
    {
        /// <summary>Simulation tick this command applies to. Used for reconciliation.</summary>
        public int Tick;

        /// <summary>Strafe axis, -1 (left) to +1 (right), quantised to 1/127.</summary>
        public sbyte MoveRight;

        /// <summary>Forward axis, -1 (back) to +1 (forward), quantised to 1/127.</summary>
        public sbyte MoveForward;

        /// <summary>
        /// Absolute view direction, not a delta. Absolute because a dropped command must not
        /// permanently rotate the player: with deltas, a lost packet is a lost aim.
        /// </summary>
        public ViewAngles View;

        public InputButtons Buttons;

        /// <summary>Weapon slot the player wants held, for direct selection.</summary>
        public byte DesiredSlot;

        public bool Held(InputButtons button) => (Buttons & button) != 0;

        public float MoveRightAxis => MoveRight / 127f;
        public float MoveForwardAxis => MoveForward / 127f;

        /// <summary>
        /// True when the player is asking to move at all. Checked against the quantised value
        /// so that a stick resting at 1/300 counts as still on both machines.
        /// </summary>
        public bool HasMoveIntent => MoveRight != 0 || MoveForward != 0;

        /// <summary>
        /// Builds a command from raw analogue input, quantising it exactly as the wire will.
        /// Predict with the value this returns, never with the raw floats.
        /// </summary>
        public static PlayerInput Quantised(int tick, float right, float forward,
                                            ViewAngles view, InputButtons buttons,
                                            byte desiredSlot = 0)
        {
            // A stick can report a magnitude above 1 on the diagonal; clamping the pair
            // rather than each axis keeps diagonal movement from being faster than straight.
            float magnitude = (float)System.Math.Sqrt(right * right + forward * forward);
            if (magnitude > 1f)
            {
                right /= magnitude;
                forward /= magnitude;
            }

            return new PlayerInput
            {
                Tick = tick,
                MoveRight = QuantiseAxis(right),
                MoveForward = QuantiseAxis(forward),
                // Angles are quantised too: a float that differs in its last bit between
                // client and server drifts the two simulations apart over a long spray.
                View = new ViewAngles(QuantiseAngle(view.Pitch), QuantiseAngle(view.Yaw)),
                Buttons = buttons,
                DesiredSlot = desiredSlot,
            };
        }

        private static sbyte QuantiseAxis(float value) =>
            (sbyte)SalvoMath.Clamp((int)System.Math.Round(value * 127f), -127, 127);

        /// <summary>
        /// Rounds an angle to 1/65536 of a turn — about 0.0055°, far finer than any player
        /// can aim, and exactly representable so both machines round to the same float.
        /// </summary>
        public static float QuantiseAngle(float radians)
        {
            const float steps = 65536f / SalvoMath.TwoPi;
            return (float)System.Math.Round(radians * steps) / steps;
        }

        public override string ToString() =>
            $"t{Tick} move({MoveRight},{MoveForward}) {View} [{Buttons}]";
    }
}
