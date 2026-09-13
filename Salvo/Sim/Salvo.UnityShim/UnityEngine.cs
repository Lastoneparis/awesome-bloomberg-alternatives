// Minimal UnityEngine stand-ins. See README.md — this exists to compile the bridge, not to
// emulate Unity. Written from the documented API; where it is wrong, it is wrong silently.
using System;

namespace UnityEngine
{
    public struct Vector2
    {
        public float x, y;
        public Vector2(float x, float y) { this.x = x; this.y = y; }
        public static readonly Vector2 zero = new Vector2(0f, 0f);
        public static Vector2 ClampMagnitude(Vector2 v, float max) => v;
        public static Vector2 operator +(Vector2 a, Vector2 b) => new Vector2(a.x + b.x, a.y + b.y);
        public static Vector2 operator -(Vector2 a, Vector2 b) => new Vector2(a.x - b.x, a.y - b.y);
        public static Vector2 operator *(Vector2 a, float s) => new Vector2(a.x * s, a.y * s);
        public static Vector2 operator -(Vector2 a) => new Vector2(-a.x, -a.y);
    }

    public struct Vector3
    {
        public float x, y, z;
        public Vector3(float x, float y, float z) { this.x = x; this.y = y; this.z = z; }
        public static readonly Vector3 zero = new Vector3(0f, 0f, 0f);
        public static readonly Vector3 one = new Vector3(1f, 1f, 1f);
        public static readonly Vector3 up = new Vector3(0f, 1f, 0f);
        public static readonly Vector3 down = new Vector3(0f, -1f, 0f);
        public static readonly Vector3 left = new Vector3(-1f, 0f, 0f);
        public static readonly Vector3 right = new Vector3(1f, 0f, 0f);
        public static readonly Vector3 forward = new Vector3(0f, 0f, 1f);
        public static readonly Vector3 back = new Vector3(0f, 0f, -1f);
    }

    public struct Quaternion
    {
        public static readonly Quaternion identity = default;
        public static Quaternion Euler(float x, float y, float z) => default;
    }

    public struct Color
    {
        public float r, g, b, a;
        public Color(float r, float g, float b) { this.r = r; this.g = g; this.b = b; a = 1f; }
        public Color(float r, float g, float b, float a) { this.r = r; this.g = g; this.b = b; this.a = a; }
    }

    public struct Bounds
    {
        public Bounds(Vector3 centre, Vector3 size) { }
    }

    public struct Rect
    {
        public Rect(float x, float y, float width, float height) { }
    }

    public static class Mathf
    {
        public static float Abs(float v) => Math.Abs(v);
        public static int Min(int a, int b) => Math.Min(a, b);
        public static float Min(float a, float b) => Math.Min(a, b);
        public static int Max(int a, int b) => Math.Max(a, b);
        public static float Max(float a, float b) => Math.Max(a, b);
        public static float Clamp(float v, float lo, float hi) => Math.Min(hi, Math.Max(lo, v));
    }

    public static class Time
    {
        public static float deltaTime => 0f;
    }

    public class Object
    {
        public string name;
        public static UnityEngine.Object Instantiate(UnityEngine.Object original) => original;
        public static T Instantiate<T>(T original, Transform parent) where T : UnityEngine.Object
            => original;
        public static void DestroyImmediate(UnityEngine.Object target) { }
        public static void Destroy(UnityEngine.Object target) { }
    }

    public class Component : Object
    {
        public Transform transform => null;
        public GameObject gameObject => null;
        public T GetComponent<T>() where T : Component => null;
        public T AddComponent<T>() where T : Component => null;
    }

    public class Transform : Component
    {
        public Vector3 position { get; set; }
        public Quaternion rotation { get; set; }
        public Vector3 localScale { get; set; }
        public void SetParent(Transform parent, bool worldPositionStays) { }
        public void SetPositionAndRotation(Vector3 position, Quaternion rotation) { }
    }

    public class GameObject : Object
    {
        public GameObject() { }
        public GameObject(string name) { this.name = name; }
        public Transform transform => null;
        public T AddComponent<T>() where T : Component => null;
        public T GetComponent<T>() where T : Component => null;
        public void SetActive(bool value) { }
        public static GameObject CreatePrimitive(PrimitiveType type) => null;
    }

    public enum PrimitiveType { Sphere, Capsule, Cylinder, Cube, Plane, Quad }

    public class MonoBehaviour : Component
    {
        public bool enabled { get; set; }
    }

    public class ScriptableObject : Object { }

    public class Collider : Component { }
    public class Material : Object
    {
        public Material(Shader shader) { }
        public Color color { get; set; }
    }

    public class Shader : Object
    {
        public static Shader Find(string name) => null;
    }

    public class Mesh : Object
    {
        public Rendering.IndexFormat indexFormat { get; set; }
        public void SetVertices(System.Collections.Generic.List<Vector3> v) { }
        public void SetNormals(System.Collections.Generic.List<Vector3> n) { }
        public void SetUVs(int channel, System.Collections.Generic.List<Vector2> uvs) { }
        public void SetTriangles(System.Collections.Generic.List<int> t, int submesh) { }
        public void RecalculateBounds() { }
    }

    public class MeshFilter : Component { public Mesh sharedMesh { get; set; } }

    public class Renderer : Component
    {
        public Material sharedMaterial { get; set; }
        public Rendering.ShadowCastingMode shadowCastingMode { get; set; }
    }

    public class MeshRenderer : Renderer { }

    public class Camera : Component
    {
        public float fieldOfView { get; set; }
        public float nearClipPlane { get; set; }
        public float farClipPlane { get; set; }
    }

    public enum LightType { Spot, Directional, Point, Area }
    public enum LightShadows { None, Hard, Soft }

    public class Light : Component
    {
        public LightType type { get; set; }
        public float intensity { get; set; }
        public LightShadows shadows { get; set; }
    }

    public class AudioListener : Component { }

    public static class Debug
    {
        public static void Log(object message) { }
        public static void LogWarning(object message) { }
        public static void LogError(object message) { }
    }

    public static class GUI
    {
        public static void Label(Rect position, string text) { }
    }

    [AttributeUsage(AttributeTargets.Field)]
    public sealed class SerializeField : Attribute { }

    [AttributeUsage(AttributeTargets.Field)]
    public sealed class HeaderAttribute : PropertyAttribute
    {
        public HeaderAttribute(string header) { }
    }

    [AttributeUsage(AttributeTargets.Field)]
    public sealed class TooltipAttribute : PropertyAttribute
    {
        public TooltipAttribute(string tooltip) { }
    }

    [AttributeUsage(AttributeTargets.Field)]
    public sealed class RangeAttribute : PropertyAttribute
    {
        public RangeAttribute(float min, float max) { }
    }

    public abstract class PropertyAttribute : Attribute { }

    [AttributeUsage(AttributeTargets.Class)]
    public sealed class AddComponentMenu : Attribute
    {
        public AddComponentMenu(string menuName) { }
    }

    [AttributeUsage(AttributeTargets.Class)]
    public sealed class CreateAssetMenu : Attribute
    {
        public string menuName;
        public string fileName;
        public int order;
    }

    namespace Rendering
    {
        public enum ShadowCastingMode { Off, On, TwoSided, ShadowsOnly }
        public enum IndexFormat { UInt16, UInt32 }
    }

    namespace SceneManagement
    {
        public struct Scene { }
    }

    namespace InputSystem
    {
        public class ButtonControl { public bool isPressed => false; }
        public class StickControl { public Vector2 ReadValue() => Vector2.zero; }
        public class Vector2Control { public Vector2 ReadValue() => Vector2.zero; }

        public class Keyboard
        {
            public static Keyboard current => null;
            public ButtonControl wKey, aKey, sKey, dKey, spaceKey, leftCtrlKey, leftShiftKey;
            public ButtonControl rKey, eKey, digit1Key, digit2Key, digit3Key;
        }

        public class Mouse
        {
            public static Mouse current => null;
            public ButtonControl leftButton, rightButton;
            public Vector2Control delta;
        }

        public class Gamepad
        {
            public static Gamepad current => null;
            public StickControl leftStick, rightStick;
            public ButtonControl leftTrigger, rightTrigger, buttonSouth, buttonEast;
            public ButtonControl buttonWest, buttonNorth, leftStickButton;
        }
    }
}
