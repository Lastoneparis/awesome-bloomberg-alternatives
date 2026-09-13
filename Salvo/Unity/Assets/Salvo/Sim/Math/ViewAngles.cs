using System;

namespace Salvo.Sim
{
    /// <summary>
    /// Where a player is looking, in radians. Pitch is clamped rather than wrapped: a
    /// player who looks past straight up should stop, not flip upside down.
    /// </summary>
    [Serializable]
    public struct ViewAngles
    {
        /// <summary>Just under 90 degrees. Exactly 90 makes the forward vector degenerate
        /// and the resulting yaw meaningless.</summary>
        public const float MaxPitch = 1.55334f;

        public float Pitch;
        public float Yaw;

        public ViewAngles(float pitch, float yaw)
        {
            Pitch = SalvoMath.Clamp(pitch, -MaxPitch, MaxPitch);
            Yaw = SalvoMath.WrapAngle(yaw);
        }

        public Vec3 Forward
        {
            get
            {
                float cosPitch = (float)System.Math.Cos(Pitch);
                return new Vec3(
                    (float)System.Math.Sin(Yaw) * cosPitch,
                    -(float)System.Math.Sin(Pitch),
                    (float)System.Math.Cos(Yaw) * cosPitch);
            }
        }

        /// <summary>Right in the horizontal plane — what strafing uses. Deriving it from
        /// <see cref="Forward"/> would tilt strafing when looking up or down.</summary>
        public Vec3 Right => new Vec3((float)System.Math.Cos(Yaw), 0f, -(float)System.Math.Sin(Yaw));

        /// <summary>Horizontal forward, for movement. Walking must not slow down because
        /// the player is looking at the sky.</summary>
        public Vec3 FlatForward => new Vec3((float)System.Math.Sin(Yaw), 0f, (float)System.Math.Cos(Yaw));

        public ViewAngles RotatedBy(float deltaPitch, float deltaYaw) =>
            new ViewAngles(Pitch + deltaPitch, Yaw + deltaYaw);

        /// <summary>Angles that look from one point towards another.</summary>
        public static ViewAngles LookingAt(Vec3 from, Vec3 target)
        {
            Vec3 delta = target - from;
            float yaw = (float)System.Math.Atan2(delta.X, delta.Z);
            float horizontal = delta.HorizontalLength;
            float pitch = horizontal < 1e-6f
                ? (delta.Y > 0f ? -MaxPitch : MaxPitch)
                : (float)System.Math.Atan2(-delta.Y, horizontal);
            return new ViewAngles(pitch, yaw);
        }

        public override string ToString() =>
            string.Format(System.Globalization.CultureInfo.InvariantCulture,
                          "pitch {0:0.00} yaw {1:0.00}", Pitch, Yaw);
    }
}
