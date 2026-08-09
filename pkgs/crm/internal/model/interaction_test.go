package model_test

import (
	"testing"

	"github.com/mecattaf/crm/internal/model"
)

func TestInteractionKindValidationUsesTheSharedSlice(t *testing.T) {
	t.Parallel()

	want := []string{"call", "meeting", "email", "message", "note"}
	if len(model.InteractionKinds) != len(want) {
		t.Fatalf("interaction kinds = %v, want %v", model.InteractionKinds, want)
	}
	for index, kind := range want {
		if model.InteractionKinds[index] != kind {
			t.Fatalf("interaction kinds = %v, want %v", model.InteractionKinds, want)
		}
		if !model.ValidInteractionKind(kind) {
			t.Fatalf("ValidInteractionKind(%q) = false", kind)
		}
	}
	if model.ValidInteractionKind("zoom") {
		t.Fatal("ValidInteractionKind(\"zoom\") = true")
	}
}
