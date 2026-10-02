# Usability protocol v1.2 — freeze record

Declared: **v1.2**, 2026-10-02. Supersedes v1.1 (`docs/usability/FREEZE_v1.1.md`, 2026-09-11). No participant has been recruited, contacted
or tested. Nothing in the kit contains participant data.

## What "frozen" means here

* Recruitment may begin only from a repository commit whose message carries `usability protocol v1.2`.
* The success criteria (C1–C3), the three tasks, the critical-error definition, the exclusion rules
  and the SUS wording are **not edited after the first session**. Any later change is v1.3 with its
  own note in this file and in `docs/post_evaluation_changes.md`.
* The task images are fixed files: every participant sees the same two photos.

## Frozen file hashes

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `docs/usability_evaluation_protocol.md` | 24761 | `7bbb3536e3ebde53a91d3545427adf77d611a36e6f261ddd4d89a0edf694dbba` |
| `docs/usability/consent_script.md` | 2220 | `689a4b7afbba33434230c06992bc1920b44c92446592dca3091705d5e942ded7` |
| `docs/usability/SUS_form.md` | 1809 | `9e107abc0260c33ebc1eb4307b96bb6e5c3069faf0d21cabe1c3730883f0c090` |
| `docs/usability/reset_checklist.md` | 3000 | `96039870dfd420a58a5648e04d1a1fecc3de57aa0f9838f3b69005baf24d030c` |
| `docs/usability/TESTING_KIT.md` | 7139 | `93deaa31bff455b48e1e1ecde30745581f00f4317032e25d7a86d97186abf1ba` |
| `docs/usability/templates/participant_intake.md` | 1415 | `ae4385b4141c7901e7542ed028895f0faf45b14955127d2d2fc644e28b64d185` |
| `docs/usability/templates/session_notes.md` | 3598 | `4b2bdde0bc61c4a4301aa4c620ba3516e8cef9f55273b520c116f2cb0e1a72f5` |
| `docs/usability/task_images/task1_subject.jpg` | 175424 | `9fbf50b85d8447e4b2bdb8e1cba49f91c3be872edfe92fb7a2801cb15d3f1aee` |
| `docs/usability/task_images/task2_unsuitable.jpg` | 33556 | `e8388f8cab51eb468adca450b9386ce5612cecdf2747afe8ab11794053e4a3db` |
| `docs/usability/task_images/PROVENANCE.md` | 3822 | `dc217d9c19c6328de0dd9f84f7ccbb8d6624c1b286cf12e47909ca217ebb54d2` |
| `tools/usability/analyse_usability.py` | 33865 | `aad0485e94783971ee1365954dd7a68baa77ed1b5026ff4dc131d3f4a62712d3` |
| `tools/usability/make_task_images.py` | 1583 | `60e288fab99f9dd4d5b564e7c1553970ca4160d147f9c52b7dde45dcb2b52f5e` |
| `docs/usability/SELF_TEST.md` | 2864 | `c62d44ab7463819a71159b32f7c183f54a7bb32cf044565b0124cc21919b3f65` |

Verify the freeze at any time with:

```sh
python3 tools/usability/verify_kit_freeze.py
```

The script recomputes the hashes and reports any file that changed, so a silent edit to a frozen
instrument is detectable rather than a matter of trust.

## Amendment v1.1 → v1.2 (declared 2026-10-02, before any participant)

Decided before the first participant was recruited, contacted or tested, so it cannot be a post-hoc
adjustment. Full reasoning: `docs/post_evaluation_changes.md` Change 6.

**What changed**

1. **Recruitment target ten → five.** The lecturer clarified that there is no fixed participant count
   and that at least five classmates are recommended. **No measurement threshold moved**: still ≥ 90 %
   of recruited participants completing Task 1 unaided, mean SUS ≥ 70, zero critical interaction
   errors. At n = 5 the ≥ 90 % requirement is **5/5**; 4/5 is 80 % and does not meet it. Criteria are
   reported `not_evaluable` below the target, so a partial sample can be neither passed nor failed.
2. **Task 1 stimulus replaced** — `task1_subject.jpg` is now korimako photo `37780000` (validation
   split, CC BY, top-1 **0.9856**). The previous kowhai photo `412560479` returns `Uncertain`
   (top-1 0.2199, below the 0.37 accept threshold), so **no learning card was ever rendered and Task 1
   was impossible for every participant**. Found in the facilitator rehearsal before any session; see
   `task_images/PROVENANCE.md` and Change 6.5.
3. **Reset step 5 command corrected.** `am broadcast … MEDIA_SCANNER_SCAN_FILE` did not make the
   picker list pushed images on Android 17; the checklist now uses
   `content call --method scan_file` and step 7 verifies personal gallery content was untouched.
4. **Scope guarantee added** to the reset procedure: only `nz.fieldsnap.app` and
   `/sdcard/Pictures/FieldSnap/` may be touched, never DCIM or the general gallery.
5. **`tools/usability/verify_kit_freeze.py` repointed** from the v1.1 record to this one.
6. **Kit text updated for five participants**: `TESTING_KIT.md` (build pinning, rehearsal record,
   incremental analysis) and the sheet-copy instructions; `consent_script.md` states ~25 minutes.

**What did not change:** the three tasks, the SUS wording and scale, the critical-error definition,
the exclusion rules, the model, the class set, the FR2/FR4 thresholds and every frozen metric.

**Kit re-hashed.** The v1.1 hashes in `FREEZE_v1.1.md` are historical and no longer verified; that
record now carries a superseded banner and this file is the record in force. The rehearsal found no
defect in the v1.1 *criteria* — only in the stimulus and the reset command — so the measurement
instrument is carried over unchanged apart from the items listed above.

**Not in the frozen set, and why.** `tools/usability/verify_kit_freeze.py` and
`tools/usability/make_print_pack.py` are development tooling, not study instruments: the verifier is
the checker itself (it must be able to change when the record does), and the print pack only *renders*
the frozen forms without writing them back — generating it leaves every hash above unchanged. Freezing
them would mean the hash record had to be edited every time a rendering bug was fixed, which is the
opposite of what the record is for.
