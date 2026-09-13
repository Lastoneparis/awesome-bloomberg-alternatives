using System;

namespace Salvo.Sim
{
    /// <summary>
    /// Drives the simulation at a fixed rate regardless of how fast frames are arriving.
    /// </summary>
    /// <remarks>
    /// A fixed tick is not a style choice for a competitive shooter: movement, recoil and
    /// hit registration all have to produce the same result on the server and on a client
    /// predicting ahead of it, and they cannot if the step size is whatever the last frame
    /// happened to take.
    ///
    /// The catch-up is clamped. After a stall — an app resumed from the background, a
    /// garbage collection spike — the accumulator can hold seconds of unsimulated time, and
    /// running all of it produces a burst of ticks that is slower than the stall was. That
    /// is the classic spiral of death. Dropping the excess is visible as a small jump and
    /// is far better than never catching up.
    /// </remarks>
    public sealed class FixedClock
    {
        public const int TicksPerSecond = 64;
        public const float TickInterval = 1f / TicksPerSecond;
        public const int MaxCatchUpTicks = 8;

        private float _accumulator;

        public int Tick { get; private set; }
        public float Time => Tick * TickInterval;

        /// <summary>Fraction of the way into the next tick, for interpolating presentation
        /// between simulated states.</summary>
        public float Alpha => _accumulator / TickInterval;

        /// <summary>Number of whole ticks that were dropped to avoid a death spiral. Not
        /// cosmetic: a server reporting a non-zero value here is overloaded.</summary>
        public int DroppedTicks { get; private set; }

        public void Reset()
        {
            _accumulator = 0f;
            Tick = 0;
            DroppedTicks = 0;
        }

        /// <summary>
        /// Advances by real elapsed time and invokes <paramref name="step"/> once per whole
        /// tick that is due.
        /// </summary>
        public int Advance(float deltaTime, Action<int, float> step)
        {
            if (deltaTime > 0f) _accumulator += deltaTime;

            int stepped = 0;
            while (_accumulator >= TickInterval && stepped < MaxCatchUpTicks)
            {
                _accumulator -= TickInterval;
                Tick++;
                stepped++;
                step?.Invoke(Tick, TickInterval);
            }

            if (_accumulator >= TickInterval)
            {
                int dropped = (int)(_accumulator / TickInterval);
                DroppedTicks += dropped;
                _accumulator -= dropped * TickInterval;
            }

            return stepped;
        }
    }

    /// <summary>A one-shot countdown. Named <c>Countdown</c> rather than <c>Timer</c>
    /// because <c>Timer</c> collides with types in both System and UnityEngine, and a
    /// simulation type that cannot be named without qualification in half the codebase is a
    /// permanent tax.</summary>
    [Serializable]
    public struct Countdown
    {
        public float Remaining;
        public float Duration;

        public bool IsRunning => Remaining > 0f;
        public bool IsFinished => Remaining <= 0f;

        public float Progress => Duration > 0f
            ? 1f - SalvoMath.Clamp01(Remaining / Duration)
            : 1f;

        public void Start(float seconds)
        {
            Duration = seconds;
            Remaining = seconds;
        }

        public void Stop() { Remaining = 0f; }

        /// <summary>Returns true on the tick the countdown completes, and only that tick,
        /// so callers can fire an event without tracking edges themselves.</summary>
        public bool Tick(float deltaTime)
        {
            if (Remaining <= 0f) return false;
            Remaining -= deltaTime;
            if (Remaining <= 0f)
            {
                Remaining = 0f;
                return true;
            }
            return false;
        }
    }
}
