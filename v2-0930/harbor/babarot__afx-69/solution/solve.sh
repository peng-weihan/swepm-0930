#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/cmd/check.go b/cmd/check.go
--- a/cmd/check.go
+++ b/cmd/check.go
@@ -4,16 +4,13 @@ import (
 	"context"
 	"fmt"
 	"log"
-	"os"
-	"os/signal"
 
 	"github.com/spf13/cobra"
-	"golang.org/x/sync/errgroup"
 
-	"github.com/babarot/afx/pkg/config"
-	"github.com/babarot/afx/pkg/errors"
-	"github.com/babarot/afx/pkg/helpers/templates"
-	"github.com/babarot/afx/pkg/state"
+	"github.com/babarot/afx/internal/helpers/templates"
+	afxpkg "github.com/babarot/afx/internal/pkg"
+	"github.com/babarot/afx/internal/runner"
+	"github.com/babarot/afx/internal/state"
 )
 
 type checkCmd struct {
@@ -76,7 +73,7 @@ func (m metaCmd) newCheckCmd() *cobra.Command {
 
 			pkgs := m.GetPackages(resources)
 			m.env.AskWhen(map[string]bool{
-				"GITHUB_TOKEN": config.HasGitHubReleaseBlock(pkgs),
+				"GITHUB_TOKEN": afxpkg.HasGitHubReleaseBlock(pkgs),
 			})
 
 			return c.run(pkgs)
@@ -89,59 +86,23 @@ func (m metaCmd) newCheckCmd() *cobra.Command {
 	return checkCmd
 }
 
-type checkResult struct {
-	Package config.Package
-	Error   error
-}
-
-func (c *checkCmd) run(pkgs []config.Package) error {
-	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
-	defer stop()
-
-	progress := config.NewProgress(pkgs)
-	completion := make(chan config.Status)
-	limit := make(chan struct{}, 16)
-	results := make(chan checkResult)
-
-	go func() {
-		progress.Print(completion)
-	}()
-
+func (c *checkCmd) run(pkgs []afxpkg.Package) error {
 	log.Printf("[DEBUG] (check): start to run each pkg.Check()")
-	eg := errgroup.Group{}
-	for _, pkg := range pkgs {
-		eg.Go(func() error {
-			limit <- struct{}{}
-			defer func() { <-limit }()
-			err := pkg.Check(ctx, completion)
-			select {
-			case results <- checkResult{Package: pkg, Error: err}:
-				return nil
-			case <-ctx.Done():
-				return errors.Wrapf(ctx.Err(), "%s: canceled checking", pkg.GetName())
-			}
-		})
-	}
-
-	go func() {
-		_ = eg.Wait()
-		close(results)
-	}()
 
-	var exit errors.Errors
-	for result := range results {
-		exit.Append(result.Error)
-	}
-	if err := eg.Wait(); err != nil {
-		log.Printf("[ERROR] failed to check: %s", err)
-		exit.Append(err)
+	runnerPkgs := make([]runner.Package, len(pkgs))
+	for i, p := range pkgs {
+		runnerPkgs[i] = p
 	}
 
-	defer func(err error) {
-		if err != nil {
-			_ = c.env.Refresh()
+	err := runner.Execute(runnerPkgs, func(p runner.Package) runner.TaskFunc {
+		pkg, _ := p.(afxpkg.Package)
+		return func(ctx context.Context, completion chan<- runner.Status) error {
+			return pkg.Check(ctx, completion)
 		}
-	}(exit.ErrorOrNil())
+	})
 
-	return exit.ErrorOrNil()
+	if err != nil {
+		_ = c.env.Refresh()
+	}
+	return err
 }
diff --git a/cmd/completion.go b/cmd/completion.go
--- a/cmd/completion.go
+++ b/cmd/completion.go
@@ -5,7 +5,7 @@ import (
 
 	"github.com/spf13/cobra"
 
-	"github.com/babarot/afx/pkg/helpers/templates"
+	"github.com/babarot/afx/internal/helpers/templates"
 )
 
 var (
diff --git a/cmd/init.go b/cmd/init.go
--- a/cmd/init.go
+++ b/cmd/init.go
@@ -6,7 +6,7 @@ import (
 
 	"github.com/spf13/cobra"
 
-	"github.com/babarot/afx/pkg/helpers/templates"
+	"github.com/babarot/afx/internal/helpers/templates"
 )
 
 var (
diff --git a/cmd/install.go b/cmd/install.go
--- a/cmd/install.go
+++ b/cmd/install.go
@@ -4,18 +4,14 @@ import (
 	"context"
 	"fmt"
 	"log"
-	"os"
-	"os/signal"
 
 	"github.com/spf13/cobra"
 
-	"golang.org/x/sync/errgroup"
-
-	"github.com/babarot/afx/pkg/config"
-	"github.com/babarot/afx/pkg/errors"
-	"github.com/babarot/afx/pkg/helpers/templates"
-	"github.com/babarot/afx/pkg/logging"
-	"github.com/babarot/afx/pkg/state"
+	"github.com/babarot/afx/internal/helpers/templates"
+	"github.com/babarot/afx/internal/logging"
+	afxpkg "github.com/babarot/afx/internal/pkg"
+	"github.com/babarot/afx/internal/runner"
+	"github.com/babarot/afx/internal/state"
 )
 
 type installCmd struct {
@@ -78,8 +74,8 @@ func (m metaCmd) newInstallCmd() *cobra.Command {
 
 			pkgs := m.GetPackages(resources)
 			m.env.AskWhen(map[string]bool{
-				"GITHUB_TOKEN":      config.HasGitHubReleaseBlock(pkgs),
-				"AFX_SUDO_PASSWORD": config.HasSudoInCommandBuildSteps(pkgs),
+				"GITHUB_TOKEN":      afxpkg.HasGitHubReleaseBlock(pkgs),
+				"AFX_SUDO_PASSWORD": afxpkg.HasSudoInCommandBuildSteps(pkgs),
 			})
 
 			return c.run(pkgs)
@@ -92,30 +88,17 @@ func (m metaCmd) newInstallCmd() *cobra.Command {
 	return installCmd
 }
 
-type installResult struct {
-	Package config.Package
-	Error   error
-}
-
-func (c *installCmd) run(pkgs []config.Package) error {
-	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
-	defer stop()
-
-	progress := config.NewProgress(pkgs)
-	completion := make(chan config.Status)
-	limit := make(chan struct{}, 16)
-	results := make(chan installResult)
+func (c *installCmd) run(pkgs []afxpkg.Package) error {
+	log.Printf("[DEBUG] (install): start to run each pkg.Install()")
 
-	go func() {
-		progress.Print(completion)
-	}()
+	runnerPkgs := make([]runner.Package, len(pkgs))
+	for i, p := range pkgs {
+		runnerPkgs[i] = p
+	}
 
-	log.Printf("[DEBUG] (install): start to run each pkg.Install()")
-	eg := errgroup.Group{}
-	for _, pkg := range pkgs {
-		eg.Go(func() error {
-			limit <- struct{}{}
-			defer func() { <-limit }()
+	err := runner.Execute(runnerPkgs, func(p runner.Package) runner.TaskFunc {
+		pkg, _ := p.(afxpkg.Package)
+		return func(ctx context.Context, completion chan<- runner.Status) error {
 			err := pkg.Install(ctx, completion)
 			switch err {
 			case nil:
@@ -126,35 +109,12 @@ func (c *installCmd) run(pkgs []config.Package) error {
 					_ = pkg.Uninstall(ctx)
 				}
 			}
-			select {
-			case results <- installResult{Package: pkg, Error: err}:
-				return nil
-			case <-ctx.Done():
-				return errors.Wrapf(ctx.Err(), "%s: canceled installation", pkg.GetName())
-			}
-		})
-	}
-
-	go func() {
-		_ = eg.Wait()
-		close(results)
-	}()
-
-	var exit errors.Errors
-	for result := range results {
-		exit.Append(result.Error)
-	}
-
-	if err := eg.Wait(); err != nil {
-		log.Printf("[ERROR] failed to install: %s", err)
-		exit.Append(err)
-	}
-
-	defer func(err error) {
-		if err != nil {
-			_ = c.env.Refresh()
+			return err
 		}
-	}(exit.ErrorOrNil())
+	})
 
-	return exit.ErrorOrNil()
+	if err != nil {
+		_ = c.env.Refresh()
+	}
+	return err
 }
diff --git a/cmd/meta.go b/cmd/meta.go
--- a/cmd/meta.go
+++ b/cmd/meta.go
@@ -11,21 +11,21 @@ import (
 	"github.com/AlecAivazis/survey/v2"
 	"github.com/fatih/color"
 
-	"github.com/babarot/afx/pkg/config"
-	"github.com/babarot/afx/pkg/env"
-	"github.com/babarot/afx/pkg/errors"
-	"github.com/babarot/afx/pkg/github"
-	"github.com/babarot/afx/pkg/printers"
-	"github.com/babarot/afx/pkg/state"
-	"github.com/babarot/afx/pkg/update"
+	"github.com/babarot/afx/internal/env"
+	"github.com/babarot/afx/internal/errors"
+	"github.com/babarot/afx/internal/github"
+	afxpkg "github.com/babarot/afx/internal/pkg"
+	"github.com/babarot/afx/internal/printers"
+	"github.com/babarot/afx/internal/state"
+	"github.com/babarot/afx/internal/update"
 )
 
 type metaCmd struct {
 	env      *env.Config
-	packages []config.Package
-	main     *config.Main
+	packages []afxpkg.Package
+	main     *afxpkg.Main
 	state    *state.State
-	configs  map[string]config.Config
+	configs  map[string]afxpkg.Config
 
 	updateMessageChan chan *update.ReleaseInfo
 }
@@ -45,20 +45,20 @@ func (m *metaCmd) init() error {
 	cfgRoot := filepath.Join(os.Getenv("HOME"), ".config", "afx")
 	cache := filepath.Join(root, "cache.json")
 
-	err := config.CreateDirIfNotExist(cfgRoot)
+	err := afxpkg.CreateDirIfNotExist(cfgRoot)
 	if err != nil {
 		return errors.Wrapf(err, "%s: failed to create dir", cfgRoot)
 	}
-	files, err := config.WalkDir(cfgRoot)
+	files, err := afxpkg.WalkDir(cfgRoot)
 	if err != nil {
 		return errors.Wrapf(err, "%s: failed to walk dir", cfgRoot)
 	}
 
-	var pkgs []config.Package
-	app := &config.DefaultMain
-	m.configs = map[string]config.Config{}
+	var pkgs []afxpkg.Package
+	app := &afxpkg.DefaultMain
+	m.configs = map[string]afxpkg.Config{}
 	for _, file := range files {
-		cfg, err := config.Read(file)
+		cfg, err := afxpkg.Read(file)
 		if err != nil {
 			return errors.Wrapf(err, "%s: failed to read config", file)
 		}
@@ -78,11 +78,11 @@ func (m *metaCmd) init() error {
 
 	m.main = app
 
-	if err := config.Validate(pkgs); err != nil {
+	if err := afxpkg.Validate(pkgs); err != nil {
 		return errors.Wrap(err, "failed to validate packages")
 	}
 
-	pkgs, err = config.Sort(pkgs)
+	pkgs, err = afxpkg.Sort(pkgs)
 	if err != nil {
 		return errors.Wrap(err, "failed to resolve dependencies between packages")
 	}
@@ -98,14 +98,14 @@ func (m *metaCmd) init() error {
 		"AFX_SHELL":        env.Variable{Default: m.main.Shell},
 		"AFX_SUDO_PASSWORD": env.Variable{
 			Input: env.Input{
-				When:    config.HasSudoInCommandBuildSteps(m.packages),
+				When:    afxpkg.HasSudoInCommandBuildSteps(m.packages),
 				Message: "Please enter sudo command password",
 				Help:    "Some packages build steps requires sudo command",
 			},
 		},
 		"GITHUB_TOKEN": env.Variable{
 			Input: env.Input{
-				When:    config.HasGitHubReleaseBlock(m.packages),
+				When:    afxpkg.HasGitHubReleaseBlock(m.packages),
 				Message: "Please type your GITHUB_TOKEN",
 				Help:    "To fetch GitHub Releases, GitHub token is required",
 			},
@@ -233,7 +233,7 @@ func checkForUpdate(currentVersion string) (*update.ReleaseInfo, error) {
 	return update.CheckForUpdate(client, stateFilePath, Repository, Version)
 }
 
-func (m metaCmd) GetPackage(resource state.Resource) config.Package {
+func (m metaCmd) GetPackage(resource state.Resource) afxpkg.Package {
 	for _, pkg := range m.packages {
 		if pkg.GetName() == resource.Name {
 			return pkg
@@ -242,24 +242,24 @@ func (m metaCmd) GetPackage(resource state.Resource) config.Package {
 	return nil
 }
 
-func (m metaCmd) GetPackages(resources []state.Resource) []config.Package {
-	var pkgs []config.Package
+func (m metaCmd) GetPackages(resources []state.Resource) []afxpkg.Package {
+	var pkgs []afxpkg.Package
 	for _, resource := range resources {
 		pkgs = append(pkgs, m.GetPackage(resource))
 	}
 	return pkgs
 }
 
-func (m metaCmd) GetConfig() config.Config {
-	var all config.Config
-	for _, config := range m.configs {
-		if config.Main != nil {
-			all.Main = config.Main
+func (m metaCmd) GetConfig() afxpkg.Config {
+	var all afxpkg.Config
+	for _, cfg := range m.configs {
+		if cfg.Main != nil {
+			all.Main = cfg.Main
 		}
-		all.GitHub = append(all.GitHub, config.GitHub...)
-		all.Gist = append(all.Gist, config.Gist...)
-		all.HTTP = append(all.HTTP, config.HTTP...)
-		all.Local = append(all.Local, config.Local...)
+		all.GitHub = append(all.GitHub, cfg.GitHub...)
+		all.Gist = append(all.Gist, cfg.Gist...)
+		all.HTTP = append(all.HTTP, cfg.HTTP...)
+		all.Local = append(all.Local, cfg.Local...)
 	}
 	return all
 }
diff --git a/cmd/root.go b/cmd/root.go
--- a/cmd/root.go
+++ b/cmd/root.go
@@ -8,10 +8,10 @@ import (
 
 	"github.com/spf13/cobra"
 
-	"github.com/babarot/afx/pkg/errors"
-	"github.com/babarot/afx/pkg/helpers/templates"
-	"github.com/babarot/afx/pkg/logging"
-	"github.com/babarot/afx/pkg/update"
+	"github.com/babarot/afx/internal/errors"
+	"github.com/babarot/afx/internal/helpers/templates"
+	"github.com/babarot/afx/internal/logging"
+	"github.com/babarot/afx/internal/update"
 )
 
 var Repository string = "babarot/afx"
diff --git a/cmd/self-update.go b/cmd/self-update.go
--- a/cmd/self-update.go
+++ b/cmd/self-update.go
@@ -12,9 +12,9 @@ import (
 	"github.com/fatih/color"
 	"github.com/spf13/cobra"
 
-	"github.com/babarot/afx/pkg/errors"
-	"github.com/babarot/afx/pkg/github"
-	"github.com/babarot/afx/pkg/helpers/templates"
+	"github.com/babarot/afx/internal/errors"
+	"github.com/babarot/afx/internal/github"
+	"github.com/babarot/afx/internal/helpers/templates"
 )
 
 type selfUpdateCmd struct {
diff --git a/cmd/show.go b/cmd/show.go
--- a/cmd/show.go
+++ b/cmd/show.go
@@ -9,9 +9,9 @@ import (
 	"github.com/goccy/go-yaml"
 	"github.com/spf13/cobra"
 
-	"github.com/babarot/afx/pkg/helpers/templates"
-	"github.com/babarot/afx/pkg/printers"
-	"github.com/babarot/afx/pkg/state"
+	"github.com/babarot/afx/internal/helpers/templates"
+	"github.com/babarot/afx/internal/printers"
+	"github.com/babarot/afx/internal/state"
 )
 
 type showCmd struct {
diff --git a/cmd/state.go b/cmd/state.go
--- a/cmd/state.go
+++ b/cmd/state.go
@@ -7,9 +7,9 @@ import (
 	"github.com/fatih/color"
 	"github.com/spf13/cobra"
 
-	"github.com/babarot/afx/pkg/errors"
-	"github.com/babarot/afx/pkg/helpers/templates"
-	"github.com/babarot/afx/pkg/state"
+	"github.com/babarot/afx/internal/errors"
+	"github.com/babarot/afx/internal/helpers/templates"
+	"github.com/babarot/afx/internal/state"
 )
 
 type stateCmd struct {
diff --git a/cmd/uninstall.go b/cmd/uninstall.go
--- a/cmd/uninstall.go
+++ b/cmd/uninstall.go
@@ -6,9 +6,9 @@ import (
 
 	"github.com/spf13/cobra"
 
-	"github.com/babarot/afx/pkg/errors"
-	"github.com/babarot/afx/pkg/helpers/templates"
-	"github.com/babarot/afx/pkg/state"
+	"github.com/babarot/afx/internal/errors"
+	"github.com/babarot/afx/internal/helpers/templates"
+	"github.com/babarot/afx/internal/state"
 )
 
 type uninstallCmd struct {
diff --git a/cmd/update.go b/cmd/update.go
--- a/cmd/update.go
+++ b/cmd/update.go
@@ -5,15 +5,13 @@ import (
 	"fmt"
 	"log"
 	"os"
-	"os/signal"
 
 	"github.com/spf13/cobra"
-	"golang.org/x/sync/errgroup"
 
-	"github.com/babarot/afx/pkg/config"
-	"github.com/babarot/afx/pkg/errors"
-	"github.com/babarot/afx/pkg/helpers/templates"
-	"github.com/babarot/afx/pkg/state"
+	"github.com/babarot/afx/internal/helpers/templates"
+	afxpkg "github.com/babarot/afx/internal/pkg"
+	"github.com/babarot/afx/internal/runner"
+	"github.com/babarot/afx/internal/state"
 )
 
 type updateCmd struct {
@@ -76,8 +74,8 @@ func (m metaCmd) newUpdateCmd() *cobra.Command {
 
 			pkgs := m.GetPackages(resources)
 			m.env.AskWhen(map[string]bool{
-				"GITHUB_TOKEN":      config.HasGitHubReleaseBlock(pkgs),
-				"AFX_SUDO_PASSWORD": config.HasSudoInCommandBuildSteps(pkgs),
+				"GITHUB_TOKEN":      afxpkg.HasGitHubReleaseBlock(pkgs),
+				"AFX_SUDO_PASSWORD": afxpkg.HasSudoInCommandBuildSteps(pkgs),
 			})
 
 			return c.run(pkgs)
@@ -90,31 +88,18 @@ func (m metaCmd) newUpdateCmd() *cobra.Command {
 	return updateCmd
 }
 
-type updateResult struct {
-	Package config.Package
-	Error   error
-}
-
-func (c *updateCmd) run(pkgs []config.Package) error {
-	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
-	defer stop()
-
-	progress := config.NewProgress(pkgs)
-	completion := make(chan config.Status)
-	limit := make(chan struct{}, 16)
-	results := make(chan updateResult)
+func (c *updateCmd) run(pkgs []afxpkg.Package) error {
+	log.Printf("[DEBUG] (update): start to run each pkg.Install()")
 
-	go func() {
-		progress.Print(completion)
-	}()
+	runnerPkgs := make([]runner.Package, len(pkgs))
+	for i, p := range pkgs {
+		runnerPkgs[i] = p
+	}
 
-	log.Printf("[DEBUG] (update): start to run each pkg.Install()")
-	eg := errgroup.Group{}
-	for _, pkg := range pkgs {
-		eg.Go(func() error {
-			limit <- struct{}{}
-			defer func() { <-limit }()
-			os.RemoveAll(pkg.GetHome()) // delete before updating
+	err := runner.Execute(runnerPkgs, func(p runner.Package) runner.TaskFunc {
+		pkg, _ := p.(afxpkg.Package)
+		return func(ctx context.Context, completion chan<- runner.Status) error {
+			_ = os.RemoveAll(pkg.GetHome()) // delete before updating
 			err := pkg.Install(ctx, completion)
 			switch err {
 			case nil:
@@ -123,34 +108,12 @@ func (c *updateCmd) run(pkgs []config.Package) error {
 				log.Printf("[DEBUG] uninstall %q because updating failed", pkg.GetName())
 				_ = pkg.Uninstall(ctx)
 			}
-			select {
-			case results <- updateResult{Package: pkg, Error: err}:
-				return nil
-			case <-ctx.Done():
-				return errors.Wrapf(ctx.Err(), "%s: canceled updating", pkg.GetName())
-			}
-		})
-	}
-
-	go func() {
-		_ = eg.Wait()
-		close(results)
-	}()
-
-	var exit errors.Errors
-	for result := range results {
-		exit.Append(result.Error)
-	}
-	if err := eg.Wait(); err != nil {
-		log.Printf("[ERROR] failed to update: %s", err)
-		exit.Append(err)
-	}
-
-	defer func(err error) {
-		if err != nil {
-			_ = c.env.Refresh()
+			return err
 		}
-	}(exit.ErrorOrNil())
+	})
 
-	return exit.ErrorOrNil()
+	if err != nil {
+		_ = c.env.Refresh()
+	}
+	return err
 }
diff --git a/pkg/data/data.go b/internal/data/data.go
rename from pkg/data/data.go
rename to internal/data/data.go
--- a/pkg/data/data.go
+++ b/internal/data/data.go

diff --git a/pkg/dependency/dependency.go b/internal/dependency/dependency.go
rename from pkg/dependency/dependency.go
rename to internal/dependency/dependency.go
--- a/pkg/dependency/dependency.go
+++ b/internal/dependency/dependency.go

diff --git a/pkg/env/config.go b/internal/env/config.go
rename from pkg/env/config.go
rename to internal/env/config.go
--- a/pkg/env/config.go
+++ b/internal/env/config.go
@@ -188,6 +188,7 @@ func (c *Config) save() error {
 	if err != nil {
 		return err
 	}
+	defer f.Close()
 	return json.NewEncoder(f).Encode(cfg)
 }
 
diff --git a/pkg/errors/errors.go b/internal/errors/errors.go
rename from pkg/errors/errors.go
rename to internal/errors/errors.go
--- a/pkg/errors/errors.go
+++ b/internal/errors/errors.go

diff --git a/pkg/errors/wrap.go b/internal/errors/wrap.go
rename from pkg/errors/wrap.go
rename to internal/errors/wrap.go
--- a/pkg/errors/wrap.go
+++ b/internal/errors/wrap.go

diff --git a/pkg/github/client.go b/internal/github/client.go
rename from pkg/github/client.go
rename to internal/github/client.go
--- a/pkg/github/client.go
+++ b/internal/github/client.go
@@ -6,7 +6,7 @@ import (
 	"net/http"
 	"os"
 
-	"github.com/babarot/afx/pkg/errors"
+	"github.com/babarot/afx/internal/errors"
 )
 
 // ClientOption represents an argument to NewClient
diff --git a/pkg/github/github.go b/internal/github/github.go
rename from pkg/github/github.go
rename to internal/github/github.go
--- a/pkg/github/github.go
+++ b/internal/github/github.go
@@ -16,8 +16,8 @@ import (
 	"github.com/mholt/archiver"
 	"github.com/schollz/progressbar/v3"
 
-	"github.com/babarot/afx/pkg/errors"
-	"github.com/babarot/afx/pkg/logging"
+	"github.com/babarot/afx/internal/errors"
+	"github.com/babarot/afx/internal/logging"
 )
 
 // Release represents a GitHub release and its client
diff --git a/internal/helpers/path/path.go b/internal/helpers/path/path.go
new file mode 100644
--- /dev/null
+++ b/internal/helpers/path/path.go
@@ -0,0 +1,32 @@
+package path
+
+import (
+	"os"
+	"path/filepath"
+	"runtime"
+	"strings"
+)
+
+// ExpandTilda replaces a leading ~ in the path with the user's home directory.
+func ExpandTilda(path string) string {
+	if !strings.HasPrefix(path, "~") {
+		return path
+	}
+
+	home := ""
+	switch runtime.GOOS {
+	case "windows":
+		home = filepath.Join(os.Getenv("HomeDrive"), os.Getenv("HomePath"))
+		if home == "" {
+			home = os.Getenv("UserProfile")
+		}
+	default:
+		home = os.Getenv("HOME")
+	}
+
+	if home == "" {
+		return path
+	}
+
+	return home + path[1:]
+}
diff --git a/pkg/helpers/shell/shell.go b/internal/helpers/shell/shell.go
rename from pkg/helpers/shell/shell.go
rename to internal/helpers/shell/shell.go
--- a/pkg/helpers/shell/shell.go
+++ b/internal/helpers/shell/shell.go

diff --git a/pkg/helpers/spin/spin.go b/internal/helpers/spin/spin.go
rename from pkg/helpers/spin/spin.go
rename to internal/helpers/spin/spin.go
--- a/pkg/helpers/spin/spin.go
+++ b/internal/helpers/spin/spin.go

diff --git a/pkg/helpers/spin/symbol.go b/internal/helpers/spin/symbol.go
rename from pkg/helpers/spin/symbol.go
rename to internal/helpers/spin/symbol.go
--- a/pkg/helpers/spin/symbol.go
+++ b/internal/helpers/spin/symbol.go

diff --git a/pkg/helpers/templates/README.md b/internal/helpers/templates/README.md
rename from pkg/helpers/templates/README.md
rename to internal/helpers/templates/README.md
--- a/pkg/helpers/templates/README.md
+++ b/internal/helpers/templates/README.md

diff --git a/pkg/helpers/templates/markdown.go b/internal/helpers/templates/markdown.go
rename from pkg/helpers/templates/markdown.go
rename to internal/helpers/templates/markdown.go
--- a/pkg/helpers/templates/markdown.go
+++ b/internal/helpers/templates/markdown.go

diff --git a/pkg/helpers/templates/normalizer.go b/internal/helpers/templates/normalizer.go
rename from pkg/helpers/templates/normalizer.go
rename to internal/helpers/templates/normalizer.go
--- a/pkg/helpers/templates/normalizer.go
+++ b/internal/helpers/templates/normalizer.go

diff --git a/pkg/logging/logging.go b/internal/logging/logging.go
rename from pkg/logging/logging.go
rename to internal/logging/logging.go
--- a/pkg/logging/logging.go
+++ b/internal/logging/logging.go

diff --git a/pkg/logging/transport.go b/internal/logging/transport.go
rename from pkg/logging/transport.go
rename to internal/logging/transport.go
--- a/pkg/logging/transport.go
+++ b/internal/logging/transport.go

diff --git a/pkg/config/command.go b/internal/pkg/command.go
rename from pkg/config/command.go
rename to internal/pkg/command.go
--- a/pkg/config/command.go
+++ b/internal/pkg/command.go
@@ -1,4 +1,4 @@
-package config
+package pkg
 
 import (
 	"bytes"
@@ -15,7 +15,8 @@ import (
 	"github.com/mattn/go-shellwords"
 	"github.com/mattn/go-zglob"
 
-	"github.com/babarot/afx/pkg/errors"
+	"github.com/babarot/afx/internal/errors"
+	pathutil "github.com/babarot/afx/internal/helpers/path"
 )
 
 // Command represents shell command configuration including build steps and symlinks.
@@ -57,7 +58,7 @@ func (l *Link) UnmarshalYAML(b []byte) error {
 	}
 
 	l.From = tmp.From
-	l.To = expandTilda(os.ExpandEnv(tmp.To))
+	l.To = pathutil.ExpandTilda(os.ExpandEnv(tmp.To))
 
 	return nil
 }
@@ -307,7 +308,7 @@ func (c Command) Init(pkg Package) error {
 		switch k {
 		case "PATH":
 			// avoid overwriting PATH
-			v = fmt.Sprintf("$PATH:%s", expandTilda(v))
+			v = fmt.Sprintf("$PATH:%s", pathutil.ExpandTilda(v))
 		default:
 			// through
 		}
diff --git a/pkg/config/config.go b/internal/pkg/config.go
rename from pkg/config/config.go
rename to internal/pkg/config.go
--- a/pkg/config/config.go
+++ b/internal/pkg/config.go
@@ -1,4 +1,4 @@
-package config
+package pkg
 
 import (
 	"bufio"
@@ -12,8 +12,7 @@ import (
 	"github.com/goccy/go-yaml"
 	"github.com/hashicorp/go-multierror"
 
-	"github.com/babarot/afx/pkg/dependency"
-	"github.com/babarot/afx/pkg/state"
+	"github.com/babarot/afx/internal/dependency"
 )
 
 // Config structure for file describing deployment. This includes the module source, inputs
@@ -230,69 +229,6 @@ func Validate(pkgs []Package) error {
 	return nil
 }
 
-func getResource(pkg Package) state.Resource {
-	var paths []string
-
-	// repository existence is also one of the path resource
-	paths = append(paths, pkg.GetHome())
-
-	if pkg.HasPluginBlock() {
-		plugin := pkg.GetPluginBlock()
-		paths = append(paths, plugin.GetSources(pkg)...)
-	}
-
-	if pkg.HasCommandBlock() {
-		command := pkg.GetCommandBlock()
-		links, _ := command.GetLink(pkg)
-		for _, link := range links {
-			paths = append(paths, link.From)
-			paths = append(paths, link.To)
-		}
-	}
-
-	var ty string
-	var version string
-	var id string
-
-	switch pkg := pkg.(type) {
-	case GitHub:
-		ty = "GitHub"
-		if pkg.HasReleaseBlock() {
-			ty = "GitHub Release"
-			version = pkg.Release.Tag
-		}
-		id = fmt.Sprintf("github.com/%s/%s", pkg.Owner, pkg.Repo)
-		if pkg.HasReleaseBlock() {
-			id = fmt.Sprintf("github.com/release/%s/%s", pkg.Owner, pkg.Repo)
-		}
-		if pkg.IsGHExtension() {
-			ty = "GitHub (gh extension)"
-			gh := pkg.As.GHExtension
-			paths = append(paths, gh.GetHome())
-		}
-	case Gist:
-		ty = "Gist"
-		id = fmt.Sprintf("gist.github.com/%s/%s", pkg.Owner, pkg.ID)
-	case Local:
-		ty = "Local"
-		id = fmt.Sprintf("local/%s", pkg.Directory)
-	case HTTP:
-		ty = "HTTP"
-		id = pkg.URL
-	default:
-		ty = "Unknown"
-	}
-
-	return state.Resource{
-		ID:      id,
-		Name:    pkg.GetName(),
-		Home:    pkg.GetHome(),
-		Type:    ty,
-		Version: version,
-		Paths:   paths,
-	}
-}
-
 func (c Config) Get(args ...string) Config {
 	var part Config
 	for _, arg := range args {
diff --git a/internal/pkg/gh_extension.go b/internal/pkg/gh_extension.go
new file mode 100644
--- /dev/null
+++ b/internal/pkg/gh_extension.go
@@ -0,0 +1,138 @@
+package pkg
+
+import (
+	"context"
+	"fmt"
+	"log"
+	"net/http"
+	"os"
+	"path/filepath"
+	"strings"
+
+	"github.com/go-playground/validator/v10"
+	"gopkg.in/yaml.v2"
+
+	"github.com/babarot/afx/internal/errors"
+	"github.com/babarot/afx/internal/github"
+)
+
+func ValidateGHExtension(fl validator.FieldLevel) bool {
+	return fl.Field().String() == "" || strings.HasPrefix(fl.Field().String(), "gh-")
+}
+
+func (c GitHub) IsGHExtension() bool {
+	return c.As != nil && c.As.GHExtension != nil && c.As.GHExtension.Name != ""
+}
+
+type ghManifest struct {
+	Owner    string `yaml:"owner"`
+	Name     string `yaml:"name"`
+	Host     string `yaml:"host"`
+	Tag      string `yaml:"tag"`
+	IsPinned bool   `yaml:"ispinned"`
+	Path     string `yaml:"path"`
+}
+
+func (gh GHExtension) GetHome() string {
+	base := filepath.Join(os.Getenv("HOME"), ".local", "share", "gh", "extensions")
+	var ext string
+	if gh.RenameTo == "" {
+		ext = filepath.Join(base, gh.Name)
+	} else {
+		ext = filepath.Join(base, gh.RenameTo)
+	}
+	return ext
+}
+
+func (gh GHExtension) GetTag() string {
+	if gh.Tag != "" {
+		return gh.Tag
+	}
+	return "latest"
+}
+
+func (gh GHExtension) Install(ctx context.Context, owner, repo, tag string) error {
+	available, _ := github.HasRelease(http.DefaultClient, owner, repo, tag)
+	if available {
+		err := gh.InstallFromRelease(ctx, owner, repo, tag)
+		if err != nil {
+			return fmt.Errorf("%w: %s: failed to get gh extension", err, gh.Name)
+		}
+	}
+
+	ghHome := gh.GetHome()
+	// ensure to create the parent dir of each gh extension's path
+	_ = os.MkdirAll(filepath.Dir(ghHome), os.ModePerm)
+
+	// make alias
+	if gh.RenameTo != "" {
+		if err := os.Symlink(
+			filepath.Join(ghHome, gh.Name),
+			filepath.Join(ghHome, gh.RenameTo),
+		); err != nil {
+			return fmt.Errorf("%w: failed to symlink as alise", err)
+		}
+	}
+
+	if gh.GetTag() == "latest" {
+		// in case of not making manifest yaml
+		return nil
+	}
+
+	return gh.makeManifest(owner)
+}
+
+func (gh GHExtension) InstallFromRelease(ctx context.Context, owner, repo, tag string) error {
+	ctx, cancel := context.WithCancel(ctx)
+	defer cancel()
+
+	log.Printf("[DEBUG] install from release: %s/%s (%s)", owner, repo, tag)
+	release, err := github.NewRelease(
+		ctx, owner, repo, tag,
+		github.WithOverwrite(),
+		github.WithWorkdir(gh.GetHome()),
+	)
+	if err != nil {
+		return err
+	}
+
+	asset, err := release.Download(ctx)
+	if err != nil {
+		return errors.Wrapf(err, "%s: failed to download", release.Name)
+	}
+
+	if err := release.Unarchive(asset); err != nil {
+		return errors.Wrapf(err, "%s: failed to unarchive", release.Name)
+	}
+
+	return nil
+}
+
+func (gh GHExtension) makeManifest(owner string) error {
+	// https://github.com/cli/cli/blob/c9a2d85793c4cef026d5bb941b3ac4121c81ae10/pkg/cmd/extension/manager.go#L424-L451
+	manifest := ghManifest{
+		Name:     gh.Name,
+		Owner:    owner,
+		Host:     "github.com",
+		Path:     gh.GetHome(),
+		Tag:      gh.GetTag(),
+		IsPinned: false,
+	}
+	bs, err := yaml.Marshal(manifest)
+	if err != nil {
+		return fmt.Errorf("failed to serialize manifest: %w", err)
+	}
+
+	manifestPath := filepath.Join(gh.GetHome(), "manifest.yml")
+	f, err := os.OpenFile(manifestPath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0600)
+	if err != nil {
+		return fmt.Errorf("failed to open manifest for writing: %w", err)
+	}
+	defer f.Close()
+
+	_, err = f.Write(bs)
+	if err != nil {
+		return fmt.Errorf("failed write manifest file: %w", err)
+	}
+	return nil
+}
diff --git a/pkg/config/gist.go b/internal/pkg/gist.go
rename from pkg/config/gist.go
rename to internal/pkg/gist.go
--- a/pkg/config/gist.go
+++ b/internal/pkg/gist.go
@@ -1,4 +1,4 @@
-package config
+package pkg
 
 import (
 	"context"
@@ -9,8 +9,9 @@ import (
 
 	git "gopkg.in/src-d/go-git.v4"
 
-	"github.com/babarot/afx/pkg/errors"
-	"github.com/babarot/afx/pkg/state"
+	"github.com/babarot/afx/internal/errors"
+	"github.com/babarot/afx/internal/runner"
+	"github.com/babarot/afx/internal/state"
 )
 
 // Gist represents
@@ -40,7 +41,7 @@ func (c Gist) Init() error {
 }
 
 // Install is
-func (c Gist) Install(ctx context.Context, status chan<- Status) error {
+func (c Gist) Install(ctx context.Context, status chan<- runner.Status) error {
 	ctx, cancel := context.WithCancel(ctx)
 	defer cancel()
 
@@ -64,7 +65,7 @@ func (c Gist) Install(ctx context.Context, status chan<- Status) error {
 		Tags: git.NoTags,
 	})
 	if err != nil {
-		status <- Status{Name: c.GetName(), Done: true, Err: true}
+		status <- runner.Status{Name: c.GetName(), Done: true, Err: true}
 		return wrapAuthError(errors.Wrapf(err, "%s: failed to clone gist repo", c.Name), c.Name)
 	}
 
@@ -76,7 +77,7 @@ func (c Gist) Install(ctx context.Context, status chan<- Status) error {
 		errs.Append(c.Command.Install(c))
 	}
 
-	status <- Status{Name: c.GetName(), Done: true, Err: errs.ErrorOrNil() != nil}
+	status <- runner.Status{Name: c.GetName(), Done: true, Err: errs.ErrorOrNil() != nil}
 	return errs.ErrorOrNil()
 }
 
@@ -110,6 +111,10 @@ func (c Gist) HasCommandBlock() bool {
 	return c.Command != nil
 }
 
+func (c Gist) HasReleaseBlock() bool {
+	return false
+}
+
 // GetPluginBlock is
 func (c Gist) GetPluginBlock() Plugin {
 	if c.HasPluginBlock() {
@@ -173,7 +178,7 @@ func (c Gist) GetResource() state.Resource {
 	return getResource(c)
 }
 
-func (c Gist) Check(ctx context.Context, status chan<- Status) error {
-	status <- Status{Name: c.GetName(), Done: true, Err: false, Message: "(gist)", NoColor: true}
+func (c Gist) Check(ctx context.Context, status chan<- runner.Status) error {
+	status <- runner.Status{Name: c.GetName(), Done: true, Err: false, Message: "(gist)", NoColor: true}
 	return nil
 }
diff --git a/internal/pkg/github.go b/internal/pkg/github.go
new file mode 100644
--- /dev/null
+++ b/internal/pkg/github.go
@@ -0,0 +1,137 @@
+package pkg
+
+import (
+	"os"
+	"path/filepath"
+
+	"github.com/babarot/afx/internal/errors"
+)
+
+// GitHub represents GitHub repository
+type GitHub struct {
+	Name string `yaml:"name" validate:"required"`
+
+	Owner       string `yaml:"owner"       validate:"required"`
+	Repo        string `yaml:"repo"        validate:"required"`
+	Description string `yaml:"description"`
+
+	Branch string        `yaml:"branch"`
+	Option *GitHubOption `yaml:"with"`
+
+	Release *GitHubRelease `yaml:"release"`
+
+	Plugin  *Plugin   `yaml:"plugin"`
+	Command *Command  `yaml:"command" validate:"required_with=Release"` // TODO: (not required Release)
+	As      *GitHubAs `yaml:"as"`
+
+	DependsOn []string `yaml:"depends-on"`
+}
+
+type GitHubAs struct {
+	GHExtension *GHExtension `yaml:"gh-extension"`
+}
+
+type GHExtension struct {
+	Name     string `yaml:"name" validate:"required,startswith=gh-"`
+	Tag      string `yaml:"tag"`
+	RenameTo string `yaml:"rename-to" validate:"startswith-gh-if-not-empty,excludesall=/"`
+}
+
+type GitHubOption struct {
+	Depth int `yaml:"depth"`
+}
+
+// GitHubRelease represents a GitHub release structure
+type GitHubRelease struct {
+	Name string `yaml:"name" validate:"required"`
+	Tag  string `yaml:"tag"`
+
+	Asset GitHubReleaseAsset `yaml:"asset"`
+}
+
+type GitHubReleaseAsset struct {
+	Filename     string            `yaml:"filename"`
+	Replacements map[string]string `yaml:"replacements"`
+}
+
+// Init runs initialization step related to GitHub packages
+func (c GitHub) Init() error {
+	var errs errors.Errors
+	if c.HasPluginBlock() {
+		errs.Append(c.Plugin.Init(c))
+	}
+	if c.HasCommandBlock() {
+		errs.Append(c.Command.Init(c))
+	}
+	return errs.ErrorOrNil()
+}
+
+// Installed returns true the GitHub package is already installed
+func (c GitHub) Installed() bool {
+	var list []bool
+
+	if c.HasPluginBlock() {
+		list = append(list, c.Plugin.Installed(c))
+	}
+
+	if c.HasCommandBlock() {
+		list = append(list, c.Command.Installed(c))
+	}
+
+	if !c.HasPluginBlock() && !c.HasCommandBlock() {
+		_, err := os.Stat(c.GetHome())
+		list = append(list, err == nil)
+	}
+
+	return allTrue(list)
+}
+
+func (c GitHub) GetReleaseTag() string {
+	if c.Release != nil {
+		return c.Release.Tag
+	}
+	return "latest"
+}
+
+func (c GitHub) HasPluginBlock() bool {
+	return c.Plugin != nil
+}
+
+func (c GitHub) HasCommandBlock() bool {
+	return c.Command != nil
+}
+
+func (c GitHub) HasReleaseBlock() bool {
+	return c.Release != nil
+}
+
+func (c GitHub) GetPluginBlock() Plugin {
+	if c.HasPluginBlock() {
+		return *c.Plugin
+	}
+	return Plugin{}
+}
+
+func (c GitHub) GetCommandBlock() Command {
+	if c.HasCommandBlock() {
+		return *c.Command
+	}
+	return Command{}
+}
+
+// GetName returns a name
+func (c GitHub) GetName() string {
+	return c.Name
+}
+
+// GetHome returns a path
+func (c GitHub) GetHome() string {
+	if c.IsGHExtension() {
+		return c.As.GHExtension.GetHome()
+	}
+	return filepath.Join(os.Getenv("HOME"), ".afx", "github.com", c.Owner, c.Repo)
+}
+
+func (c GitHub) GetDependsOn() []string {
+	return c.DependsOn
+}
diff --git a/internal/pkg/github_check.go b/internal/pkg/github_check.go
new file mode 100644
--- /dev/null
+++ b/internal/pkg/github_check.go
@@ -0,0 +1,96 @@
+package pkg
+
+import (
+	"context"
+	"fmt"
+	"log"
+
+	"github.com/Masterminds/semver"
+	"github.com/fatih/color"
+
+	"github.com/babarot/afx/internal/errors"
+	"github.com/babarot/afx/internal/github"
+	"github.com/babarot/afx/internal/runner"
+)
+
+func (c GitHub) Check(ctx context.Context, status chan<- runner.Status) error {
+	ctx, cancel := context.WithCancel(ctx)
+	defer cancel()
+
+	select {
+	case <-ctx.Done():
+		log.Println("[DEBUG] canceled")
+		return nil
+	default:
+		// go next
+	}
+
+	switch {
+	case c.Release == nil:
+		// TODO: Check git commit
+		status <- runner.Status{Name: c.GetName(), Done: true, Err: false, Message: "(github)", NoColor: true}
+		return nil
+	case c.Release != nil:
+		report, err := c.checkUpdates(ctx)
+		if err != nil {
+			err = errors.Wrapf(err, "%s: failed to check release version", c.Name)
+		}
+		status <- runner.Status{Name: c.GetName(), Done: true, Err: err != nil, Message: report.message}
+		return err
+	}
+
+	status <- runner.Status{Name: c.GetName(), Done: true, Err: false}
+	return nil
+}
+
+type report struct {
+	message string
+}
+
+func (c GitHub) checkUpdates(ctx context.Context) (report, error) {
+	ctx, cancel := context.WithCancel(ctx)
+	defer cancel()
+
+	red := color.New(color.FgRed).SprintfFunc()
+	yellow := color.New(color.FgYellow).SprintfFunc()
+
+	tag := c.Release.Tag
+	switch tag {
+	case "latest", "stable", "nightly":
+		return report{message: tag}, nil
+	case "":
+		return report{message: "(tag not set)"}, nil
+	}
+
+	release, err := github.NewRelease(
+		ctx, c.Owner, c.Repo, "latest",
+		github.WithWorkdir(c.GetHome()),
+	)
+	if err != nil {
+		return report{
+			message: fmt.Sprintf("%s %s", red("error!"), err),
+		}, err
+	}
+
+	current, err := semver.NewVersion(tag)
+	if err != nil {
+		return report{}, nil
+	}
+
+	next, err := semver.NewVersion(release.Tag)
+	if err != nil {
+		return report{}, nil
+	}
+
+	switch current.Compare(next) {
+	case -1:
+		return report{
+			message: fmt.Sprintf("%s v%s -> v%s",
+				yellow("new!"), current, next),
+		}, nil
+	case 0:
+		return report{message: "up-to-date"}, nil
+	default:
+		return report{}, errors.New("invalid version comparison")
+	}
+}
diff --git a/internal/pkg/github_install.go b/internal/pkg/github_install.go
new file mode 100644
--- /dev/null
+++ b/internal/pkg/github_install.go
@@ -0,0 +1,249 @@
+package pkg
+
+import (
+	"context"
+	stderrors "errors"
+	"fmt"
+	"io"
+	"log"
+	"os"
+
+	git "gopkg.in/src-d/go-git.v4"
+	"gopkg.in/src-d/go-git.v4/config"
+	"gopkg.in/src-d/go-git.v4/plumbing"
+
+	"github.com/babarot/afx/internal/data"
+	"github.com/babarot/afx/internal/errors"
+	"github.com/babarot/afx/internal/github"
+	"github.com/babarot/afx/internal/logging"
+	"github.com/babarot/afx/internal/runner"
+	"github.com/babarot/afx/internal/state"
+	"github.com/babarot/afx/internal/templates"
+)
+
+// Clone runs git clone
+func (c GitHub) Clone(ctx context.Context) error {
+	writer := io.Discard
+	if logging.IsTrace() {
+		writer = os.Stdout
+	}
+
+	var opt GitHubOption
+	if c.Option != nil {
+		opt = *c.Option
+	}
+
+	var r *git.Repository
+	_, err := os.Stat(c.GetHome())
+	switch {
+	case os.IsNotExist(err):
+		r, err = git.PlainCloneContext(ctx, c.GetHome(), false, &git.CloneOptions{
+			URL:      fmt.Sprintf("https://github.com/%s/%s", c.Owner, c.Repo),
+			Auth:     getGitAuth(),
+			Tags:     git.NoTags,
+			Depth:    opt.Depth,
+			Progress: writer,
+		})
+		if err != nil {
+			return wrapAuthError(errors.Wrapf(err, "%s: failed to clone repository", c.GetName()), c.GetName())
+		}
+	default:
+		r, err = git.PlainOpen(c.GetHome())
+		if err != nil {
+			return errors.Wrapf(err, "%s: failed to open repository", c.GetName())
+		}
+	}
+
+	w, err := r.Worktree()
+	if err != nil {
+		return errors.Wrapf(err, "%s: failed to get worktree", c.GetName())
+	}
+
+	if c.Branch != "" {
+		var err error
+		err = r.FetchContext(ctx, &git.FetchOptions{
+			RemoteName: "origin",
+			Auth:       getGitAuth(),
+			RefSpecs: []config.RefSpec{
+				config.RefSpec(fmt.Sprintf("+%s:%s",
+					plumbing.NewBranchReferenceName(c.Branch),
+					plumbing.NewBranchReferenceName(c.Branch),
+				)),
+			},
+			Depth:    opt.Depth,
+			Force:    true,
+			Tags:     git.NoTags,
+			Progress: writer,
+		})
+		if err != nil && !stderrors.Is(err, git.NoErrAlreadyUpToDate) {
+			return errors.Wrapf(err, "%s: failed to fetch repository", c.Branch)
+		}
+		err = w.Checkout(&git.CheckoutOptions{
+			Branch: plumbing.ReferenceName("refs/heads/" + c.Branch),
+			Force:  true,
+		})
+		if err != nil {
+			return errors.Wrapf(err, "%s: failed to checkout", c.Branch)
+		}
+	}
+
+	return nil
+}
+
+// Install installs from GitHub repository with git clone command
+func (c GitHub) Install(ctx context.Context, status chan<- runner.Status) error {
+	ctx, cancel := context.WithCancel(ctx)
+	defer cancel()
+
+	select {
+	case <-ctx.Done():
+		log.Println("[DEBUG] canceled")
+		return nil
+	default:
+		// Go installing step!
+	}
+
+	switch {
+	case c.Release == nil:
+		err := c.Clone(ctx)
+		if err != nil {
+			err = errors.Wrapf(err, "%s: failed to clone repo", c.Name)
+			status <- runner.Status{Name: c.GetName(), Done: true, Err: true}
+			return err
+		}
+	case c.Release != nil:
+		err := c.InstallFromRelease(ctx)
+		if err != nil {
+			err = errors.Wrapf(err, "%s: failed to get from release", c.Name)
+			status <- runner.Status{Name: c.GetName(), Done: true, Err: true}
+			return err
+		}
+	}
+
+	var errs errors.Errors
+
+	if c.IsGHExtension() {
+		gh := c.As.GHExtension
+		err := gh.Install(ctx, c.Owner, c.Repo, gh.GetTag())
+		if err != nil {
+			err = errors.Wrapf(err, "%s: failed to get from release", c.Name)
+			status <- runner.Status{Name: c.GetName(), Done: true, Err: true}
+			return err
+		}
+	}
+
+	if c.HasPluginBlock() {
+		errs.Append(c.Plugin.Install(c))
+	}
+	if c.HasCommandBlock() {
+		errs.Append(c.Command.Install(c))
+	}
+
+	status <- runner.Status{Name: c.GetName(), Done: true, Err: errs.ErrorOrNil() != nil}
+	return errs.ErrorOrNil()
+}
+
+// InstallFromRelease runs install from GitHub release, from not repository
+func (c GitHub) InstallFromRelease(ctx context.Context) error {
+	ctx, cancel := context.WithCancel(ctx)
+	defer cancel()
+
+	owner, repo, tag := c.Owner, c.Repo, c.GetReleaseTag()
+	log.Printf("[DEBUG] install from release: %s/%s (%s)", owner, repo, tag)
+
+	release, err := github.NewRelease(
+		ctx, owner, repo, tag,
+		github.WithWorkdir(c.GetHome()),
+		github.WithFilter(func(filename string) github.FilterFunc {
+			if filename == "" {
+				// cancel filtering
+				return nil
+			}
+			return func(assets github.Assets) *github.Asset {
+				for _, asset := range assets {
+					if asset.Name == filename {
+						return &asset
+					}
+				}
+				return nil
+			}
+		}(c.templateFilename())),
+	)
+	if err != nil {
+		return err
+	}
+
+	asset, err := release.Download(ctx)
+	if err != nil {
+		return errors.Wrapf(err, "%s: failed to download", release.Name)
+	}
+
+	if err := release.Unarchive(asset); err != nil {
+		return errors.Wrapf(err, "%s: failed to unarchive", release.Name)
+	}
+
+	return nil
+}
+
+func (c GitHub) templateFilename() string {
+	release := c.Release
+	if release == nil {
+		return ""
+	}
+
+	filename := release.Asset.Filename
+	replacements := release.Asset.Replacements
+
+	if filename == "" {
+		// no filename specified
+		return ""
+	}
+
+	log.Printf("[DEBUG] asset: templating filename from %q", filename)
+
+	data := data.New(
+		data.WithPackage(c),
+		data.WithRelease(data.Release{
+			Name: release.Name,
+			Tag:  release.Tag,
+		}),
+	)
+
+	filename, err := templates.New(data).
+		Replace(replacements).
+		Apply(filename)
+	if err != nil {
+		log.Printf("[WARN] asset: failed to template filename: %q", filename)
+	}
+
+	log.Printf("[DEBUG] asset: templated filename: -> %q", filename)
+	return filename
+}
+
+func (c GitHub) Uninstall(ctx context.Context) error {
+	var errs errors.Errors
+
+	delete := func(f string, errs *errors.Errors) {
+		err := os.RemoveAll(f)
+		if err != nil {
+			errs.Append(err)
+			return
+		}
+		log.Printf("[INFO] Delete %s\n", f)
+	}
+
+	if c.HasCommandBlock() {
+		links, _ := c.Command.GetLink(c)
+		for _, link := range links {
+			delete(link.From, &errs)
+			delete(link.To, &errs)
+		}
+	}
+
+	delete(c.GetHome(), &errs)
+	return errs.ErrorOrNil()
+}
+
+func (c GitHub) GetResource() state.Resource {
+	return getResource(c)
+}
diff --git a/pkg/config/http.go b/internal/pkg/http.go
rename from pkg/config/http.go
rename to internal/pkg/http.go
--- a/pkg/config/http.go
+++ b/internal/pkg/http.go
@@ -1,4 +1,4 @@
-package config
+package pkg
 
 import (
 	"context"
@@ -12,10 +12,11 @@ import (
 
 	"github.com/mholt/archiver"
 
-	"github.com/babarot/afx/pkg/data"
-	"github.com/babarot/afx/pkg/errors"
-	"github.com/babarot/afx/pkg/state"
-	"github.com/babarot/afx/pkg/templates"
+	"github.com/babarot/afx/internal/data"
+	"github.com/babarot/afx/internal/errors"
+	"github.com/babarot/afx/internal/runner"
+	"github.com/babarot/afx/internal/state"
+	"github.com/babarot/afx/internal/templates"
 )
 
 // HTTP represents
@@ -94,7 +95,7 @@ func (c HTTP) call(ctx context.Context) error {
 }
 
 // Install is
-func (c HTTP) Install(ctx context.Context, status chan<- Status) error {
+func (c HTTP) Install(ctx context.Context, status chan<- runner.Status) error {
 	select {
 	case <-ctx.Done():
 		log.Println("[DEBUG] canceled")
@@ -108,7 +109,7 @@ func (c HTTP) Install(ctx context.Context, status chan<- Status) error {
 
 	if err := c.call(ctx); err != nil {
 		err = errors.Wrapf(err, "%s: failed to make HTTP request", c.Name)
-		status <- Status{Name: c.GetName(), Done: true, Err: true}
+		status <- runner.Status{Name: c.GetName(), Done: true, Err: true}
 		return err
 	}
 
@@ -120,7 +121,7 @@ func (c HTTP) Install(ctx context.Context, status chan<- Status) error {
 		errs.Append(c.Command.Install(c))
 	}
 
-	status <- Status{Name: c.GetName(), Done: true, Err: errs.ErrorOrNil() != nil}
+	status <- runner.Status{Name: c.GetName(), Done: true, Err: errs.ErrorOrNil() != nil}
 	return errs.ErrorOrNil()
 }
 
@@ -163,6 +164,10 @@ func (c HTTP) HasCommandBlock() bool {
 	return c.Command != nil
 }
 
+func (c HTTP) HasReleaseBlock() bool {
+	return false
+}
+
 // GetPluginBlock is
 func (c HTTP) GetPluginBlock() Plugin {
 	if c.HasPluginBlock() {
@@ -238,7 +243,7 @@ func (c *HTTP) ParseURL() {
 	}
 }
 
-func (c HTTP) Check(ctx context.Context, status chan<- Status) error {
-	status <- Status{Name: c.GetName(), Done: true, Err: false, Message: "(http)", NoColor: true}
+func (c HTTP) Check(ctx context.Context, status chan<- runner.Status) error {
+	status <- runner.Status{Name: c.GetName(), Done: true, Err: false, Message: "(http)", NoColor: true}
 	return nil
 }
diff --git a/pkg/config/local.go b/internal/pkg/local.go
rename from pkg/config/local.go
rename to internal/pkg/local.go
--- a/pkg/config/local.go
+++ b/internal/pkg/local.go
@@ -1,11 +1,13 @@
-package config
+package pkg
 
 import (
 	"context"
 	"os"
 
-	"github.com/babarot/afx/pkg/errors"
-	"github.com/babarot/afx/pkg/state"
+	"github.com/babarot/afx/internal/errors"
+	pathutil "github.com/babarot/afx/internal/helpers/path"
+	"github.com/babarot/afx/internal/runner"
+	"github.com/babarot/afx/internal/state"
 )
 
 // Local represents
@@ -34,7 +36,7 @@ func (c Local) Init() error {
 }
 
 // Install is
-func (c Local) Install(ctx context.Context, status chan<- Status) error {
+func (c Local) Install(ctx context.Context, status chan<- runner.Status) error {
 	return nil
 }
 
@@ -53,6 +55,10 @@ func (c Local) HasCommandBlock() bool {
 	return c.Command != nil
 }
 
+func (c Local) HasReleaseBlock() bool {
+	return false
+}
+
 // GetPluginBlock is
 func (c Local) GetPluginBlock() Plugin {
 	if c.HasPluginBlock() {
@@ -81,7 +87,7 @@ func (c Local) GetName() string {
 
 // GetHome returns a path
 func (c Local) GetHome() string {
-	return expandTilda(os.ExpandEnv(c.Directory))
+	return pathutil.ExpandTilda(os.ExpandEnv(c.Directory))
 }
 
 func (c Local) GetDependsOn() []string {
@@ -92,7 +98,7 @@ func (c Local) GetResource() state.Resource {
 	return getResource(c)
 }
 
-func (c Local) Check(ctx context.Context, status chan<- Status) error {
-	status <- Status{Name: c.GetName(), Done: true, Err: false, Message: "(local)", NoColor: true}
+func (c Local) Check(ctx context.Context, status chan<- runner.Status) error {
+	status <- runner.Status{Name: c.GetName(), Done: true, Err: false, Message: "(local)", NoColor: true}
 	return nil
 }
diff --git a/pkg/config/package.go b/internal/pkg/package.go
rename from pkg/config/package.go
rename to internal/pkg/package.go
--- a/pkg/config/package.go
+++ b/internal/pkg/package.go
@@ -1,19 +1,20 @@
-package config
+package pkg
 
 import (
 	"context"
 
 	"github.com/mattn/go-shellwords"
 
-	"github.com/babarot/afx/pkg/state"
+	"github.com/babarot/afx/internal/runner"
+	"github.com/babarot/afx/internal/state"
 )
 
 // Installer is an interface related to installation of a package
 type Installer interface {
-	Install(context.Context, chan<- Status) error
+	Install(context.Context, chan<- runner.Status) error
 	Uninstall(context.Context) error
 	Installed() bool
-	Check(context.Context, chan<- Status) error
+	Check(context.Context, chan<- runner.Status) error
 }
 
 // Loader is an interface related to initialize a package
@@ -28,6 +29,7 @@ type Handler interface {
 
 	HasPluginBlock() bool
 	HasCommandBlock() bool
+	HasReleaseBlock() bool
 	GetPluginBlock() Plugin
 	GetCommandBlock() Command
 
@@ -45,11 +47,7 @@ type Package interface {
 // HasGitHubReleaseBlock returns true if release block is included in one package at least
 func HasGitHubReleaseBlock(pkgs []Package) bool {
 	for _, pkg := range pkgs {
-		github, ok := pkg.(*GitHub)
-		if !ok {
-			continue
-		}
-		if github.Release != nil {
+		if pkg.HasReleaseBlock() {
 			return true
 		}
 	}
diff --git a/pkg/config/plugin.go b/internal/pkg/plugin.go
rename from pkg/config/plugin.go
rename to internal/pkg/plugin.go
--- a/pkg/config/plugin.go
+++ b/internal/pkg/plugin.go
@@ -1,4 +1,4 @@
-package config
+package pkg
 
 import (
 	"context"
@@ -11,6 +11,8 @@ import (
 
 	"github.com/goccy/go-yaml"
 	"github.com/mattn/go-zglob"
+
+	pathutil "github.com/babarot/afx/internal/helpers/path"
 )
 
 // Plugin is
@@ -47,7 +49,7 @@ func (p *Plugin) UnmarshalYAML(b []byte) error {
 
 	var sources []string
 	for _, source := range tmp.Sources {
-		sources = append(sources, expandTilda(os.ExpandEnv(source)))
+		sources = append(sources, pathutil.ExpandTilda(os.ExpandEnv(source)))
 	}
 
 	p.Sources = sources
@@ -122,7 +124,7 @@ func (p Plugin) Init(pkg Package) error {
 		switch k {
 		case "PATH":
 			// avoid overwriting PATH
-			v = fmt.Sprintf("$PATH:%s", expandTilda(v))
+			v = fmt.Sprintf("$PATH:%s", pathutil.ExpandTilda(v))
 		default:
 			// through
 		}
diff --git a/internal/pkg/resource.go b/internal/pkg/resource.go
new file mode 100644
--- /dev/null
+++ b/internal/pkg/resource.go
@@ -0,0 +1,70 @@
+package pkg
+
+import (
+	"fmt"
+
+	"github.com/babarot/afx/internal/state"
+)
+
+func getResource(pkg Package) state.Resource {
+	var paths []string
+
+	// repository existence is also one of the path resource
+	paths = append(paths, pkg.GetHome())
+
+	if pkg.HasPluginBlock() {
+		plugin := pkg.GetPluginBlock()
+		paths = append(paths, plugin.GetSources(pkg)...)
+	}
+
+	if pkg.HasCommandBlock() {
+		command := pkg.GetCommandBlock()
+		links, _ := command.GetLink(pkg)
+		for _, link := range links {
+			paths = append(paths, link.From)
+			paths = append(paths, link.To)
+		}
+	}
+
+	var ty string
+	var version string
+	var id string
+
+	switch pkg := pkg.(type) {
+	case GitHub:
+		ty = "GitHub"
+		if pkg.HasReleaseBlock() {
+			ty = "GitHub Release"
+			version = pkg.Release.Tag
+		}
+		id = fmt.Sprintf("github.com/%s/%s", pkg.Owner, pkg.Repo)
+		if pkg.HasReleaseBlock() {
+			id = fmt.Sprintf("github.com/release/%s/%s", pkg.Owner, pkg.Repo)
+		}
+		if pkg.IsGHExtension() {
+			ty = "GitHub (gh extension)"
+			gh := pkg.As.GHExtension
+			paths = append(paths, gh.GetHome())
+		}
+	case Gist:
+		ty = "Gist"
+		id = fmt.Sprintf("gist.github.com/%s/%s", pkg.Owner, pkg.ID)
+	case Local:
+		ty = "Local"
+		id = fmt.Sprintf("local/%s", pkg.Directory)
+	case HTTP:
+		ty = "HTTP"
+		id = pkg.URL
+	default:
+		ty = "Unknown"
+	}
+
+	return state.Resource{
+		ID:      id,
+		Name:    pkg.GetName(),
+		Home:    pkg.GetHome(),
+		Type:    ty,
+		Version: version,
+		Paths:   paths,
+	}
+}
diff --git a/pkg/config/util.go b/internal/pkg/util.go
rename from pkg/config/util.go
rename to internal/pkg/util.go
--- a/pkg/config/util.go
+++ b/internal/pkg/util.go
@@ -1,16 +1,14 @@
-package config
+package pkg
 
 import (
 	"log"
 	"os"
-	"path/filepath"
-	"runtime"
 	"strings"
 
 	"github.com/cli/go-gh/v2/pkg/auth"
 	githttp "gopkg.in/src-d/go-git.v4/plumbing/transport/http"
 
-	"github.com/babarot/afx/pkg/errors"
+	"github.com/babarot/afx/internal/errors"
 )
 
 func allTrue(list []bool) bool {
@@ -25,29 +23,6 @@ func allTrue(list []bool) bool {
 	return true
 }
 
-func expandTilda(path string) string {
-	if !strings.HasPrefix(path, "~") {
-		return path
-	}
-
-	home := ""
-	switch runtime.GOOS {
-	case "windows":
-		home = filepath.Join(os.Getenv("HomeDrive"), os.Getenv("HomePath"))
-		if home == "" {
-			home = os.Getenv("UserProfile")
-		}
-	default:
-		home = os.Getenv("HOME")
-	}
-
-	if home == "" {
-		return path
-	}
-
-	return home + path[1:]
-}
-
 // getGitAuth returns BasicAuth for git operations.
 // It first tries to get token from gh auth (gh CLI), then falls back to GITHUB_TOKEN.
 // Returns nil if no token is found, allowing public repository access.
diff --git a/pkg/printers/printers.go b/internal/printers/printers.go
rename from pkg/printers/printers.go
rename to internal/printers/printers.go
--- a/pkg/printers/printers.go
+++ b/internal/printers/printers.go

diff --git a/pkg/printers/terminal.go b/internal/printers/terminal.go
rename from pkg/printers/terminal.go
rename to internal/printers/terminal.go
--- a/pkg/printers/terminal.go
+++ b/internal/printers/terminal.go

diff --git a/pkg/config/status.go b/internal/runner/progress.go
rename from pkg/config/status.go
rename to internal/runner/progress.go
--- a/pkg/config/status.go
+++ b/internal/runner/progress.go
@@ -1,4 +1,4 @@
-package config
+package runner
 
 import (
 	"fmt"
@@ -12,10 +12,12 @@ import (
 	"golang.org/x/term"
 )
 
+// Progress tracks the completion status of multiple packages.
 type Progress struct {
 	Status map[string]Status
 }
 
+// Status represents the completion status of a single package operation.
 type Status struct {
 	Name    string
 	Done    bool
@@ -24,11 +26,12 @@ type Status struct {
 	NoColor bool
 }
 
-func NewProgress(pkgs []Package) Progress {
+// NewProgress creates a Progress tracker for the given package names.
+func NewProgress(names []string) Progress {
 	status := make(map[string]Status)
-	for _, pkg := range pkgs {
-		status[pkg.GetName()] = Status{
-			Name:    pkg.GetName(),
+	for _, name := range names {
+		status[name] = Status{
+			Name:    name,
 			Done:    false,
 			Err:     false,
 			Message: "",
@@ -37,6 +40,7 @@ func NewProgress(pkgs []Package) Progress {
 	return Progress{Status: status}
 }
 
+// Print listens on the completion channel and prints progress to stdout.
 func (p Progress) Print(completion chan Status) {
 	green := color.New(color.FgGreen).SprintFunc()
 	red := color.New(color.FgRed).SprintFunc()
diff --git a/internal/runner/runner.go b/internal/runner/runner.go
new file mode 100644
--- /dev/null
+++ b/internal/runner/runner.go
@@ -0,0 +1,79 @@
+package runner
+
+import (
+	"context"
+	"log"
+	"os"
+	"os/signal"
+
+	"golang.org/x/sync/errgroup"
+
+	"github.com/babarot/afx/internal/errors"
+)
+
+// Package is the minimal interface needed by the runner.
+type Package interface {
+	GetName() string
+}
+
+// TaskFunc is the function executed for each package in parallel.
+// It receives the context and the completion channel for progress reporting.
+type TaskFunc func(ctx context.Context, completion chan<- Status) error
+
+// Result holds the outcome of a single package execution.
+type Result struct {
+	Name  string
+	Error error
+}
+
+// Execute runs taskFn for each package in parallel with progress reporting.
+// It handles signal interruption, concurrency limiting, and error aggregation.
+func Execute(pkgs []Package, taskFn func(pkg Package) TaskFunc) error {
+	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
+	defer stop()
+
+	names := make([]string, len(pkgs))
+	for i, p := range pkgs {
+		names[i] = p.GetName()
+	}
+	progress := NewProgress(names)
+	completion := make(chan Status)
+	limit := make(chan struct{}, 16)
+	results := make(chan Result)
+
+	go func() {
+		progress.Print(completion)
+	}()
+
+	eg := errgroup.Group{}
+	for _, pkg := range pkgs {
+		fn := taskFn(pkg)
+		eg.Go(func() error {
+			limit <- struct{}{}
+			defer func() { <-limit }()
+			err := fn(ctx, completion)
+			select {
+			case results <- Result{Name: pkg.GetName(), Error: err}:
+				return nil
+			case <-ctx.Done():
+				return ctx.Err()
+			}
+		})
+	}
+
+	go func() {
+		_ = eg.Wait()
+		close(results)
+	}()
+
+	var exit errors.Errors
+	for result := range results {
+		exit.Append(result.Error)
+	}
+	if err := eg.Wait(); err != nil {
+		log.Printf("[ERROR] execution failed: %s", err)
+		exit.Append(err)
+	}
+
+	return exit.ErrorOrNil()
+}
diff --git a/pkg/state/state.go b/internal/state/state.go
rename from pkg/state/state.go
rename to internal/state/state.go
--- a/pkg/state/state.go
+++ b/internal/state/state.go

diff --git a/pkg/templates/templates.go b/internal/templates/templates.go
rename from pkg/templates/templates.go
rename to internal/templates/templates.go
--- a/pkg/templates/templates.go
+++ b/internal/templates/templates.go
@@ -7,7 +7,7 @@ import (
 	"text/template"
 	"time"
 
-	"github.com/babarot/afx/pkg/data"
+	"github.com/babarot/afx/internal/data"
 )
 
 // Template holds data that can be applied to a template string.
diff --git a/pkg/update/update.go b/internal/update/update.go
rename from pkg/update/update.go
rename to internal/update/update.go
--- a/pkg/update/update.go
+++ b/internal/update/update.go
@@ -14,7 +14,7 @@ import (
 
 	"github.com/hashicorp/go-version"
 
-	"github.com/babarot/afx/pkg/github"
+	"github.com/babarot/afx/internal/github"
 )
 
 // refer: github.com/cli/cli/tree/<hash>/internal/update
diff --git a/pkg/config/github.go b/pkg/config/github.go
deleted file mode 100644
--- a/pkg/config/github.go
+++ /dev/null
@@ -1,587 +0,0 @@
-package config
-
-import (
-	"context"
-	stderrors "errors"
-	"fmt"
-	"io"
-	"log"
-	"net/http"
-	"os"
-	"path/filepath"
-	"strings"
-
-	"github.com/Masterminds/semver"
-	"github.com/fatih/color"
-	"github.com/go-playground/validator/v10"
-	git "gopkg.in/src-d/go-git.v4"
-	"gopkg.in/src-d/go-git.v4/config"
-	"gopkg.in/src-d/go-git.v4/plumbing"
-	"gopkg.in/yaml.v2"
-
-	"github.com/babarot/afx/pkg/data"
-	"github.com/babarot/afx/pkg/errors"
-	"github.com/babarot/afx/pkg/github"
-	"github.com/babarot/afx/pkg/logging"
-	"github.com/babarot/afx/pkg/state"
-	"github.com/babarot/afx/pkg/templates"
-)
-
-// GitHub represents GitHub repository
-type GitHub struct {
-	Name string `yaml:"name" validate:"required"`
-
-	Owner       string `yaml:"owner"       validate:"required"`
-	Repo        string `yaml:"repo"        validate:"required"`
-	Description string `yaml:"description"`
-
-	Branch string        `yaml:"branch"`
-	Option *GitHubOption `yaml:"with"`
-
-	Release *GitHubRelease `yaml:"release"`
-
-	Plugin  *Plugin   `yaml:"plugin"`
-	Command *Command  `yaml:"command" validate:"required_with=Release"` // TODO: (not required Release)
-	As      *GitHubAs `yaml:"as"`
-
-	DependsOn []string `yaml:"depends-on"`
-}
-
-type GitHubAs struct {
-	GHExtension *GHExtension `yaml:"gh-extension"`
-}
-
-type GHExtension struct {
-	Name     string `yaml:"name" validate:"required,startswith=gh-"`
-	Tag      string `yaml:"tag"`
-	RenameTo string `yaml:"rename-to" validate:"startswith-gh-if-not-empty,excludesall=/"`
-}
-
-type GitHubOption struct {
-	Depth int `yaml:"depth"`
-}
-
-// GitHubRelease represents a GitHub release structure
-type GitHubRelease struct {
-	Name string `yaml:"name" validate:"required"`
-	Tag  string `yaml:"tag"`
-
-	Asset GitHubReleaseAsset `yaml:"asset"`
-}
-
-type GitHubReleaseAsset struct {
-	Filename     string            `yaml:"filename"`
-	Replacements map[string]string `yaml:"replacements"`
-}
-
-// Init runs initialization step related to GitHub packages
-func (c GitHub) Init() error {
-	var errs errors.Errors
-	if c.HasPluginBlock() {
-		errs.Append(c.Plugin.Init(c))
-	}
-	if c.HasCommandBlock() {
-		errs.Append(c.Command.Init(c))
-	}
-	return errs.ErrorOrNil()
-}
-
-// Clone runs git clone
-func (c GitHub) Clone(ctx context.Context) error {
-	writer := io.Discard
-	if logging.IsTrace() {
-		writer = os.Stdout
-	}
-
-	var opt GitHubOption
-	if c.Option != nil {
-		opt = *c.Option
-	}
-
-	var r *git.Repository
-	_, err := os.Stat(c.GetHome())
-	switch {
-	case os.IsNotExist(err):
-		r, err = git.PlainCloneContext(ctx, c.GetHome(), false, &git.CloneOptions{
-			URL:      fmt.Sprintf("https://github.com/%s/%s", c.Owner, c.Repo),
-			Auth:     getGitAuth(),
-			Tags:     git.NoTags,
-			Depth:    opt.Depth,
-			Progress: writer,
-		})
-		if err != nil {
-			return wrapAuthError(errors.Wrapf(err, "%s: failed to clone repository", c.GetName()), c.GetName())
-		}
-	default:
-		r, err = git.PlainOpen(c.GetHome())
-		if err != nil {
-			return errors.Wrapf(err, "%s: failed to open repository", c.GetName())
-		}
-	}
-
-	w, err := r.Worktree()
-	if err != nil {
-		return errors.Wrapf(err, "%s: failed to get worktree", c.GetName())
-	}
-
-	if c.Branch != "" {
-		var err error
-		err = r.FetchContext(ctx, &git.FetchOptions{
-			RemoteName: "origin",
-			Auth:       getGitAuth(),
-			RefSpecs: []config.RefSpec{
-				config.RefSpec(fmt.Sprintf("+%s:%s",
-					plumbing.NewBranchReferenceName(c.Branch),
-					plumbing.NewBranchReferenceName(c.Branch),
-				)),
-			},
-			Depth:    opt.Depth,
-			Force:    true,
-			Tags:     git.NoTags,
-			Progress: writer,
-		})
-		if err != nil && !stderrors.Is(err, git.NoErrAlreadyUpToDate) {
-			return errors.Wrapf(err, "%s: failed to fetch repository", c.Branch)
-		}
-		err = w.Checkout(&git.CheckoutOptions{
-			Branch: plumbing.ReferenceName("refs/heads/" + c.Branch),
-			Force:  true,
-		})
-		if err != nil {
-			return errors.Wrapf(err, "%s: failed to checkout", c.Branch)
-		}
-	}
-
-	return nil
-}
-
-// Install installs from GitHub repository with git clone command
-func (c GitHub) Install(ctx context.Context, status chan<- Status) error {
-	ctx, cancel := context.WithCancel(ctx)
-	defer cancel()
-
-	select {
-	case <-ctx.Done():
-		log.Println("[DEBUG] canceled")
-		return nil
-	default:
-		// Go installing step!
-	}
-
-	switch {
-	case c.Release == nil:
-		err := c.Clone(ctx)
-		if err != nil {
-			err = errors.Wrapf(err, "%s: failed to clone repo", c.Name)
-			status <- Status{Name: c.GetName(), Done: true, Err: true}
-			return err
-		}
-	case c.Release != nil:
-		err := c.InstallFromRelease(ctx)
-		if err != nil {
-			err = errors.Wrapf(err, "%s: failed to get from release", c.Name)
-			status <- Status{Name: c.GetName(), Done: true, Err: true}
-			return err
-		}
-	}
-
-	var errs errors.Errors
-
-	if c.IsGHExtension() {
-		gh := c.As.GHExtension
-		err := gh.Install(ctx, c.Owner, c.Repo, gh.GetTag())
-		if err != nil {
-			err = errors.Wrapf(err, "%s: failed to get from release", c.Name)
-			status <- Status{Name: c.GetName(), Done: true, Err: true}
-			return err
-		}
-	}
-
-	if c.HasPluginBlock() {
-		errs.Append(c.Plugin.Install(c))
-	}
-	if c.HasCommandBlock() {
-		errs.Append(c.Command.Install(c))
-	}
-
-	status <- Status{Name: c.GetName(), Done: true, Err: errs.ErrorOrNil() != nil}
-	return errs.ErrorOrNil()
-}
-
-// Installed returns true the GitHub package is already installed
-func (c GitHub) Installed() bool {
-	var list []bool
-
-	if c.HasPluginBlock() {
-		list = append(list, c.Plugin.Installed(c))
-	}
-
-	if c.HasCommandBlock() {
-		list = append(list, c.Command.Installed(c))
-	}
-
-	if !c.HasPluginBlock() && !c.HasCommandBlock() {
-		_, err := os.Stat(c.GetHome())
-		list = append(list, err == nil)
-	}
-
-	return allTrue(list)
-}
-
-func (c GitHub) GetReleaseTag() string {
-	if c.Release != nil {
-		return c.Release.Tag
-	}
-	return "latest"
-}
-
-// InstallFromRelease runs install from GitHub release, from not repository
-func (c GitHub) InstallFromRelease(ctx context.Context) error {
-	ctx, cancel := context.WithCancel(ctx)
-	defer cancel()
-
-	owner, repo, tag := c.Owner, c.Repo, c.GetReleaseTag()
-	log.Printf("[DEBUG] install from release: %s/%s (%s)", owner, repo, tag)
-
-	release, err := github.NewRelease(
-		ctx, owner, repo, tag,
-		github.WithWorkdir(c.GetHome()),
-		github.WithFilter(func(filename string) github.FilterFunc {
-			if filename == "" {
-				// cancel filtering
-				return nil
-			}
-			return func(assets github.Assets) *github.Asset {
-				for _, asset := range assets {
-					if asset.Name == filename {
-						return &asset
-					}
-				}
-				return nil
-			}
-		}(c.templateFilename())),
-	)
-	if err != nil {
-		return err
-	}
-
-	asset, err := release.Download(ctx)
-	if err != nil {
-		return errors.Wrapf(err, "%s: failed to download", release.Name)
-	}
-
-	if err := release.Unarchive(asset); err != nil {
-		return errors.Wrapf(err, "%s: failed to unarchive", release.Name)
-	}
-
-	return nil
-}
-
-func (c GitHub) templateFilename() string {
-	release := c.Release
-	if release == nil {
-		return ""
-	}
-
-	filename := release.Asset.Filename
-	replacements := release.Asset.Replacements
-
-	if filename == "" {
-		// no filename specified
-		return ""
-	}
-
-	log.Printf("[DEBUG] asset: templating filename from %q", filename)
-
-	data := data.New(
-		data.WithPackage(c),
-		data.WithRelease(data.Release{
-			Name: release.Name,
-			Tag:  release.Tag,
-		}),
-	)
-
-	filename, err := templates.New(data).
-		Replace(replacements).
-		Apply(filename)
-	if err != nil {
-		log.Printf("[WARN] asset: failed to template filename: %q", filename)
-	}
-
-	log.Printf("[DEBUG] asset: templated filename: -> %q", filename)
-	return filename
-}
-
-func (c GitHub) HasPluginBlock() bool {
-	return c.Plugin != nil
-}
-
-func (c GitHub) HasCommandBlock() bool {
-	return c.Command != nil
-}
-
-func (c GitHub) HasReleaseBlock() bool {
-	return c.Release != nil
-}
-
-func (c GitHub) GetPluginBlock() Plugin {
-	if c.HasPluginBlock() {
-		return *c.Plugin
-	}
-	return Plugin{}
-}
-
-func (c GitHub) GetCommandBlock() Command {
-	if c.HasCommandBlock() {
-		return *c.Command
-	}
-	return Command{}
-}
-
-func (c GitHub) Uninstall(ctx context.Context) error {
-	var errs errors.Errors
-
-	delete := func(f string, errs *errors.Errors) {
-		err := os.RemoveAll(f)
-		if err != nil {
-			errs.Append(err)
-			return
-		}
-		log.Printf("[INFO] Delete %s\n", f)
-	}
-
-	if c.HasCommandBlock() {
-		links, _ := c.Command.GetLink(c)
-		for _, link := range links {
-			delete(link.From, &errs)
-			delete(link.To, &errs)
-		}
-	}
-
-	delete(c.GetHome(), &errs)
-	return errs.ErrorOrNil()
-}
-
-// GetName returns a name
-func (c GitHub) GetName() string {
-	return c.Name
-}
-
-// GetHome returns a path
-func (c GitHub) GetHome() string {
-	if c.IsGHExtension() {
-		return c.As.GHExtension.GetHome()
-	}
-	return filepath.Join(os.Getenv("HOME"), ".afx", "github.com", c.Owner, c.Repo)
-}
-
-func (c GitHub) GetDependsOn() []string {
-	return c.DependsOn
-}
-
-func (c GitHub) GetResource() state.Resource {
-	return getResource(c)
-}
-
-func (c GitHub) Check(ctx context.Context, status chan<- Status) error {
-	ctx, cancel := context.WithCancel(ctx)
-	defer cancel()
-
-	select {
-	case <-ctx.Done():
-		log.Println("[DEBUG] canceled")
-		return nil
-	default:
-		// go next
-	}
-
-	switch {
-	case c.Release == nil:
-		// TODO: Check git commit
-		status <- Status{Name: c.GetName(), Done: true, Err: false, Message: "(github)", NoColor: true}
-		return nil
-	case c.Release != nil:
-		report, err := c.checkUpdates(ctx)
-		if err != nil {
-			err = errors.Wrapf(err, "%s: failed to check release version", c.Name)
-		}
-		status <- Status{Name: c.GetName(), Done: true, Err: err != nil, Message: report.message}
-		return err
-	}
-
-	status <- Status{Name: c.GetName(), Done: true, Err: false}
-	return nil
-}
-
-type report struct {
-	message string
-}
-
-func (c GitHub) checkUpdates(ctx context.Context) (report, error) {
-	ctx, cancel := context.WithCancel(ctx)
-	defer cancel()
-
-	red := color.New(color.FgRed).SprintfFunc()
-	yellow := color.New(color.FgYellow).SprintfFunc()
-
-	tag := c.Release.Tag
-	switch tag {
-	case "latest", "stable", "nightly":
-		return report{message: tag}, nil
-	case "":
-		return report{message: "(tag not set)"}, nil
-	}
-
-	release, err := github.NewRelease(
-		ctx, c.Owner, c.Repo, "latest",
-		github.WithWorkdir(c.GetHome()),
-	)
-	if err != nil {
-		return report{
-			message: fmt.Sprintf("%s %s", red("error!"), err),
-		}, err
-	}
-
-	current, err := semver.NewVersion(tag)
-	if err != nil {
-		return report{}, nil
-	}
-
-	next, err := semver.NewVersion(release.Tag)
-	if err != nil {
-		return report{}, nil
-	}
-
-	switch current.Compare(next) {
-	case -1:
-		return report{
-			message: fmt.Sprintf("%s v%s -> v%s",
-				yellow("new!"), current, next),
-		}, nil
-	case 0:
-		return report{message: "up-to-date"}, nil
-	default:
-		return report{}, errors.New("invalid version comparison")
-	}
-}
-
-func ValidateGHExtension(fl validator.FieldLevel) bool {
-	return fl.Field().String() == "" || strings.HasPrefix(fl.Field().String(), "gh-")
-}
-
-func (c GitHub) IsGHExtension() bool {
-	return c.As != nil && c.As.GHExtension != nil && c.As.GHExtension.Name != ""
-}
-
-type ghManifest struct {
-	Owner    string `yaml:"owner"`
-	Name     string `yaml:"name"`
-	Host     string `yaml:"host"`
-	Tag      string `yaml:"tag"`
-	IsPinned bool   `yaml:"ispinned"`
-	Path     string `yaml:"path"`
-}
-
-func (gh GHExtension) GetHome() string {
-	base := filepath.Join(os.Getenv("HOME"), ".local", "share", "gh", "extensions")
-	var ext string
-	if gh.RenameTo == "" {
-		ext = filepath.Join(base, gh.Name)
-	} else {
-		ext = filepath.Join(base, gh.RenameTo)
-	}
-	return ext
-}
-
-func (gh GHExtension) GetTag() string {
-	if gh.Tag != "" {
-		return gh.Tag
-	}
-	return "latest"
-}
-
-func (gh GHExtension) Install(ctx context.Context, owner, repo, tag string) error {
-	available, _ := github.HasRelease(http.DefaultClient, owner, repo, tag)
-	if available {
-		err := gh.InstallFromRelease(ctx, owner, repo, tag)
-		if err != nil {
-			return fmt.Errorf("%w: %s: failed to get gh extension", err, gh.Name)
-		}
-	}
-
-	ghHome := gh.GetHome()
-	// ensure to create the parent dir of each gh extension's path
-	_ = os.MkdirAll(filepath.Dir(ghHome), os.ModePerm)
-
-	// make alias
-	if gh.RenameTo != "" {
-		if err := os.Symlink(
-			filepath.Join(ghHome, gh.Name),
-			filepath.Join(ghHome, gh.RenameTo),
-		); err != nil {
-			return fmt.Errorf("%w: failed to symlink as alise", err)
-		}
-	}
-
-	if gh.GetTag() == "latest" {
-		// in case of not making manifest yaml
-		return nil
-	}
-
-	return gh.makeManifest(owner)
-}
-
-func (gh GHExtension) InstallFromRelease(ctx context.Context, owner, repo, tag string) error {
-	ctx, cancel := context.WithCancel(ctx)
-	defer cancel()
-
-	log.Printf("[DEBUG] install from release: %s/%s (%s)", owner, repo, tag)
-	release, err := github.NewRelease(
-		ctx, owner, repo, tag,
-		github.WithOverwrite(),
-		github.WithWorkdir(gh.GetHome()),
-	)
-	if err != nil {
-		return err
-	}
-
-	asset, err := release.Download(ctx)
-	if err != nil {
-		return errors.Wrapf(err, "%s: failed to download", release.Name)
-	}
-
-	if err := release.Unarchive(asset); err != nil {
-		return errors.Wrapf(err, "%s: failed to unarchive", release.Name)
-	}
-
-	return nil
-}
-
-func (gh GHExtension) makeManifest(owner string) error {
-	// https://github.com/cli/cli/blob/c9a2d85793c4cef026d5bb941b3ac4121c81ae10/pkg/cmd/extension/manager.go#L424-L451
-	manifest := ghManifest{
-		Name:     gh.Name,
-		Owner:    owner,
-		Host:     "github.com",
-		Path:     gh.GetHome(),
-		Tag:      gh.GetTag(),
-		IsPinned: false,
-	}
-	bs, err := yaml.Marshal(manifest)
-	if err != nil {
-		return fmt.Errorf("failed to serialize manifest: %w", err)
-	}
-
-	manifestPath := filepath.Join(gh.GetHome(), "manifest.yml")
-	f, err := os.OpenFile(manifestPath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0600)
-	if err != nil {
-		return fmt.Errorf("failed to open manifest for writing: %w", err)
-	}
-	defer f.Close()
-
-	_, err = f.Write(bs)
-	if err != nil {
-		return fmt.Errorf("failed write manifest file: %w", err)
-	}
-	return nil
-}
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
