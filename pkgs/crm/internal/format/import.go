package format

import (
	"fmt"
	"io"

	"github.com/mecattaf/crm/internal/model"
)

// WriteImportPlan renders the deterministic row decisions made by a dry run.
func WriteImportPlan(output io.Writer, actions []model.ImportAction) error {
	for _, action := range actions {
		if _, err := fmt.Fprintf(
			output,
			"%s %s %s %q\n",
			action.Operation,
			action.Entity,
			action.Ref,
			action.Name,
		); err != nil {
			return fmt.Errorf("write import plan: %w", err)
		}
	}

	return nil
}
