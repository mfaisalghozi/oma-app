# On-device NSFW check: model, threshold and test protocol

Owner: Ghozi. Ticket: ONB-FE-08. Code: `lib/features/photos/`.

## What runs

- Package: `nsfw_detect` **2.8.0** (pinned exactly). Inference is on the
  device; the package sends no telemetry (source read for 2.8.0: the only
  network calls are model downloads).
- Model: OpenNSFW2 (2-class: safe / nudity), ~11 MB.
- We **don't** use the package's built-in download. Its default URLs point
  at the package author's GitHub release and carry no checksum. Instead
  `ModelFetcher` downloads our mirrored copy over HTTPS, checks the SHA-256
  from `NSFW_MODEL_SHA256_*`, and registers it with `registerModel`.
  - Android: `.tflite` file. iOS: `.mlmodel` source file (the package
    compiles it on first load).
- Fails closed: download, checksum, registration or scan errors block the
  upload and M09 shows Try again.
- Suggestive (swimwear, gym, freediving) is allowed on purpose; only
  `nudity` / `explicitNudity` at or above the threshold is blocked.
- This is a client signal only. A modified app can skip it, so backend
  moderation still reviews every photo.

## Before beta (not done yet; needs a real device)

1. Put the model files on our mirror (Supabase Storage public bucket or
   the web CDN), record their SHA-256 in `config/*.json`.
2. Build the fixed test set (keep it outside the repo, it contains nudity):
   - 100 clearly safe profile photos (faces, groups, outdoors)
   - 60 hard-safe photos: swimwear, freediving, gym, beach, shirtless
   - 60 nudity / explicit photos
3. Run the set through the app at thresholds 0.6, 0.7, 0.8, 0.9 and fill
   the table below. Pick the lowest threshold that keeps the hard-safe
   false-positive rate under 5%.
4. Measure scan time on a mid-range Android phone (e.g. Redmi Note class),
   first scan (model load) and warm scans.

| Threshold | False positives (safe) | False positives (hard-safe) | Missed nudity |
| --- | --- | --- | --- |
| 0.6 | | | |
| 0.7 (default) | | | |
| 0.8 | | | |
| 0.9 | | | |

| Device | First scan | Warm scan |
| --- | --- | --- |
| | | |

Change the threshold with `NSFW_THRESHOLD` in the dart-define file; no code
change needed.
