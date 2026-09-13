using System;

namespace Salvo.Sim
{
    /// <summary>
    /// A stable string key for a piece of content.
    /// </summary>
    /// <remarks>
    /// String, not an enum or an int. Content is added by live operations without a client
    /// update (§25), so the key has to survive a build it was not present in, and it has to
    /// be readable in a save file, a server log and a JSON manifest. The cost is a string
    /// comparison; content lookups happen at load time, not per frame.
    /// </remarks>
    [Serializable]
    public struct ContentId : IEquatable<ContentId>
    {
        public string Value;

        public ContentId(string value) { Value = value; }

        public bool IsEmpty => string.IsNullOrEmpty(Value);
        public static readonly ContentId None = new ContentId(null);

        public static implicit operator ContentId(string value) => new ContentId(value);

        public bool Equals(ContentId other) =>
            string.Equals(Value, other.Value, StringComparison.Ordinal);

        public override bool Equals(object obj) => obj is ContentId other && Equals(other);
        public override int GetHashCode() => Value == null ? 0 : Value.GetHashCode();
        public override string ToString() => Value ?? "<none>";

        public static bool operator ==(ContentId a, ContentId b) => a.Equals(b);
        public static bool operator !=(ContentId a, ContentId b) => !a.Equals(b);
    }

    /// <summary>Runtime identity of one participant in a match. Not content — this is
    /// assigned per match and is meaningless outside it.</summary>
    [Serializable]
    public struct PlayerId : IEquatable<PlayerId>
    {
        public int Raw;
        public PlayerId(int raw) { Raw = raw; }

        public static readonly PlayerId None = new PlayerId(-1);
        public bool IsValid => Raw >= 0;

        public bool Equals(PlayerId other) => Raw == other.Raw;
        public override bool Equals(object obj) => obj is PlayerId other && Equals(other);
        public override int GetHashCode() => Raw;
        public override string ToString() => Raw < 0 ? "<none>" : "P" + Raw;

        public static bool operator ==(PlayerId a, PlayerId b) => a.Raw == b.Raw;
        public static bool operator !=(PlayerId a, PlayerId b) => a.Raw != b.Raw;
    }

    /// <summary>
    /// Which side a player is on. Deliberately generic: the faction (US Rangers, Martian
    /// Directorate, whatever a world defines) is content, and the simulation only needs to
    /// know who shoots whom.
    /// </summary>
    public enum Team : byte
    {
        None = 0,
        Alpha = 1,
        Bravo = 2
    }

    public static class TeamExtensions
    {
        public static Team Opponent(this Team team) => team switch
        {
            Team.Alpha => Team.Bravo,
            Team.Bravo => Team.Alpha,
            _ => Team.None
        };

        public static bool IsHostileTo(this Team team, Team other) =>
            team != Team.None && other != Team.None && team != other;
    }
}
