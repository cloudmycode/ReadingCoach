package migrations

import _ "embed"

// ReadingSchema is shared by startup and integration tests; the SQL migration is the source of truth.
//
//go:embed migrations/20260920_add_reading_challenges.sql
var ReadingSchema string
