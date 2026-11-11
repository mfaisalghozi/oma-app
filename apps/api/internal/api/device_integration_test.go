//go:build integration

package api_test

import "testing"

func TestDeviceRegistrationUpsertAndOwnership(t *testing.T) {
	_, h := setup(t)
	call(t, h, "POST", "/v1/me/initialize", "alice", "", 200)
	call(t, h, "POST", "/v1/me/initialize", "bob", "", 200)
	body := `{"token":"device-token-fixture","platform":"android","provider":"fcm"}`
	first := call(t, h, "POST", "/v1/devices", "alice", body, 200)["data"].(map[string]any)
	second := call(t, h, "POST", "/v1/devices", "alice", body, 200)["data"].(map[string]any)
	id := first["device_id"].(string)
	if second["device_id"] != id {
		t.Fatal("duplicate token created a second device")
	}
	call(t, h, "DELETE", "/v1/devices/"+id, "bob", "", 404)
	moved := call(t, h, "POST", "/v1/devices", "bob", body, 200)["data"].(map[string]any)
	if moved["device_id"] != id {
		t.Fatal("token reassignment created a duplicate")
	}
	call(t, h, "DELETE", "/v1/devices/"+id, "alice", "", 404)
	call(t, h, "DELETE", "/v1/devices/"+id, "bob", "", 200)
	call(t, h, "DELETE", "/v1/devices/"+id, "bob", "", 404)
	for _, bad := range []string{`{"token":"x","platform":"web","provider":"fcm"}`, `{"token":"x","platform":"ios","provider":"unknown"}`, `{"token":"","platform":"ios","provider":"apns"}`} {
		call(t, h, "POST", "/v1/devices", "alice", bad, 422)
	}
}
