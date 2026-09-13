using System.Collections.Generic;

namespace Salvo.Sim
{
    /// <summary>How a client's content compares with the server's.</summary>
    public enum ContentVerdict : byte
    {
        /// <summary>Identical. Play.</summary>
        Identical,
        /// <summary>The simulation agrees; only presentation differs. Play, and log it.</summary>
        PresentationDiffers,
        /// <summary>The simulation disagrees. Refuse.</summary>
        Incompatible,
    }

    public struct ContentCheck
    {
        public ContentVerdict Verdict;
        /// <summary>Localisation key for what to tell the player. Never a sentence.</summary>
        public string ReasonKey;
        public string ServerVersion;
        public string ClientVersion;

        public bool CanPlay => Verdict != ContentVerdict.Incompatible;
    }

    /// <summary>
    /// Decides whether a client may join, given what content each side is running.
    /// </summary>
    /// <remarks>
    /// The check exists because the failure it prevents is silent. Two machines running
    /// different weapon statistics produce a match where prediction never settles, damage
    /// numbers disagree, and every symptom points at the netcode. Refusing the connection turns
    /// a week of confused debugging into one clear message at the door.
    ///
    /// <para>It is a correctness gate, not an anti-cheat measure. A client that has altered its
    /// content can report whatever hash it likes. That is fine, and is not what this is for: the
    /// server already refuses to take a client's word for damage, health, position or hits, so
    /// altered client content changes what that client <em>draws</em> and nothing about what
    /// happens. What this catches is the honest case — a partial download, a stale build, a
    /// content patch that reached half the fleet.</para>
    /// </remarks>
    public static class ContentCompatibility
    {
        public static ContentCheck Check(ContentManifest server, ContentManifest client)
        {
            if (server == null || client == null)
            {
                return new ContentCheck
                {
                    Verdict = ContentVerdict.Incompatible,
                    ReasonKey = "content.error.missing_manifest",
                    ServerVersion = server?.Version ?? "",
                    ClientVersion = client?.Version ?? "",
                };
            }

            var result = new ContentCheck
            {
                ServerVersion = server.Version,
                ClientVersion = client.Version,
            };

            if (server.SimulationHash != client.SimulationHash)
            {
                result.Verdict = ContentVerdict.Incompatible;
                result.ReasonKey = "content.error.simulation_mismatch";
                return result;
            }

            if (server.PresentationHash != client.PresentationHash)
            {
                // Deliberately allowed. Blocking here would mean a translation fix could not
                // ship without forcing the whole fleet to update simultaneously.
                result.Verdict = ContentVerdict.PresentationDiffers;
                result.ReasonKey = "content.warning.presentation_mismatch";
                return result;
            }

            result.Verdict = ContentVerdict.Identical;
            result.ReasonKey = "content.ok";
            return result;
        }

        /// <summary>
        /// A human-readable account of what differs, for a log or a support ticket.
        /// </summary>
        /// <remarks>
        /// Counts only — this cannot say <em>which</em> weapon differs, because a hash does not
        /// carry that. Saying so plainly is better than implying a precision it does not have.
        /// </remarks>
        public static List<string> Describe(ContentManifest server, ContentManifest client)
        {
            var differences = new List<string>();
            if (server == null || client == null)
            {
                differences.Add("one side reported no manifest at all");
                return differences;
            }

            if (server.Version != client.Version)
                differences.Add($"version: server {server.Version}, client {client.Version}");
            if (server.WeaponCount != client.WeaponCount)
                differences.Add($"weapons: server {server.WeaponCount}, client {client.WeaponCount}");
            if (server.AttachmentCount != client.AttachmentCount)
                differences.Add($"attachments: server {server.AttachmentCount}, client {client.AttachmentCount}");
            if (server.MapCount != client.MapCount)
                differences.Add($"maps: server {server.MapCount}, client {client.MapCount}");
            if (server.WorldCount != client.WorldCount)
                differences.Add($"worlds: server {server.WorldCount}, client {client.WorldCount}");
            if (server.ModeCount != client.ModeCount)
                differences.Add($"modes: server {server.ModeCount}, client {client.ModeCount}");

            if (differences.Count == 0 && server.SimulationHash != client.SimulationHash)
                differences.Add("the same number of everything, but different values — "
                                + "a balance change reached one side and not the other");
            return differences;
        }
    }
}
