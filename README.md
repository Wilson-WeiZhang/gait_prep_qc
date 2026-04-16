# gait_prep_qc

Preprocessing, QC, alignment, and EEG-Goni pairing pipeline for the gait imagery project.

## Pipeline Overview

```
Raw EEG (.vhdr)  --> V8 Pipeline (prep_healthy_v8.m) --> step1/2/3.set + epochs.mat
Raw Goni (.txt)  --> Goni Extraction + IOI Alignment  --> _goni.mat (trial-segmented)
                           |
                  Pair EEG + Goni (pair_eeg_goni_v8.m) --> _paired.mat
```

## Output Summary (2026-04-14)

| Dataset | EEG V8 | Goni extracted | Paired | Notes |
|---------|--------|----------------|--------|-------|
| Healthy (28 subjects, 40 sessions) | 40/40 | 40/40 | 39/40 | SUB_10_sess01 excluded (8 trials, goni partial) |
| Patient usable (5 sessions) | 5/5 | 5/5 | 5/5 | MI condition only |
| Patient excluded (4 sessions) | 4/4 (step1-2) | 4/4 | -- | Bad REF (Cz >20kOhm) |

**Total paired data**: 44 sessions in `paired_data_v8/`

## Directory Structure

```
gait_prep_qc/
├── README.md                  # This file
├── code/
│   ├── prep_healthy_v8.m      # EEG V8 pipeline (works for both healthy & patient)
│   ├── extract_goni_all_healthy.m  # Healthy goni extraction + IOI alignment
│   ├── extract_goni_patient.m      # Patient goni extraction + S10 alignment
│   ├── pair_eeg_goni_v8.m          # EEG-Goni pairing (V8 epochs + goni)
│   ├── align_ioi.m            # IOI pattern matching alignment algorithm
│   ├── align_eeg_goni.m       # Patient S10/Stim alignment algorithm
│   ├── validate_alignment.m   # Post-alignment validation + QC output
│   ├── load_goniometer.m      # Goni enggunit.txt loader (UTF-16LE)
│   ├── build_healthy_goni_jobs.m   # Auto-discover healthy session jobs
│   ├── qc_goni_trial.m        # Condition-aware trial QC
│   ├── report_v8_summary.m    # V8 QC report (bad ch, ICLabel brain ICs)
│   ├── run_full_pipeline.m    # End-to-end pipeline orchestrator
│   ├── run_prep_v8.m          # Batch V8 runner for single-file sessions
│   ├── plot_ic_topo.m         # IC scalp topoplots (top 20, step2.set, ICLabel on-the-fly)
│   ├── plot_goni_qc.m         # Goni QC plots (3x2 grid, Walker/Subject channels)
│   ├── plot_alignment_qc.m    # EEG-Goni alignment QC figures (healthy + patient)
│   ├── generate_qc_report.m   # QC summary table (XLSX+CSV, 49 sessions)
│   ├── run_qc_report.m        # Master runner for all QC reports
│   ├── special_offsets/        # Per-session clock drift corrections
│   │   ├── SUB_07_sess02.m    # 2 segments, drift 0.244s
│   │   ├── SUB_16_sess02.m    # 2 segments, drift 8.01s
│   │   ├── SUB_19_sess02.m    # 3 segments, drift ~0.18s
│   │   └── SUB_27_sess01.m    # 3 segments, initial 2.4s + drift 0.257s
│   ├── utils/
│   │   ├── find_goni_idx.m    # Label-based goni channel lookup (NEVER hardcode index)
│   │   ├── parse_vmrk.m       # BrainVision marker parser (no EEGLAB needed)
│   │   ├── extract_goni_stim.m
│   │   ├── detect_gait_cycles.m
│   │   ├── circular_shift_surrogate.m
│   │   └── phase_randomize_surrogate.m
│   └── _archive/               # Superseded scripts (V2 pairing, one-off runners)
│
├── note/
│   ├── healthy_data_prep.md    # Study design, channel layout, alignment, QC, outliers
│   ├── patient_data_prep.md    # Patient protocols, markers, alignment, excluded sessions
│   ├── preprocessing_lessons.md # V8 pipeline details, bugs & fixes
│   └── align_special_cases.md  # Clock drift + SUB_12 file swap + SUB_10 diagnostics
│
└── result/
    ├── qc_report.xlsx          # Master QC table (49 sessions, PASS/WARN/FAIL/EXCLUDED)
    ├── qc_report.csv           # CSV fallback
    ├── qc_figs/
    │   ├── ic_topo/            # IC scalp topoplots (49 PNGs, top 20 ICs each)
    │   └── goni_qc/            # Goni joint angle QC plots (49 PNGs)
    └── goni_healthy/           # All goni .mat files (healthy + patient)
        ├── SUB_01_sess01_goni.mat ... SUB_28_sess01_goni.mat  (40 healthy)
        ├── P01_Sess01_goni.mat ... P02_Sess04_goni.mat        (9 patient)
        └── qc/
            ├── alignment_figs/ # EEG-Goni alignment QC figures (49 PNGs)
            └── align_qc_*.txt  # Per-segment alignment error tables
```

## EEG V8 Pipeline (prep_healthy_v8.m)

Same script for healthy and patient. Parameters:

| Step | Content | Output | Channels |
|------|---------|--------|----------|
| 1_ica | 1-40Hz BP, 59ch, for ICA training | `_step1_ica.set` | 59 |
| 1 | 0.1-40Hz BP, 59ch | `_step1.set` | 59 |
| 2 | Segments (no BL) -> bad ch -> interp -> +FCz -> CAR -> ASR(Walk,k=20) -> AMICA(1m,1000i) | `_step2.set` | 60 |
| 3 | 0.1Hz + bad ch -> interp -> +FCz -> CAR -> ASR -> ICA transfer -> ICLabel(>0.8) | `_step3.set` | 60 |
| 4 | Epoch by trial type | `_epochs_ica.mat` + `_epochs_bp.mat` | 60 |

**60ch = 59 brain + FCz (restored online reference)**

Key decisions:
- 59ch whitelist: EOG (HEL/VEL/HER/VEU) permanently excluded
- Online reference = FCz for both healthy and patient (patient vhdr labels it "REF" but same physical position)
- Bad REF patient sessions (P01_Sess03/04, P02_Sess01/02): max_step=2, no ICA transfer

QC thresholds: brain>70% >= 2, brain>80% >= 2, brain>90% >= 1

## Goni Alignment

### Healthy: IOI Pattern Matching (align_ioi.m)

EEG and Goni receive same TTL triggers. The inter-onset-interval (IOI) sequence acts as a unique fingerprint. Sliding window match finds the time offset.

- 35/40 sessions: 100% match, single offset
- 4 sessions: clock drift, per-segment offsets (see `special_offsets/`)
- 1 session (SUB_10_sess01): partial goni coverage (8/66 trials)

### Patient: S10 Stim Matching (align_eeg_goni.m)

S10 periodic sync triggers in EEG matched to Stim rising edges in Goni.

## QC Report Pipeline (run_qc_report.m)

Single command generates all QC visualizations + summary table:

```bash
cd ~/gait/gait_prep_qc/code && matlab -batch "run_qc_report"
```

| Step | Script | Output | Description |
|------|--------|--------|-------------|
| 1 | `plot_ic_topo.m` | `result/qc_figs/ic_topo/*.png` | Top 20 IC scalp maps from step2.set, ICLabel on-the-fly |
| 2 | `plot_goni_qc.m` | `result/qc_figs/goni_qc/*.png` | Joint angle traces (Hip/Knee/Ankle × MI/Walk), QC color-coded |
| 3 | `plot_alignment_qc.m` | `result/goni_healthy/qc/alignment_figs/*.png` | EEG-Goni trigger alignment residuals, segment-aware |
| 4 | `generate_qc_report.m` | `result/qc_report.xlsx` + `.csv` | 49-row summary: bad ch, ICs, ICLabel, goni trials, alignment, verdict |

**QC Verdict rules:**
- **EXCLUDED**: P01_Sess03/04, P02_Sess01/02 (bad REF, intentionally stopped at step2)
- **FAIL**: no step2.set, or >15 bad channels
- **WARN**: step2-only (non-excluded), >8 bad channels, >3 goni problems, >30ms alignment error
- **PASS**: everything else

**Design notes:**
- IC topoplots use step2.set (not step3) because step2 is the common denominator for all 49 sessions
- Patient goni.mat has different field names from healthy; scripts normalize inline
- Both healthy and patient sessions handled in all 4 scripts

## Known Outliers and Special Cases

### Excluded from analysis
- **SUB_10_sess01**: Goni Rec2 lost Stim + Walker channels after restart. Only 8 paired trials. SUB_10 relies on sess02 (60/60/30).
- **P01_Sess03, P01_Sess04**: Bad REF electrode (Cz impedance >20kOhm)
- **P02_Sess01, P02_Sess02**: Bad REF electrode

### Flagged but included
- **SUB_26_sess01**: 11/59 bad channels (frontal: Fp1/2, AF3/4/7/8/z, F2/4, Fz, Cz). Data rank=49. Sensorimotor area intact.
- **SUB_01_sess01**: Old experiment script. Rest encoded as R1+S4->S5. Fixed in extraction code.

### Clock drift sessions (per-segment offsets)
- **SUB_07_sess02**: 2 segments, drift 0.244s at ~1700s
- **SUB_16_sess02**: 2 segments, 8s offset jump at ~290s (Goni re-sync)
- **SUB_19_sess02**: 3 segments, gradual drift ~0.18s
- **SUB_27_sess01**: 3 segments, initial 2.4s mismatch + late drift 0.257s

### Data fixes applied to raw data
- **SUB_12_sess01**: Goni files were swapped between folders. Fixed on aa + NTU OneDrive (2026-04-13).

## Goni Channel Layout

23 channels (no Stim in output). W=Walker, S=Subject(Spectator).

**Channel ordering varies across sessions. NEVER hardcode indices. Always use `find_goni_idx(labels, 'LKneW X')`.**

Walker X-axis (6 joints): LHipW X, LKneW X, LAnkW X, RHipW X, RKneW X, RAnkW X
- LAnkW X missing in Type A sessions (SUB_01_01, SUB_02_01/02, SUB_03_01, SUB_04_01, SUB_05_01, SUB_06_01)
- RAnkS X globally missing

## Paired Data Format (paired_data_v8/)

Each `_paired.mat` contains:
```matlab
result.label        % 'SUB_01_sess01'
result.chanlocs     % 60-element struct (EEG channel locations)
result.goni_labels  % cell array of goni channel names
result.eeg_srate    % 250 (Hz, after resampling)
result.goni_srate   % 250 (Hz, resampled from 1000)
result.n_eeg_ch     % 60
result.n_goni_ch    % number of goni channels
result.paired.mi    % struct: eeg_epochs{N}, goni_epochs{N}, trial_dur, trial_table
result.paired.walk  % struct (same format)
result.paired.rest  % struct (same format)
result.session_ok   % true if all conditions matched
result.total_pairs  % total number of paired trials
```

## Documentation Index

| Document | Content |
|----------|---------|
| `note/healthy_data_prep.md` | Study design, channel layout, 30-cycle protocol, alignment algorithm, QC results, all outliers |
| `note/patient_data_prep.md` | RESTORE2 protocol, markers, reference electrode (FCz not Cz), excluded sessions, per-session summary |
| `note/preprocessing_lessons.md` | V8 pipeline evolution, parameter choices, bugs & fixes, non-ASCII issues |
| `note/align_special_cases.md` | Detailed diagnostics for clock drift (SUB_07/16/19/27), SUB_12 file swap, SUB_10 partial goni |
