package guiyang

import (
	"bytes"
	"testing"
)

func TestSubmittedReactionOptionsDisappearAndRejectedResponsesPreserveState(t *testing.T) {
	g := priorityReactionFixture("ming_gang")
	if err := g.Apply(1, "pass", 0); err != nil {
		t.Fatal(err)
	}
	if g.Phase != PhaseReaction || len(g.Options(1)) != 0 {
		t.Fatal("submitted seat must immediately lose its buttons while other seats are still responding")
	}
	if options, ok := g.SnapshotFor(1)["options"].([]ActionOption); !ok || len(options) != 0 {
		t.Fatal("private snapshot must serialize an empty option list for the submitted seat")
	}
	if len(g.Options(2)) != 2 || g.Options(2)[1].Type != "ming_gang" || g.Options(2)[1].TileID != 0 {
		t.Fatal("unsubmitted claimant must retain its canonical zero-ID discard-kong option")
	}
	before, err := g.MarshalCheckpoint()
	if err != nil {
		t.Fatal(err)
	}
	for _, command := range []struct {
		seat int
		kind string
	}{{1, "hu"}, {1, "pass"}, {0, "ming_gang"}, {0, "hu"}, {2, "an_gang"}, {2, "bu_gang"}, {2, "gang"}} {
		if err := g.Apply(command.seat, command.kind, 0); err == nil {
			t.Fatalf("duplicate, ineligible, or wrong-phase command was accepted: %+v", command)
		}
		after, err := g.MarshalCheckpoint()
		if err != nil {
			t.Fatal(err)
		}
		if !bytes.Equal(before, after) {
			t.Fatalf("rejected command changed epoch, hand, submitted choices, or scores: %+v", command)
		}
	}
}
