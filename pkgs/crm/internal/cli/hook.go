package cli

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"os"
	"os/exec"
	"strings"
	"time"

	crmformat "github.com/mecattaf/crm/internal/format"
	"github.com/spf13/cobra"
)

const (
	postWriteEntityAnnotation = "crm.mecattaf.dev/post-write-entity"
	postWriteTimeout          = 30 * time.Second
)

type postWriteContextKey struct{}

type postWriteMutation struct {
	verb    string
	entity  string
	refs    []string
	records []any
}

type postWritePayload struct {
	Event   string   `json:"event"`
	Verb    string   `json:"verb"`
	Entity  string   `json:"entity"`
	Refs    []string `json:"refs"`
	Records []any    `json:"records"`
	DBPath  string   `json:"db_path"`
}

func markPostWrite(command *cobra.Command, entity string) {
	if command.Annotations == nil {
		command.Annotations = make(map[string]string)
	}
	command.Annotations[postWriteEntityAnnotation] = entity
}

func recordPostWriteRows(command *cobra.Command, rows []crmformat.Row) {
	entity := command.Annotations[postWriteEntityAnnotation]
	if entity == "" {
		return
	}

	refs := make([]string, 0, len(rows))
	records := make([]any, 0, len(rows))
	for _, row := range rows {
		if row.Ref != "" {
			refs = append(refs, row.Ref)
		}
		records = append(records, row.JSON)
	}
	recordPostWrite(command, command.Name(), entity, refs, records)
}

func recordPostWrite(
	command *cobra.Command,
	verb string,
	entity string,
	refs []string,
	records []any,
) {
	if refs == nil {
		refs = []string{}
	}
	if records == nil {
		records = []any{}
	}
	mutation := postWriteMutation{
		verb:    verb,
		entity:  entity,
		refs:    refs,
		records: records,
	}
	command.SetContext(context.WithValue(command.Context(), postWriteContextKey{}, mutation))
}

func runPostWriteHook(command *cobra.Command, root *rootOptions) {
	configured := strings.TrimSpace(os.Getenv("CRM_POST_WRITE_HOOK"))
	if configured == "" {
		return
	}
	mutation, ok := command.Context().Value(postWriteContextKey{}).(postWriteMutation)
	if !ok {
		return
	}
	paths, err := root.resolvePaths()
	if err != nil {
		return
	}
	payload, err := json.Marshal(postWritePayload{
		Event:   "post-write",
		Verb:    mutation.verb,
		Entity:  mutation.entity,
		Refs:    mutation.refs,
		Records: mutation.records,
		DBPath:  paths.database,
	})
	if err != nil {
		return
	}

	hookContext, cancel := context.WithTimeout(command.Context(), postWriteTimeout)
	defer cancel()
	hook := exec.CommandContext(hookContext, "sh", "-c", configured)
	hook.Stdin = bytes.NewReader(payload)
	hook.Stdout = io.Discard
	hook.Stderr = command.ErrOrStderr()
	_ = hook.Run()
}
