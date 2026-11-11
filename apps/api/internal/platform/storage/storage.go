package storage

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const MaxPhotoSize int64 = 10 * 1024 * 1024

var ErrNotFound = errors.New("storage object not found")
var ErrUnavailable = errors.New("storage unavailable")

type Upload struct {
	PhotoID   string    `json:"photo_id"`
	Bucket    string    `json:"bucket"`
	Path      string    `json:"path"`
	Token     string    `json:"upload_token"`
	ExpiresAt time.Time `json:"expires_at"`
}
type Info struct {
	Size        int64
	ContentType string
}
type Store interface {
	CreateUpload(context.Context, string) (Upload, error)
	SignRead(context.Context, string) (string, error)
	ObjectInfo(context.Context, string) (Info, error)
	Remove(context.Context, string) error
}
type Unavailable struct{}

func (Unavailable) CreateUpload(context.Context, string) (Upload, error) {
	return Upload{}, ErrUnavailable
}
func (Unavailable) SignRead(context.Context, string) (string, error) { return "", ErrUnavailable }
func (Unavailable) ObjectInfo(context.Context, string) (Info, error) { return Info{}, ErrUnavailable }
func (Unavailable) Remove(context.Context, string) error             { return ErrUnavailable }

type Supabase struct {
	base, key, bucket string
	client            *http.Client
}

func NewSupabase(projectURL, key string) (*Supabase, error) {
	u, err := url.Parse(projectURL)
	if err != nil || u.Host == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" || u.Path != "" && u.Path != "/" || u.Scheme != "https" && (u.Scheme != "http" || u.Hostname() != "127.0.0.1") {
		return nil, errors.New("invalid Supabase URL")
	}
	if key == "" {
		return nil, errors.New("SUPABASE_SERVICE_ROLE_KEY is required")
	}
	return &Supabase{base: strings.TrimRight(projectURL, "/") + "/storage/v1", key: key, bucket: "profile-photos", client: &http.Client{Timeout: 5 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}}, nil
}
func (s *Supabase) request(ctx context.Context, method, path string, body, out any) error {
	var payload io.Reader
	if body != nil {
		data, err := json.Marshal(body)
		if err != nil {
			return ErrUnavailable
		}
		payload = bytes.NewReader(data)
	}
	req, err := http.NewRequestWithContext(ctx, method, s.base+path, payload)
	if err != nil {
		return ErrUnavailable
	}
	req.Header.Set("Authorization", "Bearer "+s.key)
	req.Header.Set("apikey", s.key)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-upsert", "false")
	res, err := s.client.Do(req)
	if err != nil {
		return ErrUnavailable
	}
	defer res.Body.Close()
	if res.StatusCode == 404 {
		return ErrNotFound
	}
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		return ErrUnavailable
	}
	if out != nil {
		if err = json.NewDecoder(io.LimitReader(res.Body, 1<<20)).Decode(out); err != nil {
			return ErrUnavailable
		}
	}
	return nil
}

// CheckBucket prevents minting capabilities for a public or unrestricted bucket.
func (s *Supabase) CheckBucket(ctx context.Context) error {
	var bucket struct {
		Public bool     `json:"public"`
		Size   int64    `json:"file_size_limit"`
		Types  []string `json:"allowed_mime_types"`
	}
	if err := s.request(ctx, "GET", "/bucket/"+s.bucket, nil, &bucket); err != nil {
		return err
	}
	if bucket.Public || bucket.Size <= 0 || bucket.Size > MaxPhotoSize || len(bucket.Types) == 0 {
		return errors.New("profile bucket must be private with image type and size restrictions")
	}
	for _, t := range bucket.Types {
		if Extension(t) == "" {
			return errors.New("profile bucket allows unsupported content types")
		}
	}
	return nil
}
func Extension(contentType string) string {
	switch contentType {
	case "image/jpeg":
		return ".jpg"
	case "image/png":
		return ".png"
	case "image/webp":
		return ".webp"
	}
	return ""
}
func (s *Supabase) CreateUpload(ctx context.Context, path string) (Upload, error) {
	var out struct {
		URL string `json:"url"`
	}
	if err := s.request(ctx, "POST", "/object/upload/sign/"+s.bucket+"/"+path, map[string]any{}, &out); err != nil {
		return Upload{}, err
	}
	u, err := url.Parse(out.URL)
	if err != nil || u.IsAbs() {
		return Upload{}, ErrUnavailable
	}
	token := u.Query().Get("token")
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return Upload{}, ErrUnavailable
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return Upload{}, ErrUnavailable
	}
	var claims struct {
		Exp int64 `json:"exp"`
	}
	if json.Unmarshal(payload, &claims) != nil || claims.Exp <= time.Now().Unix() {
		return Upload{}, ErrUnavailable
	}
	return Upload{Bucket: s.bucket, Path: path, Token: token, ExpiresAt: time.Unix(claims.Exp, 0).UTC()}, nil
}
func (s *Supabase) SignRead(ctx context.Context, path string) (string, error) {
	var out struct {
		URL string `json:"signedURL"`
	}
	if err := s.request(ctx, "POST", "/object/sign/"+s.bucket+"/"+path, map[string]int{"expiresIn": 300}, &out); err != nil {
		return "", err
	}
	u, err := url.Parse(out.URL)
	if err != nil || u.IsAbs() || !strings.HasPrefix(u.Path, "/object/sign/"+s.bucket+"/") || u.Query().Get("token") == "" {
		return "", ErrUnavailable
	}
	return s.base + out.URL, nil
}
func (s *Supabase) ObjectInfo(ctx context.Context, path string) (Info, error) {
	var out struct {
		Size        int64  `json:"size"`
		ContentType string `json:"content_type"`
		Metadata    struct {
			Size     int64  `json:"size"`
			Mimetype string `json:"mimetype"`
		} `json:"metadata"`
	}
	if err := s.request(ctx, "GET", "/object/info/"+s.bucket+"/"+path, nil, &out); err != nil {
		return Info{}, err
	}
	if out.Size == 0 {
		out.Size = out.Metadata.Size
	}
	if out.ContentType == "" {
		out.ContentType = out.Metadata.Mimetype
	}
	return Info{Size: out.Size, ContentType: out.ContentType}, nil
}
func (s *Supabase) Remove(ctx context.Context, path string) error {
	err := s.request(ctx, "DELETE", "/object/"+s.bucket, map[string]any{"prefixes": []string{path}}, nil)
	if errors.Is(err, ErrNotFound) {
		return nil
	}
	return err
}
