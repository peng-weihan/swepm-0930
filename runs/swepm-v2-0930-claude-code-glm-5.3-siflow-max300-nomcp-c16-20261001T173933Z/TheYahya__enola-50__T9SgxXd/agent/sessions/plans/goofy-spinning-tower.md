# Enola refactor: usable library API + robust checking, export, and non-interactive CLI

## Context

Enola is currently a thin TUI-only wrapper: `enola.New(ctx)` returns a value struct, the check engine ignores half of `data.json` (regexCheck, errorCode, errorUrl, urlProbe, request_method/payload, headers), never closes its result channel, silently mishandles array `errorMsg`, ignores `response_url` sites entirely (they emit nothing), mutates `http.DefaultClient` from many goroutines, requires the TUI even when stdout is not a terminal, and silently does nothing for unsupported `--output` extensions.

The goal is a well-defined public Go API (`enola.New(...Option)`, `SetSite`, `Check(ctx, username)` returning a closed receive-only channel), a strategy-pattern checking engine (`internal/checker`), a proper export package (`internal/export`), PCRE-capable username validation, and plain-text CLI output when stdout is not a TTY.

Upstream `github.com/TheYahya/enola` has already evolved into exactly this design; I'm porting that architecture onto this tree (keeping MIT license — same project).

## Plan

### 1. Root package `enola` (files: `enola.go`, `website.go`, `result.go`, `options.go`, `errors.go`, `regex.go`)

**`website.go`** — replace the 6-field `Website` struct:
- Public struct: `ErrorType string`, `ErrorMessages []string`, `ErrorURL string`, `ErrorCodes []int`, `URL string` (`json:"url"`), `URLProbe string` (`json:"urlProbe"`), `URLMain string` (`json:"urlMain"`), `RegexCheck string` (`json:"regexCheck"`), `RequestMethod string` (`json:"request_method"`), `RequestPayload any` (`json:"request_payload"`), `Headers map[string]string`, `IsNSFW bool`, `UsernameClaimed string` (`json:"username_claimed"`), `UsernameUnclaimed string` (`json:"username_unclaimed"`).
- Private `websiteJSON` mirror with `errorMsg`/`errorCode` as `json.RawMessage`; custom `UnmarshalJSON` normalizes string|array for messages and int|[]int for codes (helpers `parseErrorMessages`, `parseErrorCodes`).

**`result.go`** — `Status int` with `StatusNotFound`, `StatusFound`, `StatusInvalid`, `StatusErrored` (iota order); `Result{Name, URL string, Found bool, Status Status}` (Status tagged `json:"-"`).

**`errors.go`** — replace string constants with `errors.New` values: `ErrDataFileIsNotAValidJson`, `ErrSiteNotFound` (keep messages).

**`options.go`** — `Option func(*Enola)`, `WithHTTPClient(*http.Client)`, `WithConcurrency(int64)` (guarded n > 0), `WithData(map[string]Website)`; consts `defaultConcurrency = 20`, `defaultTimeout = 20s`; `defaultHTTPClient()`.

**`regex.go`** — `matchUsernameRegex(pattern, username string) (bool, error)`: empty pattern → true; try stdlib `regexp.Compile` first; on compile failure fall back to `github.com/dlclark/regexp2` (PCRE lookahead/lookbehind support — needed by GitHub's pattern etc.).

**`enola.go`** — `Enola{Data map[string]Website; Site string; client *http.Client; sem *semaphore.Weighted}`; `//go:embed data.json` stays; `New(opts ...Option) (*Enola, error)` unmarshals embedded data; `SetSite` (chainable); `ListCount`/`List` kept.
- `Check(ctx, username) (<-chan Result, error)`: `selectSites()` (substring filter, `ErrSiteNotFound` if empty match and site != ""), spawn goroutine that `defer close(ch)`, WaitGroup + semaphore over sites, each result sent via `checkOne`.
- `checkOne`: build `Result` with `{}`→username substitution; regex gate (invalid → `StatusInvalid`, no HTTP request); `checker.Lookup(site.ErrorType)` (unknown → `StatusErrored`); `probe()` (transport error → `StatusErrored`); run `detector.Detect(resp, target)`; found → `StatusFound`.
- `probe`: `buildRequest` (urlProbe over url, `{}` substitution, method default GET, JSON payload with recursive `substituteUsername`, headers applied, Content-Type default for payloads), `client.Do`, read body, capture `resp.Request.URL.String()` as `FinalURL`.
- Uses the per-instance client (no more `http.DefaultClient` mutation).

### 2. `internal/checker` (new: `checker.go`, `registry.go`, `status_code.go`, `message.go`, `response_url.go`)

- `checker.go`: `Response{StatusCode int; Body []byte; FinalURL string}`, `Target{ErrorMessages []string; ErrorURL string; ErrorCodes []int}`, `Detector interface { Detect(resp Response, target Target) (bool, error) }`.
- `registry.go`: `type Factory func() Detector`, `registry` map, `Register(errorType string, f Factory)`, `Lookup(errorType string) (Detector, bool)`.
- `status_code.go`: 200 → found unless status in `ErrorCodes`; non-200 → not found.
- `message.go`: body contains any error message → not found, else found.
- `response_url.go`: with `ErrorURL` → found iff `FinalURL` does NOT begin with `ErrorURL`; without → found iff status 200.

### 3. `internal/export` (new: `writer.go`, `json.go`, `csv.go`, `file.go`)

- `ExportType` string; consts `JSON`, `CSV`, `NotSupported`.
- `Item{Title, URL string, Found bool}` with json tags `title`, `url`, `found`.
- `Writer interface { Write() error }`; factory map keyed by ExportType; `CheckExportType(path)` case-insensitive suffix; `NewWriter(path string, items []Item) (Writer, error)` — returns `fmt.Errorf("unsupported export format: %s", path)` for NotSupported.
- `json.go`: pretty-printed JSON array via `encoder.SetIndent("", "  ")`.
- `csv.go`: header `title,url,found`, `strconv.FormatBool`, flush + error check.
- `file.go`: `openOrCreateFile` — `os.MkdirAll(filepath.Dir(path), 0755)` then `O_RDWR|O_CREATE|O_TRUNC 0644`.

### 4. CLI (`cmd/enola/`)

- `main.go` (rename of `enola.go`): unchanged cobra flags `--site`/`-s`, `--output`/`-o`, `enola {username}` usage.
- `find.go`: `enola.New()` (no ctx), `SetSite(...).Check(ctx, username)`; branch on `isInteractive()`; `exportResults` after scan.
- `plain.go` (new): `isInteractive()` via `golang.org/x/term.IsTerminal(os.Stdout)`; `printResults(<-chan enola.Result) []tui.Item` printing `[+] SiteName: URL` / `[-] SiteName: not found` as results arrive; `exportResults` (exit 1 with clear message on unsupported extension).
- `cmd/enola/internal/tui/` (new package, moved `model.go` + `delegate.go`): exported `Item{Title, URL, Found}`, `Run(results <-chan enola.Result) ([]Item, error)` — model handles channel close via `doneMsg` (fixes the hang on `response_url` sites), collects items for export.

### 5. Cleanup

- Delete `cmd/exporter/` (superseded by `internal/export`).
- Delete old `error.go` (replaced by `errors.go`).
- `go.mod`: add `github.com/dlclark/regexp2 v1.12.0`, `golang.org/x/term v0.43.0` (both reachable via proxy.golang.org — verified 200).
- go:embed requires `data.json` at package root — stays where it is.

### Verification

1. `go build ./...` and `go vet ./...`.
2. `go test ./...` (I will also add tests where cheap: matchUsernameRegex PCRE semantics, Website unmarshal normalization, checker detectors, export writers — matching upstream's test files).
3. CLI end-to-end:
   - `go run ./cmd/enola github` (piped, non-TTY) → plain `[+]`/`[-]` lines, no TUI.
   - `go run ./cmd/enola johndoe --site github` → single site.
   - `go run ./cmd/enola johndoe --output ./out/res.json` then `./out/res.csv` → valid files with parent dir creation; `--output ./res.txt` → clear error, exit 1.
   - JSON output parses as an array of `{title,url,found}`; CSV has header row.
   - Invalid-regex username (e.g. `-bad-name`-style) produces no HTTP request (invalid status).
