package cli

import (
	"bytes"
	"context"
	"fmt"
	"os/exec"
	"path/filepath"
	"testing"
	"time"

	"github.com/mecattaf/crm/internal/db"
)

func TestConcurrentLogWriters(t *testing.T) {
	temporaryDirectory := t.TempDir()
	databasePath := filepath.Join(temporaryDirectory, "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)
	stdout, stderr, code = crm(t, databasePath, "contact", "add", "Writer Anchor")
	if stderr != "" || code != 0 {
		t.Fatalf("contact add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}

	// Calibration: the cited busy-timeout precedent found N=20 did not contend
	// reliably, while N=40 consistently produced about four SQLITE_BUSY
	// failures without the timeout. Rechecking this implementation at N=40
	// exposed SQLITE_BUSY in under 50 ms before write transactions acquired
	// their lock through the busy handler. Keep N=40 so this remains a
	// distinguishing contention test rather than a smoke test that serializes.
	const writerCount = 40
	type writerProcess struct {
		command *exec.Cmd
		stdout  bytes.Buffer
		stderr  bytes.Buffer
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	processes := make([]writerProcess, writerCount)
	for index := range processes {
		processes[index].command = exec.CommandContext(
			ctx,
			testBinaryPath,
			"--db", databasePath,
			"log",
			"--with", "c1",
			"--kind", "note",
			"--summary", fmt.Sprintf("parallel writer %02d", index),
		)
		processes[index].command.Stdout = &processes[index].stdout
		processes[index].command.Stderr = &processes[index].stderr
		if err := processes[index].command.Start(); err != nil {
			t.Fatalf("start writer %d: %v", index, err)
		}
	}

	for index := range processes {
		err := processes[index].command.Wait()
		if err != nil {
			t.Fatalf(
				"writer %d failed: %v; stdout=%q stderr=%q",
				index,
				err,
				processes[index].stdout.String(),
				processes[index].stderr.String(),
			)
		}
		if processes[index].stderr.Len() != 0 {
			t.Fatalf("writer %d stderr = %q, want empty", index, processes[index].stderr.String())
		}
	}
	if err := ctx.Err(); err != nil {
		t.Fatalf("concurrent writer deadline: %v", err)
	}

	database, err := db.Open(databasePath)
	if err != nil {
		t.Fatalf("open database after concurrent writes: %v", err)
	}
	var count int
	if err := database.QueryRow("SELECT COUNT(*) FROM interactions").Scan(&count); err != nil {
		_ = database.Close()
		t.Fatalf("count concurrent interactions: %v", err)
	}
	if err := database.Close(); err != nil {
		t.Fatalf("close database after concurrent writes: %v", err)
	}
	if count != writerCount {
		t.Fatalf("interaction count = %d, want %d", count, writerCount)
	}

	assertNoSidecars(t, databasePath)
}
