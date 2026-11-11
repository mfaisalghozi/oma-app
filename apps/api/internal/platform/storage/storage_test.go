package storage_test

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"oma/apps/api/internal/platform/storage"
	"strings"
	"testing"
	"time"
)

func TestSupabaseStorageCapabilitiesAndObjectMetadata(t *testing.T) {
	expiry := time.Now().Add(2 * time.Hour).Unix()
	claims, _ := json.Marshal(map[string]any{"exp": expiry})
	token := "header." + base64.RawURLEncoding.EncodeToString(claims) + ".signature"
	path := "11111111-1111-4111-8111-111111111111/33333333-3333-4333-8333-333333333333.jpg"
	service := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer server-only" || r.Header.Get("apikey") != "server-only" {
			t.Error("backend credential missing")
			w.WriteHeader(401)
			return
		}
		switch {
		case r.URL.Path == "/storage/v1/bucket/profile-photos":
			json.NewEncoder(w).Encode(map[string]any{"public": false, "file_size_limit": 10485760, "allowed_mime_types": []string{"image/jpeg", "image/png", "image/webp"}})
		case r.URL.Path == "/storage/v1/object/upload/sign/profile-photos/"+path:
			if r.Header.Get("x-upsert") != "false" {
				t.Error("upload can overwrite existing object")
			}
			json.NewEncoder(w).Encode(map[string]string{"url": "/object/upload/sign/profile-photos/" + path + "?token=" + token})
		case r.URL.Path == "/storage/v1/object/sign/profile-photos/"+path:
			var body struct {
				ExpiresIn int `json:"expiresIn"`
			}
			json.NewDecoder(r.Body).Decode(&body)
			if body.ExpiresIn != 300 {
				t.Error("unexpected read URL lifetime")
			}
			json.NewEncoder(w).Encode(map[string]string{"signedURL": "/object/sign/profile-photos/" + path + "?token=read"})
		case r.URL.Path == "/storage/v1/object/info/profile-photos/"+path:
			json.NewEncoder(w).Encode(map[string]any{"metadata": map[string]any{"size": 1000, "mimetype": "image/jpeg"}})
		default:
			w.WriteHeader(404)
		}
	}))
	defer service.Close()
	client, err := storage.NewSupabase(service.URL, "server-only")
	if err != nil {
		t.Fatal(err)
	}
	if err = client.CheckBucket(context.Background()); err != nil {
		t.Fatal(err)
	}
	upload, err := client.CreateUpload(context.Background(), path)
	if err != nil || upload.Token != token || upload.ExpiresAt.Unix() != expiry {
		t.Fatalf("capability mismatch: %v", err)
	}
	signed, err := client.SignRead(context.Background(), path)
	if err != nil || !strings.HasPrefix(signed, service.URL+"/storage/v1/object/sign/") {
		t.Fatalf("read URL mismatch: %v", err)
	}
	info, err := client.ObjectInfo(context.Background(), path)
	if err != nil || info.Size != 1000 || info.ContentType != "image/jpeg" {
		t.Fatalf("metadata mismatch: %#v %v", info, err)
	}
	if _, err = client.ObjectInfo(context.Background(), "missing"); err != storage.ErrNotFound {
		t.Fatalf("missing object not distinguished: %v", err)
	}
}
func TestSupabaseStorageRejectsUnsafeBucketConfiguration(t *testing.T) {
	service := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]any{"public": true, "file_size_limit": 10485760, "allowed_mime_types": []string{"image/jpeg"}})
	}))
	defer service.Close()
	client, err := storage.NewSupabase(service.URL, "server-only")
	if err != nil {
		t.Fatal(err)
	}
	if err = client.CheckBucket(context.Background()); err == nil {
		t.Fatal("public bucket accepted")
	}
}
