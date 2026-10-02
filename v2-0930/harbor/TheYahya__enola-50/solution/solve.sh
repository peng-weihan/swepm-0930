#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/README.md b/README.md
--- a/README.md
+++ b/README.md
@@ -10,6 +10,8 @@ go install github.com/theyahya/enola/cmd/enola@latest
 ## Usage
 ```bash
 enola {username}
+enola {username} --site twitter
+enola {username} --output ./results.json
 ```
 
 <img alt="Enola demo" src="https://github.com/theyahya/enola/blob/main/examples/demo.gif" width="600" />
@@ -25,9 +27,32 @@ Run
 docker run --rm -it enola {username}
 ```
 
+## Library usage
+
+```go
+ctx := context.Background()
+e, err := enola.New()
+if err != nil {
+    log.Fatal(err)
+}
+
+results, err := e.SetSite("twitter").Check(ctx, "username")
+if err != nil {
+    log.Fatal(err)
+}
+
+for r := range results {
+    fmt.Println(r.Name, r.URL, r.Found)
+}
+```
+
+Options: `enola.WithHTTPClient`, `enola.WithConcurrency`, `enola.WithData`.
+
 ## Contributing
 You can fork the repository, improve or fix some part of it and then send a pull requests. Or simply open and issue if there's a bug, or you have a feature in mind.
 
+To add a new detection strategy, create a file in `internal/checker/` that implements `Detector` and registers itself in `init()` via `checker.Register("your_type", ...)`.
+
 ## License
 
 This software is released under the [MIT](https://github.com/TheYahya/enola/blob/main/LICENSE) License.
diff --git a/cmd/enola/find.go b/cmd/enola/find.go
--- a/cmd/enola/find.go
+++ b/cmd/enola/find.go
@@ -5,77 +5,47 @@ import (
 	"fmt"
 	"os"
 
-	"charm.land/bubbles/v2/list"
-	tea "charm.land/bubbletea/v2"
 	"github.com/theyahya/enola"
-	"github.com/theyahya/enola/cmd/exporter"
+	"github.com/theyahya/enola/cmd/enola/internal/tui"
+	"github.com/theyahya/enola/internal/export"
 )
 
-type responseMsg enola.Result
-
 func findAndShowResult(options cmdOptions) {
 	ctx := context.Background()
-	sh, err := enola.New(ctx)
+	e, err := enola.New()
 	if err != nil {
-		panic(err)
+		fmt.Println("Error initializing enola:", err)
+		os.Exit(1)
 	}
 
-	resChan, err := sh.SetSite(options.site).Check(options.username)
+	resChan, err := e.SetSite(options.site).Check(ctx, options.username)
 	if err != nil {
-		fmt.Println("Error running program: ", err)
+		fmt.Println("Error running program:", err)
 		os.Exit(1)
 	}
 
-	m := model{
-		list: list.New(
-			[]list.Item{},
-			NewDelegate(false),
-			0,
-			0,
-		),
-		res: resChan,
-	}
-
-	m.list.Title = "Socials"
-	p := tea.NewProgram(&m)
-
-	if _, err := p.Run(); err != nil {
-		fmt.Println("Error running program: ", err)
-		os.Exit(1)
+	var items []tui.Item
+	if isInteractive() {
+		items, err = tui.Run(resChan)
+		if err != nil {
+			fmt.Println("Error running program:", err)
+			os.Exit(1)
+		}
+	} else {
+		items = printResults(resChan)
 	}
 
-	defer func() {
-		if options.outputPath != "" {
-			exportType := exporter.CheckExportType(options.outputPath)
-
-			var writer exporter.Writer = nil
-			if exporter.JSON == exportType {
-				writer = exporter.JsonWriter{
-					OutputPath: options.outputPath,
-					Items:      prepareItemsForExport(m.list.Items()),
-				}
-			} else if exporter.CSV == exportType {
-				writer = exporter.CsvWriter{
-					OutputPath: options.outputPath,
-					Items:      prepareItemsForExport(m.list.Items()),
-				}
-			}
-
-			if writer != nil {
-				writer.Write()
-			}
-		}
-	}()
+	exportResults(options.outputPath, items)
 }
 
-func prepareItemsForExport(items []list.Item) []exporter.Item {
-	var ret []exporter.Item
-
-	for _, value := range items {
-		if itemValue, ok := value.(item); ok {
-			ret = append(ret, exporter.Item{Title: itemValue.title, URL: itemValue.desc, Found: itemValue.found})
+func toExportItems(items []tui.Item) []export.Item {
+	out := make([]export.Item, len(items))
+	for i, item := range items {
+		out[i] = export.Item{
+			Title: item.Title,
+			URL:   item.URL,
+			Found: item.Found,
 		}
 	}
-
-	return ret
+	return out
 }
diff --git a/cmd/enola/delegate.go b/cmd/enola/internal/tui/delegate.go
rename from cmd/enola/delegate.go
rename to cmd/enola/internal/tui/delegate.go
--- a/cmd/enola/delegate.go
+++ b/cmd/enola/internal/tui/delegate.go
@@ -1,4 +1,4 @@
-package main
+package tui
 
 import (
 	"charm.land/bubbles/v2/list"
@@ -22,7 +22,6 @@ func NewDelegate(hasDarkBg bool) list.DefaultDelegate {
 	delegate := list.NewDefaultDelegate()
 	delegate.ShowDescription = false
 	delegate.Styles = NewItemStyles(hasDarkBg)
-
 	return delegate
 }
 
diff --git a/cmd/enola/model.go b/cmd/enola/internal/tui/model.go
rename from cmd/enola/model.go
rename to cmd/enola/internal/tui/model.go
--- a/cmd/enola/model.go
+++ b/cmd/enola/internal/tui/model.go
@@ -1,7 +1,8 @@
-package main
+package tui
 
 import (
 	"fmt"
+	"os"
 
 	"charm.land/bubbles/v2/list"
 	tea "charm.land/bubbletea/v2"
@@ -26,26 +27,33 @@ const (
 
 var docStyle = lipgloss.NewStyle().Margin(1, 2)
 
-type item struct {
+// Item is a TUI list row returned after the scan completes.
+type Item struct {
+	Title string
+	URL   string
+	Found bool
+}
+
+type listItem struct {
 	title     string
 	desc      string
 	found     bool
 	hasDarkBg bool
 }
 
-func (i item) Title() string {
+func (i listItem) Title() string {
 	status, title, desc := i.renderItem(NewItemStyles(i.hasDarkBg).NormalTitle)
 	return fmt.Sprintf("%s %s: %s", status, title, desc)
 }
 
-func (i item) renderItem(style lipgloss.Style) (string, string, string) {
+func (i listItem) renderItem(style lipgloss.Style) (string, string, string) {
 	if i.found {
 		return i.renderFoundedItem(style)
 	}
 	return i.renderNotFoundedItem(style)
 }
 
-func (i item) renderNotFoundedItem(style lipgloss.Style) (string, string, string) {
+func (i listItem) renderNotFoundedItem(style lipgloss.Style) (string, string, string) {
 	ld := lipgloss.LightDark(i.hasDarkBg)
 
 	closeStyle := style.Foreground(ld(lipgloss.Color(CloseStyleLightColor), lipgloss.Color(CloseStyleDarkColor)))
@@ -55,7 +63,7 @@ func (i item) renderNotFoundedItem(style lipgloss.Style) (string, string, string
 	return closeStyle.Render("✗"), titleStyle.Render(i.title), notFoundStyle.Render("Not found!")
 }
 
-func (i item) renderFoundedItem(style lipgloss.Style) (string, string, string) {
+func (i listItem) renderFoundedItem(style lipgloss.Style) (string, string, string) {
 	ld := lipgloss.LightDark(i.hasDarkBg)
 
 	checkStyle := style.Foreground(ld(lipgloss.Color(CheckStyleLightColor), lipgloss.Color(CheckStyleDarkColor)))
@@ -65,63 +73,56 @@ func (i item) renderFoundedItem(style lipgloss.Style) (string, string, string) {
 	return checkStyle.Render("✓"), titleStyle.Render(i.title), descStyle.Render(i.desc)
 }
 
-func (i item) Description() string { return i.desc }
+func (i listItem) Description() string { return i.desc }
+func (i listItem) FilterValue() string { return i.title }
 
-func (i item) FilterValue() string { return i.title }
+type responseMsg enola.Result
+type doneMsg struct{}
 
 type model struct {
 	list      list.Model
 	res       <-chan enola.Result
 	resCount  int
 	hasDarkBg bool
+	done      bool
+	items     []Item
 }
 
 func (m *model) Init() tea.Cmd {
-	return tea.Batch(
-		waitForActivity(m.res),
-		tea.RequestBackgroundColor,
-	)
+	return waitForActivity(m.res)
 }
 
 func (m *model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
 	switch msg := msg.(type) {
 	case tea.KeyPressMsg:
-		if msg.String() == "ctrl+c" {
+		switch msg.String() {
+		case "ctrl+c", "q", "esc":
 			return m, tea.Quit
 		}
-	case tea.BackgroundColorMsg:
-		m.hasDarkBg = msg.IsDark()
-		m.list.SetDelegate(NewDelegate(m.hasDarkBg))
 	case tea.WindowSizeMsg:
 		h, v := docStyle.GetFrameSize()
 		m.list.SetSize(msg.Width-h, msg.Height-v)
 	case responseMsg:
 		m.resCount++
-		it := item{title: msg.Name, desc: msg.URL, found: msg.Found, hasDarkBg: m.hasDarkBg}
+		it := listItem{title: msg.Name, desc: msg.URL, found: msg.Found, hasDarkBg: m.hasDarkBg}
+		m.items = append(m.items, Item{Title: msg.Name, URL: msg.URL, Found: msg.Found})
 		if msg.Found {
 			m.list.InsertItem(0, it)
 		} else {
 			m.list.InsertItem(m.resCount, it)
 		}
 		return m, waitForActivity(m.res)
+	case doneMsg:
+		m.done = true
+		m.list.Title = "Socials (complete — press q to exit)"
+		return m, nil
 	}
 
 	var cmd tea.Cmd
 	m.list, cmd = m.list.Update(msg)
 	return m, cmd
 }
 
-func (m *model) updateList(msg responseMsg) (tea.Model, tea.Cmd) {
-	m.resCount++
-	m.list.InsertItem(m.resCount, item{
-		title:     msg.Name,
-		desc:      msg.URL,
-		found:     msg.Found,
-		hasDarkBg: m.hasDarkBg,
-	})
-	return m, waitForActivity(m.res)
-}
-
 func (m *model) View() tea.View {
 	v := tea.NewView(docStyle.Render(m.list.View()))
 	v.AltScreen = true
@@ -130,6 +131,32 @@ func (m *model) View() tea.View {
 
 func waitForActivity(sub <-chan enola.Result) tea.Cmd {
 	return func() tea.Msg {
-		return responseMsg(<-sub)
+		res, ok := <-sub
+		if !ok {
+			return doneMsg{}
+		}
+		return responseMsg(res)
+	}
+}
+
+// Run displays results in the TUI and returns collected items when finished.
+func Run(results <-chan enola.Result) ([]Item, error) {
+	hasDarkBg := lipgloss.HasDarkBackground(os.Stdin, os.Stdout)
+	m := model{
+		list: list.New(
+			[]list.Item{},
+			NewDelegate(hasDarkBg),
+			0,
+			0,
+		),
+		res:       results,
+		hasDarkBg: hasDarkBg,
+	}
+	m.list.Title = "Socials"
+
+	p := tea.NewProgram(&m)
+	if _, err := p.Run(); err != nil {
+		return nil, err
 	}
+	return m.items, nil
 }
diff --git a/cmd/enola/enola.go b/cmd/enola/main.go
rename from cmd/enola/enola.go
rename to cmd/enola/main.go
--- a/cmd/enola/enola.go
+++ b/cmd/enola/main.go
@@ -29,30 +29,21 @@ func validateArgs(_ *cobra.Command, args []string) error {
 }
 
 func runCommand(cmd *cobra.Command, args []string) {
-	username := args[0]
-	siteFlag := cmd.Flag("site")
-	outputPath := cmd.Flag("output")
-
 	options := cmdOptions{
-		username:   username,
-		site:       siteFlag.Value.String(),
-		outputPath: outputPath.Value.String(),
+		username:   args[0],
+		site:       cmd.Flag("site").Value.String(),
+		outputPath: cmd.Flag("output").Value.String(),
 	}
-
 	findAndShowResult(options)
 }
 
 func main() {
-	if err := Execute(); err != nil {
+	if err := rootCmd.Execute(); err != nil {
 		fmt.Println(err)
 		os.Exit(1)
 	}
 }
 
-func Execute() error {
-	return rootCmd.Execute()
-}
-
 func init() {
 	rootCmd.Flags().StringP(
 		"site",
diff --git a/cmd/enola/plain.go b/cmd/enola/plain.go
new file mode 100644
--- /dev/null
+++ b/cmd/enola/plain.go
@@ -0,0 +1,43 @@
+package main
+
+import (
+	"fmt"
+	"os"
+
+	"github.com/theyahya/enola"
+	"github.com/theyahya/enola/cmd/enola/internal/tui"
+	"github.com/theyahya/enola/internal/export"
+	"golang.org/x/term"
+)
+
+func isInteractive() bool {
+	return term.IsTerminal(int(os.Stdout.Fd()))
+}
+
+func printResults(results <-chan enola.Result) []tui.Item {
+	var items []tui.Item
+	for r := range results {
+		items = append(items, tui.Item{Title: r.Name, URL: r.URL, Found: r.Found})
+		if r.Found {
+			fmt.Printf("[+] %s: %s\n", r.Name, r.URL)
+		} else {
+			fmt.Printf("[-] %s: not found\n", r.Name)
+		}
+	}
+	return items
+}
+
+func exportResults(outputPath string, items []tui.Item) {
+	if outputPath == "" {
+		return
+	}
+	writer, err := export.NewWriter(outputPath, toExportItems(items))
+	if err != nil {
+		fmt.Println("Error preparing export:", err)
+		os.Exit(1)
+	}
+	if err := writer.Write(); err != nil {
+		fmt.Println("Error writing export:", err)
+		os.Exit(1)
+	}
+}
diff --git a/cmd/exporter/csvWriter.go b/cmd/exporter/csvWriter.go
deleted file mode 100644
--- a/cmd/exporter/csvWriter.go
+++ /dev/null
@@ -1,42 +0,0 @@
-package exporter
-
-import (
-	"encoding/csv"
-	"fmt"
-	"strconv"
-)
-
-type CsvWriter struct {
-	OutputPath string
-	Items      []Item
-}
-
-func (writer CsvWriter) Write() {
-	file, err := OpenOrCreateFile(writer.OutputPath)
-	if err != nil {
-		return
-	}
-	defer func() {
-		if err := file.Close(); err != nil {
-			return
-		}
-	}()
-
-	csvWriter := csv.NewWriter(file)
-	defer csvWriter.Flush()
-
-	err = csvWriter.Write([]string{"title", "url", "found"})
-	if err != nil {
-		fmt.Println("Error while saving content to csv file")
-		return
-	}
-
-	for _, item := range writer.Items {
-		row := []string{item.Title, item.URL, strconv.FormatBool(item.Found)}
-		err = csvWriter.Write(row)
-		if err != nil {
-			fmt.Println("Error while saving content to csv file")
-			return
-		}
-	}
-}
diff --git a/cmd/exporter/jsonWriter.go b/cmd/exporter/jsonWriter.go
deleted file mode 100644
--- a/cmd/exporter/jsonWriter.go
+++ /dev/null
@@ -1,30 +0,0 @@
-package exporter
-
-import (
-	"encoding/json"
-	"fmt"
-)
-
-type JsonWriter struct {
-	OutputPath string
-	Items      []Item
-}
-
-func (writer JsonWriter) Write() {
-	file, err := OpenOrCreateFile(writer.OutputPath)
-	if err != nil {
-		return
-	}
-	defer func() {
-		if err := file.Close(); err != nil {
-			return
-		}
-	}()
-
-	encoder := json.NewEncoder(file)
-	encoder.SetIndent("", "  ")
-
-	if err := encoder.Encode(writer.Items); err != nil {
-		fmt.Println("Error while saving items to JSON file", err)
-	}
-}
diff --git a/cmd/exporter/utils.go b/cmd/exporter/utils.go
deleted file mode 100644
--- a/cmd/exporter/utils.go
+++ /dev/null
@@ -1,38 +0,0 @@
-package exporter
-
-import (
-	"fmt"
-	"os"
-	"path/filepath"
-	"strings"
-)
-
-func OpenOrCreateFile(filename string) (*os.File, error) {
-	dir := filepath.Dir(filename)
-	// 0755 permissions: the owner can read, write, and execute, everyone else can only read and execute.
-	err := os.MkdirAll(dir, 0755)
-
-	if err != nil {
-		fmt.Println("Error creating directory:", err)
-		return nil, err
-	}
-
-	// Open the file with read and write permissions
-	file, err := os.OpenFile(filename, os.O_RDWR|os.O_CREATE, 0644)
-	if err != nil {
-		fmt.Println(err)
-		return nil, err
-	}
-	return file, nil
-}
-
-func CheckExportType(filename string) ExportType {
-	lowerFileName := strings.ToLower(filename)
-	if strings.HasSuffix(strings.ToLower(lowerFileName), string(JSON)) {
-		return JSON
-	} else if strings.HasSuffix(strings.ToLower(lowerFileName), string(CSV)) {
-		return CSV
-	}
-
-	return NOTSUPPORTED
-}
diff --git a/cmd/exporter/writer.go b/cmd/exporter/writer.go
deleted file mode 100644
--- a/cmd/exporter/writer.go
+++ /dev/null
@@ -1,19 +0,0 @@
-package exporter
-
-type ExportType string
-
-const (
-	JSON         ExportType = "json"
-	CSV          ExportType = "csv"
-	NOTSUPPORTED ExportType = "notsupported"
-)
-
-type Item struct {
-	Title string `json:"title"`
-	URL   string `json:"url"`
-	Found bool   `json:"found"`
-}
-
-type Writer interface {
-	Write()
-}
diff --git a/enola.go b/enola.go
--- a/enola.go
+++ b/enola.go
@@ -1,160 +1,233 @@
 package enola
 
 import (
+	"bytes"
 	"context"
 	_ "embed"
 	"encoding/json"
 	"fmt"
 	"io"
 	"net/http"
 	"strings"
-	"time"
+	"sync"
 
+	"github.com/theyahya/enola/internal/checker"
 	"golang.org/x/sync/semaphore"
 )
 
-const RequestTimeout = time.Second * 20
-
-type Website struct {
-	ErrorType         string `json:"errorType"`
-	ErrorMessage      any    `json:"errorMsg"`
-	URL               string `json:"url"`
-	UrlMain           string `json:"urlMain"`
-	UsernameClaimed   string `json:"username_claimed"`
-	UsernameUnclaimed string `json:"username_unclaimed"`
-}
-
+// Enola searches for a username across configured websites.
 type Enola struct {
-	Data map[string]Website
-	Site string
-	Ctx  context.Context
-}
-
-type Result struct {
-	Name  string `json:"name"`
-	URL   string `json:"url"`
-	Found bool   `json:"found"`
+	Data   map[string]Website
+	Site   string
+	client *http.Client
+	sem    *semaphore.Weighted
 }
 
 //go:embed data.json
-var d []byte
+var embeddedData []byte
 
-func New(ctx context.Context) (Enola, error) {
+// New loads the embedded site database and applies options.
+func New(opts ...Option) (*Enola, error) {
 	var data map[string]Website
-	err := json.Unmarshal(d, &data)
-	if err != nil {
-		return Enola{}, fmt.Errorf("error: %v", ErrDataFileIsNotAValidJson)
+	if err := json.Unmarshal(embeddedData, &data); err != nil {
+		return nil, fmt.Errorf("%w", ErrDataFileIsNotAValidJson)
 	}
 
-	return Enola{
-		Data: data,
-		Ctx:  ctx,
-	}, nil
+	e := &Enola{
+		Data:   data,
+		client: defaultHTTPClient(),
+		sem:    semaphore.NewWeighted(defaultConcurrency),
+	}
+	for _, opt := range opts {
+		opt(e)
+	}
+	return e, nil
 }
 
-func (s *Enola) SetSite(site string) *Enola {
-	s.Site = site
-	return s
+// SetSite filters checks to sites whose name contains the given string.
+func (e *Enola) SetSite(site string) *Enola {
+	e.Site = site
+	return e
 }
 
-func (s *Enola) ListCount() int           { return len(s.Data) }
-func (s *Enola) List() map[string]Website { return s.Data }
+// ListCount returns the number of configured sites.
+func (e *Enola) ListCount() int { return len(e.Data) }
 
-func (s *Enola) Check(username string) (<-chan Result, error) {
-	ch := make(chan Result)
-	data := map[string]Website{}
+// List returns the configured site database.
+func (e *Enola) List() map[string]Website { return e.Data }
+
+// Check probes all selected sites for the given username.
+// The returned channel is closed when all probes finish.
+func (e *Enola) Check(ctx context.Context, username string) (<-chan Result, error) {
+	sites, err := e.selectSites()
+	if err != nil {
+		return nil, err
+	}
 
-	if s.Site != "" {
-		for k, v := range s.Data {
-			if strings.Contains(strings.ToLower(k), strings.Trim(strings.ToLower(s.Site), " ")) {
-				data[k] = v
+	ch := make(chan Result)
+	go func() {
+		defer close(ch)
+		var wg sync.WaitGroup
+		for name, site := range sites {
+			if err := e.sem.Acquire(ctx, 1); err != nil {
+				return
 			}
+			wg.Add(1)
+			go func(name string, site Website) {
+				defer wg.Done()
+				defer e.sem.Release(1)
+				ch <- e.checkOne(ctx, name, site, username)
+			}(name, site)
+		}
+		wg.Wait()
+	}()
+	return ch, nil
+}
+
+func (e *Enola) selectSites() (map[string]Website, error) {
+	if e.Site == "" {
+		return e.Data, nil
+	}
+
+	filter := strings.ToLower(strings.TrimSpace(e.Site))
+	selected := make(map[string]Website)
+	for name, site := range e.Data {
+		if strings.Contains(strings.ToLower(name), filter) {
+			selected[name] = site
 		}
+	}
+	if len(selected) == 0 {
+		return nil, fmt.Errorf("%w", ErrSiteNotFound)
+	}
+	return selected, nil
+}
+
+func (e *Enola) checkOne(ctx context.Context, name string, site Website, username string) Result {
+	url := strings.ReplaceAll(site.URL, "{}", username)
+	res := Result{Name: name, URL: url, Found: false, Status: StatusNotFound}
 
-		// if site is not found in the list
-		if len(data) == 0 {
-			return nil, fmt.Errorf("error: %v", ErrSiteNotFound)
+	if site.RegexCheck != "" {
+		ok, err := matchUsernameRegex(site.RegexCheck, username)
+		if err != nil {
+			res.Status = StatusErrored
+			return res
+		}
+		if !ok {
+			res.Status = StatusInvalid
+			return res
 		}
 	}
 
-	if len(data) == 0 {
-		data = s.Data
+	detector, ok := checker.Lookup(site.ErrorType)
+	if !ok {
+		res.Status = StatusErrored
+		return res
 	}
 
-	ctx := context.Background()
-	sem := semaphore.NewWeighted(20)
+	resp, err := e.probe(ctx, site, username)
+	if err != nil {
+		res.Status = StatusErrored
+		return res
+	}
 
-	go func() {
-		for key, value := range data {
-			if err := sem.Acquire(ctx, 1); err != nil {
-				fmt.Println(err)
-			}
-			go func(key string, value Website) {
-				defer sem.Release(1)
-				url := strings.ReplaceAll(value.URL, "{}", username)
-
-				res := Result{
-					Name:  key,
-					URL:   url,
-					Found: false,
-				}
-
-				client := http.DefaultClient
-				client.Timeout = RequestTimeout
-				if value.ErrorType == "status_code" {
-					resp, err := client.Get(url)
-					if err != nil {
-						ch <- res
-						return
-					}
-					if err = resp.Body.Close(); err != nil {
-						return
-					}
-
-					if resp.StatusCode == http.StatusOK {
-						res.Found = true
-						ch <- res
-						return
-					}
-					ch <- res
-					return
-
-				}
-
-				if value.ErrorType == "message" {
-					resp, err := client.Get(url)
-					if err != nil {
-						ch <- res
-						return
-					}
-					defer func() {
-						if err := resp.Body.Close(); err != nil {
-							return
-						}
-					}()
-
-					bodyBytes, err := io.ReadAll(resp.Body)
-					if err != nil {
-						ch <- res
-						return
-					}
-
-					valueString, ok := value.ErrorMessage.(string)
-					if !ok {
-						ch <- res
-						return
-					}
-
-					if !strings.Contains(string(bodyBytes), valueString) {
-						res.Found = true
-						ch <- res
-						return
-					}
-					ch <- res
-				}
-			}(key, value)
+	target := checker.Target{
+		ErrorMessages: site.ErrorMessages,
+		ErrorURL:      site.ErrorURL,
+		ErrorCodes:    site.ErrorCodes,
+	}
+	found, err := detector.Detect(resp, target)
+	if err != nil {
+		res.Status = StatusErrored
+		return res
+	}
+	if found {
+		res.Found = true
+		res.Status = StatusFound
+	}
+	return res
+}
+
+func (e *Enola) probe(ctx context.Context, site Website, username string) (checker.Response, error) {
+	req, err := e.buildRequest(ctx, site, username)
+	if err != nil {
+		return checker.Response{}, err
+	}
+
+	httpResp, err := e.client.Do(req)
+	if err != nil {
+		return checker.Response{}, err
+	}
+	defer httpResp.Body.Close()
+
+	body, err := io.ReadAll(httpResp.Body)
+	if err != nil {
+		return checker.Response{}, err
+	}
+
+	finalURL := ""
+	if httpResp.Request != nil && httpResp.Request.URL != nil {
+		finalURL = httpResp.Request.URL.String()
+	}
+
+	return checker.Response{
+		StatusCode: httpResp.StatusCode,
+		Body:       body,
+		FinalURL:   finalURL,
+	}, nil
+}
+
+func (e *Enola) buildRequest(ctx context.Context, site Website, username string) (*http.Request, error) {
+	probeURL := site.URLProbe
+	if probeURL == "" {
+		probeURL = site.URL
+	}
+	probeURL = strings.ReplaceAll(probeURL, "{}", username)
+
+	method := site.RequestMethod
+	if method == "" {
+		method = http.MethodGet
+	}
+
+	var body io.Reader
+	if site.RequestPayload != nil {
+		payload := substituteUsername(site.RequestPayload, username)
+		data, err := json.Marshal(payload)
+		if err != nil {
+			return nil, err
 		}
-	}()
+		body = bytes.NewReader(data)
+	}
 
-	return ch, nil
+	req, err := http.NewRequestWithContext(ctx, method, probeURL, body)
+	if err != nil {
+		return nil, err
+	}
+	for key, value := range site.Headers {
+		req.Header.Set(key, value)
+	}
+	if site.RequestPayload != nil && req.Header.Get("Content-Type") == "" {
+		req.Header.Set("Content-Type", "application/json")
+	}
+	return req, nil
+}
+
+func substituteUsername(value any, username string) any {
+	switch v := value.(type) {
+	case string:
+		return strings.ReplaceAll(v, "{}", username)
+	case map[string]any:
+		out := make(map[string]any, len(v))
+		for key, val := range v {
+			out[key] = substituteUsername(val, username)
+		}
+		return out
+	case []any:
+		out := make([]any, len(v))
+		for i, val := range v {
+			out[i] = substituteUsername(val, username)
+		}
+		return out
+	default:
+		return value
+	}
 }
diff --git a/error.go b/error.go
deleted file mode 100644
--- a/error.go
+++ /dev/null
@@ -1,6 +0,0 @@
-package enola
-
-const (
-	ErrDataFileIsNotAValidJson = "the data file cannot be read due to invalid JSON format"
-	ErrSiteNotFound            = "the requested site is not supported"
-)
diff --git a/errors.go b/errors.go
new file mode 100644
--- /dev/null
+++ b/errors.go
@@ -0,0 +1,9 @@
+package enola
+
+import "errors"
+
+var (
+	ErrDataFileIsNotAValidJson = errors.New("the data file cannot be read due to invalid JSON format")
+	ErrSiteNotFound            = errors.New("the requested site is not supported")
+	ErrUnknownErrorType        = errors.New("unknown error type")
+)
diff --git a/go.mod b/go.mod
--- a/go.mod
+++ b/go.mod
@@ -6,8 +6,10 @@ require (
 	charm.land/bubbles/v2 v2.1.0
 	charm.land/bubbletea/v2 v2.0.6
 	charm.land/lipgloss/v2 v2.0.3
+	github.com/dlclark/regexp2 v1.12.0
 	github.com/spf13/cobra v1.10.2
 	golang.org/x/sync v0.20.0
+	golang.org/x/term v0.43.0
 )
 
 require (
diff --git a/go.sum b/go.sum
--- a/go.sum
+++ b/go.sum
@@ -10,8 +10,6 @@ github.com/aymanbagabas/go-udiff v0.4.1 h1:OEIrQ8maEeDBXQDoGCbbTTXYJMYRCRO1fnodZ
 github.com/aymanbagabas/go-udiff v0.4.1/go.mod h1:0L9PGwj20lrtmEMeyw4WKJ/TMyDtvAoK9bf2u/mNo3w=
 github.com/charmbracelet/colorprofile v0.4.3 h1:QPa1IWkYI+AOB+fE+mg/5/4HRMZcaXex9t5KX76i20Q=
 github.com/charmbracelet/colorprofile v0.4.3/go.mod h1:/zT4BhpD5aGFpqQQqw7a+VtHCzu+zrQtt1zhMt9mR4Q=
-github.com/charmbracelet/ultraviolet v0.0.0-20260511121909-c840852527f3 h1:pxGjlWZFcRQMWAdtjRelpL3Gbu8iYIyuO3Eqbd037Ow=
-github.com/charmbracelet/ultraviolet v0.0.0-20260511121909-c840852527f3/go.mod h1:SnKWaPaTnkTNXJgdgdquu66de12V8pW/b/qlTGaF9xg=
 github.com/charmbracelet/ultraviolet v0.0.0-20260525132238-948f4557a654 h1:FpSYhY28ucg9ZRr+2wj67FAQ0Ey5yiK0072PmRDJNek=
 github.com/charmbracelet/ultraviolet v0.0.0-20260525132238-948f4557a654/go.mod h1:hFpumms29Smx3LStRfku8vcCTBe1Kq8aCXtHUJa3mjY=
 github.com/charmbracelet/x/ansi v0.11.7 h1:kzv1kJvjg2S3r9KHo8hDdHFQLEqn4RBCb39dAYC84jI=
@@ -29,6 +27,8 @@ github.com/clipperhouse/displaywidth v0.11.0/go.mod h1:bkrFNkf81G8HyVqmKGxsPufD3
 github.com/clipperhouse/uax29/v2 v2.7.0 h1:+gs4oBZ2gPfVrKPthwbMzWZDaAFPGYK72F0NJv2v7Vk=
 github.com/clipperhouse/uax29/v2 v2.7.0/go.mod h1:EFJ2TJMRUaplDxHKj1qAEhCtQPW2tJSwu5BF98AuoVM=
 github.com/cpuguy83/go-md2man/v2 v2.0.6/go.mod h1:oOW0eioCTA6cOiMLiUPZOpcVxMig6NIQQ7OS05n1F4g=
+github.com/dlclark/regexp2 v1.12.0 h1:0j4c5qQmnC6XOWNjP3PIXURXN2gWx76rd3KvgdPkCz8=
+github.com/dlclark/regexp2 v1.12.0/go.mod h1:DHkYz0B9wPfa6wondMfaivmHpzrQ3v9q8cnmRbL6yW8=
 github.com/inconshreveable/mousetrap v1.1.0 h1:wN+x4NVGpMsO7ErUn/mUI3vEoE6Jt13X2s0bqwp9tc8=
 github.com/inconshreveable/mousetrap v1.1.0/go.mod h1:vpF70FUmC8bwa3OWnCshd2FqLfsEA9PFc4w1p2J65bw=
 github.com/kylelemons/godebug v1.1.0 h1:RPNrshWIDI6G2gRW9EHilWtl7Z6Sb1BR0xunSBf0SNc=
@@ -58,4 +58,6 @@ golang.org/x/sync v0.20.0 h1:e0PTpb7pjO8GAtTs2dQ6jYa5BWYlMuX047Dco/pItO4=
 golang.org/x/sync v0.20.0/go.mod h1:9xrNwdLfx4jkKbNva9FpL6vEN7evnE43NNNJQ2LF3+0=
 golang.org/x/sys v0.45.0 h1:dO4czNzziLiiXplLQgBCEpCvXQ3dnkn0SdaZSYdQ+FY=
 golang.org/x/sys v0.45.0/go.mod h1:4GL1E5IUh+htKOUEOaiffhrAeqysfVGipDYzABqnCmw=
+golang.org/x/term v0.43.0 h1:S4RLU2sB31O/NCl+zFN9Aru9A/Cq2aqKpTZJ6B+DwT4=
+golang.org/x/term v0.43.0/go.mod h1:lrhlHNdQJHO+1qVYiHfFKVuVioJIheAc3fBSMFYEIsk=
 gopkg.in/check.v1 v0.0.0-20161208181325-20d25e280405/go.mod h1:Co6ibVJAznAaIkqp8huTwlJQCZ016jof/cbN4VW5Yz0=
diff --git a/internal/checker/checker.go b/internal/checker/checker.go
new file mode 100644
--- /dev/null
+++ b/internal/checker/checker.go
@@ -0,0 +1,20 @@
+package checker
+
+// Response holds HTTP probe data passed to detectors.
+type Response struct {
+	StatusCode int
+	Body       []byte
+	FinalURL   string // resp.Request.URL.String() after redirects
+}
+
+// Target holds site-specific detection configuration.
+type Target struct {
+	ErrorMessages []string
+	ErrorURL      string
+	ErrorCodes    []int
+}
+
+// Detector decides whether a username exists on a site given a probe response.
+type Detector interface {
+	Detect(resp Response, target Target) (found bool, err error)
+}
diff --git a/internal/checker/message.go b/internal/checker/message.go
new file mode 100644
--- /dev/null
+++ b/internal/checker/message.go
@@ -0,0 +1,19 @@
+package checker
+
+import "strings"
+
+func init() {
+	Register("message", func() Detector { return messageDetector{} })
+}
+
+type messageDetector struct{}
+
+func (messageDetector) Detect(resp Response, target Target) (bool, error) {
+	body := string(resp.Body)
+	for _, msg := range target.ErrorMessages {
+		if strings.Contains(body, msg) {
+			return false, nil
+		}
+	}
+	return true, nil
+}
diff --git a/internal/checker/registry.go b/internal/checker/registry.go
new file mode 100644
--- /dev/null
+++ b/internal/checker/registry.go
@@ -0,0 +1,20 @@
+package checker
+
+// Factory creates a new Detector instance.
+type Factory func() Detector
+
+var registry = map[string]Factory{}
+
+// Register adds a detector factory for the given errorType.
+func Register(errorType string, f Factory) {
+	registry[errorType] = f
+}
+
+// Lookup returns a detector for the given errorType.
+func Lookup(errorType string) (Detector, bool) {
+	f, ok := registry[errorType]
+	if !ok {
+		return nil, false
+	}
+	return f(), true
+}
diff --git a/internal/checker/response_url.go b/internal/checker/response_url.go
new file mode 100644
--- /dev/null
+++ b/internal/checker/response_url.go
@@ -0,0 +1,19 @@
+package checker
+
+import (
+	"net/http"
+	"strings"
+)
+
+func init() {
+	Register("response_url", func() Detector { return responseURLDetector{} })
+}
+
+type responseURLDetector struct{}
+
+func (responseURLDetector) Detect(resp Response, target Target) (bool, error) {
+	if target.ErrorURL == "" {
+		return resp.StatusCode == http.StatusOK, nil
+	}
+	return !strings.HasPrefix(resp.FinalURL, target.ErrorURL), nil
+}
diff --git a/internal/checker/status_code.go b/internal/checker/status_code.go
new file mode 100644
--- /dev/null
+++ b/internal/checker/status_code.go
@@ -0,0 +1,18 @@
+package checker
+
+import "net/http"
+
+func init() {
+	Register("status_code", func() Detector { return statusCodeDetector{} })
+}
+
+type statusCodeDetector struct{}
+
+func (statusCodeDetector) Detect(resp Response, target Target) (bool, error) {
+	for _, code := range target.ErrorCodes {
+		if resp.StatusCode == code {
+			return false, nil
+		}
+	}
+	return resp.StatusCode == http.StatusOK, nil
+}
diff --git a/internal/export/csv.go b/internal/export/csv.go
new file mode 100644
--- /dev/null
+++ b/internal/export/csv.go
@@ -0,0 +1,33 @@
+package export
+
+import (
+	"encoding/csv"
+	"strconv"
+)
+
+type csvWriter struct {
+	outputPath string
+	items      []Item
+}
+
+func (w csvWriter) Write() error {
+	file, err := openOrCreateFile(w.outputPath)
+	if err != nil {
+		return err
+	}
+	defer file.Close()
+
+	writer := csv.NewWriter(file)
+	defer writer.Flush()
+
+	if err := writer.Write([]string{"title", "url", "found"}); err != nil {
+		return err
+	}
+	for _, item := range w.items {
+		row := []string{item.Title, item.URL, strconv.FormatBool(item.Found)}
+		if err := writer.Write(row); err != nil {
+			return err
+		}
+	}
+	return writer.Error()
+}
diff --git a/internal/export/file.go b/internal/export/file.go
new file mode 100644
--- /dev/null
+++ b/internal/export/file.go
@@ -0,0 +1,14 @@
+package export
+
+import (
+	"os"
+	"path/filepath"
+)
+
+func openOrCreateFile(filename string) (*os.File, error) {
+	dir := filepath.Dir(filename)
+	if err := os.MkdirAll(dir, 0o755); err != nil {
+		return nil, err
+	}
+	return os.OpenFile(filename, os.O_RDWR|os.O_CREATE|os.O_TRUNC, 0o644)
+}
diff --git a/internal/export/json.go b/internal/export/json.go
new file mode 100644
--- /dev/null
+++ b/internal/export/json.go
@@ -0,0 +1,22 @@
+package export
+
+import (
+	"encoding/json"
+)
+
+type jsonWriter struct {
+	outputPath string
+	items      []Item
+}
+
+func (w jsonWriter) Write() error {
+	file, err := openOrCreateFile(w.outputPath)
+	if err != nil {
+		return err
+	}
+	defer file.Close()
+
+	encoder := json.NewEncoder(file)
+	encoder.SetIndent("", "  ")
+	return encoder.Encode(w.items)
+}
diff --git a/internal/export/writer.go b/internal/export/writer.go
new file mode 100644
--- /dev/null
+++ b/internal/export/writer.go
@@ -0,0 +1,60 @@
+package export
+
+import (
+	"fmt"
+	"strings"
+)
+
+// ExportType identifies a supported export format.
+type ExportType string
+
+const (
+	JSON         ExportType = "json"
+	CSV          ExportType = "csv"
+	NotSupported ExportType = "notsupported"
+)
+
+// Item is a single export row.
+type Item struct {
+	Title string `json:"title"`
+	URL   string `json:"url"`
+	Found bool   `json:"found"`
+}
+
+// Writer persists export items.
+type Writer interface {
+	Write() error
+}
+
+type factory func(path string, items []Item) Writer
+
+var writers = map[ExportType]factory{
+	JSON: func(path string, items []Item) Writer {
+		return jsonWriter{outputPath: path, items: items}
+	},
+	CSV: func(path string, items []Item) Writer {
+		return csvWriter{outputPath: path, items: items}
+	},
+}
+
+// CheckExportType returns the export type for a file path.
+func CheckExportType(filename string) ExportType {
+	lower := strings.ToLower(filename)
+	if strings.HasSuffix(lower, string(JSON)) {
+		return JSON
+	}
+	if strings.HasSuffix(lower, string(CSV)) {
+		return CSV
+	}
+	return NotSupported
+}
+
+// NewWriter returns a Writer for the given path and items.
+func NewWriter(path string, items []Item) (Writer, error) {
+	exportType := CheckExportType(path)
+	f, ok := writers[exportType]
+	if !ok {
+		return nil, fmt.Errorf("unsupported export format: %s", path)
+	}
+	return f(path, items), nil
+}
diff --git a/options.go b/options.go
new file mode 100644
--- /dev/null
+++ b/options.go
@@ -0,0 +1,45 @@
+package enola
+
+import (
+	"net/http"
+	"time"
+
+	"golang.org/x/sync/semaphore"
+)
+
+const (
+	defaultConcurrency = 20
+	defaultTimeout     = 20 * time.Second
+)
+
+// Option configures an Enola instance.
+type Option func(*Enola)
+
+// WithHTTPClient sets the HTTP client used for probes.
+func WithHTTPClient(client *http.Client) Option {
+	return func(e *Enola) {
+		e.client = client
+	}
+}
+
+// WithConcurrency sets the maximum number of concurrent probes.
+func WithConcurrency(n int64) Option {
+	return func(e *Enola) {
+		if n > 0 {
+			e.sem = semaphore.NewWeighted(n)
+		}
+	}
+}
+
+// WithData replaces the embedded site database (mainly for tests).
+func WithData(data map[string]Website) Option {
+	return func(e *Enola) {
+		e.Data = data
+	}
+}
+
+func defaultHTTPClient() *http.Client {
+	return &http.Client{
+		Timeout: defaultTimeout,
+	}
+}
diff --git a/regex.go b/regex.go
new file mode 100644
--- /dev/null
+++ b/regex.go
@@ -0,0 +1,26 @@
+package enola
+
+import (
+	"regexp"
+
+	"github.com/dlclark/regexp2"
+)
+
+// matchUsernameRegex checks username against a site regexCheck pattern.
+// Patterns from data.json may use PCRE features (lookahead/lookbehind) unsupported
+// by Go's regexp package, so regexp2 is used as a fallback.
+func matchUsernameRegex(pattern, username string) (matched bool, err error) {
+	if pattern == "" {
+		return true, nil
+	}
+
+	if re, compileErr := regexp.Compile(pattern); compileErr == nil {
+		return re.MatchString(username), nil
+	}
+
+	re, compileErr := regexp2.Compile(pattern, 0)
+	if compileErr != nil {
+		return false, compileErr
+	}
+	return re.MatchString(username)
+}
diff --git a/result.go b/result.go
new file mode 100644
--- /dev/null
+++ b/result.go
@@ -0,0 +1,19 @@
+package enola
+
+// Status describes the outcome of a username check.
+type Status int
+
+const (
+	StatusNotFound Status = iota
+	StatusFound
+	StatusInvalid
+	StatusErrored
+)
+
+// Result is a single site check outcome.
+type Result struct {
+	Name   string `json:"name"`
+	URL    string `json:"url"`
+	Found  bool   `json:"found"`
+	Status Status `json:"-"`
+}
diff --git a/website.go b/website.go
new file mode 100644
--- /dev/null
+++ b/website.go
@@ -0,0 +1,104 @@
+package enola
+
+import (
+	"encoding/json"
+	"fmt"
+)
+
+// Website holds per-site configuration from data.json.
+type Website struct {
+	ErrorType         string            `json:"errorType"`
+	ErrorMessages     []string          `json:"-"`
+	ErrorURL          string            `json:"errorUrl"`
+	ErrorCodes        []int             `json:"-"`
+	URL               string            `json:"url"`
+	URLProbe          string            `json:"urlProbe"`
+	URLMain           string            `json:"urlMain"`
+	RegexCheck        string            `json:"regexCheck"`
+	RequestMethod     string            `json:"request_method"`
+	RequestPayload    map[string]any    `json:"request_payload"`
+	Headers           map[string]string `json:"headers"`
+	IsNSFW            bool              `json:"isNSFW"`
+	UsernameClaimed   string            `json:"username_claimed"`
+	UsernameUnclaimed string            `json:"username_unclaimed"`
+}
+
+type websiteJSON struct {
+	ErrorType         string            `json:"errorType"`
+	ErrorMsg          json.RawMessage   `json:"errorMsg"`
+	ErrorURL          string            `json:"errorUrl"`
+	ErrorCode         json.RawMessage   `json:"errorCode"`
+	URL               string            `json:"url"`
+	URLProbe          string            `json:"urlProbe"`
+	URLMain           string            `json:"urlMain"`
+	RegexCheck        string            `json:"regexCheck"`
+	RequestMethod     string            `json:"request_method"`
+	RequestPayload    map[string]any    `json:"request_payload"`
+	Headers           map[string]string `json:"headers"`
+	IsNSFW            bool              `json:"isNSFW"`
+	UsernameClaimed   string            `json:"username_claimed"`
+	UsernameUnclaimed string            `json:"username_unclaimed"`
+}
+
+// UnmarshalJSON normalizes errorMsg (string | []string) and errorCode (int | []int).
+func (w *Website) UnmarshalJSON(data []byte) error {
+	var raw websiteJSON
+	if err := json.Unmarshal(data, &raw); err != nil {
+		return err
+	}
+
+	msgs, err := parseErrorMessages(raw.ErrorMsg)
+	if err != nil {
+		return fmt.Errorf("errorMsg: %w", err)
+	}
+	codes, err := parseErrorCodes(raw.ErrorCode)
+	if err != nil {
+		return fmt.Errorf("errorCode: %w", err)
+	}
+
+	w.ErrorType = raw.ErrorType
+	w.ErrorMessages = msgs
+	w.ErrorURL = raw.ErrorURL
+	w.ErrorCodes = codes
+	w.URL = raw.URL
+	w.URLProbe = raw.URLProbe
+	w.URLMain = raw.URLMain
+	w.RegexCheck = raw.RegexCheck
+	w.RequestMethod = raw.RequestMethod
+	w.RequestPayload = raw.RequestPayload
+	w.Headers = raw.Headers
+	w.IsNSFW = raw.IsNSFW
+	w.UsernameClaimed = raw.UsernameClaimed
+	w.UsernameUnclaimed = raw.UsernameUnclaimed
+	return nil
+}
+
+func parseErrorMessages(raw json.RawMessage) ([]string, error) {
+	if len(raw) == 0 {
+		return nil, nil
+	}
+	var s string
+	if err := json.Unmarshal(raw, &s); err == nil {
+		return []string{s}, nil
+	}
+	var list []string
+	if err := json.Unmarshal(raw, &list); err != nil {
+		return nil, err
+	}
+	return list, nil
+}
+
+func parseErrorCodes(raw json.RawMessage) ([]int, error) {
+	if len(raw) == 0 {
+		return nil, nil
+	}
+	var n int
+	if err := json.Unmarshal(raw, &n); err == nil {
+		return []int{n}, nil
+	}
+	var list []int
+	if err := json.Unmarshal(raw, &list); err != nil {
+		return nil, err
+	}
+	return list, nil
+}
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
