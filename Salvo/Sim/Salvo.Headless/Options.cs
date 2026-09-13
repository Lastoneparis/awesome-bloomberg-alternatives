using System;
using Salvo.Sim;

namespace Salvo.Headless
{
    /// <summary>Command-line options for a headless run.</summary>
    public sealed class Options
    {
        public const string Usage = @"salvo-headless — plays a bot match of Salvo with no engine.

  --mode <id>        game mode (default mode.tdm)
  --map <id>         map (default map.junction)
  --bots <n>         number of bots (default 8)
  --difficulty <id>  bot.easy | bot.normal | bot.hard | bot.expert (default bot.normal)
  --seed <n>         match seed; the same seed replays identically (default 1)
  --seconds <n>      stop after this much match time (default 180)
  --verbose          print kills as they happen
  --matchmaking      queue a population of parties, form matches, and check the
                     rules held across every match formed
  --net              run a real networked match: authoritative server, predicting
                     clients, and a lossy link, all in one process
  --link <profile>   perfect | mobile | poor (default mobile). Only with --net.
  --help

Exits 0 if the match ran cleanly, 1 if the run found a problem, 2 on bad input.";

        public string ModeId = StarterContent.Modes.TeamDeathmatch;
        public string MapId = StarterContent.MapCrossfire;
        public int BotCount = 8;
        public string Difficulty = StarterContent.Difficulties.Normal;
        public uint Seed = 1;
        public float MaxSeconds = 180f;
        public bool Verbose;
        public bool ShowHelp;
        public bool Networked;
        public bool Matchmaking;
        public string NetworkProfile = "mobile";

        public static Options Parse(string[] args)
        {
            var options = new Options();
            for (int i = 0; i < args.Length; i++)
            {
                string argument = args[i];
                string Next() => i + 1 < args.Length ? args[++i] : "";

                switch (argument)
                {
                    case "--mode": options.ModeId = Next(); break;
                    case "--map": options.MapId = Next(); break;
                    case "--bots": options.BotCount = int.TryParse(Next(), out int n) ? n : 8; break;
                    case "--difficulty": options.Difficulty = Next(); break;
                    case "--seed": options.Seed = uint.TryParse(Next(), out uint s) ? s : 1u; break;
                    case "--seconds":
                        options.MaxSeconds = float.TryParse(Next(), out float t) ? t : 180f;
                        break;
                    case "--verbose": options.Verbose = true; break;
                    case "--net": options.Networked = true; break;
                    case "--matchmaking": options.Matchmaking = true; break;
                    case "--link": options.NetworkProfile = Next(); break;
                    case "--help":
                    case "-h": options.ShowHelp = true; break;
                    default:
                        Console.Error.WriteLine($"unknown option: {argument}");
                        options.ShowHelp = true;
                        break;
                }
            }
            return options;
        }
    }
}
