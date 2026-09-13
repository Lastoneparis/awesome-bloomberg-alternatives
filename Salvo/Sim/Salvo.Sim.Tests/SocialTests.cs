using System.Collections.Generic;
using Xunit;
using Salvo.Sim;

namespace Salvo.Sim.Tests
{
    /// <summary>
    /// Friends, blocks and parties. Weighted heavily toward blocking, because that is where a
    /// social system fails in a way that hurts someone rather than merely annoying them.
    /// </summary>
    public class SocialTests
    {
        private const string A = "acct.alice";
        private const string B = "acct.bob";
        private const string C = "acct.carol";
        private const string D = "acct.dan";

        // ---- friending ------------------------------------------------------------------

        [Fact]
        public void ARequestAcceptedMakesBothSidesFriends()
        {
            var graph = new SocialGraph();
            Assert.Equal(SocialResult.Ok, graph.SendRequest(A, B));
            Assert.Contains(A, graph.IncomingRequestsFor(B));
            Assert.False(graph.AreFriends(A, B));

            Assert.Equal(SocialResult.Ok, graph.Accept(A, B));
            Assert.True(graph.AreFriends(A, B));
            Assert.True(graph.AreFriends(B, A));
            Assert.Empty(graph.IncomingRequestsFor(B));
        }

        [Fact]
        public void CrossingRequestsBecomeAFriendshipRatherThanADeadlock()
        {
            // Two people who ask each other at the same moment. Without this, both end up with a
            // pending request, neither is a friend, and neither can work out why.
            var graph = new SocialGraph();
            Assert.Equal(SocialResult.Ok, graph.SendRequest(A, B));
            Assert.Equal(SocialResult.Ok, graph.SendRequest(B, A));

            Assert.True(graph.AreFriends(A, B));
            Assert.Empty(graph.IncomingRequestsFor(A));
            Assert.Empty(graph.IncomingRequestsFor(B));
        }

        [Fact]
        public void NobodyCanFriendThemselves()
        {
            var graph = new SocialGraph();
            Assert.Equal(SocialResult.Self, graph.SendRequest(A, A));
            Assert.Equal(SocialResult.Self, graph.Block(A, A));
        }

        [Fact]
        public void DuplicateRequestsAreRefused()
        {
            var graph = new SocialGraph();
            Assert.Equal(SocialResult.Ok, graph.SendRequest(A, B));
            Assert.Equal(SocialResult.AlreadyApplies, graph.SendRequest(A, B));

            graph.Accept(A, B);
            Assert.Equal(SocialResult.AlreadyApplies, graph.SendRequest(A, B));
        }

        [Fact]
        public void DecliningLeavesNoTrace()
        {
            var graph = new SocialGraph();
            graph.SendRequest(A, B);
            Assert.Equal(SocialResult.Ok, graph.Decline(A, B));
            Assert.Empty(graph.IncomingRequestsFor(B));
            Assert.False(graph.AreFriends(A, B));
            Assert.Equal(SocialResult.NotFound, graph.Decline(A, B));
        }

        [Fact]
        public void UnfriendingIsMutual()
        {
            var graph = new SocialGraph();
            graph.SendRequest(A, B);
            graph.Accept(A, B);

            Assert.Equal(SocialResult.Ok, graph.Unfriend(A, B));
            Assert.False(graph.AreFriends(A, B));
            Assert.False(graph.AreFriends(B, A));
        }

        // ---- blocking, which is the part that matters -------------------------------------

        [Fact]
        public void BlockingSeversAnExistingFriendship()
        {
            // A block that leaves the friendship in place does nothing the moment any code path
            // consults the friend list instead of the block list — and there will always be one.
            var graph = new SocialGraph();
            graph.SendRequest(A, B);
            graph.Accept(A, B);
            Assert.True(graph.AreFriends(A, B));

            Assert.Equal(SocialResult.Ok, graph.Block(A, B));
            Assert.False(graph.AreFriends(A, B));
            Assert.False(graph.AreFriends(B, A));
        }

        [Fact]
        public void BlockingCancelsPendingRequestsInBothDirections()
        {
            var graph = new SocialGraph();
            graph.SendRequest(B, A);
            graph.Block(A, B);

            Assert.Empty(graph.IncomingRequestsFor(A));
            Assert.Empty(graph.OutgoingRequestsOf(B));
        }

        [Fact]
        public void ABlockStopsContactInBothDirections()
        {
            // One-sided in intent, mutual in effect. A block that only stops the blocked party
            // lets the blocker keep sending invitations to someone with no way to refuse them.
            var graph = new SocialGraph();
            graph.Block(A, B);

            Assert.Equal(SocialResult.Blocked, graph.SendRequest(B, A));
            Assert.Equal(SocialResult.Blocked, graph.SendRequest(A, B));
            Assert.False(graph.MayInteract(A, B));
            Assert.False(graph.MayInteract(B, A));
        }

        [Fact]
        public void UnblockingDoesNotQuietlyRestoreTheFriendship()
        {
            var graph = new SocialGraph();
            graph.SendRequest(A, B);
            graph.Accept(A, B);
            graph.Block(A, B);
            Assert.Equal(SocialResult.Ok, graph.Unblock(A, B));

            Assert.True(graph.MayInteract(A, B));
            Assert.False(graph.AreFriends(A, B));
        }

        [Fact]
        public void BlockingIsIdempotentAndUnblockingAStrangerIsANoOp()
        {
            var graph = new SocialGraph();
            Assert.Equal(SocialResult.Ok, graph.Block(A, B));
            Assert.Equal(SocialResult.AlreadyApplies, graph.Block(A, B));
            Assert.Equal(SocialResult.NotFound, graph.Unblock(A, C));
        }

        // ---- deletion --------------------------------------------------------------------

        [Fact]
        public void DeletingAnAccountLeavesNothingAnywhere()
        {
            // A half-deletion is worse than none: an account that vanishes from its own lists
            // but lingers in everyone else's is still personal data, and a ghost entry nobody
            // can remove.
            var graph = new SocialGraph();
            graph.SendRequest(A, B);
            graph.Accept(A, B);
            graph.SendRequest(A, C);
            graph.Block(D, A);

            Assert.True(graph.KnowsAnythingAbout(A));
            graph.ForgetAccount(A);

            Assert.False(graph.KnowsAnythingAbout(A));
            Assert.False(graph.AreFriends(B, A));
            Assert.Empty(graph.IncomingRequestsFor(C));
            Assert.DoesNotContain(A, graph.BlockedBy(D));
        }

        // ---- parties ---------------------------------------------------------------------

        private static GameModeDefinition Mode(string id) =>
            StarterContent.Build().GameModes.Get(id);

        [Fact]
        public void AFounderLeadsTheirOwnParty()
        {
            var party = new Party(A);
            Assert.Equal(A, party.Leader);
            Assert.Equal(1, party.Size);
            Assert.True(party.Contains(A));
        }

        [Fact]
        public void OnlyTheLeaderInvites()
        {
            var graph = new SocialGraph();
            var party = new Party(A);
            party.Invite(A, B, graph);
            party.AcceptInvite(B, graph);

            Assert.Equal(SocialResult.NotFound, party.Invite(B, C, graph));
            Assert.Equal(SocialResult.Ok, party.Invite(A, C, graph));
        }

        [Fact]
        public void APartyInviteCannotBypassABlock()
        {
            // The direct line a block is supposed to close.
            var graph = new SocialGraph();
            graph.Block(B, A);

            var party = new Party(A);
            Assert.Equal(SocialResult.Blocked, party.Invite(A, B, graph));
        }

        [Fact]
        public void AnInviteIsRefusedIfAnyMemberHasBlockedTheInvitee()
        {
            // Not just the leader. A party is a room, and the failure is the same whoever
            // happened to open the door.
            var graph = new SocialGraph();
            var party = new Party(A);
            party.Invite(A, B, graph);
            party.AcceptInvite(B, graph);

            graph.Block(B, C);
            Assert.Equal(SocialResult.Blocked, party.Invite(A, C, graph));
        }

        [Fact]
        public void ABlockBetweenInviteAndAcceptanceStillApplies()
        {
            // An invitation is not a licence that outlives the block that follows it.
            var graph = new SocialGraph();
            var party = new Party(A);
            Assert.Equal(SocialResult.Ok, party.Invite(A, B, graph));

            graph.Block(B, A);
            Assert.Equal(SocialResult.Blocked, party.AcceptInvite(B, graph));
            Assert.False(party.Contains(B));
        }

        [Fact]
        public void BlockingSomeoneYouArePartiedWithEjectsThemImmediately()
        {
            // Without this, blocking a person you are currently in a party with does nothing
            // until the party happens to disband — which is exactly when it matters least.
            var graph = new SocialGraph();
            var party = new Party(A);
            party.Invite(A, B, graph);
            party.AcceptInvite(B, graph);
            Assert.Equal(2, party.Size);

            graph.Block(A, B);
            List<string> removed = party.EnforceBlocks(graph);

            Assert.Contains(B, removed);
            Assert.False(party.Contains(B));
            Assert.Equal(A, party.Leader);
        }

        [Fact]
        public void APartyCannotExceedTheTeamSizeOfItsMode()
        {
            // A party of six queueing for a 5v5 either splits a team across two matches or
            // silently drops someone; refusing the sixth invitation is better than both.
            GameModeDefinition tdm = Mode(StarterContent.Modes.TeamDeathmatch);
            var graph = new SocialGraph();
            var party = new Party(A);

            var joined = new List<string> { A };
            for (int i = 0; i < 10; i++)
            {
                string invitee = $"acct.p{i}";
                if (party.Invite(A, invitee, graph, tdm) != SocialResult.Ok) continue;
                party.AcceptInvite(invitee, graph, tdm);
                joined.Add(invitee);
            }

            Assert.Equal(Party.MaxSizeFor(tdm), party.Size);
            Assert.True(party.Size <= tdm.TeamSize);
        }

        [Fact]
        public void LeadershipMigratesWhenTheLeaderLeaves()
        {
            // A leaderless party cannot invite, queue or disband, and the members cannot tell
            // why — it simply stops working.
            var graph = new SocialGraph();
            var party = new Party(A);
            party.Invite(A, B, graph);
            party.AcceptInvite(B, graph);
            party.Invite(A, C, graph);
            party.AcceptInvite(C, graph);

            Assert.Equal(SocialResult.Ok, party.Leave(A));
            Assert.Equal(B, party.Leader);
            Assert.Equal(2, party.Size);

            party.Leave(B);
            Assert.Equal(C, party.Leader);

            party.Leave(C);
            Assert.True(party.IsEmpty);
            Assert.Null(party.Leader);
        }

        [Fact]
        public void OnlyTheLeaderKicksAndNotThemselves()
        {
            var graph = new SocialGraph();
            var party = new Party(A);
            party.Invite(A, B, graph);
            party.AcceptInvite(B, graph);

            Assert.Equal(SocialResult.NotFound, party.Kick(B, A));
            Assert.Equal(SocialResult.Self, party.Kick(A, A));
            Assert.Equal(SocialResult.Ok, party.Kick(A, B));
            Assert.False(party.Contains(B));
        }

        [Fact]
        public void APartyQueuesOnlyWhenEveryoneIsReady()
        {
            GameModeDefinition tdm = Mode(StarterContent.Modes.TeamDeathmatch);
            var graph = new SocialGraph();
            var party = new Party(A);
            party.Invite(A, B, graph);
            party.AcceptInvite(B, graph);

            Assert.False(party.CanQueueFor(tdm, out string reason));
            Assert.Equal("party.error.not_everyone_ready", reason);

            party.SetReady(A, true);
            Assert.False(party.CanQueueFor(tdm, out _));

            party.SetReady(B, true);
            Assert.True(party.CanQueueFor(tdm, out _));

            // Someone un-readying takes the party back out of the queue.
            party.SetReady(B, false);
            Assert.False(party.CanQueueFor(tdm, out _));
        }

        [Fact]
        public void LeavingClearsAReadyFlagSoItCannotHauntTheParty()
        {
            var graph = new SocialGraph();
            var party = new Party(A);
            party.Invite(A, B, graph);
            party.AcceptInvite(B, graph);
            party.SetReady(A, true);
            party.SetReady(B, true);
            party.Leave(B);

            Assert.False(party.IsReady(B));
            Assert.True(party.EveryoneReady());
        }

        [Fact]
        public void AFreeForAllStillAllowsAParty()
        {
            // Team size one, but a group who want to be in the same match while trying to kill
            // each other is a perfectly reasonable thing to want.
            GameModeDefinition ffa = Mode(StarterContent.Modes.FreeForAll);
            Assert.True(Party.MaxSizeFor(ffa) > 1);
        }

        [Fact]
        public void AnObjectiveModePartyIsCappedAtItsTeamSize()
        {
            GameModeDefinition overload = Mode(StarterContent.Modes.Overload);
            Assert.Equal(System.Math.Min(Party.AbsoluteMaxSize, overload.TeamSize),
                         Party.MaxSizeFor(overload));
        }
    }
}
