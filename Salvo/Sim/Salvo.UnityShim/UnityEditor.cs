// Minimal UnityEditor stand-ins. See README.md.
using System;
using UnityEngine;

namespace UnityEditor
{
    public enum NewSceneSetup { EmptyScene, DefaultGameObjects }
    public enum NewSceneMode { Single, Additive }

    [AttributeUsage(AttributeTargets.Method)]
    public sealed class MenuItem : Attribute
    {
        public MenuItem(string itemName) { }
        public MenuItem(string itemName, bool isValidateFunction) { }
        public MenuItem(string itemName, bool isValidateFunction, int priority) { }
        public int priority;
    }

    public class SerializedProperty
    {
        public UnityEngine.Object objectReferenceValue { get; set; }
        public int arraySize { get; set; }
        public SerializedProperty GetArrayElementAtIndex(int index) => null;
    }

    public class SerializedObject
    {
        public SerializedObject(UnityEngine.Object target) { }
        public SerializedProperty FindProperty(string path) => null;
        public bool ApplyModifiedProperties() => true;
    }

    public static class AssetDatabase
    {
        public static string[] FindAssets(string filter) => Array.Empty<string>();
        public static string GUIDToAssetPath(string guid) => "";
        public static T LoadAssetAtPath<T>(string path) where T : UnityEngine.Object => null;
        public static void CreateAsset(UnityEngine.Object asset, string path) { }
        public static void Refresh() { }
    }

    public static class PrefabUtility
    {
        public static GameObject SaveAsPrefabAsset(GameObject root, string path) => root;
    }

    namespace SceneManagement
    {
        public static class EditorSceneManager
        {
            public static UnityEngine.SceneManagement.Scene NewScene(NewSceneSetup setup,
                                                                     NewSceneMode mode) => default;
            public static bool SaveScene(UnityEngine.SceneManagement.Scene scene, string path)
                => true;
        }
    }
}
