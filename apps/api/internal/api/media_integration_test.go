//go:build integration

package api_test

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"oma/apps/api/internal/api"
	"oma/apps/api/internal/platform/storage"
	"strings"
	"sync"
	"testing"
	"time"
)

type storageFixture struct {
	mu      sync.Mutex
	objects map[string]storage.Info
	fail    bool
}

func (s *storageFixture) CreateUpload(_ context.Context, path string) (storage.Upload, error) {
	if s.fail {
		return storage.Upload{}, errors.New("storage unavailable")
	}
	return storage.Upload{Bucket: "profile-photos", Path: path, Token: "temporary-capability", ExpiresAt: time.Now().Add(2 * time.Hour)}, nil
}
func (s *storageFixture) SignRead(_ context.Context, path string) (string, error) {
	return "https://storage.example.test/private/" + path + "?token=read-capability", nil
}
func (s *storageFixture) ObjectInfo(_ context.Context, path string) (storage.Info, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	info, ok := s.objects[path]
	if !ok {
		return storage.Info{}, storage.ErrNotFound
	}
	return info, nil
}
func (s *storageFixture) Remove(_ context.Context, path string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.objects, path)
	return nil
}
func mediaSetup(t *testing.T) (http.Handler, *storageFixture) {
	db, _ := setup(t)
	store := &storageFixture{objects: map[string]storage.Info{}}
	return api.NewWithStorage(db, identityFixture{}, store), store
}

const uploadOne = `{"photos":[{"filename":"../../someone-else.jpg","content_type":"image/jpeg","file_size":1000}]}`

func TestPhotoReservationQuotaOwnershipAndRefresh(t *testing.T) {
	h, _ := mediaSetup(t)
	call(t, h, "POST", "/v1/me/initialize", "alice", "", 200)
	call(t, h, "POST", "/v1/me/initialize", "bob", "", 200)
	first := call(t, h, "POST", "/v1/photos/upload-urls", "alice", uploadOne, 201)["data"].([]any)[0].(map[string]any)
	id := first["photo_id"].(string)
	if !strings.HasPrefix(first["path"].(string), alice+"/") || strings.Contains(first["path"].(string), "..") {
		t.Fatal("client filename trusted as storage path")
	}
	call(t, h, "POST", "/v1/photos/"+id+"/upload-url", "bob", "", 404)
	call(t, h, "POST", "/v1/photos/"+id+"/upload-url", "alice", "", 200)
	for range 5 {
		call(t, h, "POST", "/v1/photos/upload-urls", "alice", uploadOne, 201)
	}
	out := call(t, h, "POST", "/v1/photos/upload-urls", "alice", uploadOne, 422)
	if out["error"].(map[string]any)["code"] != "PHOTO_LIMIT_EXCEEDED" {
		t.Fatalf("wrong quota error: %#v", out)
	}
	call(t, h, "DELETE", "/v1/photos/"+id, "bob", "", 404)
	call(t, h, "DELETE", "/v1/photos/"+id, "alice", "", 200)
	call(t, h, "POST", "/v1/photos/"+id+"/upload-url", "alice", "", 404)
	call(t, h, "POST", "/v1/photos/upload-urls", "alice", uploadOne, 201)
	for _, body := range []string{`{"photos":[{"content_type":"image/gif","file_size":1000}]}`, `{"photos":[{"content_type":"image/png","file_size":10485761}]}`, `{"photos":[]}`} {
		call(t, h, "POST", "/v1/photos/upload-urls", "alice", body, 422)
	}
}

func TestPhotoStorageFailureDoesNotConsumeQuota(t *testing.T) {
	h, store := mediaSetup(t)
	call(t, h, "POST", "/v1/me/initialize", "alice", "", 200)
	store.fail = true
	call(t, h, "POST", "/v1/photos/upload-urls", "alice", uploadOne, 503)
	store.fail = false
	for range 6 {
		call(t, h, "POST", "/v1/photos/upload-urls", "alice", uploadOne, 201)
	}
}

func TestPhotoOrderingPrimaryAndOwnership(t *testing.T) {
	db, _ := setup(t)
	store := &storageFixture{objects: map[string]storage.Info{}}
	h := api.NewWithStorage(db, identityFixture{}, store)
	call(t, h, "POST", "/v1/me/initialize", "alice", "", 200)
	call(t, h, "POST", "/v1/me/initialize", "bob", "", 200)
	ids := []string{}
	for range 2 {
		p := call(t, h, "POST", "/v1/photos/upload-urls", "alice", uploadOne, 201)["data"].([]any)[0].(map[string]any)
		ids = append(ids, p["photo_id"].(string))
	}
	for i, id := range ids {
		if _, err := db.Exec(`UPDATE photos SET status='active',position=$1,is_primary=$2 WHERE id=$3`, i+1, i == 0, id); err != nil {
			t.Fatal(err)
		}
	}
	call(t, h, "PATCH", "/v1/photos/"+ids[1], "bob", `{"is_primary":true}`, 404)
	call(t, h, "PATCH", "/v1/photos/"+ids[1], "alice", `{"position":1,"is_primary":true}`, 200)
	photos := call(t, h, "GET", "/v1/photos", "alice", "", 200)["data"].([]any)
	primary := 0
	positions := map[float64]bool{}
	for _, item := range photos {
		p := item.(map[string]any)
		if p["is_primary"] == true {
			primary++
		}
		position := p["position"].(float64)
		if positions[position] {
			t.Fatal("duplicate position")
		}
		positions[position] = true
		if p["signed_url"] == nil {
			t.Fatal("active photo missing read URL")
		}
	}
	if primary != 1 {
		t.Fatalf("primary count %d", primary)
	}
	call(t, h, "DELETE", "/v1/photos/"+ids[1], "alice", "", 200)
	remaining := call(t, h, "GET", "/v1/photos", "alice", "", 200)["data"].([]any)
	if len(remaining) != 1 || remaining[0].(map[string]any)["is_primary"] != true {
		t.Fatal("primary not reassigned after deletion")
	}
}

func TestConcurrentPhotoReservationsRespectQuota(t *testing.T) {
	h, _ := mediaSetup(t)
	call(t, h, "POST", "/v1/me/initialize", "alice", "", 200)
	photo := `{"content_type":"image/png","file_size":1000}`
	body := `{"photos":[` + strings.Join([]string{photo, photo, photo, photo}, ",") + `]}`
	results := make(chan int, 2)
	var wg sync.WaitGroup
	for range 2 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			req := httptest.NewRequest("POST", "/v1/photos/upload-urls", strings.NewReader(body))
			req.Header.Set("Authorization", "Bearer alice")
			w := httptest.NewRecorder()
			h.ServeHTTP(w, req)
			results <- w.Code
		}()
	}
	wg.Wait()
	close(results)
	counts := map[int]int{}
	for status := range results {
		counts[status]++
	}
	if counts[201] != 1 || counts[422] != 1 {
		t.Fatalf("quota race: %#v", counts)
	}
}

func TestClearingNonPrimaryPhotoPreservesExistingPrimary(t *testing.T) {
	db, _ := setup(t)
	store := &storageFixture{objects: map[string]storage.Info{}}
	h := api.NewWithStorage(db, identityFixture{}, store)
	call(t, h, "POST", "/v1/me/initialize", "alice", "", 200)
	ids := []string{}
	for i := range 3 {
		p := call(t, h, "POST", "/v1/photos/upload-urls", "alice", uploadOne, 201)["data"].([]any)[0].(map[string]any)
		id := p["photo_id"].(string)
		ids = append(ids, id)
		if _, err := db.Exec(`UPDATE photos SET status='active',position=$1,is_primary=$2 WHERE id=$3`, i+1, i == 2, id); err != nil {
			t.Fatal(err)
		}
	}
	call(t, h, "PATCH", "/v1/photos/"+ids[1], "alice", `{"is_primary":false}`, 200)
	out := call(t, h, "GET", "/v1/photos", "alice", "", 200)["data"].([]any)
	for _, row := range out {
		p := row.(map[string]any)
		if p["is_primary"] != (p["id"] == ids[2]) {
			t.Fatalf("primary changed: %#v", out)
		}
	}
}
