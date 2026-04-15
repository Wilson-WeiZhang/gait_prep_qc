# Healthy Subject Data Preparation & QC Notes (A2Walk Study)

## 1. Study Design

28 healthy subjects (SUB_01–SUB_28), each paired with a Walker. Each session = **30 cycles x 5 trials = 150 trials**, ~57 min recording.

### Cycle Structure (always in this order)

| # | Trial type | Subject action | Walker action | Direction | Duration | EEG Markers |
|---|------------|---------------|---------------|-----------|----------|-------------|
| 1 | Imagine (odd) | Imagines walking | Actually walks | Forward | ~10s | S1 → S2 |
| 2 | Walk (odd) | Actually walks | Stands still | Forward | ~10s | S4 → S5 |
| 3 | Imagine (even) | Imagines walking | Actually walks | Backward | ~10s | S1 → S2 |
| 4 | Walk (even) | Actually walks | Stands still | Backward | ~10s | S4 → S5 |
| 5 | Rest | Both rest | Both rest | — | ~12s | S7 → S8 |

- Breaks every 10 cycles (~2.5 min), visible as marker gaps.
- Odd/even direction **not distinguishable from EEG markers** — use PyLog `trial_durations.csv` for `task_id` mapping.

### Trial Counts per Session

60 imagine + 60 walk + 30 rest = 150 trials

---

## 2. EEG Recording

| Parameter | Value |
|-----------|-------|
| Amplifier | actiCHamp (Brain Products) |
| Channels | 63 EEG + 1 reference = 64 |
| Online reference | **FCz** (differs from patient Cz) |
| Ground | AFz |
| Sampling rate | 1000 Hz |
| Format | BrainVision (.vhdr / .vmrk / .eeg) |
| Files per session | 1 (single continuous recording) |

### EEG Markers

**Standard scheme (12/13 sessions):**

| Marker | Meaning | Count/session |
|--------|---------|---------------|
| S 11 | Experiment START | 1 |
| S 1 | Imagine trial START (odd + even) | 60 |
| S 2 | Imagine trial STOP | 60 |
| S 4 | Walk trial START (odd + even) | 60 |
| S 5 | Walk trial STOP | 60 |
| S 7 | Rest START | 30 |
| S 8 | Rest STOP | 30 |
| S 12 | Experiment END | 1 |

**Exception — SUB_01 Sess01 (old experiment script):**
- 2x S11 markers
- S4→S5 used for **both** walk (60) AND rest (30) = 90 pairs
- Rest trials encoded as R1+S4 → R1+S5 instead of S7→S8
- No S7/S8 markers at all
- Does not affect ICA quality, but downstream trial extraction must handle this case

### PyLog Marker Mapping (Important!)

The experiment PC sends more markers than what appears in EEG. Some are collapsed:

| PyLog marker | EEG marker | Description |
|-------------|------------|-------------|
| S1/S2 | S 1 / S 2 | Imagine (backward direction) |
| S4/S5 | S 4 / S 5 | Walk (forward direction) |
| S6/S7 | **S 1 / S 2** | Imagine (forward) — mapped to same as backward |
| S8/S9 | **S 4 / S 5** | Walk (backward) — mapped to same as forward |
| S20/S21 | S 7 / S 8 | Rest |
| S11/S12 | S 11 / S 12 | Experiment start/end |

---

## 3. Goniometer

### Hardware

- System: Biometrics Ltd digital goniometers + DataLITE wireless receivers
- Sampling rate: 1000 Hz
- File format: UTF-16LE encoded text (.txt)
- 6 goniometers (Subject) + 6 (Walker) + 1 wireless trigger = max 24 channels

### Channel Layout (23 goni + 1 Stim = 24)

| Joint | Subject X | Subject Y | Walker X | Walker Y |
|-------|-----------|-----------|----------|----------|
| Right Hip | RHipS X | RHipS Y | RHipW X | RHipW Y |
| Right Knee | RKneS X | RKneS Y | RKneW X | RKneW Y |
| Right Ankle | RAnkS X | RAnkS Y | RAnkW X | RAnkW Y |
| Left Hip | LHipS X | LHipS Y | LHipW X | LHipW Y |
| Left Knee | LKneS X | LKneS Y | LKneW X | LKneW Y |
| Left Ankle | LAnkS X | **varies** | LAnkW X | LAnkW Y |

### Two Receiver Configurations (Critical!)

Due to 24-channel limit, one goni axis is sacrificed per session:

| Config | Sessions | Missing channel | Present instead |
|--------|----------|----------------|-----------------|
| Type A | SUB_01_s01, 02_s01, 02_s02, 03_s01, 04, 05, 06_s01 (7 sessions) | **LAnkW X** | LAnkS Y |
| Type B | SUB_01_s02, 03_s02, 06_s02, 07, 08, 09 (6 sessions) | **LAnkS Y** | LAnkW X |

**Consequences:**
- Subject X-axis: all 6 joints available in ALL sessions
- Walker X-axis: only 5 joints common (LAnkW X missing in Type A)
- Cross-session CCA using Walker joints should use 5-joint intersection
- **Channel order varies across subjects** (e.g. SUB_09 has completely different column order)

> **NEVER hardcode goniometer channel indices.** Always use label-based lookup via `find_goni_idx.m`. See the channel index bug below.

### Goniometer Filename Patterns (Inconsistent!)

- `a2walk-{NNN}-sess{N}_enggunit.txt` (most common)
- `a2walk-{NNN}_sess{N}.txt` (SUB_01)
- `a2walk-sub{NN}-sess{NN}.txt` (some later subjects)
- `SUB-{NNN}_sess-{NN}_{date}.txt` (SUB_03 sess01)

All files are in engineering units (degrees) regardless of filename.

---

## 4. EEG--Goniometer Alignment (Healthy)

### Shared Principle

The experiment PC sends the same TTL trigger to both EEG amplifier and goniometer DataLITE simultaneously. EEG records them as `S 1`, `S 2`, ... `S 12` markers; goniometer records them as rising edges in its embedded Stim channel (bit-coded values: 0, 2, 6, 8, 10, 14, 16). A standard session has 302 triggers on each side.

Alignment = find a single scalar offset such that `goni_time = eeg_time + offset`. The EEG clock is the grand clock; all trial timestamps are expressed in EEG time.

### Algorithm: `align_ioi.m`

Healthy data has no periodic S10 sync pulses (unlike patient data), so alignment uses IOI (Inter-Onset-Interval) substring matching:

1. **Stim edge extraction**: threshold goni Stim > 5, merge pulses within 5ms, filter spurious onsets (IOI < 50ms)
2. **Direct 1:1 attempt** (if counts match): compute per-event offset, accept if all residuals < 100ms
3. **IOI sliding match** (if direct fails or counts differ): extract IOI subsequences from 5 starting positions (5%, 20%, 40%, 60%, 80%), slide each against the goni IOI sequence, pick the candidate with highest match rate
4. **Hough fallback** (if match < 90%): build a histogram of all pairwise EEG-to-goni offsets, find the dominant peak, refine via median of nearby matches
5. **Output**: `offset` (scalar), `align_info` struct with method, match_frac, residuals

### Count Mismatch Handling: `align_eeg_goni.m` / `check_iei()`

When EEG and goni trigger counts differ by N:

1. Identify which side is longer
2. Iteratively try removing each event from the longer side; pick the removal that minimizes max IEI difference vs the shorter side
3. Accept removal if residual < 3000ms; repeat until counts match
4. Log each removal with timestamp and residual

Examples: SUB_01_sess01 (303 vs 303, old script, resolved by IOI sliding), Sub02_Sess03 patient (145 vs 144, 1 spurious goni stim at recording end removed).

### Alignment Quality (40 sessions)

| Category | Sessions | Match | Max residual |
|----------|----------|-------|-------------|
| Perfect (single offset) | 36/40 | 100% | < 50ms |
| Clock drift (per-segment offset) | SUB_07_sess02, SUB_19_sess02, SUB_27_sess01 | 100% after fix | < 31ms |
| Late goni start | SUB_16_sess02 | 91% (274/301); all trials in matched region | < 40ms |
| Partial goni coverage | SUB_10_sess01 | 41/~302 matched; only 8 GI trials | Excluded from primary analysis |

See `align_special_cases.md` for full diagnostic details on all 4 special cases.

### Clock Drift & Alignment Special Cases

Four sessions require special handling. See `align_special_cases.md` for full diagnostics.

**Clock drift** (3 sessions): gradual clock drift between EEG and goni systems. Joint angle data is fully continuous (no disconnection, no zeros). The standard single offset fails because cumulative drift exceeds the 100ms tolerance.

**Fix**: `extract_goni_all_healthy.m` applies per-segment offsets for these sessions via `get_special_offsets()`. Each trial's EEG time determines which offset to use.

#### SUB_07_sess02

Drift of +0.244s over 28 minutes. Two offset segments:

| EEG time range | Offset (s) |
|---------------|------------|
| < 1700s | -28.085 |
| >= 1700s | -27.841 |

#### SUB_27_sess01

Initial clock mismatch of 2.4s that resolves after ~260s, plus late drift of +0.257s. Three offset segments:

| EEG time range | Offset (s) | Note |
|---------------|------------|------|
| < 260s | -11.840 | Initial mismatch |
| 260--1695s | -9.424 | Primary |
| >= 1695s | -9.167 | Late drift |

See `align_special_cases.md` for full diagnostic details.

#### SUB_19_sess02

Clock drift with 3 phases (~183ms total over ~2800s). Per-segment offsets:

| EEG time range | Offset (s) | Note |
|---------------|------------|------|
| < 610s | 28.258 | Goni clock behind |
| 610–2090s | 28.370 | Near baseline |
| >= 2090s | 28.441 | Goni clock ahead |

#### SUB_16_sess02 — Late Goni Start

Goni recording started ~4.5 min after EEG. First 27 EEG events have no goni counterpart. From event 29 onward: perfect alignment (mean 10ms, max 40ms). All 60/60/30 trials extracted from matched region. No code change needed.

#### SUB_10_sess01 — Partial Goni Coverage

Multi-file session. Goni only captured 41 out of ~302 EEG events. Only 8 GI trials with goni data. Excluded from primary CCA/decoding analysis.

### Validation

Per-session trigger correspondence tables are saved to `result/goni_healthy/qc/align_qc_*.txt`. Each row shows: trigger index, EEG time, error (ms), match status.

---

## 5. Goniometer Data Quality Issues

### Root Cause

Wireless disconnection between goniometer sensor and DataLITE receiver. The sensor records **zeros** until reconnection. This is NOT hardware failure — only the disconnected sensor is affected.

### Affected Sessions

| Subject | Session | Bad/Total GI Trials | Cause | Severity |
|---------|---------|---------------------|-------|----------|
| **SUB_12** | sess01 | 28/62 | Walker goni wireless disconnection | Severe |
| **SUB_13** | sess01 | 15/60 | Goni zeros | Severe |
| **SUB_14** | sess01 | 25/60 | Goni zeros | Severe |
| **SUB_21** | sess01 | 19/60 | Walker goni wireless disconnection | Moderate |
| SUB_06 | sess02 | 1/60 | Trial 6 flagged | Minor |
| SUB_15 | sess02 | 1/60 | Trial 98 flagged | Minor |

### Walk vs Imagine Goniometer Quality

- **Walk condition:** High variability (CV 0.15–0.80), many flat trials because Walker slows/stops during turns
  - Worst: SUB_01_sess01 walk has 29/90 flat trials
- **Imagine condition:** Very stable (CV 0.02–0.04) because Walker maintains continuous walking

### Impact on Analysis

- Trials with zero-reading goni channels must be excluded from CCA/decoding
- Subject-side goniometer typically unaffected when only walker-side drops
- QC scripts: `run_qc_gonio.m`, `qc_gonio_classify.m`

---

## 6. Multi-File / Special Sessions

| Subject | Session | Structure | Issue |
|---------|---------|-----------|-------|
| SUB_04 | sess02 | 2 recording segments | 15+46 trials |
| SUB_09 | sess02 | 2 recording segments | 6+56 trials |
| SUB_10 | sess01 | 2 recording segments | 8+? trials |
| **SUB_22** | sess01 | **3 segments** | Goni wireless disconnection caused mid-session restart; segment 2 has no corresponding EEG S11 → visual alignment by Neethu |
| **SUB_24** | sess01 | Normal | Only mixed-gender pair (female subject, male walker) |

---

## 7. Standard Data Structure (Per Session)

### Raw Data Directory

```
SUB_XX/sessNN_{date}/
├── EEG/
│   └── a2walk_cbcr_{NNNN}.vhdr/.vmrk/.eeg    # BrainVision, 1000Hz, 63ch + FCz ref
├── Goniometer/
│   └── a2walk-*_enggunit.txt                   # UTF-16LE, 1000Hz, 24ch (23 goni + Stim)
│       (also .cnt binary + .log metadata)
└── PyLog/
    ├── {timestamp}.txt                          # Marker sequence + Unix timestamps
    └── {timestamp}_trial_durations.csv          # Trial-level metadata (cycle, task_id, duration)
```

### Expected EEG Marker Counts (Standard Session)

| Marker | Expected | Meaning |
|--------|----------|---------|
| S 11 | 1 | Experiment START |
| S 12 | 1 | Experiment END |
| S 1 | 60 | Imagine START |
| S 2 | 60 | Imagine STOP |
| S 4 | 60 | Walk START |
| S 5 | 60 | Walk STOP |
| S 7 | 30 | Rest START |
| S 8 | 30 | Rest STOP |
| **Total** | **302** | (= goni Stim onset count) |

### Expected Goniometer Stim Values

Bit-coded TTL: 0 (baseline), 2, 6, 8, 10, 14, 16. Total onsets per session ≈ 302, matching EEG marker count 1:1.

### PyLog `trial_durations.csv` Columns

```
session_id, trial_index_global, cycle_no, seq_idx, trial_index_in_cycle,
task_id, task_name, marker_start, marker_end, t_start_unix_ms, t_end_unix_ms, duration_s
```

`task_id`: 1 = imagine-odd, 2 = walk-odd, 4 = imagine-even, 5 = walk-even, 3 = rest

---

## 8. Outlier & Exception List

### EEG Marker Exceptions

| Session | Issue | Impact | Handling |
|---------|-------|--------|----------|
| **SUB_01 sess01** | Old experiment script: 2x S11, no S7/S8, rest encoded as R1+S4→R1+S5 | 90 S4→S5 pairs (walk+rest mixed) | Filter by R1 co-occurrence to separate rest from walk |

### Multi-File Sessions (Recording Interrupted)

| Session | Segments | Trial Split | Notes |
|---------|----------|-------------|-------|
| SUB_04 sess02 | 2 | 15 + 46 | |
| SUB_09 sess02 | 2 | 6 + 56 | |
| SUB_10 sess01 | 2 | 8 + ? | Goni only captured 41 events; partial coverage |
| **SUB_22 sess01** | **3** | 78 + 3 + 70 | Goni wireless disconnection → mid-session restart; segment 2 has no S11 → visual alignment by Neethu |
| **SUB_28 sess01** | 1 | **20 MI + 20 Walk** | Recording interrupted early; only ~40 trials total |

### Goniometer Data Quality (Wireless Disconnection → Zeros)

| Session | Bad/Total GI Trials | Severity | Notes |
|---------|---------------------|----------|-------|
| **SUB_12 sess01** | 28/62 | Severe | Walker goni |
| **SUB_13 sess01** | 15/60 | Severe | |
| **SUB_14 sess01** | 25/60 | Severe | |
| **SUB_21 sess01** | 19/60 | Moderate | Walker goni |
| SUB_06 sess02 | 1/60 | Minor | Trial 6 |
| SUB_15 sess02 | 1/60 | Minor | Trial 98 |

### Walk Condition Goni Quality

Walk condition has high trial-level variability (CV 0.15–0.80) because Walker slows/stops during turns. Worst: SUB_01_sess01 walk has 29/90 flat trials. Imagine condition is stable (CV 0.02–0.04).

### EEG Bad Channel Outliers (V8 Pipeline)

| Session | Bad Ch | Channels | Notes |
|---------|--------|----------|-------|
| **SUB_26 sess01** | **11** | Fp1,Fz,Cz,F4,Fp2,AF7,AF3,AFz,AF8,AF4,F2 | Entire frontal strip bad; processed with warning |
| **SUB_21 sess01** | **10** | FC5,T7,Pz,T8,F4,Fp2,FT7,C5,PO7,TP8 | At limit; also has goni issues |
| SUB_19 sess01 | 7 | FC5,FC1,P7,P8,C4,F4,F8 | |
| SUB_08 sess01 | 6 | F3,T7,T8,AF3,F5,FT7 | Temporal channels |
| SUB_17 sess01 | 5 | Fz,F3,F4,Fp2,F5 | Frontal channels |
| SUB_01 sess01 | 5 | T7,O2,T8,C5,PO8 | Temporal-occipital |

**Most common bad channel**: Fp2 (20/40 sessions) — typical frontal electrode contact issue.

### ICLabel Brain IC Outliers

QC threshold: brain>70% ≥2, brain>80% ≥2, brain>90% ≥1

| Session | >70% | >80% | >90% | Notes |
|---------|------|------|------|-------|
| **SUB_07 sess01** | 4 | 4 | **1** | >90% borderline |
| **SUB_07 sess02** | 5 | 4 | **1** | >90% borderline |
| **SUB_11 sess01** | **2** | **2** | **1** | All thresholds at minimum |
| **SUB_19 sess01** | **2** | **2** | **2** | All thresholds at minimum; also 7 bad ch |

**SUB_19_sess02**: **FAIL** QC (B70=1, B80=1, B90=1). Excluded from analysis.

All other sessions pass QC criteria, but SUB_07/11/19_sess01 are borderline — flag for extra scrutiny in downstream analysis.

### Other Exceptions

| Session | Issue |
|---------|-------|
| **SUB_24 sess01** | Only mixed-gender pair (female subject, male walker) |
| **SUB_25 sess01** | Female subject (with SUB_26) |
| **SUB_26 sess01** | Female subject (with SUB_25); 11 bad channels (frontal strip) |
| **SUB_01 sess01** | IOI alignment needed special sliding match (192s residual with naive 1:1 mapping) |

### V8 QC Summary (40 sessions)

| Status | Count | Details |
|--------|-------|---------|
| **PASS** | 39 | All except SUB_19_sess02 |
| **FAIL** | 1 | SUB_19_sess02 (ICLabel B70=1, B80=1, B90=1) |
| **Flagged** | 6 | SUB_04_sess02 (11 bad ch), SUB_10_sess01 (partial goni), SUB_19_sess01 (borderline QC), SUB_21_sess01 (10 bad ch + goni), SUB_26_sess01 (11 bad ch), SUB_28_sess01 (20 MI/20 Walk only) |

---

> **EEG preprocessing pipeline V8, bugs & lessons, goni channel index bug** → see `preprocessing_lessons.md`
