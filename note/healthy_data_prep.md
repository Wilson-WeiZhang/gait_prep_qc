# Healthy Subject Data Preparation & QC Notes (A2Walk Study)

## 1. Study Design

26 healthy subjects (SUB_01–SUB_26), each paired with a Walker. Each session = **30 cycles x 5 trials = 150 trials**, ~57 min recording.

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

## 4. EEG–Goniometer Alignment (Healthy)

### Strategy: IOI Pattern Matching

Unlike patient data (which has periodic S10 sync pulses), healthy data uses **Inter-Onset-Interval (IOI) substring matching**:

1. The experiment PC sends TTL triggers to **both** EEG amplifier and goniometer system simultaneously
2. Goniometer records triggers in its embedded **Stim channel** (values: 0, 2, 6, 8, 10, 14, 16 — bit-coded)
3. Total goni stim onsets = total EEG stimulus markers (302 for typical session) → 1:1 correspondence
4. Cross-correlate IOI sequences of goni stim onsets vs EEG marker positions
5. Yields single time offset (typically ~70s, because goni recording starts before EEG experiment)

### Alignment Quality

- Residuals < 50ms verified across all 13 healthy sessions
- Example: SUB_02 Sess01 — mean residual = 0.012s, max = 0.052s

### SUB_01 Sess01 Special Case

This session uses the old experiment script with 303 EEG markers vs 303 goni onsets. Direct 1:1 mapping gave 192s residual. Solution: IOI substring sliding alignment (positional mapping via IEI pattern matching). Result: 302/303 matched with correct offset.

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
| SUB_10 sess01 | 2 | 8 + ? | |
| **SUB_22 sess01** | **3** | 78 + 3 + 70 | Goni wireless disconnection → mid-session restart; segment 2 has no S11 → visual alignment by Neethu |

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

### Other Exceptions

| Session | Issue |
|---------|-------|
| **SUB_24 sess01** | Only mixed-gender pair (female subject, male walker) |
| **SUB_01 sess01** | IOI alignment needed special sliding match (192s residual with naive 1:1 mapping) |

---

> **EEG preprocessing pipeline, bugs & lessons, goni channel index bug** → see `preprocessing_lessons.md`
