using System.Collections.Generic;
using UnityEngine;
using Salvo.Sim;

namespace Salvo.Runtime
{
    /// <summary>
    /// Runs a single-machine match: one local player, the rest bots. The prototype.
    /// </summary>
    /// <remarks>
    /// Deliberately offline. Networking is a later phase, and this exists to prove the
    /// simulation is a game before any of that is in the way — if it is not fun against bots on
    /// one device, no amount of netcode will help.
    ///
    /// <para>Note what this class does and does not do. It ticks the simulation at a fixed rate,
    /// feeds it commands, and copies the results onto transforms. It never reads a transform
    /// back into the simulation. That direction of flow is the whole design: Unity is a view of
    /// the simulation, never a participant in it, which is what lets the identical code run on a
    /// dedicated server with no Unity at all.</para>
    ///
    /// <para>Rendering interpolates between the last two simulation states using the clock's
    /// alpha. Without that, a 64 Hz simulation displayed on a 120 Hz screen judders visibly,
    /// and the instinctive fix — raising the tick rate — costs bandwidth and CPU to solve a
    /// problem that is purely about presentation.</para>
    /// </remarks>
    [AddComponentMenu("Salvo/Prototype Host")]
    public sealed class PrototypeHost : MonoBehaviour
    {
        [Header("Content")]
        [Tooltip("Leave empty to use the code-built starter catalogue.")]
        [SerializeField] private ContentCatalogueAsset catalogue;
        [SerializeField] private string modeId = "mode.tdm";
        [SerializeField] private string mapId = "map.junction";
        [SerializeField] private string botDifficultyId = "bot.normal";
        [SerializeField, Range(1, 9)] private int botCount = 5;
        [SerializeField] private uint matchSeed = 1;

        [Header("Scene")]
        [SerializeField] private Camera playerCamera;
        [SerializeField] private LocalPlayerInput playerInput;
        [SerializeField] private Material[] surfaceMaterials;
        [Tooltip("Stand-in for a character model until there is one.")]
        [SerializeField] private GameObject botMarkerPrefab;

        private MatchSimulation _match;
        private BotDirector _director;
        private PlayerRuntime _localPlayer;
        private readonly FixedClock _clock = new FixedClock();
        private readonly Dictionary<int, Transform> _markers = new Dictionary<int, Transform>();

        private Vec3 _previousEye;
        private Vec3 _currentEye;

        public MatchSimulation Match => _match;

        private void Start()
        {
            GameContent content = catalogue != null ? catalogue.Build() : StarterContent.Build();

            List<string> problems = content.Validate();
            if (problems.Count > 0)
            {
                // Refusing to start is the right response. A match built on invalid content
                // produces failures that look like engine bugs and waste a day each.
                foreach (string problem in problems) Debug.LogError($"[Salvo] content: {problem}");
                enabled = false;
                return;
            }

            if (!content.GameModes.TryGet(modeId, out GameModeDefinition modeDefinition))
            {
                Debug.LogError($"[Salvo] no such game mode: {modeId}");
                enabled = false;
                return;
            }
            if (!content.Maps.TryGet(mapId, out MapDefinition map))
            {
                Debug.LogError($"[Salvo] no such map: {mapId}");
                enabled = false;
                return;
            }

            IGameMode mode = modeDefinition.Kind == GameModeKind.FreeForAll
                ? (IGameMode)new FreeForAllMode(modeDefinition)
                : new TeamDeathmatchMode(modeDefinition);

            _match = new MatchSimulation(content, map, mode, matchSeed);
            _director = new BotDirector(content, matchSeed);

            var loadout = Loadout.Default("wpn.kestrel", "wpn.pike", "wpn.cleaver");
            _localPlayer = _match.AddPlayer("You", Team.Alpha, loadout);
            int bots = Mathf.Min(botCount, modeDefinition.MaxPlayers - 1);
            for (int i = 0; i < bots; i++)
            {
                _match.AddPlayer($"Bot{i:D2}", i % 2 == 0 ? Team.Bravo : Team.Alpha, loadout,
                                 isBot: true, botDifficulty: botDifficultyId);
            }

            MapGeometryBuilder.Build(map, surfaceMaterials, transform);
            _match.Start();

            if (playerInput != null) playerInput.ResetView(_localPlayer.Movement.View);
            _previousEye = _currentEye = _localPlayer.Movement.EyePosition;
            _clock.Reset();
        }

        private void Update()
        {
            if (_match == null) return;

            _clock.Advance(Time.deltaTime, (tick, dt) => StepOnce(dt));

            // Interpolating the camera between the last two ticks is what makes a 64 Hz
            // simulation look smooth on a 120 Hz display.
            if (playerCamera != null && _localPlayer != null)
            {
                Vec3 eye = Vec3.Lerp(_previousEye, _currentEye, _clock.Alpha);
                playerCamera.transform.SetPositionAndRotation(
                    eye.ToUnity(), _localPlayer.Movement.View.ToUnity());
            }
            UpdateMarkers();
        }

        private void StepOnce(float dt)
        {
            _previousEye = _currentEye;

            if (playerInput != null && _localPlayer != null)
            {
                _match.SubmitInput(_localPlayer.Id, playerInput.Build(_match.Tick, dt));
            }
            _director.Think(_match, dt);
            _match.Step();

            if (_localPlayer != null) _currentEye = _localPlayer.Movement.EyePosition;
        }

        private void UpdateMarkers()
        {
            if (botMarkerPrefab == null) return;

            foreach (PlayerRuntime player in _match.Players)
            {
                if (player == _localPlayer) continue;
                if (!_markers.TryGetValue(player.Id.Raw, out Transform marker))
                {
                    marker = Instantiate(botMarkerPrefab, transform).transform;
                    marker.name = player.Name;
                    _markers[player.Id.Raw] = marker;
                }
                marker.gameObject.SetActive(player.IsAlive);
                if (!player.IsAlive) continue;

                marker.position = (player.Movement.Position
                                   + new Vec3(0f, player.Movement.Height * 0.5f, 0f)).ToUnity();
                marker.rotation = Quaternion.Euler(0f, player.Movement.View.Yaw * SalvoMath.RadToDeg, 0f);
            }
        }

        private void OnGUI()
        {
            if (_match == null || _localPlayer == null) return;

            // Deliberately IMGUI and deliberately ugly. This is a debug readout for the
            // prototype, not the HUD — the real one is a Phase 11 job with localisation and a
            // touch layout, and dressing this up would only make it look finished.
            GUI.Label(new Rect(12, 12, 480, 22),
                      $"HP {_localPlayer.Vitals.Health:F0}  AR {_localPlayer.Vitals.Armour:F0}   "
                      + $"{_localPlayer.HeldWeapon.Magazine}/{_localPlayer.HeldWeapon.Reserve}   "
                      + $"K{_localPlayer.Score.Kills} D{_localPlayer.Score.Deaths}");
            GUI.Label(new Rect(12, 34, 480, 22),
                      $"{_match.Phase}  Alpha {_match.Mode.TeamScore(Team.Alpha)}"
                      + $" - {_match.Mode.TeamScore(Team.Bravo)} Bravo   tick {_match.Tick}"
                      + (_match.Tick > 0 && _clock.DroppedTicks > 0
                         ? $"   DROPPED {_clock.DroppedTicks}" : ""));
        }
    }
}
