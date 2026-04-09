# Patient Data Preparation & QC Notes (RESTORE2 SCI Study)

## 1. Study Design

Two spinal cord injury (SCI) patients undergoing epidural spinal cord stimulation (eSCS) rehabilitation. Longitudinal EEG recordings during imagined walking (gait imagery).

### Participants

| ID | Label | Surgery | Sessions | Stimulation |
|----|-------|---------|----------|-------------|
| Sub01 | RESTORE2_001 | Epidural SCS | 5 (Sess01–05) | OFF: Sess01–03, ON: Sess04–05 |
| Sub02 | RESTORE2_002 | Epidural SCS | 3 (Sess01–03) + Resting | OFF: Sess01, ON: Sess02–03 |

### Session Structure

```
S10 → S11 → [S4→S5]×5 → [S1→S2]×N → [S7→S8] → [S1→S2]×N → ... → S12 → S10
```

| # | Task | Who performs | Markers | Duration |
|---|------|-------------|---------|----------|
| 1 | Sit-to-Stand (×5) | Patient | S4 → S5 per rep | ~2 min |
| 2 | GI Block 1 | Patient (seated, imagines walking while watching walker) | S1 → S2 per trial | ~5 min |
| 3 | [6m Walk + GI] ×2 | Walker walks, patient watches then imagines | S3 → R1 (walk), S1 → S2 (GI) | varies |
| 4 | GI Block 2 | Patient | S1 → S2 | ~5 min |
| 5 | 2-Min Walk | Patient walks with FLOAT body-weight support | S7 → S8 | 2 min |
| 6 | GI Block 3 | Patient | S1 → S2 | ~5 min |

- GI trials per session: **20–55** (highly variable due to fatigue)
- S2S trials: 5–6
- 2-min Walk: only 3 usable segments across all 8 sessions

---

## 2. EEG Recording

| Parameter | Value |
|-----------|-------|
| Amplifier | actiCHamp Plus (Brain Products) |
| Channels | 63 (10-20 extended montage) |
| Online reference | **Cz** (differs from healthy FCz) |
| Ground | AFz |
| Sampling rate | 1000 Hz |
| Format | BrainVision (.vhdr / .vmrk / .eeg) |

### Reference Electrode Issues (Important!)

Sessions with bad REF (Cz): **Sub01_Sess03** (abandoned), **Sub01_Sess04**, **Sub02_Sess01**, **Sub02_Sess02**

- REF impedance > 20kΩ corrupts all channels via common-mode noise
- Average re-ref theoretically removes pure common-mode, but fails when REF noise is non-stationary or other channels are also bad
- Symptom: `clean_rawdata` flagging 16–38/63 channels = hallmark of bad REF

---

## 3. Event Markers

### Standard Markers (Sess03 onward)

| Marker | Meaning | Count/session | Role |
|--------|---------|---------------|------|
| S 10 | Periodic sync trigger | 83–144 | **Primary alignment anchor** (NOT an experiment event) |
| S 11 | Experiment START | 1 | Trim boundary |
| S 12 | Experiment END | 1 (missing in Sub02_Sess03) | Trim boundary |
| **S 1** | **Gait Imagery START** | 20–55 | Trial epoch boundary |
| **S 2** | **Gait Imagery END** | 20–55 | Trial epoch boundary |
| S 3 | 6-Meter Walk START | varies | |
| R 1 | 6-Meter Walk END | varies | |
| S 4 | Sit-to-Stand START | 5–6 | |
| S 5 | Sit-to-Stand END | 5–6 | |
| S 6 | Relax Break START | varies | |
| S 7 | 2-Min Walk START | 0–1 | Actual walking |
| S 8 | 2-Min Walk END | 0–1 | Actual walking |
| S 20/S 21 | Relax Break START/END | varies | Alternate naming |

### Legacy Markers (Sub01 Sess01–02 only, before 22 Dec 2025)

| Marker | Legacy meaning |
|--------|---------------|
| S 1 | Eyes Close Start / Imagine Start |
| S 3 | 6-Meter Walk Start |
| S 7 / S 8 | 2-Min Walk Start / End |
| S 13 / S 14 | 6MW Pause / Resume |

- **No S11/S12** in early sessions
- S1/S2 in Sess01 files 0009–0012 appear to use standard GI meaning despite early protocol

### S11/S12 Trimming Lessons

- S11/S12 unreliable across sessions: missing, duplicated, or misordered
- Sub02_Sess03: S11 present but no S12 marker
- Pipeline must handle missing S11/S12 gracefully (skip trim or use S10 bookends)

---

## 4. EEG–Goniometer Alignment (Patient)

### Strategy: S10/Stim Periodic Trigger Matching

Patient data has **periodic S10 sync pulses** (~83–144 per session), providing dense alignment anchor grid.

#### Algorithm (`align_eeg_goni.m`)

1. **Extract goni Stim edges:** threshold > 5V, merge pulses within 5ms
2. **Simple alignment:** anchor first S10 = first Stim rising edge, compute offset
3. **Validate:** check inter-event intervals (IEI) between matched pairs, 100ms tolerance
4. **Fallback** (if simple fails): brute-force search — try each S10 as anchor, accept >80% IEI match
5. **Output:** `offset_sec` such that `goni_time = eeg_time + offset`

#### Post-Alignment Validation

- Trigger correspondence table: `qc/align/trigger_table_*.txt`
- 4-panel QC plot: `qc/QC_align_*.png`
- Maximum timing error across all sessions: **43ms**

### Alignment Quality Per Session

| Session | S10 | Stim | Matched | Max err | Notes |
|---------|-----|------|---------|---------|-------|
| Sub01_Sess01 (×6 files) | 83 | 83 | 83 | 43ms | 100% |
| Sub01_Sess02 (×3 files) | 83 | 83 | 83 | 43ms | 100% |
| Sub01_Sess03 (Goni1) | 103 | 59 | 59 | — | Goni restarted mid-session |
| Sub01_Sess03 (Goni2) | 103 | 44 | 44 | — | Second goni file |
| Sub01_Sess04 (F1) | 83 | 82 | 82 | — | Goni gap 335–775s, 1 stim lost |
| Sub01_Sess04 (F2) | 83 | 83 | 83 | 41ms | 100% |
| Sub01_Sess05 | 83 | 83 | 83 | 41ms | 100% |
| Sub02_Sess01 | 144 | 144 | 144 | 41ms | 100% |
| Sub02_Sess02 | 144 | 144 | 144 | 41ms | 100% |
| Sub02_Sess03 | 144 | 145 | 144 | — | 1 spurious stim at goni end |

### 2-Min Walk (S7/S8) Availability

Only **3 usable segments** across all sessions:

| Session | S7 | End | Method |
|---------|-----|-----|--------|
| Sub01_Sess01 | 2486s | 2608s | S8 marker |
| Sub02_Sess01 | 2050s | 2170s | S7 + 120s |
| Sub02_Sess02 | 2253s | 2373s | S7 + 120s |

Other S7 events excluded:
- Sub01_Sess03: short walk trials (~20s apart), not 2-min walk
- Sub01_Sess05: only 49s before recording ended
- Sub02_Sess01 second S7: only 13s before S12

---

## 5. Standard Data Structure (Per Session)

### Raw Data Directory

```
SUBJECT-0X/RESTORE2_00X_SessNN/sessNN_{date}/
├── EEG/
│   └── RESTORE2-{NNNN}.vhdr/.vmrk/.eeg       # BrainVision, 1000Hz, 63ch + Cz ref
│       (multiple files per session possible — see multi-file sessions below)
├── Goniometer/
│   └── *_enggunit.txt                          # UTF-16LE, 1000Hz, goni channels + Stim
│       (also .cnt binary + .log metadata)
└── (no PyLog — patient sessions use EEG markers only)
```

### Expected EEG Marker Counts (Standard Session, Sess03+)

| Marker | Expected | Meaning |
|--------|----------|---------|
| S 10 | 83–144 | Periodic sync trigger (alignment anchor) |
| S 11 | 1 | Experiment START |
| S 12 | 1 | Experiment END |
| S 1 | 20–55 | GI START (variable by fatigue) |
| S 2 | 20–55 | GI END |
| S 4 | 5–6 | S2S START |
| S 5 | 5–6 | S2S END |
| S 7 | 0–1 | 2-Min Walk START |
| S 8 | 0–1 | 2-Min Walk END |
| S 3 / R 1 | varies | 6m Walk START / END |

### Trial Duration Statistics

- Total raw S1–S2 pairs (all sessions): 318
- After rejection (< 5.5s): 317 kept, 1 rejected
- Duration range: 5.88–14.61s; Median: 7.16s, Mean: 7.34s
- Filtering: 5.5s centered in S1–S2 interval, outlier threshold ±3 MAD

---

## 6. Outlier & Exception List

### EEG Marker Exceptions

| Session | Issue | Impact | Handling |
|---------|-------|--------|----------|
| **Sub01 Sess01–02** | Legacy markers (before 22 Dec 2025): no S11/S12, different S1 meaning | Cannot auto-trim by S11/S12 | Skip trim; S1/S2 in files 0009–0012 still mean GI |
| **Sub02 Sess03** | S11 present but **no S12** | Cannot trim end | Use S10 bookend or recording end |

### Multi-File Sessions

| Session | Files | Handling |
|---------|-------|----------|
| **Sub01 Sess01** | 6 files (0001, 0008–0012) | `pop_mergeset`; 0001/0008 have no GI → discard; USB error in 0010 |
| **Sub01 Sess02** | 3 files (0013–0015) | `pop_mergeset`; all contain GI |
| **Sub01 Sess04** | 2 files (0016, 0018) | `pop_mergeset`; file 2 = S2S only |

### Bad Reference Electrode (Cz)

| Session | REF impedance | Bad ch flagged by clean_rawdata | Status |
|---------|--------------|--------------------------------|--------|
| **Sub01 Sess03** | > 20kΩ | 16–38/63 | **Abandoned** |
| **Sub01 Sess04** | > 20kΩ | elevated | Processed with caution |
| **Sub02 Sess01** | > 20kΩ | elevated | Processed with caution |
| **Sub02 Sess02** | > 20kΩ | elevated | Processed with caution |

### Stimulation Artifact (eSCS ON)

| Session | Stim | Decoding PCC | clean_rawdata bad ch | Notes |
|---------|------|-------------|---------------------|-------|
| Sub01 Sess01–03 | OFF | High | Normal | Baseline |
| Sub01 Sess04–05 | ON | **Dropped significantly** | Normal (except Sess04 goni) | eSCS EM artifact hypothesis |
| **Sub02 Sess04** | ON (stronger params) | — | **33/59 at corr=0.8** | corr=0.7→11, corr=0.6→3 |

### Goniometer Issues

| Session | Issue |
|---------|-------|
| **Sub01 Sess03** | Goni restarted mid-session → 2 goni files (59 + 44 stim onsets vs 103 S10) |
| **Sub01 Sess04** | Goni gap 335–775s in file 1; 1 stim trigger lost |
| **Sub02 Sess03** | 1 spurious stim pulse at goni end (145 vs 144 S10) |

### 2-Min Walk (S7/S8) — Mostly Unusable

Only **3 usable** out of 8 sessions:

| Session | S7 time | End | Method | Usable? |
|---------|---------|-----|--------|---------|
| Sub01 Sess01 | 2486s | 2608s | S8 marker | Yes |
| Sub02 Sess01 | 2050s | 2170s | S7 + 120s | Yes |
| Sub02 Sess02 | 2253s | 2373s | S7 + 120s | Yes |
| Sub01 Sess03 | — | — | S7s are short walk trials | No |
| Sub01 Sess05 | — | — | Only 49s before recording ended | No |
| Sub02 Sess01 (2nd) | — | — | Only 13s before S12 | No |

### Resting State (Sub02_Resting) — Non-Standard

No S10/S1/S2 markers. Uses dedicated condition markers:

| Segment | Start Marker | Duration | Condition |
|---------|-------------|----------|-----------|
| 1 | `eye_open_stim_off` (66s) | ~122s | EO + Stim OFF |
| 2 | `eye_close_stim_off` (213s) | ~117s | EC + Stim OFF |
| 3 | `eye_open_stim_on` (960s) | ~121s | EO + Stim ON |
| 4 | `eye_close_stim_on` (1100s) | ~119s | EC + Stim ON |

No goniometer alignment needed.

### Per-Session Summary

| Session | Subject | Date | Files | GI Trials | Stim | Key Issues |
|---------|---------|------|-------|-----------|------|------------|
| Sess01 | Sub01 | 30 Oct 2025 | 6 | 51 | OFF | Legacy markers, USB error in 0010 |
| Sess02 | Sub01 | 13 Nov 2025 | 3 | ~53 | OFF | Shoulder movement in Block 2 |
| Sess03 | Sub01 | 22 Dec 2025 | 1 | ~29 | OFF | **Bad REF → abandoned**; fatigued |
| Sess04 | Sub01 | 20 Jan 2026 | 2 | ~27 | ON | Bad REF; goni disconnections |
| Sess05 | Sub01 | 20 Feb 2026 | 1 | ~45 | ON | Standard |
| Sess01 | Sub02 | 05 Jan 2026 | 1 | ~29 | OFF | Bad REF |
| Sess02 | Sub02 | 29 Jan 2026 | 1 | ~39 | ON | Bad REF |
| Sess03 | Sub02 | 02 Mar 2026 | 1 | ~44 | ON | No S12; 1 spurious goni stim |

---

> **EEG preprocessing pipeline, bugs & lessons** → see `preprocessing_lessons.md`
