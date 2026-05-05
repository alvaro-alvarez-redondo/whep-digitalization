# Pipeline Performance Report: perf_1-import_pipeline

- Stage identifier: 1-import
- Preset: standard
- Total functions benchmarked: 7
- Dominant complexity class: O(n^3)
- Stage runtime share: 87.9%
- Stage risk score: 0.6372
- Highest-complexity function: discover_excel_files (O(n^3))
- Primary bottleneck candidate: read_excel_file_sheets (O(1), 73.6% impact)
- Runtime projection sample n values: 1000, 100000, 10000000

## Stage KPI Dashboard

```text
| KPI                         | Value                                 |
| --------------------------- | ------------------------------------- |
| Total functions benchmarked | 7                                     |
| Dominant complexity class   | O(n^3)                                |
| Stage runtime total (s)     | 478.83                                |
| Stage runtime share         | 87.9%                                 |
| Expensive function share    | 28.6%                                 |
| Stage risk score            | 0.6372                                |
| Top runtime driver          | read_excel_file_sheets (73.6%)        |
| Top composite bottleneck    | read_excel_file_sheets (score 0.4077) |
```

## Function-Level Performance Matrix

```text
| Function                     | Description                                          | Complexity | adj.R2   | Slope per n         | Estimated runtime (sample n)                         | Relative impact | Indicator            | Bottleneck | Complexity rank | Confidence | Observed runtime total (s) | Runtime at max n (s) | Volatility cv | p99/p50 ratio | Growth max | Composite score | Flags                      | Dominant in stage | Likely slowdown drivers                              |
| ---------------------------- | ---------------------------------------------------- | ---------- | -------- | ------------------- | ---------------------------------------------------- | --------------- | -------------------- | ---------- | --------------- | ---------- | -------------------------- | -------------------- | ------------- | ------------- | ---------- | --------------- | -------------------------- | ----------------- | ---------------------------------------------------- |
| read_excel_file_sheets       | read n synthetic workbook sheets (fixed rows per sh~ | O(1)       | 0        | N/A                 | n=1000: N/A s; n=100000: N/A s; n=10000000: N/A s    | 73.6%           | ! (high_impact)      | no         | 1               | very low   | 352.56                     | 71.967               | 0.067524      | 1.053         | 1.065      | 0.4077          | high_impact/low_confidence | no                | runtime concentration is high (73.6% of stage runti~ |
| reshape_to_long              | melt n-row wide table (40 year cols) to long format  | O(n^2)     | 0.999481 | 0.00000000000101169 | n=1000: 0.000001012 s; n=100000: 0.01012 s; n=10000~ | 22.0%           | !! (high_complexity) | no         | 5               | very high  | 105.43                     | 101.8                | 0.050175      | 1.065         | 32         | 0.3171          | high_complexity            | no                | reshape pressure likely amplifies memory movement; ~ |
| discover_excel_files         | discover synthetic xlsx files with n-scaled workboo~ | O(n^3)     | 0.973458 | 0.0000000908322     | n=1000: 90.83 s; n=100000: 90832190 s; n=10000000: ~ | 0.3%            | !! (high_complexity) | no         | 6               | high       | 1.4837                     | 0.3449               | 0.11205       | 1.201         | 1.31       | 0.3051          | high_complexity            | yes               | super-linear class (O(n^3)) raises asymptotic risk   |
| normalize_key_fields         | normalize commodity/variable/continent/country in n-r~ | O(n)       | 0.996543 | 0.000000912336      | n=1000: 0.0009123 s; n=100000: 0.09123 s; n=1000000~ | 2.2%            | ? (watch)            | no         | 3               | very high  | 10.607                     | 9.183                | 0.39262       | 1.668         | 28.44      | 0.1283          | high_volatility            | no                | reshape pressure likely amplifies memory movement; ~ |
| detect_duplicates_dt         | detect duplicate keys in n-row long table (2% dups)  | O(n)       | 0.999791 | 0.000000624769      | n=1000: 0.0006248 s; n=100000: 0.06248 s; n=1000000~ | 1.4%            | . (ok)               | no         | 3               | very high  | 6.8685                     | 6.2389               | 0.03108       | 1.053         | 11.34      | 0.1251          | ok                         | no                | grouping across repeated keys increases hash/scan c~ |
| consolidate_audited_dt       | consolidate and reorder columns in a list of n-row ~ | O(n)       | 0.999848 | 0.0000000937437     | n=1000: 0.00009374 s; n=100000: 0.009374 s; n=10000~ | 0.2%            | . (ok)               | no         | 3               | very high  | 1.0429                     | 0.93841              | 0.038253      | 1.083         | 10.85      | 0.1208          | ok                         | no                | sorting/reordering work adds comparison overhead; r~ |
| validate_mandatory_fields_dt | check mandatory non-empty fields in n-row long table | O(n)       | 0.999664 | 0.0000000761593     | n=1000: 0.00007616 s; n=100000: 0.007616 s; n=10000~ | 0.2%            | . (ok)               | no         | 3               | very high  | 0.83957                    | 0.76115              | 0.03145       | 1.061         | 11.61      | 0.1207          | ok                         | no                | runtime jumps sharply between sizes (max 11.61x)     |
```

## Bottleneck Candidates

- read_excel_file_sheets: class O(1), score 0.4077, impact 73.6%, flags high_impact/low_confidence.
- reshape_to_long: class O(n^2), score 0.3171, impact 22.0%, flags high_complexity.
- discover_excel_files: class O(n^3), score 0.3051, impact 0.3%, flags high_complexity.
- normalize_key_fields: class O(n), score 0.1283, impact 2.2%, flags high_volatility.
- detect_duplicates_dt: class O(n), score 0.1251, impact 1.4%, flags ok.

## Top Bottlenecks by Composite Score

```text
| Rank | Function               | Complexity | Composite score | Stage impact | adj.R2  | Confidence | Volatility cv | Growth max | Flags                      | Likely slowdown drivers                              |
| ---- | ---------------------- | ---------- | --------------- | ------------ | ------- | ---------- | ------------- | ---------- | -------------------------- | ---------------------------------------------------- |
| 1    | read_excel_file_sheets | O(1)       | 0.4077          | 73.6%        | 0       | very low   | 0.067524      | 1.065      | high_impact/low_confidence | runtime concentration is high (73.6% of stage runti~ |
| 2    | reshape_to_long        | O(n^2)     | 0.3171          | 22.0%        | 0.99948 | very high  | 0.050175      | 32         | high_complexity            | reshape pressure likely amplifies memory movement; ~ |
| 3    | discover_excel_files   | O(n^3)     | 0.3051          | 0.3%         | 0.97346 | high       | 0.11205       | 1.31       | high_complexity            | super-linear class (O(n^3)) raises asymptotic risk   |
| 4    | normalize_key_fields   | O(n)       | 0.1283          | 2.2%         | 0.99654 | very high  | 0.39262       | 28.44      | high_volatility            | reshape pressure likely amplifies memory movement; ~ |
| 5    | detect_duplicates_dt   | O(n)       | 0.1251          | 1.4%         | 0.99979 | very high  | 0.03108       | 11.34      | ok                         | grouping across repeated keys increases hash/scan c~ |
```

## Confidence and Uncertainty Summary

```text
| Metric                      | Value   |
| --------------------------- | ------- |
| Mean adjusted R2            | 0.85268 |
| Median adjusted R2          | 0.99948 |
| Low-confidence functions    | 1       |
| Low-confidence share        | 14.3%   |
| High-volatility functions   | 1       |
| High-volatility share       | 14.3%   |
| Critical bottlenecks        | 0       |
| Runtime concentration (HHI) | 0.59132 |
```

## Optimization Priority Queue

```text
| Priority tier | Function               | Complexity | Composite score | Stage impact | Reason                                               | Expected impact           | Flags                      |
| ------------- | ---------------------- | ---------- | --------------- | ------------ | ---------------------------------------------------- | ------------------------- | -------------------------- |
| P2            | read_excel_file_sheets | O(1)       | 0.4077          | 73.6%        | large runtime share; low model confidence            | up to 73.6% stage runtime | high_impact/low_confidence |
| P2            | reshape_to_long        | O(n^2)     | 0.3171          | 22.0%        | super-linear growth risk; sharp growth jump (max 32~ | up to 22.0% stage runtime | high_complexity            |
| P2            | discover_excel_files   | O(n^3)     | 0.3051          | 0.3%         | super-linear growth risk                             | up to 0.3% stage runtime  | high_complexity            |
| P2            | normalize_key_fields   | O(n)       | 0.1283          | 2.2%         | unstable repeated timings; sharp growth jump (max 2~ | up to 2.2% stage runtime  | high_volatility            |
| P2            | detect_duplicates_dt   | O(n)       | 0.1251          | 1.4%         | sharp growth jump (max 11.34x)                       | up to 1.4% stage runtime  | ok                         |
```

## Stage Narrative

- Runtime is dominated by read_excel_file_sheets, contributing 73.6% of stage runtime.
- Asymptotic risk is dominated by discover_excel_files with class O(n^3).
- Optimize first: read_excel_file_sheets because large runtime share; low model confidence; expected impact up to 73.6% stage runtime.

## Complexity Distribution (ASCII)

```text
| Complexity class | Function count | Function share | Runtime share | Distribution             |
| ---------------- | -------------- | -------------- | ------------- | ------------------------ |
| O(1)             | 1              | 14.3%          | 73.6%         | ##################------ |
| O(n^2)           | 1              | 14.3%          | 22.0%         | #####------------------- |
| O(n)             | 4              | 57.1%          | 4.0%          | #----------------------- |
| O(n^3)           | 1              | 14.3%          | 0.3%          | ------------------------ |
```

## Runtime Share Distribution (ASCII)

```text
| Function                     | Relative impact | Composite score | Distribution             |
| ---------------------------- | --------------- | --------------- | ------------------------ |
| read_excel_file_sheets       | 73.6%           | 0.4077          | ##################------ |
| reshape_to_long              | 22.0%           | 0.3171          | #####------------------- |
| normalize_key_fields         | 2.2%            | 0.1283          | #----------------------- |
| detect_duplicates_dt         | 1.4%            | 0.1251          | ------------------------ |
| discover_excel_files         | 0.3%            | 0.3051          | ------------------------ |
| consolidate_audited_dt       | 0.2%            | 0.1208          | ------------------------ |
| validate_mandatory_fields_dt | 0.2%            | 0.1207          | ------------------------ |
```

## Runtime Projection Grid

```text
| Function                     | n        | Estimated runtime (s) |
| ---------------------------- | -------- | --------------------- |
| consolidate_audited_dt       | 1000     | 0.000093744           |
| detect_duplicates_dt         | 1000     | 0.00062477            |
| discover_excel_files         | 1000     | 90.832                |
| normalize_key_fields         | 1000     | 0.00091234            |
| read_excel_file_sheets       | 1000     | N/A                   |
| reshape_to_long              | 1000     | 0.0000010117          |
| validate_mandatory_fields_dt | 1000     | 0.000076159           |
| consolidate_audited_dt       | 100000   | 0.0093744             |
| detect_duplicates_dt         | 100000   | 0.062477              |
| discover_excel_files         | 100000   | 90832190              |
| normalize_key_fields         | 100000   | 0.091234              |
| read_excel_file_sheets       | 100000   | N/A                   |
| reshape_to_long              | 100000   | 0.010117              |
| validate_mandatory_fields_dt | 100000   | 0.0076159             |
| consolidate_audited_dt       | 10000000 | 0.93744               |
| detect_duplicates_dt         | 10000000 | 6.2477                |
| discover_excel_files         | 10000000 | 90832189950652        |
| normalize_key_fields         | 10000000 | 9.1234                |
| read_excel_file_sheets       | 10000000 | N/A                   |
| reshape_to_long              | 10000000 | 101.17                |
| validate_mandatory_fields_dt | 10000000 | 0.76159               |
```
