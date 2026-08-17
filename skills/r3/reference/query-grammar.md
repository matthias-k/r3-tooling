# r3 query grammar

r3 queries are MongoDB-style documents compiled to SQLite that run against each job's
`metadata`. Only the subset below is implemented — do not assume any Mongo operator that
isn't listed. A query has two levels: **logical operators** combine subqueries; **field
conditions** test one metadata field.

## Logical operators (query level)

| Operator | Meaning |
|----------|---------|
| `{a: 1, b: 2}` | **implicit AND** — every key must match |
| `$and: [q, …]` | all subqueries match |
| `$or: [q, …]` | any subquery matches |
| `$nor: [q, …]` | no subquery matches |
| `$not: q` | subquery does not match |

- **`$not` exists only at the query level** — `{"$not": {"tags": "x"}}` → `NOT (…)`. There
  is no working field-level `$not` (see the trap below).
- **An unknown `$operator` at query level raises `ValueError`** (`Unsupported operator: …`).

## Field conditions

`{field: value}` is shorthand for `{field: {"$eq": value}}`. The full condition set:

| Condition | Meaning |
|-----------|---------|
| `$eq` (implicit) | equal |
| `$ne` | not equal |
| `$in: [...]` | equal to any listed value |
| `$nin: [...]` | not equal to any listed value |
| `$gt` `$gte` `$lt` `$lte` | numeric comparison |
| `$glob: pat` | SQLite GLOB match |
| `$all: [...]` | array contains all listed values |
| `$elemMatch: {…}` | one array element satisfies all sub-conditions |

`find({})` (empty query) matches **all** jobs.

## Not implemented — and the silent-coercion trap

These Mongo operators are **not implemented**: `$exists`, `$type`, `$regex`, `$size`,
`$mod`, `$expr`, `$text`, and **field-level `$not`**.

- **Unknown FIELD-level operators are SILENTLY coerced to `$eq` — no error.** The unknown
  operator is dropped and its argument becomes the equality value:

  ```
  {"f": {"$regex": "x"}}   ->   metadata->>'$.f' = 'x'      # NOT a regex match
  {"f": {"$not": {"$eq": 1}}}  ->  metadata->>'$.f' = {'$eq': 1}   # garbage comparison
  ```

  This is a silent-wrong trap: the query runs and returns results, just not the ones you
  meant. Only *query-level* unknown operators raise; field-level ones never do. Field-level
  `$not` in particular compiles to nonsense — always negate at the query level instead.
- **A scalar field cannot carry two operators.** `{"f": {"$gt": 1, "$lt": 9}}` raises
  `ValueError` (`Invalid condition`). Express a range with query-level `$and`
  (`{"$and": [{"f": {"$gte": 1}}, {"f": {"$lte": 9}}]}`) or, on an array field, with
  `$elemMatch`.

## Array semantics (the sharp ones)

When a metadata field holds a JSON array, `$eq`/implicit, `$ne`, `$in`, `$nin`, `$glob`, and
the range operators test **each element** (match if *any* element satisfies). So:

- **`$eq`/implicit/`$in`/`$glob` on an array mean "contains".** `{"tags": "x"}` matches any
  job whose `tags` array contains `"x"`.
- **`$ne`/`$nin` on an array do NOT exclude.** They match if *any* element differs, so
  `{"tags": {"$ne": "x"}}` matches every job whose `tags` has at least one non-`x` value —
  i.e. essentially every job, *including* ones tagged `x`. This diverges from MongoDB. To
  actually exclude, negate at the query level: `{"$not": {"tags": "x"}}`.
- **`$all` and `$elemMatch` are JSON-type-strict.** `28` (int) ≠ `"28"` (str) — store
  queryable values with the JSON type you will query with.
- **`$all: [...]`** matches when the array contains **all** listed values; **empty `$all`
  (`{"$all": []}`) matches everything** (this is what a bare `r3 find` uses).
- **`$elemMatch` binds all its sub-conditions to ONE element.** `{"tags": {"$elemMatch":
  {"$gt": 1, "$lt": 9}}}` matches when a *single* element is both `> 1` and `< 9`. (Sibling
  top-level conditions may instead be satisfied by different elements — use `$elemMatch` when
  the same element must satisfy everything. It is also the only way to put two operators on
  one array field.)

## `$glob`

`$glob` is **SQLite GLOB**, not a regex and not SQL `LIKE`:

- **Case-sensitive.** Wildcards are `*` (any run of characters), `?` (one character), and
  `[...]` (character class). No `%`/`_` (those are `LIKE`).

## Values are interpolated, not parameterized

Query values are string-interpolated directly into SQL, with two consequences:

- **Range operators interpolate the value UNQUOTED** (unlike `$eq`/`$ne`, which quote
  strings). On a numeric field this is fine. On a **string** field it is a trap:
  - A numeric-looking value → an unquoted number compared against TEXT. SQLite orders numbers
    before text, so `{"version": {"$gt": "1.0"}}` becomes `… > 1.0` and matches **all or
    none** of the text rows by type ranking, never a semver comparison.
  - A non-numeric token → an unquoted bare identifier, e.g. `{"version": {"$gt": "v1.0"}}`
    becomes `… > v1.0`, which is **invalid SQL and errors** at execution.

  So never range-query a string field. Store versions/thresholds as **numbers**, and use
  `$eq` (which quotes) for exact string matches.
- **Embedded quotes break the query.** A value containing a `'` produces malformed SQL —
  keep queryable values quote-free.

## Dotted nested fields

Dotted keys address nested JSON: `{"task_meta.seed": 42}` compiles to
`metadata->>'$.task_meta.seed'`. Nest as deep as your metadata goes.

## Result ordering

Query results are in **unspecified order** unless `latest=True` (API) / `--latest` (CLI),
which returns the single newest job by `timestamp`. A plain `find` has no `ORDER BY`; do not
read its order as meaningful (see `gotchas.md`). Sort by `timestamp` yourself if you need an
order.
