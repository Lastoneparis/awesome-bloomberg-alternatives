using System;
using System.Collections.Generic;

namespace Salvo.Sim
{
    /// <summary>What a surface is made of. Drives footstep and impact audio, and how much
    /// of a bullet a wall eats.</summary>
    public enum SurfaceKind : byte
    {
        Concrete, Metal, Wood, Dirt, Sand, Grass, Water, Glass, Fabric, Snow, Tile, Flesh
    }

    /// <summary>An axis-aligned box of solid world.</summary>
    [Serializable]
    public struct Aabb
    {
        public Vec3 Min;
        public Vec3 Max;

        /// <summary>Orders the corners, so <see cref="Min"/> really is the minimum on every
        /// axis. Everything downstream indexes a grid from Min to Max as a range, and an
        /// inverted box is not a harmless oddity — it is a crash. Cheap here, once, at
        /// authoring time; impossible to forget.</summary>
        public Aabb(Vec3 a, Vec3 b)
        {
            Min = new Vec3(System.Math.Min(a.X, b.X), System.Math.Min(a.Y, b.Y), System.Math.Min(a.Z, b.Z));
            Max = new Vec3(System.Math.Max(a.X, b.X), System.Math.Max(a.Y, b.Y), System.Math.Max(a.Z, b.Z));
        }

        public static Aabb FromCentre(Vec3 centre, Vec3 size)
        {
            Vec3 half = size * 0.5f;
            return new Aabb(centre - half, centre + half);
        }

        public Vec3 Centre => (Min + Max) * 0.5f;
        public Vec3 Size => Max - Min;

        public bool Contains(Vec3 point) =>
            point.X >= Min.X && point.X <= Max.X &&
            point.Y >= Min.Y && point.Y <= Max.Y &&
            point.Z >= Min.Z && point.Z <= Max.Z;

        /// <summary>
        /// True when the two boxes share actual volume.
        /// </summary>
        /// <remarks>
        /// Strict comparisons, so boxes that merely share a face do not intersect. That is the
        /// physically meaningful answer — the shared volume is zero — and it is the one the
        /// callers need: the overlap test is what decides "is this body embedded in the level",
        /// and a player standing on a floor touches it by definition. With inclusive
        /// comparisons every spawn point on the ground reads as buried in the ground, and no
        /// crouched player can ever stand up.
        /// </remarks>
        public bool Intersects(Aabb other) =>
            Min.X < other.Max.X && Max.X > other.Min.X &&
            Min.Y < other.Max.Y && Max.Y > other.Min.Y &&
            Min.Z < other.Max.Z && Max.Z > other.Min.Z;

        public Aabb Expanded(Vec3 amount) => new Aabb(Min - amount, Max + amount);

        public Vec3 ClosestPoint(Vec3 point) => new Vec3(
            SalvoMath.Clamp(point.X, Min.X, Max.X),
            SalvoMath.Clamp(point.Y, Min.Y, Max.Y),
            SalvoMath.Clamp(point.Z, Min.Z, Max.Z));

        /// <summary>Slab test. Returns the entry distance along the ray and the surface
        /// normal, or false if the ray misses within <paramref name="maxDistance"/>.</summary>
        public bool Raycast(Vec3 origin, Vec3 direction, float maxDistance,
                            out float distance, out Vec3 normal)
        {
            distance = 0f;
            normal = Vec3.Zero;
            float near = 0f;
            float far = maxDistance;
            Vec3 hitNormal = Vec3.Zero;

            for (int axis = 0; axis < 3; axis++)
            {
                float o = axis == 0 ? origin.X : axis == 1 ? origin.Y : origin.Z;
                float d = axis == 0 ? direction.X : axis == 1 ? direction.Y : direction.Z;
                float lo = axis == 0 ? Min.X : axis == 1 ? Min.Y : Min.Z;
                float hi = axis == 0 ? Max.X : axis == 1 ? Max.Y : Max.Z;

                if (System.Math.Abs(d) < 1e-6f)
                {
                    if (o < lo || o > hi) return false;   // parallel and outside
                    continue;
                }

                float inverse = 1f / d;
                float t1 = (lo - o) * inverse;
                float t2 = (hi - o) * inverse;
                float sign = -1f;
                if (t1 > t2) { float swap = t1; t1 = t2; t2 = swap; sign = 1f; }

                // >= rather than >: a ray that starts exactly on a face has t1 == 0 == near
                // on that axis, and with a strict comparison it would keep the zero normal it
                // started with. That is not a corner case here — it is a player standing on a
                // floor, which is the single most common query the movement code makes.
                if (t1 >= near)
                {
                    near = t1;
                    hitNormal = axis == 0 ? new Vec3(sign, 0f, 0f)
                              : axis == 1 ? new Vec3(0f, sign, 0f)
                                          : new Vec3(0f, 0f, sign);
                }
                if (t2 < far) far = t2;
                if (near > far) return false;
            }

            distance = near;
            normal = hitNormal;
            return true;
        }
    }

    /// <summary>One solid box of level geometry.</summary>
    [Serializable]
    public struct MapBrush
    {
        public Aabb Box;
        public SurfaceKind Surface;
        /// <summary>Clip brushes block players but not bullets or sight — invisible walls.</summary>
        public bool IsClip;
        public bool BlocksSight;
        public bool BlocksBullets;

        public MapBrush(Aabb box, SurfaceKind surface = SurfaceKind.Concrete,
                        bool isClip = false, bool blocksSight = true, bool blocksBullets = true)
        {
            Box = box;
            Surface = surface;
            IsClip = isClip;
            BlocksSight = blocksSight;
            BlocksBullets = blocksBullets;
        }
    }

    [Serializable]
    public struct SpawnPoint
    {
        public Vec3 Position;
        public float Yaw;
        public Team Team;
        /// <summary>Higher is preferred when several spawns are equally safe.</summary>
        public int Priority;

        public SpawnPoint(Vec3 position, float yawDegrees, Team team = Team.None, int priority = 0)
        {
            Position = position;
            Yaw = yawDegrees * SalvoMath.DegToRad;
            Team = team;
            Priority = priority;
        }
    }

    /// <summary>A named objective volume — a bomb site, a capture point, a hardpoint. The
    /// mode decides what it means; the map only says where it is.</summary>
    [Serializable]
    public struct ObjectiveZone
    {
        public int Index;
        public string NameKey;
        public Aabb Volume;

        public ObjectiveZone(int index, string nameKey, Aabb volume)
        {
            Index = index;
            NameKey = nameKey;
            Volume = volume;
        }

        public Vec3 Centre => Volume.Centre;
        public bool Contains(Vec3 point) => Volume.Contains(point);
    }

    /// <summary>
    /// A map: geometry, spawns, objectives and the modes it supports. No behaviour.
    /// </summary>
    [Serializable]
    public class MapDefinition
    {
        public ContentId Id;
        public string DisplayNameKey = "";
        public ContentId WorldId;

        public Aabb Bounds = new Aabb(new Vec3(-64f, -8f, -64f), new Vec3(64f, 32f, 64f));
        public List<MapBrush> Brushes = new List<MapBrush>();
        public List<SpawnPoint> Spawns = new List<SpawnPoint>();
        public List<ObjectiveZone> Objectives = new List<ObjectiveZone>();

        public GameModeKind[] SupportedModes = { GameModeKind.TeamDeathmatch };
        public int RecommendedMinPlayers = 4;
        public int RecommendedMaxPlayers = 10;

        public IEnumerable<SpawnPoint> SpawnsFor(Team team)
        {
            foreach (SpawnPoint spawn in Spawns)
                if (spawn.Team == team || spawn.Team == Team.None)
                    yield return spawn;
        }

        public void Validate(List<string> problems)
        {
            if (Id.IsEmpty) problems.Add("map has no Id");
            string name = Id.ToString();
            if (Brushes.Count == 0) problems.Add($"{name}: no geometry");
            if (Spawns.Count == 0) problems.Add($"{name}: no spawn points");
            if (string.IsNullOrEmpty(DisplayNameKey)) problems.Add($"{name}: DisplayNameKey is empty");

            for (int i = 0; i < Brushes.Count; i++)
            {
                Aabb box = Brushes[i].Box;
                if (box.Min.X > box.Max.X || box.Min.Y > box.Max.Y || box.Min.Z > box.Max.Z)
                    problems.Add($"{name}: brush {i} is inverted");
                if (float.IsNaN(box.Min.X) || float.IsNaN(box.Max.X))
                    problems.Add($"{name}: brush {i} has a non-finite corner");
            }

            foreach (SpawnPoint spawn in Spawns)
                if (!Bounds.Contains(spawn.Position))
                    problems.Add($"{name}: spawn at {spawn.Position} is outside the map bounds");
        }
    }
}
