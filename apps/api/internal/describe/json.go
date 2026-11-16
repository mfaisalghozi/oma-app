package describe

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
)

func strictShape(raw []byte) error {
	d := json.NewDecoder(bytes.NewReader(raw))
	if err := uniqueValue(d); err != nil {
		return err
	}
	if _, err := d.Token(); err != io.EOF {
		return ErrInvalidCriteria
	}
	var root map[string]json.RawMessage
	if json.Unmarshal(raw, &root) != nil || !exactKeys(root, "version", "rewrite_id", "translation_en", "must", "nice", "not_searchable") {
		return ErrInvalidCriteria
	}
	for _, key := range []string{"must", "nice", "not_searchable"} {
		var entries []map[string]json.RawMessage
		if json.Unmarshal(root[key], &entries) != nil || entries == nil {
			return ErrInvalidCriteria
		}
		for _, e := range entries {
			keys := []string{"field", "operator", "number", "text", "evidence"}
			if key == "not_searchable" {
				keys = []string{"text", "reason"}
			}
			if !exactKeys(e, keys...) {
				return ErrInvalidCriteria
			}
			for k, v := range e {
				if k != "number" && bytes.Equal(bytes.TrimSpace(v), []byte("null")) {
					return ErrInvalidCriteria
				}
			}
		}
	}
	return nil
}
func exactKeys(m map[string]json.RawMessage, keys ...string) bool {
	if len(m) != len(keys) {
		return false
	}
	for _, key := range keys {
		if _, ok := m[key]; !ok {
			return false
		}
	}
	return true
}
func uniqueValue(d *json.Decoder) error {
	t, err := d.Token()
	if err != nil {
		return err
	}
	delim, ok := t.(json.Delim)
	if !ok {
		return nil
	}
	switch delim {
	case '{':
		seen := map[string]bool{}
		for d.More() {
			k, err := d.Token()
			if err != nil {
				return err
			}
			key, ok := k.(string)
			if !ok || seen[key] {
				return ErrInvalidCriteria
			}
			seen[key] = true
			if err := uniqueValue(d); err != nil {
				return err
			}
		}
	case '[':
		for d.More() {
			if err := uniqueValue(d); err != nil {
				return err
			}
		}
	default:
		return fmt.Errorf("invalid JSON delimiter")
	}
	_, err = d.Token()
	return err
}
