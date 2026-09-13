using System;

namespace Salvo.Sim
{
    /// <summary>
    /// A 3D vector. Deliberately not <c>UnityEngine.Vector3</c>: the simulation has to
    /// compile and run on a dedicated server that has no engine in it. Layout and
    /// semantics match Unity's (left-handed, Y up) so conversion at the boundary is a
    /// field copy and nothing in the presentation layer has to think about it.
    /// </summary>
    [Serializable]
    public struct Vec3 : IEquatable<Vec3>
    {
        public float X;
        public float Y;
        public float Z;

        public Vec3(float x, float y, float z) { X = x; Y = y; Z = z; }

        public static readonly Vec3 Zero = new Vec3(0f, 0f, 0f);
        public static readonly Vec3 One = new Vec3(1f, 1f, 1f);
        public static readonly Vec3 Up = new Vec3(0f, 1f, 0f);
        public static readonly Vec3 Forward = new Vec3(0f, 0f, 1f);
        public static readonly Vec3 Right = new Vec3(1f, 0f, 0f);

        public static Vec3 operator +(Vec3 a, Vec3 b) => new Vec3(a.X + b.X, a.Y + b.Y, a.Z + b.Z);
        public static Vec3 operator -(Vec3 a, Vec3 b) => new Vec3(a.X - b.X, a.Y - b.Y, a.Z - b.Z);
        public static Vec3 operator -(Vec3 a) => new Vec3(-a.X, -a.Y, -a.Z);
        public static Vec3 operator *(Vec3 a, float s) => new Vec3(a.X * s, a.Y * s, a.Z * s);
        public static Vec3 operator *(float s, Vec3 a) => a * s;
        public static Vec3 operator /(Vec3 a, float s) => a * (1f / s);

        public float LengthSquared => X * X + Y * Y + Z * Z;
        public float Length => (float)System.Math.Sqrt(LengthSquared);

        /// <summary>Horizontal length. Movement speed caps ignore vertical velocity, or
        /// falling would count as running.</summary>
        public float HorizontalLength => (float)System.Math.Sqrt(X * X + Z * Z);

        public Vec3 WithY(float y) => new Vec3(X, y, Z);
        public Vec3 Flattened => new Vec3(X, 0f, Z);

        /// <summary>Unit vector, or zero for a zero vector — never NaN. Normalising a zero
        /// vector is a real case here (a player standing still) and a NaN that reaches the
        /// physics step poisons a player's position permanently.</summary>
        public Vec3 Normalized
        {
            get
            {
                float lengthSquared = LengthSquared;
                if (lengthSquared < 1e-12f) return Zero;
                float inverse = 1f / (float)System.Math.Sqrt(lengthSquared);
                return new Vec3(X * inverse, Y * inverse, Z * inverse);
            }
        }

        public static float Dot(Vec3 a, Vec3 b) => a.X * b.X + a.Y * b.Y + a.Z * b.Z;

        public static Vec3 Cross(Vec3 a, Vec3 b) => new Vec3(
            a.Y * b.Z - a.Z * b.Y,
            a.Z * b.X - a.X * b.Z,
            a.X * b.Y - a.Y * b.X);

        public static Vec3 Min(Vec3 a, Vec3 b) => new Vec3(
            a.X < b.X ? a.X : b.X,
            a.Y < b.Y ? a.Y : b.Y,
            a.Z < b.Z ? a.Z : b.Z);

        public static Vec3 Max(Vec3 a, Vec3 b) => new Vec3(
            a.X > b.X ? a.X : b.X,
            a.Y > b.Y ? a.Y : b.Y,
            a.Z > b.Z ? a.Z : b.Z);

        public static float Distance(Vec3 a, Vec3 b) => (a - b).Length;
        public static float DistanceSquared(Vec3 a, Vec3 b) => (a - b).LengthSquared;

        public static Vec3 Lerp(Vec3 a, Vec3 b, float t) => a + (b - a) * SalvoMath.Clamp01(t);

        /// <summary>Removes the component heading into a surface, so a player sliding along
        /// a wall keeps the speed that is parallel to it instead of stopping dead.</summary>
        public Vec3 ClippedAgainst(Vec3 normal, float bounce = 1.0f)
        {
            float into = Dot(this, normal);
            if (into > 0f) return this;
            return this - normal * (into * bounce);
        }

        public bool Equals(Vec3 other) => X.Equals(other.X) && Y.Equals(other.Y) && Z.Equals(other.Z);
        public override bool Equals(object obj) => obj is Vec3 other && Equals(other);

        public override int GetHashCode()
        {
            unchecked { return (X.GetHashCode() * 397) ^ (Y.GetHashCode() * 31) ^ Z.GetHashCode(); }
        }

        public static bool operator ==(Vec3 a, Vec3 b) => a.Equals(b);
        public static bool operator !=(Vec3 a, Vec3 b) => !a.Equals(b);

        public override string ToString() =>
            string.Format(System.Globalization.CultureInfo.InvariantCulture,
                          "({0:0.00}, {1:0.00}, {2:0.00})", X, Y, Z);
    }
}
