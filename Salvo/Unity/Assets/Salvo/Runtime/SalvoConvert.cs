using UnityEngine;
using Salvo.Sim;

namespace Salvo.Runtime
{
    /// <summary>
    /// The border crossing between the simulation's types and Unity's.
    /// </summary>
    /// <remarks>
    /// Every conversion between <see cref="Vec3"/> and <see cref="Vector3"/> goes through here
    /// and nowhere else. That sounds like ceremony over a struct with three floats, and it is
    /// not: it is the one place where a coordinate convention can be stated once and checked.
    /// The simulation uses Unity's convention already — Y up, Z forward, left-handed — so these
    /// are straight copies, and if that ever stops being true this file is the only thing that
    /// has to change.
    /// </remarks>
    public static class SalvoConvert
    {
        public static Vector3 ToUnity(this Vec3 v) => new Vector3(v.X, v.Y, v.Z);

        public static Vec3 ToSim(this Vector3 v) => new Vec3(v.x, v.y, v.z);

        /// <summary>
        /// Turns the simulation's view angles into a Unity rotation.
        /// </summary>
        /// <remarks>
        /// Note the sign on pitch. The simulation measures pitch as positive-up, the way a
        /// person would describe it; Unity's Euler angles measure X rotation as positive-down.
        /// Getting this backwards produces inverted look, which every player notices instantly
        /// and which is very easy to "fix" in the wrong place by inverting the input instead.
        /// </remarks>
        public static Quaternion ToUnity(this ViewAngles view) =>
            Quaternion.Euler(-view.Pitch * SalvoMath.RadToDeg,
                             view.Yaw * SalvoMath.RadToDeg, 0f);

        public static Bounds ToUnity(this Aabb box) =>
            new Bounds(box.Centre.ToUnity(), box.Size.ToUnity());

        public static Color ToUnity(this uint rgb) => new Color(
            ((rgb >> 16) & 0xFF) / 255f,
            ((rgb >> 8) & 0xFF) / 255f,
            (rgb & 0xFF) / 255f);
    }
}
