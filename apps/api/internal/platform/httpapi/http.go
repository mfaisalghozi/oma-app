package httpapi

import (
	"encoding/json"
	"io"
	"net/http"
	"regexp"
)

type FieldError struct {
	Field  string `json:"field"`
	Reason string `json:"reason"`
}
type Error struct {
	Status  int          `json:"-"`
	Code    string       `json:"code"`
	Message string       `json:"message"`
	Details []FieldError `json:"details"`
}

func (e *Error) Error() string { return e.Code }
func Fail(w http.ResponseWriter, status int, code string) {
	Write(w, status, map[string]any{"error": Error{Status: status, Code: code, Message: http.StatusText(status), Details: []FieldError{}}})
}
func Validation(w http.ResponseWriter, code string, details []FieldError) {
	Write(w, 422, map[string]any{"error": Error{Code: code, Message: "Please check the submitted information.", Details: details}})
}
func Write(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
func Data(w http.ResponseWriter, status int, v any) { Write(w, status, map[string]any{"data": v}) }
func Decode(w http.ResponseWriter, r *http.Request, v any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, 64<<10)
	d := json.NewDecoder(r.Body)
	d.DisallowUnknownFields()
	if err := d.Decode(v); err != nil {
		Fail(w, 400, "INVALID_REQUEST")
		return false
	}
	if err := d.Decode(new(any)); err != io.EOF {
		Fail(w, 400, "INVALID_REQUEST")
		return false
	}
	return true
}

var uuidPattern = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)

func ValidID(id string) bool { return uuidPattern.MatchString(id) }
