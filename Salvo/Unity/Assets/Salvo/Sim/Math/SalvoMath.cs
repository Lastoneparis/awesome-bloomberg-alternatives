using System;

namespace Salvo.Sim
{
    /// <summary>Small maths helpers the simulation needs and netstandard does not provide.</summary>
    public static class SalvoMath
    {
        public const float Pi = 3.14159265f;
        public const float TwoPi = 6.28318531f;
        public const float DegToRad = Pi / 180f;
        public const float RadToDeg = 180f / Pi;

        public static float Clamp(float value, float min, float max) =>
            value < min ? min : (value > max ? max : value);

        public static float Clamp01(float value) => Clamp(value, 0f, 1f);

        public static int Clamp(int value, int min, int max) =>
            value < min ? min : (value > max ? max : value);

        public static float Lerp(float a, float b, float t) => a + (b - a) * Clamp01(t);

        public static float InverseLerp(float a, float b, float value) =>
            System.Math.Abs(b - a) < 1e-9f ? 0f : Clamp01((value - a) / (b - a));

        /// <summary>
        /// Frame-rate independent smoothing. Lerping by a constant per frame makes the
        /// result depend on frame rate, which means aim assist and view smoothing behave
        /// differently at 30 and 120 fps. This does not.
        /// </summary>
        public static float Damp(float current, float target, float halfLife, float deltaTime)
        {
            if (halfLife <= 0f) return target;
            float factor = 1f - (float)System.Math.Pow(2.0, -deltaTime / halfLife);
            return current + (target - current) * factor;
        }

        public static Vec3 Damp(Vec3 current, Vec3 target, float halfLife, float deltaTime)
        {
            if (halfLife <= 0f) return target;
            float factor = 1f - (float)System.Math.Pow(2.0, -deltaTime / halfLife);
            return current + (target - current) * factor;
        }

        /// <summary>
        /// Wraps an angle into roughly (-pi, pi]. "Roughly" is deliberate: which side of
        /// the boundary a value lands on after a float remainder is a one-ulp question, so
        /// callers must compare angles with <see cref="AngleDelta"/> rather than by value.
        /// </summary>
        public static float WrapAngle(float radians)
        {
            float wrapped = radians % TwoPi;
            if (wrapped > Pi) wrapped -= TwoPi;
            if (wrapped <= -Pi) wrapped += TwoPi;
            return wrapped;
        }

        /// <summary>Shortest signed rotation from one angle to another.</summary>
        public static float AngleDelta(float from, float to) => WrapAngle(to - from);

        public static float MoveTowards(float current, float target, float maxDelta)
        {
            float difference = target - current;
            if (System.Math.Abs(difference) <= maxDelta) return target;
            return current + System.Math.Sign(difference) * maxDelta;
        }
    }
}
