using System.Collections.Generic;

namespace Salvo.Sim
{
    /// <summary>
    /// Owns one <see cref="BotBrain"/> per bot and feeds their commands into the match.
    /// </summary>
    /// <remarks>
    /// Separate from <see cref="MatchSimulation"/> on purpose. The match must not know that bots
    /// exist: on a dedicated server the bots run alongside it exactly as remote clients do, and
    /// if the match had a "tick the bots" step then a bot would be a different kind of
    /// participant from a player. Here it is the same kind, driven from outside.
    /// </remarks>
    public sealed class BotDirector
    {
        private readonly Dictionary<int, BotBrain> _brains = new Dictionary<int, BotBrain>();
        private readonly GameContent _content;
        private readonly uint _seed;

        public BotDirector(GameContent content, uint seed)
        {
            _content = content ?? throw new System.ArgumentNullException(nameof(content));
            _seed = seed;
        }

        public BotBrain BrainFor(PlayerRuntime bot)
        {
            if (_brains.TryGetValue(bot.Id.Raw, out BotBrain existing)) return existing;

            if (!_content.BotDifficulties.TryGet(bot.BotDifficultyId,
                                                 out BotDifficultyDefinition difficulty))
            {
                // A bot with an unknown difficulty is a content bug. Failing loudly beats
                // silently promoting it to whatever the first difficulty in the catalogue is.
                throw new System.InvalidOperationException(
                    $"bot '{bot.Name}' has difficulty '{bot.BotDifficultyId}', "
                    + "which is not in the catalogue");
            }

            // Seeded per bot so two bots of the same difficulty do not act in lockstep, and
            // deterministically so a match can be replayed.
            var brain = new BotBrain(difficulty, _seed ^ (uint)(bot.Id.Raw * 2654435761u));
            _brains[bot.Id.Raw] = brain;
            return brain;
        }

        /// <summary>Thinks for every bot and submits their commands. Call once per tick, before
        /// <see cref="MatchSimulation.Step"/>.</summary>
        public void Think(MatchSimulation match, float dt)
        {
            IReadOnlyList<PlayerRuntime> players = match.Players;
            for (int i = 0; i < players.Count; i++)
            {
                PlayerRuntime player = players[i];
                if (!player.IsBot || !player.IsConnected) continue;
                match.SubmitInput(player.Id, BrainFor(player).Think(match, player, dt));
            }
        }

        public BotGoal GoalOf(PlayerRuntime bot) =>
            _brains.TryGetValue(bot.Id.Raw, out BotBrain brain) ? brain.Goal : BotGoal.Idle;
    }
}
