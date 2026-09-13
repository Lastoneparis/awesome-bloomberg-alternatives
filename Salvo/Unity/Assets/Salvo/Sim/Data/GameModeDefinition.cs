using System;

namespace Salvo.Sim
{
    /// <summary>
    /// Which rules object runs a match. The enum names a rules implementation; everything
    /// tunable lives in the definition beside it, so Team Deathmatch at 50 kills and Team
    /// Deathmatch at 100 are two assets, not two classes.
    /// </summary>
    public enum GameModeKind : byte
    {
        TeamDeathmatch,
        FreeForAll,
        SearchAndDestroy,
        CapturePoint,
        Domination,
        GunGame,
        TeamVersusBots,
        SoloPractice
    }

    [Serializable]
    public class GameModeDefinition
    {
        public ContentId Id;
        public string DisplayNameKey = "";
        public string DescriptionKey = "";
        public GameModeKind Kind = GameModeKind.TeamDeathmatch;

        /// <summary>Per mode, never global (§3). A 1v1 practice mode and a 10v10 mode are
        /// the same build.</summary>
        public int MinPlayers = 2;
        public int MaxPlayers = 10;
        public int TeamSize = 5;
        public bool IsTeamBased = true;

        public int ScoreLimit = 75;
        public float TimeLimitSeconds = 600f;
        public int RoundsToWin = 0;             // 0 = not round-based
        public float RoundSeconds = 0f;
        public float WarmupSeconds = 10f;
        public float FreezeSeconds = 0f;

        public bool AllowsRespawn = true;
        public float RespawnDelaySeconds = 3f;
        public float SpawnProtectionSeconds = 1.5f;
        public bool FriendlyFire = false;
        public bool HealthRegenerates = true;
        public float RegenDelaySeconds = 5f;
        public float RegenPerSecond = 25f;

        public float StartingHealth = 100f;
        public float StartingArmour = 0f;

        /// <summary>Bots fill empty slots so the game is playable alone (§7).</summary>
        public bool FillWithBots = true;

        public bool IsRoundBased => RoundsToWin > 0;

        public void Validate(System.Collections.Generic.List<string> problems)
        {
            if (Id.IsEmpty) problems.Add("game mode has no Id");
            string name = Id.ToString();
            if (MaxPlayers < MinPlayers) problems.Add($"{name}: MaxPlayers is below MinPlayers");
            if (IsTeamBased && TeamSize * 2 < MinPlayers)
                problems.Add($"{name}: TeamSize cannot seat MinPlayers");
            if (ScoreLimit <= 0 && TimeLimitSeconds <= 0f && !IsRoundBased)
                problems.Add($"{name}: no score limit, time limit or round count — the match cannot end");
            if (StartingHealth <= 0f) problems.Add($"{name}: StartingHealth must be positive");
            if (!AllowsRespawn && !IsRoundBased)
                problems.Add($"{name}: no respawn and no rounds — eliminated players wait forever");
            if (string.IsNullOrEmpty(DisplayNameKey)) problems.Add($"{name}: DisplayNameKey is empty");
        }
    }

    /// <summary>
    /// How good a bot is (§7). Every value here degrades a bot's *senses and hands* —
    /// reaction, accuracy, awareness. None of them touches damage, health or fire rate,
    /// because a bot that survives two extra bullets is not harder, it is broken.
    /// </summary>
    [Serializable]
    public class BotDifficultyDefinition
    {
        public ContentId Id;
        public string DisplayNameKey = "";

        /// <summary>Seconds between an enemy becoming visible and the bot reacting.</summary>
        public float ReactionSeconds = 0.35f;
        /// <summary>Radians of error added to aim. The dominant difficulty knob.</summary>
        public float AimErrorRadians = 0.05f;
        /// <summary>How fast the bot turns onto a target. Low values read as human.</summary>
        public float TurnSpeedRadiansPerSecond = 4.5f;
        /// <summary>Chance per shot of releasing the trigger, so bots do not hold a
        /// perfect beam.</summary>
        public float TriggerDisciplineChance = 0.25f;
        public float ViewConeDegrees = 110f;
        public float SightRangeMetres = 60f;
        public float HearingRangeMetres = 25f;
        /// <summary>0–1. How readily the bot breaks off when losing a fight.</summary>
        public float RetreatTendency = 0.3f;
        /// <summary>0–1. How much the bot prefers cover over the direct route.</summary>
        public float CoverPreference = 0.5f;
        /// <summary>0–1. How reliably the bot plays the objective rather than the kill.</summary>
        public float ObjectiveFocus = 0.5f;

        public void Validate(System.Collections.Generic.List<string> problems)
        {
            if (Id.IsEmpty) problems.Add("bot difficulty has no Id");
            string name = Id.ToString();
            if (AimErrorRadians < 0f) problems.Add($"{name}: AimErrorRadians cannot be negative");
            if (ReactionSeconds < 0f) problems.Add($"{name}: ReactionSeconds cannot be negative");
            if (AimErrorRadians <= 0.0001f && ReactionSeconds <= 0.01f)
                problems.Add($"{name}: a bot with no aim error and no reaction time is an aimbot, not a difficulty");
        }
    }
}
