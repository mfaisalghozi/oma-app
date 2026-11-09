#!/usr/bin/env python3
"""Mock OMA API for local mobile runs.

Serves the endpoints the Flutter app calls under /v1, so the app can be walked
end to end before apps/api has handlers. Run `python tools/scripts/mock_api.py`
and point API_BASE_URL at it; the Android emulator reaches host loopback at
http://10.0.2.2:8080.

State is in memory, so restarting resets the onboarding flow. Requests are
logged, which is the quickest way to see what the app actually calls.

Photo bytes are not faked: the app uploads to Supabase Storage with the signed
token, so M09 still fails here. A fake bucket would assert a photo exists that
nobody can read.
"""

from __future__ import annotations

import argparse
import json
import uuid
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

STATE = {
    "user_id": "11111111-2222-3333-4444-555555555555",
    "consents_accepted": False,
    "onboarding_done": False,
    "photos": {},
}

MASTER_DATA = {
    "gender": [
        {"id": "g_f", "label": "Perempuan", "code": "F"},
        {"id": "g_m", "label": "Laki-laki", "code": "M"},
        {"id": "g_x", "label": "Non-biner", "code": "X"},
    ],
    "pronoun": [
        {"id": "p_1", "label": "Dia"},
        {"id": "p_2", "label": "She/Her"},
        {"id": "p_3", "label": "He/Him"},
        {"id": "p_4", "label": "They/Them"},
    ],
    "show_me": [
        {"id": "s_f", "label": "Perempuan"},
        {"id": "s_m", "label": "Laki-laki"},
        {"id": "s_all", "label": "Semua"},
    ],
    "looking_for": [
        {"id": "lf_serious", "label": "Hubungan serius"},
        {"id": "lf_chat", "label": "Teman ngobrol"},
        {"id": "lf_activity", "label": "Teman aktivitas"},
        {"id": "lf_unsure", "label": "Belum tahu"},
    ],
    "university": [
        {"id": "u_ui", "name": "Universitas Indonesia"},
        {"id": "u_itb", "name": "Institut Teknologi Bandung"},
        {"id": "u_ugm", "name": "Universitas Gadjah Mada"},
        {"id": "u_binus", "name": "Bina Nusantara"},
        {"id": "u_telkom", "name": "Telkom University"},
        {"id": "u_unpad", "name": "Universitas Padjadjaran"},
    ],
    "religion": [
        {"id": "r_islam", "label": "Islam"},
        {"id": "r_kristen", "label": "Kristen"},
        {"id": "r_katolik", "label": "Katolik"},
        {"id": "r_hindu", "label": "Hindu"},
        {"id": "r_buddha", "label": "Buddha"},
        {"id": "r_konghucu", "label": "Konghucu"},
    ],
    "personality": [
        {"id": "pt_intj", "label": "INTJ — Arsitek"},
        {"id": "pt_intp", "label": "INTP — Pemikir"},
        {"id": "pt_entj", "label": "ENTJ — Komandan"},
        {"id": "pt_entp", "label": "ENTP — Debat"},
        {"id": "pt_infj", "label": "INFJ — Advokat"},
        {"id": "pt_infp", "label": "INFP — Mediator"},
        {"id": "pt_enfj", "label": "ENFJ — Protagonis"},
        {"id": "pt_enfp", "label": "ENFP — Juru Kampanye"},
    ],
    "hobby_category": [
        {"id": "hc_sport", "label": "Olahraga"},
        {"id": "hc_art", "label": "Seni"},
        {"id": "hc_music", "label": "Musik"},
        {"id": "hc_food", "label": "Kuliner"},
        {"id": "hc_travel", "label": "Travel"},
        {"id": "hc_tech", "label": "Teknologi"},
    ],
    "hobby": [
        {"id": "h_dive", "label": "Freediving", "category_id": "hc_sport"},
        {"id": "h_run", "label": "Lari pagi", "category_id": "hc_sport"},
        {"id": "h_gym", "label": "Gym", "category_id": "hc_sport"},
        {"id": "h_photo", "label": "Fotografi", "category_id": "hc_art"},
        {"id": "h_draw", "label": "Menggambar", "category_id": "hc_art"},
        {"id": "h_guitar", "label": "Gitar", "category_id": "hc_music"},
        {"id": "h_vinyl", "label": "Koleksi vinyl", "category_id": "hc_music"},
        {"id": "h_coffee", "label": "Kopi manual brew", "category_id": "hc_food"},
        {"id": "h_cook", "label": "Masak", "category_id": "hc_food"},
        {"id": "h_hike", "label": "Hiking", "category_id": "hc_travel"},
        {"id": "h_camp", "label": "Camping", "category_id": "hc_travel"},
        {"id": "h_code", "label": "Side project ngoding", "category_id": "hc_tech"},
        {"id": "h_ai", "label": "Mainan AI agent", "category_id": "hc_tech"},
    ],
}

CONSENT_DOCUMENTS = [
    {
        "type": "terms",
        "title": "Syarat dan Ketentuan",
        "version": "1.0",
        "document_url": "https://oma.app/legal/terms/1.0",
        "required": True,
    },
    {
        "type": "privacy",
        "title": "Kebijakan Privasi",
        "version": "1.0",
        "document_url": "https://oma.app/legal/privacy/1.0",
        "required": True,
    },
    {
        "type": "data_processing",
        "title": "Persetujuan Pengolahan Data",
        "version": "1.0",
        "document_url": "https://oma.app/legal/data-processing/1.0",
        "required": True,
    },
]


def next_action() -> str:
    if not STATE["consents_accepted"]:
        return "accept_consents"
    if not STATE["onboarding_done"]:
        return "complete_onboarding"
    return "discovery"


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args) -> None:
        pass

    def _body(self) -> dict:
        length = int(self.headers.get("Content-Length") or 0)
        if not length:
            return {}
        raw = self.rfile.read(length)
        try:
            parsed = json.loads(raw)
            return parsed if isinstance(parsed, dict) else {"_body": parsed}
        except json.JSONDecodeError:
            return {"_raw": raw.decode("utf-8", "replace")}

    def _send(self, status: int, payload: object) -> None:
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)
        self._log(status)

    def _data(self, payload: object, status: int = 200) -> None:
        self._send(status, {"data": payload})

    def _error(self, status: int, code: str, message: str, details=None) -> None:
        self._send(
            status,
            {"error": {"code": code, "message": message, "details": details or []}},
        )

    def _log(self, status: int) -> None:
        print(
            f"{self.command:6} {self.path:46} -> {status}",
            flush=True,
        )

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "*, Authorization, Idempotency-Key")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self) -> None:
        url = urlparse(self.path)
        path, query = url.path, parse_qs(url.query)

        if path in ("/health", "/v1/health"):
            return self._data({"status": "ok", "mock": True})

        if path == "/v1/consents/documents":
            return self._data(CONSENT_DOCUMENTS)

        if path == "/v1/profile-data":
            return self._master_data(query)

        if path == "/v1/photos":
            return self._data(
                [
                    {"id": pid, "signed_url": f"https://mock.local/photos/{pid}.jpg"}
                    for pid in STATE["photos"]
                ]
            )

        return self._error(404, "NOT_FOUND", f"no mock route for GET {path}")

    def do_POST(self) -> None:
        url = urlparse(self.path)
        path = url.path
        body = self._body()

        if path == "/v1/me/initialize":
            return self._data(
                {
                    "user_id": STATE["user_id"],
                    "account_status": "active",
                    "account_created": True,
                    "onboarding_completed": STATE["onboarding_done"],
                    "next_action": next_action(),
                    "suspended_until": None,
                }
            )

        if path == "/v1/me/consents":
            consents = body.get("consents") or []
            if not isinstance(consents, list) or not consents:
                return self._error(
                    422, "VALIDATION_FAILED", "consents required",
                    [{"field": "consents", "reason": "required"}],
                )
            STATE["consents_accepted"] = True
            return self._data({"accepted": len(consents), "next_action": next_action()})

        if path == "/v1/me/onboarding":
            if not STATE["consents_accepted"]:
                return self._error(
                    403, "CONSENT_REQUIRED", "consents must be accepted first"
                )
            STATE["onboarding_done"] = True
            return self._data(
                {
                    "profile_id": str(uuid.uuid4()),
                    "onboarding_completed": True,
                    "next_action": "discovery",
                }
            )

        if path == "/v1/photos/upload-urls":
            requested = body.get("photos") or []
            if not isinstance(requested, list):
                return self._error(422, "VALIDATION_FAILED", "photos must be a list")
            return self._data([self._slot() for _ in requested])

        if path.startswith("/v1/photos/") and path.endswith("/upload-url"):
            photo_id = path[len("/v1/photos/") : -len("/upload-url")]
            if photo_id not in STATE["photos"]:
                return self._error(404, "NOT_FOUND", "unknown photo")
            return self._data(self._slot(photo_id))

        if path == "/v1/devices":
            return self._data({"registered": True})

        return self._error(404, "NOT_FOUND", f"no mock route for POST {path}")

    def do_DELETE(self) -> None:
        path = urlparse(self.path).path
        if path.startswith("/v1/photos/"):
            photo_id = path[len("/v1/photos/") :]
            STATE["photos"].pop(photo_id, None)
            return self._data({"deleted": True})
        return self._error(404, "NOT_FOUND", f"no mock route for DELETE {path}")

    def _slot(self, photo_id: str | None = None) -> dict:
        pid = photo_id or str(uuid.uuid4())
        path = f"{STATE['user_id']}/{pid}.jpg"
        STATE["photos"].setdefault(pid, {"path": path})
        return {
            "photo_id": pid,
            "bucket": "oma-photos",
            "path": path,
            "upload_token": f"mock-upload-token-{pid}",
            "expires_at": (
                datetime.now(timezone.utc) + timedelta(minutes=10)
            ).isoformat().replace("+00:00", "Z"),
        }

    def _master_data(self, query: dict) -> None:
        kind = (query.get("type") or [""])[0]
        items = MASTER_DATA.get(kind)
        if items is None:
            return self._error(422, "VALIDATION_FAILED", f"unknown type {kind!r}")

        rows = list(items)
        q = (query.get("q") or [""])[0].strip().lower()
        if q:
            rows = [r for r in rows if q in (r.get("label") or r.get("name") or "").lower()]
        category = (query.get("category_id") or [""])[0]
        if category:
            rows = [r for r in rows if r.get("category_id") == category]

        page = int((query.get("page") or ["1"])[0])
        limit = int((query.get("limit") or ["20"])[0])
        start = (page - 1) * limit
        window = rows[start : start + limit]
        total_pages = max(1, (len(rows) + limit - 1) // limit)

        # Small reference lists come without pagination, like the real API.
        if len(rows) <= limit and page == 1:
            return self._data({"items": window})
        return self._data(
            {
                "items": window,
                "pagination": {"page": page, "total_pages": total_pages},
            }
        )


def main() -> None:
    parser = argparse.ArgumentParser(description="Mock OMA API")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8080)
    args = parser.parse_args()

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"mock OMA API on http://{args.host}:{args.port}/v1", flush=True)
    print("emulator: http://10.0.2.2:%d" % args.port, flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("stopped", flush=True)


if __name__ == "__main__":
    main()
