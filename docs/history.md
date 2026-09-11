# FR6 local history — schema and the decision not to store photographs

## What is stored

SQLite (`lib/services/sqflite_history_repository.dart`, table `history`, schema version 1) with one
row per identification:

| Column | Meaning |
| --- | --- |
| `created_at` | ISO-8601 timestamp, sorts correctly and stays readable in a database browser |
| `top_slug`, `top_common_name`, `top_scientific_name` | the asserted species (or the top candidate when the verdict was Uncertain) |
| `top_confidence`, `runner_up_slug`, `runner_up_confidence` | what the model actually produced |
| `was_uncertain` | whether FR4 abstained instead of asserting |
| `confidence_threshold`, `confidence_policy_validated` | the policy that was applied, **per row**, so a record made under an older or uncalibrated policy can never be mistaken later for a calibrated one (the deployed threshold is 0.37 since Iteration 3) |
| `quality_brightness`, `quality_laplacian_variance`, `quality_accepted` | what FR2 measured |
| `model_label`, `model_asset` | which model produced the record (FP32 vs the experimental INT8) |

## What is deliberately NOT stored: the photograph

The record keeps **no image and no file path to one**. Reasons, in order of weight:

1. The user's photo already exists in their own gallery; copying it into the app's database creates
   a second, permanent copy the user did not ask for.
2. Nothing in the accepted feature set needs it: history is a log of identifications, and the
   learning card content is static.
3. It keeps the storage story simple to explain in the report — the database contains no personal
   media, only derived values.

If a justified need appears later (for example "show the thumbnail I classified last week"), the
change should add an explicit, user-visible retention rule (copy-on-save with a delete affordance)
rather than quietly writing paths now.

## Repository boundary

`HistoryRepository` is the interface the UI and ViewModel depend on; `SqfliteHistoryRepository` is
the only implementation that touches SQL, matching M1's rule that "only the history repository
touches SQLite". `InMemoryHistoryRepository` exists for tests and for any platform without sqflite.

## Tests

`test/quality_and_history_test.dart` covers: id assignment, newest-first ordering, delete one,
delete all, row round-trip, and the "no photograph reference" property. The ViewModel tests cover
what gets recorded for an identified and for an Uncertain result, including the quality metrics.

## Not done yet

* The app wires `InMemoryHistoryRepository` at startup because `sqflite` needs platform channels
  that are unavailable to the current test environment; switching `main.dart` to
  `SqfliteHistoryRepository.open()` is a one-line change, and the SQLite implementation is covered by
  schema/row tests rather than by a device run. **A device run of the SQLite path has not been
  performed yet** and must not be claimed.
