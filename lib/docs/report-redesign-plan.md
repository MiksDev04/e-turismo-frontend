# E-Turismo Report System Redesign — Implementation Plan

**Scope:** Replace the current `reports` (+ business-per-row) model with a single
`report_batches` table, decouple "viewing a report" from "having a generated file,"
and make viewing reflect live tourist data at all times.

---

## 1. Why This Is Changing

- **Old model doesn't fit the actual files.** A DAE report is one workbook with a
  sheet per establishment; a VAR report is one workbook covering every
  establishment. Neither is "one row per business," so `business_id` on the old
  `reports` table never made sense once we stopped generating per-business files.
- **Auto-generating xlsx + pdf on every change is wasted work.** Regenerating a
  file every time `guest_records` changes means most generated files are never
  even opened.
- **The professor wants viewing to be realtime.** Whatever numbers a user sees on
  screen must reflect the current state of `guest_records`, not a snapshot from
  whenever the file was last generated.

**The fix:** separate "a report someone wants" (a definition: type + variant +
period) from "a file someone downloaded" (a byproduct, generated on demand). A
report is *always* computed live when viewed. A file only gets created when the
Download button is clicked.

---

## 2. Old vs New, at a Glance

| | Old | New |
|---|---|---|
| Table(s) | `reports` (+ dropped `report_downloads`) | `report_batches` (single table) |
| Keyed by | `business_id` per row | `report_type` + `report_variant` + `period_year` + `period_months` |
| On create | Immediately generates `.xlsx` **and** `.pdf` | Nothing is generated |
| On view | Opens the previously generated file | Runs a live query against `guest_records`, renders fresh numbers in the UI |
| On download | N/A (file already existed) | Runs the *same* live query, builds `.xlsx` (and `.pdf` if requested) right then, uploads to Cloudinary, overwrites the URL on the batch row |
| Staleness | File can lag behind real data | Impossible to be stale — view never reads a cached file |

---

## 3. Database Schema

Drop the old tables and replace with one:

```sql
DROP TABLE IF EXISTS `report_downloads`;
DROP TABLE IF EXISTS `report_batches`;
DROP TABLE IF EXISTS `reports`;

CREATE TABLE `report_batches` (
  `id` char(36) NOT NULL DEFAULT (uuid()),
  `report_type` enum('dae','var') NOT NULL,
  `report_variant` enum('daily','summary','series','total') NOT NULL
    COMMENT 'DAE: daily/summary/series. VAR always uses total (single sheet).',
  `period_year` smallint NOT NULL,
  `period_months` JSON NOT NULL
    COMMENT 'Sorted array of ints 1-12, e.g. [1,2,3]. App must sort before insert.',
  `period_months_hash` char(64)
    GENERATED ALWAYS AS (SHA2(CAST(`period_months` AS CHAR), 256)) STORED,
  `requested_by` char(36) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `last_viewed_at` datetime DEFAULT NULL
    COMMENT 'Bumped on every view; viewing is a live query, no file involved',
  `last_xlsx_url` varchar(1000) DEFAULT NULL,
  `last_pdf_url` varchar(1000) DEFAULT NULL,
  `last_generated_at` datetime DEFAULT NULL
    COMMENT 'Bumped whenever Download regenerates the file',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_batch_combo` (`report_type`, `report_variant`, `period_year`, `period_months_hash`),
  KEY `idx_batches_type_period` (`report_type`, `period_year`),
  CONSTRAINT `report_batches_requested_by_fkey` FOREIGN KEY (`requested_by`) REFERENCES `users` (`id`),
  CONSTRAINT `chk_batch_period_year` CHECK (`period_year` >= 2000),
  CONSTRAINT `chk_batch_period_months_array` CHECK (JSON_TYPE(`period_months`) = 'ARRAY'),
  CONSTRAINT `chk_batch_variant_matches_type` CHECK (
    (`report_type` = 'dae' AND `report_variant` IN ('daily','summary','series')) OR
    (`report_type` = 'var' AND `report_variant` = 'total')
  ),
  CONSTRAINT `chk_batch_single_month_variants` CHECK (
    `report_variant` NOT IN ('daily','summary') OR JSON_LENGTH(`period_months`) = 1
  )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
```

**Key points for whoever implements this:**
- `report_variant = 'total'` is used for **every** VAR row (never `NULL` — MySQL
  treats `NULL`s in a unique index as distinct, which would break dedup).
- `period_months` must be sorted before insert (`[1,2,3]`, never `[3,2,1]`), or
  identical month sets will hash differently and dodge the unique key.
- `daily` and `summary` are locked to exactly one month by
  `chk_batch_single_month_variants`. `series` and `var/total` allow any subset,
  including all 12 months for a full-year VAR or DAE series report.

---

## 4. Backend Logic

### 4.1 Viewing a report (must be realtime)

**This is the core behavior change.** Viewing a report in the system must **never**
read from a previously generated file or a cached number. Every time a report
screen is opened — or refreshed — the backend must:

1. Find-or-create the matching `report_batches` row (dedupe on
   `report_type` + `report_variant` + `period_year` + `period_months_hash`).
2. Bump `last_viewed_at`.
3. Run a **live aggregation query** directly against `guest_records`
   (joined with `guest_record_rooms`, using `lead_birthdate` +
   `TIMESTAMPDIFF` for age) for the requested establishment(s), variant,
   and period.
4. Return the computed numbers as JSON to the frontend, which renders them
   as a table/view in the app — **not** as an embedded Excel or PDF file.

If a guest record is added, edited, or synced offline one minute before someone
opens the report, that change must already be reflected. There is no
regeneration job to "catch up" — the query itself is always current.

### 4.2 Keeping an *open* report live (optional but recommended)

Because E-Turismo already has the pattern for this (`report:stale` Socket.IO
events triggering admin panel re-fetches), reuse it here:

- Emit `report:stale` whenever a `guest_records` write happens, from **both**
  the direct controller and the offline sync push endpoint.
- If a report screen matching the affected period is currently open, the
  frontend silently re-fetches the live query in the background (no full page
  reload) so the numbers update while the user is looking at it, not just on
  next open.

This is the difference between "correct every time you open it" (guaranteed by
4.1 alone) and "updates while you're staring at it" (needs this socket layer).
Confirm with your professor which one they actually mean by "realtime" — 4.1 is
required either way; 4.2 is the nice-to-have on top.

### 4.3 Downloading a report

Downloading is the **only** place a file gets created:

1. Run the *same* aggregation function used for viewing (single source of
   truth — do not duplicate the calculation logic between "view" and
   "download" code paths).
2. Build the workbook with ExcelJS:
   - DAE (`daily`/`summary`/`series`): one sheet per establishment.
   - VAR (`total`): one sheet, columns per month if `period_months` has more
     than one entry, otherwise a single totals block.
3. Convert to PDF if the user requested it.
4. Upload both to Cloudinary as `raw` resource type.
5. Overwrite `last_xlsx_url`, `last_pdf_url`, and `last_generated_at` on the
   same `report_batches` row found/created in step 1 of the view flow (or
   created fresh if this is a download without a prior view).
6. Return the URL(s) to the frontend.

### 4.4 Rewriting the DAE-1B generator

The current DAE-1B Excel generator still queries the old `guest_breakdowns` /
`guest_breakdowns_synced` tables, which no longer exist — this needs a full
rewrite against the current schema (`guest_records`, `guest_record_rooms`,
`lead_birthdate`). Build this as the shared aggregation function referenced in
4.1 and 4.3, so the JSON the user sees on screen and the workbook they download
are always computed by the exact same code.

---

## 5. Frontend Changes — Viewing the Report

The view screen should **look like a spreadsheet** while being fed entirely by
live data — never by the generated `.xlsx` file. These are not two competing
requirements; a spreadsheet-styled grid rendered from the live JSON response
achieves both at once, with none of the staleness or regeneration cost of
displaying an actual file.

### 5.1 Data source (unchanged from Section 4.1)

- Report view screen fetches JSON from the `GET /reports/view` endpoint and
  renders it — it does **not** embed, preview, or read the generated
  `.xlsx`/`.pdf` file in any way.
- A separate **Download** button hits `POST /reports/download`, which remains
  the only trigger that ever produces an actual file.

### 5.2 Grid package choice

Plain lists/`DataTable` won't read as "Excel." Use a proper grid widget instead:

| Package | Pros | Cons |
|---|---|---|
| `syncfusion_flutter_datagrid` | Closest to a native Excel feel: frozen header row/column, per-cell styling, column resizing, built for large tabular data | Commercial package — requires a Syncfusion commercial license or the free **Community License** (qualifying criteria: less than $1M USD annual gross revenue, 5 or fewer developers, 10 or fewer total employees — a solo capstone project should qualify, but apply early since validation isn't instant) |
| `pluto_grid` | Free and open source, no licensing step | Less polished out of the box; frozen columns/spreadsheet styling need more manual work |

Pick one before starting implementation — don't mix both in the same app.

### 5.3 Structure

- `TabBar`/`TabBarView` across the top for **DAE** variants — one tab per
  establishment, mirroring the one-sheet-per-establishment layout of the
  generated workbook.
- **VAR** reports skip the tabs entirely and render a single grid (VAR is
  always one sheet).
- Grid columns depend on variant, using the same JSON shape as the download:
  - `daily` — one column per day in the selected month.
  - `summary` — a single totals block for the selected month.
  - `series` / VAR with multiple months — one column per selected month plus
    a totals column.

### 5.4 Styling to read as "Excel"

- Thin borders between cells (gridlines).
- Shaded, frozen header row (and frozen first column if labels are long).
- Alternating row banding.
- None of this touches the data layer — it's purely how the same JSON gets
  painted onto the grid widget.

### 5.5 Realtime indicator

- Optional: a small "last updated" timestamp, and (if Section 4.2 is
  implemented) a quiet auto-refresh of the grid when a `report:stale` event
  arrives for the currently open report — no full page reload, just the grid
  data swapping under the user.

---

## 6. Migration Checklist

- [ ] Confirm it's fine to drop existing `reports` data outright (capstone
      context — likely yes, but confirm before running `DROP TABLE`).
- [ ] Run the schema migration SQL in Section 3.
- [ ] Build the shared aggregation function (used by both view and download).
- [ ] Build `GET /reports/view` — find-or-create batch, run live query, return
      JSON, bump `last_viewed_at`.
- [ ] Build `POST /reports/download` — run live query, generate file(s),
      upload to Cloudinary, update `last_xlsx_url`/`last_pdf_url`/
      `last_generated_at`.
- [ ] Rewire the frontend report screen to consume the JSON view endpoint
      instead of any static file.
- [ ] Pick the grid package (`syncfusion_flutter_datagrid` vs `pluto_grid`,
      see Section 5.2) and, if Syncfusion, apply for the Community License
      before building the UI around it.
- [ ] Build the tabbed spreadsheet-style grid view (Section 5.3–5.4): tabs
      per establishment for DAE, single grid for VAR, styled with gridlines,
      frozen header row, and row banding.
- [ ] Wire the Download button to the new download endpoint.
- [ ] Wire `report:stale` emission (guest record controller **and** offline
      sync push endpoint) and a frontend listener for auto-refresh, if doing 4.2.
- [ ] Remove the old auto-regenerate-on-insert job — it's no longer needed.
- [ ] Test:
  - [ ] DAE `daily` / `summary` reject more than one month (constraint check).
  - [ ] DAE `series` and VAR `total` accept multiple months, including all 12.
  - [ ] Opening the same report twice (same type/variant/year/months) reuses
        the same `report_batches` row instead of creating a duplicate.
  - [ ] Downloading regenerates the file and overwrites the URL fields.
  - [ ] Editing a guest record and re-opening an already-viewed report shows
        the updated numbers with no manual regeneration step.

---

## 7. Open Decisions to Confirm Before/While Coding

- Does "realtime" mean **fresh on every open** (Section 4.1, required) or also
  **live-updating while the screen stays open** (Section 4.2, needs sockets)?
- Is preserving old report data/history a requirement, or is a clean drop of
  the old tables acceptable?
