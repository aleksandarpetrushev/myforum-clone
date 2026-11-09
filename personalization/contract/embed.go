// Package contract holds the JSON Schema for POST /internal/events, the body Rails sends to this service.
// Rails' specs validate every outbox payload against the same files (MF-203).
package contract

import (
	"embed"
	"fmt"
)

// Files holds every version's schema and examples.
//
//go:embed v1/events.schema.json v1/examples/*.json
var Files embed.FS

// SchemaPath returns the embedded path of a version's schema.
func SchemaPath(version int) string {
	return fmt.Sprintf("v%d/events.schema.json", version)
}
