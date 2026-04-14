# Alignment Special Cases (Healthy)

Out of 40 healthy sessions, 36 align perfectly (100% match, single offset, residual < 50ms).
Three sessions require **per-segment offset** due to clock drift. One session has late goni start.

## SUB_12_sess01 -- Goni Files Swapped (fixed 2026-04-13)

The two goni files (`sess1_1` and `sess1_2`) were copied into the wrong recording folders by Aung Aung. `sess1_2` was in the first EEG folder and `sess1_1` in the second. Reported by Liu Rui with misalignment figures. **Fix**: swapped the files back to correct folders on aa. No code workaround needed.

Joint angle data is fully continuous in both cases -- no disconnection, no zeros, no jumps.

---

## SUB_07_sess02

**Summary**: Clock drift of ~0.244s over 28 minutes. Single offset matches first 199/302 triggers; remaining 103 fail because cumulative drift exceeds 100ms tolerance.

**Evidence** (from diagnostic 2026-04-13):
- Goni: 302 stim onsets, recording 2546s, fully continuous
- Joint data around break point (~1660s): range [-12, +20] deg, std=4.9, zero samples=143/120001 (normal)
- Large IOI gaps: 42.9s (onset 11-12), 87.1s (onset 101-102), 94.3s (onset 201-202) -- all are real experiment breaks, consistent with EEG

**Per-segment offsets**:

| Segment | Goni triggers | Offset (s) | Drift from Seg 1 |
|---------|--------------|------------|-------------------|
| 1 (triggers 1-199) | 1-199 | -28.085 | baseline |
| 2 (triggers 200-302) | 200-302 | -27.841 | +0.244s |

**Fix**: Use two offsets. Expected residual after fix: < 31ms (max observed within matched segments).

---

## SUB_27_sess01

**Summary**: Initial clock offset of ~2.4s that resolves after ~260s, then gradual drift of ~0.257s over the session. Goni has 304 onsets vs EEG 302 (2 extra, 1 removed by spurious filter).

**Evidence** (from diagnostic 2026-04-13):
- Goni: 304 stim onsets (after spurious filter), recording 3226s, fully continuous
- Joint data at all check points: no zeros, no jumps, std 0.3-0.8 (normal)
- 498s gap between onset 102-103: identical in both EEG and Goni (real experiment break)

**Per-segment offsets**:

| Segment | EEG triggers | Offset (s) | Note |
|---------|-------------|------------|------|
| A (1-21) | 37-255s | -11.840 | Initial clock mismatch, 2.4s off from B |
| B (22-101) | 265-971s | -9.424 | Primary alignment |
| C (102-130) | 1469-1691s | -9.424 | Same as B (post-break, clock still OK) |
| D (131-302) | 1701s+ | -9.167 | +0.257s drift from B |

**Fix**: Use segment-specific offsets. Segment A needs special attention (large initial offset). Expected residual after fix: < 26ms.

**Open question**: Why is Segment A offset so different? Possible cause: Goni DataLITE receiver started recording ~2.4s before the EEG amplifier began receiving TTL triggers, or there was an initial buffering delay in the EEG system.

---

## SUB_19_sess02

**Summary**: Clock drift with 3 phases. Signed errors: -99ms (early), +13ms (middle), +84ms (late). Total drift ~183ms over the full session (~2800s).

**Evidence** (from diagnostic 2026-04-13):
- EEG: 302 events, Goni: 303 stim onsets
- Global offset: 28.357s. All 302 events matched (within 250ms tolerance)
- Phase 1 (events 1-60, 8-608s): signed error median = -99ms
- Phase 2 (events 61-201, 618-1821s): signed error median = +13ms
- Phase 3 (events 202-302, 2096-2793s): signed error median = +84ms
- Sharp transition at ~610s (error drops from -83ms to -19ms) and ~2095s (jumps from +17ms to +80ms)

**Per-segment offsets**:

| Segment | EEG time range | Offset (s) | Note |
|---------|---------------|------------|------|
| A (0-610s) | 8-608s | 28.258 | Early: goni clock behind |
| B (610-2090s) | 618-1821s | 28.370 | Middle: near baseline |
| C (2090s+) | 2096-2793s | 28.441 | Late: goni clock ahead |

**Fix**: Per-segment offsets in `get_special_offsets()`. Re-extraction: 100% match, 60/60/30 trials, 0 problems.

---

## SUB_16_sess02 -- Late Goni Start

**Summary**: Goni recording started ~4.5 minutes after EEG. First 27 EEG events (41-285s) have no goni counterpart. Not clock drift.

**Evidence**:
- EEG: 301 events, Goni: 302 events
- 274/301 matched (91.0%), all 27 mismatches at the start
- From event 29 (302s): perfect alignment, mean error 10ms, max 40ms
- 60/60/30 trials extracted (all from matched region)

**No code change needed** — pipeline handles partial matches correctly.

---

## SUB_10_sess01 -- Partial Goni Coverage

**Summary**: Multi-file session. Goni only captured 41 out of ~302 EEG events. EEG has 66/65/32 epochs (multi-file merge succeeded). Goni has 8/8/4 trials.

**Decision**: Exclude from primary analysis (insufficient paired EEG-goni data for CCA/decoding).

---

## Implementation

The `extract_goni_all_healthy.m` pipeline should detect these cases (match_frac < 100%) and automatically try per-segment offsets:

1. Run initial single-offset alignment
2. If match_frac < 95%, identify contiguous matched/unmatched regions
3. For each unmatched region, compute a local offset using the nearest matched triggers as anchors
4. Re-validate with per-segment offsets
5. Store all segment offsets in `align_info`

This keeps the standard pipeline simple for the 35 normal sessions while handling the 2 special cases automatically.
