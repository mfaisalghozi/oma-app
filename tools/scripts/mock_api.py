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
import time
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

# Daily grants follow the real rules: 15 likes base plus 15 at full profile
# completion, 3 describe searches free or 20 for PRO. A complete profile is the
# default so the app shows the full 30 the board draws.
USAGE = {
    "pro": False,
    "profile_complete": True,
    "likes": {"limit": 30, "used": 18, "reserved": 0},
    "searches": {"limit": 3, "used": 0, "reserved": 0},
}

WIB = timezone(timedelta(hours=7))


def next_wib_midnight_utc() -> str:
    """Next midnight in Asia/Jakarta, returned in UTC as the API does."""
    now_wib = datetime.now(WIB)
    midnight = (now_wib + timedelta(days=1)).replace(
        hour=0, minute=0, second=0, microsecond=0
    )
    return midnight.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def usage_payload() -> dict:
    likes = USAGE["likes"]
    searches = USAGE["searches"]
    return {
        "bucket": datetime.now(WIB).date().isoformat(),
        "resets_at": next_wib_midnight_utc(),
        "pro": USAGE["pro"],
        "profile_complete": USAGE["profile_complete"],
        "likes": {**likes, "available": max(likes["limit"] - likes["used"], 0)},
        "searches": {
            **searches,
            "available": max(searches["limit"] - searches["used"], 0),
        },
    }

# --- Discovery -------------------------------------------------------------

MALE_NAMES = [
    "Dimas", "Rizky", "Bagas", "Yoga", "Fajar", "Aldi", "Reza", "Hendra",
    "Bima", "Galih", "Satria", "Iqbal", "Farhan", "Andre", "Doni",
]
FEMALE_NAMES = [
    "Ayu", "Sari", "Nadia", "Putri", "Rani", "Maya", "Dewi", "Intan",
    "Citra", "Laras", "Sinta", "Vina", "Ratna", "Dinda", "Kirana",
]
HOBBIES = [
    ("Running", "running"), ("Hiking", "hiking"), ("Coffees", "coffees"),
    ("Photography", "photography"), ("Cooking", "cooking"), ("Reading", "reading"),
    ("Gaming", "gaming"), ("Traveling", "traveling"), ("Music", "music"),
    ("Movies", "movies"),
]
PERSONALITIES = [
    ("ENFP", "enfp"), ("INTJ", "intj"), ("ESTJ", "estj"), ("ISFP", "isfp"),
    ("ENTP", "entp"),
]
RELIGIONS = [
    ("Islam", "islam"), ("Catholic", "catholic"), ("Christian", "christian"),
    ("Hindu", "hindu"), ("Buddhist", "buddhist"),
]
LOOKING_FOR = [
    ("Long-term", "long_term"), ("Dating", "dating"), ("Friendship", "friendship"),
]
CITIES = [("Jakarta", "DKI Jakarta"), ("Bandung", "Jawa Barat")]
AMBITIONS = [
    "Run the Jakarta Marathon under 4 hours",
    "Open a small coffee shop in Bandung",
    "Publish a photo book about Indonesian coasts",
    "Learn to cook one dish from every province",
    "Finish a half ironman before 30",
]
BIOS = [
    "Mostly outside on weekends. Ask me about trails.",
    "Coffee first, plans later.",
    "Here for something real, not a pen pal.",
    "I will beat you at Mario Kart and then buy you dinner.",
    "Quiet until you get me talking about film photography.",
]


def _oid(text: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, f"oma-mock-{text}"))


def _option(pair) -> dict:
    label, code = pair
    return {"id": _oid(f"opt-{code}"), "code": code, "label": label}


def build_candidates() -> list[dict]:
    """30 profiles: two cities, both genders, 4 photos each."""
    cards = []
    for i in range(30):
        female = i % 2 == 1
        name = (FEMALE_NAMES if female else MALE_NAMES)[i // 2 % 15]
        city, _ = CITIES[i % 2]
        hobbies = [HOBBIES[i % len(HOBBIES)], HOBBIES[(i + 3) % len(HOBBIES)]]
        personality = PERSONALITIES[i % len(PERSONALITIES)]
        religion = RELIGIONS[i % len(RELIGIONS)]
        cards.append(
            {
                "id": _oid(f"card-{i}"),
                "display_name": name,
                "age": 21 + (i * 3) % 15,
                "height_cm": 155 + (i * 5) % 40,
                "approx_distance_km": 1 + i % 14,
                "city": city,
                "bio": BIOS[i % len(BIOS)],
                "ambition": AMBITIONS[i % len(AMBITIONS)],
                "occupation": None,
                "education_degree": None,
                "profile_revision": 1,
                "photo_ids": [_oid(f"photo-{i}-{p}") for p in range(4)],
                "hobbies": [_option(h) for h in hobbies],
                "looking_for": [_option(LOOKING_FOR[i % len(LOOKING_FOR)])],
                "personality": _option(personality),
                "religion": _option(religion),
                "university": {
                    "id": _oid(f"uni-{i % 3}"),
                    "name": ["Universitas Indonesia", "ITB", "UGM"][i % 3],
                    "country_code": "ID",
                },
            }
        )
    return cards


CANDIDATES = build_candidates()
CARDS_BY_ID = {c["id"]: c for c in CANDIDATES}

DECK = {
    "context_id": None,
    "expires_at": 0.0,
    "offset": 0,
    "end_reason": None,
    "order": [],
    "delivered": set(),
}
CURSORS: dict[str, int] = {}
DECISIONS: dict[str, dict] = {}
IDEMPOTENCY: dict[str, tuple[int, dict]] = {}
SEARCHES: dict[str, dict] = {}
SUPER_LIKES = {"balance": 0}

PNG_CACHE: dict[tuple, bytes] = {}


def _png(rgb: tuple[int, int, int], width: int = 480, height: int = 640) -> bytes:
    """Solid-colour PNG so cards show a picture without shipping assets."""
    import struct
    import zlib

    key = (rgb, width, height)
    cached = PNG_CACHE.get(key)
    if cached:
        return cached
    row = b"\x00" + bytes(rgb) * width
    raw = row * height

    def chunk(kind: bytes, data: bytes) -> bytes:
        body = struct.pack(">I", len(data)) + kind + data
        return body + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    blob = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(raw, 6))
        + chunk(b"IEND", b"")
    )
    PNG_CACHE[key] = blob
    return blob


def _colour(seed: str) -> tuple[int, int, int]:
    digest = uuid.uuid5(uuid.NAMESPACE_DNS, seed).int
    return (
        40 + digest % 150,
        80 + (digest >> 8) % 140,
        110 + (digest >> 16) % 120,
    )


def wire_card(card: dict, host: str) -> dict:
    return {
        "id": card["id"],
        "display_name": card["display_name"],
        "age": card["age"],
        "height_cm": card["height_cm"],
        "approx_distance_km": card["approx_distance_km"],
        "bio": card["bio"],
        "ambition": card["ambition"],
        "occupation": card["occupation"],
        "education_degree": card["education_degree"],
        "profile_revision": card["profile_revision"],
        "photos": [
            {
                "id": pid,
                "position": pos,
                "read_url": f"http://{host}/static/card/{card['id']}/{pos}.png",
            }
            for pos, pid in enumerate(card["photo_ids"])
        ],
        "hobbies": card["hobbies"],
        "looking_for": card["looking_for"],
        "personality": card["personality"],
        "religion": card["religion"],
        "university": card["university"],
    }


def reset_deck_if_expired(now: float) -> None:
    if DECK["context_id"] is not None and now < DECK["expires_at"]:
        return
    DECK.update(
        context_id=str(uuid.uuid4()),
        expires_at=now + 1800,
        offset=0,
        end_reason=None,
        order=[c["id"] for c in CANDIDATES],
        delivered=set(),
    )
    CURSORS.clear()


def search_status(search: dict, now: float) -> str:
    elapsed = now - search["created_at"]
    terminal = search["terminal_after"]
    if elapsed >= terminal:
        return "failed" if search["scenario"] in ("error", "invalid") else "succeeded"
    span = terminal / 4
    if elapsed < span:
        return "queued"
    if elapsed < span * 2:
        return "parsing"
    if elapsed < span * 3:
        return "retrieving"
    return "ranking"


def search_envelope(search: dict, now: float) -> dict:
    status = search_status(search, now)
    failed = status == "failed"
    return {
        "search_id": search["id"],
        "status": status,
        "criteria": None if status == "queued" else build_criteria(search),
        "error_code": (
            "SEARCH_FAILED"
            if failed and search["scenario"] == "error"
            else "INVALID_SEARCH_QUERY"
            if failed
            else None
        ),
        "created_at": datetime.fromtimestamp(
            search["created_at"], timezone.utc
        ).isoformat().replace("+00:00", "Z"),
        "completed_at": (
            datetime.fromtimestamp(
                search["created_at"] + search["terminal_after"], timezone.utc
            ).isoformat().replace("+00:00", "Z")
            if status in ("succeeded", "failed")
            else None
        ),
        "poll_after_seconds": 2,
        "parser_version": "mock-1",
        "ranking_policy_version": "mock-1",
        "policy_version": "mock-1",
    }


def build_criteria(search: dict) -> dict:
    query = search["query"]
    lowered = query.lower()
    must = []
    nice = []
    not_searchable = []
    if "180" in query:
        must.append({"field": "height_cm", "op": ">=", "value": 180})
    if "male" in lowered or "cowok" in lowered:
        must.append({"field": "gender", "op": "=", "value": "male"})
    if "hiking" in lowered:
        nice.append({"field": "hobbies", "term": "hiking"})
    if search["scenario"] == "hair":
        not_searchable.append(
            {"field": "hair", "term": "brown hair", "reason": "hair is not a profile field"}
        )
    return {
        "version": "v1",
        "original_query": query,
        "rewrite_id": _oid(f"rewrite-{search['id']}"),
        "translation_en": lowered,
        "must": must,
        "nice": nice,
        "not_searchable": not_searchable,
    }


def describe_results(search: dict, host: str) -> dict:
    scenario = search["scenario"]
    rows = []
    if scenario != "none":
        for i, card in enumerate(CANDIDATES[:10]):
            close = scenario == "close" and i >= 5
            rows.append(
                {
                    "candidate": wire_card(card, host),
                    "ordinal": i + 1,
                    "profile_updated": i == 2,
                    "tier": "close" if close else "exact",
                    "matched": 2 if close else len(search["query"].split()) + 2,
                    "total": len(search["query"].split()) + 3,
                    "reason": (
                        "Close on distance and hobbies, misses height"
                        if close
                        else "Matches every criterion you named"
                    ),
                    "violated_criteria": (
                        [{"field": "height_cm", "value": card["height_cm"]}]
                        if close
                        else []
                    ),
                    "criterion_evaluations": [
                        {"field": "height_cm", "mandatory": True, "status": "matched"},
                        {
                            "field": "hobbies",
                            "mandatory": False,
                            "status": "near_miss" if close else "matched",
                            "evidence": card["hobbies"][0]["label"],
                        },
                    ],
                }
            )
    return {
        "search_id": search["id"],
        "criteria": build_criteria(search),
        "parser_version": "mock-1",
        "ranking_policy_version": "mock-1",
        "policy_version": "mock-1",
        "results": rows,
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

    def _send_bytes(self, status: int, blob: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(blob)))
        self.send_header("Cache-Control", "public, max-age=600")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(blob)
        self._log(status)

    def _log(self, status: int) -> None:
        print(
            f"{self.command:6} {self.path:46} -> {status}",
            flush=True,
        )

    def _deck(self) -> None:
        raw = self.headers.get("X-Limit") or "20"
        try:
            limit = max(1, min(int(raw), 20))
        except ValueError:
            return self._error(400, "INVALID_LIMIT", "X-Limit must be an integer 1-20")
        cursor = self.headers.get("X-Cursor")
        now = time.time()
        reset_deck_if_expired(now)
        if cursor:
            start = CURSORS.get(cursor)
            if start is None:
                return self._error(
                    409,
                    "STALE_DISCOVERY_CONTEXT",
                    "cursor does not belong to the open deck",
                )
        else:
            start = DECK["offset"]
        window = DECK["order"][start : start + limit]
        batch = [CARDS_BY_ID[cid] for cid in window if cid not in DECISIONS]
        for card in batch:
            DECK["delivered"].add(card["id"])
        if not cursor:
            DECK["offset"] = start + len(window)
        next_cursor = None
        if start + len(window) < len(DECK["order"]):
            next_cursor = str(uuid.uuid4())
            CURSORS[next_cursor] = start + len(window)
        if not batch:
            DECK["end_reason"] = "candidate_pool_exhausted"
        host = self.headers.get("Host") or "127.0.0.1:8080"
        return self._data(
            {
                "context_id": DECK["context_id"],
                "cards": [wire_card(card, host) for card in batch],
                "next_cursor": next_cursor,
                "deck_expires_at": datetime.fromtimestamp(
                    DECK["expires_at"], timezone.utc
                ).isoformat().replace("+00:00", "Z"),
                "end_reason": DECK["end_reason"],
            }
        )

    def _action(self, body: dict) -> None:
        key = self.headers.get("Idempotency-Key")
        if not key or len(key) > 200:
            return self._error(
                422, "INVALID_IDEMPOTENCY_KEY", "Idempotency-Key is required"
            )
        replay = IDEMPOTENCY.get(key)
        if replay:
            return self._send(replay[0], replay[1])

        candidate_id = body.get("candidate_id")
        kind = body.get("kind")
        context = body.get("context") or {}
        if kind not in ("pass", "like", "super_like"):
            return self._error(
                422, "INVALID_ACTION", "kind must be pass, like or super_like"
            )
        if not candidate_id:
            return self._error(422, "INVALID_ACTION", "candidate_id is required")
        ctx_kind = context.get("kind")
        if ctx_kind == "regular_deck" and context.get("id") != DECK["context_id"]:
            return self._error(
                409, "STALE_DISCOVERY_CONTEXT", "context is not the open deck"
            )
        if ctx_kind == "describe" and context.get("id") not in SEARCHES:
            return self._error(404, "SEARCH_NOT_FOUND", "no such search")
        if ctx_kind not in ("regular_deck", "describe"):
            return self._error(
                422, "INVALID_CONTEXT", "context.kind must be regular_deck or describe"
            )
        if candidate_id not in DECK["delivered"]:
            return self._error(
                404, "UNAVAILABLE_CANDIDATE", "candidate was not delivered"
            )

        existing = DECISIONS.get(candidate_id)
        if existing:
            if existing["action"] != kind:
                return self._error(
                    409, "DECISION_CONFLICT", "candidate already decided differently"
                )
            return self._data(existing)

        likes = USAGE["likes"]
        if kind == "like" and likes["limit"] - likes["used"] <= 0:
            return self._error(429, "LIKE_LIMIT_REACHED", "no likes left today")
        if kind == "super_like" and SUPER_LIKES["balance"] <= 0:
            return self._error(
                429, "SUPER_LIKE_BALANCE_EMPTY", "no super likes available"
            )

        if kind == "like":
            likes["used"] += 1
        if kind == "super_like":
            SUPER_LIKES["balance"] -= 1

        index = DECK["order"].index(candidate_id)
        match = None
        if kind != "pass" and index % 3 == 0:
            match = {
                "id": str(uuid.uuid4()),
                "conversation_status": "pending",
                "conversation_id": None,
            }
        decision = {"action_id": str(uuid.uuid4()), "action": kind, "match": match}
        DECISIONS[candidate_id] = decision
        IDEMPOTENCY[key] = (200, {"data": decision})
        return self._data(decision)

    def _create_search(self, body: dict) -> None:
        key = self.headers.get("Idempotency-Key")
        if not key or len(key) > 200:
            return self._error(
                422, "INVALID_IDEMPOTENCY_KEY", "Idempotency-Key is required"
            )
        replay = IDEMPOTENCY.get(key)
        if replay:
            return self._send(replay[0], replay[1])

        query = parse_qs(urlparse(self.path).query)
        scenario = (query.get("scenario") or [""])[0]
        if scenario == "blocked":
            return self._error(
                503, "DESCRIBE_NOT_CONFIGURED", "describe provider is not configured"
            )
        if scenario == "busy":
            return self._error(409, "SEARCH_IN_PROGRESS", "a search is already running")

        text = body.get("query")
        if not isinstance(text, str) or not 1 <= len(text) <= 500:
            return self._error(
                400, "INVALID_SEARCH_QUERY", "query must be 1-500 characters"
            )
        searches = USAGE["searches"]
        if searches["limit"] - searches["used"] <= 0:
            return self._error(
                429, "SEARCH_QUOTA_EXHAUSTED", "no searches left today"
            )
        searches["used"] += 1

        now = time.time()
        search = {
            "id": str(uuid.uuid4()),
            "query": text,
            "scenario": scenario,
            "created_at": now,
            "terminal_after": 50.0 if scenario == "slow" else 4.0,
        }
        SEARCHES[search["id"]] = search
        payload = {"data": search_envelope(search, now)}
        IDEMPOTENCY[key] = (202, payload)
        return self._send(202, payload)

    def _reset(self) -> None:
        """Mock-only: put the walkthrough back to a fresh day."""
        DECK.update(
            context_id=None, expires_at=0.0, offset=0, end_reason=None,
            order=[], delivered=set(),
        )
        CURSORS.clear()
        DECISIONS.clear()
        IDEMPOTENCY.clear()
        SEARCHES.clear()
        SUPER_LIKES["balance"] = 0
        USAGE.update(
            pro=False,
            profile_complete=True,
            likes={"limit": 30, "used": 18, "reserved": 0},
            searches={"limit": 3, "used": 0, "reserved": 0},
        )
        STATE.update(consents_accepted=False, onboarding_done=False, photos={})
        return self._data({"reset": True})

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

        if path == "/v1/me/usage":
            scenario = (query.get("scenario") or [""])[0]
            if scenario == "error":
                return self._error(
                    503, "SERVICE_UNAVAILABLE", "usage unavailable"
                )
            if scenario == "slow":
                time.sleep(3)
            return self._data(usage_payload())

        if path == "/v1/photos":
            return self._data(
                [
                    {"id": pid, "signed_url": f"https://mock.local/photos/{pid}.jpg"}
                    for pid in STATE["photos"]
                ]
            )

        if path == "/v1/discovery":
            return self._deck()

        if path.startswith("/v1/describe/searches/"):
            rest = path[len("/v1/describe/searches/") :].strip("/").split("/")
            search = SEARCHES.get(rest[0])
            if search is None:
                return self._error(404, "SEARCH_NOT_FOUND", "no such search")
            if len(rest) == 1:
                return self._data(search_envelope(search, time.time()))
            if rest[1] == "results":
                if search_status(search, time.time()) != "succeeded":
                    return self._error(
                        409, "SEARCH_NOT_SUCCESSFUL", "search has not succeeded"
                    )
                return self._data(
                    describe_results(search, self.headers.get("Host") or "127.0.0.1:8080")
                )
            return self._error(404, "NOT_FOUND", f"no mock route for GET {path}")

        if path.startswith("/static/card/"):
            parts = path.strip("/").split("/")
            if len(parts) == 4 and parts[3].endswith(".png"):
                return self._send_bytes(
                    200, _png(_colour(parts[2] + parts[3])), "image/png"
                )
            return self._error(404, "NOT_FOUND", "no such image")

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

        if path == "/v1/discovery/actions":
            return self._action(body)

        if path == "/v1/describe/searches":
            return self._create_search(body)

        if path == "/v1/_mock/reset":
            return self._reset()

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
