# Data set (checkpoint 1A)

Everything in this directory is **local only** — the images are git-ignored on purpose.
The repository keeps the scripts and the frozen protocol so the data can be reproduced,
without becoming a redistribution mirror of other people's photographs.

## Accepted licences

Only **CC0** and **CC BY** are fetched. `CC BY-NC` is excluded; `CC BY-SA` is a fallback
only if a class cannot reach its sample target. The licence is read **per photo**
(`photo.license_code`), never from the observation record.

## Reproduce

```sh
python3 tools/fetch_dataset.py --per-class 60          # API is rate limited to ~1/s,
                                                       # CDN downloads use 4 workers
python3 tools/make_split.py                            # freezes the split + protocol
```

`fetch_dataset.py` writes `manifest.csv`, which is the provenance record for every image:
observation id, photo id, licence code, attribution string, observed date, place, taxon id,
both CDN URLs, local path, byte size, md5, and the original dimensions. The split script
refuses to run if any row carries a licence outside the accepted set.

## Files

| Path | Tracked? | Purpose |
| --- | --- | --- |
| `manifest.csv` | no | one row per downloaded image, with licence and attribution |
| `manifest_{train,val,test}.csv` | no | the same rows, split |
| `split.json` | no | `photo_id -> split` mapping |
| `split_protocol.json` | yes | frozen protocol: seed, ratios, grouping rule, manifest hash, per-class counts, and the sealed-test statement |
| `class_indices.json` | yes | the model's label order, generated in the same run as the model |
| `raw/<class_slug>/*.jpg` | no | the images themselves |
| `cache/*.json` | no | cached API responses, so re-runs do not re-query |
| `provenance_shareable.csv` | yes | public record of the data set: photo/observation ids, class, licence, attribution, taxon, CDN URL, md5, size, original dimensions and split. Local paths, coordinates, place names and local timestamps are deliberately **removed** so this can be shared |
| `../assets/models/fieldsnap_int8.tflite` | yes | the model that actually ships (1.2 MiB), committed so the app and tests run without retraining |
| `../assets/models/class_indices.json` | yes | label order, generated with the model |

## Reproducing this experiment without re-downloading anything

A teacher can inspect the data decisions from `provenance_shareable.csv` and run the app and
every test from a plain clone: the shipped model and label list are committed.

Re-creating the *images* is optional and separate:

```sh
python3 tools/fetch_dataset.py --per-class 60   # refetches by photo id and verifies md5
python3 tools/verify_split.py                   # must pass before trusting any result
```

`tools/fetch_dataset.py` re-downloads the same photo ids and `verify_split.py` re-checks the
recorded md5 for every file, so a re-fetch either reproduces the same bytes or fails loudly.

## Split rule

The split is by **observation**, not by photo: observations often contain several
near-identical frames of the same individual, and splitting per photo would put
near-duplicates on both sides of the boundary and inflate measured accuracy. Verified
with `tools/verify_split.py`.

The **test split is sealed**: nothing in training, threshold selection or debugging may
read `manifest_test.csv`. M1 fixes the confidence threshold on validation data and locks
it before test evaluation, and that rule starts here.
