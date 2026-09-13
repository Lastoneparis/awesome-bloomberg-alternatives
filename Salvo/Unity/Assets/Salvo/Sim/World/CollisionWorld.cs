using System.Collections.Generic;

namespace Salvo.Sim
{
    public struct TraceHit
    {
        public bool Hit;
        /// <summary>0–1 along the traced segment.</summary>
        public float Fraction;
        public Vec3 Point;
        public Vec3 Normal;
        public SurfaceKind Surface;
        public int BrushIndex;

        public static TraceHit Miss(Vec3 end) => new TraceHit
        {
            Hit = false, Fraction = 1f, Point = end, Normal = Vec3.Zero,
            Surface = SurfaceKind.Concrete, BrushIndex = -1
        };
    }

    /// <summary>What a trace is allowed to collide with.</summary>
    public enum TraceMask : byte
    {
        /// <summary>Everything solid, including invisible clip brushes. Player movement.</summary>
        Solid,
        /// <summary>Things that stop a bullet. Ignores clip brushes — you can shoot through
        /// an invisible wall, which is what makes it an invisible wall and not a real one.</summary>
        Bullets,
        /// <summary>Things that block line of sight. Ignores clip and glass.</summary>
        Sight
    }

    /// <summary>
    /// Static level geometry, and the queries the simulation runs against it.
    /// </summary>
    /// <remarks>
    /// A uniform grid over axis-aligned boxes. Not a BVH: level geometry here is brush-based
    /// and roughly uniform, the maps are tens of metres across, and a grid is simpler to get
    /// right. It is built once per map and shared across every match on that map — nothing
    /// mutates after construction, which is what makes sharing safe.
    /// </remarks>
    public sealed class CollisionWorld
    {
        private const float CellSize = 6f;

        private readonly MapBrush[] _brushes;
        private readonly List<int>[] _cells;
        private readonly Vec3 _gridMin;
        private readonly int _dimX, _dimY, _dimZ;

        public Aabb Bounds { get; }
        public int BrushCount => _brushes.Length;

        public CollisionWorld(MapDefinition map)
        {
            _brushes = map.Brushes.ToArray();
            Bounds = map.Bounds;
            _gridMin = map.Bounds.Min;

            Vec3 size = map.Bounds.Size;
            _dimX = System.Math.Max(1, (int)System.Math.Ceiling(size.X / CellSize));
            _dimY = System.Math.Max(1, (int)System.Math.Ceiling(size.Y / CellSize));
            _dimZ = System.Math.Max(1, (int)System.Math.Ceiling(size.Z / CellSize));

            _cells = new List<int>[_dimX * _dimY * _dimZ];
            for (int i = 0; i < _cells.Length; i++) _cells[i] = new List<int>();

            for (int i = 0; i < _brushes.Length; i++)
            {
                CellRange(_brushes[i].Box, out int x0, out int y0, out int z0,
                                            out int x1, out int y1, out int z1);
                for (int z = z0; z <= z1; z++)
                    for (int y = y0; y <= y1; y++)
                        for (int x = x0; x <= x1; x++)
                            _cells[CellIndex(x, y, z)].Add(i);
            }
        }

        private int CellIndex(int x, int y, int z) => (z * _dimY + y) * _dimX + x;

        private void CellRange(Aabb box, out int x0, out int y0, out int z0,
                                         out int x1, out int y1, out int z1)
        {
            Vec3 lo = box.Min - _gridMin;
            Vec3 hi = box.Max - _gridMin;
            x0 = SalvoMath.Clamp((int)(lo.X / CellSize), 0, _dimX - 1);
            y0 = SalvoMath.Clamp((int)(lo.Y / CellSize), 0, _dimY - 1);
            z0 = SalvoMath.Clamp((int)(lo.Z / CellSize), 0, _dimZ - 1);
            x1 = SalvoMath.Clamp((int)(hi.X / CellSize), 0, _dimX - 1);
            y1 = SalvoMath.Clamp((int)(hi.Y / CellSize), 0, _dimY - 1);
            z1 = SalvoMath.Clamp((int)(hi.Z / CellSize), 0, _dimZ - 1);
        }

        private static bool Accepts(in MapBrush brush, TraceMask mask) => mask switch
        {
            TraceMask.Solid => true,
            TraceMask.Bullets => !brush.IsClip && brush.BlocksBullets,
            TraceMask.Sight => !brush.IsClip && brush.BlocksSight,
            _ => true
        };

        /// <summary>Brush indices whose grid cells overlap a box. Duplicates removed.</summary>
        public void CandidatesInto(Aabb box, List<int> results, HashSet<int> scratch)
        {
            results.Clear();
            scratch.Clear();
            CellRange(box, out int x0, out int y0, out int z0, out int x1, out int y1, out int z1);
            for (int z = z0; z <= z1; z++)
                for (int y = y0; y <= y1; y++)
                    for (int x = x0; x <= x1; x++)
                    {
                        List<int> cell = _cells[CellIndex(x, y, z)];
                        for (int i = 0; i < cell.Count; i++)
                            if (scratch.Add(cell[i])) results.Add(cell[i]);
                    }
        }

        [System.ThreadStatic] private static List<int> _traceCandidates;
        [System.ThreadStatic] private static HashSet<int> _traceScratch;

        private static void EnsureScratch()
        {
            _traceCandidates ??= new List<int>(64);
            _traceScratch ??= new HashSet<int>();
        }

        /// <summary>A line trace against the level.</summary>
        public TraceHit Trace(Vec3 start, Vec3 end, TraceMask mask = TraceMask.Solid)
        {
            Vec3 delta = end - start;
            float distance = delta.Length;
            if (distance < 1e-5f) return TraceHit.Miss(end);
            Vec3 direction = delta / distance;

            EnsureScratch();
            var sweep = new Aabb(start, end).Expanded(new Vec3(0.05f, 0.05f, 0.05f));
            CandidatesInto(sweep, _traceCandidates, _traceScratch);

            TraceHit best = TraceHit.Miss(end);
            best.Fraction = 1f;

            for (int i = 0; i < _traceCandidates.Count; i++)
            {
                int index = _traceCandidates[i];
                if (!Accepts(_brushes[index], mask)) continue;
                if (!_brushes[index].Box.Raycast(start, direction, distance,
                                                 out float hitDistance, out Vec3 normal)) continue;

                float fraction = hitDistance / distance;
                if (fraction < best.Fraction)
                {
                    best = new TraceHit
                    {
                        Hit = true,
                        Fraction = fraction,
                        Point = start + direction * hitDistance,
                        Normal = normal,
                        Surface = _brushes[index].Surface,
                        BrushIndex = index
                    };
                }
            }
            return best;
        }

        [System.ThreadStatic] private static List<int> _sweepCandidates;
        [System.ThreadStatic] private static HashSet<int> _sweepScratch;

        /// <summary>
        /// Sweeps an axis-aligned box from one centre to another and reports the first
        /// blocking contact.
        /// </summary>
        /// <remarks>
        /// This is a Minkowski sweep: expanding each brush by the box's half extents turns
        /// box-versus-box into ray-versus-box, so the same slab test that serves bullets
        /// serves the player capsule. It has its own scratch buffers rather than sharing
        /// <see cref="Trace"/>'s, because movement code legitimately calls both and a shared
        /// buffer would be cleared underneath the caller.
        ///
        /// If the box starts already overlapping a brush the slab test reports a zero-distance
        /// hit with no meaningful normal. That is reported as <c>startedSolid</c> rather than
        /// silently treated as a wall, because the two need opposite responses: a wall is slid
        /// along, a penetration must be pushed out of first.
        /// </remarks>
        public TraceHit SweepBox(Vec3 centre, Vec3 halfExtents, Vec3 target,
                                 out bool startedSolid, TraceMask mask = TraceMask.Solid)
        {
            startedSolid = false;
            Vec3 delta = target - centre;
            float distance = delta.Length;
            var miss = TraceHit.Miss(target);
            miss.Fraction = 1f;
            if (distance < 1e-6f) return miss;
            Vec3 direction = delta / distance;

            _sweepCandidates ??= new List<int>(64);
            _sweepScratch ??= new HashSet<int>();

            var region = new Aabb(centre - halfExtents, centre + halfExtents);
            region = new Aabb(Vec3.Min(region.Min, target - halfExtents),
                              Vec3.Max(region.Max, target + halfExtents));
            CandidatesInto(region, _sweepCandidates, _sweepScratch);

            TraceHit best = miss;
            for (int i = 0; i < _sweepCandidates.Count; i++)
            {
                int index = _sweepCandidates[i];
                if (!Accepts(_brushes[index], mask)) continue;

                Aabb expanded = _brushes[index].Box.Expanded(halfExtents);
                if (!expanded.Raycast(centre, direction, distance,
                                      out float hitDistance, out Vec3 normal)) continue;

                // A zero normal means the slab test never crossed a face on the way in. Two
                // very different situations produce that, and they need opposite responses:
                // the box genuinely started inside the brush (push out), or it started exactly
                // on a face and is leaving (ignore — it is grazing, not colliding). Asking the
                // geometry directly is the only way to tell them apart.
                if (normal == Vec3.Zero)
                {
                    if (StrictlyInside(expanded, centre)) startedSolid = true;
                    continue;
                }

                float fraction = hitDistance / distance;
                if (fraction < best.Fraction)
                {
                    best = new TraceHit
                    {
                        Hit = true,
                        Fraction = SalvoMath.Clamp01(fraction),
                        Point = centre + direction * hitDistance,
                        Normal = normal,
                        Surface = _brushes[index].Surface,
                        BrushIndex = index
                    };
                }
            }
            return best;
        }

        public bool HasLineOfSight(Vec3 from, Vec3 to) => !Trace(from, to, TraceMask.Sight).Hit;

        public bool Overlaps(Aabb box, TraceMask mask = TraceMask.Solid)
        {
            EnsureScratch();
            CandidatesInto(box, _traceCandidates, _traceScratch);
            for (int i = 0; i < _traceCandidates.Count; i++)
            {
                int index = _traceCandidates[i];
                if (!Accepts(_brushes[index], mask)) continue;
                if (_brushes[index].Box.Intersects(box)) return true;
            }
            return false;
        }

        /// <summary>
        /// True when <paramref name="point"/> is inside <paramref name="box"/> by more than a
        /// hair on every axis. Merely touching a face does not count.
        /// </summary>
        private static bool StrictlyInside(Aabb box, Vec3 point)
        {
            const float epsilon = 1e-4f;
            return point.X > box.Min.X + epsilon && point.X < box.Max.X - epsilon
                && point.Y > box.Min.Y + epsilon && point.Y < box.Max.Y - epsilon
                && point.Z > box.Min.Z + epsilon && point.Z < box.Max.Z - epsilon;
        }

        /// <summary>
        /// Pushes a box out of any geometry it is overlapping and returns the corrected centre.
        /// </summary>
        /// <remarks>
        /// The safety net under the movement model, and it earns its place. Sweeping alone is
        /// not enough in practice: floating-point error at a wall/floor seam, a stance change
        /// that grows the box into a ceiling, or a spawn placed a millimetre inside a brush all
        /// leave the player slightly embedded. Without a push-out, the next sweep starts solid,
        /// the model has nothing sensible to do, and the player falls through the level — which
        /// is precisely the class of bug that only ever gets found by a player mid-match.
        ///
        /// <para>Resolution is along the axis of least penetration, deepest overlap first, a
        /// few times over. Least-penetration is what makes a player embedded in a floor pop up
        /// rather than sideways. The iteration count is small and fixed because this must cost
        /// the same every tick: an unbounded loop here would be a stutter under exactly the
        /// conditions that cause it.</para>
        /// </remarks>
        public Vec3 Depenetrate(Vec3 centre, Vec3 halfExtents, TraceMask mask = TraceMask.Solid,
                                int iterations = 4)
        {
            _sweepCandidates ??= new List<int>(64);
            _sweepScratch ??= new HashSet<int>();

            for (int pass = 0; pass < iterations; pass++)
            {
                var box = new Aabb(centre - halfExtents, centre + halfExtents);
                CandidatesInto(box, _sweepCandidates, _sweepScratch);

                float deepest = 0f;
                Vec3 push = Vec3.Zero;

                for (int i = 0; i < _sweepCandidates.Count; i++)
                {
                    int index = _sweepCandidates[i];
                    if (!Accepts(_brushes[index], mask)) continue;
                    Aabb brush = _brushes[index].Box;
                    if (!brush.Intersects(box)) continue;

                    // Overlap on each axis; the smallest is the cheapest way out.
                    float ox = System.Math.Min(box.Max.X, brush.Max.X) - System.Math.Max(box.Min.X, brush.Min.X);
                    float oy = System.Math.Min(box.Max.Y, brush.Max.Y) - System.Math.Max(box.Min.Y, brush.Min.Y);
                    float oz = System.Math.Min(box.Max.Z, brush.Max.Z) - System.Math.Max(box.Min.Z, brush.Min.Z);
                    if (ox <= 0f || oy <= 0f || oz <= 0f) continue;

                    float overlap;
                    Vec3 direction;
                    if (oy <= ox && oy <= oz)
                    {
                        overlap = oy;
                        direction = centre.Y >= brush.Centre.Y ? Vec3.Up : -Vec3.Up;
                    }
                    else if (ox <= oz)
                    {
                        overlap = ox;
                        direction = centre.X >= brush.Centre.X ? Vec3.Right : -Vec3.Right;
                    }
                    else
                    {
                        overlap = oz;
                        direction = centre.Z >= brush.Centre.Z ? Vec3.Forward : -Vec3.Forward;
                    }

                    if (overlap > deepest)
                    {
                        deepest = overlap;
                        push = direction * overlap;
                    }
                }

                if (deepest <= 0f) break;
                // A sliver beyond the overlap, so the result is clear of the brush rather than
                // exactly touching it — exactly touching is what caused this in the first place.
                centre += push + push.Normalized * 1e-3f;
            }
            return centre;
        }

        /// <summary>Height of the floor below a point, or null if there is nothing under it
        /// within <paramref name="maxDrop"/>.</summary>
        public float? GroundHeight(Vec3 point, float maxDrop = 30f)
        {
            TraceHit hit = Trace(point, point + new Vec3(0f, -maxDrop, 0f), TraceMask.Solid);
            return hit.Hit ? hit.Point.Y : (float?)null;
        }

        public SurfaceKind SurfaceBelow(Vec3 point, float maxDrop = 3f)
        {
            TraceHit hit = Trace(point, point + new Vec3(0f, -maxDrop, 0f), TraceMask.Solid);
            return hit.Hit ? hit.Surface : SurfaceKind.Concrete;
        }
    }
}
