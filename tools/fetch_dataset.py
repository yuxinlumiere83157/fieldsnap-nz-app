#!/usr/bin/env python3
"""1A step 1 — fetch observation-level image candidates under the CC0/CC BY policy.

Policy enforced here (decided by the project owner, 2026-09-11):
  * accepted photo licences: CC0 and CC BY (cc-by); CC BY-SA is *not* fetched by
    default, CC BY-NC is excluded entirely;
  * the licence is read per PHOTO (`photo.license_code`), never from the observation;
  * one class = one internal slug, with all taxon synonyms mapping to it;
  * images are downloaded with the observation id attached, so the train/val/test
    split can be grouped by observation and cannot leak near-duplicate frames.

Politeness: cached API responses, ~1 request/second, retries with backoff, a
descriptive User-Agent. `--offline` re-uses the cache and never touches the network.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import pathlib
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

REPO = pathlib.Path(__file__).resolve().parents[1]  # tools/ -> repository root
DATA = REPO / "data"
RAW = DATA / "raw"
CACHE = DATA / "cache"
MANIFEST = DATA / "manifest.csv"

USER_AGENT = (
    "FieldSnapNZ-the course/0.2 (student feasibility study; "
    "contact: the repository owner (contact via the repository))"
)
API = "https://api.inaturalist.org/v1/observations"
PLACE_NZ = 6803  # verified: 6803 = New Zealand, 7143 = Eswatini
LICENCES = ("cc0", "cc-by")
MIN_REQUEST_INTERVAL_S = 1.1
MAX_FILE_BYTES = 32 * 1024 * 1024  # mirrors the app's import guard

# internal slug -> (group, display name, [accepted names / synonyms to query])
CLASSES: dict[str, tuple[str, str, list[str]]] = {
    "tui": ("bird", "Tūī", ["Prosthemadera novaeseelandiae"]),
    "kereru": ("bird", "Kererū", ["Hemiphaga novaeseelandiae"]),
    "piwakawaka": ("bird", "Pīwakawaka", ["Rhipidura fuliginosa"]),
    "tauhou": ("bird", "Tauhou (silvereye)", ["Zosterops lateralis"]),
    "korimako": ("bird", "Korimako", ["Anthornis melanura"]),
    "house_sparrow": ("bird", "House sparrow", ["Passer domesticus"]),
    "blackbird": ("bird", "Common blackbird", ["Turdus merula"]),
    "song_thrush": ("bird", "Song thrush", ["Turdus philomelos"]),
    "starling": ("bird", "Common starling", ["Sturnus vulgaris"]),
    "common_myna": ("bird", "Common myna", ["Acridotheres tristis"]),
    "pohutukawa": ("plant", "Pōhutukawa", ["Metrosideros excelsa"]),
    "ti_kouka": ("plant", "Tī kōuka (cabbage tree)", ["Cordyline australis"]),
    "harakeke": ("plant", "Harakeke (NZ flax)", ["Phormium tenax"]),
    # Silver fern: one internal class, several accepted names across platforms.
    "silver_fern": (
        "plant",
        "Silver fern",
        ["Cyathea dealbata", "Alsophila tricolor", "Alsophila dealbata"],
    ),
    "nikau": ("plant", "Nīkau", ["Rhopalostylis sapida"]),
    "kowhai": ("plant", "Kōwhai", ["Sophora microphylla"]),
    "tradescantia": ("plant", "Tradescantia", ["Tradescantia fluminensis"]),
    "woolly_nightshade": ("plant", "Woolly nightshade", ["Solanum mauritianum"]),
    "wild_ginger": ("plant", "Wild ginger", ["Hedychium gardnerianum"]),
    "moth_plant": ("plant", "Moth plant", ["Araujia sericifera"]),
}

# Privacy: precise and near-precise observation locations (`latitude`, `longitude`,
# `place_guess`) are deliberately NOT recorded. They were never used for training or
# evaluation, and iNaturalist itself obscures coordinates for sensitive taxa, so keeping them
# only creates a publication risk. Locality is not needed to reproduce the data: the photo id
# and the CDN URL identify each image. See docs/data_privacy.md.
MANIFEST_FIELDS = [
    "class_slug", "group", "display_name", "queried_name", "observation_id",
    "photo_id", "license_code", "attribution", "observed_on",
    "taxon_id", "taxon_name", "url_large", "url_original",
    "file_path", "bytes", "md5", "width", "height", "downloaded_at",
]


def log(msg: str) -> None:
    print(msg, flush=True)


_last_request = 0.0


def _throttle() -> None:
    global _last_request
    delta = time.monotonic() - _last_request
    if delta < MIN_REQUEST_INTERVAL_S:
        time.sleep(MIN_REQUEST_INTERVAL_S - delta)
    _last_request = time.monotonic()


def _get_json(url: str, cache_file: pathlib.Path, offline: bool) -> dict:
    if cache_file.exists():
        return json.loads(cache_file.read_text())
    if offline:
        raise RuntimeError(f"offline and no cache for {url}")
    last_error: Exception | None = None
    for attempt in range(4):
        _throttle()
        req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        try:
            with urllib.request.urlopen(req, timeout=60) as response:
                payload = json.load(response)
            cache_file.parent.mkdir(parents=True, exist_ok=True)
            cache_file.write_text(json.dumps(payload))
            return payload
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError) as exc:
            last_error = exc
            time.sleep(2 * (attempt + 1))
    raise RuntimeError(f"request failed after retries: {url}: {last_error}")


def _download(url: str, dest: pathlib.Path, offline: bool) -> bool:
    """Fetch one image from the CDN.

    Image files come from the S3/CDN host, not the API, so the 1 request/second API
    politeness rule does not apply here; a small worker pool is used instead. The API
    calls that discover the photos are still serialised by `_throttle()`.
    """
    if dest.exists() and dest.stat().st_size > 0:
        return True
    if offline:
        return False
    for attempt in range(4):
        req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        try:
            with urllib.request.urlopen(req, timeout=120) as response:
                dest.parent.mkdir(parents=True, exist_ok=True)
                tmp = dest.with_suffix(dest.suffix + ".part")
                with open(tmp, "wb") as fh:
                    while True:
                        chunk = response.read(262144)
                        if not chunk:
                            break
                        fh.write(chunk)
                if tmp.stat().st_size == 0 or tmp.stat().st_size > MAX_FILE_BYTES:
                    tmp.unlink(missing_ok=True)
                    return False
                tmp.rename(dest)
                return True
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError):
            time.sleep(2 * (attempt + 1))
    return False


def _slug_name(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")


def fetch_class(slug: str, target: int, per_page: int, offline: bool,
                exclude_photo_ids: set[str] | None = None,
                exclude_observation_ids: set[str] | None = None) -> list[dict]:
    group, display, names = CLASSES[slug]
    rows: list[dict] = []
    seen_photos: set[str] = set(exclude_photo_ids or set())
    seen_observations: set[int] = set(exclude_observation_ids or set())

    for queried in names:
        page = 1
        while len(rows) < target:
            params = {
                "taxon_name": queried,
                "place_id": PLACE_NZ,
                "photos": "true",
                "photo_license": ",".join(LICENCES),
                "quality_grade": "research",
                "per_page": per_page,
                "page": page,
                "order_by": "votes",
                "order": "desc",
            }
            url = f"{API}?{urllib.parse.urlencode(params)}"
            cache_file = CACHE / f"{slug}_{_slug_name(queried)}_p{page}.json"
            payload = _get_json(url, cache_file, offline)
            results = payload.get("results", [])
            if not results:
                break
            for observation in results:
                obs_id = observation.get("id")
                for photo in observation.get("photos", []):
                    license_code = (photo.get("license_code") or "").lower()
                    if license_code not in LICENCES:
                        continue  # per-photo licence check, not the observation's
                    photo_id = str(photo.get("id"))
                    if photo_id in seen_photos or obs_id in seen_observations:
                        continue
                    seen_photos.add(photo_id)
                    seen_observations.add(obs_id)
                    original = photo.get("url") or ""
                    large = original.replace("square.", "large.").replace(
                        "square.jpg", "large.jpg").replace("square.jpeg", "large.jpeg")
                    original_url = original.replace("square.", "original.").replace(
                        "square.jpg", "original.jpg").replace("square.jpeg", "original.jpeg")
                    dims = photo.get("original_dimensions") or {}
                    rows.append({
                        "class_slug": slug,
                        "group": group,
                        "display_name": display,
                        "queried_name": queried,
                        "observation_id": obs_id,
                        "photo_id": photo_id,
                        "license_code": license_code,
                        "attribution": (photo.get("attribution") or "").strip(),
                        "observed_on": observation.get("observed_on") or "",
                        "taxon_id": (observation.get("taxon") or {}).get("id", ""),
                        "taxon_name": (observation.get("taxon") or {}).get("name", ""),
                        "url_large": large,
                        "url_original": original_url,
                        "file_path": "",
                        "bytes": "",
                        "md5": "",
                        "width": dims.get("width", ""),
                        "height": dims.get("height", ""),
                        "downloaded_at": "",
                    })
                    if len(rows) >= target:
                        break
                if len(rows) >= target:
                    break
            if len(results) < per_page:
                break
            page += 1
        if len(rows) >= target:
            break
    log(f"  {slug:18} candidates={len(rows):>3} observations={len(seen_observations):>3} "
        f"(queried {', '.join(names)})")
    return rows


def download_rows(rows: list[dict], offline: bool, workers: int = 4) -> list[dict]:
    from concurrent.futures import ThreadPoolExecutor

    def _fetch(row: dict) -> tuple[dict, pathlib.Path, bool]:
        dest = RAW / row["class_slug"] / f"{row['photo_id']}.jpg"
        url = row["url_large"] or row["url_original"]
        return row, dest, _download(url, dest, offline)

    kept: list[dict] = []
    hashes: dict[str, str] = {}
    with ThreadPoolExecutor(max_workers=max(1, workers)) as pool:
        outcomes = list(pool.map(_fetch, rows))
    for row, dest, ok in outcomes:
        if not ok:
            log(f"    ! download failed, skipped: {row['photo_id']}")
            continue
        digest = hashlib.md5(dest.read_bytes()).hexdigest()
        if digest in hashes:
            log(f"    ! duplicate bytes of photo {hashes[digest]}, removed {row['photo_id']}")
            dest.unlink(missing_ok=True)
            continue
        hashes[digest] = row["photo_id"]
        row["file_path"] = str(dest.relative_to(REPO))
        row["bytes"] = dest.stat().st_size
        row["md5"] = digest
        row["downloaded_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
        kept.append(row)
    return kept


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--per-class", type=int, default=60,
                        help="target number of photos per class")
    parser.add_argument("--per-page", type=int, default=30)
    parser.add_argument("--classes", nargs="*", default=list(CLASSES))
    parser.add_argument("--download-workers", type=int, default=4,
                        help="parallel CDN downloads (the API itself stays rate limited)")
    parser.add_argument("--offline", action="store_true",
                        help="use only cached API responses and already-downloaded files")
    args = parser.parse_args()

    CACHE.mkdir(parents=True, exist_ok=True)
    RAW.mkdir(parents=True, exist_ok=True)
    log(f"repo={REPO}")
    log(f"data dir={DATA}  (images -> {RAW})")

    all_rows: list[dict] = []
    for slug in args.classes:
        if slug not in CLASSES:
            log(f"unknown class {slug}, skipped")
            continue
        rows = fetch_class(slug, args.per_class, args.per_page, args.offline)
        all_rows.extend(download_rows(rows, args.offline, args.download_workers))

    with open(MANIFEST, "w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=MANIFEST_FIELDS)
        writer.writeheader()
        writer.writerows(all_rows)

    per_class: dict[str, int] = {}
    per_class_obs: dict[str, set[int]] = {}
    for row in all_rows:
        per_class[row["class_slug"]] = per_class.get(row["class_slug"], 0) + 1
        per_class_obs.setdefault(row["class_slug"], set()).add(row["observation_id"])
    log("")
    log(f"manifest: {MANIFEST.relative_to(REPO)}  rows={len(all_rows)}")
    log("per-class images / distinct observations:")
    for slug in CLASSES:
        log(f"  {slug:18} {per_class.get(slug, 0):>3} / {len(per_class_obs.get(slug, set())):>3}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
