using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using Salvo.Runtime;
using Salvo.Sim;

namespace Salvo.Editor
{
    /// <summary>
    /// Builds the prototype scene from code.
    /// </summary>
    /// <remarks>
    /// The scene is generated rather than committed as a `.unity` file, and that is a deliberate
    /// choice with a real trade-off. A committed scene is a large YAML document full of GUIDs
    /// that no reviewer can read and that conflicts on every simultaneous edit. A generator is a
    /// C# file: it diffs, it reviews, and it cannot drift out of step with the code it wires
    /// together, because it is that code's caller.
    ///
    /// <para>The cost is that the scene is not the authored artefact — anyone who hand-edits it
    /// will lose their work the next time this runs. That is the right trade for a prototype
    /// scene whose whole content is "a camera, a light, and one component". It would be the
    /// wrong trade for a real level.</para>
    /// </remarks>
    public static class PrototypeSceneBuilder
    {
        private const string ScenePath = "Assets/Salvo/Scenes/Prototype.unity";

        [MenuItem("Salvo/Build Prototype Scene", priority = 10)]
        public static void BuildAndOpen()
        {
            UnityEngine.SceneManagement.Scene scene =
                EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);

            var lightObject = new GameObject("Sun");
            Light sun = lightObject.AddComponent<Light>();
            sun.type = LightType.Directional;
            sun.intensity = 1.1f;
            sun.shadows = LightShadows.Soft;
            lightObject.transform.rotation = Quaternion.Euler(48f, 35f, 0f);

            var cameraObject = new GameObject("Player Camera");
            Camera camera = cameraObject.AddComponent<Camera>();
            camera.fieldOfView = 75f;
            camera.nearClipPlane = 0.05f;
            camera.farClipPlane = 260f;
            cameraObject.AddComponent<AudioListener>();

            LocalPlayerInput input = cameraObject.AddComponent<LocalPlayerInput>();

            var hostObject = new GameObject("Salvo Host");
            PrototypeHost host = hostObject.AddComponent<PrototypeHost>();

            // Wired through SerializedObject rather than by making the fields public. Keeping
            // them private with [SerializeField] is what stops other runtime code from reaching
            // in and rewriting the host's configuration at play time.
            var serialized = new SerializedObject(host);
            serialized.FindProperty("playerCamera").objectReferenceValue = camera;
            serialized.FindProperty("playerInput").objectReferenceValue = input;
            serialized.FindProperty("botMarkerPrefab").objectReferenceValue = BuildMarkerPrefab();

            SerializedProperty materials = serialized.FindProperty("surfaceMaterials");
            int surfaceCount = System.Enum.GetValues(typeof(SurfaceKind)).Length;
            materials.arraySize = surfaceCount;
            for (int i = 0; i < surfaceCount; i++)
                materials.GetArrayElementAtIndex(i).objectReferenceValue = PlaceholderMaterial((SurfaceKind)i);
            serialized.ApplyModifiedProperties();

            System.IO.Directory.CreateDirectory("Assets/Salvo/Scenes");
            EditorSceneManager.SaveScene(scene, ScenePath);
            AssetDatabase.Refresh();
            Debug.Log($"[Salvo] Prototype scene written to {ScenePath}. Press Play.");
        }

        [MenuItem("Salvo/Validate Content", priority = 20)]
        public static void ValidateContent()
        {
            // Runs the same validation the dedicated server runs, from the editor, so an
            // authoring mistake is found before a build rather than in a match.
            System.Collections.Generic.List<string> problems = StarterContent.Build().Validate();
            foreach (ContentCatalogueAsset asset in LoadAll<ContentCatalogueAsset>())
                foreach (string problem in asset.Validate())
                    problems.Add($"{asset.name}: {problem}");

            if (problems.Count == 0) { Debug.Log("[Salvo] Content is valid."); return; }
            foreach (string problem in problems) Debug.LogError($"[Salvo] {problem}");
        }

        private static T[] LoadAll<T>() where T : Object
        {
            string[] guids = AssetDatabase.FindAssets($"t:{typeof(T).Name}");
            var results = new T[guids.Length];
            for (int i = 0; i < guids.Length; i++)
                results[i] = AssetDatabase.LoadAssetAtPath<T>(AssetDatabase.GUIDToAssetPath(guids[i]));
            return results;
        }

        private static GameObject BuildMarkerPrefab()
        {
            const string path = "Assets/Salvo/Prefabs/BotMarker.prefab";
            GameObject existing = AssetDatabase.LoadAssetAtPath<GameObject>(path);
            if (existing != null) return existing;

            GameObject capsule = GameObject.CreatePrimitive(PrimitiveType.Capsule);
            capsule.name = "BotMarker";
            // Matched to CharacterDefinition so what is drawn is the size of what is shot at.
            // A marker that does not match the hitbox teaches players the wrong thing.
            capsule.transform.localScale = new Vector3(
                CharacterDefinition.Radius * 2f,
                CharacterDefinition.StandingHeight * 0.5f,
                CharacterDefinition.Radius * 2f);
            Object.DestroyImmediate(capsule.GetComponent<Collider>());

            System.IO.Directory.CreateDirectory("Assets/Salvo/Prefabs");
            GameObject prefab = PrefabUtility.SaveAsPrefabAsset(capsule, path);
            Object.DestroyImmediate(capsule);
            return prefab;
        }

        private static Material PlaceholderMaterial(SurfaceKind surface)
        {
            string path = $"Assets/Salvo/Materials/surface_{surface}.mat";
            Material existing = AssetDatabase.LoadAssetAtPath<Material>(path);
            if (existing != null) return existing;

            Shader shader = Shader.Find("Universal Render Pipeline/Lit") ?? Shader.Find("Standard");
            var material = new Material(shader) { name = $"surface_{surface}" };
            // Flat colours, not textures. The point of the prototype is to see the shape of the
            // level and tell surfaces apart; anything more would be art direction done before
            // the game is known to be fun.
            material.color = surface switch
            {
                SurfaceKind.Metal => new Color(0.55f, 0.57f, 0.60f),
                SurfaceKind.Wood => new Color(0.52f, 0.38f, 0.24f),
                SurfaceKind.Dirt => new Color(0.42f, 0.35f, 0.26f),
                SurfaceKind.Sand => new Color(0.76f, 0.69f, 0.50f),
                SurfaceKind.Glass => new Color(0.70f, 0.80f, 0.85f),
                SurfaceKind.Water => new Color(0.25f, 0.45f, 0.60f),
                _ => new Color(0.62f, 0.62f, 0.60f),
            };

            System.IO.Directory.CreateDirectory("Assets/Salvo/Materials");
            AssetDatabase.CreateAsset(material, path);
            return material;
        }
    }
}
