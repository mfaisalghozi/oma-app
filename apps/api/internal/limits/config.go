package limits

import (
	"errors"
	"oma/apps/api/internal/platform/httpapi"
	"strings"
)

type Config struct {
	Environment           string
	DevelopmentPROUserIDs []string
}
type Service struct{ pro map[string]bool }

func NewService(cfg Config) (*Service, error) {
	s := &Service{pro: make(map[string]bool)}
	if len(cfg.DevelopmentPROUserIDs) > 0 {
		switch cfg.Environment {
		case "development", "local", "test":
		default:
			return nil, errors.New("development PRO requires explicit development, local, or test environment")
		}
	}
	for _, id := range cfg.DevelopmentPROUserIDs {
		if !httpapi.ValidID(id) {
			return nil, errors.New("development PRO allowlist requires UUIDs")
		}
		s.pro[strings.ToLower(id)] = true
	}
	return s, nil
}

func ConfigFromEnvironment(getenv func(string) string) Config {
	cfg := Config{Environment: getenv("APP_ENV")}
	if raw := getenv("DEVELOPMENT_PRO_USER_IDS"); raw != "" {
		cfg.DevelopmentPROUserIDs = strings.Split(raw, ",")
	}
	return cfg
}
