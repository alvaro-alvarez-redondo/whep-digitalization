# Pipeline Performance Report: perf_1-import_pipeline

- Stage identifier: 1-import
- Preset: quick
- Total functions benchmarked: 7
- Dominant complexity class: unknown
- Stage runtime share: 99.9%
- Stage risk score: 0.8282
- Highest-complexity function: read_excel_file_sheets (unknown)
- Primary bottleneck candidate: read_excel_file_sheets (unknown, 99.7% impact)
- Runtime projection sample n values: 1000, 10000

## Stage KPI Dashboard

```text
| KPI                         | Value                                 |
| --------------------------- | ------------------------------------- |
| Total functions benchmarked | 7                                     |
| Dominant complexity class   | unknown                               |
| Stage runtime total (s)     | 104                                   |
| Stage runtime share         | 99.9%                                 |
| Expensive function share    | 100.0%                                |
| Stage risk score            | 0.8282                                |
| Top runtime driver          | read_excel_file_sheets (99.7%)        |
| Top composite bottleneck    | read_excel_file_sheets (score 0.7988) |
```

## Function-Level Performance Matrix

```text
| Function                     | Description                                          | Complexity | adj.R2 | Slope per n | Estimated runtime (sample n)  | Relative impact | Indicator            | Bottleneck | Complexity rank | Confidence | Observed runtime total (s) | Runtime at max n (s) | Volatility cv | p99/p50 ratio | Growth max | Composite score | Flags                                                | Dominant in stage | Likely slowdown drivers                              |
| ---------------------------- | ---------------------------------------------------- | ---------- | ------ | ----------- | ----------------------------- | --------------- | -------------------- | ---------- | --------------- | ---------- | -------------------------- | -------------------- | ------------- | ------------- | ---------- | --------------- | ---------------------------------------------------- | ----------------- | ---------------------------------------------------- |
| read_excel_file_sheets       | read n synthetic workbook sheets (fixed rows per sh~ | unknown    | N/A    | N/A         | n=1000: N/A s; n=10000: N/A s | 99.7%           | !!! (critical)       | yes        | 7               | unknown    | 103.64                     | 52.436               | 0.027033      | 1.006         | 1.024      | 0.7988          | high_complexity/high_impact/low_confidence/critical~ | yes               | super-linear class (unknown) raises asymptotic risk~ |
| discover_excel_files         | discover synthetic xlsx files with n-scaled workboo~ | unknown    | N/A    | N/A         | n=1000: N/A s; n=10000: N/A s | 0.3%            | !! (high_complexity) | no         | 7               | unknown    | 0.32296                    | 0.16009              | 0.077297      | 1.087         | 0.9829     | 0.4511          | high_complexity/low_confidence                       | yes               | super-linear class (unknown) raises asymptotic risk~ |
| normalize_key_fields         | normalize commodity/variable/continent/country in n-r~ | unknown    | N/A    | N/A         | n=1000: N/A s; n=10000: N/A s | 0.0%            | !! (high_complexity) | no         | 7               | unknown    | 0.0093609                  | 0.0064025            | 0.11817       | 1.214         | 2.164      | 0.45            | high_complexity/low_confidence                       | yes               | reshape pressure likely amplifies memory movement; ~ |
| detect_duplicates_dt         | detect duplicate keys in n-row long table (2% dups)  | unknown    | N/A    | N/A         | n=1000: N/A s; n=10000: N/A s | 0.0%            | !! (high_complexity) | no         | 7               | unknown    | 0.0089491                  | 0.0053343            | 0.16434       | 1.261         | 1.476      | 0.45            | high_complexity/low_confidence                       | yes               | grouping across repeated keys increases hash/scan c~ |
| reshape_to_long              | melt n-row wide table (10 year cols) to long format  | unknown    | N/A    | N/A         | n=1000: N/A s; n=10000: N/A s | 0.0%            | !! (high_complexity) | no         | 7               | unknown    | 0.0057904                  | 0.0047265            | 0.10372       | 1.156         | 4.443      | 0.45            | high_complexity/low_confidence                       | yes               | reshape pressure likely amplifies memory movement; ~ |
| consolidate_audited_dt       | consolidate and reorder columns in a list of n-row ~ | unknown    | N/A    | N/A         | n=1000: N/A s; n=10000: N/A s | 0.0%            | !! (high_complexity) | no         | 7               | unknown    | 0.003162                   | 0.0017185            | 0.17273       | 1.29          | 1.191      | 0.45            | high_complexity/low_confidence                       | yes               | sorting/reordering work adds comparison overhead; s~ |
| validate_mandatory_fields_dt | check mandatory non-empty fields in n-row long table | unknown    | N/A    | N/A         | n=1000: N/A s; n=10000: N/A s | 0.0%            | !! (high_complexity) | no         | 7               | unknown    | 0.0015533                  | 0.001112             | 0.26507       | 1.089         | 2.52       | 0.45            | high_complexity/low_confidence/high_volatility       | yes               | super-linear class (unknown) raises asymptotic risk~ |
```

## Bottleneck Candidates

- read_excel_file_sheets: class unknown, score 0.7988, impact 99.7%, flags high_complexity/high_impact/low_confidence/critical_bottleneck.
- discover_excel_files: class unknown, score 0.4511, impact 0.3%, flags high_complexity/low_confidence.
- normalize_key_fields: class unknown, score  0.45, impact 0.0%, flags high_complexity/low_confidence.
- detect_duplicates_dt: class unknown, score  0.45, impact 0.0%, flags high_complexity/low_confidence.
- reshape_to_long: class unknown, score  0.45, impact 0.0%, flags high_complexity/low_confidence.

## Top Bottlenecks by Composite Score

```text
| Rank | Function               | Complexity | Composite score | Stage impact | adj.R2 | Confidence | Volatility cv | Growth max | Flags                                                | Likely slowdown drivers                              |
| ---- | ---------------------- | ---------- | --------------- | ------------ | ------ | ---------- | ------------- | ---------- | ---------------------------------------------------- | ---------------------------------------------------- |
| 1    | read_excel_file_sheets | unknown    | 0.7988          | 99.7%        | N/A    | unknown    | 0.027033      | 1.024      | high_complexity/high_impact/low_confidence/critical~ | super-linear class (unknown) raises asymptotic risk~ |
| 2    | discover_excel_files   | unknown    | 0.4511          | 0.3%         | N/A    | unknown    | 0.077297      | 0.9829     | high_complexity/low_confidence                       | super-linear class (unknown) raises asymptotic risk~ |
| 3    | normalize_key_fields   | unknown    | 0.45            | 0.0%         | N/A    | unknown    | 0.11817       | 2.164      | high_complexity/low_confidence                       | reshape pressure likely amplifies memory movement; ~ |
| 4    | detect_duplicates_dt   | unknown    | 0.45            | 0.0%         | N/A    | unknown    | 0.16434       | 1.476      | high_complexity/low_confidence                       | grouping across repeated keys increases hash/scan c~ |
| 5    | reshape_to_long        | unknown    | 0.45            | 0.0%         | N/A    | unknown    | 0.10372       | 4.443      | high_complexity/low_confidence                       | reshape pressure likely amplifies memory movement; ~ |
```

## Confidence and Uncertainty Summary

```text
| Metric                      | Value   |
| --------------------------- | ------- |
| Mean adjusted R2            | N/A     |
| Median adjusted R2          | N/A     |
| Low-confidence functions    | 7       |
| Low-confidence share        | 100.0%  |
| High-volatility functions   | 1       |
| High-volatility share       | 14.3%   |
| Critical bottlenecks        | 1       |
| Runtime concentration (HHI) | 0.99326 |
```

## Optimization Priority Queue

```text
| Priority tier | Function               | Complexity | Composite score | Stage impact | Reason                                               | Expected impact           | Flags                                                |
| ------------- | ---------------------- | ---------- | --------------- | ------------ | ---------------------------------------------------- | ------------------------- | ---------------------------------------------------- |
| P0            | read_excel_file_sheets | unknown    | 0.7988          | 99.7%        | large runtime share; super-linear growth risk; low ~ | up to 99.7% stage runtime | high_complexity/high_impact/low_confidence/critical~ |
| P2            | discover_excel_files   | unknown    | 0.4511          | 0.3%         | super-linear growth risk; low model confidence       | up to 0.3% stage runtime  | high_complexity/low_confidence                       |
| P2            | normalize_key_fields   | unknown    | 0.45            | 0.0%         | super-linear growth risk; low model confidence; sha~ | up to 0.0% stage runtime  | high_complexity/low_confidence                       |
| P2            | detect_duplicates_dt   | unknown    | 0.45            | 0.0%         | super-linear growth risk; low model confidence       | up to 0.0% stage runtime  | high_complexity/low_confidence                       |
| P2            | reshape_to_long        | unknown    | 0.45            | 0.0%         | super-linear growth risk; low model confidence; sha~ | up to 0.0% stage runtime  | high_complexity/low_confidence                       |
```

## Stage Narrative

- Runtime is dominated by read_excel_file_sheets, contributing 99.7% of stage runtime.
- Asymptotic risk is dominated by read_excel_file_sheets with class unknown.
- Optimize first: read_excel_file_sheets because large runtime share; super-linear growth risk; low model confidence; expected impact up to 99.7% stage runtime.

## Complexity Distribution (ASCII)

```text
| Complexity class | Function count | Function share | Runtime share | Distribution             |
| ---------------- | -------------- | -------------- | ------------- | ------------------------ |
| unknown          | 7              | 100.0%         | 100.0%        | ######################## |
```

## Runtime Share Distribution (ASCII)

```text
| Function                     | Relative impact | Composite score | Distribution             |
| ---------------------------- | --------------- | --------------- | ------------------------ |
| read_excel_file_sheets       | 99.7%           | 0.7988          | ######################## |
| discover_excel_files         | 0.3%            | 0.4511          | ------------------------ |
| normalize_key_fields         | 0.0%            | 0.45            | ------------------------ |
| detect_duplicates_dt         | 0.0%            | 0.45            | ------------------------ |
| reshape_to_long              | 0.0%            | 0.45            | ------------------------ |
| consolidate_audited_dt       | 0.0%            | 0.45            | ------------------------ |
| validate_mandatory_fields_dt | 0.0%            | 0.45            | ------------------------ |
```

## Runtime Projection Grid

```text
| Function                     | n     | Estimated runtime (s) |
| ---------------------------- | ----- | --------------------- |
| consolidate_audited_dt       | 1000  | N/A                   |
| detect_duplicates_dt         | 1000  | N/A                   |
| discover_excel_files         | 1000  | N/A                   |
| normalize_key_fields         | 1000  | N/A                   |
| read_excel_file_sheets       | 1000  | N/A                   |
| reshape_to_long              | 1000  | N/A                   |
| validate_mandatory_fields_dt | 1000  | N/A                   |
| consolidate_audited_dt       | 10000 | N/A                   |
| detect_duplicates_dt         | 10000 | N/A                   |
| discover_excel_files         | 10000 | N/A                   |
| normalize_key_fields         | 10000 | N/A                   |
| read_excel_file_sheets       | 10000 | N/A                   |
| reshape_to_long              | 10000 | N/A                   |
| validate_mandatory_fields_dt | 10000 | N/A                   |
```
