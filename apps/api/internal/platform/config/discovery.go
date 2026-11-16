package config

import (
	"encoding/json"
	"fmt"
	"io"
	"oma/apps/api/internal/discovery"
	"os"
)

func LoadDiscovery(path string) (discovery.Policy, error) {
	var p discovery.Policy
	if path == "" {
		return p, nil
	}
	f, err := os.Open(path)
	if err != nil {
		return p, err
	}
	defer f.Close()
	d := json.NewDecoder(io.LimitReader(f, 64*1024))
	d.DisallowUnknownFields()
	if err = d.Decode(&p); err != nil {
		return p, fmt.Errorf("invalid discovery configuration: %w", err)
	}
	if err = d.Decode(new(any)); err != io.EOF {
		return p, fmt.Errorf("discovery configuration has trailing content")
	}
	return p, p.Validate()
}
