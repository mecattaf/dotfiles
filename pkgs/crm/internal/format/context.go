package format

import (
	"encoding/json"
	"fmt"
	"io"
	"strings"

	"github.com/mecattaf/crm/internal/model"
)

// ContextFormats returns the two serializations supported by crm context.
// Table selects the human briefing document rather than a row table.
func ContextFormats() []Format {
	return []Format{FormatTable, FormatJSON}
}

// WriteBriefing renders one assembled briefing as either a human document or
// its JSON twin. No renderer performs database work.
func WriteBriefing(
	output io.Writer,
	briefing *model.Briefing,
	selected Format,
	pretty bool,
) error {
	if briefing == nil {
		return fmt.Errorf("write context briefing: nil briefing")
	}
	if briefing.Contact == nil && briefing.Org == nil {
		return fmt.Errorf("write context briefing: missing primary subject")
	}

	switch selected {
	case FormatTable:
		return writeBriefingDocument(output, briefing)
	case FormatJSON:
		return writeBriefingJSON(output, briefing, pretty)
	default:
		return fmt.Errorf("write context briefing: unsupported resolved format %q", selected)
	}
}

func writeBriefingJSON(output io.Writer, briefing *model.Briefing, pretty bool) error {
	encoder := json.NewEncoder(output)
	if pretty {
		encoder.SetIndent("", "  ")
	}
	if err := encoder.Encode(briefing); err != nil {
		return fmt.Errorf("write context JSON output: %w", err)
	}

	return nil
}

func writeBriefingDocument(output io.Writer, briefing *model.Briefing) error {
	var document strings.Builder
	if briefing.Contact != nil {
		writeContactProfile(&document, *briefing.Contact)
		if briefing.Org != nil {
			writeOrganizationBlock(&document, *briefing.Org)
		}
	} else {
		writeOrganizationProfile(&document, *briefing.Org)
	}

	writeLinkSection(&document, briefing.Links)
	writeDealSection(&document, briefing.Deals)
	writeTimelineSection(&document, briefing.Timeline, briefing.TimelineTotal)

	if _, err := io.WriteString(output, document.String()); err != nil {
		return fmt.Errorf("write context document: %w", err)
	}

	return nil
}

func writeContactProfile(document *strings.Builder, contact model.Contact) {
	_, _ = fmt.Fprintf(document, "# %s (%s)\n", contact.Name, contact.Reference())
	writeOptionalLine(document, "Relationship", contact.RelationshipHint, "")
	writeOptionalLine(document, "Provenance", contact.ProvenanceSources, "")
	writeOptionalLine(document, "Provenance detail", contact.ProvenanceDetails, "")
	writeOptionalLine(document, "Title", contact.JobTitle, "")
	writeOptionalLine(document, "Email", contact.Email, "")
	writeOptionalLine(document, "Phone", contact.Phone, "")
	if contact.LinkedIn != nil {
		value := "https://www.linkedin.com/in/" + *contact.LinkedIn
		writeLine(document, "LinkedIn", value, "")
	}
	writeOptionalLine(document, "Location", contact.Location, "")
	writeOptionalLine(document, "Archived", contact.ArchivedAt, "")
	writeDossier(document, contact.Context)
}

func writeOrganizationProfile(document *strings.Builder, organization model.Org) {
	_, _ = fmt.Fprintf(document, "# %s (%s)\n", organization.Name, organization.Reference())
	writeOptionalLine(document, "Relationship", organization.RelationshipHint, "")
	writeOptionalLine(document, "Provenance", organization.ProvenanceSources, "")
	writeOptionalLine(document, "Provenance detail", organization.ProvenanceDetails, "")
	writeOrganizationDetails(document, organization, "")
	writeDossier(document, organization.Context)
}

func writeOrganizationBlock(document *strings.Builder, organization model.Org) {
	document.WriteString("\nOrganization:\n")
	_, _ = fmt.Fprintf(document, "  %s (%s)\n", organization.Name, organization.Reference())
	writeOptionalLine(document, "Relationship", organization.RelationshipHint, "  ")
	writeOptionalLine(document, "Provenance", organization.ProvenanceSources, "  ")
	writeOptionalLine(document, "Provenance detail", organization.ProvenanceDetails, "  ")
	writeOrganizationDetails(document, organization, "  ")
	if organization.Context != nil {
		writeLine(document, "Dossier", *organization.Context, "  ")
	}
}

func writeOrganizationDetails(
	document *strings.Builder,
	organization model.Org,
	indent string,
) {
	writeOptionalLine(document, "Category", organization.Category, indent)
	writeOptionalLine(document, "Website", organization.Website, indent)
	if organization.LinkedIn != nil {
		value := "https://www.linkedin.com/company/" + *organization.LinkedIn
		writeLine(document, "LinkedIn", value, indent)
	}
	writeOptionalLine(document, "Location", organization.Location, indent)
	writeOptionalLine(document, "Focus", organization.Focus, indent)
	writeOptionalLine(document, "Archived", organization.ArchivedAt, indent)
}

func writeDossier(document *strings.Builder, dossier *string) {
	if dossier == nil {
		return
	}
	document.WriteString("\nDossier:\n")
	document.WriteString(*dossier)
	document.WriteByte('\n')
}

func writeLinkSection(document *strings.Builder, links []model.ContextLink) {
	if len(links) == 0 {
		return
	}
	_, _ = fmt.Fprintf(document, "\nLinks (%d):\n", len(links))
	for _, link := range links {
		_, _ = fmt.Fprintf(
			document,
			"  %s  %s  %s  %s",
			link.Contact.Reference(),
			link.Contact.Name,
			link.Direction,
			link.Type,
		)
		if link.Note != nil {
			_, _ = fmt.Fprintf(document, " — %s", *link.Note)
		}
		document.WriteByte('\n')
	}
}

func writeDealSection(document *strings.Builder, deals []model.ContextDeal) {
	if len(deals) == 0 {
		return
	}
	_, _ = fmt.Fprintf(document, "\nDeals (%d):\n", len(deals))
	for _, deal := range deals {
		_, _ = fmt.Fprintf(
			document,
			"  %s  %s  %s  %d days in stage\n",
			deal.Ref,
			deal.Title,
			deal.Stage,
			deal.DaysInStage,
		)
	}
}

func writeTimelineSection(
	document *strings.Builder,
	timeline []model.Interaction,
	total int,
) {
	if len(timeline) == 0 {
		return
	}
	_, _ = fmt.Fprintf(document, "\nTimeline (%d):\n", total)
	for _, interaction := range timeline {
		_, _ = fmt.Fprintf(
			document,
			"  %s  %s  %s  %s\n",
			interaction.Reference(),
			interaction.OccurredOn,
			interaction.Kind,
			interaction.Summary,
		)
		if interaction.TranscriptPath != nil {
			_, _ = fmt.Fprintf(document, "    Transcript: %s\n", *interaction.TranscriptPath)
		}
	}
}

func writeOptionalLine(
	document *strings.Builder,
	label string,
	value *string,
	indent string,
) {
	if value == nil {
		return
	}
	writeLine(document, label, *value, indent)
}

func writeLine(document *strings.Builder, label, value, indent string) {
	_, _ = fmt.Fprintf(document, "%s%s: %s\n", indent, label, value)
}
