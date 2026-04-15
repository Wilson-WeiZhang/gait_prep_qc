# EEG Preprocessing Lessons & Pipeline V8

Shared lessons from processing both healthy (A2Walk) and patient (RESTORE2) data. For population-specific details see `healthy_data_prep.md` and `patient_data_prep.md`.

---

## 1. Pipeline V8 (Current — frozen 2026-04-10)

### Data Flow

```
Raw → 59ch whitelist → Resample 250Hz
  ├─ 1-40 Hz BP (step1_ica.set, 59ch) ─── for ICA training
  │   └─ Trim S11–S12 → Extract task segments (no BL correction)
  │       → clean_rawdata (corr=0.8, bad ch detection)
  │       → Spherical spline interpolation → Reorder 59ch
  │       → +FCz zero-filled → CAR (60ch) → ASR (k=20, Walk only)
  │       → AMICA (1 model, 1000 iter) → step2.set (60ch)
  │
  └─ 0.1-40 Hz BP (step1.set, 59ch) ─── for final output
      └─ Same bad ch interp → Reorder 59ch
          → +FCz zero-filled → CAR (60ch) → ASR (k=20, Walk only)
          → ICA weight transfer from step2
          → ICLabel → Reject artifact > 0.8
          → step3.set (60ch, continuous, ICA-cleaned)
```

### Key Design Decisions

| Decision | V8 | Rationale |
|----------|-----|-----------|
| Dual high-pass | 1 Hz (ICA) / 0.1 Hz (output) | Klug & Gramann 2021; preserves delta/SCP for decoding |
| ICA training: no BL correction | Yes | BL correction distorts inter-channel correlation; ICA assumes stationarity |
| FCz restoration | Zero-filled before CAR | FCz is online ref (actiCHamp); restoring avoids rank loss (Makoto/Kim 2023) |
| 60ch output | 59 brain + FCz | FCz becomes valid after CAR; located at fronto-central midline (SMA/pre-SMA) |
| ASR on 0.1 Hz path | Yes, Walk only | Removes non-stationary bursts that ICA cannot separate; both paths cleaned |
| AMICA 1 model | 1 model, 1000 iter | BeMoBIL standard; 2 models unnecessary when ASR pre-cleans movement data |
| ICLabel threshold | artifact > 0.8 | More aggressive than 0.9; appropriate for MoBI data |
| ICA weights preserved | In `step3_meta.icaweights_pre_reject` | Enables post-hoc source analysis |

### V6 → V8 Changes Summary

| Parameter | V6 | V8 |
|-----------|-----|-----|
| Output HP | 0.5 Hz | 0.1 Hz |
| ICA HP | same as output | separate 1 Hz copy |
| AMICA | 2 models | 1 model |
| BL for ICA training | Yes (1s pre-trial) | No |
| FCz | Excluded | Restored as 60th channel |
| CAR timing | After IC rejection (Step2b) | After interp, before ASR (Step2) |
| IC rejection | artifact>0.9 ∥ brain<0.05 | artifact>0.8 only |
| ASR on output | No | Yes (Walk segments) |
| ICA weights | Cleared | Preserved in metadata |

---

## 2. Bandpass Filter for ICA

- **1 Hz high-pass is critical** for good ICA decomposition
- 0.1 Hz retains too much slow drift → ASR removes 92% variance, ICA wastes components on low-frequency artifacts
- Use **1–40 Hz** for ICA training (standard: Makoto's pipeline, EEGLAB wiki)
- 40 Hz preferred over 45 Hz to cut 50 Hz line noise (Singapore)
- If delta band (0.1–3 Hz) needed for decoding: **"dual high-pass"** — train ICA on 1 Hz data, transfer weights to 0.1 Hz data

---

## 3. IC Rejection Criteria

- **V8 rule: artifact > 0.8** (Muscle/Eye/Heart/LineNoise/ChanNoise any > 0.8)
- "Other" category does NOT trigger rejection
- brain < 0.1 rule abandoned — too aggressive, removed valid brain components
- **QC threshold**: brain>70% ≥2, brain>80% ≥2, brain>90% ≥1 per session

---

## 4. Bugs & Fixes

### Baseline Correction Order (Critical)

Applying baseline correction **before** `clean_rawdata` destroys inter-channel spatial correlation → massive false positives in bad channel detection.

- P02_Sess04: went from 33 flagged bad channels to fewer after fixing order
- **Rule:** bad channel detection on un-corrected data, baseline correction afterward
- **V8:** ICA training segments extracted with NO baseline correction at all

### AMICA Rank Calculation

- `pop_reref([], [])` for avgref reduces rank by 1
- **V8 fix:** Restore FCz as zero-filled channel before CAR → rank loss absorbed
- Formula: `data_rank = n_brain - n_interp` (no -1 with FCz restoration)

### Step3 Interpolation Silent Skip

- `pop_interp` silently skips channels already in the montage
- Fix: `pop_select` to remove bad channels first, THEN `pop_interp` to restore them

### EEGLAB chanlocs Corruption

- `pop_select` on trial segments sometimes lost channel location info → ICLabel failure in Step3
- Fix: restore `chanlocs`/`chaninfo` after `pop_select` and after `pop_runamica`

### ASR Segment Selection Consistency

- `apply_asr` must check boundary crossings and nested start markers (same logic as `extract_segments` and `extract_epochs`)
- V8 fix: added boundary check + nested marker check + dur>300s limit + warning if no segments found

---

## 5. clean_rawdata Thresholds

- BeMoBIL (Klug 2022): **corr 0.75 (lax) to 0.85 (strict)**
- 0.8 = field default (Jacobsen 2021, most gait EEG studies)
- Pipeline V8: upper limit = 10/59 bad channels; error-exit if exceeded
- **P02_Sess04 anomaly**: corr=0.8 → 33 bad (root cause: stronger eSCS stimulation); corr=0.7 → 11; corr=0.6 → 3
- **SUB_26_sess01**: 11/59 bad (all frontal: Fp1, Fz, Cz, F4, Fp2, AF7-AF8) → processed with warning (exceeds 10-ch limit)

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

| Population | Online REF | Ground | V8 Handling | Output |
|------------|-----------|--------|-------------|--------|
| Healthy (A2Walk) | FCz | AFz | FCz zero-filled + CAR | 60ch (59 brain + FCz) |
| Patient (RESTORE2) | Cz | AFz | Cz zero-filled + CAR (updated 2026-04-13) | 60ch (59 brain + Cz) |

Both pipelines now produce identical 60-channel montage: 59 brain channels + online ref zero-filled before CAR. The 59 brain channels differ by one: healthy includes Cz (data channel), excludes FCz (ref); patient includes FCz (data channel), excludes Cz (ref). After CAR, all 60 channels are valid.

Bad REF (impedance > 20kΩ) corrupts all channels -- see patient notes for affected sessions.

---

## 8. V8 QC Results (2026-04-13, 40 healthy sessions)

### ICLabel QC (pass: B70>=2, B80>=2, B90>=1)

| Status | Count | Sessions |
|--------|-------|----------|
| PASS | 39 | All except SUB_19_sess02 |
| **FAIL** | 1 | SUB_19_sess02 (B70=1, B80=1, B90=1) |

### Flagged sessions (pass QC but need attention)

| Session | BadCh | Issue |
|---------|-------|-------|
| SUB_04_sess02 | 11 | Exceeds 10-ch limit; scattered (frontal+central+temporal+occipital) |
| SUB_19_sess01 | 7 | Marginal QC (B70=2, B80=2, B90=2) |
| SUB_21_sess01 | 10 | At limit; widespread |
| SUB_26_sess01 | 11 | Exceeds limit; all frontal strip |
| SUB_28_sess01 | 3 | Only 20 MI / 20 Walk trials (recording interrupted) |
| SUB_10_sess01 | 3 | Only 8 goni trials (second EEG segment has 68 trials) |

---

## 9. EEG--Goniometer Alignment

See dedicated docs:
- `healthy_data_prep.md` Section 4 -- IOI alignment, count mismatch, clock jump special cases
- `patient_data_prep.md` Section 4 -- S10/Stim alignment, multi-file goni
- `align_special_cases.md` -- SUB_07/27 clock jumps + SUB_12 file swap

### Key findings (2026-04-13)

- **40/40 healthy sessions aligned**, every trial independently trigger-matched
- **9/9 patient sessions aligned** (P02_Sess04 added after goni upload to aa)
- **Goni QC: 0 problems** across all 40 healthy sessions (condition-aware QC)
- Clock jumps in SUB_07_sess02 (2 offsets, 244ms) and SUB_27_sess01 (3 offsets, 2673ms) are discrete, not drift. Each trial's goni cut is exact.
- SUB_12_sess01 goni file swap fixed in raw data (aa + NTU OneDrive, 2026-04-13)
- SUB_01_sess01 rest trials recovered via R1 marker co-occurrence
- QC figures: `result/goni_healthy/qc/alignment_figs/` (40 PNGs, 3-panel: EEG timeline / Goni timeline / offset vs time)

## 10. Data Sources and Sync

| Source | Content | Sync status (2026-04-13) |
|--------|---------|--------------------------|
| NTU OneDrive | 28 healthy raw EEG+Goni | Canonical source; SUB_01-09 goni synced to aa |
| aa server | 28 healthy + patient raw; V8 output; goni extraction | V8 40/40 complete; goni 40/40 complete |
| Local (personal OneDrive) | Repo + goni results + flagged step2 | goni 40/40; 6 flagged step2.set downloaded |

**SUB_01-09 goni raw data**: only on NTU OneDrive and (now) aa. Not in local repo.
**V8 step1/2/3.set (32GB)**: only on aa. Epochs synced to local on demand.
