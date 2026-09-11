# Task image provenance

These two files are the fixed stimuli for the usability study. Every session uses them, so the task is
identical across participants.

## task1_subject.jpg — the ordinary photo (Task 1)

* source: our own **validation-split** image `data/raw/kowhai/412560479.jpg` (never in the sealed test split)
* class: `kowhai`
* licence: `cc0`
* attribution: no rights reserved
* observation id `232231244`, photo id `412560479`, original size 768x1024
* downscaled to at most 900 px on the long edge and re-encoded at quality 92 for the repository

## task2_unsuitable.jpg — the unsuitable photo (Task 2)

Generated, not collected, so its provenance is trivial and it is trivially reproducible: a synthetic
low-contrast, heavily blurred frame with a bright glare band and a visible pixel grid, i.e. the shape
of the photo-of-a-screen a novice might take. It contains no personal content and no identifiable
subject, and it ships with this repository under the same terms as the project's own code.

Regenerate it with `python3 tools/usability/make_task_images.py`.

## Fit with the frozen evaluation

Neither image is used to compute any metric. `task1_subject.jpg` comes from the validation split,
which the classifier is not trained on; using it as a study stimulus says nothing about accuracy and
does not touch the sealed test split or any frozen result.
