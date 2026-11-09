package contract

import (
	"bytes"
	"fmt"
	"slices"

	"github.com/santhosh-tekuri/jsonschema/v6"
)

// baseURL matches the schemas' $id, so $refs resolve inside the embedded files.
const baseURL = "https://myforum.example/contract/personalization/"

// SupportedVersions is the only list of schema_versions this service accepts: a version missing here is
// answered as unsupported even if its schema is embedded. During a rollout it holds the old and the new
// version (README.md, "Moving to version 2").
var SupportedVersions = []int{1}

// Validator checks a request body against the schema of its own schema_version.
type Validator struct {
	schemas    map[int]*jsonschema.Schema
	eventTypes map[int]map[string]bool
}

// NewValidator compiles every supported version's embedded schema. It fails if a schema does not compile,
// so a broken contract stops the service at startup instead of letting every payload through unchecked.
func NewValidator() (*Validator, error) {
	compiler := jsonschema.NewCompiler()
	compiler.AssertFormat()
	schemas := map[int]*jsonschema.Schema{}
	eventTypes := map[int]map[string]bool{}
	for _, version := range SupportedVersions {
		path := SchemaPath(version)
		raw, err := Files.ReadFile(path)
		if err != nil {
			return nil, fmt.Errorf("read %s: %w", path, err)
		}
		doc, err := jsonschema.UnmarshalJSON(bytes.NewReader(raw))
		if err != nil {
			return nil, fmt.Errorf("parse %s: %w", path, err)
		}
		if err := compiler.AddResource(baseURL+path, doc); err != nil {
			return nil, fmt.Errorf("add %s: %w", path, err)
		}
		schema, err := compiler.Compile(baseURL + path)
		if err != nil {
			return nil, fmt.Errorf("compile %s: %w", path, err)
		}
		schemas[version] = schema
		types, err := eventTypeEnum(doc)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", path, err)
		}
		eventTypes[version] = types
	}
	return &Validator{schemas: schemas, eventTypes: eventTypes}, nil
}

// eventTypeEnum reads properties.event_type.enum, so the schema is the one list of event types.
func eventTypeEnum(doc any) (map[string]bool, error) {
	root, _ := doc.(map[string]any)
	properties, _ := root["properties"].(map[string]any)
	eventType, _ := properties["event_type"].(map[string]any)
	values, _ := eventType["enum"].([]any)
	if len(values) == 0 {
		return nil, fmt.Errorf("no properties.event_type.enum")
	}
	types := map[string]bool{}
	for _, value := range values {
		name, ok := value.(string)
		if !ok {
			return nil, fmt.Errorf("event_type enum holds a non-string %v", value)
		}
		types[name] = true
	}
	return types, nil
}

// EventTypes returns the event types a version's schema lists, sorted.
func (v *Validator) EventTypes(version int) []string {
	types := make([]string, 0, len(v.eventTypes[version]))
	for name := range v.eventTypes[version] {
		types = append(types, name)
	}
	slices.Sort(types)
	return types
}

// Knows reports whether a version's schema lists the event type.
func (v *Validator) Knows(version int, eventType string) bool {
	return v.eventTypes[version][eventType]
}

// Supports reports whether this service can read the given schema_version.
func (v *Validator) Supports(version int) bool {
	_, ok := v.schemas[version]
	return ok
}

// Validate checks a decoded request body (from encoding/json) against the schema of the given version. It
// returns nil when the body is valid, or an error listing every problem.
func (v *Validator) Validate(version int, body any) error {
	schema, ok := v.schemas[version]
	if !ok {
		return fmt.Errorf("unsupported schema_version %d", version)
	}
	return schema.Validate(body)
}
