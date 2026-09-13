using System.Collections.Generic;
using UnityEngine;
using Salvo.Sim;

namespace Salvo.Runtime
{
    /// <summary>
    /// Builds the visible geometry for a <see cref="MapDefinition"/>.
    /// </summary>
    /// <remarks>
    /// The map's brushes are the collision <em>and</em> the visuals, for now. That keeps the two
    /// from disagreeing — the commonest and most infuriating bug in a shooter is a wall you can
    /// see through but not shoot through, or the reverse — and it means a map can be authored
    /// as data and played immediately.
    ///
    /// <para>Brushes are merged into one mesh per surface kind rather than one object per brush.
    /// A few hundred separate renderers would blow the draw-call budget in PROJECT_PLAN.md on a
    /// phone before a single player was drawn. Clip brushes are skipped: they exist to block
    /// movement without being visible, which is the entire point of them.</para>
    /// </remarks>
    public static class MapGeometryBuilder
    {
        /// <summary>
        /// Creates a child object per surface kind, each holding one merged mesh.
        /// </summary>
        /// <param name="materials">
        /// One material per <see cref="SurfaceKind"/>, indexed by its numeric value. A missing
        /// entry falls back to the first, so an unfinished material set renders rather than
        /// throwing.
        /// </param>
        public static GameObject Build(MapDefinition map, Material[] materials, Transform parent)
        {
            var root = new GameObject($"Map:{map.Id}");
            if (parent != null) root.transform.SetParent(parent, worldPositionStays: false);

            var bySurface = new Dictionary<SurfaceKind, List<Aabb>>();
            foreach (MapBrush brush in map.Brushes)
            {
                if (brush.IsClip) continue;
                if (!bySurface.TryGetValue(brush.Surface, out List<Aabb> list))
                {
                    list = new List<Aabb>();
                    bySurface[brush.Surface] = list;
                }
                list.Add(brush.Box);
            }

            foreach (KeyValuePair<SurfaceKind, List<Aabb>> entry in bySurface)
            {
                var child = new GameObject(entry.Key.ToString());
                child.transform.SetParent(root.transform, worldPositionStays: false);

                MeshFilter filter = child.AddComponent<MeshFilter>();
                filter.sharedMesh = BuildMesh(entry.Value, entry.Key.ToString());

                MeshRenderer renderer = child.AddComponent<MeshRenderer>();
                renderer.sharedMaterial = MaterialFor(materials, entry.Key);
                // Level geometry never moves, so tell the lightmapper and the culler that.
                renderer.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.On;
            }
            return root;
        }

        private static Material MaterialFor(Material[] materials, SurfaceKind surface)
        {
            if (materials == null || materials.Length == 0) return null;
            int index = (int)surface;
            return index >= 0 && index < materials.Length && materials[index] != null
                ? materials[index] : materials[0];
        }

        /// <summary>
        /// Merges boxes into one mesh.
        /// </summary>
        /// <remarks>
        /// Every face is emitted, including ones buried inside a neighbouring box. Culling
        /// hidden faces would be a real saving and is deliberately not done yet: it is only
        /// correct when two boxes share a face exactly, and getting the epsilon wrong leaves
        /// visible holes in the level. It belongs in the same phase as the rest of the map
        /// pipeline, with a test that renders and compares.
        /// </remarks>
        public static Mesh BuildMesh(List<Aabb> boxes, string name)
        {
            var vertices = new List<Vector3>(boxes.Count * 24);
            var normals = new List<Vector3>(boxes.Count * 24);
            var uvs = new List<Vector2>(boxes.Count * 24);
            var triangles = new List<int>(boxes.Count * 36);

            foreach (Aabb box in boxes) AppendBox(box, vertices, normals, uvs, triangles);

            var mesh = new Mesh { name = name };
            // A big level will exceed 65535 vertices, and the failure mode for that is a
            // silently truncated mesh rather than an error.
            mesh.indexFormat = vertices.Count > 65000
                ? UnityEngine.Rendering.IndexFormat.UInt32
                : UnityEngine.Rendering.IndexFormat.UInt16;
            mesh.SetVertices(vertices);
            mesh.SetNormals(normals);
            mesh.SetUVs(0, uvs);
            mesh.SetTriangles(triangles, 0);
            mesh.RecalculateBounds();
            return mesh;
        }

        private static void AppendBox(Aabb box, List<Vector3> vertices, List<Vector3> normals,
                                      List<Vector2> uvs, List<int> triangles)
        {
            Vector3 min = box.Min.ToUnity();
            Vector3 max = box.Max.ToUnity();

            // Six faces, each with its own four vertices, because a shared corner cannot carry
            // three different normals and a box with smoothed corners looks like a balloon.
            void Face(Vector3 a, Vector3 b, Vector3 c, Vector3 d, Vector3 normal,
                      float width, float height)
            {
                int start = vertices.Count;
                vertices.Add(a); vertices.Add(b); vertices.Add(c); vertices.Add(d);
                for (int i = 0; i < 4; i++) normals.Add(normal);

                // World-scale UVs: a texture tiles every metre regardless of how big the brush
                // is, so a long wall and a short one have the same apparent texture size.
                uvs.Add(new Vector2(0f, 0f));
                uvs.Add(new Vector2(width, 0f));
                uvs.Add(new Vector2(width, height));
                uvs.Add(new Vector2(0f, height));

                triangles.Add(start); triangles.Add(start + 2); triangles.Add(start + 1);
                triangles.Add(start); triangles.Add(start + 3); triangles.Add(start + 2);
            }

            float sizeX = max.x - min.x, sizeY = max.y - min.y, sizeZ = max.z - min.z;

            Face(new Vector3(min.x, min.y, min.z), new Vector3(max.x, min.y, min.z),
                 new Vector3(max.x, max.y, min.z), new Vector3(min.x, max.y, min.z),
                 Vector3.back, sizeX, sizeY);
            Face(new Vector3(max.x, min.y, max.z), new Vector3(min.x, min.y, max.z),
                 new Vector3(min.x, max.y, max.z), new Vector3(max.x, max.y, max.z),
                 Vector3.forward, sizeX, sizeY);
            Face(new Vector3(min.x, min.y, max.z), new Vector3(min.x, min.y, min.z),
                 new Vector3(min.x, max.y, min.z), new Vector3(min.x, max.y, max.z),
                 Vector3.left, sizeZ, sizeY);
            Face(new Vector3(max.x, min.y, min.z), new Vector3(max.x, min.y, max.z),
                 new Vector3(max.x, max.y, max.z), new Vector3(max.x, max.y, min.z),
                 Vector3.right, sizeZ, sizeY);
            Face(new Vector3(min.x, max.y, min.z), new Vector3(max.x, max.y, min.z),
                 new Vector3(max.x, max.y, max.z), new Vector3(min.x, max.y, max.z),
                 Vector3.up, sizeX, sizeZ);
            Face(new Vector3(min.x, min.y, max.z), new Vector3(max.x, min.y, max.z),
                 new Vector3(max.x, min.y, min.z), new Vector3(min.x, min.y, min.z),
                 Vector3.down, sizeX, sizeZ);
        }
    }
}
