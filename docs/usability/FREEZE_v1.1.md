# Usability protocol v1.1 — freeze record

> **SUPERSEDED by v1.2 (`docs/usability/FREEZE_v1.2.md`), declared 2026-10-02.** This v1.1 record is
> kept as history. Its hashes are historical and are **not** the current freeze — run
> `python3 tools/usability/verify_kit_freeze.py`, which checks the v1.2 record.


Declared: **v1.1**, 2026-09-11. No participant has been recruited, contacted
or tested. Nothing in the kit contains participant data.

## What "frozen" means here

* Recruitment may begin only from a repository commit whose message carries `usability protocol v1.1`.
* The success criteria (C1–C3), the three tasks, the critical-error definition, the exclusion rules
  and the SUS wording are **not edited after the first session**. Any later change is v1.2 with its
  own note in this file and in `docs/post_evaluation_changes.md`, and the sessions already run are
  reported as v1.1.
* The task images are fixed files: every participant sees the same two photos.

## Frozen file hashes

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `docs/usability_evaluation_protocol.md` | 16083 | `f67d45e32ecf8c125e1a413c360a612477c1dd70563d233cf5c27709338de576` |
| `docs/usability/consent_script.md` | 2226 | `377900e2713872c84ae5680a20d1af9cd7c71e870535dcb2f3853c576c1e4e12` |
| `docs/usability/SUS_form.md` | 1809 | `9e107abc0260c33ebc1eb4307b96bb6e5c3069faf0d21cabe1c3730883f0c090` |
| `docs/usability/reset_checklist.md` | 2112 | `0764715ba16feadbeb265fce1e3851a463578929f79f945290e0daa9ef5ed51c` |
| `docs/usability/TESTING_KIT.md` | 3159 | `a8069d82456f858d0c35f0c9935936e1716c0feac0175bdecd15276ba0b793a6` |
| `docs/usability/templates/participant_intake.md` | 1339 | `00d5d6b7d38fae3875f86b294daa2bac7eb79558b321ccbff97df7e1bd0b4a85` |
| `docs/usability/templates/session_notes.md` | 3263 | `fd49c6d2d31e39894f2da134509d376dca3364bef50901e6fba64839db797164` |
| `docs/usability/task_images/task1_subject.jpg` | 402245 | `3901759e217b436aad315f9a62955c505a83ac03a755e139e78420e6f655b86b` |
| `docs/usability/task_images/task2_unsuitable.jpg` | 33556 | `e8388f8cab51eb468adca450b9386ce5612cecdf2747afe8ab11794053e4a3db` |
| `docs/usability/task_images/PROVENANCE.md` | 1377 | `daa3b8fc8be6736bae11a07f5747751266d7f51c341d00911daad357cac6cfc9` |
| `tools/usability/analyse_usability.py` | 21494 | `e38f52b00ec89a1835c7a4bfe088c779a4b9afd9d23e016e71602977bfcdf871` |
| `tools/usability/make_task_images.py` | 1583 | `60e288fab99f9dd4d5b564e7c1553970ca4160d147f9c52b7dde45dcb2b52f5e` |
| `docs/usability/SELF_TEST.md` | 1718 | `c51296c984910a1d73ed793d5f0303c30ba3e4d2174f5c50dad5a38c93eb5acb` |

Verify the freeze at any time with:

```sh
python3 tools/usability/verify_kit_freeze.py
```

The script recomputes the hashes and reports any file that changed, so a silent edit to a frozen
instrument is detectable rather than a matter of trust.
