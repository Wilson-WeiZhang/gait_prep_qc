# EEG Preprocessing Lessons & Pipeline V7

Shared lessons from processing both healthy (A2Walk) and patient (RESTORE2) data. For population-specific details see `healthy_data_prep.md` and `patient_data_prep.md`.

---

## 1. Pipeline V7 (Current)

```
Step1a: Load → 59ch whitelist → resample 250Hz → BP 1-40Hz → trim → step1_ica.set
Step1b: Same but BP 0.1-40Hz → step1.set
Step2:  Extract segments → clean_rawdata(ch, corr=0.8) → interp → CAR →
        BL correction → ASR(k=20, movement only) → AMICA(1 model, 1000 iter) → step2.set
Step3:  Transfer ICA to 0.1Hz → interp+CAR → ICLabel → artifact>0.9 rejection → step3.set
Step4:  Epoch → epochs.mat
```

Key V7 changes from V6: dual high-pass, avgref after bad ch interp, bad ch detection before baseline correction.

---

## 2. Bandpass Filter for ICA

- **1 Hz high-pass is critical** for good ICA decomposition
- 0.1 Hz retains too much slow drift → ASR removes 92% variance, ICA wastes components on low-frequency artifacts
- Use **1–40 Hz** for ICA training (standard: Makoto's pipeline, EEGLAB wiki)
- 40 Hz preferred over 45 Hz to cut 50 Hz line noise (Singapore)
- If delta band (0.1–3 Hz) needed for decoding: **"dual high-pass"** — train ICA on 1 Hz data, transfer weights to 0.1 Hz data

---

## 3. IC Rejection Criteria

- **Final rule: artifact > 0.9 only** (Muscle/Eye/Heart/LineNoise/ChanNoise any > 0.9)
- "Other" category does NOT trigger rejection
- brain < 0.1 rule abandoned — too aggressive, removed valid brain components

---

## 4. Bugs & Fixes

### Baseline Correction Order (Critical)

Applying baseline correction **before** `clean_rawdata` destroys inter-channel spatial correlation → massive false positives in bad channel detection.

- P02_Sess04: went from 33 flagged bad channels to fewer after fixing order
- **Rule:** bad channel detection on un-corrected data, baseline correction afterward

### AMICA Rank Calculation

- `pop_reref([], [])` for avgref reduces rank by 1
- Wrong: `data_rank = n_brain - n_interp`
- Correct: `data_rank = n_brain - n_interp - 1`
- All V7 outputs required rerun after this fix

### Step3 Interpolation Silent Skip

- `pop_interp` silently skips channels already in the montage
- Fix: `pop_select` to remove bad channels first, THEN `pop_interp` to restore them

### EEGLAB chanlocs Corruption

- `pop_select` on trial segments sometimes lost channel location info → ICLabel failure in Step3
- Fix: restore `chanlocs`/`chaninfo` after `pop_select` and after `pop_runamica`

---

## 5. clean_rawdata Thresholds

- BeMoBIL (Klug 2022): **corr 0.75 (lax) to 0.85 (strict)**
- 0.8 = field default (Jacobsen 2021, most gait EEG studies)
- Pipeline V7: upper limit = 10/59 bad channels; error-exit if exceeded
- **P02_Sess04 anomaly**: corr=0.8 → 33 bad (root cause: stronger eSCS stimulation); corr=0.7 → 11; corr=0.6 → 3

---

## 6. Goniometer Channel Index Bug (Major Lesson)

Early analysis hardcoded `target_goni_idx = 2`, assuming Walker Knee X. In reality:
- Type A sessions: Walker X axes at indices 4–8
- Type B sessions: Walker X axes at indices 17–22
- Index 2 = **Subject Knee X** in both configs

**Consequence:** Walk PLV (~0.82) was measuring Subject EEG vs Subject's own movement (motor artifact), not cross-person synchronization.

**Fix:** Created `find_goni_idx.m` for label-based lookup. **Never hardcode goni channel positions.**

---

## 7. Online Reference Electrode

| Population | Online REF | Ground |
|------------|-----------|--------|
| Healthy (A2Walk) | FCz | AFz |
| Patient (RESTORE2) | Cz | AFz |

Average re-referencing removes this difference downstream. However, bad REF (impedance > 20kΩ) corrupts all channels — see patient notes for affected sessions.
