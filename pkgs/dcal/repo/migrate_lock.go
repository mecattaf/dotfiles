package repo

import (
	"context"
	"errors"
	"fmt"
	"os"
	"time"

	"golang.org/x/sys/unix"
)

const migrationLockRetry = 10 * time.Millisecond

// acquireMigrationLock serializes the complete open-and-migrate path across
// processes. The lock file is intentionally left beside the database: unlinking
// it could let a new opener lock a different inode while an existing migration
// still holds the old one.
func acquireMigrationLock(ctx context.Context, path string) (*os.File, error) {
	file, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return nil, fmt.Errorf("open migration lock %q: %w", path, err)
	}

	ticker := time.NewTicker(migrationLockRetry)
	defer ticker.Stop()
	for {
		err = unix.Flock(int(file.Fd()), unix.LOCK_EX|unix.LOCK_NB)
		switch {
		case err == nil:
			return file, nil
		case !errors.Is(err, unix.EWOULDBLOCK):
			_ = file.Close()
			return nil, fmt.Errorf("lock migrations at %q: %w", path, err)
		}

		select {
		case <-ctx.Done():
			_ = file.Close()
			return nil, fmt.Errorf("wait for migration lock %q: %w", path, ctx.Err())
		case <-ticker.C:
		}
	}
}

func releaseMigrationLock(file *os.File) error {
	unlockErr := unix.Flock(int(file.Fd()), unix.LOCK_UN)
	closeErr := file.Close()
	return errors.Join(unlockErr, closeErr)
}
