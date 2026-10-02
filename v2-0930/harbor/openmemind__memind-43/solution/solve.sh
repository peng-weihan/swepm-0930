#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/memind-server/src/main/java/com/openmemind/ai/memory/server/configuration/MemindServerCorsConfiguration.java b/memind-server/src/main/java/com/openmemind/ai/memory/server/configuration/MemindServerCorsConfiguration.java
new file mode 100644
--- /dev/null
+++ b/memind-server/src/main/java/com/openmemind/ai/memory/server/configuration/MemindServerCorsConfiguration.java
@@ -0,0 +1,40 @@
+/*
+ * Licensed under the Apache License, Version 2.0 (the "License");
+ * you may not use this file except in compliance with the License.
+ * You may obtain a copy of the License at
+ *
+ * http://www.apache.org/licenses/LICENSE-2.0
+ *
+ * Unless required by applicable law or agreed to in writing, software
+ * distributed under the License is distributed on an "AS IS" BASIS,
+ * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
+ * See the License for the specific language governing permissions and
+ * limitations under the License.
+ */
+package com.openmemind.ai.memory.server.configuration;
+
+import org.springframework.context.annotation.Bean;
+import org.springframework.context.annotation.Configuration;
+import org.springframework.web.cors.CorsConfiguration;
+import org.springframework.web.cors.UrlBasedCorsConfigurationSource;
+import org.springframework.web.filter.CorsFilter;
+
+@Configuration
+public class MemindServerCorsConfiguration {
+
+    @Bean
+    public CorsFilter corsFilter() {
+        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
+        source.registerCorsConfiguration("/**", openCorsConfiguration());
+        return new CorsFilter(source);
+    }
+
+    static CorsConfiguration openCorsConfiguration() {
+        CorsConfiguration configuration = new CorsConfiguration();
+        configuration.addAllowedOrigin(CorsConfiguration.ALL);
+        configuration.addAllowedMethod(CorsConfiguration.ALL);
+        configuration.addAllowedHeader(CorsConfiguration.ALL);
+        configuration.setAllowCredentials(false);
+        return configuration;
+    }
+}
diff --git a/memind-server/src/main/java/com/openmemind/ai/memory/server/service/config/MemoryOptionsProjectionMapper.java b/memind-server/src/main/java/com/openmemind/ai/memory/server/service/config/MemoryOptionsProjectionMapper.java
--- a/memind-server/src/main/java/com/openmemind/ai/memory/server/service/config/MemoryOptionsProjectionMapper.java
+++ b/memind-server/src/main/java/com/openmemind/ai/memory/server/service/config/MemoryOptionsProjectionMapper.java
@@ -393,7 +393,7 @@ public Map<String, List<MemoryOptionItemView>> toProjection(MemoryBuildOptions o
                 flattenValues(PersistedMemoryOptions.from(MemoryBuildOptions.defaults()));
         Map<String, List<MemoryOptionItemView>> grouped = new LinkedHashMap<>();
         for (OptionDefinition definition : DEFINITIONS) {
-            grouped.computeIfAbsent(definition.group(), ignored -> new ArrayList<>())
+            grouped.computeIfAbsent(groupForKey(definition.key()), ignored -> new ArrayList<>())
                     .add(
                             new MemoryOptionItemView(
                                     definition.key(),
@@ -432,24 +432,22 @@ public MemoryBuildOptions toOptions(Map<String, List<MemoryOptionItemView>> conf
 
     private static List<OptionDefinition> discoverDefinitions(Object value) {
         List<OptionDefinition> definitions = new ArrayList<>();
-        collectDefinitions(value, value == null ? null : value.getClass(), "", "", definitions);
+        collectDefinitions(value, value == null ? null : value.getClass(), "", definitions);
         return List.copyOf(definitions);
     }
 
     private static void collectDefinitions(
             Object value,
             Class<?> declaredType,
             String currentPath,
-            String currentGroup,
             List<OptionDefinition> definitions) {
         if (value == null) {
             return;
         }
         Class<?> type = declaredType == null ? value.getClass() : declaredType;
         if (!type.isRecord()) {
             definitions.add(
-                    new OptionDefinition(
-                            currentPath, currentGroup, type, List.of(currentPath.split("\\."))));
+                    new OptionDefinition(currentPath, type, List.of(currentPath.split("\\."))));
             return;
         }
         for (RecordComponent component : type.getRecordComponents()) {
@@ -458,12 +456,62 @@ private static void collectDefinitions(
                     currentPath.isBlank()
                             ? component.getName()
                             : currentPath + "." + component.getName();
-            String nextGroup = currentPath.isBlank() ? component.getName() : currentGroup;
-            collectDefinitions(
-                    componentValue, component.getType(), nextPath, nextGroup, definitions);
+            collectDefinitions(componentValue, component.getType(), nextPath, definitions);
         }
     }
 
+    private static String groupForKey(String key) {
+        if (key.startsWith("extraction.common.")) {
+            return "extraction.common";
+        }
+        if (key.startsWith("extraction.rawdata.")) {
+            return "extraction.rawdata";
+        }
+        if (key.startsWith("extraction.item.graph.")) {
+            return "extraction.itemGraph";
+        }
+        if (key.startsWith("extraction.item.")) {
+            return "extraction.item";
+        }
+        if (key.startsWith("extraction.insight.")) {
+            return "extraction.insight";
+        }
+        if (key.startsWith("retrieval.common.")) {
+            return "retrieval.common";
+        }
+        if (key.startsWith("retrieval.simple.graphAssist.")) {
+            return "retrieval.simpleGraphAssist";
+        }
+        if (key.startsWith("retrieval.simple.memoryThreadAssist.")) {
+            return "retrieval.simpleThreadAssist";
+        }
+        if (key.startsWith("retrieval.simple.")) {
+            return "retrieval.simple";
+        }
+        if (key.startsWith("retrieval.deep.graphAssist.")) {
+            return "retrieval.deepGraphAssist";
+        }
+        if (key.startsWith("retrieval.deep.memoryThreadAssist.")) {
+            return "retrieval.deepThreadAssist";
+        }
+        if (key.startsWith("retrieval.deep.")) {
+            return "retrieval.deep";
+        }
+        if (key.startsWith("retrieval.advanced.rerank.")) {
+            return "retrieval.rerank";
+        }
+        if (key.startsWith("retrieval.advanced.scoring.")) {
+            return "retrieval.scoring";
+        }
+        if (key.startsWith("memoryThread.enrichment.")) {
+            return "memoryThread.enrichment";
+        }
+        if (key.startsWith("memoryThread.")) {
+            return "memoryThread.lifecycle";
+        }
+        throw new IllegalArgumentException("Unsupported memory option key group: " + key);
+    }
+
     private static Map<String, Object> flattenValues(Object value) {
         Map<String, Object> flattened = new LinkedHashMap<>();
         collectValues(value, "", flattened);
@@ -666,10 +714,10 @@ private static String typeName(Class<?> rawType) {
             return "integer";
         }
         if (type == Double.class || type == Float.class) {
-            return "number";
+            return "double";
         }
         if (type == Duration.class) {
-            return "duration";
+            return "string";
         }
         if (Collection.class.isAssignableFrom(type)) {
             return "array";
@@ -678,7 +726,7 @@ private static String typeName(Class<?> rawType) {
             return "object";
         }
         if (Enum.class.isAssignableFrom(type)) {
-            return "enum";
+            return "string";
         }
         return "string";
     }
@@ -735,8 +783,7 @@ private static Class<?> boxedType(Class<?> type) {
         return type;
     }
 
-    private record OptionDefinition(
-            String key, String group, Class<?> type, List<String> pathSegments) {}
+    private record OptionDefinition(String key, Class<?> type, List<String> pathSegments) {}
 
     private record PersistedMemoryOptions(
             ExtractionOptions extraction,
diff --git a/memind-ui/.env.example b/memind-ui/.env.example
new file mode 100644
--- /dev/null
+++ b/memind-ui/.env.example
@@ -0,0 +1 @@
+VITE_CLERK_PUBLISHABLE_KEY=
\ No newline at end of file
diff --git a/memind-ui/.env.mock b/memind-ui/.env.mock
new file mode 100644
--- /dev/null
+++ b/memind-ui/.env.mock
@@ -0,0 +1 @@
+VITE_MEMIND_MOCK_API=true
diff --git a/memind-ui/.gitignore b/memind-ui/.gitignore
new file mode 100644
--- /dev/null
+++ b/memind-ui/.gitignore
@@ -0,0 +1,34 @@
+# Logs
+logs
+*.log
+npm-debug.log*
+yarn-debug.log*
+yarn-error.log*
+pnpm-debug.log*
+lerna-debug.log*
+
+node_modules
+dist
+dist-ssr
+*.local
+
+.env
+
+# Editor directories and files
+.vscode/*
+!.vscode/extensions.json
+!.vscode/settings.json
+.idea
+.DS_Store
+*.suo
+*.ntvs*
+*.njsproj
+*.sln
+*.sw?
+
+# Test coverage
+/coverage
+
+# Vitest artifacts (browser screenshots/attachments)
+**/__screenshots__/
+.vitest-attachments/
diff --git a/memind-ui/.prettierignore b/memind-ui/.prettierignore
new file mode 100644
--- /dev/null
+++ b/memind-ui/.prettierignore
@@ -0,0 +1,19 @@
+# Ignore everything
+/*
+
+# Except these files & folders
+!/src
+!index.html
+!package.json
+!tailwind.config.js
+!tsconfig.json
+!tsconfig.node.json
+!vite.config.ts
+!.prettierrc
+!README.md
+!eslint.config.js
+!postcss.config.js
+!.vscode/
+
+# Ignore auto generated routeTree.gen.ts
+/src/routeTree.gen.ts
\ No newline at end of file
diff --git a/memind-ui/.prettierrc b/memind-ui/.prettierrc
new file mode 100644
--- /dev/null
+++ b/memind-ui/.prettierrc
@@ -0,0 +1,51 @@
+{
+  "arrowParens": "always",
+  "semi": false,
+  "tabWidth": 2,
+  "printWidth": 80,
+  "singleQuote": true,
+  "jsxSingleQuote": true,
+  "trailingComma": "es5",
+  "bracketSpacing": true,
+  "endOfLine": "lf",
+  "plugins": [
+    "@trivago/prettier-plugin-sort-imports",
+    "prettier-plugin-tailwindcss"
+  ],
+  "tailwindFunctions": ["cn", "clsx"],
+  "tailwindStylesheet": "./src/styles/index.css",
+  "importOrder": [
+    "^path$",
+    "^vite$",
+    "^@vitejs/(.*)$",
+    "^react$",
+    "^react-dom/client$",
+    "^react/(.*)$",
+    "^globals$",
+    "^zod$",
+    "^axios$",
+    "^date-fns$",
+    "^react-hook-form$",
+    "^use-intl$",
+    "^@radix-ui/(.*)$",
+    "^@hookform/resolvers/zod$",
+    "^@tanstack/react-query$",
+    "^@tanstack/react-router$",
+    "^@tanstack/react-table$",
+    "<THIRD_PARTY_MODULES>",
+    "^@/assets/(.*)",
+    "^@/api/(.*)$",
+    "^@/stores/(.*)$",
+    "^@/lib/(.*)$",
+    "^@/utils/(.*)$",
+    "^@/constants/(.*)$",
+    "^@/context/(.*)$",
+    "^@/hooks/(.*)$",
+    "^@/components/layouts/(.*)$",
+    "^@/components/ui/(.*)$",
+    "^@/components/errors/(.*)$",
+    "^@/components/(.*)$",
+    "^@/features/(.*)$",
+    "^[./]"
+  ]
+}
diff --git a/memind-ui/README.md b/memind-ui/README.md
new file mode 100644
--- /dev/null
+++ b/memind-ui/README.md
@@ -0,0 +1,93 @@
+# Memind UI
+
+Local Memory Admin for a developer-run `memind-server`.
+
+`memind-ui` is a standalone Vite React application for inspecting and managing local Memind memory data. It is intentionally not a Maven module and is not bundled into `memind-server` in this first version.
+
+## Local-Only Warning
+
+This UI has no login or authorization flow. It can expose delete, rebuild, and runtime configuration operations from the connected Memind server. Do not expose the Vite dev server, built frontend, or proxied Memind server endpoints to public networks.
+
+## Requirements
+
+- Node.js `^20.19.0 || ^22.12.0 || >=24.0.0`
+- pnpm `>=9.0.0`
+- Corepack is recommended so the pinned `packageManager` value is used.
+
+## Memind Server
+
+Run `memind-server` separately before using the UI. The default local server URL is:
+
+```text
+http://127.0.0.1:8366
+```
+
+During development, Vite proxies same-origin requests:
+
+- `/admin` -> `http://127.0.0.1:8366`
+- `/open` -> `http://127.0.0.1:8366`
+
+## Development
+
+Install dependencies:
+
+```bash
+pnpm install
+```
+
+Install the browser runtime used by Vitest browser tests:
+
+```bash
+pnpm test:browser:install
+```
+
+Start the dev server:
+
+```bash
+pnpm dev
+```
+
+Start the UI with rich local mock data when a real `memind-server` has little
+or no data:
+
+```bash
+pnpm dev:mock
+```
+
+Mock mode is frontend-only. It keeps the Vite proxy and real server untouched,
+but `api-client` serves `/admin` and `/open` requests from deterministic local
+fixtures when `VITE_MEMIND_MOCK_API=true`.
+
+Run checks:
+
+```bash
+pnpm lint
+pnpm test
+pnpm build
+```
+
+## First Run
+
+1. Start `memind-server`.
+2. Start this UI with `pnpm dev`.
+3. Open the Vite URL shown in the terminal.
+4. Set the global memory scope when detail views require `userId` or `agentId`, using the `userId:agentId` input in the header.
+
+Keep the UI on localhost. It is unauthenticated and should not be exposed to public networks.
+
+## Manual Integration Checklist
+
+With `memind-server` running at `http://127.0.0.1:8366`, verify:
+
+- Server status changes to `connected`.
+- Dashboard loads real data or real zero counts.
+- List pages load with `pageNo` and `pageSize`; filters change request query strings.
+- Items, Raw Data, Insights, Memory Threads, and Item Graph detail drawers load detail data.
+- Buffers and Item Graph tab links preserve the expected `tab` and filter search params.
+- Delete dialogs send selected row ids only; run destructive checks only on disposable test data.
+- Config Save sends one full config document with `expectedVersion`; stale versions show the conflict message.
+- Retrieve sends `userId`, `agentId`, `query`, `strategy`, and `trace`, then renders returned results and trace details.
+
+## Attribution
+
+This module is derived from selected source files and project structure from `shadcn-admin`. See [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md).
diff --git a/memind-ui/THIRD_PARTY_NOTICES.md b/memind-ui/THIRD_PARTY_NOTICES.md
new file mode 100644
--- /dev/null
+++ b/memind-ui/THIRD_PARTY_NOTICES.md
@@ -0,0 +1,33 @@
+# Third-Party Notices
+
+`memind-ui` is derived from selected source files and project structure from `shadcn-admin`.
+
+## shadcn-admin
+
+- Source project: https://github.com/satnaing/shadcn-admin
+- License: MIT
+
+MIT License
+
+Copyright (c) 2024 Sat Naing
+
+Permission is hereby granted, free of charge, to any person obtaining a copy
+of this software and associated documentation files (the "Software"), to deal
+in the Software without restriction, including without limitation the rights
+to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
+copies of the Software, and to permit persons to whom the Software is
+furnished to do so, subject to the following conditions:
+
+The above copyright notice and this permission notice shall be included in all
+copies or substantial portions of the Software.
+
+THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
+IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
+FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
+AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
+LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
+OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
+SOFTWARE.
+
+Memind project code remains under the repository's Apache-2.0 license unless
+otherwise stated in a specific file or notice.
diff --git a/memind-ui/components.json b/memind-ui/components.json
new file mode 100644
--- /dev/null
+++ b/memind-ui/components.json
@@ -0,0 +1,21 @@
+{
+  "$schema": "https://ui.shadcn.com/schema.json",
+  "style": "new-york",
+  "rsc": false,
+  "tsx": true,
+  "tailwind": {
+    "config": "",
+    "css": "src/styles/index.css",
+    "baseColor": "slate",
+    "cssVariables": true,
+    "prefix": ""
+  },
+  "aliases": {
+    "components": "@/components",
+    "utils": "@/lib/utils",
+    "ui": "@/components/ui",
+    "lib": "@/lib",
+    "hooks": "@/hooks"
+  },
+  "iconLibrary": "lucide"
+}
diff --git a/memind-ui/eslint.config.js b/memind-ui/eslint.config.js
new file mode 100644
--- /dev/null
+++ b/memind-ui/eslint.config.js
@@ -0,0 +1,59 @@
+import globals from 'globals'
+import js from '@eslint/js'
+import pluginQuery from '@tanstack/eslint-plugin-query'
+import reactHooks from 'eslint-plugin-react-hooks'
+import reactRefresh from 'eslint-plugin-react-refresh'
+import { defineConfig } from 'eslint/config'
+import tseslint from 'typescript-eslint'
+
+export default defineConfig(
+  { ignores: ['dist', 'src/components/ui'] },
+  {
+    extends: [
+      js.configs.recommended,
+      ...tseslint.configs.recommended,
+      ...pluginQuery.configs['flat/recommended'],
+    ],
+    files: ['**/*.{ts,tsx}'],
+    languageOptions: {
+      ecmaVersion: 2020,
+      globals: globals.browser,
+    },
+    plugins: {
+      'react-hooks': reactHooks,
+      'react-refresh': reactRefresh,
+    },
+    rules: {
+      ...reactHooks.configs.recommended.rules,
+      'react-refresh/only-export-components': [
+        'warn',
+        { allowConstantExport: true },
+      ],
+      'no-console': 'error',
+      'no-unused-vars': 'off',
+      '@typescript-eslint/no-unused-vars': [
+        'error',
+        {
+          args: 'all',
+          argsIgnorePattern: '^_',
+          caughtErrors: 'all',
+          caughtErrorsIgnorePattern: '^_',
+          destructuredArrayIgnorePattern: '^_',
+          varsIgnorePattern: '^_',
+          ignoreRestSiblings: true,
+        },
+      ],
+      // Enforce type-only imports for TypeScript types
+      '@typescript-eslint/consistent-type-imports': [
+        'error',
+        {
+          prefer: 'type-imports',
+          fixStyle: 'inline-type-imports',
+          disallowTypeAnnotations: false,
+        },
+      ],
+      // Prevent duplicate imports from the same module
+      'no-duplicate-imports': 'error',
+    },
+  }
+)
diff --git a/memind-ui/index.html b/memind-ui/index.html
new file mode 100644
--- /dev/null
+++ b/memind-ui/index.html
@@ -0,0 +1,62 @@
+<!doctype html>
+<html lang="en">
+  <head>
+    <meta charset="UTF-8" />
+    <link
+      rel="icon"
+      type="image/svg+xml"
+      href="/images/favicon.svg"
+      media="(prefers-color-scheme: light)"
+    />
+    <link
+      rel="icon"
+      type="image/svg+xml"
+      href="/images/favicon_light.svg"
+      media="(prefers-color-scheme: dark)"
+    />
+    <link
+      rel="icon"
+      type="image/png"
+      href="/images/favicon.png"
+      media="(prefers-color-scheme: light)"
+    />
+    <link
+      rel="icon"
+      type="image/png"
+      href="/images/favicon_light.png"
+      media="(prefers-color-scheme: dark)"
+    />
+    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
+
+    <!-- Primary Meta Tags -->
+    <title>Memind UI</title>
+    <meta name="title" content="Memind UI" />
+    <meta
+      name="description"
+      content="Local Memory Admin for a developer-run memind-server."
+    />
+
+    <!-- Open Graph / Facebook -->
+    <meta property="og:type" content="website" />
+    <meta property="og:title" content="Memind UI" />
+    <meta
+      property="og:description"
+      content="Local Memory Admin for a developer-run memind-server."
+    />
+
+    <!-- Twitter -->
+    <meta property="twitter:card" content="summary_large_image" />
+    <meta property="twitter:title" content="Memind UI" />
+    <meta
+      property="twitter:description"
+      content="Local Memory Admin for a developer-run memind-server."
+    />
+
+    <meta name="theme-color" content="#fff" />
+  </head>
+
+  <body>
+    <div id="root"></div>
+    <script type="module" src="/src/main.tsx"></script>
+  </body>
+</html>
diff --git a/memind-ui/knip.config.ts b/memind-ui/knip.config.ts
new file mode 100644
--- /dev/null
+++ b/memind-ui/knip.config.ts
@@ -0,0 +1,10 @@
+import type { KnipConfig } from 'knip'
+
+const config: KnipConfig = {
+  ignore: [
+    'src/components/ui/**',
+    'src/tanstack-table.d.ts',
+  ],
+}
+
+export default config
diff --git a/memind-ui/package.json b/memind-ui/package.json
new file mode 100644
--- /dev/null
+++ b/memind-ui/package.json
@@ -0,0 +1,84 @@
+{
+  "name": "memind-ui",
+  "private": true,
+  "version": "0.1.0",
+  "type": "module",
+  "engines": {
+    "node": "^20.19.0 || ^22.12.0 || >=24.0.0",
+    "pnpm": ">=9.0.0"
+  },
+  "packageManager": "pnpm@10.15.0",
+  "scripts": {
+    "dev": "vite",
+    "dev:mock": "vite --mode mock --host 127.0.0.1",
+    "build": "tsc -b && vite build",
+    "lint": "eslint .",
+    "preview": "vite preview",
+    "format:check": "prettier --check .",
+    "format": "prettier --write .",
+    "knip": "knip",
+    "test": "vitest run --browser.headless",
+    "test:watch": "vitest --browser.headless",
+    "test:ui": "vitest --ui --browser.headless",
+    "test:browser": "vitest",
+    "test:coverage": "vitest run --coverage --browser.headless",
+    "test:browser:install": "playwright install chromium --with-deps"
+  },
+  "dependencies": {
+    "@radix-ui/react-alert-dialog": "^1.1.15",
+    "@radix-ui/react-checkbox": "^1.3.3",
+    "@radix-ui/react-collapsible": "^1.1.12",
+    "@radix-ui/react-dialog": "^1.1.15",
+    "@radix-ui/react-direction": "^1.1.1",
+    "@radix-ui/react-dropdown-menu": "^2.1.16",
+    "@radix-ui/react-label": "^2.1.8",
+    "@radix-ui/react-separator": "^1.1.8",
+    "@radix-ui/react-slot": "^1.2.4",
+    "@radix-ui/react-switch": "^1.2.6",
+    "@radix-ui/react-tabs": "^1.1.13",
+    "@radix-ui/react-tooltip": "^1.2.8",
+    "@tailwindcss/vite": "^4.2.2",
+    "@tanstack/react-query": "^5.99.0",
+    "@tanstack/react-router": "^1.168.22",
+    "@tanstack/react-table": "^8.21.3",
+    "axios": "^1.15.0",
+    "class-variance-authority": "^0.7.1",
+    "clsx": "^2.1.1",
+    "lucide-react": "^1.8.0",
+    "react": "^19.2.5",
+    "react-dom": "^19.2.5",
+    "react-top-loading-bar": "^3.0.2",
+    "sonner": "^2.0.7",
+    "tailwind-merge": "^3.5.0",
+    "tailwindcss": "^4.2.2",
+    "tw-animate-css": "^1.4.0"
+  },
+  "devDependencies": {
+    "@eslint/js": "^10.0.1",
+    "@tanstack/eslint-plugin-query": "^5.99.0",
+    "@tanstack/react-query-devtools": "^5.99.0",
+    "@tanstack/react-router-devtools": "^1.166.13",
+    "@tanstack/router-plugin": "^1.167.22",
+    "@trivago/prettier-plugin-sort-imports": "^6.0.2",
+    "@types/node": "^25.6.0",
+    "@types/react": "^19.2.14",
+    "@types/react-dom": "^19.2.3",
+    "@vitejs/plugin-react": "^6.0.1",
+    "@vitest/browser-playwright": "^4.1.4",
+    "@vitest/coverage-v8": "^4.1.4",
+    "@vitest/ui": "^4.1.4",
+    "eslint": "^10.2.1",
+    "eslint-plugin-react-hooks": "7.1.1",
+    "eslint-plugin-react-refresh": "^0.5.2",
+    "globals": "^17.5.0",
+    "knip": "^6.4.1",
+    "playwright": "1.59.1",
+    "prettier": "^3.8.3",
+    "prettier-plugin-tailwindcss": "^0.7.2",
+    "typescript": "~6.0.3",
+    "typescript-eslint": "^8.58.2",
+    "vite": "^8.0.8",
+    "vitest": "^4.1.4",
+    "vitest-browser-react": "^2.2.0"
+  }
+}
diff --git a/memind-ui/pnpm-lock.yaml b/memind-ui/pnpm-lock.yaml
new file mode 100644
--- /dev/null
+++ b/memind-ui/pnpm-lock.yaml

diff --git a/memind-ui/public/images/favicon.png b/memind-ui/public/images/favicon.png
new file mode 100644
--- /dev/null
+++ b/memind-ui/public/images/favicon.png

diff --git a/memind-ui/public/images/favicon.svg b/memind-ui/public/images/favicon.svg
new file mode 100644
--- /dev/null
+++ b/memind-ui/public/images/favicon.svg
@@ -0,0 +1,4 @@
+<svg xmlns="http://www.w3.org/2000/svg" version="1.1" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:svgjs="http://svgjs.com/svgjs" width="24" height="24"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokewidth="2" strokelinecap="round" strokelinejoin="round">
+  <path d="M15 6v12a3 3 0 1 0 3-3H6a3 3 0 1 0 3 3V6a3 3 0 1 0-3 3h12a3 3 0 1 0-3-3"></path>
+</svg><style>@media (prefers-color-scheme: light) { :root { filter: contrast(1) brightness(0.8); } }
+</style></svg>
\ No newline at end of file
diff --git a/memind-ui/public/images/favicon_light.png b/memind-ui/public/images/favicon_light.png
new file mode 100644
--- /dev/null
+++ b/memind-ui/public/images/favicon_light.png

diff --git a/memind-ui/public/images/favicon_light.svg b/memind-ui/public/images/favicon_light.svg
new file mode 100644
--- /dev/null
+++ b/memind-ui/public/images/favicon_light.svg
@@ -0,0 +1 @@
+<svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="24" height="24" viewBox="948,463.5,24,24"><defs><clipPath id="clip-1"><rect x="948" y="463.5" width="24" height="24" id="clip-1" stroke="none"/></clipPath></defs><g fill="none" fill-rule="nonzero" stroke="none" stroke-width="1" stroke-linecap="butt" stroke-linejoin="miter" stroke-miterlimit="10" stroke-dasharray="" stroke-dashoffset="0" font-family="none" font-weight="none" font-size="none" text-anchor="none" style="mix-blend-mode: normal"><g><g id="Group 1"><g clip-path="url(#clip-1)" id="Group 1"><path d="M963,469.5v12c0,1.65685 1.34315,3 3,3c1.65685,0 3,-1.34315 3,-3c0,-1.65685 -1.34315,-3 -3,-3h-12c-1.65685,0 -3,1.34315 -3,3c0,1.65685 1.34315,3 3,3c1.65685,0 3,-1.34315 3,-3v-12c0,-1.65685 -1.34315,-3 -3,-3c-1.65685,0 -3,1.34315 -3,3c0,1.65685 1.34315,3 3,3h12c1.65685,0 3,-1.34315 3,-3c0,-1.65685 -1.34315,-3 -3,-3c-1.65685,0 -3,1.34315 -3,3" id="Path 1" stroke="#f2f2f2"/></g></g></g></g></svg>
\ No newline at end of file
diff --git a/memind-ui/public/images/shadcn-admin.png b/memind-ui/public/images/shadcn-admin.png
new file mode 100644
--- /dev/null
+++ b/memind-ui/public/images/shadcn-admin.png

diff --git a/memind-ui/src/components/layout/app-layout.tsx b/memind-ui/src/components/layout/app-layout.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/components/layout/app-layout.tsx
@@ -0,0 +1,36 @@
+import { Outlet } from '@tanstack/react-router'
+import { getCookie } from '@/lib/cookies'
+import { cn } from '@/lib/utils'
+import { SidebarInset, SidebarProvider } from '@/components/ui/sidebar'
+import { AppSidebar } from '@/components/layout/app-sidebar'
+import { SkipToMain } from '@/components/skip-to-main'
+
+type AppLayoutProps = {
+  children?: React.ReactNode
+}
+
+export function AppLayout({ children }: AppLayoutProps) {
+  const defaultOpen = getCookie('sidebar_state') !== 'false'
+  return (
+    <SidebarProvider defaultOpen={defaultOpen}>
+      <SkipToMain />
+      <AppSidebar />
+      <SidebarInset
+        className={cn(
+          // Set content container, so we can use container queries
+          '@container/content',
+
+          // If layout is fixed, set the height
+          // to 100svh to prevent overflow
+          'has-data-[layout=fixed]:h-svh',
+
+          // If layout is fixed and sidebar is inset,
+          // set the height to 100svh - spacing (total margins) to prevent overflow
+          'peer-data-[variant=inset]:has-data-[layout=fixed]:h-[calc(100svh-(var(--spacing)*4))]'
+        )}
+      >
+        {children ?? <Outlet />}
+      </SidebarInset>
+    </SidebarProvider>
+  )
+}
diff --git a/memind-ui/src/components/layout/app-sidebar.tsx b/memind-ui/src/components/layout/app-sidebar.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/components/layout/app-sidebar.tsx
@@ -0,0 +1,30 @@
+import {
+  Sidebar,
+  SidebarContent,
+  SidebarFooter,
+  SidebarHeader,
+  SidebarRail,
+} from '@/components/ui/sidebar'
+import { ServerStatus } from '@/features/components/server-status'
+import { AppTitle } from './app-title'
+import { sidebarData } from './data/sidebar-data'
+import { NavGroup } from './nav-group'
+
+export function AppSidebar() {
+  return (
+    <Sidebar collapsible='icon' variant='inset'>
+      <SidebarHeader>
+        <AppTitle />
+      </SidebarHeader>
+      <SidebarContent>
+        {sidebarData.navGroups.map((props) => (
+          <NavGroup key={props.title} {...props} />
+        ))}
+      </SidebarContent>
+      <SidebarFooter>
+        <ServerStatus />
+      </SidebarFooter>
+      <SidebarRail />
+    </Sidebar>
+  )
+}
diff --git a/memind-ui/src/components/layout/app-title.tsx b/memind-ui/src/components/layout/app-title.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/components/layout/app-title.tsx
@@ -0,0 +1,65 @@
+import { Link } from '@tanstack/react-router'
+import { Menu, X } from 'lucide-react'
+import { cn } from '@/lib/utils'
+import {
+  SidebarMenu,
+  SidebarMenuButton,
+  SidebarMenuItem,
+  useSidebar,
+} from '@/components/ui/sidebar'
+import { Button } from '../ui/button'
+
+export function AppTitle() {
+  const { setOpenMobile } = useSidebar()
+  return (
+    <SidebarMenu>
+      <SidebarMenuItem>
+        <SidebarMenuButton
+          size='lg'
+          className='gap-0 py-0 hover:bg-transparent active:bg-transparent'
+          asChild
+        >
+          <div>
+            <Link
+              to='/'
+              search={{}}
+              onClick={() => setOpenMobile(false)}
+              className='grid flex-1 text-start text-sm leading-tight'
+            >
+              <span className='truncate font-bold'>Memind UI</span>
+              <span className='truncate text-xs'>Local Memory Admin</span>
+            </Link>
+            <ToggleSidebar />
+          </div>
+        </SidebarMenuButton>
+      </SidebarMenuItem>
+    </SidebarMenu>
+  )
+}
+
+function ToggleSidebar({
+  className,
+  onClick,
+  ...props
+}: React.ComponentProps<typeof Button>) {
+  const { toggleSidebar } = useSidebar()
+
+  return (
+    <Button
+      data-sidebar='trigger'
+      data-slot='sidebar-trigger'
+      variant='ghost'
+      size='icon'
+      className={cn('aspect-square size-8 max-md:scale-125', className)}
+      onClick={(event) => {
+        onClick?.(event)
+        toggleSidebar()
+      }}
+      {...props}
+    >
+      <X className='md:hidden' />
+      <Menu className='max-md:hidden' />
+      <span className='sr-only'>Toggle Sidebar</span>
+    </Button>
+  )
+}
diff --git a/memind-ui/src/components/layout/data/sidebar-data.ts b/memind-ui/src/components/layout/data/sidebar-data.ts
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/components/layout/data/sidebar-data.ts
@@ -0,0 +1,29 @@
+import {
+  Database,
+  FileText,
+  GitBranch,
+  Inbox,
+  LayoutDashboard,
+  Lightbulb,
+  Network,
+  SlidersHorizontal,
+} from 'lucide-react'
+import { type SidebarData } from '../types'
+
+export const sidebarData: SidebarData = {
+  navGroups: [
+    {
+      title: 'Memind',
+      items: [
+        { title: 'Dashboard', url: '/', icon: LayoutDashboard },
+        { title: 'Buffers', url: '/buffers', icon: Inbox },
+        { title: 'Raw Data', url: '/raw-data', icon: FileText },
+        { title: 'Memory Items', url: '/items', icon: Database },
+        { title: 'Item Graph', url: '/item-graph', icon: Network },
+        { title: 'Memory Threads', url: '/memory-threads', icon: GitBranch },
+        { title: 'Insight Tree', url: '/insights', icon: Lightbulb },
+        { title: 'Settings', url: '/config', icon: SlidersHorizontal },
+      ],
+    },
+  ],
+}
diff --git a/memind-ui/src/components/layout/header.tsx b/memind-ui/src/components/layout/header.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/components/layout/header.tsx
@@ -0,0 +1,56 @@
+import { useEffect, useState } from 'react'
+import { cn } from '@/lib/utils'
+import { Separator } from '@/components/ui/separator'
+import { SidebarTrigger } from '@/components/ui/sidebar'
+import { MemoryScopePicker } from '@/features/components/memory-scope-picker'
+import { ThemeSwitch } from '../theme-switch'
+
+type HeaderProps = React.HTMLAttributes<HTMLElement> & {
+  fixed?: boolean
+  ref?: React.Ref<HTMLElement>
+}
+
+export function Header({ className, fixed, children, ...props }: HeaderProps) {
+  const [offset, setOffset] = useState(0)
+
+  useEffect(() => {
+    const onScroll = () => {
+      setOffset(document.body.scrollTop || document.documentElement.scrollTop)
+    }
+
+    // Add scroll listener to the body
+    document.addEventListener('scroll', onScroll, { passive: true })
+
+    // Clean up the event listener on unmount
+    return () => document.removeEventListener('scroll', onScroll)
+  }, [])
+
+  return (
+    <header
+      className={cn(
+        'z-50 min-h-16',
+        fixed && 'header-fixed peer/header sticky top-0 w-[inherit]',
+        offset > 10 && fixed ? 'shadow' : 'shadow-none',
+        className
+      )}
+      {...props}
+    >
+      <div
+        className={cn(
+          'relative flex min-h-16 flex-wrap items-center gap-3 p-4 sm:gap-4',
+          offset > 10 &&
+            fixed &&
+            'after:absolute after:inset-0 after:-z-10 after:bg-background/20 after:backdrop-blur-lg'
+        )}
+      >
+        <SidebarTrigger variant='outline' className='max-md:scale-125' />
+        <Separator orientation='vertical' className='h-6' />
+        <div className='min-w-0 flex-1'>{children}</div>
+        <div className='ml-auto flex min-w-0 flex-wrap items-center justify-end gap-2'>
+          <MemoryScopePicker />
+          <ThemeSwitch />
+        </div>
+      </div>
+    </header>
+  )
+}
diff --git a/memind-ui/src/components/layout/main.tsx b/memind-ui/src/components/layout/main.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/components/layout/main.tsx
@@ -0,0 +1,27 @@
+import { cn } from '@/lib/utils'
+
+type MainProps = React.HTMLAttributes<HTMLElement> & {
+  fixed?: boolean
+  fluid?: boolean
+  ref?: React.Ref<HTMLElement>
+}
+
+export function Main({ fixed, className, fluid, ...props }: MainProps) {
+  return (
+    <main
+      data-layout={fixed ? 'fixed' : 'auto'}
+      className={cn(
+        'px-4 py-6',
+
+        // If layout is fixed, make the main container flex and grow
+        fixed && 'flex grow flex-col overflow-hidden',
+
+        // If layout is not fluid, set the max-width
+        !fluid &&
+          '@7xl/content:mx-auto @7xl/content:w-full @7xl/content:max-w-7xl',
+        className
+      )}
+      {...props}
+    />
+  )
+}
diff --git a/memind-ui/src/components/layout/nav-group.tsx b/memind-ui/src/components/layout/nav-group.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/components/layout/nav-group.tsx
@@ -0,0 +1,185 @@
+import { type ReactNode } from 'react'
+import { Link, useLocation } from '@tanstack/react-router'
+import { ChevronRight } from 'lucide-react'
+import {
+  Collapsible,
+  CollapsibleContent,
+  CollapsibleTrigger,
+} from '@/components/ui/collapsible'
+import {
+  SidebarGroup,
+  SidebarGroupLabel,
+  SidebarMenu,
+  SidebarMenuButton,
+  SidebarMenuItem,
+  SidebarMenuSub,
+  SidebarMenuSubButton,
+  SidebarMenuSubItem,
+  useSidebar,
+} from '@/components/ui/sidebar'
+import { Badge } from '../ui/badge'
+import {
+  DropdownMenu,
+  DropdownMenuContent,
+  DropdownMenuItem,
+  DropdownMenuLabel,
+  DropdownMenuSeparator,
+  DropdownMenuTrigger,
+} from '../ui/dropdown-menu'
+import {
+  type NavCollapsible,
+  type NavItem,
+  type NavLink,
+  type NavGroup as NavGroupProps,
+} from './types'
+
+export function NavGroup({ title, items }: NavGroupProps) {
+  const { state, isMobile } = useSidebar()
+  const href = useLocation({ select: (location) => location.href })
+  return (
+    <SidebarGroup>
+      <SidebarGroupLabel>{title}</SidebarGroupLabel>
+      <SidebarMenu>
+        {items.map((item) => {
+          const key = `${item.title}-${item.url}`
+
+          if (!item.items)
+            return <SidebarMenuLink key={key} item={item} href={href} />
+
+          if (state === 'collapsed' && !isMobile)
+            return (
+              <SidebarMenuCollapsedDropdown key={key} item={item} href={href} />
+            )
+
+          return <SidebarMenuCollapsible key={key} item={item} href={href} />
+        })}
+      </SidebarMenu>
+    </SidebarGroup>
+  )
+}
+
+function NavBadge({ children }: { children: ReactNode }) {
+  return <Badge className='rounded-full px-1 py-0 text-xs'>{children}</Badge>
+}
+
+function SidebarMenuLink({ item, href }: { item: NavLink; href: string }) {
+  const { setOpenMobile } = useSidebar()
+  return (
+    <SidebarMenuItem>
+      <SidebarMenuButton
+        asChild
+        isActive={checkIsActive(href, item)}
+        tooltip={item.title}
+      >
+        <Link to={item.url} onClick={() => setOpenMobile(false)}>
+          {item.icon && <item.icon />}
+          <span>{item.title}</span>
+          {item.badge && <NavBadge>{item.badge}</NavBadge>}
+        </Link>
+      </SidebarMenuButton>
+    </SidebarMenuItem>
+  )
+}
+
+function SidebarMenuCollapsible({
+  item,
+  href,
+}: {
+  item: NavCollapsible
+  href: string
+}) {
+  const { setOpenMobile } = useSidebar()
+  return (
+    <Collapsible
+      asChild
+      defaultOpen={checkIsActive(href, item, true)}
+      className='group/collapsible'
+    >
+      <SidebarMenuItem>
+        <CollapsibleTrigger asChild>
+          <SidebarMenuButton tooltip={item.title}>
+            {item.icon && <item.icon />}
+            <span>{item.title}</span>
+            {item.badge && <NavBadge>{item.badge}</NavBadge>}
+            <ChevronRight className='ms-auto transition-transform duration-200 group-data-[state=open]/collapsible:rotate-90 rtl:rotate-180' />
+          </SidebarMenuButton>
+        </CollapsibleTrigger>
+        <CollapsibleContent className='CollapsibleContent'>
+          <SidebarMenuSub>
+            {item.items.map((subItem) => (
+              <SidebarMenuSubItem key={subItem.title}>
+                <SidebarMenuSubButton
+                  asChild
+                  isActive={checkIsActive(href, subItem)}
+                >
+                  <Link to={subItem.url} onClick={() => setOpenMobile(false)}>
+                    {subItem.icon && <subItem.icon />}
+                    <span>{subItem.title}</span>
+                    {subItem.badge && <NavBadge>{subItem.badge}</NavBadge>}
+                  </Link>
+                </SidebarMenuSubButton>
+              </SidebarMenuSubItem>
+            ))}
+          </SidebarMenuSub>
+        </CollapsibleContent>
+      </SidebarMenuItem>
+    </Collapsible>
+  )
+}
+
+function SidebarMenuCollapsedDropdown({
+  item,
+  href,
+}: {
+  item: NavCollapsible
+  href: string
+}) {
+  return (
+    <SidebarMenuItem>
+      <DropdownMenu>
+        <DropdownMenuTrigger asChild>
+          <SidebarMenuButton
+            tooltip={item.title}
+            isActive={checkIsActive(href, item)}
+          >
+            {item.icon && <item.icon />}
+            <span>{item.title}</span>
+            {item.badge && <NavBadge>{item.badge}</NavBadge>}
+            <ChevronRight className='ms-auto transition-transform duration-200 group-data-[state=open]/collapsible:rotate-90' />
+          </SidebarMenuButton>
+        </DropdownMenuTrigger>
+        <DropdownMenuContent side='right' align='start' sideOffset={4}>
+          <DropdownMenuLabel>
+            {item.title} {item.badge ? `(${item.badge})` : ''}
+          </DropdownMenuLabel>
+          <DropdownMenuSeparator />
+          {item.items.map((sub) => (
+            <DropdownMenuItem key={`${sub.title}-${sub.url}`} asChild>
+              <Link
+                to={sub.url}
+                className={`${checkIsActive(href, sub) ? 'bg-secondary' : ''}`}
+              >
+                {sub.icon && <sub.icon />}
+                <span className='max-w-52 text-wrap'>{sub.title}</span>
+                {sub.badge && (
+                  <span className='ms-auto text-xs'>{sub.badge}</span>
+                )}
+              </Link>
+            </DropdownMenuItem>
+          ))}
+        </DropdownMenuContent>
+      </DropdownMenu>
+    </SidebarMenuItem>
+  )
+}
+
+function checkIsActive(href: string, item: NavItem, mainNav = false) {
+  return (
+    href === item.url || // /endpint?search=param
+    href.split('?')[0] === item.url || // endpoint
+    !!item?.items?.filter((i) => i.url === href).length || // if child nav is active
+    (mainNav &&
+      href.split('/')[1] !== '' &&
+      href.split('/')[1] === item?.url?.split('/')[1])
+  )
+}
diff --git a/memind-ui/src/components/layout/types.ts b/memind-ui/src/components/layout/types.ts
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/components/layout/types.ts
@@ -0,0 +1,30 @@
+import { type LinkProps } from '@tanstack/react-router'
+
+type BaseNavItem = {
+  title: string
+  badge?: string
+  icon?: React.ElementType
+}
+
+type NavLink = BaseNavItem & {
+  url: LinkProps['to'] | (string & {})
+  items?: never
+}
+
+type NavCollapsible = BaseNavItem & {
+  items: (BaseNavItem & { url: LinkProps['to'] | (string & {}) })[]
+  url?: never
+}
+
+type NavItem = NavCollapsible | NavLink
+
+type NavGroup = {
+  title: string
+  items: NavItem[]
+}
+
+type SidebarData = {
+  navGroups: NavGroup[]
+}
+
+export type { SidebarData, NavGroup, NavItem, NavCollapsible, NavLink }
diff --git a/memind-ui/src/components/navigation-progress.tsx b/memind-ui/src/components/navigation-progress.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/components/navigation-progress.tsx
@@ -0,0 +1,25 @@
+import { useEffect, useRef } from 'react'
+import { useRouterState } from '@tanstack/react-router'
+import LoadingBar, { type LoadingBarRef } from 'react-top-loading-bar'
+
+export function NavigationProgress() {
+  const ref = useRef<LoadingBarRef>(null)
+  const state = useRouterState()
+
+  useEffect(() => {
+    if (state.status === 'pending') {
+      ref.current?.continuousStart()
+    } else {
+      ref.current?.complete()
+    }
+  }, [state.status])
+
+  return (
+    <LoadingBar
+      color='var(--muted-foreground)'
+      ref={ref}
+      shadow={true}
+      height={2}
+    />
+  )
+}
diff --git a/memind-ui/src/components/skip-to-main.tsx b/memind-ui/src/components/skip-to-main.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/components/skip-to-main.tsx
@@ -0,0 +1,10 @@
+export function SkipToMain() {
+  return (
+    <a
+      className={`fixed inset-s-44 z-999 -translate-y-52 bg-primary px-4 py-2 text-sm font-medium whitespace-nowrap text-primary-foreground opacity-95 shadow-sm transition hover:bg-primary/90 focus:translate-y-3 focus:transform focus-visible:ring-1 focus-visible:ring-ring`}
+      href='#content'
+    >
+      Skip to Main
+    </a>
+  )
+}
diff --git a/memind-ui/src/components/theme-switch.tsx b/memind-ui/src/components/theme-switch.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/components/theme-switch.tsx
@@ -0,0 +1,58 @@
+import { useEffect } from 'react'
+import { Check, Moon, Sun } from 'lucide-react'
+import { cn } from '@/lib/utils'
+import { useTheme } from '@/context/theme-provider'
+import { Button } from '@/components/ui/button'
+import {
+  DropdownMenu,
+  DropdownMenuContent,
+  DropdownMenuItem,
+  DropdownMenuTrigger,
+} from '@/components/ui/dropdown-menu'
+
+export function ThemeSwitch() {
+  const { theme, setTheme } = useTheme()
+
+  /* Update theme-color meta tag
+   * when theme is updated */
+  useEffect(() => {
+    const themeColor = theme === 'dark' ? '#020817' : '#fff'
+    const metaThemeColor = document.querySelector("meta[name='theme-color']")
+    if (metaThemeColor) metaThemeColor.setAttribute('content', themeColor)
+  }, [theme])
+
+  return (
+    <DropdownMenu modal={false}>
+      <DropdownMenuTrigger asChild>
+        <Button variant='ghost' size='icon' className='scale-95 rounded-full'>
+          <Sun className='size-[1.2rem] scale-100 rotate-0 transition-all dark:scale-0 dark:-rotate-90' />
+          <Moon className='absolute size-[1.2rem] scale-0 rotate-90 transition-all dark:scale-100 dark:rotate-0' />
+          <span className='sr-only'>Toggle theme</span>
+        </Button>
+      </DropdownMenuTrigger>
+      <DropdownMenuContent align='end'>
+        <DropdownMenuItem onClick={() => setTheme('light')}>
+          Light{' '}
+          <Check
+            size={14}
+            className={cn('ms-auto', theme !== 'light' && 'hidden')}
+          />
+        </DropdownMenuItem>
+        <DropdownMenuItem onClick={() => setTheme('dark')}>
+          Dark
+          <Check
+            size={14}
+            className={cn('ms-auto', theme !== 'dark' && 'hidden')}
+          />
+        </DropdownMenuItem>
+        <DropdownMenuItem onClick={() => setTheme('system')}>
+          System
+          <Check
+            size={14}
+            className={cn('ms-auto', theme !== 'system' && 'hidden')}
+          />
+        </DropdownMenuItem>
+      </DropdownMenuContent>
+    </DropdownMenu>
+  )
+}
diff --git a/memind-ui/src/components/ui/alert-dialog.tsx b/memind-ui/src/components/ui/alert-dialog.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/components/ui/alert-dialog.tsx
@@ -0,0 +1,154 @@
+import * as React from 'react'
+import * as AlertDialogPrimitive from '@radix-ui/react-alert-dialog'
+import { cn } from '@/lib/utils'
+import { buttonVariants } from '@/components/ui/button'
+
+function AlertDialog({
+  ...props
+}: React.ComponentProps<typeof AlertDialogPrimitive.Root>) {
+  return <AlertDialogPrimitive.Root data-slot='alert-dialog' {...props} />
+}
+
+function AlertDialogTrigger({
+  ...props
+}: React.ComponentProps<typeof AlertDialogPrimitive.Trigger>) {
+  return (
+    <AlertDialogPrimitive.Trigger data-slot='alert-dialog-trigger' {...props} />
+  )
+}
+
+function AlertDialogPortal({
+  ...props
+}: React.ComponentProps<typeof AlertDialogPrimitive.Portal>) {
+  return (
+    <AlertDialogPrimitive.Portal data-slot='alert-dialog-portal' {...props} />
+  )
+}
+
+function AlertDialogOverlay({
+  className,
+  ...props
+}: React.ComponentProps<typeof AlertDialogPrimitive.Overlay>) {
+  return (
+    <AlertDialogPrimitive.Overlay
+      data-slot='alert-dialog-overlay'
+      className={cn(
+        'fixed inset-0 z-50 bg-black/50 data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:animate-in data-[state=open]:fade-in-0',
+        className
+      )}
+      {...props}
+    />
+  )
+}
+
+function AlertDialogContent({
+  className,
+  ...props
+}: React.ComponentProps<typeof AlertDialogPrimitive.Content>) {
+  return (
+    <AlertDialogPortal>
+      <AlertDialogOverlay />
+      <AlertDialogPrimitive.Content
+        data-slot='alert-dialog-content'
+        className={cn(
+          'fixed top-[50%] left-[50%] z-50 grid w-full max-w-[calc(100%-2rem)] translate-x-[-50%] translate-y-[-50%] gap-4 rounded-lg border bg-background p-6 shadow-lg duration-200 data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=closed]:zoom-out-95 data-[state=open]:animate-in data-[state=open]:fade-in-0 data-[state=open]:zoom-in-95 sm:max-w-lg',
+          className
+        )}
+        {...props}
+      />
+    </AlertDialogPortal>
+  )
+}
+
+function AlertDialogHeader({
+  className,
+  ...props
+}: React.ComponentProps<'div'>) {
+  return (
+    <div
+      data-slot='alert-dialog-header'
+      className={cn('flex flex-col gap-2 text-center sm:text-start', className)}
+      {...props}
+    />
+  )
+}
+
+function AlertDialogFooter({
+  className,
+  ...props
+}: React.ComponentProps<'div'>) {
+  return (
+    <div
+      data-slot='alert-dialog-footer'
+      className={cn(
+        'flex flex-col-reverse gap-2 sm:flex-row sm:justify-end',
+        className
+      )}
+      {...props}
+    />
+  )
+}
+
+function AlertDialogTitle({
+  className,
+  ...props
+}: React.ComponentProps<typeof AlertDialogPrimitive.Title>) {
+  return (
+    <AlertDialogPrimitive.Title
+      data-slot='alert-dialog-title'
+      className={cn('text-lg font-semibold', className)}
+      {...props}
+    />
+  )
+}
+
+function AlertDialogDescription({
+  className,
+  ...props
+}: React.ComponentProps<typeof AlertDialogPrimitive.Description>) {
+  return (
+    <AlertDialogPrimitive.Description
+      data-slot='alert-dialog-description'
+      className={cn('text-sm text-muted-foreground', className)}
+      {...props}
+    />
+  )
+}
+
+function AlertDialogAction({
+  className,
+  ...props
+}: React.ComponentProps<typeof AlertDialogPrimitive.Action>) {
+  return (
+    <AlertDialogPrimitive.Action
+      className={cn(buttonVariants(), className)}
+      {...props}
+    />
+  )
+}
+
+function AlertDialogCancel({
+  className,
+  ...props
+}: React.ComponentProps<typeof AlertDialogPrimitive.Cancel>) {
+  return (
+    <AlertDialogPrimitive.Cancel
+      className={cn(buttonVariants({ variant: 'outline' }), className)}
+      {...props}
+    />
+  )
+}
+
+export {
+  AlertDialog,
+  AlertDialogPortal,
+  AlertDialogOverlay,
+  AlertDialogTrigger,
+  AlertDialogContent,
+  AlertDialogHeader,
+  AlertDialogFooter,
+  AlertDialogTitle,
+  AlertDialogDescription,
+  AlertDialogAction,
+  AlertDialogCancel,
+}
diff --git a/memind-ui/src/components/ui/alert.tsx b/memind-ui/src/components/ui/alert.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/components/ui/alert.tsx
@@ -0,0 +1,65 @@
+import * as React from 'react'
+import { cva, type VariantProps } from 'class-variance-authority'
+import { cn } from '@/lib/utils'
+
+const alertVariants = cva(
+  'relative w-full rounded-lg border px-4 py-3 text-sm grid has-[>svg]:grid-cols-[calc(var(--spacing)*4)_1fr] grid-cols-[0_1fr] has-[>svg]:gap-x-3 gap-y-0.5 items-start [&>svg]:size-4 [&>svg]:translate-y-0.5 [&>svg]:text-current',
+  {
+    variants: {
+      variant: {
+        default: 'bg-card text-card-foreground',
+        destructive:
+          'text-destructive bg-card [&>svg]:text-current *:data-[slot=alert-description]:text-destructive/90',
+      },
+    },
+    defaultVariants: {
+      variant: 'default',
+    },
+  }
+)
+
+function Alert({
+  className,
+  variant,
+  ...props
+}: React.ComponentProps<'div'> & VariantProps<typeof alertVariants>) {
+  return (
+    <div
+      data-slot='alert'
+      role='alert'
+      className={cn(alertVariants({ variant }), className)}
+      {...props}
+    />
+  )
+}
+
+function AlertTitle({ className, ...props }: React.ComponentProps<'div'>) {
+  return (
+    <div
+      data-slot='alert-title'
+      className={cn(
+        'col-start-2 line-clamp-1 min-h-4 font-medium tracking-tight',
+        className
+      )}
+      {...props}
+    />
+  )
+}
+
+function AlertDescription({
+  className,
+  ...props
+}: React.ComponentProps<'div'>) {
+  return (
+    <div
+      data-slot='alert-description'
+      className={cn(
+        'col-start-2 grid justify-items-start gap-1 text-sm text-muted-foreground [&_p]:leading-relaxed',
+        className
+      )}
+      {...props}
+    />
+  )
+}
+
+export { Alert, AlertTitle, AlertDescription }
diff --git a/memind-ui/src/components/ui/badge.tsx b/memind-ui/src/components/ui/badge.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/components/ui/badge.tsx
@@ -0,0 +1,45 @@
+import * as React from 'react'
+import { Slot } from '@radix-ui/react-slot'
+import { cva, type VariantProps } from 'class-variance-authority'
+import { cn } from '@/lib/utils'
+
+const badgeVariants = cva(
+  'inline-flex items-center justify-center rounded-md border px-2 py-0.5 text-xs font-medium w-fit whitespace-nowrap shrink-0 [&>svg]:size-3 gap-1 [&>svg]:pointer-events-none focus-visible:border-ring focus-visible:ring-ring/50 focus-visible:ring-[3px] aria-invalid:ring-destructive/20 dark:aria-invalid:ring-destructive/40 aria-invalid:border-destructive transition-[color,box-shadow] overflow-hidden',
+  {
+    variants: {
+      variant: {
+        default:
+          'border-transparent bg-primary text-primary-foreground [a&]:hover:bg-primary/90',
+        secondary:
+          'border-transparent bg-secondary text-secondary-foreground [a&]:hover:bg-secondary/90',
+        destructive:
+          'border-transparent bg-destructive text-white [a&]:hover:bg-destructive/90 focus-visible:ring-destructive/20 dark:focus-visible:ring-destructive/40 dark:bg-destructive/60',
+        outline:
+          'text-foreground [a&]:hover:bg-accent [a&]:hover:text-accent-foreground',
+      },
+    },
+    defaultVariants: {
+      variant: 'default',
+    },
+  }
+)
+
+function Badge({
+  className,
+  variant,
+  asChild = false,
+  ...props
+}: React.ComponentProps<'span'> &
+  VariantProps<typeof badgeVariants> & { asChild?: boolean }) {
+  const Comp = asChild ? Slot : 'span'
+
+  return (
+    <Comp
+      data-slot='badge'
+      className={cn(badgeVariants({ variant }), className)}
+      {...props}
+    />
+  )
+}
+
+export { Badge, badgeVariants }
diff --git a/memind-ui/src/components/ui/button.tsx b/memind-ui/src/components/ui/button.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/components/ui/button.tsx
@@ -0,0 +1,58 @@
+import * as React from 'react'
+import { Slot } from '@radix-ui/react-slot'
+import { cva, type VariantProps } from 'class-variance-authority'
+import { cn } from '@/lib/utils'
+
+const buttonVariants = cva(
+  "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-md text-sm font-medium transition-all disabled:pointer-events-none disabled:opacity-50 [&_svg]:pointer-events-none [&_svg:not([class*='size-'])]:size-4 shrink-0 [&_svg]:shrink-0 outline-none focus-visible:border-ring focus-visible:ring-ring/50 focus-visible:ring-[3px] aria-invalid:ring-destructive/20 dark:aria-invalid:ring-destructive/40 aria-invalid:border-destructive",
+  {
+    variants: {
+      variant: {
+        default:
+          'bg-primary text-primary-foreground shadow-xs hover:bg-primary/90',
+        destructive:
+          'bg-destructive text-white shadow-xs hover:bg-destructive/90 focus-visible:ring-destructive/20 dark:focus-visible:ring-destructive/40 dark:bg-destructive/60',
+        outline:
+          'border bg-background shadow-xs hover:bg-accent hover:text-accent-foreground dark:bg-input/30 dark:border-input dark:hover:bg-input/50',
+        secondary:
+          'bg-secondary text-secondary-foreground shadow-xs hover:bg-secondary/80',
+        ghost:
+          'hover:bg-accent hover:text-accent-foreground dark:hover:bg-accent/50',
+        link: 'text-primary underline-offset-4 hover:underline',
+      },
+      size: {
+        default: 'h-9 px-4 py-2 has-[>svg]:px-3',
+        sm: 'h-8 rounded-md gap-1.5 px-3 has-[>svg]:px-2.5',
+        lg: 'h-10 rounded-md px-6 has-[>svg]:px-4',
+        icon: 'size-9',
+      },
+    },
+    defaultVariants: {
+      variant: 'default',
+      size: 'default',
+    },
+  }
+)
+
+function Button({
+  className,
+  variant,
+  size,
+  asChild = false,
+  ...props
+}: React.ComponentProps<'button'> &
+  VariantProps<typeof buttonVariants> & {
+    asChild?: boolean
+  }) {
+  const Comp = asChild ? Slot : 'button'
+
+  return (
+    <Comp
+      data-slot='button'
+      className={cn(buttonVariants({ variant, size, className }))}
+      {...props}
+    />
+  )
+}
+
+export { Button, buttonVariants }
diff --git a/memind-ui/src/components/ui/card.tsx b/memind-ui/src/components/ui/card.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/components/ui/card.tsx
@@ -0,0 +1,91 @@
+import * as React from 'react'
+import { cn } from '@/lib/utils'
+
+function Card({ className, ...props }: React.ComponentProps<'div'>) {
+  return (
+    <div
+      data-slot='card'
+      className={cn(
+        'flex flex-col gap-6 rounded-xl border bg-card py-6 text-card-foreground shadow-sm',
+        className
+      )}
+      {...props}
+    />
+  )
+}
+
+function CardHeader({ className, ...props }: React.ComponentProps<'div'>) {
+  return (
+    <div
+      data-slot='card-header'
+      className={cn(
+        '@container/card-header grid auto-rows-min grid-rows-[auto_auto] items-start gap-1.5 px-6 has-data-[slot=card-action]:grid-cols-[1fr_auto] [.border-b]:pb-6',
+        className
+      )}
+      {...props}
+    />
+  )
+}
+
+function CardTitle({ className, ...props }: React.ComponentProps<'div'>) {
+  return (
+    <div
+      data-slot='card-title'
+      className={cn('leading-none font-semibold', className)}
+      {...props}
+    />
+  )
+}
+
+function CardDescription({ className, ...props }: React.ComponentProps<'div'>) {
+  return (
+    <div
+      data-slot='card-description'
+      className={cn('text-sm text-muted-foreground', className)}
+      {...props}
+    />
+  )
+}
+
+function CardAction({ className, ...props }: React.ComponentProps<'div'>) {
+  return (
+    <div
+      data-slot='card-action'
+      className={cn(
+        'col-start-2 row-span-2 row-start-1 self-start justify-self-end',
+        className
+      )}
+      {...props}
+    />
+  )
+}
+
+function CardContent({ className, ...props }: React.ComponentProps<'div'>) {
+  return (
+    <div
+      data-slot='card-content'
+      className={cn('px-6', className)}
+      {...props}
+    />
+  )
+}
+
+function CardFooter({ className, ...props }: React.ComponentProps<'div'>) {
+  return (
+    <div
+      data-slot='card-footer'
+      className={cn('flex items-center px-6 [.border-t]:pt-6', className)}
+      {...props}
+    />
+  )
+}
+
+export {
+  Card,
+  CardHeader,
+  CardFooter,
+  CardTitle,
+  CardAction,
+  CardDescription,
+  CardContent,
+}
diff --git a/memind-ui/src/components/ui/checkbox.tsx b/memind-ui/src/components/ui/checkbox.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/components/ui/checkbox.tsx
@@ -0,0 +1,29 @@
+import * as React from 'react'
+import * as CheckboxPrimitive from '@radix-ui/react-checkbox'
+import { CheckIcon } from 'lucide-react'
+import { cn } from '@/lib/utils'
+
+function Checkbox({
+  className,
+  ...props
+}: React.ComponentProps<typeof CheckboxPrimitive.Root>) {
+  return (
+    <CheckboxPrimitive.Root
+      data-slot='checkbox'
+      className={cn(
+        'peer size-4 shrink-0 rounded-lg border border-input shadow-xs transition-shadow outline-none focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50 disabled:cursor-not-allowed disabled:opacity-50 aria-invalid:border-destructive aria-invalid:ring-destructive/20 data-[state=checked]:border-primary data-[state=checked]:bg-primary data-[state=checked]:text-primary-foreground dark:bg-input/30 dark:aria-invalid:ring-destructive/40 dark:data-[state=checked]:bg-primary',
+        className
+      )}
+      {...props}
+    >
+      <CheckboxPrimitive.Indicator
+        data-slot='checkbox-indicator'
+        className='flex items-center justify-center text-current transition-none'
+      >
+        <CheckIcon className='size-3.5' />
+      </CheckboxPrimitive.Indicator>
+    </CheckboxPrimitive.Root>
+  )
+}
+
+export { Checkbox }
diff --git a/memind-ui/src/components/ui/collapsible.tsx b/memind-ui/src/components/ui/collapsible.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/components/ui/collapsible.tsx
@@ -0,0 +1,31 @@
+import * as CollapsiblePrimitive from '@radix-ui/react-collapsible'
+
+function Collapsible({
+  ...props
+}: React.ComponentProps<typeof CollapsiblePrimitive.Root>) {
+  return <CollapsiblePrimitive.Root data-slot='collapsible' {...props} />
+}
+
+function CollapsibleTrigger({
+  ...props
+}: React.ComponentProps<typeof CollapsiblePrimitive.CollapsibleTrigger>) {
+  return (
+    <CollapsiblePrimitive.CollapsibleTrigger
+      data-slot='collapsible-trigger'
+      {...props}
+    />
+  )
+}
+
+function CollapsibleContent({
+  ...props
+}: React.ComponentProps<typeof CollapsiblePrimitive.CollapsibleContent>) {
+  return (
+    <CollapsiblePrimitive.CollapsibleContent
+      data-slot='collapsible-content'
+      {...props}
+    />
+  )
+}
+
+export { Collapsible, CollapsibleTrigger, CollapsibleContent }
diff --git a/memind-ui/src/components/ui/dialog.tsx b/memind-ui/src/components/ui/dialog.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/components/ui/dialog.tsx
@@ -0,0 +1,142 @@
+'use client'
+
+import * as React from 'react'
+import * as DialogPrimitive from '@radix-ui/react-dialog'
+import { XIcon } from 'lucide-react'
+import { cn } from '@/lib/utils'
+
+function Dialog({
+  ...props
+}: React.ComponentProps<typeof DialogPrimitive.Root>) {
+  return <DialogPrimitive.Root data-slot='dialog' {...props} />
+}
+
+function DialogTrigger({
+  ...props
+}: React.ComponentProps<typeof DialogPrimitive.Trigger>) {
+  return <DialogPrimitive.Trigger data-slot='dialog-trigger' {...props} />
+}
+
+function DialogPortal({
+  ...props
+}: React.ComponentProps<typeof DialogPrimitive.Portal>) {
+  return <DialogPrimitive.Portal data-slot='dialog-portal' {...props} />
+}
+
+function DialogClose({
+  ...props
+}: React.ComponentProps<typeof DialogPrimitive.Close>) {
+  return <DialogPrimitive.Close data-slot='dialog-close' {...props} />
+}
+
+function DialogOverlay({
+  className,
+  ...props
+}: React.ComponentProps<typeof DialogPrimitive.Overlay>) {
+  return (
+    <DialogPrimitive.Overlay
+      data-slot='dialog-overlay'
+      className={cn(
+        'fixed inset-0 z-50 bg-black/50 data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:animate-in data-[state=open]:fade-in-0',
+        className
+      )}
+      {...props}
+    />
+  )
+}
+
+function DialogContent({
+  className,
+  children,
+  showCloseButton = true,
+  ...props
+}: React.ComponentProps<typeof DialogPrimitive.Content> & {
+  showCloseButton?: boolean
+}) {
+  return (
+    <DialogPortal data-slot='dialog-portal'>
+      <DialogOverlay />
+      <DialogPrimitive.Content
+        data-slot='dialog-content'
+        className={cn(
+          'fixed top-[50%] left-[50%] z-50 grid w-full max-w-[calc(100%-2rem)] translate-x-[-50%] translate-y-[-50%] gap-4 rounded-lg border bg-background p-6 shadow-lg duration-200 data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=closed]:zoom-out-95 data-[state=open]:animate-in data-[state=open]:fade-in-0 data-[state=open]:zoom-in-95 sm:max-w-lg',
+          className
+        )}
+        {...props}
+      >
+        {children}
+        {showCloseButton && (
+          <DialogPrimitive.Close
+            data-slot='dialog-close'
+            className="absolute inset-e-4 top-4 rounded-xs opacity-70 ring-offset-background transition-opacity hover:opacity-100 focus:ring-2 focus:ring-ring focus:ring-offset-2 focus:outline-hidden disabled:pointer-events-none data-[state=open]:bg-accent data-[state=open]:text-muted-foreground [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4"
+          >
+            <XIcon />
+            <span className='sr-only'>Close</span>
+          </DialogPrimitive.Close>
+        )}
+      </DialogPrimitive.Content>
+    </DialogPortal>
+  )
+}
+
+function DialogHeader({ className, ...props }: React.ComponentProps<'div'>) {
+  return (
+    <div
+      data-slot='dialog-header'
+      className={cn('flex flex-col gap-2 text-center sm:text-start', className)}
+      {...props}
+    />
+  )
+}
+
+function DialogFooter({ className, ...props }: React.ComponentProps<'div'>) {
+  return (
+    <div
+      data-slot='dialog-footer'
+      className={cn(
+        'flex flex-col-reverse gap-2 sm:flex-row sm:justify-end',
+        className
+      )}
+      {...props}
+    />
+  )
+}
+
+function DialogTitle({
+  className,
+  ...props
+}: React.ComponentProps<typeof DialogPrimitive.Title>) {
+  return (
+    <DialogPrimitive.Title
+      data-slot='dialog-title'
+      className={cn('text-lg leading-none font-semibold', className)}
+      {...props}
+    />
+  )
+}
+
+function DialogDescription({
+  className,
+  ...props
+}: React.ComponentProps<typeof DialogPrimitive.Description>) {
+  return (
+    <DialogPrimitive.Description
+      data-slot='dialog-description'
+      className={cn('text-sm text-muted-foreground', className)}
+      {...props}
+    />
+  )
+}
+
+export {
+  Dialog,
+  DialogClose,
+  DialogContent,
+  DialogDescription,
+  DialogFooter,
+  DialogHeader,
+  DialogOverlay,
+  DialogPortal,
+  DialogTitle,
+  DialogTrigger,
+}
diff --git a/memind-ui/src/components/ui/dropdown-menu.tsx b/memind-ui/src/components/ui/dropdown-menu.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/components/ui/dropdown-menu.tsx
@@ -0,0 +1,254 @@
+import * as React from 'react'
+import * as DropdownMenuPrimitive from '@radix-ui/react-dropdown-menu'
+import { CheckIcon, ChevronRightIcon, CircleIcon } from 'lucide-react'
+import { cn } from '@/lib/utils'
+
+function DropdownMenu({
+  ...props
+}: React.ComponentProps<typeof DropdownMenuPrimitive.Root>) {
+  return <DropdownMenuPrimitive.Root data-slot='dropdown-menu' {...props} />
+}
+
+function DropdownMenuPortal({
+  ...props
+}: React.ComponentProps<typeof DropdownMenuPrimitive.Portal>) {
+  return (
+    <DropdownMenuPrimitive.Portal data-slot='dropdown-menu-portal' {...props} />
+  )
+}
+
+function DropdownMenuTrigger({
+  ...props
+}: React.ComponentProps<typeof DropdownMenuPrimitive.Trigger>) {
+  return (
+    <DropdownMenuPrimitive.Trigger
+      data-slot='dropdown-menu-trigger'
+      {...props}
+    />
+  )
+}
+
+function DropdownMenuContent({
+  className,
+  sideOffset = 4,
+  ...props
+}: React.ComponentProps<typeof DropdownMenuPrimitive.Content>) {
+  return (
+    <DropdownMenuPrimitive.Portal>
+      <DropdownMenuPrimitive.Content
+        data-slot='dropdown-menu-content'
+        sideOffset={sideOffset}
+        className={cn(
+          'z-50 max-h-(--radix-dropdown-menu-content-available-height) min-w-32 origin-(--radix-dropdown-menu-content-transform-origin) overflow-x-hidden overflow-y-auto rounded-md border bg-popover p-1 text-popover-foreground shadow-md data-[side=bottom]:slide-in-from-top-2 data-[side=left]:slide-in-from-right-2 data-[side=right]:slide-in-from-left-2 data-[side=top]:slide-in-from-bottom-2 data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=closed]:zoom-out-95 data-[state=open]:animate-in data-[state=open]:fade-in-0 data-[state=open]:zoom-in-95',
+          className
+        )}
+        {...props}
+      />
+    </DropdownMenuPrimitive.Portal>
+  )
+}
+
+function DropdownMenuGroup({
+  ...props
+}: React.ComponentProps<typeof DropdownMenuPrimitive.Group>) {
+  return (
+    <DropdownMenuPrimitive.Group data-slot='dropdown-menu-group' {...props} />
+  )
+}
+
+function DropdownMenuItem({
+  className,
+  inset,
+  variant = 'default',
+  ...props
+}: React.ComponentProps<typeof DropdownMenuPrimitive.Item> & {
+  inset?: boolean
+  variant?: 'default' | 'destructive'
+}) {
+  return (
+    <DropdownMenuPrimitive.Item
+      data-slot='dropdown-menu-item'
+      data-inset={inset}
+      data-variant={variant}
+      className={cn(
+        "relative flex cursor-default items-center gap-2 rounded-sm px-2 py-1.5 text-sm outline-hidden select-none focus:bg-accent focus:text-accent-foreground data-disabled:pointer-events-none data-disabled:opacity-50 data-inset:ps-8 data-[variant=destructive]:text-destructive data-[variant=destructive]:focus:bg-destructive/10 data-[variant=destructive]:focus:text-destructive dark:data-[variant=destructive]:focus:bg-destructive/20 [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4 [&_svg:not([class*='text-'])]:text-muted-foreground data-[variant=destructive]:*:[svg]:text-destructive!",
+        className
+      )}
+      {...props}
+    />
+  )
+}
+
+function DropdownMenuCheckboxItem({
+  className,
+  children,
+  checked,
+  ...props
+}: React.ComponentProps<typeof DropdownMenuPrimitive.CheckboxItem>) {
+  return (
+    <DropdownMenuPrimitive.CheckboxItem
+      data-slot='dropdown-menu-checkbox-item'
+      className={cn(
+        "relative flex cursor-default items-center gap-2 rounded-sm py-1.5 ps-8 pe-2 text-sm outline-hidden select-none focus:bg-accent focus:text-accent-foreground data-disabled:pointer-events-none data-disabled:opacity-50 [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4",
+        className
+      )}
+      checked={checked}
+      {...props}
+    >
+      <span className='pointer-events-none absolute inset-s-2 flex size-3.5 items-center justify-center'>
+        <DropdownMenuPrimitive.ItemIndicator>
+          <CheckIcon className='size-4' />
+        </DropdownMenuPrimitive.ItemIndicator>
+      </span>
+      {children}
+    </DropdownMenuPrimitive.CheckboxItem>
+  )
+}
+
+function DropdownMenuRadioGroup({
+  ...props
+}: React.ComponentProps<typeof DropdownMenuPrimitive.RadioGroup>) {
+  return (
+    <DropdownMenuPrimitive.RadioGroup
+      data-slot='dropdown-menu-radio-group'
+      {...props}
+    />
+  )
+}
+
+function DropdownMenuRadioItem({
+  className,
+  children,
+  ...props
+}: React.ComponentProps<typeof DropdownMenuPrimitive.RadioItem>) {
+  return (
+    <DropdownMenuPrimitive.RadioItem
+      data-slot='dropdown-menu-radio-item'
+      className={cn(
+        "relative flex cursor-default items-center gap-2 rounded-sm py-1.5 ps-8 pe-2 text-sm outline-hidden select-none focus:bg-accent focus:text-accent-foreground data-disabled:pointer-events-none data-disabled:opacity-50 [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4",
+        className
+      )}
+      {...props}
+    >
+      <span className='pointer-events-none absolute inset-s-2 flex size-3.5 items-center justify-center'>
+        <DropdownMenuPrimitive.ItemIndicator>
+          <CircleIcon className='size-2 fill-current' />
+        </DropdownMenuPrimitive.ItemIndicator>
+      </span>
+      {children}
+    </DropdownMenuPrimitive.RadioItem>
+  )
+}
+
+function DropdownMenuLabel({
+  className,
+  inset,
+  ...props
+}: React.ComponentProps<typeof DropdownMenuPrimitive.Label> & {
+  inset?: boolean
+}) {
+  return (
+    <DropdownMenuPrimitive.Label
+      data-slot='dropdown-menu-label'
+      data-inset={inset}
+      className={cn(
+        'px-2 py-1.5 text-sm font-medium data-inset:ps-8',
+        className
+      )}
+      {...props}
+    />
+  )
+}
+
+function DropdownMenuSeparator({
+  className,
+  ...props
+}: React.ComponentProps<typeof DropdownMenuPrimitive.Separator>) {
+  return (
+    <DropdownMenuPrimitive.Separator
+      data-slot='dropdown-menu-separator'
+      className={cn('-mx-1 my-1 h-px bg-border', className)}
+      {...props}
+    />
+  )
+}
+
+function DropdownMenuShortcut({
+  className,
+  ...props
+}: React.ComponentProps<'span'>) {
+  return (
+    <span
+      data-slot='dropdown-menu-shortcut'
+      className={cn(
+        'ms-auto text-xs tracking-widest text-muted-foreground',
+        className
+      )}
+      {...props}
+    />
+  )
+}
+
+function DropdownMenuSub({
+  ...props
+}: React.ComponentProps<typeof DropdownMenuPrimitive.Sub>) {
+  return <DropdownMenuPrimitive.Sub data-slot='dropdown-menu-sub' {...props} />
+}
+
+function DropdownMenuSubTrigger({
+  className,
+  inset,
+  children,
+  ...props
+}: React.ComponentProps<typeof DropdownMenuPrimitive.SubTrigger> & {
+  inset?: boolean
+}) {
+  return (
+    <DropdownMenuPrimitive.SubTrigger
+      data-slot='dropdown-menu-sub-trigger'
+      data-inset={inset}
+      className={cn(
+        'flex cursor-default items-center rounded-sm px-2 py-1.5 text-sm outline-hidden select-none focus:bg-accent focus:text-accent-foreground data-inset:ps-8 data-[state=open]:bg-accent data-[state=open]:text-accent-foreground',
+        className
+      )}
+      {...props}
+    >
+      {children}
+      <ChevronRightIcon className='ms-auto size-4' />
+    </DropdownMenuPrimitive.SubTrigger>
+  )
+}
+
+function DropdownMenuSubContent({
+  className,
+  ...props
+}: React.ComponentProps<typeof DropdownMenuPrimitive.SubContent>) {
+  return (
+    <DropdownMenuPrimitive.SubContent
+      data-slot='dropdown-menu-sub-content'
+      className={cn(
+        'z-50 min-w-32 origin-(--radix-dropdown-menu-content-transform-origin) overflow-hidden rounded-md border bg-popover p-1 text-popover-foreground shadow-lg data-[side=bottom]:slide-in-from-top-2 data-[side=left]:slide-in-from-right-2 data-[side=right]:slide-in-from-left-2 data-[side=top]:slide-in-from-bottom-2 data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=closed]:zoom-out-95 data-[state=open]:animate-in data-[state=open]:fade-in-0 data-[state=open]:zoom-in-95',
+        className
+      )}
+      {...props}
+    />
+  )
+}
+
+export {
+  DropdownMenu,
+  DropdownMenuPortal,
+  DropdownMenuTrigger,
+  DropdownMenuContent,
+  DropdownMenuGroup,
+  DropdownMenuLabel,
+  DropdownMenuItem,
+  DropdownMenuCheckboxItem,
+  DropdownMenuRadioGroup,
+  DropdownMenuRadioItem,
+  DropdownMenuSeparator,
+  DropdownMenuShortcut,
+  DropdownMenuSub,
+  DropdownMenuSubTrigger,
+  DropdownMenuSubContent,
+}
diff --git a/memind-ui/src/components/ui/input.tsx b/memind-ui/src/components/ui/input.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/components/ui/input.tsx
@@ -0,0 +1,20 @@
+import * as React from 'react'
+import { cn } from '@/lib/utils'
+
+function Input({ className, type, ...props }: React.ComponentProps<'input'>) {
+  return (
+    <input
+      type={type}
+      data-slot='input'
+      className={cn(
+        'flex h-9 w-full min-w-0 rounded-md border border-input bg-transparent px-3 py-1 text-base shadow-xs transition-[color,box-shadow] outline-none selection:bg-primary selection:text-primary-foreground file:inline-flex file:h-7 file:border-0 file:bg-transparent file:text-sm file:font-medium file:text-foreground placeholder:text-muted-foreground disabled:pointer-events-none disabled:cursor-not-allowed disabled:opacity-50 md:text-sm dark:bg-input/30',
+        'focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50',
+        'aria-invalid:border-destructive aria-invalid:ring-destructive/20 dark:aria-invalid:ring-destructive/40',
+        className
+      )}
+      {...props}
+    />
+  )
+}
+
+export { Input }
diff --git a/memind-ui/src/components/ui/label.tsx b/memind-ui/src/components/ui/label.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/components/ui/label.tsx
@@ -0,0 +1,23 @@
+'use client'
+
+import * as React from 'react'
+import * as LabelPrimitive from '@radix-ui/react-label'
+import { cn } from '@/lib/utils'
+
+function Label({
+  className,
+  ...props
+}: React.ComponentProps<typeof LabelPrimitive.Root>) {
+  return (
+    <LabelPrimitive.Root
+      data-slot='label'
+      className={cn(
+        'flex items-center gap-2 text-sm leading-none font-medium select-none group-data-[disabled=true]:pointer-events-none group-data-[disabled=true]:opacity-50 peer-disabled:cursor-not-allowed peer-disabled:opacity-50',
+        className
+      )}
+      {...props}
+    />
+  )
+}
+
+export { Label }
diff --git a/memind-ui/src/components/ui/separator.tsx b/memind-ui/src/components/ui/separator.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/components/ui/separator.tsx
@@ -0,0 +1,25 @@
+import * as React from 'react'
+import * as SeparatorPrimitive from '@radix-ui/react-separator'
+import { cn } from '@/lib/utils'
+
+function Separator({
+  className,
+  orientation = 'horizontal',
+  decorative = true,
+  ...props
+}: React.ComponentProps<typeof SeparatorPrimitive.Root>) {
+  return (
+    <SeparatorPrimitive.Root
+      data-slot='separator'
+      decorative={decorative}
+      orientation={orientation}
+      className={cn(
+        'shrink-0 bg-border data-[orientation=horizontal]:h-px data-[orientation=horizontal]:w-full data-[orientation=vertical]:w-px',
+        className
+      )}
+      {...props}
+    />
+  )
+}
+
+export { Separator }
diff --git a/memind-ui/src/components/ui/sheet.tsx b/memind-ui/src/components/ui/sheet.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/components/ui/sheet.tsx
@@ -0,0 +1,136 @@
+import * as React from 'react'
+import * as SheetPrimitive from '@radix-ui/react-dialog'
+import { XIcon } from 'lucide-react'
+import { cn } from '@/lib/utils'
+
+function Sheet({ ...props }: React.ComponentProps<typeof SheetPrimitive.Root>) {
+  return <SheetPrimitive.Root data-slot='sheet' {...props} />
+}
+
+function SheetTrigger({
+  ...props
+}: React.ComponentProps<typeof SheetPrimitive.Trigger>) {
+  return <SheetPrimitive.Trigger data-slot='sheet-trigger' {...props} />
+}
+
+function SheetClose({
+  ...props
+}: React.ComponentProps<typeof SheetPrimitive.Close>) {
+  return <SheetPrimitive.Close data-slot='sheet-close' {...props} />
+}
+
+function SheetPortal({
+  ...props
+}: React.ComponentProps<typeof SheetPrimitive.Portal>) {
+  return <SheetPrimitive.Portal data-slot='sheet-portal' {...props} />
+}
+
+function SheetOverlay({
+  className,
+  ...props
+}: React.ComponentProps<typeof SheetPrimitive.Overlay>) {
+  return (
+    <SheetPrimitive.Overlay
+      data-slot='sheet-overlay'
+      className={cn(
+        'fixed inset-0 z-50 bg-black/50 data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:animate-in data-[state=open]:fade-in-0',
+        className
+      )}
+      {...props}
+    />
+  )
+}
+
+function SheetContent({
+  className,
+  children,
+  side = 'right',
+  ...props
+}: React.ComponentProps<typeof SheetPrimitive.Content> & {
+  side?: 'top' | 'right' | 'bottom' | 'left'
+}) {
+  return (
+    <SheetPortal>
+      <SheetOverlay />
+      <SheetPrimitive.Content
+        data-slot='sheet-content'
+        className={cn(
+          'fixed z-50 flex flex-col gap-4 bg-background shadow-lg transition ease-in-out data-[state=closed]:animate-out data-[state=closed]:duration-300 data-[state=open]:animate-in data-[state=open]:duration-500',
+          side === 'right' &&
+            'inset-y-0 inset-e-0 h-full w-3/4 border-s data-[state=closed]:slide-out-to-end data-[state=open]:slide-in-from-end sm:max-w-sm',
+          side === 'left' &&
+            'inset-y-0 inset-s-0 h-full w-3/4 border-e data-[state=closed]:slide-out-to-start data-[state=open]:slide-in-from-start sm:max-w-sm',
+          side === 'top' &&
+            'inset-x-0 top-0 h-auto border-b data-[state=closed]:slide-out-to-top data-[state=open]:slide-in-from-top',
+          side === 'bottom' &&
+            'inset-x-0 bottom-0 h-auto border-t data-[state=closed]:slide-out-to-bottom data-[state=open]:slide-in-from-bottom',
+          className
+        )}
+        {...props}
+      >
+        {children}
+        <SheetPrimitive.Close className='absolute inset-e-4 top-4 rounded-xs opacity-70 ring-offset-background transition-opacity hover:opacity-100 focus:ring-2 focus:ring-ring focus:ring-offset-2 focus:outline-hidden disabled:pointer-events-none data-[state=open]:bg-secondary'>
+          <XIcon className='size-4' />
+          <span className='sr-only'>Close</span>
+        </SheetPrimitive.Close>
+      </SheetPrimitive.Content>
+    </SheetPortal>
+  )
+}
+
+function SheetHeader({ className, ...props }: React.ComponentProps<'div'>) {
+  return (
+    <div
+      data-slot='sheet-header'
+      className={cn('flex flex-col gap-1.5 p-4', className)}
+      {...props}
+    />
+  )
+}
+
+function SheetFooter({ className, ...props }: React.ComponentProps<'div'>) {
+  return (
+    <div
+      data-slot='sheet-footer'
+      className={cn('mt-auto flex flex-col gap-2 p-4', className)}
+      {...props}
+    />
+  )
+}
+
+function SheetTitle({
+  className,
+  ...props
+}: React.ComponentProps<typeof SheetPrimitive.Title>) {
+  return (
+    <SheetPrimitive.Title
+      data-slot='sheet-title'
+      className={cn('font-semibold text-foreground', className)}
+      {...props}
+    />
+  )
+}
+
+function SheetDescription({
+  className,
+  ...props
+}: React.ComponentProps<typeof SheetPrimitive.Description>) {
+  return (
+    <SheetPrimitive.Description
+      data-slot='sheet-description'
+      className={cn('text-sm text-muted-foreground', className)}
+      {...props}
+    />
+  )
+}
+
+export {
+  Sheet,
+  SheetTrigger,
+  SheetClose,
+  SheetContent,
+  SheetHeader,
+  SheetFooter,
+  SheetTitle,
+  SheetDescription,
+}
diff --git a/memind-ui/src/components/ui/sidebar.tsx b/memind-ui/src/components/ui/sidebar.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/components/ui/sidebar.tsx
@@ -0,0 +1,728 @@
+import * as React from 'react'
+import { Slot } from '@radix-ui/react-slot'
+import { VariantProps, cva } from 'class-variance-authority'
+import { PanelLeftIcon } from 'lucide-react'
+import { cn } from '@/lib/utils'
+import { useIsMobile } from '@/hooks/use-mobile'
+import { Button } from '@/components/ui/button'
+import { Input } from '@/components/ui/input'
+import { Separator } from '@/components/ui/separator'
+import {
+  Sheet,
+  SheetContent,
+  SheetDescription,
+  SheetHeader,
+  SheetTitle,
+} from '@/components/ui/sheet'
+import { Skeleton } from '@/components/ui/skeleton'
+import {
+  Tooltip,
+  TooltipContent,
+  TooltipProvider,
+  TooltipTrigger,
+} from '@/components/ui/tooltip'
+
+const SIDEBAR_COOKIE_NAME = 'sidebar_state'
+const SIDEBAR_COOKIE_MAX_AGE = 60 * 60 * 24 * 7
+const SIDEBAR_WIDTH = '16rem'
+const SIDEBAR_WIDTH_MOBILE = '18rem'
+const SIDEBAR_WIDTH_ICON = '3rem'
+const SIDEBAR_KEYBOARD_SHORTCUT = 'b'
+
+type SidebarContextProps = {
+  state: 'expanded' | 'collapsed'
+  open: boolean
+  setOpen: (open: boolean) => void
+  openMobile: boolean
+  setOpenMobile: (open: boolean) => void
+  isMobile: boolean
+  toggleSidebar: () => void
+}
+
+const SidebarContext = React.createContext<SidebarContextProps | null>(null)
+
+function useSidebar() {
+  const context = React.useContext(SidebarContext)
+  if (!context) {
+    throw new Error('useSidebar must be used within a SidebarProvider.')
+  }
+
+  return context
+}
+
+function SidebarProvider({
+  defaultOpen = true,
+  open: openProp,
+  onOpenChange: setOpenProp,
+  className,
+  style,
+  children,
+  ...props
+}: React.ComponentProps<'div'> & {
+  defaultOpen?: boolean
+  open?: boolean
+  onOpenChange?: (open: boolean) => void
+}) {
+  const isMobile = useIsMobile()
+  const [openMobile, setOpenMobile] = React.useState(false)
+
+  // This is the internal state of the sidebar.
+  // We use openProp and setOpenProp for control from outside the component.
+  const [_open, _setOpen] = React.useState(defaultOpen)
+  const open = openProp ?? _open
+  const setOpen = React.useCallback(
+    (value: boolean | ((value: boolean) => boolean)) => {
+      const openState = typeof value === 'function' ? value(open) : value
+      if (setOpenProp) {
+        setOpenProp(openState)
+      } else {
+        _setOpen(openState)
+      }
+
+      // This sets the cookie to keep the sidebar state.
+      document.cookie = `${SIDEBAR_COOKIE_NAME}=${openState}; path=/; max-age=${SIDEBAR_COOKIE_MAX_AGE}`
+    },
+    [setOpenProp, open]
+  )
+
+  // Helper to toggle the sidebar.
+  const toggleSidebar = React.useCallback(() => {
+    return isMobile ? setOpenMobile((open) => !open) : setOpen((open) => !open)
+  }, [isMobile, setOpen, setOpenMobile])
+
+  // Adds a keyboard shortcut to toggle the sidebar.
+  React.useEffect(() => {
+    const handleKeyDown = (event: KeyboardEvent) => {
+      if (
+        event.key === SIDEBAR_KEYBOARD_SHORTCUT &&
+        (event.metaKey || event.ctrlKey)
+      ) {
+        event.preventDefault()
+        toggleSidebar()
+      }
+    }
+
+    window.addEventListener('keydown', handleKeyDown)
+    return () => window.removeEventListener('keydown', handleKeyDown)
+  }, [toggleSidebar])
+
+  // We add a state so that we can do data-state="expanded" or "collapsed".
+  // This makes it easier to style the sidebar with Tailwind classes.
+  const state = open ? 'expanded' : 'collapsed'
+
+  const contextValue = React.useMemo<SidebarContextProps>(
+    () => ({
+      state,
+      open,
+      setOpen,
+      isMobile,
+      openMobile,
+      setOpenMobile,
+      toggleSidebar,
+    }),
+    [state, open, setOpen, isMobile, openMobile, setOpenMobile, toggleSidebar]
+  )
+
+  return (
+    <SidebarContext.Provider value={contextValue}>
+      <TooltipProvider delayDuration={0}>
+        <div
+          data-slot='sidebar-wrapper'
+          style={
+            {
+              '--sidebar-width': SIDEBAR_WIDTH,
+              '--sidebar-width-icon': SIDEBAR_WIDTH_ICON,
+              ...style,
+            } as React.CSSProperties
+          }
+          className={cn(
+            'group/sidebar-wrapper flex min-h-svh w-full has-data-[variant=inset]:bg-sidebar',
+            className
+          )}
+          {...props}
+        >
+          {children}
+        </div>
+      </TooltipProvider>
+    </SidebarContext.Provider>
+  )
+}
+
+function Sidebar({
+  side = 'left',
+  variant = 'sidebar',
+  collapsible = 'offcanvas',
+  className,
+  children,
+  ...props
+}: React.ComponentProps<'div'> & {
+  side?: 'left' | 'right'
+  variant?: 'sidebar' | 'floating' | 'inset'
+  collapsible?: 'offcanvas' | 'icon' | 'none'
+}) {
+  const { isMobile, state, openMobile, setOpenMobile } = useSidebar()
+
+  if (collapsible === 'none') {
+    return (
+      <div
+        data-slot='sidebar'
+        className={cn(
+          'flex h-full w-(--sidebar-width) flex-col bg-sidebar text-sidebar-foreground',
+          className
+        )}
+        {...props}
+      >
+        {children}
+      </div>
+    )
+  }
+
+  if (isMobile) {
+    return (
+      <Sheet open={openMobile} onOpenChange={setOpenMobile} {...props}>
+        <SheetContent
+          data-sidebar='sidebar'
+          data-slot='sidebar'
+          data-mobile='true'
+          className='w-(--sidebar-width) bg-sidebar p-0 text-sidebar-foreground [&>button]:hidden'
+          style={
+            {
+              '--sidebar-width': SIDEBAR_WIDTH_MOBILE,
+            } as React.CSSProperties
+          }
+          side={side}
+        >
+          <SheetHeader className='sr-only'>
+            <SheetTitle>Sidebar</SheetTitle>
+            <SheetDescription>Displays the mobile sidebar.</SheetDescription>
+          </SheetHeader>
+          <div className='flex h-full w-full flex-col'>{children}</div>
+        </SheetContent>
+      </Sheet>
+    )
+  }
+
+  return (
+    <div
+      className='group peer hidden text-sidebar-foreground md:block'
+      data-state={state}
+      data-collapsible={state === 'collapsed' ? collapsible : ''}
+      data-variant={variant}
+      data-side={side}
+      data-slot='sidebar'
+    >
+      {/* This is what handles the sidebar gap on desktop */}
+      <div
+        data-slot='sidebar-gap'
+        className={cn(
+          'relative w-(--sidebar-width) bg-transparent transition-[width] duration-200 ease-linear',
+          'group-data-[collapsible=offcanvas]:w-0',
+          'group-data-[side=right]:rotate-180',
+          variant === 'floating' || variant === 'inset'
+            ? 'group-data-[collapsible=icon]:w-[calc(var(--sidebar-width-icon)+(--spacing(4)))]'
+            : 'group-data-[collapsible=icon]:w-(--sidebar-width-icon)'
+        )}
+      />
+      <div
+        data-slot='sidebar-container'
+        className={cn(
+          'fixed inset-y-0 z-10 hidden h-svh w-(--sidebar-width) transition-[inset-inline,width] duration-200 ease-linear md:flex',
+          side === 'left'
+            ? 'inset-s-0 group-data-[collapsible=offcanvas]:-inset-s-[calc(var(--sidebar-width))]'
+            : 'inset-e-0 group-data-[collapsible=offcanvas]:-inset-e-[calc(var(--sidebar-width))]',
+          // Adjust the padding for floating and inset variants.
+          variant === 'floating' || variant === 'inset'
+            ? 'p-2 group-data-[collapsible=icon]:w-[calc(var(--sidebar-width-icon)+(--spacing(4))+2px)]'
+            : 'group-data-[collapsible=icon]:w-(--sidebar-width-icon) group-data-[side=left]:border-e group-data-[side=right]:border-s',
+          className
+        )}
+        {...props}
+      >
+        <div
+          data-sidebar='sidebar'
+          data-slot='sidebar-inner'
+          className='flex h-full w-full flex-col bg-sidebar group-data-[variant=floating]:rounded-lg group-data-[variant=floating]:border group-data-[variant=floating]:border-sidebar-border group-data-[variant=floating]:shadow-sm'
+        >
+          {children}
+        </div>
+      </div>
+    </div>
+  )
+}
+
+function SidebarTrigger({
+  className,
+  onClick,
+  ...props
+}: React.ComponentProps<typeof Button>) {
+  const { toggleSidebar } = useSidebar()
+
+  return (
+    <Button
+      data-sidebar='trigger'
+      data-slot='sidebar-trigger'
+      variant='ghost'
+      size='icon'
+      className={cn('size-7', className)}
+      onClick={(event) => {
+        onClick?.(event)
+        toggleSidebar()
+      }}
+      {...props}
+    >
+      <PanelLeftIcon />
+      <span className='sr-only'>Toggle Sidebar</span>
+    </Button>
+  )
+}
+
+function SidebarRail({ className, ...props }: React.ComponentProps<'button'>) {
+  const { toggleSidebar } = useSidebar()
+
+  return (
+    <button
+      data-sidebar='rail'
+      data-slot='sidebar-rail'
+      aria-label='Toggle Sidebar'
+      tabIndex={-1}
+      onClick={toggleSidebar}
+      title='Toggle Sidebar'
+      className={cn(
+        'absolute inset-y-0 z-20 hidden w-4 -translate-x-1/2 transition-all ease-linear group-data-[side=left]:-inset-e-4 group-data-[side=right]:inset-s-0 after:absolute after:inset-y-0 after:inset-s-1/2 after:w-0.5 hover:after:bg-sidebar-border sm:flex',
+        'in-data-[side=left]:cursor-w-resize in-data-[side=right]:cursor-e-resize',
+        '[[data-side=left][data-state=collapsed]_&]:cursor-e-resize [[data-side=right][data-state=collapsed]_&]:cursor-w-resize',
+        'group-data-[collapsible=offcanvas]:translate-x-0 group-data-[collapsible=offcanvas]:after:start-full hover:group-data-[collapsible=offcanvas]:bg-sidebar',
+        '[[data-side=left][data-collapsible=offcanvas]_&]:-inset-e-2',
+        '[[data-side=right][data-collapsible=offcanvas]_&]:-inset-s-2',
+
+        // RTL support
+        'rtl:translate-x-1/2',
+        'rtl:in-data-[side=left]:cursor-e-resize rtl:in-data-[side=right]:cursor-w-resize',
+        'rtl:[[data-side=left][data-state=collapsed]_&]:cursor-w-resize rtl:[[data-side=right][data-state=collapsed]_&]:cursor-e-resize',
+        className
+      )}
+      {...props}
+    />
+  )
+}
+
+function SidebarInset({ className, ...props }: React.ComponentProps<'div'>) {
+  return (
+    <div
+      data-slot='sidebar-inset'
+      className={cn(
+        'relative flex w-full flex-1 flex-col bg-background',
+        'md:peer-data-[variant=inset]:m-2 md:peer-data-[variant=inset]:ms-0 md:peer-data-[variant=inset]:rounded-xl md:peer-data-[variant=inset]:shadow-sm md:peer-data-[variant=inset]:peer-data-[state=collapsed]:ms-2',
+        className
+      )}
+      {...props}
+    />
+  )
+}
+
+function SidebarInput({
+  className,
+  ...props
+}: React.ComponentProps<typeof Input>) {
+  return (
+    <Input
+      data-slot='sidebar-input'
+      data-sidebar='input'
+      className={cn('h-8 w-full bg-background shadow-none', className)}
+      {...props}
+    />
+  )
+}
+
+function SidebarHeader({ className, ...props }: React.ComponentProps<'div'>) {
+  return (
+    <div
+      data-slot='sidebar-header'
+      data-sidebar='header'
+      className={cn('flex flex-col gap-2 p-2', className)}
+      {...props}
+    />
+  )
+}
+
+function SidebarFooter({ className, ...props }: React.ComponentProps<'div'>) {
+  return (
+    <div
+      data-slot='sidebar-footer'
+      data-sidebar='footer'
+      className={cn('flex flex-col gap-2 p-2', className)}
+      {...props}
+    />
+  )
+}
+
+function SidebarSeparator({
+  className,
+  ...props
+}: React.ComponentProps<typeof Separator>) {
+  return (
+    <Separator
+      data-slot='sidebar-separator'
+      data-sidebar='separator'
+      className={cn('mx-2 w-auto bg-sidebar-border', className)}
+      {...props}
+    />
+  )
+}
+
+function SidebarContent({ className, ...props }: React.ComponentProps<'div'>) {
+  return (
+    <div
+      data-slot='sidebar-content'
+      data-sidebar='content'
+      className={cn(
+        'flex min-h-0 flex-1 flex-col gap-2 overflow-auto group-data-[collapsible=icon]:overflow-hidden',
+        className
+      )}
+      {...props}
+    />
+  )
+}
+
+function SidebarGroup({ className, ...props }: React.ComponentProps<'div'>) {
+  return (
+    <div
+      data-slot='sidebar-group'
+      data-sidebar='group'
+      className={cn('relative flex w-full min-w-0 flex-col p-2', className)}
+      {...props}
+    />
+  )
+}
+
+function SidebarGroupLabel({
+  className,
+  asChild = false,
+  ...props
+}: React.ComponentProps<'div'> & { asChild?: boolean }) {
+  const Comp = asChild ? Slot : 'div'
+
+  return (
+    <Comp
+      data-slot='sidebar-group-label'
+      data-sidebar='group-label'
+      className={cn(
+        'flex h-8 shrink-0 items-center rounded-md px-2 text-xs font-medium text-sidebar-foreground/70 ring-sidebar-ring outline-hidden transition-[margin,opacity] duration-200 ease-linear focus-visible:ring-2 [&>svg]:size-4 [&>svg]:shrink-0',
+        'group-data-[collapsible=icon]:-mt-8 group-data-[collapsible=icon]:opacity-0',
+        className
+      )}
+      {...props}
+    />
+  )
+}
+
+function SidebarGroupAction({
+  className,
+  asChild = false,
+  ...props
+}: React.ComponentProps<'button'> & { asChild?: boolean }) {
+  const Comp = asChild ? Slot : 'button'
+
+  return (
+    <Comp
+      data-slot='sidebar-group-action'
+      data-sidebar='group-action'
+      className={cn(
+        'absolute inset-e-3 top-3.5 flex aspect-square w-5 items-center justify-center rounded-md p-0 text-sidebar-foreground ring-sidebar-ring outline-hidden transition-transform hover:bg-sidebar-accent hover:text-sidebar-accent-foreground focus-visible:ring-2 [&>svg]:size-4 [&>svg]:shrink-0',
+        // Increases the hit area of the button on mobile.
+        'after:absolute after:-inset-2 md:after:hidden',
+        'group-data-[collapsible=icon]:hidden',
+        className
+      )}
+      {...props}
+    />
+  )
+}
+
+function SidebarGroupContent({
+  className,
+  ...props
+}: React.ComponentProps<'div'>) {
+  return (
+    <div
+      data-slot='sidebar-group-content'
+      data-sidebar='group-content'
+      className={cn('w-full text-sm', className)}
+      {...props}
+    />
+  )
+}
+
+function SidebarMenu({ className, ...props }: React.ComponentProps<'ul'>) {
+  return (
+    <ul
+      data-slot='sidebar-menu'
+      data-sidebar='menu'
+      className={cn('flex w-full min-w-0 flex-col gap-1', className)}
+      {...props}
+    />
+  )
+}
+
+function SidebarMenuItem({ className, ...props }: React.ComponentProps<'li'>) {
+  return (
+    <li
+      data-slot='sidebar-menu-item'
+      data-sidebar='menu-item'
+      className={cn('group/menu-item relative', className)}
+      {...props}
+    />
+  )
+}
+
+const sidebarMenuButtonVariants = cva(
+  'peer/menu-button flex w-full items-center gap-2 overflow-hidden rounded-md p-2 text-start text-sm outline-hidden ring-sidebar-ring transition-[width,height,padding] hover:bg-sidebar-accent hover:text-sidebar-accent-foreground focus-visible:ring-2 active:bg-sidebar-accent active:text-sidebar-accent-foreground disabled:pointer-events-none disabled:opacity-50 group-has-data-[sidebar=menu-action]/menu-item:pe-8 aria-disabled:pointer-events-none aria-disabled:opacity-50 data-[active=true]:bg-sidebar-accent data-[active=true]:font-medium data-[active=true]:text-sidebar-accent-foreground data-[state=open]:hover:bg-sidebar-accent data-[state=open]:hover:text-sidebar-accent-foreground group-data-[collapsible=icon]:size-8! group-data-[collapsible=icon]:p-2! [&>span:last-child]:truncate [&>svg]:size-4 [&>svg]:shrink-0',
+  {
+    variants: {
+      variant: {
+        default: 'hover:bg-sidebar-accent hover:text-sidebar-accent-foreground',
+        outline:
+          'bg-background shadow-[0_0_0_1px_hsl(var(--sidebar-border))] hover:bg-sidebar-accent hover:text-sidebar-accent-foreground hover:shadow-[0_0_0_1px_hsl(var(--sidebar-accent))]',
+      },
+      size: {
+        default: 'h-8 text-sm',
+        sm: 'h-7 text-xs',
+        lg: 'h-12 text-sm group-data-[collapsible=icon]:p-0!',
+      },
+    },
+    defaultVariants: {
+      variant: 'default',
+      size: 'default',
+    },
+  }
+)
+
+function SidebarMenuButton({
+  asChild = false,
+  isActive = false,
+  variant = 'default',
+  size = 'default',
+  tooltip,
+  className,
+  ...props
+}: React.ComponentProps<'button'> & {
+  asChild?: boolean
+  isActive?: boolean
+  tooltip?: string | React.ComponentProps<typeof TooltipContent>
+} & VariantProps<typeof sidebarMenuButtonVariants>) {
+  const Comp = asChild ? Slot : 'button'
+  const { isMobile, state } = useSidebar()
+
+  const button = (
+    <Comp
+      data-slot='sidebar-menu-button'
+      data-sidebar='menu-button'
+      data-size={size}
+      data-active={isActive}
+      className={cn(sidebarMenuButtonVariants({ variant, size }), className)}
+      {...props}
+    />
+  )
+
+  if (!tooltip) {
+    return button
+  }
+
+  if (typeof tooltip === 'string') {
+    tooltip = {
+      children: tooltip,
+    }
+  }
+
+  return (
+    <Tooltip>
+      <TooltipTrigger asChild>{button}</TooltipTrigger>
+      <TooltipContent
+        side='right'
+        align='center'
+        hidden={state !== 'collapsed' || isMobile}
+        {...tooltip}
+      />
+    </Tooltip>
+  )
+}
+
+function SidebarMenuAction({
+  className,
+  asChild = false,
+  showOnHover = false,
+  ...props
+}: React.ComponentProps<'button'> & {
+  asChild?: boolean
+  showOnHover?: boolean
+}) {
+  const Comp = asChild ? Slot : 'button'
+
+  return (
+    <Comp
+      data-slot='sidebar-menu-action'
+      data-sidebar='menu-action'
+      className={cn(
+        'absolute inset-e-1 top-1.5 flex aspect-square w-5 items-center justify-center rounded-md p-0 text-sidebar-foreground ring-sidebar-ring outline-hidden transition-transform peer-hover/menu-button:text-sidebar-accent-foreground hover:bg-sidebar-accent hover:text-sidebar-accent-foreground focus-visible:ring-2 [&>svg]:size-4 [&>svg]:shrink-0',
+        // Increases the hit area of the button on mobile.
+        'after:absolute after:-inset-2 md:after:hidden',
+        'peer-data-[size=sm]/menu-button:top-1',
+        'peer-data-[size=default]/menu-button:top-1.5',
+        'peer-data-[size=lg]/menu-button:top-2.5',
+        'group-data-[collapsible=icon]:hidden',
+        showOnHover &&
+          'group-focus-within/menu-item:opacity-100 group-hover/menu-item:opacity-100 peer-data-[active=true]/menu-button:text-sidebar-accent-foreground data-[state=open]:opacity-100 md:opacity-0',
+        className
+      )}
+      {...props}
+    />
+  )
+}
+
+function SidebarMenuBadge({
+  className,
+  ...props
+}: React.ComponentProps<'div'>) {
+  return (
+    <div
+      data-slot='sidebar-menu-badge'
+      data-sidebar='menu-badge'
+      className={cn(
+        'pointer-events-none absolute inset-e-1 flex h-5 min-w-5 items-center justify-center rounded-md px-1 text-xs font-medium text-sidebar-foreground tabular-nums select-none',
+        'peer-hover/menu-button:text-sidebar-accent-foreground peer-data-[active=true]/menu-button:text-sidebar-accent-foreground',
+        'peer-data-[size=sm]/menu-button:top-1',
+        'peer-data-[size=default]/menu-button:top-1.5',
+        'peer-data-[size=lg]/menu-button:top-2.5',
+        'group-data-[collapsible=icon]:hidden',
+        className
+      )}
+      {...props}
+    />
+  )
+}
+
+function SidebarMenuSkeleton({
+  className,
+  showIcon = false,
+  ...props
+}: React.ComponentProps<'div'> & {
+  showIcon?: boolean
+}) {
+  // Random width between 50 to 90%.
+  const width = React.useMemo(() => {
+    return `${Math.floor(Math.random() * 40) + 50}%`
+  }, [])
+
+  return (
+    <div
+      data-slot='sidebar-menu-skeleton'
+      data-sidebar='menu-skeleton'
+      className={cn('flex h-8 items-center gap-2 rounded-md px-2', className)}
+      {...props}
+    >
+      {showIcon && (
+        <Skeleton
+          className='size-4 rounded-md'
+          data-sidebar='menu-skeleton-icon'
+        />
+      )}
+      <Skeleton
+        className='h-4 max-w-(--skeleton-width) flex-1'
+        data-sidebar='menu-skeleton-text'
+        style={
+          {
+            '--skeleton-width': width,
+          } as React.CSSProperties
+        }
+      />
+    </div>
+  )
+}
+
+function SidebarMenuSub({ className, ...props }: React.ComponentProps<'ul'>) {
+  return (
+    <ul
+      data-slot='sidebar-menu-sub'
+      data-sidebar='menu-sub'
+      className={cn(
+        'mx-3.5 flex min-w-0 translate-x-px flex-col gap-1 border-s border-sidebar-border px-2.5 py-0.5',
+        'group-data-[collapsible=icon]:hidden',
+        className
+      )}
+      {...props}
+    />
+  )
+}
+
+function SidebarMenuSubItem({
+  className,
+  ...props
+}: React.ComponentProps<'li'>) {
+  return (
+    <li
+      data-slot='sidebar-menu-sub-item'
+      data-sidebar='menu-sub-item'
+      className={cn('group/menu-sub-item relative', className)}
+      {...props}
+    />
+  )
+}
+
+function SidebarMenuSubButton({
+  asChild = false,
+  size = 'md',
+  isActive = false,
+  className,
+  ...props
+}: React.ComponentProps<'a'> & {
+  asChild?: boolean
+  size?: 'sm' | 'md'
+  isActive?: boolean
+}) {
+  const Comp = asChild ? Slot : 'a'
+
+  return (
+    <Comp
+      data-slot='sidebar-menu-sub-button'
+      data-sidebar='menu-sub-button'
+      data-size={size}
+      data-active={isActive}
+      className={cn(
+        'flex h-7 min-w-0 -translate-x-px items-center gap-2 overflow-hidden rounded-md px-2 text-sidebar-foreground ring-sidebar-ring outline-hidden hover:bg-sidebar-accent hover:text-sidebar-accent-foreground focus-visible:ring-2 active:bg-sidebar-accent active:text-sidebar-accent-foreground disabled:pointer-events-none disabled:opacity-50 aria-disabled:pointer-events-none aria-disabled:opacity-50 [&>span:last-child]:truncate [&>svg]:size-4 [&>svg]:shrink-0 [&>svg]:text-inherit',
+        'data-[active=true]:bg-sidebar-accent data-[active=true]:text-sidebar-accent-foreground',
+        size === 'sm' && 'text-xs',
+        size === 'md' && 'text-sm',
+        'group-data-[collapsible=icon]:hidden',
+        className
+      )}
+      {...props}
+    />
+  )
+}
+
+export {
+  Sidebar,
+  SidebarContent,
+  SidebarFooter,
+  SidebarGroup,
+  SidebarGroupAction,
+  SidebarGroupContent,
+  SidebarGroupLabel,
+  SidebarHeader,
+  SidebarInput,
+  SidebarInset,
+  SidebarMenu,
+  SidebarMenuAction,
+  SidebarMenuBadge,
+  SidebarMenuButton,
+  SidebarMenuItem,
+  SidebarMenuSkeleton,
+  SidebarMenuSub,
+  SidebarMenuSubButton,
+  SidebarMenuSubItem,
+  SidebarProvider,
+  SidebarRail,
+  SidebarSeparator,
+  SidebarTrigger,
+  useSidebar,
+}
diff --git a/memind-ui/src/components/ui/skeleton.tsx b/memind-ui/src/components/ui/skeleton.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/components/ui/skeleton.tsx
@@ -0,0 +1,13 @@
+import { cn } from '@/lib/utils'
+
+function Skeleton({ className, ...props }: React.ComponentProps<'div'>) {
+  return (
+    <div
+      data-slot='skeleton'
+      className={cn('animate-pulse rounded-md bg-accent', className)}
+      {...props}
+    />
+  )
+}
+
+export { Skeleton }
diff --git a/memind-ui/src/components/ui/sonner.tsx b/memind-ui/src/components/ui/sonner.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/components/ui/sonner.tsx
@@ -0,0 +1,21 @@
+import { Toaster as Sonner, ToasterProps } from 'sonner'
+import { useTheme } from '@/context/theme-provider'
+
+export function Toaster({ ...props }: ToasterProps) {
+  const { theme = 'system' } = useTheme()
+
+  return (
+    <Sonner
+      theme={theme as ToasterProps['theme']}
+      className='toaster group [&_div[data-content]]:w-full'
+      style={
+        {
+          '--normal-bg': 'var(--popover)',
+          '--normal-text': 'var(--popover-foreground)',
+          '--normal-border': 'var(--border)',
+        } as React.CSSProperties
+      }
+      {...props}
+    />
+  )
+}
diff --git a/memind-ui/src/components/ui/switch.tsx b/memind-ui/src/components/ui/switch.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/components/ui/switch.tsx
@@ -0,0 +1,28 @@
+import * as React from 'react'
+import * as SwitchPrimitive from '@radix-ui/react-switch'
+import { cn } from '@/lib/utils'
+
+function Switch({
+  className,
+  ...props
+}: React.ComponentProps<typeof SwitchPrimitive.Root>) {
+  return (
+    <SwitchPrimitive.Root
+      data-slot='switch'
+      className={cn(
+        'peer inline-flex h-[1.15rem] w-8 shrink-0 items-center rounded-full border border-transparent shadow-xs transition-all outline-none focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50 disabled:cursor-not-allowed disabled:opacity-50 data-[state=checked]:bg-primary data-[state=unchecked]:bg-input dark:data-[state=unchecked]:bg-input/80',
+        className
+      )}
+      {...props}
+    >
+      <SwitchPrimitive.Thumb
+        data-slot='switch-thumb'
+        className={cn(
+          'pointer-events-none block size-4 rounded-full bg-background ring-0 transition-transform data-[state=checked]:translate-x-[calc(100%-2px)] data-[state=unchecked]:translate-x-0 rtl:data-[state=checked]:-translate-x-[calc(100%-2px)] dark:data-[state=checked]:bg-primary-foreground dark:data-[state=unchecked]:bg-foreground'
+        )}
+      />
+    </SwitchPrimitive.Root>
+  )
+}
+
+export { Switch }
diff --git a/memind-ui/src/components/ui/table.tsx b/memind-ui/src/components/ui/table.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/components/ui/table.tsx
@@ -0,0 +1,113 @@
+import * as React from 'react'
+import { cn } from '@/lib/utils'
+
+function Table({ className, ...props }: React.ComponentProps<'table'>) {
+  return (
+    <div
+      data-slot='table-container'
+      className='relative w-full overflow-x-auto'
+    >
+      <table
+        data-slot='table'
+        className={cn('w-full caption-bottom text-sm', className)}
+        {...props}
+      />
+    </div>
+  )
+}
+
+function TableHeader({ className, ...props }: React.ComponentProps<'thead'>) {
+  return (
+    <thead
+      data-slot='table-header'
+      className={cn('[&_tr]:border-b', className)}
+      {...props}
+    />
+  )
+}
+
+function TableBody({ className, ...props }: React.ComponentProps<'tbody'>) {
+  return (
+    <tbody
+      data-slot='table-body'
+      className={cn('[&_tr:last-child]:border-0', className)}
+      {...props}
+    />
+  )
+}
+
+function TableFooter({ className, ...props }: React.ComponentProps<'tfoot'>) {
+  return (
+    <tfoot
+      data-slot='table-footer'
+      className={cn(
+        'border-t bg-muted/50 font-medium [&>tr]:last:border-b-0',
+        className
+      )}
+      {...props}
+    />
+  )
+}
+
+function TableRow({ className, ...props }: React.ComponentProps<'tr'>) {
+  return (
+    <tr
+      data-slot='table-row'
+      className={cn(
+        'border-b transition-colors hover:bg-muted/50 data-[state=selected]:bg-muted',
+        className
+      )}
+      {...props}
+    />
+  )
+}
+
+function TableHead({ className, ...props }: React.ComponentProps<'th'>) {
+  return (
+    <th
+      data-slot='table-head'
+      className={cn(
+        'h-10 px-2 text-start align-middle font-medium whitespace-nowrap text-foreground *:[[role=checkbox]]:translate-y-0.5',
+        className
+      )}
+      {...props}
+    />
+  )
+}
+
+function TableCell({ className, ...props }: React.ComponentProps<'td'>) {
+  return (
+    <td
+      data-slot='table-cell'
+      className={cn(
+        'p-2 align-middle whitespace-nowrap *:[[role=checkbox]]:translate-y-0.5',
+        className
+      )}
+      {...props}
+    />
+  )
+}
+
+function TableCaption({
+  className,
+  ...props
+}: React.ComponentProps<'caption'>) {
+  return (
+    <caption
+      data-slot='table-caption'
+      className={cn('mt-4 text-sm text-muted-foreground', className)}
+      {...props}
+    />
+  )
+}
+
+export {
+  Table,
+  TableHeader,
+  TableBody,
+  TableFooter,
+  TableHead,
+  TableRow,
+  TableCell,
+  TableCaption,
+}
diff --git a/memind-ui/src/components/ui/tabs.tsx b/memind-ui/src/components/ui/tabs.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/components/ui/tabs.tsx
@@ -0,0 +1,63 @@
+import * as React from 'react'
+import * as TabsPrimitive from '@radix-ui/react-tabs'
+import { cn } from '@/lib/utils'
+
+function Tabs({
+  className,
+  ...props
+}: React.ComponentProps<typeof TabsPrimitive.Root>) {
+  return (
+    <TabsPrimitive.Root
+      data-slot='tabs'
+      className={cn('flex flex-col gap-2', className)}
+      {...props}
+    />
+  )
+}
+
+function TabsList({
+  className,
+  ...props
+}: React.ComponentProps<typeof TabsPrimitive.List>) {
+  return (
+    <TabsPrimitive.List
+      data-slot='tabs-list'
+      className={cn(
+        'inline-flex h-9 w-fit items-center justify-center rounded-lg bg-muted p-0.75 text-muted-foreground',
+        className
+      )}
+      {...props}
+    />
+  )
+}
+
+function TabsTrigger({
+  className,
+  ...props
+}: React.ComponentProps<typeof TabsPrimitive.Trigger>) {
+  return (
+    <TabsPrimitive.Trigger
+      data-slot='tabs-trigger'
+      className={cn(
+        "inline-flex h-[calc(100%-1px)] flex-1 items-center justify-center gap-1.5 rounded-md border border-transparent px-2 py-1 text-sm font-medium whitespace-nowrap text-foreground transition-[color,box-shadow] focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50 focus-visible:outline-1 focus-visible:outline-ring disabled:pointer-events-none disabled:opacity-50 data-[state=active]:bg-background data-[state=active]:shadow-sm dark:text-muted-foreground dark:data-[state=active]:border-input dark:data-[state=active]:bg-input/30 dark:data-[state=active]:text-foreground [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4",
+        className
+      )}
+      {...props}
+    />
+  )
+}
+
+function TabsContent({
+  className,
+  ...props
+}: React.ComponentProps<typeof TabsPrimitive.Content>) {
+  return (
+    <TabsPrimitive.Content
+      data-slot='tabs-content'
+      className={cn('flex-1 outline-none', className)}
+      {...props}
+    />
+  )
+}
+
+export { Tabs, TabsList, TabsTrigger, TabsContent }
diff --git a/memind-ui/src/components/ui/textarea.tsx b/memind-ui/src/components/ui/textarea.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/components/ui/textarea.tsx
@@ -0,0 +1,17 @@
+import * as React from 'react'
+import { cn } from '@/lib/utils'
+
+function Textarea({ className, ...props }: React.ComponentProps<'textarea'>) {
+  return (
+    <textarea
+      data-slot='textarea'
+      className={cn(
+        'flex field-sizing-content min-h-16 w-full rounded-md border border-input bg-transparent px-3 py-2 text-base shadow-xs transition-[color,box-shadow] outline-none placeholder:text-muted-foreground focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50 disabled:cursor-not-allowed disabled:opacity-50 aria-invalid:border-destructive aria-invalid:ring-destructive/20 md:text-sm dark:bg-input/30 dark:aria-invalid:ring-destructive/40',
+        className
+      )}
+      {...props}
+    />
+  )
+}
+
+export { Textarea }
diff --git a/memind-ui/src/components/ui/tooltip.tsx b/memind-ui/src/components/ui/tooltip.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/components/ui/tooltip.tsx
@@ -0,0 +1,60 @@
+'use client'
+
+import * as React from 'react'
+import * as TooltipPrimitive from '@radix-ui/react-tooltip'
+import { cn } from '@/lib/utils'
+
+function TooltipProvider({
+  delayDuration = 0,
+  ...props
+}: React.ComponentProps<typeof TooltipPrimitive.Provider>) {
+  return (
+    <TooltipPrimitive.Provider
+      data-slot='tooltip-provider'
+      delayDuration={delayDuration}
+      {...props}
+    />
+  )
+}
+
+function Tooltip({
+  ...props
+}: React.ComponentProps<typeof TooltipPrimitive.Root>) {
+  return (
+    <TooltipProvider>
+      <TooltipPrimitive.Root data-slot='tooltip' {...props} />
+    </TooltipProvider>
+  )
+}
+
+function TooltipTrigger({
+  ...props
+}: React.ComponentProps<typeof TooltipPrimitive.Trigger>) {
+  return <TooltipPrimitive.Trigger data-slot='tooltip-trigger' {...props} />
+}
+
+function TooltipContent({
+  className,
+  sideOffset = 0,
+  children,
+  ...props
+}: React.ComponentProps<typeof TooltipPrimitive.Content>) {
+  return (
+    <TooltipPrimitive.Portal>
+      <TooltipPrimitive.Content
+        data-slot='tooltip-content'
+        sideOffset={sideOffset}
+        className={cn(
+          'z-50 w-fit origin-(--radix-tooltip-content-transform-origin) animate-in rounded-md bg-primary px-3 py-1.5 text-xs text-balance text-primary-foreground fade-in-0 zoom-in-95 data-[side=bottom]:slide-in-from-top-2 data-[side=left]:slide-in-from-right-2 data-[side=right]:slide-in-from-left-2 data-[side=top]:slide-in-from-bottom-2 data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=closed]:zoom-out-95',
+          className
+        )}
+        {...props}
+      >
+        {children}
+        <TooltipPrimitive.Arrow className='z-50 size-2.5 translate-y-[calc(-50%-2px)] rotate-45 rounded-[2px] bg-primary fill-primary' />
+      </TooltipPrimitive.Content>
+    </TooltipPrimitive.Portal>
+  )
+}
+
+export { Tooltip, TooltipTrigger, TooltipContent, TooltipProvider }
diff --git a/memind-ui/src/context/direction-provider.tsx b/memind-ui/src/context/direction-provider.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/context/direction-provider.tsx
@@ -0,0 +1,21 @@
+import { useEffect, useState } from 'react'
+import { DirectionProvider as RdxDirProvider } from '@radix-ui/react-direction'
+import { getCookie } from '@/lib/cookies'
+
+type Direction = 'ltr' | 'rtl'
+
+const DEFAULT_DIRECTION = 'ltr'
+const DIRECTION_COOKIE_NAME = 'dir'
+
+export function DirectionProvider({ children }: { children: React.ReactNode }) {
+  const [dir] = useState<Direction>(
+    () => (getCookie(DIRECTION_COOKIE_NAME) as Direction) || DEFAULT_DIRECTION
+  )
+
+  useEffect(() => {
+    const htmlElement = document.documentElement
+    htmlElement.setAttribute('dir', dir)
+  }, [dir])
+
+  return <RdxDirProvider dir={dir}>{children}</RdxDirProvider>
+}
diff --git a/memind-ui/src/context/theme-provider.tsx b/memind-ui/src/context/theme-provider.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/context/theme-provider.tsx
@@ -0,0 +1,110 @@
+import { createContext, useContext, useEffect, useState, useMemo } from 'react'
+import { getCookie, setCookie, removeCookie } from '@/lib/cookies'
+
+type Theme = 'dark' | 'light' | 'system'
+type ResolvedTheme = Exclude<Theme, 'system'>
+
+const DEFAULT_THEME = 'system'
+const THEME_COOKIE_NAME = 'vite-ui-theme'
+const THEME_COOKIE_MAX_AGE = 60 * 60 * 24 * 365 // 1 year
+
+type ThemeProviderProps = {
+  children: React.ReactNode
+  defaultTheme?: Theme
+  storageKey?: string
+}
+
+type ThemeProviderState = {
+  defaultTheme: Theme
+  resolvedTheme: ResolvedTheme
+  theme: Theme
+  setTheme: (theme: Theme) => void
+  resetTheme: () => void
+}
+
+const initialState: ThemeProviderState = {
+  defaultTheme: DEFAULT_THEME,
+  resolvedTheme: 'light',
+  theme: DEFAULT_THEME,
+  setTheme: () => null,
+  resetTheme: () => null,
+}
+
+const ThemeContext = createContext<ThemeProviderState>(initialState)
+
+export function ThemeProvider({
+  children,
+  defaultTheme = DEFAULT_THEME,
+  storageKey = THEME_COOKIE_NAME,
+  ...props
+}: ThemeProviderProps) {
+  const [theme, _setTheme] = useState<Theme>(
+    () => (getCookie(storageKey) as Theme) || defaultTheme
+  )
+
+  // Optimized: Memoize the resolved theme calculation to prevent unnecessary re-computations
+  const resolvedTheme = useMemo((): ResolvedTheme => {
+    if (theme === 'system') {
+      return window.matchMedia('(prefers-color-scheme: dark)').matches
+        ? 'dark'
+        : 'light'
+    }
+    return theme as ResolvedTheme
+  }, [theme])
+
+  useEffect(() => {
+    const root = window.document.documentElement
+    const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)')
+
+    const applyTheme = (currentResolvedTheme: ResolvedTheme) => {
+      root.classList.remove('light', 'dark') // Remove existing theme classes
+      root.classList.add(currentResolvedTheme) // Add the new theme class
+    }
+
+    const handleChange = () => {
+      if (theme === 'system') {
+        const systemTheme = mediaQuery.matches ? 'dark' : 'light'
+        applyTheme(systemTheme)
+      }
+    }
+
+    applyTheme(resolvedTheme)
+
+    mediaQuery.addEventListener('change', handleChange)
+
+    return () => mediaQuery.removeEventListener('change', handleChange)
+  }, [theme, resolvedTheme])
+
+  const setTheme = (theme: Theme) => {
+    setCookie(storageKey, theme, THEME_COOKIE_MAX_AGE)
+    _setTheme(theme)
+  }
+
+  const resetTheme = () => {
+    removeCookie(storageKey)
+    _setTheme(DEFAULT_THEME)
+  }
+
+  const contextValue = {
+    defaultTheme,
+    resolvedTheme,
+    resetTheme,
+    theme,
+    setTheme,
+  }
+
+  return (
+    <ThemeContext value={contextValue} {...props}>
+      {children}
+    </ThemeContext>
+  )
+}
+
+// eslint-disable-next-line react-refresh/only-export-components
+export const useTheme = () => {
+  const context = useContext(ThemeContext)
+
+  if (!context) throw new Error('useTheme must be used within a ThemeProvider')
+
+  return context
+}
diff --git a/memind-ui/src/features/api/buffers.ts b/memind-ui/src/features/api/buffers.ts
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/api/buffers.ts
@@ -0,0 +1,101 @@
+import { apiDelete, apiGet, apiPatch, type PageResult } from '@/lib/api-client'
+import type {
+  AdminIdsRequest,
+  AdminUpdateResult,
+  BatchDeleteResult,
+  ConversationBufferView,
+  InsightBufferBuiltUpdateRequest,
+  InsightBufferGroupUpdateRequest,
+  InsightBufferGroupView,
+  InsightBufferView,
+} from '@/features/types'
+import type { MemoryIdFilter, PageParams } from './common'
+
+export type ConversationBufferState = 'pending' | 'extracted' | 'all'
+export type InsightBufferState =
+  | 'unbuilt'
+  | 'ungrouped'
+  | 'grouped'
+  | 'built'
+  | 'all'
+
+export type ConversationBufferListParams = PageParams &
+  MemoryIdFilter & {
+    sessionId?: string
+    state?: ConversationBufferState
+  }
+
+export type InsightBufferListParams = PageParams &
+  MemoryIdFilter & {
+    insightTypeName?: string
+    state?: InsightBufferState
+  }
+
+type InsightBufferGroupParams = MemoryIdFilter & {
+  insightTypeName?: string
+}
+
+export function listConversationBuffers(
+  params: ConversationBufferListParams = {}
+) {
+  return apiGet<PageResult<ConversationBufferView>>(
+    '/admin/v1/buffers/conversations',
+    params
+  )
+}
+
+export function getConversationBuffer(id: number) {
+  return apiGet<ConversationBufferView>(
+    `/admin/v1/buffers/conversations/${id}`
+  )
+}
+
+export function markConversationsExtracted(ids: number[]) {
+  return apiPatch<AdminUpdateResult>(
+    '/admin/v1/buffers/conversations/extracted',
+    { ids }
+  )
+}
+
+export function deleteConversationBuffers(ids: number[]) {
+  return apiDelete<BatchDeleteResult>('/admin/v1/buffers/conversations', {
+    ids,
+  })
+}
+
+export function listInsightBuffers(params: InsightBufferListParams = {}) {
+  return apiGet<PageResult<InsightBufferView>>(
+    '/admin/v1/buffers/insights',
+    params
+  )
+}
+
+export function listInsightBufferGroups(params: InsightBufferGroupParams = {}) {
+  return apiGet<InsightBufferGroupView[]>(
+    '/admin/v1/buffers/insights/groups',
+    params
+  )
+}
+
+export function updateInsightBufferGroup(
+  request: InsightBufferGroupUpdateRequest
+) {
+  return apiPatch<AdminUpdateResult>(
+    '/admin/v1/buffers/insights/group',
+    request
+  )
+}
+
+export function updateInsightBufferBuilt(
+  request: InsightBufferBuiltUpdateRequest
+) {
+  return apiPatch<AdminUpdateResult>(
+    '/admin/v1/buffers/insights/built',
+    request
+  )
+}
+
+export function deleteInsightBuffers(ids: number[]) {
+  const body: AdminIdsRequest = { ids }
+  return apiDelete<BatchDeleteResult>('/admin/v1/buffers/insights', body)
+}
diff --git a/memind-ui/src/features/api/common.ts b/memind-ui/src/features/api/common.ts
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/api/common.ts
@@ -0,0 +1,13 @@
+export type PageParams = {
+  pageNo?: number
+  pageSize?: number
+}
+
+export type MemoryIdFilter = {
+  memoryId?: string
+}
+
+export type UserAgentFilter = {
+  userId?: string
+  agentId?: string
+}
diff --git a/memind-ui/src/features/api/config.ts b/memind-ui/src/features/api/config.ts
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/api/config.ts
@@ -0,0 +1,15 @@
+import { apiGet, apiPut } from '@/lib/api-client'
+import type {
+  MemoryOptionsGetResponse,
+  MemoryOptionsPutRequest,
+} from '@/features/types'
+
+const CONFIG_PATH = '/admin/v1/config/memory-options'
+
+export function getMemoryOptions() {
+  return apiGet<MemoryOptionsGetResponse>(CONFIG_PATH)
+}
+
+export function updateMemoryOptions(request: MemoryOptionsPutRequest) {
+  return apiPut<MemoryOptionsGetResponse>(CONFIG_PATH, request)
+}
diff --git a/memind-ui/src/features/api/dashboard.ts b/memind-ui/src/features/api/dashboard.ts
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/api/dashboard.ts
@@ -0,0 +1,11 @@
+import { apiGet } from '@/lib/api-client'
+import type { AdminDashboardView } from '@/features/types'
+import type { MemoryIdFilter } from './common'
+
+type DashboardParams = MemoryIdFilter & {
+  days?: number
+}
+
+export function getDashboard(params: DashboardParams = {}) {
+  return apiGet<AdminDashboardView>('/admin/v1/dashboard', params)
+}
diff --git a/memind-ui/src/features/api/insights.ts b/memind-ui/src/features/api/insights.ts
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/api/insights.ts
@@ -0,0 +1,27 @@
+import { apiDelete, apiGet, type PageResult } from '@/lib/api-client'
+import type {
+  AdminInsightView,
+  BatchDeleteResult,
+  InsightDeleteRequest,
+} from '@/features/types'
+import type { PageParams, UserAgentFilter } from './common'
+
+export type InsightListParams = PageParams &
+  UserAgentFilter & {
+    scope?: string
+    type?: string
+    tier?: string
+  }
+
+export function listInsights(params: InsightListParams = {}) {
+  return apiGet<PageResult<AdminInsightView>>('/admin/v1/insights', params)
+}
+
+export function getInsight(insightId: number) {
+  return apiGet<AdminInsightView>(`/admin/v1/insights/${insightId}`)
+}
+
+export function deleteInsights(insightIds: number[]) {
+  const body: InsightDeleteRequest = { insightIds }
+  return apiDelete<BatchDeleteResult>('/admin/v1/insights', body)
+}
diff --git a/memind-ui/src/features/api/item-graph.ts b/memind-ui/src/features/api/item-graph.ts
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/api/item-graph.ts
@@ -0,0 +1,135 @@
+import { apiDelete, apiGet, type PageResult } from '@/lib/api-client'
+import type {
+  AdminGraphEntityDeleteResult,
+  BatchDeleteResult,
+  GraphAliasView,
+  GraphBatchView,
+  GraphCooccurrenceView,
+  GraphEntityDeleteRequest,
+  GraphEntityDetailView,
+  GraphEntityView,
+  GraphIdsRequest,
+  GraphItemLinkView,
+  GraphMentionView,
+  ItemGraphSummaryView,
+} from '@/features/types'
+import type { MemoryIdFilter, PageParams } from './common'
+
+export type GraphBatchState = 'PENDING' | 'COMMITTED' | 'REPAIR_REQUIRED'
+
+type GraphEntityListParams = PageParams &
+  MemoryIdFilter & {
+    entityType?: string
+    q?: string
+  }
+
+type GraphAliasListParams = PageParams &
+  MemoryIdFilter & {
+    entityKey?: string
+    q?: string
+  }
+
+type GraphMentionListParams = PageParams &
+  MemoryIdFilter & {
+    itemId?: number
+    entityKey?: string
+  }
+
+type GraphItemLinkListParams = PageParams &
+  MemoryIdFilter & {
+    itemId?: number
+    linkType?: string
+    evidenceSource?: string
+  }
+
+type GraphCooccurrenceListParams = PageParams &
+  MemoryIdFilter & {
+    entityKey?: string
+  }
+
+type GraphBatchListParams = PageParams &
+  MemoryIdFilter & {
+    state?: GraphBatchState
+  }
+
+export function getItemGraphSummary(params: MemoryIdFilter = {}) {
+  return apiGet<ItemGraphSummaryView>('/admin/v1/item-graph/summary', params)
+}
+
+export function listGraphEntities(params: GraphEntityListParams = {}) {
+  return apiGet<PageResult<GraphEntityView>>(
+    '/admin/v1/item-graph/entities',
+    params
+  )
+}
+
+export function getGraphEntity(id: number) {
+  return apiGet<GraphEntityDetailView>(`/admin/v1/item-graph/entities/${id}`)
+}
+
+export function deleteGraphEntities(request: GraphEntityDeleteRequest) {
+  return apiDelete<AdminGraphEntityDeleteResult>(
+    '/admin/v1/item-graph/entities',
+    request
+  )
+}
+
+export function listGraphAliases(params: GraphAliasListParams = {}) {
+  return apiGet<PageResult<GraphAliasView>>(
+    '/admin/v1/item-graph/aliases',
+    params
+  )
+}
+
+export function deleteGraphAliases(ids: number[]) {
+  const body: GraphIdsRequest = { ids }
+  return apiDelete<BatchDeleteResult>('/admin/v1/item-graph/aliases', body)
+}
+
+export function listGraphMentions(params: GraphMentionListParams = {}) {
+  return apiGet<PageResult<GraphMentionView>>(
+    '/admin/v1/item-graph/mentions',
+    params
+  )
+}
+
+export function deleteGraphMentions(ids: number[]) {
+  const body: GraphIdsRequest = { ids }
+  return apiDelete<BatchDeleteResult>('/admin/v1/item-graph/mentions', body)
+}
+
+export function listGraphItemLinks(params: GraphItemLinkListParams = {}) {
+  return apiGet<PageResult<GraphItemLinkView>>(
+    '/admin/v1/item-graph/item-links',
+    params
+  )
+}
+
+export function deleteGraphItemLinks(ids: number[]) {
+  const body: GraphIdsRequest = { ids }
+  return apiDelete<BatchDeleteResult>('/admin/v1/item-graph/item-links', body)
+}
+
+export function listGraphCooccurrences(
+  params: GraphCooccurrenceListParams = {}
+) {
+  return apiGet<PageResult<GraphCooccurrenceView>>(
+    '/admin/v1/item-graph/cooccurrences',
+    params
+  )
+}
+
+export function deleteGraphCooccurrences(ids: number[]) {
+  const body: GraphIdsRequest = { ids }
+  return apiDelete<BatchDeleteResult>(
+    '/admin/v1/item-graph/cooccurrences',
+    body
+  )
+}
+
+export function listGraphBatches(params: GraphBatchListParams = {}) {
+  return apiGet<PageResult<GraphBatchView>>(
+    '/admin/v1/item-graph/batches',
+    params
+  )
+}
diff --git a/memind-ui/src/features/api/items.ts b/memind-ui/src/features/api/items.ts
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/api/items.ts
@@ -0,0 +1,40 @@
+import { apiDelete, apiGet, type PageResult } from '@/lib/api-client'
+import type {
+  AdminItemMemoryThreadView,
+  AdminItemView,
+  BatchDeleteResult,
+  ItemDeleteRequest,
+} from '@/features/types'
+import type { PageParams, UserAgentFilter } from './common'
+
+export type ItemListParams = PageParams &
+  UserAgentFilter & {
+    scope?: string
+    category?: string
+    type?: string
+    rawDataId?: string
+  }
+
+export function listItems(params: ItemListParams = {}) {
+  return apiGet<PageResult<AdminItemView>>('/admin/v1/items', params)
+}
+
+export function getItem(itemId: number) {
+  return apiGet<AdminItemView>(`/admin/v1/items/${itemId}`)
+}
+
+export function listItemMemoryThreads(
+  itemId: number,
+  params: Required<Pick<UserAgentFilter, 'userId'>> &
+    Pick<UserAgentFilter, 'agentId'>
+) {
+  return apiGet<AdminItemMemoryThreadView[]>(
+    `/admin/v1/items/${itemId}/memory-threads`,
+    params
+  )
+}
+
+export function deleteItems(itemIds: number[]) {
+  const body: ItemDeleteRequest = { itemIds }
+  return apiDelete<BatchDeleteResult>('/admin/v1/items', body)
+}
diff --git a/memind-ui/src/features/api/memory-threads.ts b/memind-ui/src/features/api/memory-threads.ts
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/api/memory-threads.ts
@@ -0,0 +1,52 @@
+import { apiGet, apiPost, type PageResult } from '@/lib/api-client'
+import type {
+  AdminMemoryThreadItemView,
+  AdminMemoryThreadStatusView,
+  AdminMemoryThreadView,
+} from '@/features/types'
+import type { PageParams, UserAgentFilter } from './common'
+
+export type MemoryThreadStatus = 'ACTIVE' | 'DORMANT' | 'CLOSED'
+
+export type MemoryThreadListParams = PageParams &
+  UserAgentFilter & {
+    status?: MemoryThreadStatus
+  }
+
+type RequiredUserScope = Required<Pick<UserAgentFilter, 'userId'>> &
+  Pick<UserAgentFilter, 'agentId'>
+
+export function listMemoryThreads(params: MemoryThreadListParams = {}) {
+  return apiGet<PageResult<AdminMemoryThreadView>>(
+    '/admin/v1/memory-threads',
+    params
+  )
+}
+
+export function getMemoryThread(threadKey: string, params: RequiredUserScope) {
+  return apiGet<AdminMemoryThreadView>(
+    `/admin/v1/memory-threads/${encodeURIComponent(threadKey)}`,
+    params
+  )
+}
+
+export function listMemoryThreadItems(
+  threadKey: string,
+  params: RequiredUserScope
+) {
+  return apiGet<AdminMemoryThreadItemView[]>(
+    `/admin/v1/memory-threads/${encodeURIComponent(threadKey)}/items`,
+    params
+  )
+}
+
+export function getMemoryThreadStatus(params: RequiredUserScope) {
+  return apiGet<AdminMemoryThreadStatusView>(
+    '/admin/v1/memory-threads/status',
+    params
+  )
+}
+
+export function rebuildMemoryThreads(params: RequiredUserScope) {
+  return apiPost<number>('/admin/v1/memory-threads/rebuild', undefined, params)
+}
diff --git a/memind-ui/src/features/api/raw-data.ts b/memind-ui/src/features/api/raw-data.ts
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/api/raw-data.ts
@@ -0,0 +1,28 @@
+import { apiDelete, apiGet, type PageResult } from '@/lib/api-client'
+import type {
+  AdminRawDataView,
+  RawDataDeleteRequest,
+  RawDataDeleteResult,
+} from '@/features/types'
+import type { PageParams, UserAgentFilter } from './common'
+
+export type RawDataListParams = PageParams &
+  UserAgentFilter & {
+    startTimeFrom?: string
+    startTimeTo?: string
+  }
+
+export function listRawData(params: RawDataListParams = {}) {
+  return apiGet<PageResult<AdminRawDataView>>('/admin/v1/raw-data', params)
+}
+
+export function getRawData(rawDataId: string) {
+  return apiGet<AdminRawDataView>(
+    `/admin/v1/raw-data/${encodeURIComponent(rawDataId)}`
+  )
+}
+
+export function deleteRawData(rawDataIds: string[]) {
+  const body: RawDataDeleteRequest = { rawDataIds }
+  return apiDelete<RawDataDeleteResult>('/admin/v1/raw-data', body)
+}
diff --git a/memind-ui/src/features/api/retrieve.ts b/memind-ui/src/features/api/retrieve.ts
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/api/retrieve.ts
@@ -0,0 +1,9 @@
+import { apiPost } from '@/lib/api-client'
+import type {
+  RetrieveMemoryRequest,
+  RetrieveMemoryResponse,
+} from '@/features/types'
+
+export function retrieveMemory(request: RetrieveMemoryRequest) {
+  return apiPost<RetrieveMemoryResponse>('/open/v1/memory/retrieve', request)
+}
diff --git a/memind-ui/src/features/buffers/conversations-table.tsx b/memind-ui/src/features/buffers/conversations-table.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/buffers/conversations-table.tsx
@@ -0,0 +1,95 @@
+import { Badge } from '@/components/ui/badge'
+import { Button } from '@/components/ui/button'
+import { Checkbox } from '@/components/ui/checkbox'
+import {
+  Table,
+  TableBody,
+  TableCell,
+  TableHead,
+  TableHeader,
+  TableRow,
+} from '@/components/ui/table'
+import type { ConversationBufferView } from '@/features/types'
+import { formatDateTime, truncateText } from '@/lib/format'
+
+export function ConversationBuffersTable({
+  rows,
+  selectedIds,
+  onToggleSelected,
+  onView,
+}: {
+  rows: ConversationBufferView[]
+  selectedIds: Set<number>
+  onToggleSelected: (id: number, checked: boolean) => void
+  onView: (id: number) => void
+}) {
+  return (
+    <Table>
+      <TableHeader>
+        <TableRow>
+          <TableHead className='w-10'>Select</TableHead>
+          <TableHead>ID</TableHead>
+          <TableHead>Session ID</TableHead>
+          <TableHead>Memory ID</TableHead>
+          <TableHead>Role</TableHead>
+          <TableHead>Content</TableHead>
+          <TableHead>User Name</TableHead>
+          <TableHead>Source Client</TableHead>
+          <TableHead>Extracted</TableHead>
+          <TableHead>Timestamp</TableHead>
+          <TableHead>Created At</TableHead>
+          <TableHead>Updated At</TableHead>
+          <TableHead className='text-end'>Actions</TableHead>
+        </TableRow>
+      </TableHeader>
+      <TableBody>
+        {rows.map((row) => (
+          <TableRow key={row.id}>
+            <TableCell>
+              <Checkbox
+                aria-label={`Select conversation ${row.id}`}
+                checked={selectedIds.has(row.id)}
+                onCheckedChange={(checked) =>
+                  onToggleSelected(row.id, checked === true)
+                }
+              />
+            </TableCell>
+            <TableCell>{row.id}</TableCell>
+            <TableCell>{fieldValue(row.sessionId)}</TableCell>
+            <TableCell>{row.memoryId}</TableCell>
+            <TableCell>{fieldValue(row.role)}</TableCell>
+            <TableCell className='max-w-96 whitespace-normal'>
+              {truncateText(row.content, 120)}
+            </TableCell>
+            <TableCell>{fieldValue(row.userName)}</TableCell>
+            <TableCell>{fieldValue(row.sourceClient)}</TableCell>
+            <TableCell>
+              <Badge variant={row.extracted ? 'default' : 'secondary'}>
+                {row.extracted ? 'extracted' : 'pending'}
+              </Badge>
+            </TableCell>
+            <TableCell>{formatDateTime(row.timestamp)}</TableCell>
+            <TableCell>{formatDateTime(row.createdAt)}</TableCell>
+            <TableCell>{formatDateTime(row.updatedAt)}</TableCell>
+            <TableCell className='text-end'>
+              <Button
+                type='button'
+                variant='outline'
+                size='sm'
+                aria-label={`View conversation ${row.id}`}
+                onClick={() => onView(row.id)}
+              >
+                View
+              </Button>
+            </TableCell>
+          </TableRow>
+        ))}
+      </TableBody>
+    </Table>
+  )
+}
+
+function fieldValue(value: unknown) {
+  if (value === null || value === undefined || value === '') return '-'
+  return String(value)
+}
diff --git a/memind-ui/src/features/buffers/index.tsx b/memind-ui/src/features/buffers/index.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/buffers/index.tsx
@@ -0,0 +1,667 @@
+import { useMemo, useState } from 'react'
+import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
+import { Header } from '@/components/layout/header'
+import { Main } from '@/components/layout/main'
+import { Button } from '@/components/ui/button'
+import {
+  Dialog,
+  DialogContent,
+  DialogDescription,
+  DialogHeader,
+  DialogTitle,
+} from '@/components/ui/dialog'
+import { Input } from '@/components/ui/input'
+import { Label } from '@/components/ui/label'
+import {
+  Tabs,
+  TabsContent,
+  TabsList,
+  TabsTrigger,
+} from '@/components/ui/tabs'
+import {
+  deleteConversationBuffers,
+  deleteInsightBuffers,
+  getConversationBuffer,
+  listConversationBuffers,
+  listInsightBufferGroups,
+  listInsightBuffers,
+  markConversationsExtracted,
+  updateInsightBufferBuilt,
+  updateInsightBufferGroup,
+  type ConversationBufferListParams,
+  type ConversationBufferState,
+  type InsightBufferListParams,
+  type InsightBufferState,
+} from '@/features/api/buffers'
+import { ConfirmResultDialog } from '@/features/components/confirm-result-dialog'
+import {
+  EmptyState,
+  PageError,
+  PageLoading,
+  TableLoading,
+} from '@/features/components/data-state'
+import { readMemoryScopeFromLocation } from '@/features/components/memory-scope-location'
+import type { ConversationBufferView } from '@/features/types'
+import { formatDateTime } from '@/lib/format'
+import { ConversationBuffersTable } from './conversations-table'
+import { InsightBuffersTable } from './insight-buffers-table'
+import { InsightGroupsTable } from './insight-groups-table'
+
+const DEFAULT_PAGE = 1
+const DEFAULT_PAGE_SIZE = 10
+const DEFAULT_CONVERSATION_STATE: ConversationBufferState = 'pending'
+const DEFAULT_INSIGHT_STATE: InsightBufferState = 'unbuilt'
+
+type BufferTab = 'conversations' | 'insights' | 'groups'
+
+export function BuffersPage() {
+  const [tab, setTab] = useState<BufferTab>(() => readTabFromLocation())
+  const [, refreshLocation] = useState(0)
+  const search = readBuffersSearch()
+  const memoryId = readMemoryScopeFromLocation()
+
+  const writeSearch = (patch: Record<string, string | number | undefined>) => {
+    writeUrlSearch(patch)
+    refreshLocation((current) => current + 1)
+  }
+
+  return (
+    <>
+      <Header>
+        <h1 className='truncate text-lg font-semibold'>Buffers</h1>
+      </Header>
+      <Main>
+        <div className='flex flex-col gap-4'>
+          <div className='flex flex-col gap-1'>
+            <h2 className='text-2xl font-semibold'>Buffers</h2>
+            <p className='text-sm text-muted-foreground'>
+              Manage pending conversation and insight buffer records before they
+              are materialized into memory.
+            </p>
+          </div>
+
+          <Tabs
+            value={tab}
+            onValueChange={(value) => {
+              const nextTab = normalizeTab(value)
+              setTab(nextTab)
+              writeSearch({
+                tab: nextTab === 'conversations' ? undefined : nextTab,
+                pageNo: undefined,
+                state: undefined,
+              })
+            }}
+          >
+            <TabsList>
+              <TabsTrigger value='conversations'>Conversations</TabsTrigger>
+              <TabsTrigger value='insights'>Insight Buffers</TabsTrigger>
+              <TabsTrigger value='groups'>Insight Buffer Groups</TabsTrigger>
+            </TabsList>
+
+            <TabsContent value='conversations'>
+              <ConversationBuffersPanel
+                search={search}
+                memoryId={memoryId}
+                onSearchChange={writeSearch}
+              />
+            </TabsContent>
+            <TabsContent value='insights'>
+              <InsightBuffersPanel
+                search={search}
+                memoryId={memoryId}
+                onSearchChange={writeSearch}
+              />
+            </TabsContent>
+            <TabsContent value='groups'>
+              <InsightGroupsPanel search={search} memoryId={memoryId} />
+            </TabsContent>
+          </Tabs>
+        </div>
+      </Main>
+    </>
+  )
+}
+
+function ConversationBuffersPanel({
+  search,
+  memoryId,
+  onSearchChange,
+}: {
+  search: BuffersSearch
+  memoryId: string
+  onSearchChange: (patch: Record<string, string | number | undefined>) => void
+}) {
+  const queryClient = useQueryClient()
+  const [selectedIds, setSelectedIds] = useState<Set<number>>(() => new Set())
+  const [deleteOpen, setDeleteOpen] = useState(false)
+  const [detailId, setDetailId] = useState<number | null>(null)
+  const state = normalizeConversationState(search.state)
+  const params = useMemo(
+    () => buildConversationParams(search, memoryId, state),
+    [memoryId, search, state]
+  )
+  const conversationsQuery = useQuery({
+    queryKey: ['buffers', 'conversations', params],
+    queryFn: () => listConversationBuffers(params),
+  })
+  const markExtractedMutation = useMutation({
+    mutationFn: (ids: number[]) => markConversationsExtracted(ids),
+    onSuccess: async () => {
+      setSelectedIds(new Set())
+      await invalidateBuffers(queryClient)
+    },
+  })
+  const deleteMutation = useMutation({
+    mutationFn: (ids: number[]) => deleteConversationBuffers(ids),
+    onSuccess: async () => {
+      setSelectedIds(new Set())
+      await invalidateBuffers(queryClient)
+    },
+  })
+
+  const rows = conversationsQuery.data?.list ?? []
+  const selectedConversationIds = [...selectedIds]
+
+  return (
+    <div className='flex flex-col gap-4'>
+      <div className='flex flex-wrap items-end justify-between gap-3'>
+        <div className='flex items-center gap-2'>
+          <Label htmlFor='conversation-buffer-state'>
+            Conversation buffer state
+          </Label>
+          <select
+            id='conversation-buffer-state'
+            aria-label='Conversation buffer state'
+            value={state}
+            className='h-9 rounded-md border bg-background px-3 text-sm'
+            onChange={(event) =>
+              onSearchChange({
+                pageNo: undefined,
+                state:
+                  event.target.value === DEFAULT_CONVERSATION_STATE
+                    ? undefined
+                    : event.target.value,
+              })
+            }
+          >
+            <option value='pending'>pending</option>
+            <option value='extracted'>extracted</option>
+            <option value='all'>all</option>
+          </select>
+        </div>
+
+        <div className='flex flex-wrap gap-2'>
+          <Button
+            type='button'
+            variant='outline'
+            disabled={selectedIds.size === 0 || markExtractedMutation.isPending}
+            onClick={() => markExtractedMutation.mutate(selectedConversationIds)}
+          >
+            Mark extracted
+          </Button>
+          <Button
+            type='button'
+            variant='destructive'
+            disabled={selectedIds.size === 0}
+            onClick={() => {
+              deleteMutation.reset()
+              setDeleteOpen(true)
+            }}
+          >
+            Delete selected
+          </Button>
+        </div>
+      </div>
+
+      {conversationsQuery.isLoading ? <TableLoading columns={11} /> : null}
+      {conversationsQuery.isError ? (
+        <PageError
+          message='Unable to load conversation buffers.'
+          onRetry={conversationsQuery.refetch}
+        />
+      ) : null}
+      {conversationsQuery.data && rows.length === 0 ? (
+        <EmptyState title='No conversation buffers found.' />
+      ) : null}
+      {rows.length > 0 ? (
+        <ConversationBuffersTable
+          rows={rows}
+          selectedIds={selectedIds}
+          onToggleSelected={(id, checked) => {
+            setSelectedIds((current) => toggleId(current, id, checked))
+          }}
+          onView={setDetailId}
+        />
+      ) : null}
+      {conversationsQuery.data ? (
+        <p className='text-sm text-muted-foreground'>
+          Total rows: {conversationsQuery.data.total}
+        </p>
+      ) : null}
+
+      <ConfirmResultDialog
+        open={deleteOpen}
+        onOpenChange={setDeleteOpen}
+        title='Delete selected conversation buffers'
+        selectedCount={selectedConversationIds.length}
+        description='Only the selected conversation buffer ids will be sent to the server.'
+        isPending={deleteMutation.isPending}
+        result={deleteMutation.data ? { ...deleteMutation.data } : null}
+        onConfirm={() => deleteMutation.mutate(selectedConversationIds)}
+      />
+
+      <ConversationDetailDialog
+        id={detailId}
+        onOpenChange={(open) => {
+          if (!open) setDetailId(null)
+        }}
+      />
+    </div>
+  )
+}
+
+function InsightBuffersPanel({
+  search,
+  memoryId,
+  onSearchChange,
+}: {
+  search: BuffersSearch
+  memoryId: string
+  onSearchChange: (patch: Record<string, string | number | undefined>) => void
+}) {
+  const queryClient = useQueryClient()
+  const [selectedIds, setSelectedIds] = useState<Set<number>>(() => new Set())
+  const [deleteOpen, setDeleteOpen] = useState(false)
+  const [groupName, setGroupName] = useState('')
+  const state = normalizeInsightState(search.state)
+  const params = useMemo(
+    () => buildInsightParams(search, memoryId, state),
+    [memoryId, search, state]
+  )
+  const insightsQuery = useQuery({
+    queryKey: ['buffers', 'insights', params],
+    queryFn: () => listInsightBuffers(params),
+  })
+  const builtMutation = useMutation({
+    mutationFn: (request: { ids: number[]; built: boolean }) =>
+      updateInsightBufferBuilt(request),
+    onSuccess: async () => {
+      setSelectedIds(new Set())
+      await invalidateBuffers(queryClient)
+    },
+  })
+  const groupMutation = useMutation({
+    mutationFn: (request: { ids: number[]; groupName?: string | null }) =>
+      updateInsightBufferGroup(request),
+    onSuccess: async () => {
+      setSelectedIds(new Set())
+      await invalidateBuffers(queryClient)
+    },
+  })
+  const deleteMutation = useMutation({
+    mutationFn: (ids: number[]) => deleteInsightBuffers(ids),
+    onSuccess: async () => {
+      setSelectedIds(new Set())
+      await invalidateBuffers(queryClient)
+    },
+  })
+
+  const rows = insightsQuery.data?.list ?? []
+  const selectedInsightIds = [...selectedIds]
+
+  return (
+    <div className='flex flex-col gap-4'>
+      <div className='flex flex-wrap items-end justify-between gap-3'>
+        <div className='flex items-center gap-2'>
+          <Label htmlFor='insight-buffer-state'>Insight buffer state</Label>
+          <select
+            id='insight-buffer-state'
+            aria-label='Insight buffer state'
+            value={state}
+            className='h-9 rounded-md border bg-background px-3 text-sm'
+            onChange={(event) =>
+              onSearchChange({
+                pageNo: undefined,
+                state:
+                  event.target.value === DEFAULT_INSIGHT_STATE
+                    ? undefined
+                    : event.target.value,
+              })
+            }
+          >
+            <option value='unbuilt'>unbuilt</option>
+            <option value='ungrouped'>ungrouped</option>
+            <option value='grouped'>grouped</option>
+            <option value='built'>built</option>
+            <option value='all'>all</option>
+          </select>
+        </div>
+
+        <div className='flex flex-wrap items-center gap-2'>
+          <Label htmlFor='insight-buffer-group-name' className='sr-only'>
+            Group name
+          </Label>
+          <Input
+            id='insight-buffer-group-name'
+            value={groupName}
+            placeholder='groupName'
+            className='h-9 w-40'
+            onChange={(event) => setGroupName(event.target.value)}
+          />
+          <Button
+            type='button'
+            variant='outline'
+            disabled={selectedIds.size === 0 || groupMutation.isPending}
+            onClick={() =>
+              groupMutation.mutate({
+                ids: selectedInsightIds,
+                groupName: groupName.trim() || null,
+              })
+            }
+          >
+            Set group
+          </Button>
+          <Button
+            type='button'
+            variant='outline'
+            disabled={selectedIds.size === 0 || builtMutation.isPending}
+            onClick={() =>
+              builtMutation.mutate({ ids: selectedInsightIds, built: true })
+            }
+          >
+            Mark built
+          </Button>
+          <Button
+            type='button'
+            variant='outline'
+            disabled={selectedIds.size === 0 || builtMutation.isPending}
+            onClick={() =>
+              builtMutation.mutate({ ids: selectedInsightIds, built: false })
+            }
+          >
+            Mark unbuilt
+          </Button>
+          <Button
+            type='button'
+            variant='destructive'
+            disabled={selectedIds.size === 0}
+            onClick={() => {
+              deleteMutation.reset()
+              setDeleteOpen(true)
+            }}
+          >
+            Delete selected
+          </Button>
+        </div>
+      </div>
+
+      {insightsQuery.isLoading ? <TableLoading columns={8} /> : null}
+      {insightsQuery.isError ? (
+        <PageError
+          message='Unable to load insight buffers.'
+          onRetry={insightsQuery.refetch}
+        />
+      ) : null}
+      {insightsQuery.data && rows.length === 0 ? (
+        <EmptyState title='No insight buffers found.' />
+      ) : null}
+      {rows.length > 0 ? (
+        <InsightBuffersTable
+          rows={rows}
+          selectedIds={selectedIds}
+          onToggleSelected={(id, checked) => {
+            setSelectedIds((current) => toggleId(current, id, checked))
+          }}
+        />
+      ) : null}
+      {insightsQuery.data ? (
+        <p className='text-sm text-muted-foreground'>
+          Total rows: {insightsQuery.data.total}
+        </p>
+      ) : null}
+
+      <ConfirmResultDialog
+        open={deleteOpen}
+        onOpenChange={setDeleteOpen}
+        title='Delete selected insight buffers'
+        selectedCount={selectedInsightIds.length}
+        description='Only the selected insight buffer ids will be sent to the server.'
+        isPending={deleteMutation.isPending}
+        result={deleteMutation.data ? { ...deleteMutation.data } : null}
+        onConfirm={() => deleteMutation.mutate(selectedInsightIds)}
+      />
+    </div>
+  )
+}
+
+function InsightGroupsPanel({
+  search,
+  memoryId,
+}: {
+  search: BuffersSearch
+  memoryId: string
+}) {
+  const params = useMemo(
+    () => ({
+      memoryId: memoryId || undefined,
+      insightTypeName: search.insightTypeName,
+    }),
+    [memoryId, search.insightTypeName]
+  )
+  const groupsQuery = useQuery({
+    queryKey: ['buffers', 'insight-groups', params],
+    queryFn: () => listInsightBufferGroups(params),
+  })
+  const rows = groupsQuery.data ?? []
+
+  return (
+    <div className='flex flex-col gap-4'>
+      {groupsQuery.isLoading ? <TableLoading columns={6} /> : null}
+      {groupsQuery.isError ? (
+        <PageError
+          message='Unable to load insight buffer groups.'
+          onRetry={groupsQuery.refetch}
+        />
+      ) : null}
+      {groupsQuery.data && rows.length === 0 ? (
+        <EmptyState title='No insight buffer groups found.' />
+      ) : null}
+      {rows.length > 0 ? <InsightGroupsTable rows={rows} /> : null}
+    </div>
+  )
+}
+
+function ConversationDetailDialog({
+  id,
+  onOpenChange,
+}: {
+  id: number | null
+  onOpenChange: (open: boolean) => void
+}) {
+  const detailQuery = useQuery({
+    queryKey: ['buffers', 'conversations', id, 'detail'],
+    enabled: id !== null,
+    queryFn: () => getConversationBuffer(id as number),
+  })
+  const conversation = detailQuery.data
+
+  return (
+    <Dialog open={id !== null} onOpenChange={onOpenChange}>
+      <DialogContent className='max-h-[85vh] overflow-auto sm:max-w-3xl'>
+        <DialogHeader>
+          <DialogTitle>Conversation buffer {id}</DialogTitle>
+          <DialogDescription>{conversation?.memoryId ?? ''}</DialogDescription>
+        </DialogHeader>
+
+        {detailQuery.isLoading ? <PageLoading /> : null}
+        {detailQuery.isError ? (
+          <PageError
+            message='Unable to load conversation buffer detail.'
+            onRetry={detailQuery.refetch}
+          />
+        ) : null}
+        {conversation ? <ConversationDetail conversation={conversation} /> : null}
+      </DialogContent>
+    </Dialog>
+  )
+}
+
+function ConversationDetail({
+  conversation,
+}: {
+  conversation: ConversationBufferView
+}) {
+  return (
+    <div className='flex flex-col gap-5 text-sm'>
+      <section className='flex flex-col gap-2'>
+        <h3 className='font-medium'>Content</h3>
+        <p className='whitespace-pre-wrap rounded-md bg-muted p-3'>
+          {conversation.content}
+        </p>
+      </section>
+
+      <div className='grid gap-2 md:grid-cols-2'>
+        <p>sessionId: {fieldValue(conversation.sessionId)}</p>
+        <p>memoryId: {conversation.memoryId}</p>
+        <p>role: {fieldValue(conversation.role)}</p>
+        <p>userName: {fieldValue(conversation.userName)}</p>
+        <p>sourceClient: {fieldValue(conversation.sourceClient)}</p>
+        <p>extracted: {conversation.extracted ? 'yes' : 'no'}</p>
+        <p>timestamp: {formatDateTime(conversation.timestamp)}</p>
+        <p>createdAt: {formatDateTime(conversation.createdAt)}</p>
+        <p>updatedAt: {formatDateTime(conversation.updatedAt)}</p>
+      </div>
+    </div>
+  )
+}
+
+function buildConversationParams(
+  search: BuffersSearch,
+  memoryId: string,
+  state: ConversationBufferState
+): ConversationBufferListParams {
+  return {
+    pageNo: search.pageNo,
+    pageSize: search.pageSize,
+    memoryId: memoryId || undefined,
+    sessionId: search.sessionId,
+    state,
+  }
+}
+
+function buildInsightParams(
+  search: BuffersSearch,
+  memoryId: string,
+  state: InsightBufferState
+): InsightBufferListParams {
+  return {
+    pageNo: search.pageNo,
+    pageSize: search.pageSize,
+    memoryId: memoryId || undefined,
+    insightTypeName: search.insightTypeName,
+    state,
+  }
+}
+
+type BuffersSearch = {
+  pageNo: number
+  pageSize: number
+  sessionId?: string
+  insightTypeName?: string
+  state?: string
+}
+
+function readBuffersSearch(): BuffersSearch {
+  const params = readSearchParams()
+  return {
+    pageNo: readNumberParam(params, 'pageNo', DEFAULT_PAGE),
+    pageSize: readNumberParam(params, 'pageSize', DEFAULT_PAGE_SIZE),
+    sessionId: readStringParam(params, 'sessionId'),
+    insightTypeName: readStringParam(params, 'insightTypeName'),
+    state: readStringParam(params, 'state'),
+  }
+}
+
+function readTabFromLocation(): BufferTab {
+  return normalizeTab(readSearchParams().get('tab') ?? '')
+}
+
+function normalizeTab(value: string): BufferTab {
+  if (value === 'insights' || value === 'groups') return value
+  return 'conversations'
+}
+
+function normalizeConversationState(
+  state: string | undefined
+): ConversationBufferState {
+  if (state === 'extracted' || state === 'all') return state
+  return DEFAULT_CONVERSATION_STATE
+}
+
+function normalizeInsightState(state: string | undefined): InsightBufferState {
+  if (
+    state === 'ungrouped' ||
+    state === 'grouped' ||
+    state === 'built' ||
+    state === 'all'
+  ) {
+    return state
+  }
+  return DEFAULT_INSIGHT_STATE
+}
+
+function readSearchParams() {
+  if (typeof window === 'undefined') return new URLSearchParams()
+  return new URLSearchParams(window.location.search)
+}
+
+function readStringParam(params: URLSearchParams, key: string) {
+  const value = params.get(key)?.trim()
+  return value ? value : undefined
+}
+
+function readNumberParam(
+  params: URLSearchParams,
+  key: string,
+  fallback: number
+) {
+  const value = params.get(key)
+  if (!value) return fallback
+  const parsed = Number(value)
+  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback
+}
+
+function writeUrlSearch(patch: Record<string, string | number | undefined>) {
+  if (typeof window === 'undefined') return
+  const url = new URL(window.location.href)
+  for (const [key, value] of Object.entries(patch)) {
+    if (value === undefined || value === '') {
+      url.searchParams.delete(key)
+    } else {
+      url.searchParams.set(key, String(value))
+    }
+  }
+  window.history.replaceState(window.history.state, '', url)
+}
+
+function toggleId<T>(current: Set<T>, id: T, checked: boolean) {
+  const next = new Set(current)
+  if (checked) {
+    next.add(id)
+  } else {
+    next.delete(id)
+  }
+  return next
+}
+
+async function invalidateBuffers(queryClient: ReturnType<typeof useQueryClient>) {
+  await Promise.all([
+    queryClient.invalidateQueries({ queryKey: ['buffers'] }),
+    queryClient.invalidateQueries({ queryKey: ['dashboard'] }),
+  ])
+}
+
+function fieldValue(value: unknown) {
+  if (value === null || value === undefined || value === '') return '-'
+  return String(value)
+}
diff --git a/memind-ui/src/features/buffers/insight-buffers-table.tsx b/memind-ui/src/features/buffers/insight-buffers-table.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/buffers/insight-buffers-table.tsx
@@ -0,0 +1,72 @@
+import { Badge } from '@/components/ui/badge'
+import { Checkbox } from '@/components/ui/checkbox'
+import {
+  Table,
+  TableBody,
+  TableCell,
+  TableHead,
+  TableHeader,
+  TableRow,
+} from '@/components/ui/table'
+import type { InsightBufferView } from '@/features/types'
+import { formatDateTime } from '@/lib/format'
+
+export function InsightBuffersTable({
+  rows,
+  selectedIds,
+  onToggleSelected,
+}: {
+  rows: InsightBufferView[]
+  selectedIds: Set<number>
+  onToggleSelected: (id: number, checked: boolean) => void
+}) {
+  return (
+    <Table>
+      <TableHeader>
+        <TableRow>
+          <TableHead className='w-10'>Select</TableHead>
+          <TableHead>ID</TableHead>
+          <TableHead>Memory ID</TableHead>
+          <TableHead>Insight Type Name</TableHead>
+          <TableHead>Item ID</TableHead>
+          <TableHead>Group Name</TableHead>
+          <TableHead>Built</TableHead>
+          <TableHead>Created At</TableHead>
+          <TableHead>Updated At</TableHead>
+        </TableRow>
+      </TableHeader>
+      <TableBody>
+        {rows.map((row) => (
+          <TableRow key={row.id}>
+            <TableCell>
+              <Checkbox
+                aria-label={`Select insight buffer ${row.id}`}
+                checked={selectedIds.has(row.id)}
+                onCheckedChange={(checked) =>
+                  onToggleSelected(row.id, checked === true)
+                }
+              />
+            </TableCell>
+            <TableCell>{row.id}</TableCell>
+            <TableCell>{row.memoryId}</TableCell>
+            <TableCell>{row.insightTypeName}</TableCell>
+            <TableCell>{fieldValue(row.itemId)}</TableCell>
+            <TableCell>{fieldValue(row.groupName)}</TableCell>
+            <TableCell>
+              <Badge variant={row.built ? 'default' : 'secondary'}>
+                {row.built ? 'built' : 'unbuilt'}
+              </Badge>
+            </TableCell>
+            <TableCell>{formatDateTime(row.createdAt)}</TableCell>
+            <TableCell>{formatDateTime(row.updatedAt)}</TableCell>
+          </TableRow>
+        ))}
+      </TableBody>
+    </Table>
+  )
+}
+
+function fieldValue(value: unknown) {
+  if (value === null || value === undefined || value === '') return '-'
+  return String(value)
+}
diff --git a/memind-ui/src/features/buffers/insight-groups-table.tsx b/memind-ui/src/features/buffers/insight-groups-table.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/buffers/insight-groups-table.tsx
@@ -0,0 +1,52 @@
+import {
+  Table,
+  TableBody,
+  TableCell,
+  TableHead,
+  TableHeader,
+  TableRow,
+} from '@/components/ui/table'
+import type { InsightBufferGroupView } from '@/features/types'
+import { formatNumber } from '@/lib/format'
+
+export function InsightGroupsTable({
+  rows,
+}: {
+  rows: InsightBufferGroupView[]
+}) {
+  return (
+    <Table>
+      <TableHeader>
+        <TableRow>
+          <TableHead>Memory ID</TableHead>
+          <TableHead>Insight Type Name</TableHead>
+          <TableHead>Group Name</TableHead>
+          <TableHead>Total</TableHead>
+          <TableHead>Unbuilt</TableHead>
+          <TableHead>Built</TableHead>
+        </TableRow>
+      </TableHeader>
+      <TableBody>
+        {rows.map((row) => (
+          <TableRow key={groupKey(row)}>
+            <TableCell>{row.memoryId}</TableCell>
+            <TableCell>{row.insightTypeName}</TableCell>
+            <TableCell>{fieldValue(row.groupName)}</TableCell>
+            <TableCell>{formatNumber(row.total)}</TableCell>
+            <TableCell>{formatNumber(row.unbuilt)}</TableCell>
+            <TableCell>{formatNumber(row.built)}</TableCell>
+          </TableRow>
+        ))}
+      </TableBody>
+    </Table>
+  )
+}
+
+function groupKey(row: InsightBufferGroupView) {
+  return `${row.memoryId}:${row.insightTypeName}:${row.groupName ?? ''}`
+}
+
+function fieldValue(value: unknown) {
+  if (value === null || value === undefined || value === '') return '-'
+  return String(value)
+}
diff --git a/memind-ui/src/features/components/confirm-result-dialog.tsx b/memind-ui/src/features/components/confirm-result-dialog.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/components/confirm-result-dialog.tsx
@@ -0,0 +1,92 @@
+import {
+  AlertDialog,
+  AlertDialogCancel,
+  AlertDialogContent,
+  AlertDialogDescription,
+  AlertDialogFooter,
+  AlertDialogHeader,
+  AlertDialogTitle,
+} from '@/components/ui/alert-dialog'
+import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert'
+import { Button } from '@/components/ui/button'
+
+type ConfirmResultDialogProps = {
+  open: boolean
+  onOpenChange: (open: boolean) => void
+  title: string
+  selectedCount: number
+  description: string
+  cascadeWarning?: string
+  confirmText?: string
+  isPending?: boolean
+  result?: Record<string, unknown> | null
+  onConfirm: () => void
+}
+
+export function ConfirmResultDialog({
+  open,
+  onOpenChange,
+  title,
+  selectedCount,
+  description,
+  cascadeWarning,
+  confirmText = 'Delete',
+  isPending = false,
+  result,
+  onConfirm,
+}: ConfirmResultDialogProps) {
+  return (
+    <AlertDialog open={open} onOpenChange={onOpenChange}>
+      <AlertDialogContent>
+        <AlertDialogHeader>
+          <AlertDialogTitle>{title}</AlertDialogTitle>
+          <AlertDialogDescription asChild>
+            <div className='flex flex-col gap-3'>
+              <p>{selectedCount} selected rows</p>
+              <p>{description}</p>
+            </div>
+          </AlertDialogDescription>
+        </AlertDialogHeader>
+
+        {cascadeWarning ? (
+          <Alert variant='destructive'>
+            <AlertTitle>Cascading delete</AlertTitle>
+            <AlertDescription>{cascadeWarning}</AlertDescription>
+          </Alert>
+        ) : null}
+
+        {result ? (
+          <div className='flex flex-col gap-2 text-sm'>
+            <p className='font-medium'>Result</p>
+            <ul className='flex flex-col gap-1 text-muted-foreground'>
+              {summarizeResult(result).map(({ key, value }) => (
+                <li key={key}>
+                  {key}: {value}
+                </li>
+              ))}
+            </ul>
+          </div>
+        ) : null}
+
+        <AlertDialogFooter>
+          <AlertDialogCancel disabled={isPending}>Cancel</AlertDialogCancel>
+          <Button
+            type='button'
+            variant='destructive'
+            disabled={isPending || selectedCount < 1}
+            onClick={onConfirm}
+          >
+            {confirmText}
+          </Button>
+        </AlertDialogFooter>
+      </AlertDialogContent>
+    </AlertDialog>
+  )
+}
+
+function summarizeResult(result: Record<string, unknown>) {
+  return Object.entries(result).map(([key, value]) => ({
+    key,
+    value: Array.isArray(value) ? value.length : String(value),
+  }))
+}
diff --git a/memind-ui/src/features/components/data-state.tsx b/memind-ui/src/features/components/data-state.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/components/data-state.tsx
@@ -0,0 +1,86 @@
+import { AlertCircle } from 'lucide-react'
+import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert'
+import { Button } from '@/components/ui/button'
+import { Skeleton } from '@/components/ui/skeleton'
+
+export function PageLoading() {
+  return (
+    <div className='flex flex-col gap-4'>
+      <Skeleton className='h-8 w-48' />
+      <Skeleton className='h-40 w-full' />
+    </div>
+  )
+}
+
+export function TableLoading({ columns }: { columns: number }) {
+  return (
+    <div className='flex flex-col gap-2' aria-label='Loading table'>
+      {Array.from({ length: 5 }).map((_, rowIndex) => (
+        <div
+          key={rowIndex}
+          className='grid gap-2'
+          style={{ gridTemplateColumns: `repeat(${columns}, minmax(0, 1fr))` }}
+        >
+          {Array.from({ length: columns }).map((__, columnIndex) => (
+            <Skeleton
+              key={columnIndex}
+              className='h-8 w-full'
+            />
+          ))}
+        </div>
+      ))}
+    </div>
+  )
+}
+
+export function EmptyState({
+  title,
+  description,
+}: {
+  title: string
+  description?: string
+}) {
+  return (
+    <Alert>
+      <AlertTitle>{title}</AlertTitle>
+      {description ? <AlertDescription>{description}</AlertDescription> : null}
+    </Alert>
+  )
+}
+
+export function PageError({
+  message,
+  traceId,
+  onRetry,
+}: {
+  message: string
+  traceId?: string
+  onRetry?: () => void
+}) {
+  return (
+    <Alert variant='destructive'>
+      <AlertCircle aria-hidden='true' />
+      <AlertTitle>Request failed</AlertTitle>
+      <AlertDescription>
+        <div className='flex flex-col gap-3'>
+          <p>{message}</p>
+          {traceId ? <p>traceId: {traceId}</p> : null}
+          {onRetry ? (
+            <Button type='button' variant='outline' size='sm' onClick={onRetry}>
+              Retry
+            </Button>
+          ) : null}
+        </div>
+      </AlertDescription>
+    </Alert>
+  )
+}
+
+export function ScopeRequiredState({ message }: { message: string }) {
+  return (
+    <Alert>
+      <AlertTitle>Scope required</AlertTitle>
+      <AlertDescription>{message}</AlertDescription>
+    </Alert>
+  )
+}
diff --git a/memind-ui/src/features/components/json-viewer.tsx b/memind-ui/src/features/components/json-viewer.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/components/json-viewer.tsx
@@ -0,0 +1,48 @@
+import { useState } from 'react'
+import { ChevronDown, ChevronRight } from 'lucide-react'
+import { compactJson, truncateText } from '@/lib/format'
+import { Button } from '@/components/ui/button'
+
+type JsonViewerProps = {
+  value: unknown
+  label?: string
+  defaultExpanded?: boolean
+}
+
+export function JsonViewer({
+  value,
+  label = 'JSON',
+  defaultExpanded = false,
+}: JsonViewerProps) {
+  const [expanded, setExpanded] = useState(defaultExpanded)
+  const json = expanded
+    ? prettyJson(value)
+    : truncateText(compactJson(value), 160)
+
+  return (
+    <div className='flex min-w-0 flex-col gap-2'>
+      <Button
+        type='button'
+        variant='ghost'
+        size='sm'
+        className='max-w-full justify-start'
+        aria-expanded={expanded}
+        onClick={() => setExpanded((current) => !current)}
+      >
+        {expanded ? <ChevronDown /> : <ChevronRight />}
+        <span className='min-w-0 truncate'>{label}</span>
+      </Button>
+      <pre className='max-h-96 overflow-auto rounded-md bg-muted p-3 text-xs'>
+        {json}
+      </pre>
+    </div>
+  )
+}
+
+function prettyJson(value: unknown) {
+  try {
+    return JSON.stringify(value, null, 2)
+  } catch {
+    return String(value)
+  }
+}
diff --git a/memind-ui/src/features/components/memory-scope-location.ts b/memind-ui/src/features/components/memory-scope-location.ts
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/components/memory-scope-location.ts
@@ -0,0 +1,36 @@
+import { parseMemoryScope } from '@/lib/memory-scope'
+
+const MEMORY_SCOPE_SEARCH_PARAM = 'memoryId'
+const MEMORY_SCOPE_STORAGE_KEY = 'memind-ui:memory-scope'
+
+export function readMemoryScopeFromLocation() {
+  if (typeof window === 'undefined') return ''
+
+  const params = new URLSearchParams(window.location.search)
+  return (
+    params.get(MEMORY_SCOPE_SEARCH_PARAM) ??
+    window.localStorage.getItem(MEMORY_SCOPE_STORAGE_KEY) ??
+    ''
+  )
+}
+
+export function writeMemoryScopeToLocation(value: string) {
+  if (typeof window === 'undefined') return
+
+  const scope = parseMemoryScope(value)
+  const url = new URL(window.location.href)
+  url.searchParams.delete('pageNo')
+
+  if (scope.memoryId) {
+    url.searchParams.set(MEMORY_SCOPE_SEARCH_PARAM, scope.memoryId)
+    window.localStorage.setItem(MEMORY_SCOPE_STORAGE_KEY, scope.memoryId)
+  } else {
+    url.searchParams.delete(MEMORY_SCOPE_SEARCH_PARAM)
+    window.localStorage.removeItem(MEMORY_SCOPE_STORAGE_KEY)
+  }
+
+  window.history.replaceState(window.history.state, '', url)
+  window.dispatchEvent(
+    new PopStateEvent('popstate', { state: window.history.state })
+  )
+}
diff --git a/memind-ui/src/features/components/memory-scope-picker.tsx b/memind-ui/src/features/components/memory-scope-picker.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/components/memory-scope-picker.tsx
@@ -0,0 +1,39 @@
+import { useId, useState } from 'react'
+import { SlidersHorizontal } from 'lucide-react'
+import { Input } from '@/components/ui/input'
+import { Label } from '@/components/ui/label'
+import { parseMemoryScope } from '@/lib/memory-scope'
+import {
+  readMemoryScopeFromLocation,
+  writeMemoryScopeToLocation,
+} from './memory-scope-location'
+
+export function MemoryScopePicker() {
+  const id = useId()
+  const [value, setValue] = useState(() => readMemoryScopeFromLocation())
+
+  const scope = parseMemoryScope(value)
+  const title = scope.memoryId
+    ? `Scope: ${scope.memoryId}`
+    : 'Scope: all local memory data'
+
+  return (
+    <div className='flex min-w-0 items-center gap-2' title={title}>
+      <SlidersHorizontal aria-hidden='true' data-icon='inline-start' />
+      <Label htmlFor={id} className='sr-only'>
+        Memory scope
+      </Label>
+      <Input
+        id={id}
+        value={value}
+        placeholder='userId:agentId'
+        className='h-8 w-40 sm:w-56'
+        onChange={(event) => {
+          const next = event.target.value
+          setValue(next)
+          writeMemoryScopeToLocation(next)
+        }}
+      />
+    </div>
+  )
+}
diff --git a/memind-ui/src/features/components/server-status.tsx b/memind-ui/src/features/components/server-status.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/components/server-status.tsx
@@ -0,0 +1,34 @@
+import { useQuery } from '@tanstack/react-query'
+import { Badge } from '@/components/ui/badge'
+import { apiGet } from '@/lib/api-client'
+
+const SERVER_STATUS_REFETCH_INTERVAL_MS = 30_000
+
+type HealthResponse = {
+  status: string
+  service: string
+}
+
+export function ServerStatus() {
+  const query = useQuery({
+    queryKey: ['server-status'],
+    queryFn: () => apiGet<HealthResponse>('/open/v1/health'),
+    refetchInterval: SERVER_STATUS_REFETCH_INTERVAL_MS,
+    retry: false,
+  })
+
+  const status = query.isPending
+    ? 'connecting'
+    : query.isError
+      ? 'disconnected'
+      : 'connected'
+
+  return (
+    <Badge
+      variant={status === 'connected' ? 'secondary' : 'outline'}
+      aria-label={`server ${status}`}
+    >
+      {status}
+    </Badge>
+  )
+}
diff --git a/memind-ui/src/features/config/config-value-editor.tsx b/memind-ui/src/features/config/config-value-editor.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/config/config-value-editor.tsx
@@ -0,0 +1,216 @@
+import { useId, type ChangeEvent, type ReactNode } from 'react'
+import { compactJson } from '@/lib/format'
+import { Input } from '@/components/ui/input'
+import { Label } from '@/components/ui/label'
+import { Switch } from '@/components/ui/switch'
+import { Textarea } from '@/components/ui/textarea'
+import { JsonViewer } from '@/features/components/json-viewer'
+import type { JsonRecord, MemoryOptionItemView } from '@/features/types'
+
+type ConfigValueEditorProps = {
+  option: MemoryOptionItemView
+  onChange: (value: unknown) => void
+}
+
+export function ConfigValueEditor({
+  option,
+  onChange,
+}: ConfigValueEditorProps) {
+  const id = useId()
+  const enumOptions = readEnumOptions(option.constraints)
+
+  if (option.type === 'boolean') {
+    return (
+      <div className='flex min-w-0 items-center gap-3'>
+        <Switch
+          id={id}
+          checked={option.value === true}
+          onCheckedChange={onChange}
+        />
+        <Label
+          htmlFor={id}
+          className='min-w-0 leading-snug [overflow-wrap:anywhere] break-words'
+        >
+          <span className='min-w-0 [overflow-wrap:anywhere] break-words'>
+            {option.key}
+          </span>
+        </Label>
+      </div>
+    )
+  }
+
+  if (
+    option.type === 'integer' ||
+    option.type === 'double' ||
+    option.type === 'number'
+  ) {
+    const numericConstraints = readNumericConstraints(option.constraints)
+    return (
+      <EditorField label={option.key} id={id}>
+        <Input
+          id={id}
+          type='number'
+          value={toInputValue(option.value)}
+          min={numericConstraints.min}
+          max={numericConstraints.max}
+          step={option.type === 'integer' ? 1 : 'any'}
+          onChange={(event) =>
+            onChange(parseNumberValue(event, option.type === 'integer'))
+          }
+        />
+      </EditorField>
+    )
+  }
+
+  if (option.type === 'string' || option.type === 'enum') {
+    if (enumOptions.length > 0) {
+      return (
+        <EditorField label={option.key} id={id}>
+          <select
+            id={id}
+            value={toInputValue(option.value)}
+            className='h-9 w-full max-w-full min-w-0 rounded-md border bg-background px-3 text-sm'
+            onChange={(event) => onChange(event.target.value)}
+          >
+            {enumOptions.map((value) => (
+              <option key={value} value={value}>
+                {value}
+              </option>
+            ))}
+          </select>
+        </EditorField>
+      )
+    }
+
+    return (
+      <EditorField label={option.key} id={id}>
+        <Input
+          id={id}
+          type='text'
+          value={toInputValue(option.value)}
+          onChange={(event) => onChange(event.target.value)}
+        />
+      </EditorField>
+    )
+  }
+
+  if (option.type === 'duration') {
+    return (
+      <EditorField label={option.key} id={id}>
+        <Input
+          id={id}
+          type='text'
+          value={toInputValue(option.value)}
+          onChange={(event) => onChange(event.target.value)}
+        />
+      </EditorField>
+    )
+  }
+
+  return (
+    <EditorField label={`${option.key} JSON`} id={id}>
+      <div className='flex flex-col gap-3'>
+        <JsonViewer label={`${option.key} value`} value={option.value} />
+        <Textarea
+          id={id}
+          className='min-w-0'
+          value={compactJson(option.value)}
+          onChange={(event) => onChange(parseJsonOrText(event.target.value))}
+        />
+      </div>
+    </EditorField>
+  )
+}
+
+function EditorField({
+  label,
+  id,
+  children,
+}: {
+  label: string
+  id: string
+  children: ReactNode
+}) {
+  return (
+    <div className='flex min-w-0 flex-col gap-2'>
+      <Label
+        htmlFor={id}
+        className='min-w-0 leading-snug [overflow-wrap:anywhere] break-words'
+      >
+        <span className='min-w-0 [overflow-wrap:anywhere] break-words'>
+          {label}
+        </span>
+      </Label>
+      {children}
+    </div>
+  )
+}
+
+function toInputValue(value: unknown) {
+  if (value === null || value === undefined) return ''
+  return String(value)
+}
+
+function parseNumberValue(
+  event: ChangeEvent<HTMLInputElement>,
+  integer: boolean
+) {
+  const value = event.target.value
+  if (value === '') return null
+  const parsed = integer ? Number.parseInt(value, 10) : Number(value)
+  return Number.isFinite(parsed) ? parsed : null
+}
+
+function readNumericConstraints(constraints: JsonRecord | null) {
+  return {
+    min: readNumberConstraint(constraints, 'min'),
+    max: readNumberConstraint(constraints, 'max'),
+  }
+}
+
+function readNumberConstraint(
+  constraints: JsonRecord | null,
+  key: 'min' | 'max'
+) {
+  const value = constraints?.[key]
+  if (typeof value === 'number') return value
+  if (typeof value === 'string' && value.trim() !== '') {
+    const parsed = Number(value)
+    return Number.isFinite(parsed) ? parsed : undefined
+  }
+  return undefined
+}
+
+function readEnumOptions(constraints: JsonRecord | null) {
+  const value =
+    constraints?.enum ??
+    constraints?.options ??
+    constraints?.values ??
+    constraints?.allowedValues
+
+  if (!Array.isArray(value)) return []
+
+  return value
+    .map((item) => {
+      if (
+        typeof item === 'string' ||
+        typeof item === 'number' ||
+        typeof item === 'boolean'
+      ) {
+        return String(item)
+      }
+      if (item && typeof item === 'object' && 'value' in item) {
+        return String((item as { value: unknown }).value)
+      }
+      return ''
+    })
+    .filter(Boolean)
+}
+
+function parseJsonOrText(value: string) {
+  try {
+    return JSON.parse(value)
+  } catch {
+    return value
+  }
+}
diff --git a/memind-ui/src/features/config/index.tsx b/memind-ui/src/features/config/index.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/config/index.tsx
@@ -0,0 +1,379 @@
+import { useEffect, useMemo, useState } from 'react'
+import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
+import type { ApiError } from '@/lib/api-client'
+import { cn } from '@/lib/utils'
+import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert'
+import { Badge } from '@/components/ui/badge'
+import { Button } from '@/components/ui/button'
+import { Header } from '@/components/layout/header'
+import { Main } from '@/components/layout/main'
+import { getMemoryOptions, updateMemoryOptions } from '@/features/api/config'
+import {
+  EmptyState,
+  PageError,
+  PageLoading,
+} from '@/features/components/data-state'
+import type { MemoryOptionItemView } from '@/features/types'
+import { ConfigValueEditor } from './config-value-editor'
+
+export function ConfigPage() {
+  const queryClient = useQueryClient()
+  const query = useQuery({
+    queryKey: ['config', 'memory-options'],
+    queryFn: getMemoryOptions,
+  })
+  const [edits, setEdits] = useState<ConfigEdits>({})
+  const draft = useMemo(
+    () => (query.data ? buildDraftConfig(query.data.config, edits) : null),
+    [edits, query.data]
+  )
+  const sections = useMemo(() => (draft ? Object.entries(draft) : []), [draft])
+  const [selectedSectionKey, setSelectedSectionKey] = useState<string | null>(
+    null
+  )
+
+  const activeSection = useMemo(() => {
+    if (!selectedSectionKey) return sections[0] ?? null
+    return (
+      sections.find(([sectionKey]) => sectionKey === selectedSectionKey) ??
+      sections[0] ??
+      null
+    )
+  }, [selectedSectionKey, sections])
+
+  const modifiedCount = useMemo(
+    () => (query.data ? countModifiedEdits(query.data.config, edits) : 0),
+    [edits, query.data]
+  )
+  const isDirty = modifiedCount > 0
+
+  useEffect(() => {
+    if (!isDirty) return
+
+    const onBeforeUnload = (event: BeforeUnloadEvent) => {
+      event.preventDefault()
+      event.returnValue = ''
+    }
+
+    window.addEventListener('beforeunload', onBeforeUnload)
+    return () => window.removeEventListener('beforeunload', onBeforeUnload)
+  }, [isDirty])
+
+  const saveMutation = useMutation({
+    mutationFn: () => {
+      if (!query.data || !draft) {
+        throw new Error('Config is not loaded.')
+      }
+
+      return updateMemoryOptions({
+        expectedVersion: query.data.version,
+        config: draft,
+      })
+    },
+    onSuccess: (response) => {
+      setEdits({})
+      queryClient.setQueryData(['config', 'memory-options'], response)
+    },
+  })
+
+  const saveError = saveMutation.error as ApiError | null
+
+  const updateOptionValue = (
+    sectionKey: string,
+    optionKey: string,
+    value: unknown
+  ) => {
+    saveMutation.reset()
+    setEdits((current) => {
+      const originalValue = findOptionValue(
+        query.data?.config,
+        sectionKey,
+        optionKey
+      )
+      const section = { ...(current[sectionKey] ?? {}) }
+
+      if (jsonEqual(value, originalValue)) {
+        delete section[optionKey]
+      } else {
+        section[optionKey] = value
+      }
+
+      const next = { ...current }
+      if (Object.keys(section).length === 0) {
+        delete next[sectionKey]
+      } else {
+        next[sectionKey] = section
+      }
+      return next
+    })
+  }
+
+  return (
+    <>
+      <Header>
+        <h1 className='truncate text-lg font-semibold'>Settings</h1>
+      </Header>
+      <Main>
+        <div className='flex min-w-0 flex-col gap-4'>
+          <div className='flex flex-wrap items-start justify-between gap-3'>
+            <div className='flex min-w-0 flex-col gap-1'>
+              <h2 className='text-2xl font-semibold'>Memory Options</h2>
+              <p className='text-sm text-muted-foreground'>
+                Edit local memory options and save them as one versioned config
+                update.
+              </p>
+            </div>
+            <div className='flex items-center gap-2'>
+              {isDirty ? (
+                <Badge variant='secondary'>
+                  {modifiedCount} unsaved{' '}
+                  {modifiedCount === 1 ? 'change' : 'changes'}
+                </Badge>
+              ) : null}
+              <Button
+                type='button'
+                disabled={!isDirty || saveMutation.isPending}
+                onClick={() => saveMutation.mutate()}
+              >
+                Save changes
+              </Button>
+            </div>
+          </div>
+
+          {saveError?.status === 409 ? (
+            <Alert variant='destructive'>
+              <AlertTitle>Save conflict</AlertTitle>
+              <AlertDescription>
+                The server config changed. Refresh before saving again.
+              </AlertDescription>
+            </Alert>
+          ) : null}
+
+          {saveError && saveError.status !== 409 ? (
+            <PageError
+              message={saveError.message}
+              traceId={saveError.traceId}
+            />
+          ) : null}
+
+          {query.isLoading ? <PageLoading /> : null}
+          {query.isError ? (
+            <PageError
+              message='Unable to load memory options.'
+              onRetry={query.refetch}
+            />
+          ) : null}
+          {draft && Object.keys(draft).length === 0 ? (
+            <EmptyState title='No memory options found.' />
+          ) : null}
+          {sections.length > 0 && activeSection ? (
+            <div className='grid min-w-0 gap-4 lg:grid-cols-[minmax(15rem,18rem)_minmax(0,1fr)]'>
+              <ConfigSectionNav
+                sections={sections}
+                activeSectionKey={activeSection[0]}
+                onSelect={setSelectedSectionKey}
+              />
+              <ConfigSection
+                sectionKey={activeSection[0]}
+                options={activeSection[1]}
+                onChange={updateOptionValue}
+              />
+            </div>
+          ) : null}
+        </div>
+      </Main>
+    </>
+  )
+}
+
+function ConfigSectionNav({
+  sections,
+  activeSectionKey,
+  onSelect,
+}: {
+  sections: [string, MemoryOptionItemView[]][]
+  activeSectionKey: string
+  onSelect: (sectionKey: string) => void
+}) {
+  return (
+    <div className='min-w-0 lg:sticky lg:top-20 lg:self-start'>
+      <div className='min-w-0 rounded-md border p-3 lg:hidden'>
+        <label
+          htmlFor='config-section-select'
+          className='mb-2 block text-xs font-medium text-muted-foreground'
+        >
+          Section
+        </label>
+        <select
+          id='config-section-select'
+          className='h-9 w-full min-w-0 rounded-md border bg-background px-3 text-sm'
+          value={activeSectionKey}
+          onChange={(event) => onSelect(event.target.value)}
+        >
+          {sections.map(([sectionKey, options]) => (
+            <option key={sectionKey} value={sectionKey}>
+              {formatSectionLabel(sectionKey)} ({options.length})
+            </option>
+          ))}
+        </select>
+      </div>
+
+      <nav
+        aria-label='Config sections'
+        className='hidden min-w-0 rounded-md border lg:block'
+      >
+        <div className='border-b px-3 py-2'>
+          <p className='text-xs font-medium text-muted-foreground'>
+            Sections ({sections.length})
+          </p>
+        </div>
+        <div className='flex min-w-0 flex-col gap-1 overflow-y-auto p-2 lg:max-h-[calc(100vh-12rem)]'>
+          {sections.map(([sectionKey, options]) => {
+            const isActive = sectionKey === activeSectionKey
+
+            return (
+              <button
+                key={sectionKey}
+                type='button'
+                aria-label={`${formatSectionLabel(sectionKey)} ${options.length}`}
+                aria-current={isActive ? 'page' : undefined}
+                className={cn(
+                  'flex min-w-0 items-start justify-between gap-3 rounded-md px-3 py-2 text-left transition-colors',
+                  isActive
+                    ? 'bg-accent text-accent-foreground'
+                    : 'hover:bg-accent/60'
+                )}
+                onClick={() => onSelect(sectionKey)}
+              >
+                <span className='flex min-w-0 flex-col gap-0.5'>
+                  <span className='font-medium [overflow-wrap:anywhere] break-words'>
+                    {formatSectionLabel(sectionKey)}
+                  </span>
+                  <span className='text-xs [overflow-wrap:anywhere] break-words text-muted-foreground'>
+                    {sectionKey}
+                  </span>
+                </span>
+                <Badge variant='secondary'>{options.length}</Badge>
+              </button>
+            )
+          })}
+        </div>
+      </nav>
+    </div>
+  )
+}
+
+function ConfigSection({
+  sectionKey,
+  options,
+  onChange,
+}: {
+  sectionKey: string
+  options: MemoryOptionItemView[]
+  onChange: (sectionKey: string, optionKey: string, value: unknown) => void
+}) {
+  return (
+    <section className='min-w-0 rounded-md border'>
+      <div className='flex min-w-0 flex-col gap-1 border-b px-4 py-3'>
+        <h3 className='text-base font-semibold [overflow-wrap:anywhere] break-words'>
+          {formatSectionLabel(sectionKey)}
+        </h3>
+        <p className='text-xs [overflow-wrap:anywhere] break-words text-muted-foreground'>
+          {sectionKey}
+        </p>
+      </div>
+      <div className='min-w-0 divide-y'>
+        {options.map((option) => (
+          <div
+            key={option.key}
+            className='grid min-w-0 gap-3 p-4 lg:grid-cols-[minmax(0,20rem)_minmax(0,1fr)]'
+          >
+            <div className='flex min-w-0 flex-col gap-1'>
+              <p className='font-medium [overflow-wrap:anywhere] break-words'>
+                {option.key}
+              </p>
+              <p className='text-sm [overflow-wrap:anywhere] break-words text-muted-foreground'>
+                {option.description ?? 'No description.'}
+              </p>
+              <p className='text-xs [overflow-wrap:anywhere] break-words text-muted-foreground'>
+                type: {option.type}
+              </p>
+            </div>
+            <ConfigValueEditor
+              option={option}
+              onChange={(value) => onChange(sectionKey, option.key, value)}
+            />
+          </div>
+        ))}
+      </div>
+    </section>
+  )
+}
+
+type ConfigEdits = Record<string, Record<string, unknown>>
+
+function buildDraftConfig(
+  config: Record<string, MemoryOptionItemView[]>,
+  edits: ConfigEdits
+) {
+  return Object.fromEntries(
+    Object.entries(config).map(([sectionKey, options]) => [
+      sectionKey,
+      options.map((option) => {
+        const sectionEdits = edits[sectionKey] ?? {}
+        return {
+          ...option,
+          value: Object.prototype.hasOwnProperty.call(sectionEdits, option.key)
+            ? sectionEdits[option.key]
+            : option.value,
+        }
+      }),
+    ])
+  )
+}
+
+function countModifiedEdits(
+  original: Record<string, MemoryOptionItemView[]>,
+  edits: ConfigEdits
+) {
+  let count = 0
+
+  for (const [sectionKey, values] of Object.entries(edits)) {
+    for (const [optionKey, value] of Object.entries(values)) {
+      if (!jsonEqual(value, findOptionValue(original, sectionKey, optionKey))) {
+        count += 1
+      }
+    }
+  }
+
+  return count
+}
+
+function findOptionValue(
+  config: Record<string, MemoryOptionItemView[]> | undefined,
+  sectionKey: string,
+  optionKey: string
+) {
+  return config?.[sectionKey]?.find((option) => option.key === optionKey)?.value
+}
+
+function jsonEqual(left: unknown, right: unknown) {
+  return JSON.stringify(left) === JSON.stringify(right)
+}
+
+function formatSectionLabel(sectionKey: string) {
+  return sectionKey
+    .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
+    .split(/[.\s_-]+/)
+    .filter(Boolean)
+    .map(formatSectionLabelSegment)
+    .join(' ')
+}
+
+function formatSectionLabelSegment(segment: string) {
+  if (segment.toLowerCase() === 'rawdata') {
+    return 'Raw Data'
+  }
+
+  return segment.charAt(0).toUpperCase() + segment.slice(1)
+}
diff --git a/memind-ui/src/features/dashboard/index.tsx b/memind-ui/src/features/dashboard/index.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/dashboard/index.tsx
@@ -0,0 +1,399 @@
+import { useMemo, useState } from 'react'
+import { useQuery } from '@tanstack/react-query'
+import { Header } from '@/components/layout/header'
+import { Main } from '@/components/layout/main'
+import {
+  Card,
+  CardContent,
+  CardDescription,
+  CardHeader,
+  CardTitle,
+} from '@/components/ui/card'
+import { Label } from '@/components/ui/label'
+import { getDashboard } from '@/features/api/dashboard'
+import {
+  EmptyState,
+  PageError,
+  PageLoading,
+} from '@/features/components/data-state'
+import { readMemoryScopeFromLocation } from '@/features/components/memory-scope-location'
+import { formatNumber } from '@/lib/format'
+import type { AdminDashboardView, DailyCount, NamedCount } from '@/features/types'
+
+export function DashboardPage() {
+  const [days, setDays] = useState(() => readDaysFromLocation())
+  const memoryId = readMemoryScopeFromLocation()
+  const query = useQuery({
+    queryKey: ['dashboard', memoryId, days],
+    queryFn: () => getDashboard({ memoryId, days }),
+  })
+
+  return (
+    <>
+      <Header>
+        <div className='min-w-0'>
+          <h1 className='truncate text-lg font-semibold'>Memind UI</h1>
+          <p className='truncate text-sm text-muted-foreground'>
+            Local Memory Admin
+          </p>
+        </div>
+      </Header>
+      <Main>
+        <div className='flex flex-col gap-6'>
+          <div className='flex flex-wrap items-center justify-between gap-3'>
+            <div className='flex flex-col gap-1'>
+              <h2 className='text-2xl font-semibold'>Dashboard</h2>
+              <p className='text-sm text-muted-foreground'>
+                Local memory activity and maintenance backlog.
+              </p>
+            </div>
+            <div className='flex items-center gap-2'>
+              <Label htmlFor='dashboard-days'>Activity days</Label>
+              <select
+                id='dashboard-days'
+                aria-label='Activity days'
+                value={days}
+                className='h-9 rounded-md border bg-background px-3 text-sm'
+                onChange={(event) => {
+                  const next = Number(event.target.value)
+                  setDays(next)
+                  writeDaysToLocation(next)
+                }}
+              >
+                <option value={7}>7</option>
+                <option value={14}>14</option>
+                <option value={30}>30</option>
+              </select>
+            </div>
+          </div>
+
+          {query.isLoading ? <PageLoading /> : null}
+          {query.isError ? (
+            <PageError message='Unable to load dashboard.' onRetry={query.refetch} />
+          ) : null}
+          {query.data ? <DashboardContent data={query.data} memoryId={memoryId} /> : null}
+        </div>
+      </Main>
+    </>
+  )
+}
+
+function DashboardContent({
+  data,
+  memoryId,
+}: {
+  data: AdminDashboardView
+  memoryId: string
+}) {
+  const isZero = useMemo(() => isZeroDashboard(data), [data])
+
+  if (isZero) {
+    return <EmptyState title='No memory activity for this scope yet.' />
+  }
+
+  return (
+    <div className='flex flex-col gap-6'>
+      <MetricGrid data={data} />
+      <BacklogGrid backlog={data.backlog} memoryId={memoryId} />
+      <ActivityPanel activity={data.activity} />
+      <BreakdownPanel breakdown={data.breakdown} />
+      <HealthPanel healthSignals={data.healthSignals} />
+    </div>
+  )
+}
+
+function MetricGrid({ data }: { data: AdminDashboardView }) {
+  const metrics = [
+    ['Raw Data', data.totals.rawData],
+    ['Memory Items', data.totals.items],
+    ['Insights', data.totals.insights],
+    ['Memory Threads', data.totals.memoryThreads],
+    ['Graph Entities', data.totals.graphEntities],
+    ['Item Links', data.totals.itemLinks],
+  ] as const
+
+  return (
+    <div className='grid gap-4 md:grid-cols-2 xl:grid-cols-3'>
+      {metrics.map(([label, value]) => (
+        <Card key={label} aria-label={`${label} ${value}`}>
+          <CardHeader>
+            <CardDescription>{label}</CardDescription>
+            <CardTitle className='text-3xl'>{formatNumber(value)}</CardTitle>
+          </CardHeader>
+        </Card>
+      ))}
+    </div>
+  )
+}
+
+function BacklogGrid({
+  backlog,
+  memoryId,
+}: {
+  backlog: AdminDashboardView['backlog']
+  memoryId: string
+}) {
+  const links = [
+    {
+      label: 'pending conversations',
+      value: backlog.conversationPending,
+      href: backlogHref('/buffers', [
+        ['tab', 'conversations'],
+        ['state', 'pending'],
+        ['memoryId', memoryId],
+      ]),
+    },
+    {
+      label: 'unbuilt insights',
+      value: backlog.insightUnbuilt,
+      href: backlogHref('/buffers', [
+        ['tab', 'insights'],
+        ['state', 'unbuilt'],
+        ['memoryId', memoryId],
+      ]),
+    },
+    {
+      label: 'ungrouped insights',
+      value: backlog.insightUngrouped,
+      href: backlogHref('/buffers', [
+        ['tab', 'insights'],
+        ['state', 'ungrouped'],
+        ['memoryId', memoryId],
+      ]),
+    },
+    {
+      label: 'thread outbox pending',
+      value: backlog.threadOutboxPending,
+      href: backlogHref('/memory-threads', [
+        ['focus', 'status'],
+        ['memoryId', memoryId],
+      ]),
+    },
+    {
+      label: 'thread outbox failed',
+      value: backlog.threadOutboxFailed,
+      href: backlogHref('/memory-threads', [
+        ['focus', 'status'],
+        ['memoryId', memoryId],
+      ]),
+    },
+    {
+      label: 'graph batches needing repair',
+      value: backlog.graphBatchRepairRequired,
+      href: backlogHref('/item-graph', [
+        ['tab', 'batches'],
+        ['state', 'REPAIR_REQUIRED'],
+        ['memoryId', memoryId],
+      ]),
+    },
+  ]
+
+  return (
+    <Card>
+      <CardHeader>
+        <CardTitle>Backlog</CardTitle>
+        <CardDescription>Maintenance queues with direct drill-down links.</CardDescription>
+      </CardHeader>
+      <CardContent>
+        <div className='grid gap-2 md:grid-cols-2 xl:grid-cols-3'>
+          {links.map((link) => (
+            <a
+              key={link.label}
+              href={link.href}
+              className='rounded-md border p-3 text-sm hover:bg-accent'
+            >
+              <span>{link.label}</span> <span>{formatNumber(link.value)}</span>
+            </a>
+          ))}
+        </div>
+      </CardContent>
+    </Card>
+  )
+}
+
+function ActivityPanel({
+  activity,
+}: {
+  activity: AdminDashboardView['activity']
+}) {
+  const rows = mergeActivityRows(
+    activity.rawDataCreated,
+    activity.itemsCreated,
+    activity.insightsCreated
+  )
+
+  return (
+    <Card>
+      <CardHeader>
+        <CardTitle>Activity</CardTitle>
+        <CardDescription>{activity.days} day creation trend.</CardDescription>
+      </CardHeader>
+      <CardContent>
+        <div className='overflow-auto'>
+          <table className='w-full text-sm'>
+            <thead>
+              <tr className='border-b text-left'>
+                <th className='py-2 font-medium'>Date</th>
+                <th className='py-2 font-medium'>Raw data</th>
+                <th className='py-2 font-medium'>Items</th>
+                <th className='py-2 font-medium'>Insights</th>
+              </tr>
+            </thead>
+            <tbody>
+              {rows.map((row) => (
+                <tr key={row.date} className='border-b'>
+                  <td className='py-2'>{row.date}</td>
+                  <td className='py-2'>{formatNumber(row.rawData)}</td>
+                  <td className='py-2'>{formatNumber(row.items)}</td>
+                  <td className='py-2'>{formatNumber(row.insights)}</td>
+                </tr>
+              ))}
+            </tbody>
+          </table>
+        </div>
+      </CardContent>
+    </Card>
+  )
+}
+
+function BreakdownPanel({
+  breakdown,
+}: {
+  breakdown: AdminDashboardView['breakdown']
+}) {
+  return (
+    <div className='grid gap-4 lg:grid-cols-2'>
+      <BreakdownCard title='Source Clients' values={breakdown.sourceClients} />
+      <BreakdownCard title='Raw Data Types' values={breakdown.rawDataTypes} />
+      <BreakdownCard title='Item Types' values={breakdown.itemTypes} />
+      <BreakdownCard title='Insight Types' values={breakdown.insightTypes} />
+      <BreakdownCard title='Graph Link Types' values={breakdown.graphLinkTypes} />
+    </div>
+  )
+}
+
+function BreakdownCard({ title, values }: { title: string; values: NamedCount[] }) {
+  return (
+    <Card>
+      <CardHeader>
+        <CardTitle>{title}</CardTitle>
+      </CardHeader>
+      <CardContent>
+        {values.length === 0 ? (
+          <p className='text-sm text-muted-foreground'>No data.</p>
+        ) : (
+          <ul className='flex flex-col gap-2 text-sm'>
+            {values.map((value) => (
+              <li key={value.name} className='flex items-center justify-between gap-4'>
+                <span className='truncate'>{value.name}</span>
+                <span>{formatNumber(value.count)}</span>
+              </li>
+            ))}
+          </ul>
+        )}
+      </CardContent>
+    </Card>
+  )
+}
+
+function HealthPanel({
+  healthSignals,
+}: {
+  healthSignals: AdminDashboardView['healthSignals']
+}) {
+  return (
+    <Card>
+      <CardHeader>
+        <CardTitle>Health Signals</CardTitle>
+      </CardHeader>
+      <CardContent>
+        <div className='grid gap-3 text-sm md:grid-cols-2'>
+          <p>Graph enabled: {healthSignals.graphEnabled ? 'yes' : 'no'}</p>
+          <p>
+            Retrieval graph assist:{' '}
+            {healthSignals.retrievalGraphAssistEnabled ? 'yes' : 'no'}
+          </p>
+        </div>
+        {healthSignals.threadProjectionStates.length > 0 ? (
+          <ul className='mt-4 flex flex-col gap-2 text-sm'>
+            {healthSignals.threadProjectionStates.map((state) => (
+              <li key={state.state}>
+                {state.state}: {formatNumber(state.count)}
+              </li>
+            ))}
+          </ul>
+        ) : null}
+      </CardContent>
+    </Card>
+  )
+}
+
+function readDaysFromLocation() {
+  if (typeof window === 'undefined') return 7
+  const raw = new URLSearchParams(window.location.search).get('days')
+  const parsed = raw ? Number(raw) : 7
+  return [7, 14, 30].includes(parsed) ? parsed : 7
+}
+
+function writeDaysToLocation(days: number) {
+  if (typeof window === 'undefined') return
+  const url = new URL(window.location.href)
+  if (days === 7) {
+    url.searchParams.delete('days')
+  } else {
+    url.searchParams.set('days', String(days))
+  }
+  window.history.replaceState(window.history.state, '', url)
+}
+
+function backlogHref(path: string, pairs: Array<[string, string | undefined]>) {
+  const params = new URLSearchParams()
+  for (const [key, value] of pairs) {
+    if (value) params.append(key, value)
+  }
+  const query = params.toString()
+  return query ? `${path}?${query}` : path
+}
+
+function isZeroDashboard(data: AdminDashboardView) {
+  return (
+    Object.values(data.totals).every((value) => value === 0) &&
+    Object.values(data.backlog).every((value) => value === 0)
+  )
+}
+
+function mergeActivityRows(
+  rawDataCreated: DailyCount[],
+  itemsCreated: DailyCount[],
+  insightsCreated: DailyCount[]
+) {
+  const rows = new Map<
+    string,
+    { date: string; rawData: number; items: number; insights: number }
+  >()
+
+  for (const item of rawDataCreated) {
+    rows.set(item.date, {
+      ...(rows.get(item.date) ?? emptyActivityRow(item.date)),
+      rawData: item.count,
+    })
+  }
+  for (const item of itemsCreated) {
+    rows.set(item.date, {
+      ...(rows.get(item.date) ?? emptyActivityRow(item.date)),
+      items: item.count,
+    })
+  }
+  for (const item of insightsCreated) {
+    rows.set(item.date, {
+      ...(rows.get(item.date) ?? emptyActivityRow(item.date)),
+      insights: item.count,
+    })
+  }
+
+  return [...rows.values()].sort((a, b) => a.date.localeCompare(b.date))
+}
+
+function emptyActivityRow(date: string) {
+  return { date, rawData: 0, items: 0, insights: 0 }
+}
diff --git a/memind-ui/src/features/errors/general-error.tsx b/memind-ui/src/features/errors/general-error.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/errors/general-error.tsx
@@ -0,0 +1,38 @@
+import { useNavigate, useRouter } from '@tanstack/react-router'
+import { cn } from '@/lib/utils'
+import { Button } from '@/components/ui/button'
+
+type GeneralErrorProps = React.HTMLAttributes<HTMLDivElement> & {
+  minimal?: boolean
+}
+
+export function GeneralError({
+  className,
+  minimal = false,
+}: GeneralErrorProps) {
+  const navigate = useNavigate()
+  const { history } = useRouter()
+  return (
+    <div className={cn('h-svh w-full', className)}>
+      <div className='m-auto flex h-full w-full flex-col items-center justify-center gap-2'>
+        {!minimal && (
+          <h1 className='text-[7rem] leading-tight font-bold'>500</h1>
+        )}
+        <span className='font-medium'>Oops! Something went wrong {`:')`}</span>
+        <p className='text-center text-muted-foreground'>
+          We apologize for the inconvenience. <br /> Please try again later.
+        </p>
+        {!minimal && (
+          <div className='mt-6 flex gap-4'>
+            <Button variant='outline' onClick={() => history.go(-1)}>
+              Go Back
+            </Button>
+            <Button onClick={() => navigate({ to: '/', search: {} })}>
+              Back to Home
+            </Button>
+          </div>
+        )}
+      </div>
+    </div>
+  )
+}
diff --git a/memind-ui/src/features/errors/maintenance-error.tsx b/memind-ui/src/features/errors/maintenance-error.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/errors/maintenance-error.tsx
@@ -0,0 +1,19 @@
+import { Button } from '@/components/ui/button'
+
+export function MaintenanceError() {
+  return (
+    <div className='h-svh'>
+      <div className='m-auto flex h-full w-full flex-col items-center justify-center gap-2'>
+        <h1 className='text-[7rem] leading-tight font-bold'>503</h1>
+        <span className='font-medium'>Website is under maintenance!</span>
+        <p className='text-center text-muted-foreground'>
+          The site is not available at the moment. <br />
+          We'll be back online shortly.
+        </p>
+        <div className='mt-6 flex gap-4'>
+          <Button variant='outline'>Learn more</Button>
+        </div>
+      </div>
+    </div>
+  )
+}
diff --git a/memind-ui/src/features/errors/not-found-error.tsx b/memind-ui/src/features/errors/not-found-error.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/errors/not-found-error.tsx
@@ -0,0 +1,27 @@
+import { useNavigate, useRouter } from '@tanstack/react-router'
+import { Button } from '@/components/ui/button'
+
+export function NotFoundError() {
+  const navigate = useNavigate()
+  const { history } = useRouter()
+  return (
+    <div className='h-svh'>
+      <div className='m-auto flex h-full w-full flex-col items-center justify-center gap-2'>
+        <h1 className='text-[7rem] leading-tight font-bold'>404</h1>
+        <span className='font-medium'>Oops! Page Not Found!</span>
+        <p className='text-center text-muted-foreground'>
+          It seems like the page you're looking for <br />
+          does not exist or might have been removed.
+        </p>
+        <div className='mt-6 flex gap-4'>
+          <Button variant='outline' onClick={() => history.go(-1)}>
+            Go Back
+          </Button>
+          <Button onClick={() => navigate({ to: '/', search: {} })}>
+            Back to Home
+          </Button>
+        </div>
+      </div>
+    </div>
+  )
+}
diff --git a/memind-ui/src/features/insights/index.tsx b/memind-ui/src/features/insights/index.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/insights/index.tsx
@@ -0,0 +1,392 @@
+import { useMemo, useState } from 'react'
+import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
+import { Header } from '@/components/layout/header'
+import { Main } from '@/components/layout/main'
+import { Badge } from '@/components/ui/badge'
+import { Button } from '@/components/ui/button'
+import { Checkbox } from '@/components/ui/checkbox'
+import {
+  Dialog,
+  DialogContent,
+  DialogDescription,
+  DialogHeader,
+  DialogTitle,
+} from '@/components/ui/dialog'
+import {
+  Table,
+  TableBody,
+  TableCell,
+  TableHead,
+  TableHeader,
+  TableRow,
+} from '@/components/ui/table'
+import {
+  deleteInsights,
+  getInsight,
+  listInsights,
+  type InsightListParams,
+} from '@/features/api/insights'
+import { ConfirmResultDialog } from '@/features/components/confirm-result-dialog'
+import {
+  EmptyState,
+  PageError,
+  PageLoading,
+  TableLoading,
+} from '@/features/components/data-state'
+import { JsonViewer } from '@/features/components/json-viewer'
+import { readMemoryScopeFromLocation } from '@/features/components/memory-scope-location'
+import type { AdminInsightView, InsightPoint } from '@/features/types'
+import { compactJson, formatDateTime, truncateText } from '@/lib/format'
+import { toUserAgentQuery } from '@/lib/memory-scope'
+
+const DEFAULT_PAGE = 1
+const DEFAULT_PAGE_SIZE = 10
+
+export function InsightsPage() {
+  const queryClient = useQueryClient()
+  const [selectedIds, setSelectedIds] = useState<Set<number>>(() => new Set())
+  const [deleteOpen, setDeleteOpen] = useState(false)
+  const [detailInsightId, setDetailInsightId] = useState<number | null>(
+    null
+  )
+
+  const search = readInsightsSearch()
+  const memoryScope = readMemoryScopeFromLocation()
+  const params = useMemo(
+    () => buildInsightListParams(search, memoryScope),
+    [search, memoryScope]
+  )
+  const insightsQuery = useQuery({
+    queryKey: ['insights', params],
+    queryFn: () => listInsights(params),
+  })
+  const deleteMutation = useMutation({
+    mutationFn: (insightIds: number[]) => deleteInsights(insightIds),
+    onSuccess: async () => {
+      setSelectedIds(new Set())
+      await Promise.all([
+        queryClient.invalidateQueries({ queryKey: ['insights'] }),
+        queryClient.invalidateQueries({ queryKey: ['dashboard'] }),
+      ])
+    },
+  })
+
+  const rows = insightsQuery.data?.list ?? []
+  const selectedInsightIds = [...selectedIds]
+
+  return (
+    <>
+      <Header>
+        <h1 className='truncate text-lg font-semibold'>Insight Tree</h1>
+      </Header>
+      <Main>
+        <div className='flex flex-col gap-4'>
+          <div className='flex flex-wrap items-center justify-between gap-3'>
+            <div className='flex flex-col gap-1'>
+              <h2 className='text-2xl font-semibold'>Insight Tree</h2>
+              <p className='text-sm text-muted-foreground'>
+                Inspect extracted long-lived insights, reasoning points, and
+                relationships.
+              </p>
+            </div>
+            <Button
+              type='button'
+              variant='destructive'
+              disabled={selectedIds.size === 0}
+              onClick={() => {
+                deleteMutation.reset()
+                setDeleteOpen(true)
+              }}
+            >
+              Delete selected
+            </Button>
+          </div>
+
+          {insightsQuery.isLoading ? <TableLoading columns={8} /> : null}
+          {insightsQuery.isError ? (
+            <PageError
+              message='Unable to load insights.'
+              onRetry={insightsQuery.refetch}
+            />
+          ) : null}
+          {insightsQuery.data && rows.length === 0 ? (
+            <EmptyState title='No insights found.' />
+          ) : null}
+          {rows.length > 0 ? (
+            <InsightsTable
+              rows={rows}
+              selectedIds={selectedIds}
+              onToggleSelected={(insightId, checked) => {
+                setSelectedIds((current) => {
+                  const next = new Set(current)
+                  if (checked) {
+                    next.add(insightId)
+                  } else {
+                    next.delete(insightId)
+                  }
+                  return next
+                })
+              }}
+              onView={setDetailInsightId}
+            />
+          ) : null}
+
+          {insightsQuery.data ? (
+            <p className='text-sm text-muted-foreground'>
+              Total rows: {insightsQuery.data.total}
+            </p>
+          ) : null}
+        </div>
+      </Main>
+
+      <ConfirmResultDialog
+        open={deleteOpen}
+        onOpenChange={setDeleteOpen}
+        title='Delete selected insights'
+        selectedCount={selectedInsightIds.length}
+        description='Only the selected insight ids will be sent to the server.'
+        isPending={deleteMutation.isPending}
+        result={deleteMutation.data ? { ...deleteMutation.data } : null}
+        onConfirm={() => deleteMutation.mutate(selectedInsightIds)}
+      />
+
+      <InsightDetailDialog
+        insightId={detailInsightId}
+        onOpenChange={(open) => {
+          if (!open) setDetailInsightId(null)
+        }}
+      />
+    </>
+  )
+}
+
+function InsightsTable({
+  rows,
+  selectedIds,
+  onToggleSelected,
+  onView,
+}: {
+  rows: AdminInsightView[]
+  selectedIds: Set<number>
+  onToggleSelected: (insightId: number, checked: boolean) => void
+  onView: (insightId: number) => void
+}) {
+  return (
+    <Table>
+      <TableHeader>
+        <TableRow>
+          <TableHead className='w-10'>Select</TableHead>
+          <TableHead>Insight ID</TableHead>
+          <TableHead>Memory ID</TableHead>
+          <TableHead>Name / Content</TableHead>
+          <TableHead>Type</TableHead>
+          <TableHead>Tier</TableHead>
+          <TableHead>Scope</TableHead>
+          <TableHead>Group Name</TableHead>
+          <TableHead>Updated At</TableHead>
+          <TableHead className='text-end'>Actions</TableHead>
+        </TableRow>
+      </TableHeader>
+      <TableBody>
+        {rows.map((insight) => (
+          <TableRow key={insight.insightId}>
+            <TableCell>
+              <Checkbox
+                aria-label={`Select insight ${insight.insightId}`}
+                checked={selectedIds.has(insight.insightId)}
+                onCheckedChange={(checked) =>
+                  onToggleSelected(insight.insightId, checked === true)
+                }
+              />
+            </TableCell>
+            <TableCell>{insight.insightId}</TableCell>
+            <TableCell>{insight.memoryId}</TableCell>
+            <TableCell className='max-w-96 whitespace-normal'>
+              {truncateText(insight.name || insight.content, 120)}
+            </TableCell>
+            <TableCell>
+              {insight.type ? <Badge>{insight.type}</Badge> : '-'}
+            </TableCell>
+            <TableCell>{fieldValue(insight.tier)}</TableCell>
+            <TableCell>{fieldValue(insight.scope)}</TableCell>
+            <TableCell>{fieldValue(insight.groupName)}</TableCell>
+            <TableCell>{formatDateTime(insight.updatedAt)}</TableCell>
+            <TableCell className='text-end'>
+              <Button
+                type='button'
+                variant='outline'
+                size='sm'
+                aria-label={`View insight ${insight.insightId}`}
+                onClick={() => onView(insight.insightId)}
+              >
+                View
+              </Button>
+            </TableCell>
+          </TableRow>
+        ))}
+      </TableBody>
+    </Table>
+  )
+}
+
+function InsightDetailDialog({
+  insightId,
+  onOpenChange,
+}: {
+  insightId: number | null
+  onOpenChange: (open: boolean) => void
+}) {
+  const query = useQuery({
+    queryKey: ['insights', insightId, 'detail'],
+    enabled: insightId !== null,
+    queryFn: () => getInsight(insightId as number),
+  })
+  const insight = query.data
+
+  return (
+    <Dialog open={insightId !== null} onOpenChange={onOpenChange}>
+      <DialogContent className='max-h-[85vh] overflow-auto sm:max-w-3xl'>
+        <DialogHeader>
+          <DialogTitle>Insight {insightId}</DialogTitle>
+          <DialogDescription>{insight?.memoryId}</DialogDescription>
+        </DialogHeader>
+
+        {query.isLoading ? <PageLoading /> : null}
+        {query.isError ? (
+          <PageError
+            message='Unable to load insight detail.'
+            onRetry={query.refetch}
+          />
+        ) : null}
+        {insight ? (
+          <div className='flex flex-col gap-5 text-sm'>
+            <section className='flex flex-col gap-2'>
+              <h3 className='font-medium'>Content</h3>
+              <p className='whitespace-pre-wrap rounded-md bg-muted p-3'>
+                {insight.content}
+              </p>
+            </section>
+
+            <section className='flex flex-col gap-2'>
+              <h3 className='font-medium'>Categories</h3>
+              {insight.categories.length > 0 ? (
+                <div className='flex flex-wrap gap-2'>
+                  {insight.categories.map((category) => (
+                    <Badge key={category} variant='secondary'>
+                      {category}
+                    </Badge>
+                  ))}
+                </div>
+              ) : (
+                <p>-</p>
+              )}
+            </section>
+
+            <section className='flex flex-col gap-2'>
+              <h3 className='font-medium'>Points</h3>
+              {insight.points.length > 0 ? (
+                <ul className='flex flex-col gap-1'>
+                  {insight.points.map((point, index) => (
+                    <li key={pointKey(point, index)}>{pointText(point)}</li>
+                  ))}
+                </ul>
+              ) : (
+                <p>-</p>
+              )}
+            </section>
+
+            <div className='grid gap-2 md:grid-cols-2'>
+              <p>type: {fieldValue(insight.type)}</p>
+              <p>tier: {fieldValue(insight.tier)}</p>
+              <p>scope: {fieldValue(insight.scope)}</p>
+              <p>groupName: {fieldValue(insight.groupName)}</p>
+              <p>parentInsightId: {fieldValue(insight.parentInsightId)}</p>
+              <p>childInsightIds: {fieldValue(insight.childInsightIds)}</p>
+              <p>version: {fieldValue(insight.version)}</p>
+              <p>lastReasonedAt: {formatDateTime(insight.lastReasonedAt)}</p>
+              <p>createdAt: {formatDateTime(insight.createdAt)}</p>
+              <p>updatedAt: {formatDateTime(insight.updatedAt)}</p>
+            </div>
+
+            <JsonViewer
+              label='summaryEmbedding'
+              value={insight.summaryEmbedding ?? []}
+            />
+          </div>
+        ) : null}
+      </DialogContent>
+    </Dialog>
+  )
+}
+
+function buildInsightListParams(
+  search: InsightSearch,
+  memoryScope: string
+): InsightListParams {
+  return {
+    pageNo: search.pageNo,
+    pageSize: search.pageSize,
+    ...toUserAgentQuery(memoryScope),
+    scope: search.scope,
+    type: search.type,
+    tier: search.tier,
+  }
+}
+
+type InsightSearch = {
+  pageNo: number
+  pageSize: number
+  scope?: string
+  type?: string
+  tier?: string
+}
+
+function readInsightsSearch(): InsightSearch {
+  const params = readSearchParams()
+  return {
+    pageNo: readNumberParam(params, 'pageNo', DEFAULT_PAGE),
+    pageSize: readNumberParam(params, 'pageSize', DEFAULT_PAGE_SIZE),
+    scope: readStringParam(params, 'scope'),
+    type: readStringParam(params, 'type'),
+    tier: readStringParam(params, 'tier'),
+  }
+}
+
+function readSearchParams() {
+  if (typeof window === 'undefined') return new URLSearchParams()
+  return new URLSearchParams(window.location.search)
+}
+
+function readStringParam(params: URLSearchParams, key: string) {
+  const value = params.get(key)?.trim()
+  return value ? value : undefined
+}
+
+function readNumberParam(
+  params: URLSearchParams,
+  key: string,
+  fallback: number
+) {
+  const value = params.get(key)
+  if (!value) return fallback
+  const parsed = Number(value)
+  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback
+}
+
+function pointText(point: InsightPoint) {
+  const text = point.text
+  return typeof text === 'string' && text.trim() !== ''
+    ? text
+    : compactJson(point)
+}
+
+function pointKey(point: InsightPoint, index: number) {
+  return `${index}:${compactJson(point)}`
+}
+
+function fieldValue(value: unknown) {
+  if (value === null || value === undefined || value === '') return '-'
+  if (Array.isArray(value)) return value.length > 0 ? value.join(', ') : '-'
+  if (typeof value === 'object') return compactJson(value)
+  return String(value)
+}
diff --git a/memind-ui/src/features/item-graph/entity-detail-drawer.tsx b/memind-ui/src/features/item-graph/entity-detail-drawer.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/item-graph/entity-detail-drawer.tsx
@@ -0,0 +1,125 @@
+import { useQuery } from '@tanstack/react-query'
+import {
+  Dialog,
+  DialogContent,
+  DialogDescription,
+  DialogHeader,
+  DialogTitle,
+} from '@/components/ui/dialog'
+import {
+  Table,
+  TableBody,
+  TableCell,
+  TableHead,
+  TableHeader,
+  TableRow,
+} from '@/components/ui/table'
+import { getGraphEntity } from '@/features/api/item-graph'
+import { PageError, PageLoading } from '@/features/components/data-state'
+import { JsonViewer } from '@/features/components/json-viewer'
+import type { GraphEntityDetailView } from '@/features/types'
+import { formatDateTime } from '@/lib/format'
+
+export function EntityDetailDrawer({
+  entityId,
+  onOpenChange,
+}: {
+  entityId: number | null
+  onOpenChange: (open: boolean) => void
+}) {
+  const query = useQuery({
+    queryKey: ['item-graph', 'entities', entityId, 'detail'],
+    enabled: entityId !== null,
+    queryFn: () => getGraphEntity(entityId as number),
+  })
+
+  return (
+    <Dialog open={entityId !== null} onOpenChange={onOpenChange}>
+      <DialogContent className='max-h-[85vh] overflow-auto sm:max-w-4xl'>
+        <DialogHeader>
+          <DialogTitle>Graph entity {entityId}</DialogTitle>
+          <DialogDescription>{query.data?.entity.memoryId ?? ''}</DialogDescription>
+        </DialogHeader>
+
+        {query.isLoading ? <PageLoading /> : null}
+        {query.isError ? (
+          <PageError
+            message='Unable to load graph entity detail.'
+            onRetry={query.refetch}
+          />
+        ) : null}
+        {query.data ? <EntityDetail detail={query.data} /> : null}
+      </DialogContent>
+    </Dialog>
+  )
+}
+
+function EntityDetail({ detail }: { detail: GraphEntityDetailView }) {
+  return (
+    <div className='flex flex-col gap-5 text-sm'>
+      <div className='grid gap-2 md:grid-cols-2'>
+        <p>entityKey: {detail.entity.entityKey}</p>
+        <p>displayName: {fieldValue(detail.entity.displayName)}</p>
+        <p>entityType: {fieldValue(detail.entity.entityType)}</p>
+        <p>mentionCount: {detail.mentionCount}</p>
+        <p>topMentionedItemIds: {detail.topMentionedItemIds.join(', ')}</p>
+        <p>entityOverlapItemLinkCount: {detail.entityOverlapItemLinkCount}</p>
+        <p>createdAt: {formatDateTime(detail.entity.createdAt)}</p>
+        <p>updatedAt: {formatDateTime(detail.entity.updatedAt)}</p>
+      </div>
+
+      <JsonViewer label='metadata' value={detail.entity.metadata ?? {}} />
+
+      <section className='flex flex-col gap-2'>
+        <h3 className='font-medium'>Aliases</h3>
+        <Table>
+          <TableHeader>
+            <TableRow>
+              <TableHead>ID</TableHead>
+              <TableHead>Normalized Alias</TableHead>
+              <TableHead>Evidence Count</TableHead>
+              <TableHead>Entity Type</TableHead>
+            </TableRow>
+          </TableHeader>
+          <TableBody>
+            {detail.aliases.map((alias) => (
+              <TableRow key={alias.id}>
+                <TableCell>{alias.id}</TableCell>
+                <TableCell>{alias.normalizedAlias}</TableCell>
+                <TableCell>{fieldValue(alias.evidenceCount)}</TableCell>
+                <TableCell>{fieldValue(alias.entityType)}</TableCell>
+              </TableRow>
+            ))}
+          </TableBody>
+        </Table>
+      </section>
+
+      <section className='flex flex-col gap-2'>
+        <h3 className='font-medium'>Top cooccurrences</h3>
+        <Table>
+          <TableHeader>
+            <TableRow>
+              <TableHead>Left Entity Key</TableHead>
+              <TableHead>Right Entity Key</TableHead>
+              <TableHead>Count</TableHead>
+            </TableRow>
+          </TableHeader>
+          <TableBody>
+            {detail.topCooccurrences.map((row) => (
+              <TableRow key={row.id}>
+                <TableCell>{row.leftEntityKey}</TableCell>
+                <TableCell>{row.rightEntityKey}</TableCell>
+                <TableCell>{fieldValue(row.cooccurrenceCount)}</TableCell>
+              </TableRow>
+            ))}
+          </TableBody>
+        </Table>
+      </section>
+    </div>
+  )
+}
+
+function fieldValue(value: unknown) {
+  if (value === null || value === undefined || value === '') return '-'
+  return String(value)
+}
diff --git a/memind-ui/src/features/item-graph/index.tsx b/memind-ui/src/features/item-graph/index.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/item-graph/index.tsx
@@ -0,0 +1,745 @@
+import { useMemo, useState, type ReactNode } from 'react'
+import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
+import { Header } from '@/components/layout/header'
+import { Main } from '@/components/layout/main'
+import { Badge } from '@/components/ui/badge'
+import { Button } from '@/components/ui/button'
+import { Checkbox } from '@/components/ui/checkbox'
+import { Label } from '@/components/ui/label'
+import {
+  Tabs,
+  TabsContent,
+  TabsList,
+  TabsTrigger,
+} from '@/components/ui/tabs'
+import {
+  Table,
+  TableBody,
+  TableCell,
+  TableHead,
+  TableHeader,
+  TableRow,
+} from '@/components/ui/table'
+import {
+  deleteGraphAliases,
+  deleteGraphCooccurrences,
+  deleteGraphEntities,
+  deleteGraphItemLinks,
+  deleteGraphMentions,
+  listGraphAliases,
+  listGraphBatches,
+  listGraphCooccurrences,
+  listGraphEntities,
+  listGraphItemLinks,
+  listGraphMentions,
+  type GraphBatchState,
+} from '@/features/api/item-graph'
+import { ConfirmResultDialog } from '@/features/components/confirm-result-dialog'
+import {
+  EmptyState,
+  PageError,
+  TableLoading,
+} from '@/features/components/data-state'
+import { readMemoryScopeFromLocation } from '@/features/components/memory-scope-location'
+import type {
+  BatchDeleteResult,
+  GraphAliasView,
+  GraphCooccurrenceView,
+  GraphItemLinkView,
+  GraphMentionView,
+} from '@/features/types'
+import { formatDateTime } from '@/lib/format'
+import { EntityDetailDrawer } from './entity-detail-drawer'
+import { SummaryTab } from './summary-tab'
+
+const DEFAULT_PAGE = 1
+const DEFAULT_PAGE_SIZE = 10
+
+type GraphTab =
+  | 'summary'
+  | 'entities'
+  | 'aliases'
+  | 'mentions'
+  | 'item-links'
+  | 'cooccurrences'
+  | 'batches'
+type BatchStateFilter = GraphBatchState | 'all'
+
+export function ItemGraphPage() {
+  const [tab, setTab] = useState<GraphTab>(() => readTabFromLocation())
+  const [, refreshLocation] = useState(0)
+  const search = readGraphSearch()
+  const memoryId = readMemoryScopeFromLocation()
+
+  const writeSearch = (patch: Record<string, string | number | undefined>) => {
+    writeUrlSearch(patch)
+    refreshLocation((current) => current + 1)
+  }
+
+  return (
+    <>
+      <Header>
+        <h1 className='truncate text-lg font-semibold'>Item Graph</h1>
+      </Header>
+      <Main>
+        <div className='flex flex-col gap-4'>
+          <div className='flex flex-col gap-1'>
+            <h2 className='text-2xl font-semibold'>Item Graph</h2>
+            <p className='text-sm text-muted-foreground'>
+              Inspect graph entities, aliases, mentions, links, cooccurrences,
+              and extraction batches.
+            </p>
+          </div>
+
+          <Tabs
+            value={tab}
+            onValueChange={(value) => {
+              const next = normalizeTab(value)
+              setTab(next)
+              writeSearch({
+                tab: next === 'summary' ? undefined : next,
+                pageNo: undefined,
+                state: undefined,
+              })
+            }}
+          >
+            <TabsList className='flex flex-wrap'>
+              <TabsTrigger value='summary'>Summary</TabsTrigger>
+              <TabsTrigger value='entities'>Entities</TabsTrigger>
+              <TabsTrigger value='aliases'>Aliases</TabsTrigger>
+              <TabsTrigger value='mentions'>Mentions</TabsTrigger>
+              <TabsTrigger value='item-links'>Item Links</TabsTrigger>
+              <TabsTrigger value='cooccurrences'>Cooccurrences</TabsTrigger>
+              <TabsTrigger value='batches'>Batches</TabsTrigger>
+            </TabsList>
+
+            <TabsContent value='summary'>
+              <SummaryTab memoryId={memoryId} />
+            </TabsContent>
+            <TabsContent value='entities'>
+              <EntitiesTab search={search} memoryId={memoryId} />
+            </TabsContent>
+            <TabsContent value='aliases'>
+              <AliasesTab search={search} memoryId={memoryId} />
+            </TabsContent>
+            <TabsContent value='mentions'>
+              <MentionsTab search={search} memoryId={memoryId} />
+            </TabsContent>
+            <TabsContent value='item-links'>
+              <ItemLinksTab search={search} memoryId={memoryId} />
+            </TabsContent>
+            <TabsContent value='cooccurrences'>
+              <CooccurrencesTab search={search} memoryId={memoryId} />
+            </TabsContent>
+            <TabsContent value='batches'>
+              <BatchesTab
+                search={search}
+                memoryId={memoryId}
+                onSearchChange={writeSearch}
+              />
+            </TabsContent>
+          </Tabs>
+        </div>
+      </Main>
+    </>
+  )
+}
+
+function EntitiesTab({
+  search,
+  memoryId,
+}: {
+  search: GraphSearch
+  memoryId: string
+}) {
+  const queryClient = useQueryClient()
+  const [selectedKeys, setSelectedKeys] = useState<Set<string>>(() => new Set())
+  const [deleteOpen, setDeleteOpen] = useState(false)
+  const [detailId, setDetailId] = useState<number | null>(null)
+  const params = useMemo(
+    () => ({
+      pageNo: search.pageNo,
+      pageSize: search.pageSize,
+      memoryId: memoryId || undefined,
+    }),
+    [memoryId, search.pageNo, search.pageSize]
+  )
+  const query = useQuery({
+    queryKey: ['item-graph', 'entities', params],
+    queryFn: () => listGraphEntities(params),
+  })
+  const deleteMutation = useMutation({
+    mutationFn: (entityKeys: string[]) =>
+      deleteGraphEntities({ memoryId, entityKeys }),
+    onSuccess: async () => {
+      setSelectedKeys(new Set())
+      await invalidateGraph(queryClient)
+    },
+  })
+  const rows = query.data?.list ?? []
+  const selectedEntityKeys = [...selectedKeys]
+
+  return (
+    <div className='flex flex-col gap-4'>
+      <Button
+        type='button'
+        variant='destructive'
+        className='w-fit'
+        disabled={!memoryId || selectedKeys.size === 0}
+        onClick={() => {
+          deleteMutation.reset()
+          setDeleteOpen(true)
+        }}
+      >
+        Delete selected entities
+      </Button>
+      <QueryTableState
+        isLoading={query.isLoading}
+        isError={query.isError}
+        isEmpty={query.data !== undefined && rows.length === 0}
+        errorMessage='Unable to load graph entities.'
+        emptyTitle='No graph entities found.'
+        onRetry={query.refetch}
+      />
+      {rows.length > 0 ? (
+        <Table>
+          <TableHeader>
+            <TableRow>
+              <TableHead>Select</TableHead>
+              <TableHead>ID</TableHead>
+              <TableHead>Memory ID</TableHead>
+              <TableHead>Entity Key</TableHead>
+              <TableHead>Display Name</TableHead>
+              <TableHead>Entity Type</TableHead>
+              <TableHead>Created At</TableHead>
+              <TableHead>Updated At</TableHead>
+              <TableHead className='text-end'>Actions</TableHead>
+            </TableRow>
+          </TableHeader>
+          <TableBody>
+            {rows.map((row) => (
+              <TableRow key={row.id}>
+                <TableCell>
+                  <Checkbox
+                    aria-label={`Select entity ${row.entityKey}`}
+                    checked={selectedKeys.has(row.entityKey)}
+                    onCheckedChange={(checked) =>
+                      setSelectedKeys((current) =>
+                        toggleId(current, row.entityKey, checked === true)
+                      )
+                    }
+                  />
+                </TableCell>
+                <TableCell>{row.id}</TableCell>
+                <TableCell>{row.memoryId}</TableCell>
+                <TableCell>{row.entityKey}</TableCell>
+                <TableCell>{fieldValue(row.displayName)}</TableCell>
+                <TableCell>{fieldValue(row.entityType)}</TableCell>
+                <TableCell>{formatDateTime(row.createdAt)}</TableCell>
+                <TableCell>{formatDateTime(row.updatedAt)}</TableCell>
+                <TableCell className='text-end'>
+                  <Button
+                    type='button'
+                    variant='outline'
+                    size='sm'
+                    aria-label={`View entity ${row.id}`}
+                    onClick={() => setDetailId(row.id)}
+                  >
+                    View
+                  </Button>
+                </TableCell>
+              </TableRow>
+            ))}
+          </TableBody>
+        </Table>
+      ) : null}
+      <ConfirmResultDialog
+        open={deleteOpen}
+        onOpenChange={setDeleteOpen}
+        title='Delete selected graph entities'
+        selectedCount={selectedEntityKeys.length}
+        description='Only selected entity keys will be sent to the server.'
+        cascadeWarning='Aliases, mentions, and cooccurrences for these entities can also be removed.'
+        isPending={deleteMutation.isPending}
+        result={deleteMutation.data ? { ...deleteMutation.data } : null}
+        onConfirm={() => deleteMutation.mutate(selectedEntityKeys)}
+      />
+      <EntityDetailDrawer
+        entityId={detailId}
+        onOpenChange={(open) => {
+          if (!open) setDetailId(null)
+        }}
+      />
+    </div>
+  )
+}
+
+function AliasesTab(props: GraphTabProps) {
+  const params = buildPageParams(props)
+  const query = useQuery({
+    queryKey: ['item-graph', 'aliases', params],
+    queryFn: () => listGraphAliases(params),
+  })
+  return (
+    <IdDeleteTab
+      rows={query.data?.list ?? []}
+      query={query}
+      selectLabel={(row: GraphAliasView) => `Select alias ${row.id}`}
+      deleteLabel='Delete selected aliases'
+      emptyTitle='No graph aliases found.'
+      errorMessage='Unable to load graph aliases.'
+      deleteFn={deleteGraphAliases}
+      columns={['ID', 'Memory ID', 'Entity Key', 'Normalized Alias', 'Entity Type', 'Evidence Count', 'Created At']}
+      renderRow={(row: GraphAliasView) => [
+        row.id,
+        row.memoryId,
+        row.entityKey,
+        row.normalizedAlias,
+        fieldValue(row.entityType),
+        fieldValue(row.evidenceCount),
+        formatDateTime(row.createdAt),
+      ]}
+    />
+  )
+}
+
+function MentionsTab(props: GraphTabProps) {
+  const params = buildPageParams(props)
+  const query = useQuery({
+    queryKey: ['item-graph', 'mentions', params],
+    queryFn: () => listGraphMentions(params),
+  })
+  return (
+    <IdDeleteTab
+      rows={query.data?.list ?? []}
+      query={query}
+      selectLabel={(row: GraphMentionView) => `Select mention ${row.id}`}
+      deleteLabel='Delete selected mentions'
+      emptyTitle='No graph mentions found.'
+      errorMessage='Unable to load graph mentions.'
+      deleteFn={deleteGraphMentions}
+      columns={['ID', 'Memory ID', 'Item ID', 'Entity Key', 'Confidence', 'Created At']}
+      renderRow={(row: GraphMentionView) => [
+        row.id,
+        row.memoryId,
+        row.itemId,
+        row.entityKey,
+        fieldValue(row.confidence),
+        formatDateTime(row.createdAt),
+      ]}
+    />
+  )
+}
+
+function ItemLinksTab(props: GraphTabProps) {
+  const params = buildPageParams(props)
+  const query = useQuery({
+    queryKey: ['item-graph', 'item-links', params],
+    queryFn: () => listGraphItemLinks(params),
+  })
+  return (
+    <IdDeleteTab
+      rows={query.data?.list ?? []}
+      query={query}
+      selectLabel={(row: GraphItemLinkView) => `Select item link ${row.id}`}
+      deleteLabel='Delete selected item links'
+      emptyTitle='No graph item links found.'
+      errorMessage='Unable to load graph item links.'
+      deleteFn={deleteGraphItemLinks}
+      columns={['ID', 'Memory ID', 'Source Item ID', 'Target Item ID', 'Link Type', 'Relation Code', 'Evidence Source', 'Strength', 'Created At']}
+      renderRow={(row: GraphItemLinkView) => [
+        row.id,
+        row.memoryId,
+        row.sourceItemId,
+        row.targetItemId,
+        fieldValue(row.linkType),
+        fieldValue(row.relationCode),
+        fieldValue(row.evidenceSource),
+        fieldValue(row.strength),
+        formatDateTime(row.createdAt),
+      ]}
+    />
+  )
+}
+
+function CooccurrencesTab(props: GraphTabProps) {
+  const params = buildPageParams(props)
+  const query = useQuery({
+    queryKey: ['item-graph', 'cooccurrences', params],
+    queryFn: () => listGraphCooccurrences(params),
+  })
+  return (
+    <IdDeleteTab
+      rows={query.data?.list ?? []}
+      query={query}
+      selectLabel={(row: GraphCooccurrenceView) =>
+        `Select cooccurrence ${row.id}`}
+      deleteLabel='Delete selected cooccurrences'
+      emptyTitle='No graph cooccurrences found.'
+      errorMessage='Unable to load graph cooccurrences.'
+      deleteFn={deleteGraphCooccurrences}
+      columns={['ID', 'Memory ID', 'Left Entity Key', 'Right Entity Key', 'Cooccurrence Count', 'Created At']}
+      renderRow={(row: GraphCooccurrenceView) => [
+        row.id,
+        row.memoryId,
+        row.leftEntityKey,
+        row.rightEntityKey,
+        fieldValue(row.cooccurrenceCount),
+        formatDateTime(row.createdAt),
+      ]}
+    />
+  )
+}
+
+function BatchesTab({
+  search,
+  memoryId,
+  onSearchChange,
+}: GraphTabProps & {
+  onSearchChange: (patch: Record<string, string | number | undefined>) => void
+}) {
+  const state = normalizeBatchState(search.state)
+  const params = useMemo(
+    () => ({
+      pageNo: search.pageNo,
+      pageSize: search.pageSize,
+      memoryId: memoryId || undefined,
+      ...(state === 'all' ? {} : { state }),
+    }),
+    [memoryId, search.pageNo, search.pageSize, state]
+  )
+  const query = useQuery({
+    queryKey: ['item-graph', 'batches', params],
+    queryFn: () => listGraphBatches(params),
+  })
+  const rows = query.data?.list ?? []
+
+  return (
+    <div className='flex flex-col gap-4'>
+      <div className='flex items-center gap-2'>
+        <Label htmlFor='graph-batch-state'>Batch state</Label>
+        <select
+          id='graph-batch-state'
+          aria-label='Graph batch state'
+          value={state}
+          className='h-9 rounded-md border bg-background px-3 text-sm'
+          onChange={(event) =>
+            onSearchChange({
+              pageNo: undefined,
+              state:
+                event.target.value === 'all' ? undefined : event.target.value,
+            })
+          }
+        >
+          <option value='all'>all</option>
+          <option value='PENDING'>PENDING</option>
+          <option value='COMMITTED'>COMMITTED</option>
+          <option value='REPAIR_REQUIRED'>REPAIR_REQUIRED</option>
+        </select>
+      </div>
+      <QueryTableState
+        isLoading={query.isLoading}
+        isError={query.isError}
+        isEmpty={query.data !== undefined && rows.length === 0}
+        errorMessage='Unable to load graph batches.'
+        emptyTitle='No graph batches found.'
+        onRetry={query.refetch}
+      />
+      {rows.length > 0 ? (
+        <SimpleTable
+          columns={['ID', 'Memory ID', 'Extraction Batch ID', 'State', 'Error Message', 'Retry Promotion Supported', 'Created At', 'Updated At']}
+          rows={rows.map((row) => [
+            row.id,
+            row.memoryId,
+            row.extractionBatchId,
+            <Badge key='state'>{row.state}</Badge>,
+            fieldValue(row.errorMessage),
+            row.retryPromotionSupported ? 'yes' : 'no',
+            formatDateTime(row.createdAt),
+            formatDateTime(row.updatedAt),
+          ])}
+        />
+      ) : null}
+    </div>
+  )
+}
+
+function IdDeleteTab<T extends { id: number }>({
+  rows,
+  query,
+  selectLabel,
+  deleteLabel,
+  emptyTitle,
+  errorMessage,
+  deleteFn,
+  columns,
+  renderRow,
+}: {
+  rows: T[]
+  query: {
+    isLoading: boolean
+    isError: boolean
+    data?: unknown
+    refetch: () => void
+  }
+  selectLabel: (row: T) => string
+  deleteLabel: string
+  emptyTitle: string
+  errorMessage: string
+  deleteFn: (ids: number[]) => Promise<BatchDeleteResult>
+  columns: string[]
+  renderRow: (row: T) => ReactNode[]
+}) {
+  const queryClient = useQueryClient()
+  const [selectedIds, setSelectedIds] = useState<Set<number>>(() => new Set())
+  const [deleteOpen, setDeleteOpen] = useState(false)
+  const mutation = useMutation({
+    mutationFn: (ids: number[]) => deleteFn(ids),
+    onSuccess: async () => {
+      setSelectedIds(new Set())
+      await invalidateGraph(queryClient)
+    },
+  })
+  const selected = [...selectedIds]
+
+  return (
+    <div className='flex flex-col gap-4'>
+      <Button
+        type='button'
+        variant='destructive'
+        className='w-fit'
+        disabled={selectedIds.size === 0}
+        onClick={() => {
+          mutation.reset()
+          setDeleteOpen(true)
+        }}
+      >
+        {deleteLabel}
+      </Button>
+      <QueryTableState
+        isLoading={query.isLoading}
+        isError={query.isError}
+        isEmpty={query.data !== undefined && rows.length === 0}
+        errorMessage={errorMessage}
+        emptyTitle={emptyTitle}
+        onRetry={query.refetch}
+      />
+      {rows.length > 0 ? (
+        <Table>
+          <TableHeader>
+            <TableRow>
+              <TableHead>Select</TableHead>
+              {columns.map((column) => (
+                <TableHead key={column}>{column}</TableHead>
+              ))}
+            </TableRow>
+          </TableHeader>
+          <TableBody>
+            {rows.map((row) => (
+              <TableRow key={row.id}>
+                <TableCell>
+                  <Checkbox
+                    aria-label={selectLabel(row)}
+                    checked={selectedIds.has(row.id)}
+                    onCheckedChange={(checked) =>
+                      setSelectedIds((current) =>
+                        toggleId(current, row.id, checked === true)
+                      )
+                    }
+                  />
+                </TableCell>
+                {renderRow(row).map((cell, index) => (
+                  <TableCell key={cellKey(cell, index)}>{cell}</TableCell>
+                ))}
+              </TableRow>
+            ))}
+          </TableBody>
+        </Table>
+      ) : null}
+      <ConfirmResultDialog
+        open={deleteOpen}
+        onOpenChange={setDeleteOpen}
+        title={deleteLabel}
+        selectedCount={selected.length}
+        description='Only selected row ids will be sent to the server.'
+        isPending={mutation.isPending}
+        result={mutation.data ? { ...mutation.data } : null}
+        onConfirm={() => mutation.mutate(selected)}
+      />
+    </div>
+  )
+}
+
+function SimpleTable({
+  columns,
+  rows,
+}: {
+  columns: string[]
+  rows: ReactNode[][]
+}) {
+  return (
+    <Table>
+      <TableHeader>
+        <TableRow>
+          {columns.map((column) => (
+            <TableHead key={column}>{column}</TableHead>
+          ))}
+        </TableRow>
+      </TableHeader>
+      <TableBody>
+        {rows.map((row, rowIndex) => (
+          <TableRow key={rowKey(row, rowIndex)}>
+            {row.map((cell, cellIndex) => (
+              <TableCell key={cellKey(cell, cellIndex)}>{cell}</TableCell>
+            ))}
+          </TableRow>
+        ))}
+      </TableBody>
+    </Table>
+  )
+}
+
+function QueryTableState({
+  isLoading,
+  isError,
+  isEmpty,
+  errorMessage,
+  emptyTitle,
+  onRetry,
+}: {
+  isLoading: boolean
+  isError: boolean
+  isEmpty: boolean
+  errorMessage: string
+  emptyTitle: string
+  onRetry: () => void
+}) {
+  return (
+    <>
+      {isLoading ? <TableLoading columns={6} /> : null}
+      {isError ? <PageError message={errorMessage} onRetry={onRetry} /> : null}
+      {isEmpty ? <EmptyState title={emptyTitle} /> : null}
+    </>
+  )
+}
+
+type GraphTabProps = {
+  search: GraphSearch
+  memoryId: string
+}
+
+type GraphSearch = {
+  pageNo: number
+  pageSize: number
+  state?: string
+}
+
+function buildPageParams({ search, memoryId }: GraphTabProps) {
+  return {
+    pageNo: search.pageNo,
+    pageSize: search.pageSize,
+    memoryId: memoryId || undefined,
+  }
+}
+
+function readGraphSearch(): GraphSearch {
+  const params = readSearchParams()
+  return {
+    pageNo: readNumberParam(params, 'pageNo', DEFAULT_PAGE),
+    pageSize: readNumberParam(params, 'pageSize', DEFAULT_PAGE_SIZE),
+    state: readStringParam(params, 'state'),
+  }
+}
+
+function readTabFromLocation(): GraphTab {
+  return normalizeTab(readSearchParams().get('tab') ?? '')
+}
+
+function normalizeTab(value: string): GraphTab {
+  if (
+    value === 'entities' ||
+    value === 'aliases' ||
+    value === 'mentions' ||
+    value === 'item-links' ||
+    value === 'cooccurrences' ||
+    value === 'batches'
+  ) {
+    return value
+  }
+  return 'summary'
+}
+
+function normalizeBatchState(state: string | undefined): BatchStateFilter {
+  if (
+    state === 'PENDING' ||
+    state === 'COMMITTED' ||
+    state === 'REPAIR_REQUIRED'
+  ) {
+    return state
+  }
+  return 'all'
+}
+
+function readSearchParams() {
+  if (typeof window === 'undefined') return new URLSearchParams()
+  return new URLSearchParams(window.location.search)
+}
+
+function readStringParam(params: URLSearchParams, key: string) {
+  const value = params.get(key)?.trim()
+  return value ? value : undefined
+}
+
+function readNumberParam(
+  params: URLSearchParams,
+  key: string,
+  fallback: number
+) {
+  const value = params.get(key)
+  if (!value) return fallback
+  const parsed = Number(value)
+  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback
+}
+
+function writeUrlSearch(patch: Record<string, string | number | undefined>) {
+  if (typeof window === 'undefined') return
+  const url = new URL(window.location.href)
+  for (const [key, value] of Object.entries(patch)) {
+    if (value === undefined || value === '') {
+      url.searchParams.delete(key)
+    } else {
+      url.searchParams.set(key, String(value))
+    }
+  }
+  window.history.replaceState(window.history.state, '', url)
+}
+
+function toggleId<T>(current: Set<T>, id: T, checked: boolean) {
+  const next = new Set(current)
+  if (checked) {
+    next.add(id)
+  } else {
+    next.delete(id)
+  }
+  return next
+}
+
+async function invalidateGraph(queryClient: ReturnType<typeof useQueryClient>) {
+  await Promise.all([
+    queryClient.invalidateQueries({ queryKey: ['item-graph'] }),
+    queryClient.invalidateQueries({ queryKey: ['dashboard'] }),
+  ])
+}
+
+function fieldValue(value: unknown) {
+  if (value === null || value === undefined || value === '') return '-'
+  return String(value)
+}
+
+function rowKey(row: ReactNode[], index: number) {
+  return `${index}:${row.map((cell) => String(cell)).join('|')}`
+}
+
+function cellKey(cell: ReactNode, index: number) {
+  return `${index}:${String(cell)}`
+}
diff --git a/memind-ui/src/features/item-graph/summary-tab.tsx b/memind-ui/src/features/item-graph/summary-tab.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/item-graph/summary-tab.tsx
@@ -0,0 +1,75 @@
+import { useQuery } from '@tanstack/react-query'
+import { getItemGraphSummary } from '@/features/api/item-graph'
+import {
+  EmptyState,
+  PageError,
+  PageLoading,
+} from '@/features/components/data-state'
+import type { ItemGraphSummaryView, NamedCount } from '@/features/types'
+
+export function SummaryTab({ memoryId }: { memoryId: string }) {
+  const query = useQuery({
+    queryKey: ['item-graph', 'summary', memoryId],
+    queryFn: () =>
+      getItemGraphSummary({ memoryId: memoryId || undefined }),
+  })
+
+  if (query.isLoading) return <PageLoading />
+  if (query.isError) {
+    return (
+      <PageError
+        message='Unable to load item graph summary.'
+        onRetry={query.refetch}
+      />
+    )
+  }
+  if (!query.data) return <EmptyState title='No item graph summary found.' />
+
+  return <SummaryContent summary={query.data} />
+}
+
+function SummaryContent({ summary }: { summary: ItemGraphSummaryView }) {
+  return (
+    <div className='flex flex-col gap-4'>
+      <div className='grid gap-3 md:grid-cols-2 xl:grid-cols-5'>
+        <Metric label='entityCount' value={summary.entityCount} />
+        <Metric label='aliasCount' value={summary.aliasCount} />
+        <Metric label='mentionCount' value={summary.mentionCount} />
+        <Metric label='itemLinkCount' value={summary.itemLinkCount} />
+        <Metric label='cooccurrenceCount' value={summary.cooccurrenceCount} />
+      </div>
+      <div className='grid gap-4 lg:grid-cols-3'>
+        <Breakdown title='Graph batches' rows={summary.graphBatchCountByState} />
+        <Breakdown title='Item link types' rows={summary.itemLinkCountByType} />
+        <Breakdown title='Entity types' rows={summary.entityCountByType} />
+      </div>
+    </div>
+  )
+}
+
+function Metric({ label, value }: { label: string; value: number }) {
+  return (
+    <div className='rounded-md border p-3 text-sm'>
+      <p>{label}: {value}</p>
+    </div>
+  )
+}
+
+function Breakdown({ title, rows }: { title: string; rows: NamedCount[] }) {
+  return (
+    <section className='rounded-md border p-3 text-sm'>
+      <h3 className='font-medium'>{title}</h3>
+      {rows.length === 0 ? (
+        <p className='mt-2 text-muted-foreground'>No data.</p>
+      ) : (
+        <ul className='mt-2 flex flex-col gap-1'>
+          {rows.map((row) => (
+            <li key={row.name}>
+              {row.name}: {row.count}
+            </li>
+          ))}
+        </ul>
+      )}
+    </section>
+  )
+}
diff --git a/memind-ui/src/features/items/index.tsx b/memind-ui/src/features/items/index.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/items/index.tsx
@@ -0,0 +1,460 @@
+import { useMemo, useState } from 'react'
+import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
+import { Header } from '@/components/layout/header'
+import { Main } from '@/components/layout/main'
+import { Badge } from '@/components/ui/badge'
+import { Button } from '@/components/ui/button'
+import { Checkbox } from '@/components/ui/checkbox'
+import {
+  Dialog,
+  DialogContent,
+  DialogDescription,
+  DialogHeader,
+  DialogTitle,
+} from '@/components/ui/dialog'
+import {
+  Table,
+  TableBody,
+  TableCell,
+  TableHead,
+  TableHeader,
+  TableRow,
+} from '@/components/ui/table'
+import {
+  deleteItems,
+  getItem,
+  listItemMemoryThreads,
+  listItems,
+  type ItemListParams,
+} from '@/features/api/items'
+import { ConfirmResultDialog } from '@/features/components/confirm-result-dialog'
+import {
+  EmptyState,
+  PageError,
+  PageLoading,
+  ScopeRequiredState,
+  TableLoading,
+} from '@/features/components/data-state'
+import { JsonViewer } from '@/features/components/json-viewer'
+import { readMemoryScopeFromLocation } from '@/features/components/memory-scope-location'
+import type {
+  AdminItemMemoryThreadView,
+  AdminItemView,
+} from '@/features/types'
+import { compactJson, formatDateTime, truncateText } from '@/lib/format'
+import { parseMemoryScope, toUserAgentQuery } from '@/lib/memory-scope'
+
+const DEFAULT_PAGE = 1
+const DEFAULT_PAGE_SIZE = 10
+
+export function ItemsPage() {
+  const queryClient = useQueryClient()
+  const [selectedIds, setSelectedIds] = useState<Set<number>>(() => new Set())
+  const [deleteOpen, setDeleteOpen] = useState(false)
+  const [detailItemId, setDetailItemId] = useState<number | null>(null)
+
+  const search = readItemsSearch()
+  const memoryScope = readMemoryScopeFromLocation()
+  const params = useMemo(
+    () => buildItemListParams(search, memoryScope),
+    [search, memoryScope]
+  )
+  const itemsQuery = useQuery({
+    queryKey: ['items', params],
+    queryFn: () => listItems(params),
+  })
+  const deleteMutation = useMutation({
+    mutationFn: (itemIds: number[]) => deleteItems(itemIds),
+    onSuccess: async () => {
+      setSelectedIds(new Set())
+      await Promise.all([
+        queryClient.invalidateQueries({ queryKey: ['items'] }),
+        queryClient.invalidateQueries({ queryKey: ['dashboard'] }),
+      ])
+    },
+  })
+
+  const rows = itemsQuery.data?.list ?? []
+  const selectedItemIds = [...selectedIds]
+
+  return (
+    <>
+      <Header>
+        <h1 className='truncate text-lg font-semibold'>Memory Items</h1>
+      </Header>
+      <Main>
+        <div className='flex flex-col gap-4'>
+          <div className='flex flex-wrap items-center justify-between gap-3'>
+            <div className='flex flex-col gap-1'>
+              <h2 className='text-2xl font-semibold'>Memory Items</h2>
+              <p className='text-sm text-muted-foreground'>
+                Inspect item content, metadata, source raw data, and related
+                memory threads.
+              </p>
+            </div>
+            <Button
+              type='button'
+              variant='destructive'
+              disabled={selectedIds.size === 0}
+              onClick={() => {
+                deleteMutation.reset()
+                setDeleteOpen(true)
+              }}
+            >
+              Delete selected
+            </Button>
+          </div>
+
+          {itemsQuery.isLoading ? <TableLoading columns={10} /> : null}
+          {itemsQuery.isError ? (
+            <PageError
+              message='Unable to load memory items.'
+              onRetry={itemsQuery.refetch}
+            />
+          ) : null}
+          {itemsQuery.data && rows.length === 0 ? (
+            <EmptyState title='No memory items found.' />
+          ) : null}
+          {rows.length > 0 ? (
+            <ItemsTable
+              rows={rows}
+              selectedIds={selectedIds}
+              onToggleSelected={(itemId, checked) => {
+                setSelectedIds((current) => {
+                  const next = new Set(current)
+                  if (checked) {
+                    next.add(itemId)
+                  } else {
+                    next.delete(itemId)
+                  }
+                  return next
+                })
+              }}
+              onView={setDetailItemId}
+            />
+          ) : null}
+
+          {itemsQuery.data ? (
+            <p className='text-sm text-muted-foreground'>
+              Total rows: {itemsQuery.data.total}
+            </p>
+          ) : null}
+        </div>
+      </Main>
+
+      <ConfirmResultDialog
+        open={deleteOpen}
+        onOpenChange={setDeleteOpen}
+        title='Delete selected memory items'
+        selectedCount={selectedItemIds.length}
+        description='Only the selected row ids will be sent to the server.'
+        isPending={deleteMutation.isPending}
+        result={deleteMutation.data ? { ...deleteMutation.data } : null}
+        onConfirm={() => deleteMutation.mutate(selectedItemIds)}
+      />
+
+      <ItemDetailDialog
+        itemId={detailItemId}
+        memoryScope={memoryScope}
+        onOpenChange={(open) => {
+          if (!open) setDetailItemId(null)
+        }}
+      />
+    </>
+  )
+}
+
+function ItemsTable({
+  rows,
+  selectedIds,
+  onToggleSelected,
+  onView,
+}: {
+  rows: AdminItemView[]
+  selectedIds: Set<number>
+  onToggleSelected: (itemId: number, checked: boolean) => void
+  onView: (itemId: number) => void
+}) {
+  return (
+    <Table>
+      <TableHeader>
+        <TableRow>
+          <TableHead className='w-10'>Select</TableHead>
+          <TableHead>Item ID</TableHead>
+          <TableHead>Memory ID</TableHead>
+          <TableHead>Content</TableHead>
+          <TableHead>Type</TableHead>
+          <TableHead>Category</TableHead>
+          <TableHead>Scope</TableHead>
+          <TableHead>Raw Data ID</TableHead>
+          <TableHead>Source Client</TableHead>
+          <TableHead>Observed At</TableHead>
+          <TableHead>Created At</TableHead>
+          <TableHead className='text-end'>Actions</TableHead>
+        </TableRow>
+      </TableHeader>
+      <TableBody>
+        {rows.map((item) => (
+          <TableRow key={item.itemId}>
+            <TableCell>
+              <Checkbox
+                aria-label={`Select item ${item.itemId}`}
+                checked={selectedIds.has(item.itemId)}
+                onCheckedChange={(checked) =>
+                  onToggleSelected(item.itemId, checked === true)
+                }
+              />
+            </TableCell>
+            <TableCell>{item.itemId}</TableCell>
+            <TableCell>{item.memoryId}</TableCell>
+            <TableCell className='max-w-96 whitespace-normal'>
+              <span className='sr-only'>Content preview: </span>
+              {truncateText(item.content, 12)}
+            </TableCell>
+            <TableCell>{item.type ? <Badge>{item.type}</Badge> : '-'}</TableCell>
+            <TableCell>{fieldValue(item.category)}</TableCell>
+            <TableCell>{fieldValue(item.scope)}</TableCell>
+            <TableCell>{fieldValue(item.rawDataId)}</TableCell>
+            <TableCell>{fieldValue(item.sourceClient)}</TableCell>
+            <TableCell>{formatDateTime(item.observedAt)}</TableCell>
+            <TableCell>{formatDateTime(item.createdAt)}</TableCell>
+            <TableCell className='text-end'>
+              <Button
+                type='button'
+                variant='outline'
+                size='sm'
+                aria-label={`View item ${item.itemId}`}
+                onClick={() => onView(item.itemId)}
+              >
+                View
+              </Button>
+            </TableCell>
+          </TableRow>
+        ))}
+      </TableBody>
+    </Table>
+  )
+}
+
+function ItemDetailDialog({
+  itemId,
+  memoryScope,
+  onOpenChange,
+}: {
+  itemId: number | null
+  memoryScope: string
+  onOpenChange: (open: boolean) => void
+}) {
+  const query = useQuery({
+    queryKey: ['items', itemId, 'detail'],
+    enabled: itemId !== null,
+    queryFn: () => getItem(itemId as number),
+  })
+  const item = query.data
+
+  return (
+    <Dialog open={itemId !== null} onOpenChange={onOpenChange}>
+      <DialogContent className='max-h-[85vh] overflow-auto sm:max-w-3xl'>
+        <DialogHeader>
+          <DialogTitle>Memory item {itemId}</DialogTitle>
+          <DialogDescription>{item?.memoryId}</DialogDescription>
+        </DialogHeader>
+
+        {query.isLoading ? <PageLoading /> : null}
+        {query.isError ? (
+          <PageError
+            message='Unable to load memory item detail.'
+            onRetry={query.refetch}
+          />
+        ) : null}
+        {item ? (
+          <div className='flex flex-col gap-5 text-sm'>
+            <section className='flex flex-col gap-2'>
+              <h3 className='font-medium'>Content</h3>
+              <p className='whitespace-pre-wrap rounded-md bg-muted p-3'>
+                {item.content}
+              </p>
+            </section>
+
+            <div className='grid gap-2 md:grid-cols-2'>
+              <p>type: {fieldValue(item.type)}</p>
+              <p>rawDataType: {fieldValue(item.rawDataType)}</p>
+              <p>vectorId: {fieldValue(item.vectorId)}</p>
+              <p>contentHash: {fieldValue(item.contentHash)}</p>
+              <p>rawDataId: {fieldValue(item.rawDataId)}</p>
+              <p>sourceClient: {fieldValue(item.sourceClient)}</p>
+              <p>occurredAt: {formatDateTime(item.occurredAt)}</p>
+              <p>observedAt: {formatDateTime(item.observedAt)}</p>
+              <p>createdAt: {formatDateTime(item.createdAt)}</p>
+              <p>updatedAt: {formatDateTime(item.updatedAt)}</p>
+            </div>
+
+            <JsonViewer
+              label='metadata'
+              value={item.metadata ?? {}}
+              defaultExpanded
+            />
+
+            <AssociatedThreads itemId={item.itemId} memoryScope={memoryScope} />
+          </div>
+        ) : null}
+      </DialogContent>
+    </Dialog>
+  )
+}
+
+function AssociatedThreads({
+  itemId,
+  memoryScope,
+}: {
+  itemId: number
+  memoryScope: string
+}) {
+  const scope = parseMemoryScope(memoryScope)
+  const threadsQuery = useQuery({
+    queryKey: [
+      'items',
+      itemId,
+      'memory-threads',
+      scope.userId,
+      scope.agentId,
+      scope.hasAgentId,
+    ],
+    enabled: scope.hasUserId,
+    queryFn: () =>
+      listItemMemoryThreads(itemId, {
+        userId: scope.userId,
+        ...(scope.hasAgentId ? { agentId: scope.agentId } : {}),
+      }),
+  })
+
+  if (!scope.hasUserId) {
+    return (
+      <ScopeRequiredState message='Set memory scope with userId to load associated threads.' />
+    )
+  }
+
+  if (threadsQuery.isLoading) {
+    return <PageLoading />
+  }
+
+  if (threadsQuery.isError) {
+    return (
+      <PageError
+        message='Unable to load associated memory threads.'
+        onRetry={threadsQuery.refetch}
+      />
+    )
+  }
+
+  const threads = threadsQuery.data ?? []
+  if (threads.length === 0) {
+    return <EmptyState title='No associated memory threads found.' />
+  }
+
+  return (
+    <section className='flex flex-col gap-2'>
+      <h3 className='font-medium'>Associated memory threads</h3>
+      <Table>
+        <TableHeader>
+          <TableRow>
+            <TableHead>Thread Key</TableHead>
+            <TableHead>Role</TableHead>
+            <TableHead>Primary</TableHead>
+            <TableHead>Relevance</TableHead>
+            <TableHead>Created At</TableHead>
+          </TableRow>
+        </TableHeader>
+        <TableBody>
+          {threads.map((thread) => (
+            <AssociatedThreadRow key={threadRowKey(thread)} thread={thread} />
+          ))}
+        </TableBody>
+      </Table>
+    </section>
+  )
+}
+
+function AssociatedThreadRow({
+  thread,
+}: {
+  thread: AdminItemMemoryThreadView
+}) {
+  return (
+    <TableRow>
+      <TableCell>{thread.threadKey}</TableCell>
+      <TableCell>{fieldValue(thread.role)}</TableCell>
+      <TableCell>{thread.primary ? 'yes' : 'no'}</TableCell>
+      <TableCell>{fieldValue(thread.relevanceWeight)}</TableCell>
+      <TableCell>{formatDateTime(thread.createdAt)}</TableCell>
+    </TableRow>
+  )
+}
+
+function buildItemListParams(
+  search: ItemSearch,
+  memoryScope: string
+): ItemListParams {
+  return {
+    pageNo: search.pageNo,
+    pageSize: search.pageSize,
+    ...toUserAgentQuery(memoryScope),
+    scope: search.scope,
+    category: search.category,
+    type: search.type,
+    rawDataId: search.rawDataId,
+  }
+}
+
+type ItemSearch = {
+  pageNo: number
+  pageSize: number
+  scope?: string
+  category?: string
+  type?: string
+  rawDataId?: string
+}
+
+function readItemsSearch(): ItemSearch {
+  const params = readSearchParams()
+  return {
+    pageNo: readNumberParam(params, 'pageNo', DEFAULT_PAGE),
+    pageSize: readNumberParam(params, 'pageSize', DEFAULT_PAGE_SIZE),
+    scope: readStringParam(params, 'scope'),
+    category: readStringParam(params, 'category'),
+    type: readStringParam(params, 'type'),
+    rawDataId: readStringParam(params, 'rawDataId'),
+  }
+}
+
+function readSearchParams() {
+  if (typeof window === 'undefined') return new URLSearchParams()
+  return new URLSearchParams(window.location.search)
+}
+
+function readStringParam(params: URLSearchParams, key: string) {
+  const value = params.get(key)?.trim()
+  return value ? value : undefined
+}
+
+function readNumberParam(
+  params: URLSearchParams,
+  key: string,
+  fallback: number
+) {
+  const value = params.get(key)
+  if (!value) return fallback
+  const parsed = Number(value)
+  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback
+}
+
+function threadRowKey(thread: AdminItemMemoryThreadView) {
+  return `${thread.threadKey}:${thread.itemId}:${thread.role}`
+}
+
+function fieldValue(value: unknown) {
+  if (value === null || value === undefined || value === '') return '-'
+  if (Array.isArray(value)) return value.length > 0 ? value.join(', ') : '-'
+  if (typeof value === 'object') return compactJson(value)
+  return String(value)
+}
diff --git a/memind-ui/src/features/memory-threads/index.tsx b/memind-ui/src/features/memory-threads/index.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/memory-threads/index.tsx
@@ -0,0 +1,260 @@
+import { useMemo, useState } from 'react'
+import { useQuery } from '@tanstack/react-query'
+import { Header } from '@/components/layout/header'
+import { Main } from '@/components/layout/main'
+import { Badge } from '@/components/ui/badge'
+import { Button } from '@/components/ui/button'
+import { Label } from '@/components/ui/label'
+import {
+  Table,
+  TableBody,
+  TableCell,
+  TableHead,
+  TableHeader,
+  TableRow,
+} from '@/components/ui/table'
+import {
+  listMemoryThreads,
+  type MemoryThreadListParams,
+  type MemoryThreadStatus,
+} from '@/features/api/memory-threads'
+import {
+  EmptyState,
+  PageError,
+  TableLoading,
+} from '@/features/components/data-state'
+import { readMemoryScopeFromLocation } from '@/features/components/memory-scope-location'
+import type { AdminMemoryThreadView } from '@/features/types'
+import { formatDateTime } from '@/lib/format'
+import { toUserAgentQuery } from '@/lib/memory-scope'
+import { ThreadDetailDrawer } from './thread-detail-drawer'
+import { ThreadStatusPanel } from './thread-status-panel'
+
+const DEFAULT_PAGE = 1
+const DEFAULT_PAGE_SIZE = 10
+type StatusFilter = MemoryThreadStatus | 'all'
+
+export function MemoryThreadsPage() {
+  const [, refreshLocation] = useState(0)
+  const [detailThreadKey, setDetailThreadKey] = useState<string | null>(null)
+  const search = readMemoryThreadsSearch()
+  const memoryScope = readMemoryScopeFromLocation()
+  const status = normalizeStatus(search.status)
+  const params = useMemo(
+    () => buildMemoryThreadParams(search, memoryScope, status),
+    [memoryScope, search, status]
+  )
+  const threadsQuery = useQuery({
+    queryKey: ['memory-threads', 'list', params],
+    queryFn: () => listMemoryThreads(params),
+  })
+  const rows = threadsQuery.data?.list ?? []
+
+  const writeSearch = (patch: Record<string, string | number | undefined>) => {
+    writeUrlSearch(patch)
+    refreshLocation((current) => current + 1)
+  }
+
+  return (
+    <>
+      <Header>
+        <h1 className='truncate text-lg font-semibold'>Memory Threads</h1>
+      </Header>
+      <Main>
+        <div className='flex flex-col gap-6'>
+          <div className='flex flex-col gap-1'>
+            <h2 className='text-2xl font-semibold'>Memory Threads</h2>
+            <p className='text-sm text-muted-foreground'>
+              Inspect projected thread state, memberships, and maintenance
+              status.
+            </p>
+          </div>
+
+          <ThreadStatusPanel memoryScope={memoryScope} />
+
+          <div className='flex flex-wrap items-center justify-between gap-3'>
+            <div className='flex items-center gap-2'>
+              <Label htmlFor='memory-thread-status'>Status</Label>
+              <select
+                id='memory-thread-status'
+                aria-label='Memory thread status'
+                value={status}
+                className='h-9 rounded-md border bg-background px-3 text-sm'
+                onChange={(event) =>
+                  writeSearch({
+                    pageNo: undefined,
+                    status:
+                      event.target.value === 'all'
+                        ? undefined
+                        : event.target.value,
+                  })
+                }
+              >
+                <option value='all'>all</option>
+                <option value='ACTIVE'>ACTIVE</option>
+                <option value='DORMANT'>DORMANT</option>
+                <option value='CLOSED'>CLOSED</option>
+              </select>
+            </div>
+          </div>
+
+          {threadsQuery.isLoading ? <TableLoading columns={9} /> : null}
+          {threadsQuery.isError ? (
+            <PageError
+              message='Unable to load memory threads.'
+              onRetry={threadsQuery.refetch}
+            />
+          ) : null}
+          {threadsQuery.data && rows.length === 0 ? (
+            <EmptyState title='No memory threads found.' />
+          ) : null}
+          {rows.length > 0 ? (
+            <MemoryThreadsTable rows={rows} onView={setDetailThreadKey} />
+          ) : null}
+          {threadsQuery.data ? (
+            <p className='text-sm text-muted-foreground'>
+              Total rows: {threadsQuery.data.total}
+            </p>
+          ) : null}
+        </div>
+      </Main>
+
+      <ThreadDetailDrawer
+        threadKey={detailThreadKey}
+        memoryScope={memoryScope}
+        onOpenChange={(open) => {
+          if (!open) setDetailThreadKey(null)
+        }}
+      />
+    </>
+  )
+}
+
+function MemoryThreadsTable({
+  rows,
+  onView,
+}: {
+  rows: AdminMemoryThreadView[]
+  onView: (threadKey: string) => void
+}) {
+  return (
+    <Table>
+      <TableHeader>
+        <TableRow>
+          <TableHead>Memory ID</TableHead>
+          <TableHead>Thread Key</TableHead>
+          <TableHead>Label / Headline</TableHead>
+          <TableHead>Thread Type</TableHead>
+          <TableHead>Status</TableHead>
+          <TableHead>Object State</TableHead>
+          <TableHead>Members</TableHead>
+          <TableHead>Events</TableHead>
+          <TableHead>Last Event At</TableHead>
+          <TableHead className='text-end'>Actions</TableHead>
+        </TableRow>
+      </TableHeader>
+      <TableBody>
+        {rows.map((thread) => (
+          <TableRow key={thread.threadKey}>
+            <TableCell>{thread.memoryId}</TableCell>
+            <TableCell>{thread.threadKey}</TableCell>
+            <TableCell>{thread.displayLabel || thread.headline || '-'}</TableCell>
+            <TableCell>{thread.threadType}</TableCell>
+            <TableCell>
+              <Badge>{thread.lifecycleStatus}</Badge>
+            </TableCell>
+            <TableCell>{fieldValue(thread.objectState)}</TableCell>
+            <TableCell>{thread.memberCount}</TableCell>
+            <TableCell>{thread.eventCount}</TableCell>
+            <TableCell>{formatDateTime(thread.lastEventAt)}</TableCell>
+            <TableCell className='text-end'>
+              <Button
+                type='button'
+                variant='outline'
+                size='sm'
+                aria-label={`View thread ${thread.threadKey}`}
+                onClick={() => onView(thread.threadKey)}
+              >
+                View
+              </Button>
+            </TableCell>
+          </TableRow>
+        ))}
+      </TableBody>
+    </Table>
+  )
+}
+
+function buildMemoryThreadParams(
+  search: MemoryThreadsSearch,
+  memoryScope: string,
+  status: StatusFilter
+): MemoryThreadListParams {
+  return {
+    pageNo: search.pageNo,
+    pageSize: search.pageSize,
+    ...toUserAgentQuery(memoryScope),
+    ...(status === 'all' ? {} : { status }),
+  }
+}
+
+type MemoryThreadsSearch = {
+  pageNo: number
+  pageSize: number
+  status?: string
+}
+
+function readMemoryThreadsSearch(): MemoryThreadsSearch {
+  const params = readSearchParams()
+  return {
+    pageNo: readNumberParam(params, 'pageNo', DEFAULT_PAGE),
+    pageSize: readNumberParam(params, 'pageSize', DEFAULT_PAGE_SIZE),
+    status: readStringParam(params, 'status'),
+  }
+}
+
+function normalizeStatus(status: string | undefined): StatusFilter {
+  if (status === 'ACTIVE' || status === 'DORMANT' || status === 'CLOSED') {
+    return status
+  }
+  return 'all'
+}
+
+function readSearchParams() {
+  if (typeof window === 'undefined') return new URLSearchParams()
+  return new URLSearchParams(window.location.search)
+}
+
+function readStringParam(params: URLSearchParams, key: string) {
+  const value = params.get(key)?.trim()
+  return value ? value : undefined
+}
+
+function readNumberParam(
+  params: URLSearchParams,
+  key: string,
+  fallback: number
+) {
+  const value = params.get(key)
+  if (!value) return fallback
+  const parsed = Number(value)
+  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback
+}
+
+function writeUrlSearch(patch: Record<string, string | number | undefined>) {
+  if (typeof window === 'undefined') return
+  const url = new URL(window.location.href)
+  for (const [key, value] of Object.entries(patch)) {
+    if (value === undefined || value === '') {
+      url.searchParams.delete(key)
+    } else {
+      url.searchParams.set(key, String(value))
+    }
+  }
+  window.history.replaceState(window.history.state, '', url)
+}
+
+function fieldValue(value: unknown) {
+  if (value === null || value === undefined || value === '') return '-'
+  return String(value)
+}
diff --git a/memind-ui/src/features/memory-threads/thread-detail-drawer.tsx b/memind-ui/src/features/memory-threads/thread-detail-drawer.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/memory-threads/thread-detail-drawer.tsx
@@ -0,0 +1,195 @@
+import { useQuery } from '@tanstack/react-query'
+import {
+  Dialog,
+  DialogContent,
+  DialogDescription,
+  DialogHeader,
+  DialogTitle,
+} from '@/components/ui/dialog'
+import {
+  Table,
+  TableBody,
+  TableCell,
+  TableHead,
+  TableHeader,
+  TableRow,
+} from '@/components/ui/table'
+import {
+  getMemoryThread,
+  listMemoryThreadItems,
+} from '@/features/api/memory-threads'
+import {
+  EmptyState,
+  PageError,
+  PageLoading,
+  ScopeRequiredState,
+} from '@/features/components/data-state'
+import { JsonViewer } from '@/features/components/json-viewer'
+import type {
+  AdminMemoryThreadItemView,
+  AdminMemoryThreadView,
+} from '@/features/types'
+import { formatDateTime } from '@/lib/format'
+import { parseMemoryScope } from '@/lib/memory-scope'
+
+export function ThreadDetailDrawer({
+  threadKey,
+  memoryScope,
+  onOpenChange,
+}: {
+  threadKey: string | null
+  memoryScope: string
+  onOpenChange: (open: boolean) => void
+}) {
+  const scope = parseMemoryScope(memoryScope)
+  const threadQuery = useQuery({
+    queryKey: [
+      'memory-threads',
+      threadKey,
+      'detail',
+      scope.userId,
+      scope.agentId,
+      scope.hasAgentId,
+    ],
+    enabled: threadKey !== null && scope.hasUserId,
+    queryFn: () =>
+      getMemoryThread(threadKey as string, {
+        userId: scope.userId,
+        ...(scope.hasAgentId ? { agentId: scope.agentId } : {}),
+      }),
+  })
+  const membershipsQuery = useQuery({
+    queryKey: [
+      'memory-threads',
+      threadKey,
+      'items',
+      scope.userId,
+      scope.agentId,
+      scope.hasAgentId,
+    ],
+    enabled: threadKey !== null && scope.hasUserId,
+    queryFn: () =>
+      listMemoryThreadItems(threadKey as string, {
+        userId: scope.userId,
+        ...(scope.hasAgentId ? { agentId: scope.agentId } : {}),
+      }),
+  })
+
+  return (
+    <Dialog open={threadKey !== null} onOpenChange={onOpenChange}>
+      <DialogContent className='max-h-[85vh] overflow-auto sm:max-w-3xl'>
+        <DialogHeader>
+          <DialogTitle>Memory thread {threadKey}</DialogTitle>
+          <DialogDescription>
+            {threadQuery.data?.memoryId ?? memoryScope}
+          </DialogDescription>
+        </DialogHeader>
+
+        {!scope.hasUserId ? (
+          <ScopeRequiredState message='Set memory scope with userId to load thread details.' />
+        ) : null}
+        {threadQuery.isLoading ? <PageLoading /> : null}
+        {threadQuery.isError ? (
+          <PageError
+            message='Unable to load memory thread detail.'
+            onRetry={threadQuery.refetch}
+          />
+        ) : null}
+        {threadQuery.data ? (
+          <ThreadDetail thread={threadQuery.data} memberships={membershipsQuery.data ?? []} />
+        ) : null}
+        {membershipsQuery.isError ? (
+          <PageError
+            message='Unable to load thread item memberships.'
+            onRetry={membershipsQuery.refetch}
+          />
+        ) : null}
+      </DialogContent>
+    </Dialog>
+  )
+}
+
+function ThreadDetail({
+  thread,
+  memberships,
+}: {
+  thread: AdminMemoryThreadView
+  memberships: AdminMemoryThreadItemView[]
+}) {
+  return (
+    <div className='flex flex-col gap-5 text-sm'>
+      <div className='grid gap-2 md:grid-cols-2'>
+        <p>headline: {fieldValue(thread.headline)}</p>
+        <p>threadType: {thread.threadType}</p>
+        <p>anchorKind: {fieldValue(thread.anchorKind)}</p>
+        <p>anchorKey: {fieldValue(thread.anchorKey)}</p>
+        <p>objectState: {fieldValue(thread.objectState)}</p>
+        <p>snapshotVersion: {thread.snapshotVersion}</p>
+        <p>openedAt: {formatDateTime(thread.openedAt)}</p>
+        <p>closedAt: {formatDateTime(thread.closedAt)}</p>
+        <p>lastEventAt: {formatDateTime(thread.lastEventAt)}</p>
+        <p>
+          lastMeaningfulUpdateAt:{' '}
+          {formatDateTime(thread.lastMeaningfulUpdateAt)}
+        </p>
+        <p>createdAt: {formatDateTime(thread.createdAt)}</p>
+        <p>updatedAt: {formatDateTime(thread.updatedAt)}</p>
+      </div>
+
+      <JsonViewer
+        label='snapshotJson'
+        value={thread.snapshotJson ?? {}}
+        defaultExpanded
+      />
+
+      <section className='flex flex-col gap-2'>
+        <h3 className='font-medium'>Thread item memberships</h3>
+        {memberships.length === 0 ? (
+          <EmptyState title='No thread item memberships found.' />
+        ) : (
+          <MembershipTable memberships={memberships} />
+        )}
+      </section>
+    </div>
+  )
+}
+
+function MembershipTable({
+  memberships,
+}: {
+  memberships: AdminMemoryThreadItemView[]
+}) {
+  return (
+    <Table>
+      <TableHeader>
+        <TableRow>
+          <TableHead>Item ID</TableHead>
+          <TableHead>Role</TableHead>
+          <TableHead>Primary</TableHead>
+          <TableHead>Relevance Weight</TableHead>
+          <TableHead>Created At</TableHead>
+          <TableHead>Updated At</TableHead>
+        </TableRow>
+      </TableHeader>
+      <TableBody>
+        {memberships.map((membership) => (
+          <TableRow key={`${membership.threadKey}:${membership.itemId}`}>
+            <TableCell>{membership.itemId}</TableCell>
+            <TableCell>{membership.role}</TableCell>
+            <TableCell>primary: {membership.primary ? 'yes' : 'no'}</TableCell>
+            <TableCell>
+              relevanceWeight: {membership.relevanceWeight}
+            </TableCell>
+            <TableCell>{formatDateTime(membership.createdAt)}</TableCell>
+            <TableCell>{formatDateTime(membership.updatedAt)}</TableCell>
+          </TableRow>
+        ))}
+      </TableBody>
+    </Table>
+  )
+}
+
+function fieldValue(value: unknown) {
+  if (value === null || value === undefined || value === '') return '-'
+  return String(value)
+}
diff --git a/memind-ui/src/features/memory-threads/thread-status-panel.tsx b/memind-ui/src/features/memory-threads/thread-status-panel.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/memory-threads/thread-status-panel.tsx
@@ -0,0 +1,132 @@
+import { useState } from 'react'
+import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
+import {
+  AlertDialog,
+  AlertDialogCancel,
+  AlertDialogContent,
+  AlertDialogDescription,
+  AlertDialogFooter,
+  AlertDialogHeader,
+  AlertDialogTitle,
+} from '@/components/ui/alert-dialog'
+import { Button } from '@/components/ui/button'
+import {
+  getMemoryThreadStatus,
+  rebuildMemoryThreads,
+} from '@/features/api/memory-threads'
+import {
+  PageError,
+  PageLoading,
+  ScopeRequiredState,
+} from '@/features/components/data-state'
+import type { AdminMemoryThreadStatusView } from '@/features/types'
+import { formatDateTime } from '@/lib/format'
+import { parseMemoryScope } from '@/lib/memory-scope'
+
+export function ThreadStatusPanel({ memoryScope }: { memoryScope: string }) {
+  const queryClient = useQueryClient()
+  const [confirmOpen, setConfirmOpen] = useState(false)
+  const scope = parseMemoryScope(memoryScope)
+  const statusQuery = useQuery({
+    queryKey: [
+      'memory-threads',
+      'status',
+      scope.userId,
+      scope.agentId,
+      scope.hasAgentId,
+    ],
+    enabled: scope.hasUserId,
+    queryFn: () =>
+      getMemoryThreadStatus({
+        userId: scope.userId,
+        ...(scope.hasAgentId ? { agentId: scope.agentId } : {}),
+      }),
+  })
+  const rebuildMutation = useMutation({
+    mutationFn: () =>
+      rebuildMemoryThreads({
+        userId: scope.userId,
+        ...(scope.hasAgentId ? { agentId: scope.agentId } : {}),
+      }),
+    onSuccess: async () => {
+      setConfirmOpen(false)
+      await queryClient.invalidateQueries({ queryKey: ['memory-threads'] })
+    },
+  })
+
+  return (
+    <section id='thread-status' className='flex flex-col gap-3'>
+      <div className='flex flex-wrap items-center justify-between gap-3'>
+        <h3 className='text-lg font-semibold'>Thread Projection Status</h3>
+        <Button
+          type='button'
+          variant='outline'
+          disabled={!scope.hasUserId || rebuildMutation.isPending}
+          onClick={() => setConfirmOpen(true)}
+        >
+          Rebuild projections
+        </Button>
+      </div>
+
+      {!scope.hasUserId ? (
+        <ScopeRequiredState message='Set memory scope with userId to load thread status.' />
+      ) : null}
+      {statusQuery.isLoading ? <PageLoading /> : null}
+      {statusQuery.isError ? (
+        <PageError
+          message='Unable to load thread projection status.'
+          onRetry={statusQuery.refetch}
+        />
+      ) : null}
+      {statusQuery.data ? <StatusFields status={statusQuery.data} /> : null}
+
+      <AlertDialog open={confirmOpen} onOpenChange={setConfirmOpen}>
+        <AlertDialogContent>
+          <AlertDialogHeader>
+            <AlertDialogTitle>Rebuild memory thread projections</AlertDialogTitle>
+            <AlertDialogDescription>
+              Rebuild projections for the active memory scope after server-side
+              validation.
+            </AlertDialogDescription>
+          </AlertDialogHeader>
+          <AlertDialogFooter>
+            <AlertDialogCancel disabled={rebuildMutation.isPending}>
+              Cancel
+            </AlertDialogCancel>
+            <Button
+              type='button'
+              variant='destructive'
+              disabled={rebuildMutation.isPending}
+              onClick={() => rebuildMutation.mutate()}
+            >
+              Rebuild
+            </Button>
+          </AlertDialogFooter>
+        </AlertDialogContent>
+      </AlertDialog>
+    </section>
+  )
+}
+
+function StatusFields({ status }: { status: AdminMemoryThreadStatusView }) {
+  return (
+    <div className='grid gap-2 rounded-md border p-3 text-sm md:grid-cols-2'>
+      <p>projectionState: {fieldValue(status.projectionState)}</p>
+      <p>pendingCount: {status.pendingCount}</p>
+      <p>failedCount: {status.failedCount}</p>
+      <p>rebuildInProgress: {status.rebuildInProgress ? 'yes' : 'no'}</p>
+      <p>lastProcessedItemId: {fieldValue(status.lastProcessedItemId)}</p>
+      <p>
+        materializationPolicyVersion:{' '}
+        {fieldValue(status.materializationPolicyVersion)}
+      </p>
+      <p>updatedAt: {formatDateTime(status.updatedAt)}</p>
+      <p>invalidationReason: {fieldValue(status.invalidationReason)}</p>
+    </div>
+  )
+}
+
+function fieldValue(value: unknown) {
+  if (value === null || value === undefined || value === '') return '-'
+  return String(value)
+}
diff --git a/memind-ui/src/features/raw-data/index.tsx b/memind-ui/src/features/raw-data/index.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/raw-data/index.tsx
@@ -0,0 +1,356 @@
+import { useMemo, useState } from 'react'
+import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
+import { Header } from '@/components/layout/header'
+import { Main } from '@/components/layout/main'
+import { Badge } from '@/components/ui/badge'
+import { Button } from '@/components/ui/button'
+import { Checkbox } from '@/components/ui/checkbox'
+import {
+  Dialog,
+  DialogContent,
+  DialogDescription,
+  DialogHeader,
+  DialogTitle,
+} from '@/components/ui/dialog'
+import {
+  Table,
+  TableBody,
+  TableCell,
+  TableHead,
+  TableHeader,
+  TableRow,
+} from '@/components/ui/table'
+import {
+  deleteRawData,
+  getRawData,
+  listRawData,
+  type RawDataListParams,
+} from '@/features/api/raw-data'
+import { ConfirmResultDialog } from '@/features/components/confirm-result-dialog'
+import {
+  EmptyState,
+  PageError,
+  PageLoading,
+  TableLoading,
+} from '@/features/components/data-state'
+import { JsonViewer } from '@/features/components/json-viewer'
+import { readMemoryScopeFromLocation } from '@/features/components/memory-scope-location'
+import type { AdminRawDataView } from '@/features/types'
+import { compactJson, formatDateTime, truncateText } from '@/lib/format'
+import { toUserAgentQuery } from '@/lib/memory-scope'
+
+const DEFAULT_PAGE = 1
+const DEFAULT_PAGE_SIZE = 10
+
+export function RawDataPage() {
+  const queryClient = useQueryClient()
+  const [selectedIds, setSelectedIds] = useState<Set<string>>(() => new Set())
+  const [deleteOpen, setDeleteOpen] = useState(false)
+  const [detailRawDataId, setDetailRawDataId] = useState<string | null>(
+    null
+  )
+
+  const search = readRawDataSearch()
+  const memoryScope = readMemoryScopeFromLocation()
+  const params = useMemo(
+    () => buildRawDataListParams(search, memoryScope),
+    [search, memoryScope]
+  )
+  const rawDataQuery = useQuery({
+    queryKey: ['raw-data', params],
+    queryFn: () => listRawData(params),
+  })
+  const deleteMutation = useMutation({
+    mutationFn: (rawDataIds: string[]) => deleteRawData(rawDataIds),
+    onSuccess: async () => {
+      setSelectedIds(new Set())
+      await Promise.all([
+        queryClient.invalidateQueries({ queryKey: ['raw-data'] }),
+        queryClient.invalidateQueries({ queryKey: ['items'] }),
+        queryClient.invalidateQueries({ queryKey: ['dashboard'] }),
+      ])
+    },
+  })
+
+  const rows = rawDataQuery.data?.list ?? []
+  const selectedRawDataIds = [...selectedIds]
+
+  return (
+    <>
+      <Header>
+        <h1 className='truncate text-lg font-semibold'>Raw Data</h1>
+      </Header>
+      <Main>
+        <div className='flex flex-col gap-4'>
+          <div className='flex flex-wrap items-center justify-between gap-3'>
+            <div className='flex flex-col gap-1'>
+              <h2 className='text-2xl font-semibold'>Raw Data</h2>
+              <p className='text-sm text-muted-foreground'>
+                Inspect source records, captions, payloads, and cleanup impact.
+              </p>
+            </div>
+            <Button
+              type='button'
+              variant='destructive'
+              disabled={selectedIds.size === 0}
+              onClick={() => {
+                deleteMutation.reset()
+                setDeleteOpen(true)
+              }}
+            >
+              Delete selected
+            </Button>
+          </div>
+
+          {rawDataQuery.isLoading ? <TableLoading columns={8} /> : null}
+          {rawDataQuery.isError ? (
+            <PageError
+              message='Unable to load raw data.'
+              onRetry={rawDataQuery.refetch}
+            />
+          ) : null}
+          {rawDataQuery.data && rows.length === 0 ? (
+            <EmptyState title='No raw data found.' />
+          ) : null}
+          {rows.length > 0 ? (
+            <RawDataTable
+              rows={rows}
+              selectedIds={selectedIds}
+              onToggleSelected={(rawDataId, checked) => {
+                setSelectedIds((current) => {
+                  const next = new Set(current)
+                  if (checked) {
+                    next.add(rawDataId)
+                  } else {
+                    next.delete(rawDataId)
+                  }
+                  return next
+                })
+              }}
+              onView={setDetailRawDataId}
+            />
+          ) : null}
+
+          {rawDataQuery.data ? (
+            <p className='text-sm text-muted-foreground'>
+              Total rows: {rawDataQuery.data.total}
+            </p>
+          ) : null}
+        </div>
+      </Main>
+
+      <ConfirmResultDialog
+        open={deleteOpen}
+        onOpenChange={setDeleteOpen}
+        title='Delete selected raw data'
+        selectedCount={selectedRawDataIds.length}
+        description='Only the selected raw data ids will be sent to the server.'
+        cascadeWarning='Associated memory items will also be deleted.'
+        isPending={deleteMutation.isPending}
+        result={deleteMutation.data ? { ...deleteMutation.data } : null}
+        onConfirm={() => deleteMutation.mutate(selectedRawDataIds)}
+      />
+
+      <RawDataDetailDialog
+        rawDataId={detailRawDataId}
+        onOpenChange={(open) => {
+          if (!open) setDetailRawDataId(null)
+        }}
+      />
+    </>
+  )
+}
+
+function RawDataTable({
+  rows,
+  selectedIds,
+  onToggleSelected,
+  onView,
+}: {
+  rows: AdminRawDataView[]
+  selectedIds: Set<string>
+  onToggleSelected: (rawDataId: string, checked: boolean) => void
+  onView: (rawDataId: string) => void
+}) {
+  return (
+    <Table>
+      <TableHeader>
+        <TableRow>
+          <TableHead className='w-10'>Select</TableHead>
+          <TableHead>Raw Data ID</TableHead>
+          <TableHead>Memory ID</TableHead>
+          <TableHead>Type</TableHead>
+          <TableHead>Caption</TableHead>
+          <TableHead>Source Client</TableHead>
+          <TableHead>Content ID</TableHead>
+          <TableHead>Start Time</TableHead>
+          <TableHead>Created At</TableHead>
+          <TableHead className='text-end'>Actions</TableHead>
+        </TableRow>
+      </TableHeader>
+      <TableBody>
+        {rows.map((rawData) => (
+          <TableRow key={rawData.rawDataId}>
+            <TableCell>
+              <Checkbox
+                aria-label={`Select raw data ${rawData.rawDataId}`}
+                checked={selectedIds.has(rawData.rawDataId)}
+                onCheckedChange={(checked) =>
+                  onToggleSelected(rawData.rawDataId, checked === true)
+                }
+              />
+            </TableCell>
+            <TableCell>{rawData.rawDataId}</TableCell>
+            <TableCell>{rawData.memoryId}</TableCell>
+            <TableCell>
+              {rawData.type ? <Badge>{rawData.type}</Badge> : '-'}
+            </TableCell>
+            <TableCell className='max-w-96 whitespace-normal'>
+              <span className='sr-only'>Caption preview: </span>
+              {truncateText(rawData.caption, 12)}
+            </TableCell>
+            <TableCell>{fieldValue(rawData.sourceClient)}</TableCell>
+            <TableCell>{fieldValue(rawData.contentId)}</TableCell>
+            <TableCell>{formatDateTime(rawData.startTime)}</TableCell>
+            <TableCell>{formatDateTime(rawData.createdAt)}</TableCell>
+            <TableCell className='text-end'>
+              <Button
+                type='button'
+                variant='outline'
+                size='sm'
+                aria-label={`View raw data ${rawData.rawDataId}`}
+                onClick={() => onView(rawData.rawDataId)}
+              >
+                View
+              </Button>
+            </TableCell>
+          </TableRow>
+        ))}
+      </TableBody>
+    </Table>
+  )
+}
+
+function RawDataDetailDialog({
+  rawDataId,
+  onOpenChange,
+}: {
+  rawDataId: string | null
+  onOpenChange: (open: boolean) => void
+}) {
+  const query = useQuery({
+    queryKey: ['raw-data', rawDataId, 'detail'],
+    enabled: rawDataId !== null,
+    queryFn: () => getRawData(rawDataId as string),
+  })
+  const rawData = query.data
+
+  return (
+    <Dialog open={rawDataId !== null} onOpenChange={onOpenChange}>
+      <DialogContent className='max-h-[85vh] overflow-auto sm:max-w-3xl'>
+        <DialogHeader>
+          <DialogTitle>Raw data {rawDataId}</DialogTitle>
+          <DialogDescription>{rawData?.memoryId}</DialogDescription>
+        </DialogHeader>
+
+        {query.isLoading ? <PageLoading /> : null}
+        {query.isError ? (
+          <PageError
+            message='Unable to load raw data detail.'
+            onRetry={query.refetch}
+          />
+        ) : null}
+        {rawData ? (
+          <div className='flex flex-col gap-5 text-sm'>
+            <section className='flex flex-col gap-2'>
+              <h3 className='font-medium'>Caption</h3>
+              <p className='whitespace-pre-wrap rounded-md bg-muted p-3'>
+                {fieldValue(rawData.caption)}
+              </p>
+            </section>
+
+            <div className='grid gap-2 md:grid-cols-2'>
+              <p>type: {fieldValue(rawData.type)}</p>
+              <p>sourceClient: {fieldValue(rawData.sourceClient)}</p>
+              <p>contentId: {fieldValue(rawData.contentId)}</p>
+              <p>captionVectorId: {fieldValue(rawData.captionVectorId)}</p>
+              <p>startTime: {formatDateTime(rawData.startTime)}</p>
+              <p>endTime: {formatDateTime(rawData.endTime)}</p>
+              <p>createdAt: {formatDateTime(rawData.createdAt)}</p>
+              <p>updatedAt: {formatDateTime(rawData.updatedAt)}</p>
+            </div>
+
+            <JsonViewer
+              label='payload JSON'
+              value={rawData.segment ?? {}}
+              defaultExpanded
+            />
+            <JsonViewer
+              label='metadata'
+              value={rawData.metadata ?? {}}
+              defaultExpanded
+            />
+          </div>
+        ) : null}
+      </DialogContent>
+    </Dialog>
+  )
+}
+
+function buildRawDataListParams(
+  search: RawDataSearch,
+  memoryScope: string
+): RawDataListParams {
+  return {
+    pageNo: search.pageNo,
+    pageSize: search.pageSize,
+    ...toUserAgentQuery(memoryScope),
+    startTimeFrom: search.startTimeFrom,
+    startTimeTo: search.startTimeTo,
+  }
+}
+
+type RawDataSearch = {
+  pageNo: number
+  pageSize: number
+  startTimeFrom?: string
+  startTimeTo?: string
+}
+
+function readRawDataSearch(): RawDataSearch {
+  const params = readSearchParams()
+  return {
+    pageNo: readNumberParam(params, 'pageNo', DEFAULT_PAGE),
+    pageSize: readNumberParam(params, 'pageSize', DEFAULT_PAGE_SIZE),
+    startTimeFrom: readStringParam(params, 'startTimeFrom'),
+    startTimeTo: readStringParam(params, 'startTimeTo'),
+  }
+}
+
+function readSearchParams() {
+  if (typeof window === 'undefined') return new URLSearchParams()
+  return new URLSearchParams(window.location.search)
+}
+
+function readStringParam(params: URLSearchParams, key: string) {
+  const value = params.get(key)?.trim()
+  return value ? value : undefined
+}
+
+function readNumberParam(
+  params: URLSearchParams,
+  key: string,
+  fallback: number
+) {
+  const value = params.get(key)
+  if (!value) return fallback
+  const parsed = Number(value)
+  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback
+}
+
+function fieldValue(value: unknown) {
+  if (value === null || value === undefined || value === '') return '-'
+  if (Array.isArray(value)) return value.length > 0 ? value.join(', ') : '-'
+  if (typeof value === 'object') return compactJson(value)
+  return String(value)
+}
diff --git a/memind-ui/src/features/retrieve/index.tsx b/memind-ui/src/features/retrieve/index.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/retrieve/index.tsx
@@ -0,0 +1,229 @@
+import {
+  useMemo,
+  useState,
+  type FormEvent,
+  type ReactElement,
+  type ReactNode,
+} from 'react'
+import { useMutation } from '@tanstack/react-query'
+import { Header } from '@/components/layout/header'
+import { Main } from '@/components/layout/main'
+import { Button } from '@/components/ui/button'
+import { Checkbox } from '@/components/ui/checkbox'
+import { Input } from '@/components/ui/input'
+import { Label } from '@/components/ui/label'
+import { Textarea } from '@/components/ui/textarea'
+import { retrieveMemory } from '@/features/api/retrieve'
+import { PageError } from '@/features/components/data-state'
+import { readMemoryScopeFromLocation } from '@/features/components/memory-scope-location'
+import type { RetrieveMemoryResponse } from '@/features/types'
+import { parseMemoryScope } from '@/lib/memory-scope'
+import { RetrieveTrace } from './retrieve-trace'
+
+type FormErrors = {
+  userId?: string
+  agentId?: string
+  query?: string
+}
+
+export function RetrievePage() {
+  const initialScope = useMemo(
+    () => parseMemoryScope(readMemoryScopeFromLocation()),
+    []
+  )
+  const [userId, setUserId] = useState(initialScope.userId)
+  const [agentId, setAgentId] = useState(initialScope.agentId)
+  const [queryText, setQueryText] = useState('')
+  const [strategy, setStrategy] = useState('SIMPLE')
+  const [trace, setTrace] = useState(false)
+  const [errors, setErrors] = useState<FormErrors>({})
+
+  const mutation = useMutation({
+    mutationFn: retrieveMemory,
+  })
+
+  const onSubmit = (event: FormEvent<HTMLFormElement>) => {
+    event.preventDefault()
+    const nextErrors = validateForm({ userId, agentId, queryText })
+    setErrors(nextErrors)
+    mutation.reset()
+
+    if (Object.keys(nextErrors).length > 0) return
+
+    mutation.mutate({
+      userId: userId.trim(),
+      agentId: agentId.trim(),
+      query: queryText.trim(),
+      strategy,
+      trace,
+    })
+  }
+
+  return (
+    <>
+      <Header>
+        <h1 className='truncate text-lg font-semibold'>Retrieve</h1>
+      </Header>
+      <Main>
+        <div className='flex flex-col gap-5'>
+          <form onSubmit={onSubmit} className='flex flex-col gap-4'>
+            <div className='grid gap-4 md:grid-cols-2 xl:grid-cols-4'>
+              <FormField label='userId' error={errors.userId}>
+                <Input
+                  id='retrieve-user-id'
+                  value={userId}
+                  aria-invalid={Boolean(errors.userId)}
+                  onChange={(event) => setUserId(event.target.value)}
+                />
+              </FormField>
+              <FormField label='agentId' error={errors.agentId}>
+                <Input
+                  id='retrieve-agent-id'
+                  value={agentId}
+                  aria-invalid={Boolean(errors.agentId)}
+                  onChange={(event) => setAgentId(event.target.value)}
+                />
+              </FormField>
+              <FormField label='Strategy'>
+                <select
+                  id='retrieve-strategy'
+                  value={strategy}
+                  className='h-9 rounded-md border bg-background px-3 text-sm'
+                  onChange={(event) => setStrategy(event.target.value)}
+                >
+                  <option value='SIMPLE'>SIMPLE</option>
+                  <option value='DEEP'>DEEP</option>
+                </select>
+              </FormField>
+              <div className='flex items-center gap-3 self-end pb-2'>
+                <Checkbox
+                  id='retrieve-trace'
+                  checked={trace}
+                  onCheckedChange={(checked) => setTrace(checked === true)}
+                />
+                <Label htmlFor='retrieve-trace'>Trace</Label>
+              </div>
+            </div>
+
+            <FormField label='Query' error={errors.query}>
+              <Textarea
+                id='retrieve-query'
+                value={queryText}
+                aria-invalid={Boolean(errors.query)}
+                onChange={(event) => setQueryText(event.target.value)}
+              />
+            </FormField>
+
+            <Button
+              type='submit'
+              className='w-fit'
+              disabled={mutation.isPending}
+            >
+              Retrieve
+            </Button>
+          </form>
+
+          {mutation.isError ? (
+            <PageError message='Retrieve request failed.' />
+          ) : null}
+
+          {mutation.data ? <RetrieveResults result={mutation.data} /> : null}
+        </div>
+      </Main>
+    </>
+  )
+}
+
+function FormField({
+  label,
+  error,
+  children,
+}: {
+  label: string
+  error?: string
+  children: ReactElement<{ id: string }>
+}) {
+  const id = children.props.id
+
+  return (
+    <div className='flex flex-col gap-2'>
+      <Label htmlFor={id}>{label}</Label>
+      {children}
+      {error ? <p className='text-sm text-destructive'>{error}</p> : null}
+    </div>
+  )
+}
+
+function RetrieveResults({ result }: { result: RetrieveMemoryResponse }) {
+  return (
+    <div className='flex flex-col gap-4'>
+      <ResultSection title='Items'>
+        {result.items.map((item) => (
+          <ResultRow key={item.id} title={item.id} text={item.text} />
+        ))}
+      </ResultSection>
+      <ResultSection title='Insights'>
+        {result.insights.map((insight) => (
+          <ResultRow key={insight.id} title={insight.id} text={insight.text} />
+        ))}
+      </ResultSection>
+      <ResultSection title='Raw data'>
+        {result.rawData.map((rawData) => (
+          <ResultRow
+            key={rawData.rawDataId}
+            title={rawData.rawDataId}
+            text={rawData.caption ?? '-'}
+          />
+        ))}
+      </ResultSection>
+      <ResultSection title='Evidences'>
+        {result.evidences.map((evidence) => (
+          <p key={evidence} className='text-sm'>
+            {evidence}
+          </p>
+        ))}
+      </ResultSection>
+      <RetrieveTrace trace={result.trace} />
+    </div>
+  )
+}
+
+function ResultSection({
+  title,
+  children,
+}: {
+  title: string
+  children: ReactNode
+}) {
+  return (
+    <section className='rounded-md border p-4'>
+      <h2 className='font-semibold'>{title}</h2>
+      <div className='mt-3 flex flex-col gap-2'>{children}</div>
+    </section>
+  )
+}
+
+function ResultRow({ title, text }: { title: string; text: string }) {
+  return (
+    <article className='rounded-md border p-3 text-sm'>
+      <p className='font-medium'>{title}</p>
+      <p className='mt-1'>{text}</p>
+    </article>
+  )
+}
+
+function validateForm({
+  userId,
+  agentId,
+  queryText,
+}: {
+  userId: string
+  agentId: string
+  queryText: string
+}) {
+  const errors: FormErrors = {}
+  if (!userId.trim()) errors.userId = 'userId is required.'
+  if (!agentId.trim()) errors.agentId = 'agentId is required.'
+  if (!queryText.trim()) errors.query = 'Query is required.'
+  return errors
+}
diff --git a/memind-ui/src/features/retrieve/retrieve-trace.tsx b/memind-ui/src/features/retrieve/retrieve-trace.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/retrieve/retrieve-trace.tsx
@@ -0,0 +1,120 @@
+import { useState } from 'react'
+import { ChevronDown, ChevronRight } from 'lucide-react'
+import { Badge } from '@/components/ui/badge'
+import { Button } from '@/components/ui/button'
+import { JsonViewer } from '@/features/components/json-viewer'
+import type { RetrievalTraceStageView, RetrievalTraceView } from '@/features/types'
+
+export function RetrieveTrace({ trace }: { trace: RetrievalTraceView | null }) {
+  const [open, setOpen] = useState(false)
+
+  if (!trace) return null
+
+  return (
+    <section className='rounded-md border p-4'>
+      <Button
+        type='button'
+        variant='ghost'
+        className='w-fit'
+        aria-expanded={open}
+        onClick={() => setOpen((current) => !current)}
+      >
+        {open ? <ChevronDown /> : <ChevronRight />}
+        Trace details
+      </Button>
+
+      {open ? (
+        <div className='mt-4 flex flex-col gap-4'>
+          <div className='grid gap-3 md:grid-cols-2'>
+            <TraceSummary
+              title='Merge'
+              rows={[
+                ['inputCount', trace.merge?.inputCount],
+                ['outputCount', trace.merge?.outputCount],
+                ['deduplicatedCount', trace.merge?.deduplicatedCount],
+                ['sourceCount', trace.merge?.sourceCount],
+                ['status', trace.merge?.status],
+              ]}
+            />
+            <TraceSummary
+              title='Final results'
+              rows={[
+                ['strategy', trace.finalResults?.strategy],
+                ['status', trace.finalResults?.status],
+                ['itemCount', trace.finalResults?.itemCount],
+                ['insightCount', trace.finalResults?.insightCount],
+                ['rawDataCount', trace.finalResults?.rawDataCount],
+                ['evidenceCount', trace.finalResults?.evidenceCount],
+              ]}
+            />
+          </div>
+
+          <div className='flex flex-col gap-3'>
+            {trace.stages.map((stage, index) => (
+              <TraceStage key={`${stage.stage}:${index}`} stage={stage} />
+            ))}
+          </div>
+        </div>
+      ) : null}
+    </section>
+  )
+}
+
+function TraceStage({ stage }: { stage: RetrievalTraceStageView }) {
+  return (
+    <article className='rounded-md border p-3 text-sm'>
+      <div className='flex flex-wrap items-center gap-2'>
+        <h3 className='font-medium'>{stage.stage}</h3>
+        {stage.degraded ? <Badge variant='secondary'>degraded</Badge> : null}
+        {stage.skipped ? <Badge variant='secondary'>skipped</Badge> : null}
+      </div>
+      <div className='mt-2 grid gap-1 md:grid-cols-2'>
+        <p>method: {display(stage.method)}</p>
+        <p>status: {display(stage.status)}</p>
+        <p>duration: {displayDuration(stage.durationMillis)}</p>
+        <p>
+          inputCount: {display(stage.inputCount)} -&gt; resultCount:{' '}
+          {display(stage.resultCount)}
+        </p>
+        <p>candidateCount: {display(stage.candidateCount)}</p>
+        <p>tier: {display(stage.tier)}</p>
+      </div>
+      <div className='mt-3 grid gap-3 md:grid-cols-2'>
+        <JsonViewer label='attributes' value={stage.attributes ?? {}} />
+        <JsonViewer label='candidates' value={stage.candidates} />
+      </div>
+    </article>
+  )
+}
+
+function TraceSummary({
+  title,
+  rows,
+}: {
+  title: string
+  rows: Array<[string, unknown]>
+}) {
+  return (
+    <section className='rounded-md border p-3 text-sm'>
+      <h3 className='font-medium'>{title}</h3>
+      <dl className='mt-2 grid gap-1'>
+        {rows.map(([label, value]) => (
+          <div key={label} className='flex gap-2'>
+            <dt className='text-muted-foreground'>{label}:</dt>
+            <dd>{display(value)}</dd>
+          </div>
+        ))}
+      </dl>
+    </section>
+  )
+}
+
+function display(value: unknown) {
+  if (value === null || value === undefined || value === '') return '-'
+  return String(value)
+}
+
+function displayDuration(value: number | null) {
+  if (value === null || value === undefined) return '-'
+  return `${value}ms`
+}
diff --git a/memind-ui/src/features/types.ts b/memind-ui/src/features/types.ts
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/features/types.ts
@@ -0,0 +1,457 @@
+export type JsonRecord = Record<string, unknown>
+
+export type NamedCount = {
+  name: string
+  count: number
+}
+
+export type StateCount = {
+  state: string
+  count: number
+}
+
+export type DailyCount = {
+  date: string
+  count: number
+}
+
+export type AdminDashboardView = {
+  totals: {
+    rawData: number
+    items: number
+    insights: number
+    memoryThreads: number
+    graphEntities: number
+    itemLinks: number
+  }
+  backlog: {
+    conversationPending: number
+    insightUnbuilt: number
+    insightUngrouped: number
+    threadOutboxPending: number
+    threadOutboxFailed: number
+    graphBatchRepairRequired: number
+  }
+  activity: {
+    days: number
+    rawDataCreated: DailyCount[]
+    itemsCreated: DailyCount[]
+    insightsCreated: DailyCount[]
+  }
+  breakdown: {
+    sourceClients: NamedCount[]
+    rawDataTypes: NamedCount[]
+    itemTypes: NamedCount[]
+    insightTypes: NamedCount[]
+    graphLinkTypes: NamedCount[]
+  }
+  healthSignals: {
+    graphEnabled: boolean
+    retrievalGraphAssistEnabled: boolean
+    threadProjectionStates: StateCount[]
+  }
+}
+
+export type AdminItemView = {
+  itemId: number
+  userId: string
+  agentId: string | null
+  memoryId: string
+  content: string
+  scope: string | null
+  category: string | null
+  vectorId: string | null
+  rawDataId: string | null
+  contentHash: string | null
+  occurredAt: string | null
+  observedAt: string | null
+  metadata: JsonRecord | null
+  type: string | null
+  rawDataType: string | null
+  sourceClient: string | null
+  createdAt: string
+  updatedAt: string
+}
+
+export type AdminRawDataView = {
+  rawDataId: string
+  userId: string
+  agentId: string | null
+  memoryId: string
+  type: string | null
+  sourceClient: string | null
+  contentId: string | null
+  segment: JsonRecord | null
+  caption: string | null
+  captionVectorId: string | null
+  metadata: JsonRecord | null
+  startTime: string | null
+  endTime: string | null
+  createdAt: string
+  updatedAt: string
+}
+
+export type InsightPoint = JsonRecord
+
+export type AdminInsightView = {
+  insightId: number
+  userId: string
+  agentId: string | null
+  memoryId: string
+  type: string | null
+  scope: string | null
+  name: string | null
+  categories: string[]
+  content: string
+  points: InsightPoint[]
+  groupName: string | null
+  lastReasonedAt: string | null
+  summaryEmbedding: number[] | null
+  tier: string | null
+  parentInsightId: number | null
+  childInsightIds: number[]
+  version: number | null
+  createdAt: string
+  updatedAt: string
+}
+
+export type ConversationBufferView = {
+  id: number
+  sessionId: string | null
+  userId: string
+  agentId: string | null
+  memoryId: string
+  role: string | null
+  content: string
+  userName: string | null
+  sourceClient: string | null
+  timestamp: string | null
+  extracted: boolean | null
+  createdAt: string
+  updatedAt: string
+}
+
+export type InsightBufferView = {
+  id: number
+  userId: string
+  agentId: string | null
+  memoryId: string
+  insightTypeName: string
+  itemId: number | null
+  groupName: string | null
+  built: boolean | null
+  createdAt: string
+  updatedAt: string
+}
+
+export type InsightBufferGroupView = {
+  memoryId: string
+  insightTypeName: string
+  groupName: string | null
+  total: number
+  unbuilt: number
+  built: number
+}
+
+export type AdminMemoryThreadView = {
+  userId: string
+  agentId: string | null
+  memoryId: string
+  threadKey: string
+  threadType: string
+  anchorKind: string | null
+  anchorKey: string | null
+  displayLabel: string | null
+  lifecycleStatus: 'ACTIVE' | 'DORMANT' | 'CLOSED' | string
+  objectState: string | null
+  headline: string | null
+  snapshotJson: JsonRecord | null
+  snapshotVersion: number
+  openedAt: string | null
+  lastEventAt: string | null
+  lastMeaningfulUpdateAt: string | null
+  closedAt: string | null
+  eventCount: number
+  memberCount: number
+  createdAt: string
+  updatedAt: string
+}
+
+export type AdminMemoryThreadItemView = {
+  userId: string
+  agentId: string | null
+  memoryId: string
+  threadKey: string
+  itemId: number
+  role: string
+  primary: boolean
+  relevanceWeight: number
+  createdAt: string
+  updatedAt: string
+}
+
+export type AdminItemMemoryThreadView = {
+  userId: string
+  agentId: string | null
+  memoryId: string
+  threadKey: string
+  threadType: string
+  anchorKind: string | null
+  anchorKey: string | null
+  displayLabel: string | null
+  lifecycleStatus: string
+  objectState: string | null
+  headline: string | null
+  itemId: number
+  role: string
+  primary: boolean
+  relevanceWeight: number
+  createdAt: string
+  updatedAt: string
+}
+
+export type AdminMemoryThreadStatusView = {
+  projectionState: string | null
+  pendingCount: number
+  failedCount: number
+  rebuildInProgress: boolean
+  lastProcessedItemId: number | null
+  materializationPolicyVersion: string | null
+  updatedAt: string | null
+  invalidationReason: string | null
+}
+
+export type ItemGraphSummaryView = {
+  entityCount: number
+  aliasCount: number
+  mentionCount: number
+  itemLinkCount: number
+  cooccurrenceCount: number
+  graphBatchCountByState: NamedCount[]
+  itemLinkCountByType: NamedCount[]
+  entityCountByType: NamedCount[]
+}
+
+export type GraphEntityView = {
+  id: number
+  memoryId: string
+  userId: string
+  agentId: string | null
+  entityKey: string
+  displayName: string | null
+  entityType: string | null
+  metadata: JsonRecord | null
+  createdAt: string
+  updatedAt: string
+}
+
+export type GraphAliasView = {
+  id: number
+  memoryId: string
+  userId: string
+  agentId: string | null
+  entityKey: string
+  entityType: string | null
+  normalizedAlias: string
+  evidenceCount: number | null
+  metadata: JsonRecord | null
+  createdAt: string
+  updatedAt: string
+}
+
+export type GraphMentionView = {
+  id: number
+  memoryId: string
+  userId: string
+  agentId: string | null
+  itemId: number
+  entityKey: string
+  confidence: number | null
+  metadata: JsonRecord | null
+  createdAt: string
+  updatedAt: string
+}
+
+export type GraphItemLinkView = {
+  id: number
+  memoryId: string
+  userId: string
+  agentId: string | null
+  sourceItemId: number
+  targetItemId: number
+  linkType: string | null
+  relationCode: string | null
+  evidenceSource: string | null
+  strength: number | null
+  metadata: JsonRecord | null
+  createdAt: string
+  updatedAt: string
+}
+
+export type GraphCooccurrenceView = {
+  id: number
+  memoryId: string
+  userId: string
+  agentId: string | null
+  leftEntityKey: string
+  rightEntityKey: string
+  cooccurrenceCount: number | null
+  metadata: JsonRecord | null
+  createdAt: string
+  updatedAt: string
+}
+
+export type GraphBatchView = {
+  id: number
+  memoryId: string
+  userId: string
+  agentId: string | null
+  extractionBatchId: string
+  state: 'PENDING' | 'COMMITTED' | 'REPAIR_REQUIRED' | string
+  errorMessage: string | null
+  retryPromotionSupported: boolean | null
+  createdAt: string
+  updatedAt: string
+}
+
+export type GraphEntityDetailView = {
+  entity: GraphEntityView
+  aliases: GraphAliasView[]
+  mentionCount: number
+  topMentionedItemIds: number[]
+  topCooccurrences: GraphCooccurrenceView[]
+  entityOverlapItemLinkCount: number
+}
+
+export type MemoryOptionItemView = {
+  key: string
+  value: unknown
+  description: string | null
+  type: 'string' | 'boolean' | 'integer' | 'double' | string
+  defaultValue: unknown
+  constraints: JsonRecord | null
+}
+
+export type MemoryOptionsGetResponse = {
+  version: number
+  config: Record<string, MemoryOptionItemView[]>
+}
+
+export type RetrievalTraceStageView = {
+  stage: string
+  tier: string | null
+  method: string | null
+  status: string | null
+  inputCount: number | null
+  candidateCount: number | null
+  resultCount: number | null
+  degraded: boolean
+  skipped: boolean
+  startedAt: string | null
+  durationMillis: number | null
+  attributes: JsonRecord | null
+  candidates: unknown[]
+}
+
+export type RetrievalTraceView = {
+  traceId: string
+  startedAt: string | null
+  completedAt: string | null
+  truncated: boolean
+  stages: RetrievalTraceStageView[]
+  merge: {
+    inputCount: number
+    outputCount: number
+    deduplicatedCount: number
+    sourceCount: number
+    status: string | null
+  } | null
+  finalResults: {
+    strategy: string
+    status: string | null
+    itemCount: number
+    insightCount: number
+    rawDataCount: number
+    evidenceCount: number
+  } | null
+}
+
+export type RetrieveMemoryResponse = {
+  items: Array<{
+    id: string
+    text: string
+    vectorScore: number
+    finalScore: number
+    occurredAt: string | null
+  }>
+  insights: Array<{
+    id: string
+    text: string
+    tier: string | null
+  }>
+  rawData: Array<{
+    rawDataId: string
+    caption: string | null
+    maxScore: number
+    itemIds: string[]
+  }>
+  evidences: string[]
+  strategy: string
+  query: string
+  trace: RetrievalTraceView | null
+}
+
+export type BatchDeleteResult = {
+  deletedCount: number
+  affectedMemoryIds: string[]
+}
+
+export type AdminUpdateResult = {
+  updatedCount: number
+  affectedMemoryIds: string[]
+}
+
+export type RawDataDeleteResult = {
+  deletedRawDataCount: number
+  deletedItemCount: number
+  affectedMemoryIds: string[]
+  insightCleanupRequired: boolean
+}
+
+export type AdminGraphEntityDeleteResult = {
+  deletedCount: number
+  affectedMemoryIds: string[]
+  deletedAliases: number
+  deletedMentions: number
+  deletedCooccurrences: number
+  possiblyStaleEntityOverlapLinks: number
+}
+
+export type ItemDeleteRequest = { itemIds: number[] }
+export type RawDataDeleteRequest = { rawDataIds: string[] }
+export type InsightDeleteRequest = { insightIds: number[] }
+export type AdminIdsRequest = { ids: number[] }
+export type InsightBufferBuiltUpdateRequest = {
+  ids: number[]
+  built: boolean
+}
+export type InsightBufferGroupUpdateRequest = {
+  ids: number[]
+  groupName?: string | null
+}
+export type GraphEntityDeleteRequest = {
+  memoryId: string
+  entityKeys: string[]
+}
+export type GraphIdsRequest = { ids: number[] }
+export type MemoryOptionsPutRequest = {
+  expectedVersion: number
+  config: Record<string, MemoryOptionItemView[]>
+}
+export type RetrieveMemoryRequest = {
+  userId: string
+  agentId: string
+  query: string
+  strategy: 'SIMPLE' | 'DEEP' | string
+  trace?: boolean
+}
diff --git a/memind-ui/src/hooks/use-mobile.tsx b/memind-ui/src/hooks/use-mobile.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/hooks/use-mobile.tsx
@@ -0,0 +1,16 @@
+import * as React from 'react'
+
+const MOBILE_BREAKPOINT = 768
+const MOBILE_QUERY = `(max-width: ${MOBILE_BREAKPOINT - 1}px)`
+
+export function useIsMobile() {
+  return React.useSyncExternalStore(
+    (callback) => {
+      const mql = window.matchMedia(MOBILE_QUERY)
+      mql.addEventListener('change', callback)
+      return () => mql.removeEventListener('change', callback)
+    },
+    () => window.matchMedia(MOBILE_QUERY).matches,
+    () => false
+  )
+}
diff --git a/memind-ui/src/hooks/use-table-url-state.ts b/memind-ui/src/hooks/use-table-url-state.ts
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/hooks/use-table-url-state.ts
@@ -0,0 +1,219 @@
+import { useMemo, useState } from 'react'
+import type {
+  ColumnFiltersState,
+  OnChangeFn,
+  PaginationState,
+} from '@tanstack/react-table'
+
+type SearchRecord = Record<string, unknown>
+
+export type NavigateFn = (opts: {
+  search:
+    | true
+    | SearchRecord
+    | ((prev: SearchRecord) => Partial<SearchRecord> | SearchRecord)
+  replace?: boolean
+}) => void
+
+type UseTableUrlStateParams = {
+  search: SearchRecord
+  navigate: NavigateFn
+  pagination?: {
+    pageKey?: string
+    pageSizeKey?: string
+    defaultPage?: number
+    defaultPageSize?: number
+  }
+  globalFilter?: {
+    enabled?: boolean
+    key?: string
+    trim?: boolean
+  }
+  columnFilters?: Array<
+    | {
+        columnId: string
+        searchKey: string
+        type?: 'string'
+        // Optional transformers for custom types
+        serialize?: (value: unknown) => unknown
+        deserialize?: (value: unknown) => unknown
+      }
+    | {
+        columnId: string
+        searchKey: string
+        type: 'array'
+        serialize?: (value: unknown) => unknown
+        deserialize?: (value: unknown) => unknown
+      }
+  >
+}
+
+type UseTableUrlStateReturn = {
+  // Global filter
+  globalFilter?: string
+  onGlobalFilterChange?: OnChangeFn<string>
+  // Column filters
+  columnFilters: ColumnFiltersState
+  onColumnFiltersChange: OnChangeFn<ColumnFiltersState>
+  // Pagination
+  pagination: PaginationState
+  onPaginationChange: OnChangeFn<PaginationState>
+  // Helpers
+  ensurePageInRange: (
+    pageCount: number,
+    opts?: { resetTo?: 'first' | 'last' }
+  ) => void
+}
+
+export function useTableUrlState(
+  params: UseTableUrlStateParams
+): UseTableUrlStateReturn {
+  const {
+    search,
+    navigate,
+    pagination: paginationCfg,
+    globalFilter: globalFilterCfg,
+    columnFilters: columnFiltersCfg = [],
+  } = params
+
+  const pageKey = paginationCfg?.pageKey ?? ('pageNo' as string)
+  const pageSizeKey = paginationCfg?.pageSizeKey ?? ('pageSize' as string)
+  const defaultPage = paginationCfg?.defaultPage ?? 1
+  const defaultPageSize = paginationCfg?.defaultPageSize ?? 10
+
+  const globalFilterKey = globalFilterCfg?.key ?? ('filter' as string)
+  const globalFilterEnabled = globalFilterCfg?.enabled ?? true
+  const trimGlobal = globalFilterCfg?.trim ?? true
+
+  // Build initial column filters from the current search params
+  const initialColumnFilters: ColumnFiltersState = useMemo(() => {
+    const collected: ColumnFiltersState = []
+    for (const cfg of columnFiltersCfg) {
+      const raw = (search as SearchRecord)[cfg.searchKey]
+      const deserialize = cfg.deserialize ?? ((v: unknown) => v)
+      if (cfg.type === 'string') {
+        const value = (deserialize(raw) as string) ?? ''
+        if (typeof value === 'string' && value.trim() !== '') {
+          collected.push({ id: cfg.columnId, value })
+        }
+      } else {
+        // default to array type
+        const value = (deserialize(raw) as unknown[]) ?? []
+        if (Array.isArray(value) && value.length > 0) {
+          collected.push({ id: cfg.columnId, value })
+        }
+      }
+    }
+    return collected
+  }, [columnFiltersCfg, search])
+
+  const [columnFilters, setColumnFilters] =
+    useState<ColumnFiltersState>(initialColumnFilters)
+
+  const pagination: PaginationState = useMemo(() => {
+    const rawPage = (search as SearchRecord)[pageKey]
+    const rawPageSize = (search as SearchRecord)[pageSizeKey]
+    const pageNum = typeof rawPage === 'number' ? rawPage : defaultPage
+    const pageSizeNum =
+      typeof rawPageSize === 'number' ? rawPageSize : defaultPageSize
+    return { pageIndex: Math.max(0, pageNum - 1), pageSize: pageSizeNum }
+  }, [search, pageKey, pageSizeKey, defaultPage, defaultPageSize])
+
+  const onPaginationChange: OnChangeFn<PaginationState> = (updater) => {
+    const next = typeof updater === 'function' ? updater(pagination) : updater
+    const nextPage = next.pageIndex + 1
+    const nextPageSize = next.pageSize
+    navigate({
+      search: (prev) => ({
+        ...(prev as SearchRecord),
+        [pageKey]: nextPage <= defaultPage ? undefined : nextPage,
+        [pageSizeKey]:
+          nextPageSize === defaultPageSize ? undefined : nextPageSize,
+      }),
+    })
+  }
+
+  const [globalFilter, setGlobalFilter] = useState<string | undefined>(() => {
+    if (!globalFilterEnabled) return undefined
+    const raw = (search as SearchRecord)[globalFilterKey]
+    return typeof raw === 'string' ? raw : ''
+  })
+
+  const onGlobalFilterChange: OnChangeFn<string> | undefined =
+    globalFilterEnabled
+      ? (updater) => {
+          const next =
+            typeof updater === 'function'
+              ? updater(globalFilter ?? '')
+              : updater
+          const value = trimGlobal ? next.trim() : next
+          setGlobalFilter(value)
+          navigate({
+            search: (prev) => ({
+              ...(prev as SearchRecord),
+              [pageKey]: undefined,
+              [globalFilterKey]: value ? value : undefined,
+            }),
+          })
+        }
+      : undefined
+
+  const onColumnFiltersChange: OnChangeFn<ColumnFiltersState> = (updater) => {
+    const next =
+      typeof updater === 'function' ? updater(columnFilters) : updater
+    setColumnFilters(next)
+
+    const patch: Record<string, unknown> = {}
+
+    for (const cfg of columnFiltersCfg) {
+      const found = next.find((f) => f.id === cfg.columnId)
+      const serialize = cfg.serialize ?? ((v: unknown) => v)
+      if (cfg.type === 'string') {
+        const value =
+          typeof found?.value === 'string' ? (found.value as string) : ''
+        patch[cfg.searchKey] =
+          value.trim() !== '' ? serialize(value) : undefined
+      } else {
+        const value = Array.isArray(found?.value)
+          ? (found!.value as unknown[])
+          : []
+        patch[cfg.searchKey] = value.length > 0 ? serialize(value) : undefined
+      }
+    }
+
+    navigate({
+      search: (prev) => ({
+        ...(prev as SearchRecord),
+        [pageKey]: undefined,
+        ...patch,
+      }),
+    })
+  }
+
+  const ensurePageInRange = (
+    pageCount: number,
+    opts: { resetTo?: 'first' | 'last' } = { resetTo: 'first' }
+  ) => {
+    const currentPage = (search as SearchRecord)[pageKey]
+    const pageNum = typeof currentPage === 'number' ? currentPage : defaultPage
+    if (pageCount > 0 && pageNum > pageCount) {
+      navigate({
+        replace: true,
+        search: (prev) => ({
+          ...(prev as SearchRecord),
+          [pageKey]: opts.resetTo === 'last' ? pageCount : undefined,
+        }),
+      })
+    }
+  }
+
+  return {
+    globalFilter: globalFilterEnabled ? (globalFilter ?? '') : undefined,
+    onGlobalFilterChange,
+    columnFilters,
+    onColumnFiltersChange,
+    pagination,
+    onPaginationChange,
+    ensurePageInRange,
+  }
+}
diff --git a/memind-ui/src/lib/api-client.ts b/memind-ui/src/lib/api-client.ts
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/lib/api-client.ts
@@ -0,0 +1,164 @@
+type ApiResult<T> = {
+  code: string
+  message?: string
+  data?: T
+  timestamp: string
+  traceId?: string
+}
+
+export type PageResult<T> = {
+  total: number
+  list: T[]
+  current: number
+}
+
+export type ApiError = {
+  status?: number
+  code?: string
+  message: string
+  traceId?: string
+  details?: unknown
+}
+
+const SUCCESS_CODES = new Set(['success', '200'])
+
+type HttpMethod = 'GET' | 'POST' | 'PATCH' | 'PUT' | 'DELETE'
+
+export async function apiGet<T>(
+  path: string,
+  query?: Record<string, unknown>
+): Promise<T> {
+  return apiRequest<T>('GET', path, undefined, query)
+}
+
+export async function apiPost<T>(
+  path: string,
+  body?: unknown,
+  query?: Record<string, unknown>
+): Promise<T> {
+  return apiRequest<T>('POST', path, body, query)
+}
+
+export async function apiPatch<T>(
+  path: string,
+  body?: unknown,
+  query?: Record<string, unknown>
+): Promise<T> {
+  return apiRequest<T>('PATCH', path, body, query)
+}
+
+export async function apiPut<T>(
+  path: string,
+  body?: unknown,
+  query?: Record<string, unknown>
+): Promise<T> {
+  return apiRequest<T>('PUT', path, body, query)
+}
+
+export async function apiDelete<T>(
+  path: string,
+  body?: unknown,
+  query?: Record<string, unknown>
+): Promise<T> {
+  return apiRequest<T>('DELETE', path, body, query)
+}
+
+function buildUrl(path: string, query?: Record<string, unknown>) {
+  const params = new URLSearchParams()
+
+  for (const [key, value] of Object.entries(query ?? {})) {
+    appendQueryValue(params, key, value)
+  }
+
+  const serialized = params.toString()
+  return serialized ? `${path}?${serialized}` : path
+}
+
+function appendQueryValue(
+  params: URLSearchParams,
+  key: string,
+  value: unknown
+) {
+  if (value === undefined || value === null || value === '') return
+  if (Array.isArray(value)) {
+    for (const item of value) {
+      appendQueryValue(params, key, item)
+    }
+    return
+  }
+
+  if (value instanceof Date) {
+    params.append(key, value.toISOString())
+    return
+  }
+
+  params.append(key, String(value))
+}
+
+async function apiRequest<T>(
+  method: HttpMethod,
+  path: string,
+  body?: unknown,
+  query?: Record<string, unknown>
+): Promise<T> {
+  if (import.meta.env.VITE_MEMIND_MOCK_API === 'true') {
+    const { mockApiRequest } = await import('./mock-api')
+    return mockApiRequest<T>(method, path, body, query)
+  }
+
+  const init: RequestInit = {
+    method,
+    headers: {
+      accept: 'application/json',
+      ...(body === undefined ? {} : { 'content-type': 'application/json' }),
+    },
+    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
+  }
+
+  let response: Response
+  try {
+    response = await fetch(buildUrl(path, query), init)
+  } catch (error) {
+    throw toNetworkError(error)
+  }
+
+  const payload = await readJson<ApiResult<T>>(response)
+
+  if (!payload || !response.ok || !SUCCESS_CODES.has(payload.code)) {
+    throw toApiError(response, payload)
+  }
+
+  return payload.data as T
+}
+
+async function readJson<T>(response: Response): Promise<T | undefined> {
+  const text = await response.text()
+  if (!text) return undefined
+
+  try {
+    return JSON.parse(text) as T
+  } catch {
+    return undefined
+  }
+}
+
+function toApiError<T>(
+  response: Response,
+  payload: ApiResult<T> | undefined
+): ApiError {
+  return {
+    status: response.status,
+    code: payload?.code,
+    message: payload?.message || response.statusText || 'Request failed',
+    traceId: payload?.traceId,
+    details: payload?.data,
+  }
+}
+
+function toNetworkError(error: unknown): ApiError {
+  if (error instanceof Error) {
+    return { message: error.message }
+  }
+
+  return { message: 'Network request failed', details: error }
+}
diff --git a/memind-ui/src/lib/cookies.ts b/memind-ui/src/lib/cookies.ts
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/lib/cookies.ts
@@ -0,0 +1,43 @@
+/**
+ * Cookie utility functions using manual document.cookie approach
+ * Replaces js-cookie dependency for better consistency
+ */
+
+const DEFAULT_MAX_AGE = 60 * 60 * 24 * 7 // 7 days
+
+/**
+ * Get a cookie value by name
+ */
+export function getCookie(name: string): string | undefined {
+  if (typeof document === 'undefined') return undefined
+
+  const value = `; ${document.cookie}`
+  const parts = value.split(`; ${name}=`)
+  if (parts.length === 2) {
+    const cookieValue = parts.pop()?.split(';').shift()
+    return cookieValue
+  }
+  return undefined
+}
+
+/**
+ * Set a cookie with name, value, and optional max age
+ */
+export function setCookie(
+  name: string,
+  value: string,
+  maxAge: number = DEFAULT_MAX_AGE
+): void {
+  if (typeof document === 'undefined') return
+
+  document.cookie = `${name}=${value}; path=/; max-age=${maxAge}`
+}
+
+/**
+ * Remove a cookie by setting its max age to 0
+ */
+export function removeCookie(name: string): void {
+  if (typeof document === 'undefined') return
+
+  document.cookie = `${name}=; path=/; max-age=0`
+}
diff --git a/memind-ui/src/lib/format.ts b/memind-ui/src/lib/format.ts
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/lib/format.ts
@@ -0,0 +1,46 @@
+const DASH = '-'
+
+const dateTimeFormatter = new Intl.DateTimeFormat('en-US', {
+  year: 'numeric',
+  month: '2-digit',
+  day: '2-digit',
+  hour: '2-digit',
+  minute: '2-digit',
+  second: '2-digit',
+})
+
+const numberFormatter = new Intl.NumberFormat('en-US')
+
+export function formatDateTime(value: string | null | undefined): string {
+  if (!value) return DASH
+
+  const date = new Date(value)
+  if (Number.isNaN(date.getTime())) return DASH
+
+  return dateTimeFormatter.format(date)
+}
+
+export function formatNumber(value: number | null | undefined): string {
+  if (value === null || value === undefined) return DASH
+  return numberFormatter.format(value)
+}
+
+export function compactJson(value: unknown): string {
+  try {
+    const json = JSON.stringify(value)
+    return json === undefined ? String(value) : json
+  } catch {
+    return String(value)
+  }
+}
+
+export function truncateText(
+  value: string | null | undefined,
+  maxLength: number
+): string {
+  if (!value) return DASH
+  if (value.length <= maxLength) return value
+  if (maxLength <= 3) return '.'.repeat(Math.max(0, maxLength))
+
+  return `${value.slice(0, maxLength - 3)}...`
+}
diff --git a/memind-ui/src/lib/handle-server-error.ts b/memind-ui/src/lib/handle-server-error.ts
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/lib/handle-server-error.ts
@@ -0,0 +1,29 @@
+import { AxiosError } from 'axios'
+import { toast } from 'sonner'
+
+export function handleServerError(error: unknown) {
+  if (import.meta.env.DEV) {
+    // eslint-disable-next-line no-console
+    console.log(error)
+  }
+
+  let errMsg = 'Something went wrong!'
+
+  if (
+    error &&
+    typeof error === 'object' &&
+    'status' in error &&
+    Number(error.status) === 204
+  ) {
+    errMsg = 'No content.'
+  }
+
+  if (error instanceof AxiosError) {
+    const title = error.response?.data?.title
+    if (typeof title === 'string' && title.length > 0) {
+      errMsg = title
+    }
+  }
+
+  toast.error(errMsg)
+}
diff --git a/memind-ui/src/lib/memory-scope.ts b/memind-ui/src/lib/memory-scope.ts
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/lib/memory-scope.ts
@@ -0,0 +1,62 @@
+type ParsedMemoryScope = {
+  memoryId: string
+  userId: string
+  agentId: string
+  hasUserId: boolean
+  hasAgentId: boolean
+}
+
+class MemoryScopeError extends Error {
+  constructor(message: string) {
+    super(message)
+    this.name = 'MemoryScopeError'
+  }
+}
+
+export function parseMemoryScope(value: string): ParsedMemoryScope {
+  const memoryId = value.trim()
+  const colonIndex = memoryId.indexOf(':')
+  const userId = colonIndex === -1 ? memoryId : memoryId.slice(0, colonIndex)
+  const agentId = colonIndex === -1 ? '' : memoryId.slice(colonIndex + 1)
+
+  return {
+    memoryId,
+    userId,
+    agentId,
+    hasUserId: userId !== '',
+    hasAgentId: agentId !== '',
+  }
+}
+
+export function toMemoryIdQuery(value: string): { memoryId?: string } {
+  const scope = parseMemoryScope(value)
+  return scope.memoryId ? { memoryId: scope.memoryId } : {}
+}
+
+export function toUserAgentQuery(
+  value: string
+): { userId?: string; agentId?: string } {
+  const scope = parseMemoryScope(value)
+  if (!scope.hasUserId) return {}
+
+  return {
+    userId: scope.userId,
+    ...(scope.hasAgentId ? { agentId: scope.agentId } : {}),
+  }
+}
+
+export function requireUserScope(value: string): ParsedMemoryScope {
+  const scope = parseMemoryScope(value)
+  if (!scope.hasUserId) {
+    throw new MemoryScopeError('Memory scope must include userId')
+  }
+  return scope
+}
+
+export function requireRetrieveScope(value: string): ParsedMemoryScope {
+  const scope = parseMemoryScope(value)
+  if (!scope.hasUserId || !scope.hasAgentId) {
+    throw new MemoryScopeError('Memory scope must include userId and agentId')
+  }
+  return scope
+}
diff --git a/memind-ui/src/lib/mock-api.ts b/memind-ui/src/lib/mock-api.ts
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/lib/mock-api.ts
@@ -0,0 +1,1118 @@
+import type { PageResult } from '@/lib/api-client'
+import type {
+  AdminDashboardView,
+  AdminGraphEntityDeleteResult,
+  AdminInsightView,
+  AdminItemMemoryThreadView,
+  AdminItemView,
+  AdminMemoryThreadItemView,
+  AdminMemoryThreadStatusView,
+  AdminMemoryThreadView,
+  AdminRawDataView,
+  AdminUpdateResult,
+  BatchDeleteResult,
+  ConversationBufferView,
+  GraphAliasView,
+  GraphBatchView,
+  GraphCooccurrenceView,
+  GraphEntityDetailView,
+  GraphEntityView,
+  GraphItemLinkView,
+  GraphMentionView,
+  InsightBufferGroupView,
+  InsightBufferView,
+  ItemGraphSummaryView,
+  MemoryOptionsGetResponse,
+  MemoryOptionsPutRequest,
+  RawDataDeleteResult,
+  RetrieveMemoryRequest,
+  RetrieveMemoryResponse,
+} from '@/features/types'
+
+type MockMethod = 'GET' | 'POST' | 'PATCH' | 'PUT' | 'DELETE'
+
+const now = '2026-05-06T06:00:00Z'
+const memoryIds = ['alice:agent-a', 'alice:agent-b', 'bob:agent-a']
+const longText =
+  'This is deliberately long mock content used to validate table wrapping, drawer spacing, JSON sections, and dense operational review workflows in Memind UI.'
+
+export async function mockApiRequest<T>(
+  method: MockMethod,
+  path: string,
+  body?: unknown,
+  query?: Record<string, unknown>
+): Promise<T> {
+  await delay(80)
+  const data = routeMockRequest(method, path, body, normalizeQuery(query))
+  return clone(data) as T
+}
+
+function routeMockRequest(
+  method: MockMethod,
+  path: string,
+  body: unknown,
+  query: URLSearchParams
+) {
+  if (method === 'GET' && path === '/open/v1/health') {
+    return { status: 'UP', service: 'memind-server mock' }
+  }
+  if (method === 'GET' && path === '/admin/v1/dashboard')
+    return dashboard(query)
+  if (method === 'GET' && path === '/admin/v1/buffers/conversations') {
+    return page(filterConversationBuffers(query), query)
+  }
+  if (method === 'GET' && path.startsWith('/admin/v1/buffers/conversations/')) {
+    return findById(conversationBuffers, numberFromPath(path))
+  }
+  if (
+    method === 'PATCH' &&
+    path === '/admin/v1/buffers/conversations/extracted'
+  ) {
+    return updateResult(idsFromBody(body).length)
+  }
+  if (method === 'DELETE' && path === '/admin/v1/buffers/conversations') {
+    return deleteResult(idsFromBody(body).length)
+  }
+  if (method === 'GET' && path === '/admin/v1/buffers/insights') {
+    return page(filterInsightBuffers(query), query)
+  }
+  if (method === 'GET' && path === '/admin/v1/buffers/insights/groups') {
+    return filterByMemoryId(insightBufferGroups, query)
+  }
+  if (method === 'PATCH' && path.startsWith('/admin/v1/buffers/insights/')) {
+    return updateResult(idsFromBody(body).length)
+  }
+  if (method === 'DELETE' && path === '/admin/v1/buffers/insights') {
+    return deleteResult(idsFromBody(body).length)
+  }
+  if (method === 'GET' && path === '/admin/v1/raw-data') {
+    return page(filterRawData(query), query)
+  }
+  if (method === 'GET' && path.startsWith('/admin/v1/raw-data/')) {
+    return findByKey(
+      rawData,
+      'rawDataId',
+      decodeURIComponent(lastPathPart(path))
+    )
+  }
+  if (method === 'DELETE' && path === '/admin/v1/raw-data') {
+    const count = rawDataIdsFromBody(body).length
+    return {
+      deletedRawDataCount: count,
+      deletedItemCount: count * 2,
+      affectedMemoryIds: memoryIds,
+      insightCleanupRequired: true,
+    } satisfies RawDataDeleteResult
+  }
+  if (method === 'GET' && path === '/admin/v1/items') {
+    return page(filterItems(query), query)
+  }
+  if (method === 'GET' && /^\/admin\/v1\/items\/\d+$/.test(path)) {
+    return findByKey(items, 'itemId', numberFromPath(path))
+  }
+  if (
+    method === 'GET' &&
+    path.endsWith('/memory-threads') &&
+    path.startsWith('/admin/v1/items/')
+  ) {
+    requireUserId(query)
+    return itemThreadLinks(numberFromPath(path))
+  }
+  if (method === 'DELETE' && path === '/admin/v1/items') {
+    return deleteResult(itemIdsFromBody(body).length)
+  }
+  if (method === 'GET' && path === '/admin/v1/insights') {
+    return page(filterInsights(query), query)
+  }
+  if (method === 'GET' && /^\/admin\/v1\/insights\/\d+$/.test(path)) {
+    return findByKey(insights, 'insightId', numberFromPath(path))
+  }
+  if (method === 'DELETE' && path === '/admin/v1/insights') {
+    return deleteResult(insightIdsFromBody(body).length)
+  }
+  if (method === 'GET' && path === '/admin/v1/item-graph/summary') {
+    return itemGraphSummary(query)
+  }
+  if (method === 'GET' && path === '/admin/v1/item-graph/entities') {
+    return page(filterGraphEntities(query), query)
+  }
+  if (method === 'GET' && path.startsWith('/admin/v1/item-graph/entities/')) {
+    return graphEntityDetail(numberFromPath(path))
+  }
+  if (method === 'DELETE' && path === '/admin/v1/item-graph/entities') {
+    const entityKeys =
+      (body as { entityKeys?: string[] } | undefined)?.entityKeys ?? []
+    return {
+      deletedCount: entityKeys.length,
+      affectedMemoryIds: memoryIds,
+      deletedAliases: entityKeys.length * 2,
+      deletedMentions: entityKeys.length * 3,
+      deletedCooccurrences: entityKeys.length,
+      possiblyStaleEntityOverlapLinks: entityKeys.length,
+    } satisfies AdminGraphEntityDeleteResult
+  }
+  if (method === 'GET' && path === '/admin/v1/item-graph/aliases') {
+    return page(filterGraphAliases(query), query)
+  }
+  if (method === 'GET' && path === '/admin/v1/item-graph/mentions') {
+    return page(filterGraphMentions(query), query)
+  }
+  if (method === 'GET' && path === '/admin/v1/item-graph/item-links') {
+    return page(filterGraphItemLinks(query), query)
+  }
+  if (method === 'GET' && path === '/admin/v1/item-graph/cooccurrences') {
+    return page(filterGraphCooccurrences(query), query)
+  }
+  if (method === 'GET' && path === '/admin/v1/item-graph/batches') {
+    return page(filterGraphBatches(query), query)
+  }
+  if (method === 'DELETE' && path.startsWith('/admin/v1/item-graph/')) {
+    return deleteResult(idsFromBody(body).length)
+  }
+  if (method === 'GET' && path === '/admin/v1/memory-threads') {
+    return page(filterMemoryThreads(query), query)
+  }
+  if (method === 'GET' && path === '/admin/v1/memory-threads/status') {
+    requireUserId(query)
+    return threadStatus
+  }
+  if (method === 'POST' && path === '/admin/v1/memory-threads/rebuild') {
+    requireUserId(query)
+    return 12
+  }
+  if (
+    method === 'GET' &&
+    path.endsWith('/items') &&
+    path.startsWith('/admin/v1/memory-threads/')
+  ) {
+    requireUserId(query)
+    return threadMemberships(decodeURIComponent(pathPartFromEnd(path, 1)))
+  }
+  if (method === 'GET' && path.startsWith('/admin/v1/memory-threads/')) {
+    requireUserId(query)
+    return findByKey(
+      memoryThreads,
+      'threadKey',
+      decodeURIComponent(lastPathPart(path))
+    )
+  }
+  if (method === 'GET' && path === '/admin/v1/config/memory-options')
+    return memoryOptions
+  if (method === 'PUT' && path === '/admin/v1/config/memory-options') {
+    const request = body as MemoryOptionsPutRequest
+    return { version: request.expectedVersion + 1, config: request.config }
+  }
+  if (method === 'POST' && path === '/open/v1/memory/retrieve') {
+    return retrieveResult(body as RetrieveMemoryRequest)
+  }
+
+  throw {
+    status: 404,
+    code: 'mock_not_found',
+    message: `No mock handler for ${method} ${path}`,
+  }
+}
+
+const conversationBuffers: ConversationBufferView[] = Array.from(
+  { length: 16 },
+  (_, index) => {
+    const id = index + 1
+    const scope = scopeAt(index)
+    return {
+      id,
+      sessionId: `session-${Math.ceil(id / 3)}`,
+      userId: scope.userId,
+      agentId: scope.agentId,
+      memoryId: scope.memoryId,
+      role: id % 2 === 0 ? 'assistant' : 'user',
+      content: `${longText} Conversation buffer ${id} includes enough text to inspect preview truncation and full drawer content.`,
+      userName: id % 3 === 0 ? 'Bob' : 'Alice',
+      sourceClient: id % 4 === 0 ? null : 'claude-code',
+      timestamp: time(id),
+      extracted: id % 4 === 0,
+      createdAt: time(id + 1),
+      updatedAt: time(id + 2),
+    }
+  }
+)
+
+const insightBuffers: InsightBufferView[] = Array.from(
+  { length: 18 },
+  (_, index) => {
+    const id = index + 11
+    const scope = scopeAt(index)
+    return {
+      id,
+      userId: scope.userId,
+      agentId: scope.agentId,
+      memoryId: scope.memoryId,
+      insightTypeName: ['preference', 'constraint', 'workflow'][index % 3],
+      itemId: 1001 + index,
+      groupName:
+        index % 4 === 0 ? null : ['dev-style', 'tooling', 'handoff'][index % 3],
+      built: index % 5 === 0,
+      createdAt: time(index + 3),
+      updatedAt: time(index + 4),
+    }
+  }
+)
+
+const insightBufferGroups: InsightBufferGroupView[] = [
+  {
+    memoryId: 'alice:agent-a',
+    insightTypeName: 'preference',
+    groupName: 'dev-style',
+    total: 8,
+    unbuilt: 5,
+    built: 3,
+  },
+  {
+    memoryId: 'alice:agent-a',
+    insightTypeName: 'workflow',
+    groupName: 'handoff',
+    total: 4,
+    unbuilt: 4,
+    built: 0,
+  },
+  {
+    memoryId: 'bob:agent-a',
+    insightTypeName: 'constraint',
+    groupName: null,
+    total: 3,
+    unbuilt: 3,
+    built: 0,
+  },
+]
+
+const rawData: AdminRawDataView[] = Array.from({ length: 15 }, (_, index) => {
+  const id = `raw-${String(index + 1).padStart(3, '0')}`
+  const scope = scopeAt(index)
+  return {
+    rawDataId: id,
+    userId: scope.userId,
+    agentId: scope.agentId,
+    memoryId: scope.memoryId,
+    type: ['CONVERSATION', 'DOCUMENT', 'TOOL_CALL'][index % 3],
+    sourceClient: ['claude-code', 'sdk', 'web'][index % 3],
+    contentId: `content-${index + 1}`,
+    segment: {
+      index,
+      role: index % 2 === 0 ? 'user' : 'assistant',
+      text: longText,
+    },
+    caption: `${longText} Raw data caption ${index + 1}.`,
+    captionVectorId: `vector-raw-${index + 1}`,
+    metadata: {
+      channel: 'mock',
+      tags: ['ui-review', index % 2 === 0 ? 'long' : 'short'],
+    },
+    startTime: time(index + 1),
+    endTime: time(index + 2),
+    createdAt: time(index + 3),
+    updatedAt: time(index + 4),
+  }
+})
+
+const items: AdminItemView[] = Array.from({ length: 22 }, (_, index) => {
+  const itemId = 1001 + index
+  const category = ['profile', 'event', 'directive', 'playbook'][index % 4]
+  const scopeIdentity = scopeAt(index)
+  return {
+    itemId,
+    userId: scopeIdentity.userId,
+    agentId: scopeIdentity.agentId,
+    memoryId: scopeIdentity.memoryId,
+    content: `${longText} Memory item ${itemId} captures ${category} context and includes a long paragraph for detail drawer review.`,
+    scope:
+      category === 'directive' || category === 'playbook' ? 'AGENT' : 'USER',
+    category,
+    vectorId: `vector-item-${itemId}`,
+    rawDataId: rawData[index % rawData.length].rawDataId,
+    contentHash: `hash-${itemId}`,
+    occurredAt: index % 5 === 0 ? null : time(index),
+    observedAt: time(index + 1),
+    metadata: {
+      confidence: 0.75 + (index % 5) / 20,
+      labels: ['mock', category],
+      nested: { review: true },
+    },
+    type: ['fact', 'preference', 'workflow'][index % 3],
+    rawDataType: rawData[index % rawData.length].type,
+    sourceClient: rawData[index % rawData.length].sourceClient,
+    createdAt: time(index + 2),
+    updatedAt: time(index + 3),
+  }
+})
+
+const insights: AdminInsightView[] = Array.from({ length: 14 }, (_, index) => {
+  const insightId = 2001 + index
+  const scopeIdentity = scopeAt(index)
+  return {
+    insightId,
+    userId: scopeIdentity.userId,
+    agentId: scopeIdentity.agentId,
+    memoryId: scopeIdentity.memoryId,
+    type: ['preference', 'constraint', 'workflow'][index % 3],
+    scope: index % 2 === 0 ? 'USER' : 'AGENT',
+    name: `Insight ${insightId} ${['Preferences', 'Constraints', 'Workflow'][index % 3]}`,
+    categories: [['profile'], ['directive'], ['playbook', 'resolution']][
+      index % 3
+    ],
+    content: `${longText} Insight ${insightId} summarizes repeated evidence and reasoning links.`,
+    points: [
+      { text: 'Observed in multiple conversations', confidence: 0.91 },
+      { text: 'Useful for future retrieval', confidence: 0.83 },
+    ],
+    groupName:
+      index % 4 === 0 ? null : ['dev-style', 'tooling', 'handoff'][index % 3],
+    lastReasonedAt: time(index + 5),
+    summaryEmbedding: [0.12, 0.34, 0.56],
+    tier: index % 2 === 0 ? 'LONG_TERM' : 'SESSION',
+    parentInsightId: index > 2 ? 2001 : null,
+    childInsightIds: index < 3 ? [2004 + index] : [],
+    version: 3 + index,
+    createdAt: time(index + 2),
+    updatedAt: time(index + 6),
+  }
+})
+
+const graphEntities: GraphEntityView[] = Array.from(
+  { length: 13 },
+  (_, index) => {
+    const scope = scopeAt(index)
+    return {
+      id: 3001 + index,
+      memoryId: scope.memoryId,
+      userId: scope.userId,
+      agentId: scope.agentId,
+      entityKey: ['react-query', 'vite-proxy', 'memory-scope', 'item-graph'][
+        index % 4
+      ],
+      displayName: ['React Query', 'Vite proxy', 'Memory scope', 'Item graph'][
+        index % 4
+      ],
+      entityType: ['TECH', 'CONCEPT', 'PROJECT'][index % 3],
+      metadata: { aliases: index + 1, mock: true },
+      createdAt: time(index + 2),
+      updatedAt: time(index + 3),
+    }
+  }
+)
+
+const graphAliases: GraphAliasView[] = graphEntities.flatMap(
+  (entity, index) => [
+    {
+      id: 4001 + index * 2,
+      memoryId: entity.memoryId,
+      userId: entity.userId,
+      agentId: entity.agentId,
+      entityKey: entity.entityKey,
+      entityType: entity.entityType,
+      normalizedAlias: entity.displayName?.toLowerCase() ?? entity.entityKey,
+      evidenceCount: 2 + index,
+      metadata: { source: 'mock' },
+      createdAt: entity.createdAt,
+      updatedAt: entity.updatedAt,
+    },
+  ]
+)
+
+const graphMentions: GraphMentionView[] = Array.from(
+  { length: 16 },
+  (_, index) => {
+    const item = items[index % items.length]
+    const entity = pickForMemory(graphEntities, item.memoryId, index)
+    return {
+      id: 5001 + index,
+      memoryId: item.memoryId,
+      userId: item.userId,
+      agentId: item.agentId,
+      itemId: item.itemId,
+      entityKey: entity.entityKey,
+      confidence: 0.6 + (index % 4) / 10,
+      metadata: { sentence: index + 1 },
+      createdAt: time(index + 1),
+      updatedAt: time(index + 2),
+    }
+  }
+)
+
+const graphItemLinks: GraphItemLinkView[] = Array.from(
+  { length: 15 },
+  (_, index) => {
+    const sourceItem = items[index % items.length]
+    const targetItem = pickForMemory(items, sourceItem.memoryId, index + 1)
+    return {
+      id: 6001 + index,
+      memoryId: sourceItem.memoryId,
+      userId: sourceItem.userId,
+      agentId: sourceItem.agentId,
+      sourceItemId: sourceItem.itemId,
+      targetItemId: targetItem.itemId,
+      linkType: ['SEMANTIC', 'TEMPORAL', 'CAUSAL'][index % 3],
+      relationCode: ['supports', 'follows', 'explains'][index % 3],
+      evidenceSource: ['llm', 'temporal-window', 'graph-repair'][index % 3],
+      strength: 0.55 + (index % 5) / 10,
+      metadata: { batch: `batch-${index % 4}` },
+      createdAt: time(index + 1),
+      updatedAt: time(index + 2),
+    }
+  }
+)
+
+const graphCooccurrences: GraphCooccurrenceView[] = Array.from(
+  { length: 11 },
+  (_, index) => {
+    const scope = scopeAt(index)
+    const leftEntity = pickForMemory(graphEntities, scope.memoryId, index)
+    const rightEntity = pickForMemory(graphEntities, scope.memoryId, index + 1)
+    return {
+      id: 7001 + index,
+      memoryId: scope.memoryId,
+      userId: scope.userId,
+      agentId: scope.agentId,
+      leftEntityKey: leftEntity.entityKey,
+      rightEntityKey: rightEntity.entityKey,
+      cooccurrenceCount: 2 + index,
+      metadata: { window: 'conversation' },
+      createdAt: time(index + 1),
+      updatedAt: time(index + 2),
+    }
+  }
+)
+
+const graphBatches: GraphBatchView[] = Array.from({ length: 9 }, (_, index) => {
+  const scope = scopeAt(index)
+  return {
+    id: 8001 + index,
+    memoryId: scope.memoryId,
+    userId: scope.userId,
+    agentId: scope.agentId,
+    extractionBatchId: `batch-${20260500 + index}`,
+    state: ['PENDING', 'COMMITTED', 'REPAIR_REQUIRED'][index % 3],
+    errorMessage:
+      index % 3 === 2 ? 'Alias receipt mismatch detected in mock batch.' : null,
+    retryPromotionSupported: index % 3 === 2,
+    createdAt: time(index + 1),
+    updatedAt: time(index + 2),
+  }
+})
+
+const memoryThreads: AdminMemoryThreadView[] = Array.from(
+  { length: 12 },
+  (_, index) => {
+    const threadKey = `thread-${index + 1}`
+    const scope = scopeAt(index)
+    return {
+      userId: scope.userId,
+      agentId: scope.agentId,
+      memoryId: scope.memoryId,
+      threadKey,
+      threadType: ['TOPIC', 'TASK', 'DECISION'][index % 3],
+      anchorKind: ['entity', 'insight', 'item'][index % 3],
+      anchorKey: graphEntities[index % graphEntities.length].entityKey,
+      displayLabel: `Thread ${index + 1} review`,
+      lifecycleStatus: ['ACTIVE', 'DORMANT', 'CLOSED'][index % 3],
+      objectState: ['OPEN', 'STALE', 'FINALIZED'][index % 3],
+      headline: `${longText} Thread headline ${index + 1}.`,
+      snapshotJson: {
+        summary: 'Mock thread snapshot',
+        importantItemIds: [items[index].itemId, items[index + 1].itemId],
+      },
+      snapshotVersion: 2 + index,
+      openedAt: time(index + 1),
+      lastEventAt: time(index + 3),
+      lastMeaningfulUpdateAt: time(index + 4),
+      closedAt: index % 3 === 2 ? time(index + 5) : null,
+      eventCount: 3 + index,
+      memberCount: 2 + (index % 4),
+      createdAt: time(index + 1),
+      updatedAt: time(index + 5),
+    }
+  }
+)
+
+const threadStatus: AdminMemoryThreadStatusView = {
+  projectionState: 'READY',
+  pendingCount: 6,
+  failedCount: 1,
+  rebuildInProgress: false,
+  lastProcessedItemId: 1019,
+  materializationPolicyVersion: 'thread-core-v1',
+  updatedAt: now,
+  invalidationReason: 'mock data includes one pending repair item',
+}
+
+const memoryOptions: MemoryOptionsGetResponse = {
+  version: 12,
+  config: {
+    'extraction.common': [
+      option('defaultScope', 'USER', 'string', {
+        allowedValues: ['USER', 'AGENT'],
+      }),
+      option('timeout', 'PT10M', 'string', { format: 'iso-8601-duration' }),
+      option('language', 'English', 'string'),
+    ],
+    'extraction.rawdata': [
+      option('conversationStrategy', 'LLM', 'string', {
+        enum: ['FIXED', 'LLM'],
+      }),
+      option('messagesPerChunk', 12, 'integer', { min: 1, max: 64 }),
+      option('vectorBatchSize', 32, 'integer', { min: 1, max: 256 }),
+    ],
+    'extraction.item.graph': [
+      option('enabled', true, 'boolean'),
+      option('maxEntitiesPerItem', 8, 'integer', { min: 1, max: 32 }),
+      option('minimumMentionConfidence', 0.72, 'double', { min: 0, max: 1 }),
+    ],
+    'retrieval.simple.graphAssist': [
+      option('enabled', true, 'boolean'),
+      option('maxSeedItems', 12, 'integer', { min: 1, max: 100 }),
+      option('mode', 'BALANCED', 'string', {
+        enum: ['OFF', 'BALANCED', 'AGGRESSIVE'],
+      }),
+    ],
+    'memory.thread.materialization': [
+      option('enabled', true, 'boolean'),
+      option('policyVersion', 'thread-core-v1', 'string'),
+      option(
+        'veryLongOptionKeyUsedToValidateHorizontalWrappingAndFormLayoutWithDenseOperationalConfigurationPanels',
+        'very-long-value-that-should-wrap-cleanly-without-forcing-horizontal-page-overflow-in-settings-review-mode',
+        'string'
+      ),
+    ],
+  },
+}
+
+function dashboard(query: URLSearchParams): AdminDashboardView {
+  const days = Math.min(numberParam(query, 'days', 7), 30)
+  const scopedRawData = filterByMemoryId(rawData, query)
+  const scopedItems = filterByMemoryId(items, query)
+  const scopedInsights = filterByMemoryId(insights, query)
+  const scopedThreads = filterByMemoryId(memoryThreads, query)
+  const scopedEntities = filterByMemoryId(graphEntities, query)
+  const scopedItemLinks = filterByMemoryId(graphItemLinks, query)
+  const scopedConversationBuffers = filterByMemoryId(conversationBuffers, query)
+  const scopedInsightBuffers = filterByMemoryId(insightBuffers, query)
+  const scopedGraphBatches = filterByMemoryId(graphBatches, query)
+
+  return {
+    totals: {
+      rawData: scopedRawData.length,
+      items: scopedItems.length,
+      insights: scopedInsights.length,
+      memoryThreads: scopedThreads.length,
+      graphEntities: scopedEntities.length,
+      itemLinks: scopedItemLinks.length,
+    },
+    backlog: {
+      conversationPending: scopedConversationBuffers.filter(
+        (row) => !row.extracted
+      ).length,
+      insightUnbuilt: scopedInsightBuffers.filter((row) => !row.built).length,
+      insightUngrouped: scopedInsightBuffers.filter(
+        (row) => !row.built && !row.groupName
+      ).length,
+      threadOutboxPending: 7,
+      threadOutboxFailed: 1,
+      graphBatchRepairRequired: scopedGraphBatches.filter(
+        (row) => row.state === 'REPAIR_REQUIRED'
+      ).length,
+    },
+    activity: {
+      days,
+      rawDataCreated: daily(days, 5),
+      itemsCreated: daily(days, 8),
+      insightsCreated: daily(days, 3),
+    },
+    breakdown: {
+      sourceClients: countBy(scopedRawData, 'sourceClient'),
+      rawDataTypes: countBy(scopedRawData, 'type'),
+      itemTypes: countBy(scopedItems, 'type'),
+      insightTypes: countBy(scopedInsights, 'type'),
+      graphLinkTypes: countBy(scopedItemLinks, 'linkType'),
+    },
+    healthSignals: {
+      graphEnabled: true,
+      retrievalGraphAssistEnabled: true,
+      threadProjectionStates: [
+        { state: 'READY', count: 2 },
+        { state: 'REBUILD_REQUIRED', count: 1 },
+        { state: 'FAILED', count: 1 },
+      ],
+    },
+  }
+}
+
+function retrieveResult(
+  request: RetrieveMemoryRequest
+): RetrieveMemoryResponse {
+  return {
+    items: items.slice(0, 5).map((item, index) => ({
+      id: String(item.itemId),
+      text: `${item.content} Query: ${request.query}`,
+      vectorScore: 0.82 - index * 0.04,
+      finalScore: 0.91 - index * 0.03,
+      occurredAt: item.occurredAt,
+    })),
+    insights: insights.slice(0, 4).map((insight) => ({
+      id: String(insight.insightId),
+      text: insight.content,
+      tier: insight.tier,
+    })),
+    rawData: rawData.slice(0, 3).map((row) => ({
+      rawDataId: row.rawDataId,
+      caption: row.caption,
+      maxScore: 0.88,
+      itemIds: [String(items[0].itemId), String(items[1].itemId)],
+    })),
+    evidences: [
+      'Mock evidence: matching memory item content and entity mentions.',
+      'Mock evidence: insight group has repeated support across conversations.',
+    ],
+    strategy: request.strategy,
+    query: request.query,
+    trace: request.trace
+      ? {
+          traceId: 'mock-trace-001',
+          startedAt: time(1),
+          completedAt: time(2),
+          truncated: false,
+          stages: [
+            traceStage('keyword', 'SIMPLE', 24, 8),
+            traceStage('graph-expand', 'GRAPH', 8, 11),
+            traceStage('rerank', 'RERANK', 11, 5),
+          ],
+          merge: {
+            inputCount: 19,
+            outputCount: 8,
+            deduplicatedCount: 4,
+            sourceCount: 3,
+            status: 'OK',
+          },
+          finalResults: {
+            strategy: request.strategy,
+            status: 'OK',
+            itemCount: 5,
+            insightCount: 4,
+            rawDataCount: 3,
+            evidenceCount: 2,
+          },
+        }
+      : null,
+  }
+}
+
+function itemGraphSummary(query: URLSearchParams): ItemGraphSummaryView {
+  const entities = filterByMemoryId(graphEntities, query)
+  const aliases = filterByMemoryId(graphAliases, query)
+  const mentions = filterByMemoryId(graphMentions, query)
+  const itemLinks = filterByMemoryId(graphItemLinks, query)
+  const cooccurrences = filterByMemoryId(graphCooccurrences, query)
+  const batches = filterByMemoryId(graphBatches, query)
+
+  return {
+    entityCount: entities.length,
+    aliasCount: aliases.length,
+    mentionCount: mentions.length,
+    itemLinkCount: itemLinks.length,
+    cooccurrenceCount: cooccurrences.length,
+    graphBatchCountByState: countBy(batches, 'state'),
+    itemLinkCountByType: countBy(itemLinks, 'linkType'),
+    entityCountByType: countBy(entities, 'entityType'),
+  }
+}
+
+function graphEntityDetail(id: number): GraphEntityDetailView {
+  const entity = findByKey(graphEntities, 'id', id)
+  return {
+    entity,
+    aliases: graphAliases.filter(
+      (alias) => alias.entityKey === entity.entityKey
+    ),
+    mentionCount: graphMentions.filter(
+      (mention) => mention.entityKey === entity.entityKey
+    ).length,
+    topMentionedItemIds: items.slice(0, 5).map((item) => item.itemId),
+    topCooccurrences: graphCooccurrences.slice(0, 4),
+    entityOverlapItemLinkCount: 3,
+  }
+}
+
+function threadMemberships(threadKey: string): AdminMemoryThreadItemView[] {
+  const thread = findByKey(memoryThreads, 'threadKey', threadKey)
+  return items.slice(0, 4).map((item, index) => ({
+    userId: thread.userId,
+    agentId: thread.agentId,
+    memoryId: thread.memoryId,
+    threadKey,
+    itemId: item.itemId,
+    role: index === 0 ? 'anchor' : 'supporting',
+    primary: index === 0,
+    relevanceWeight: 1 - index * 0.15,
+    createdAt: time(index + 2),
+    updatedAt: time(index + 3),
+  }))
+}
+
+function itemThreadLinks(itemId: number): AdminItemMemoryThreadView[] {
+  return memoryThreads.slice(0, 3).map((thread, index) => ({
+    ...thread,
+    itemId,
+    role: index === 0 ? 'anchor' : 'supporting',
+    primary: index === 0,
+    relevanceWeight: 0.95 - index * 0.2,
+  }))
+}
+
+function filterConversationBuffers(query: URLSearchParams) {
+  const state = query.get('state') ?? 'pending'
+  const sessionId = query.get('sessionId')
+  return filterByMemoryId(conversationBuffers, query).filter((row) => {
+    if (state === 'pending' && row.extracted) return false
+    if (state === 'extracted' && !row.extracted) return false
+    if (sessionId && row.sessionId !== sessionId) return false
+    return true
+  })
+}
+
+function filterInsightBuffers(query: URLSearchParams) {
+  const state = query.get('state') ?? 'unbuilt'
+  const insightTypeName = query.get('insightTypeName')
+  return filterByMemoryId(insightBuffers, query).filter((row) => {
+    if (insightTypeName && row.insightTypeName !== insightTypeName) return false
+    if (state === 'all') return true
+    if (state === 'built') return row.built
+    if (state === 'ungrouped') return !row.built && !row.groupName
+    if (state === 'grouped') return !row.built && Boolean(row.groupName)
+    return !row.built
+  })
+}
+
+function filterRawData(query: URLSearchParams) {
+  const startTimeFrom = query.get('startTimeFrom')
+  const startTimeTo = query.get('startTimeTo')
+  return filterByUserAgent(rawData, query).filter((row) => {
+    if (startTimeFrom && (!row.startTime || row.startTime < startTimeFrom)) {
+      return false
+    }
+    if (startTimeTo && (!row.startTime || row.startTime > startTimeTo)) {
+      return false
+    }
+    return true
+  })
+}
+
+function filterItems(query: URLSearchParams) {
+  const scope = query.get('scope')
+  const category = query.get('category')
+  const type = query.get('type')
+  const rawDataId = query.get('rawDataId')
+  return filterByUserAgent(items, query).filter((row) => {
+    if (scope && row.scope !== scope) return false
+    if (category && row.category !== category) return false
+    if (type && row.type !== type) return false
+    if (rawDataId && row.rawDataId !== rawDataId) return false
+    return true
+  })
+}
+
+function filterInsights(query: URLSearchParams) {
+  const scope = query.get('scope')
+  const type = query.get('type')
+  const tier = query.get('tier')
+  return filterByUserAgent(insights, query).filter((row) => {
+    if (scope && row.scope !== scope) return false
+    if (type && row.type !== type) return false
+    if (tier && row.tier !== tier) return false
+    return true
+  })
+}
+
+function filterGraphEntities(query: URLSearchParams) {
+  const entityType = query.get('entityType')
+  const q = query.get('q')?.toLowerCase()
+  return filterByMemoryId(graphEntities, query).filter((row) => {
+    if (entityType && row.entityType !== entityType) return false
+    if (
+      q &&
+      ![row.entityKey, row.displayName, row.entityType].some((value) =>
+        value?.toLowerCase().includes(q)
+      )
+    ) {
+      return false
+    }
+    return true
+  })
+}
+
+function filterGraphAliases(query: URLSearchParams) {
+  const entityKey = query.get('entityKey')
+  const q = query.get('q')?.toLowerCase()
+  return filterByMemoryId(graphAliases, query).filter((row) => {
+    if (entityKey && row.entityKey !== entityKey) return false
+    if (
+      q &&
+      ![row.entityKey, row.normalizedAlias, row.entityType].some((value) =>
+        value?.toLowerCase().includes(q)
+      )
+    ) {
+      return false
+    }
+    return true
+  })
+}
+
+function filterGraphMentions(query: URLSearchParams) {
+  const itemId = query.get('itemId')
+  const entityKey = query.get('entityKey')
+  return filterByMemoryId(graphMentions, query).filter((row) => {
+    if (itemId && row.itemId !== Number(itemId)) return false
+    if (entityKey && row.entityKey !== entityKey) return false
+    return true
+  })
+}
+
+function filterGraphItemLinks(query: URLSearchParams) {
+  const itemId = query.get('itemId')
+  const linkType = query.get('linkType')
+  const evidenceSource = query.get('evidenceSource')
+  return filterByMemoryId(graphItemLinks, query).filter((row) => {
+    if (
+      itemId &&
+      row.sourceItemId !== Number(itemId) &&
+      row.targetItemId !== Number(itemId)
+    ) {
+      return false
+    }
+    if (linkType && row.linkType !== linkType) return false
+    if (evidenceSource && row.evidenceSource !== evidenceSource) return false
+    return true
+  })
+}
+
+function filterGraphCooccurrences(query: URLSearchParams) {
+  const entityKey = query.get('entityKey')
+  return filterByMemoryId(graphCooccurrences, query).filter((row) => {
+    if (
+      entityKey &&
+      row.leftEntityKey !== entityKey &&
+      row.rightEntityKey !== entityKey
+    ) {
+      return false
+    }
+    return true
+  })
+}
+
+function filterGraphBatches(query: URLSearchParams) {
+  const state = query.get('state')
+  return filterByMemoryId(graphBatches, query).filter(
+    (row) => !state || row.state === state
+  )
+}
+
+function filterMemoryThreads(query: URLSearchParams) {
+  const status = query.get('status')
+  return filterByUserAgent(memoryThreads, query).filter(
+    (row) => !status || row.lifecycleStatus === status
+  )
+}
+
+function filterByMemoryId<T extends { memoryId: string }>(
+  rows: T[],
+  query: URLSearchParams
+) {
+  const memoryId = query.get('memoryId')
+  return memoryId ? rows.filter((row) => row.memoryId === memoryId) : rows
+}
+
+function requireUserId(query: URLSearchParams) {
+  if (query.get('userId')) return
+  throw {
+    status: 400,
+    code: 'validation_failed',
+    message: 'userId is required',
+  }
+}
+
+function filterByUserAgent<
+  T extends { userId: string; agentId: string | null },
+>(rows: T[], query: URLSearchParams) {
+  const userId = query.get('userId')
+  const agentId = query.get('agentId')
+  return rows.filter((row) => {
+    if (userId && row.userId !== userId) return false
+    if (agentId && row.agentId !== agentId) return false
+    return true
+  })
+}
+
+function page<T>(rows: T[], query: URLSearchParams): PageResult<T> {
+  const pageNo = numberParam(query, 'pageNo', 1)
+  const pageSize = numberParam(query, 'pageSize', 10)
+  const start = (pageNo - 1) * pageSize
+  return {
+    total: rows.length,
+    current: pageNo,
+    list: rows.slice(start, start + pageSize),
+  }
+}
+
+function option(
+  key: string,
+  value: unknown,
+  type: string,
+  constraints: Record<string, unknown> | null = null
+) {
+  return {
+    key,
+    value,
+    description: `Mock ${key} option for UI review.`,
+    type,
+    defaultValue: value,
+    constraints,
+  }
+}
+
+function findById<T extends { id: number }>(rows: T[], id: number) {
+  const row = rows.find((item) => item.id === id)
+  if (!row) throw notFound(`Mock row id ${id} was not found`)
+  return row
+}
+
+function findByKey<T, K extends keyof T>(rows: T[], key: K, value: T[K]) {
+  const row = rows.find((item) => item[key] === value)
+  if (!row)
+    throw notFound(`Mock row ${String(key)}=${String(value)} was not found`)
+  return row
+}
+
+function normalizeQuery(query?: Record<string, unknown>) {
+  const params = new URLSearchParams()
+  for (const [key, value] of Object.entries(query ?? {})) {
+    if (value !== undefined && value !== null && value !== '')
+      params.set(key, String(value))
+  }
+  return params
+}
+
+function numberParam(params: URLSearchParams, key: string, fallback: number) {
+  const parsed = Number(params.get(key))
+  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback
+}
+
+function numberFromPath(path: string) {
+  const matches = path.match(/\d+/g)
+  return Number(matches ? matches[matches.length - 1] : 0)
+}
+
+function lastPathPart(path: string) {
+  return pathPartFromEnd(path, 0)
+}
+
+function pathPartFromEnd(path: string, offset: number) {
+  const parts = path.split('/')
+  return parts[parts.length - 1 - offset] ?? ''
+}
+
+function scopeAt(index: number) {
+  const memoryId = memoryIds[index % memoryIds.length]
+  const [userId, agentId = null] = memoryId.split(':')
+  return { memoryId, userId, agentId }
+}
+
+function pickForMemory<T extends { memoryId: string }>(
+  rows: T[],
+  memoryId: string,
+  index: number
+) {
+  const scopedRows = rows.filter((row) => row.memoryId === memoryId)
+  const pool = scopedRows.length ? scopedRows : rows
+  return pool[index % pool.length]
+}
+
+function idsFromBody(body: unknown) {
+  return (body as { ids?: number[] } | undefined)?.ids ?? []
+}
+
+function itemIdsFromBody(body: unknown) {
+  return (body as { itemIds?: number[] } | undefined)?.itemIds ?? []
+}
+
+function insightIdsFromBody(body: unknown) {
+  return (body as { insightIds?: number[] } | undefined)?.insightIds ?? []
+}
+
+function rawDataIdsFromBody(body: unknown) {
+  return (body as { rawDataIds?: string[] } | undefined)?.rawDataIds ?? []
+}
+
+function updateResult(count: number): AdminUpdateResult {
+  return { updatedCount: count, affectedMemoryIds: memoryIds }
+}
+
+function deleteResult(count: number): BatchDeleteResult {
+  return { deletedCount: count, affectedMemoryIds: memoryIds }
+}
+
+function time(offsetHours: number) {
+  return new Date(Date.UTC(2026, 4, 6, 6 + offsetHours)).toISOString()
+}
+
+function daily(days: number, base: number) {
+  return Array.from({ length: days }, (_, index) => ({
+    date: `2026-04-${String(24 + index).padStart(2, '0')}`,
+    count: base + index,
+  }))
+}
+
+function countBy<T, K extends keyof T>(rows: T[], key: K) {
+  const countMap = new Map<string, number>()
+  for (const row of rows) {
+    const value = row[key]
+    const name =
+      value === null || value === undefined ? 'UNKNOWN' : String(value)
+    countMap.set(name, (countMap.get(name) ?? 0) + 1)
+  }
+  return Array.from(countMap, ([name, count]) => ({ name, count }))
+}
+
+function traceStage(
+  stage: string,
+  tier: string,
+  inputCount: number,
+  resultCount: number
+) {
+  return {
+    stage,
+    tier,
+    method: 'mock',
+    status: 'OK',
+    inputCount,
+    candidateCount: inputCount + 3,
+    resultCount,
+    degraded: false,
+    skipped: false,
+    startedAt: time(1),
+    durationMillis: 120 + resultCount * 10,
+    attributes: { mock: true, stage },
+    candidates: [{ id: `${stage}-candidate`, score: 0.87 }],
+  }
+}
+
+function clone<T>(value: T): T {
+  return JSON.parse(JSON.stringify(value)) as T
+}
+
+function delay(ms: number) {
+  return new Promise((resolve) => globalThis.setTimeout(resolve, ms))
+}
+
+function notFound(message: string) {
+  return {
+    status: 404,
+    code: 'mock_not_found',
+    message,
+  }
+}
diff --git a/memind-ui/src/lib/query-client.ts b/memind-ui/src/lib/query-client.ts
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/lib/query-client.ts
@@ -0,0 +1,19 @@
+import { QueryCache, QueryClient } from '@tanstack/react-query'
+import { handleServerError } from '@/lib/handle-server-error'
+
+export const queryClient = new QueryClient({
+  defaultOptions: {
+    queries: {
+      retry: false,
+      refetchOnWindowFocus: false,
+      staleTime: 30 * 1000,
+    },
+    mutations: {
+      retry: false,
+      onError: handleServerError,
+    },
+  },
+  queryCache: new QueryCache({
+    onError: handleServerError,
+  }),
+})
diff --git a/memind-ui/src/lib/utils.ts b/memind-ui/src/lib/utils.ts
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/lib/utils.ts
@@ -0,0 +1,56 @@
+import { type ClassValue, clsx } from 'clsx'
+import { twMerge } from 'tailwind-merge'
+
+export function cn(...inputs: ClassValue[]) {
+  return twMerge(clsx(inputs))
+}
+
+/**
+ * Generates page numbers for pagination with ellipsis
+ * @param currentPage - Current page number (1-based)
+ * @param totalPages - Total number of pages
+ * @returns Array of page numbers and ellipsis strings
+ *
+ * Examples:
+ * - Small dataset (≤5 pages): [1, 2, 3, 4, 5]
+ * - Near beginning: [1, 2, 3, 4, '...', 10]
+ * - In middle: [1, '...', 4, 5, 6, '...', 10]
+ * - Near end: [1, '...', 7, 8, 9, 10]
+ */
+export function getPageNumbers(currentPage: number, totalPages: number) {
+  const maxVisiblePages = 5 // Maximum number of page buttons to show
+  const rangeWithDots = []
+
+  if (totalPages <= maxVisiblePages) {
+    // If total pages is 5 or less, show all pages
+    for (let i = 1; i <= totalPages; i++) {
+      rangeWithDots.push(i)
+    }
+  } else {
+    // Always show first page
+    rangeWithDots.push(1)
+
+    if (currentPage <= 3) {
+      // Near the beginning: [1] [2] [3] [4] ... [10]
+      for (let i = 2; i <= 4; i++) {
+        rangeWithDots.push(i)
+      }
+      rangeWithDots.push('...', totalPages)
+    } else if (currentPage >= totalPages - 2) {
+      // Near the end: [1] ... [7] [8] [9] [10]
+      rangeWithDots.push('...')
+      for (let i = totalPages - 3; i <= totalPages; i++) {
+        rangeWithDots.push(i)
+      }
+    } else {
+      // In the middle: [1] ... [4] [5] [6] ... [10]
+      rangeWithDots.push('...')
+      for (let i = currentPage - 1; i <= currentPage + 1; i++) {
+        rangeWithDots.push(i)
+      }
+      rangeWithDots.push('...', totalPages)
+    }
+  }
+
+  return rangeWithDots
+}
diff --git a/memind-ui/src/main.tsx b/memind-ui/src/main.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/main.tsx
@@ -0,0 +1,43 @@
+import { StrictMode } from 'react'
+import ReactDOM from 'react-dom/client'
+import { QueryClientProvider } from '@tanstack/react-query'
+import { RouterProvider, createRouter } from '@tanstack/react-router'
+import { queryClient } from '@/lib/query-client'
+import { DirectionProvider } from './context/direction-provider'
+import { ThemeProvider } from './context/theme-provider'
+// Generated Routes
+import { routeTree } from './routeTree.gen'
+// Styles
+import './styles/index.css'
+
+// Create a new router instance
+const router = createRouter({
+  routeTree,
+  context: { queryClient },
+  defaultPreload: 'intent',
+  defaultPreloadStaleTime: 0,
+})
+
+// Register the router instance for type safety
+declare module '@tanstack/react-router' {
+  interface Register {
+    router: typeof router
+  }
+}
+
+// Render the app
+const rootElement = document.getElementById('root')!
+if (!rootElement.innerHTML) {
+  const root = ReactDOM.createRoot(rootElement)
+  root.render(
+    <StrictMode>
+      <QueryClientProvider client={queryClient}>
+        <ThemeProvider>
+          <DirectionProvider>
+            <RouterProvider router={router} />
+          </DirectionProvider>
+        </ThemeProvider>
+      </QueryClientProvider>
+    </StrictMode>
+  )
+}
diff --git a/memind-ui/src/routeTree.gen.ts b/memind-ui/src/routeTree.gen.ts
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/routeTree.gen.ts
@@ -0,0 +1,320 @@
+/* eslint-disable */
+
+// @ts-nocheck
+
+// noinspection JSUnusedGlobalSymbols
+
+// This file was automatically generated by TanStack Router.
+// You should NOT make any changes in this file as it will be overwritten.
+// Additionally, you should also exclude this file from your linter and/or formatter to prevent it from being checked or modified.
+
+import { Route as rootRouteImport } from './routes/__root'
+import { Route as AppRouteRouteImport } from './routes/_app/route'
+import { Route as AppIndexRouteImport } from './routes/_app/index'
+import { Route as AppRetrieveRouteImport } from './routes/_app/retrieve'
+import { Route as AppRawDataRouteImport } from './routes/_app/raw-data'
+import { Route as AppMemoryThreadsRouteImport } from './routes/_app/memory-threads'
+import { Route as AppItemsRouteImport } from './routes/_app/items'
+import { Route as AppItemGraphRouteImport } from './routes/_app/item-graph'
+import { Route as AppInsightsRouteImport } from './routes/_app/insights'
+import { Route as AppConfigRouteImport } from './routes/_app/config'
+import { Route as AppBuffersRouteImport } from './routes/_app/buffers'
+import { Route as errors503RouteImport } from './routes/(errors)/503'
+import { Route as errors500RouteImport } from './routes/(errors)/500'
+import { Route as errors404RouteImport } from './routes/(errors)/404'
+
+const AppRouteRoute = AppRouteRouteImport.update({
+  id: '/_app',
+  getParentRoute: () => rootRouteImport,
+} as any)
+const AppIndexRoute = AppIndexRouteImport.update({
+  id: '/',
+  path: '/',
+  getParentRoute: () => AppRouteRoute,
+} as any)
+const AppRetrieveRoute = AppRetrieveRouteImport.update({
+  id: '/retrieve',
+  path: '/retrieve',
+  getParentRoute: () => AppRouteRoute,
+} as any)
+const AppRawDataRoute = AppRawDataRouteImport.update({
+  id: '/raw-data',
+  path: '/raw-data',
+  getParentRoute: () => AppRouteRoute,
+} as any)
+const AppMemoryThreadsRoute = AppMemoryThreadsRouteImport.update({
+  id: '/memory-threads',
+  path: '/memory-threads',
+  getParentRoute: () => AppRouteRoute,
+} as any)
+const AppItemsRoute = AppItemsRouteImport.update({
+  id: '/items',
+  path: '/items',
+  getParentRoute: () => AppRouteRoute,
+} as any)
+const AppItemGraphRoute = AppItemGraphRouteImport.update({
+  id: '/item-graph',
+  path: '/item-graph',
+  getParentRoute: () => AppRouteRoute,
+} as any)
+const AppInsightsRoute = AppInsightsRouteImport.update({
+  id: '/insights',
+  path: '/insights',
+  getParentRoute: () => AppRouteRoute,
+} as any)
+const AppConfigRoute = AppConfigRouteImport.update({
+  id: '/config',
+  path: '/config',
+  getParentRoute: () => AppRouteRoute,
+} as any)
+const AppBuffersRoute = AppBuffersRouteImport.update({
+  id: '/buffers',
+  path: '/buffers',
+  getParentRoute: () => AppRouteRoute,
+} as any)
+const errors503Route = errors503RouteImport.update({
+  id: '/(errors)/503',
+  path: '/503',
+  getParentRoute: () => rootRouteImport,
+} as any)
+const errors500Route = errors500RouteImport.update({
+  id: '/(errors)/500',
+  path: '/500',
+  getParentRoute: () => rootRouteImport,
+} as any)
+const errors404Route = errors404RouteImport.update({
+  id: '/(errors)/404',
+  path: '/404',
+  getParentRoute: () => rootRouteImport,
+} as any)
+
+export interface FileRoutesByFullPath {
+  '/': typeof AppIndexRoute
+  '/404': typeof errors404Route
+  '/500': typeof errors500Route
+  '/503': typeof errors503Route
+  '/buffers': typeof AppBuffersRoute
+  '/config': typeof AppConfigRoute
+  '/insights': typeof AppInsightsRoute
+  '/item-graph': typeof AppItemGraphRoute
+  '/items': typeof AppItemsRoute
+  '/memory-threads': typeof AppMemoryThreadsRoute
+  '/raw-data': typeof AppRawDataRoute
+  '/retrieve': typeof AppRetrieveRoute
+}
+export interface FileRoutesByTo {
+  '/404': typeof errors404Route
+  '/500': typeof errors500Route
+  '/503': typeof errors503Route
+  '/buffers': typeof AppBuffersRoute
+  '/config': typeof AppConfigRoute
+  '/insights': typeof AppInsightsRoute
+  '/item-graph': typeof AppItemGraphRoute
+  '/items': typeof AppItemsRoute
+  '/memory-threads': typeof AppMemoryThreadsRoute
+  '/raw-data': typeof AppRawDataRoute
+  '/retrieve': typeof AppRetrieveRoute
+  '/': typeof AppIndexRoute
+}
+export interface FileRoutesById {
+  __root__: typeof rootRouteImport
+  '/_app': typeof AppRouteRouteWithChildren
+  '/(errors)/404': typeof errors404Route
+  '/(errors)/500': typeof errors500Route
+  '/(errors)/503': typeof errors503Route
+  '/_app/buffers': typeof AppBuffersRoute
+  '/_app/config': typeof AppConfigRoute
+  '/_app/insights': typeof AppInsightsRoute
+  '/_app/item-graph': typeof AppItemGraphRoute
+  '/_app/items': typeof AppItemsRoute
+  '/_app/memory-threads': typeof AppMemoryThreadsRoute
+  '/_app/raw-data': typeof AppRawDataRoute
+  '/_app/retrieve': typeof AppRetrieveRoute
+  '/_app/': typeof AppIndexRoute
+}
+export interface FileRouteTypes {
+  fileRoutesByFullPath: FileRoutesByFullPath
+  fullPaths:
+    | '/'
+    | '/404'
+    | '/500'
+    | '/503'
+    | '/buffers'
+    | '/config'
+    | '/insights'
+    | '/item-graph'
+    | '/items'
+    | '/memory-threads'
+    | '/raw-data'
+    | '/retrieve'
+  fileRoutesByTo: FileRoutesByTo
+  to:
+    | '/404'
+    | '/500'
+    | '/503'
+    | '/buffers'
+    | '/config'
+    | '/insights'
+    | '/item-graph'
+    | '/items'
+    | '/memory-threads'
+    | '/raw-data'
+    | '/retrieve'
+    | '/'
+  id:
+    | '__root__'
+    | '/_app'
+    | '/(errors)/404'
+    | '/(errors)/500'
+    | '/(errors)/503'
+    | '/_app/buffers'
+    | '/_app/config'
+    | '/_app/insights'
+    | '/_app/item-graph'
+    | '/_app/items'
+    | '/_app/memory-threads'
+    | '/_app/raw-data'
+    | '/_app/retrieve'
+    | '/_app/'
+  fileRoutesById: FileRoutesById
+}
+export interface RootRouteChildren {
+  AppRouteRoute: typeof AppRouteRouteWithChildren
+  errors404Route: typeof errors404Route
+  errors500Route: typeof errors500Route
+  errors503Route: typeof errors503Route
+}
+
+declare module '@tanstack/react-router' {
+  interface FileRoutesByPath {
+    '/_app': {
+      id: '/_app'
+      path: ''
+      fullPath: '/'
+      preLoaderRoute: typeof AppRouteRouteImport
+      parentRoute: typeof rootRouteImport
+    }
+    '/_app/': {
+      id: '/_app/'
+      path: '/'
+      fullPath: '/'
+      preLoaderRoute: typeof AppIndexRouteImport
+      parentRoute: typeof AppRouteRoute
+    }
+    '/_app/retrieve': {
+      id: '/_app/retrieve'
+      path: '/retrieve'
+      fullPath: '/retrieve'
+      preLoaderRoute: typeof AppRetrieveRouteImport
+      parentRoute: typeof AppRouteRoute
+    }
+    '/_app/raw-data': {
+      id: '/_app/raw-data'
+      path: '/raw-data'
+      fullPath: '/raw-data'
+      preLoaderRoute: typeof AppRawDataRouteImport
+      parentRoute: typeof AppRouteRoute
+    }
+    '/_app/memory-threads': {
+      id: '/_app/memory-threads'
+      path: '/memory-threads'
+      fullPath: '/memory-threads'
+      preLoaderRoute: typeof AppMemoryThreadsRouteImport
+      parentRoute: typeof AppRouteRoute
+    }
+    '/_app/items': {
+      id: '/_app/items'
+      path: '/items'
+      fullPath: '/items'
+      preLoaderRoute: typeof AppItemsRouteImport
+      parentRoute: typeof AppRouteRoute
+    }
+    '/_app/item-graph': {
+      id: '/_app/item-graph'
+      path: '/item-graph'
+      fullPath: '/item-graph'
+      preLoaderRoute: typeof AppItemGraphRouteImport
+      parentRoute: typeof AppRouteRoute
+    }
+    '/_app/insights': {
+      id: '/_app/insights'
+      path: '/insights'
+      fullPath: '/insights'
+      preLoaderRoute: typeof AppInsightsRouteImport
+      parentRoute: typeof AppRouteRoute
+    }
+    '/_app/config': {
+      id: '/_app/config'
+      path: '/config'
+      fullPath: '/config'
+      preLoaderRoute: typeof AppConfigRouteImport
+      parentRoute: typeof AppRouteRoute
+    }
+    '/_app/buffers': {
+      id: '/_app/buffers'
+      path: '/buffers'
+      fullPath: '/buffers'
+      preLoaderRoute: typeof AppBuffersRouteImport
+      parentRoute: typeof AppRouteRoute
+    }
+    '/(errors)/503': {
+      id: '/(errors)/503'
+      path: '/503'
+      fullPath: '/503'
+      preLoaderRoute: typeof errors503RouteImport
+      parentRoute: typeof rootRouteImport
+    }
+    '/(errors)/500': {
+      id: '/(errors)/500'
+      path: '/500'
+      fullPath: '/500'
+      preLoaderRoute: typeof errors500RouteImport
+      parentRoute: typeof rootRouteImport
+    }
+    '/(errors)/404': {
+      id: '/(errors)/404'
+      path: '/404'
+      fullPath: '/404'
+      preLoaderRoute: typeof errors404RouteImport
+      parentRoute: typeof rootRouteImport
+    }
+  }
+}
+
+interface AppRouteRouteChildren {
+  AppBuffersRoute: typeof AppBuffersRoute
+  AppConfigRoute: typeof AppConfigRoute
+  AppInsightsRoute: typeof AppInsightsRoute
+  AppItemGraphRoute: typeof AppItemGraphRoute
+  AppItemsRoute: typeof AppItemsRoute
+  AppMemoryThreadsRoute: typeof AppMemoryThreadsRoute
+  AppRawDataRoute: typeof AppRawDataRoute
+  AppRetrieveRoute: typeof AppRetrieveRoute
+  AppIndexRoute: typeof AppIndexRoute
+}
+
+const AppRouteRouteChildren: AppRouteRouteChildren = {
+  AppBuffersRoute: AppBuffersRoute,
+  AppConfigRoute: AppConfigRoute,
+  AppInsightsRoute: AppInsightsRoute,
+  AppItemGraphRoute: AppItemGraphRoute,
+  AppItemsRoute: AppItemsRoute,
+  AppMemoryThreadsRoute: AppMemoryThreadsRoute,
+  AppRawDataRoute: AppRawDataRoute,
+  AppRetrieveRoute: AppRetrieveRoute,
+  AppIndexRoute: AppIndexRoute,
+}
+
+const AppRouteRouteWithChildren = AppRouteRoute._addFileChildren(
+  AppRouteRouteChildren,
+)
+
+const rootRouteChildren: RootRouteChildren = {
+  AppRouteRoute: AppRouteRouteWithChildren,
+  errors404Route: errors404Route,
+  errors500Route: errors500Route,
+  errors503Route: errors503Route,
+}
+export const routeTree = rootRouteImport
+  ._addFileChildren(rootRouteChildren)
+  ._addFileTypes<FileRouteTypes>()
diff --git a/memind-ui/src/routes/(errors)/404.tsx b/memind-ui/src/routes/(errors)/404.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/routes/(errors)/404.tsx
@@ -0,0 +1,6 @@
+import { createFileRoute } from '@tanstack/react-router'
+import { NotFoundError } from '@/features/errors/not-found-error'
+
+export const Route = createFileRoute('/(errors)/404')({
+  component: NotFoundError,
+})
diff --git a/memind-ui/src/routes/(errors)/500.tsx b/memind-ui/src/routes/(errors)/500.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/routes/(errors)/500.tsx
@@ -0,0 +1,6 @@
+import { createFileRoute } from '@tanstack/react-router'
+import { GeneralError } from '@/features/errors/general-error'
+
+export const Route = createFileRoute('/(errors)/500')({
+  component: GeneralError,
+})
diff --git a/memind-ui/src/routes/(errors)/503.tsx b/memind-ui/src/routes/(errors)/503.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/routes/(errors)/503.tsx
@@ -0,0 +1,6 @@
+import { createFileRoute } from '@tanstack/react-router'
+import { MaintenanceError } from '@/features/errors/maintenance-error'
+
+export const Route = createFileRoute('/(errors)/503')({
+  component: MaintenanceError,
+})
diff --git a/memind-ui/src/routes/__root.tsx b/memind-ui/src/routes/__root.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/routes/__root.tsx
@@ -0,0 +1,30 @@
+import { type QueryClient } from '@tanstack/react-query'
+import { createRootRouteWithContext, Outlet } from '@tanstack/react-router'
+import { ReactQueryDevtools } from '@tanstack/react-query-devtools'
+import { TanStackRouterDevtools } from '@tanstack/react-router-devtools'
+import { Toaster } from '@/components/ui/sonner'
+import { NavigationProgress } from '@/components/navigation-progress'
+import { GeneralError } from '@/features/errors/general-error'
+import { NotFoundError } from '@/features/errors/not-found-error'
+
+export const Route = createRootRouteWithContext<{
+  queryClient: QueryClient
+}>()({
+  component: () => {
+    return (
+      <>
+        <NavigationProgress />
+        <Outlet />
+        <Toaster duration={5000} />
+        {import.meta.env.MODE === 'development' && (
+          <>
+            <ReactQueryDevtools buttonPosition='bottom-left' />
+            <TanStackRouterDevtools position='bottom-right' />
+          </>
+        )}
+      </>
+    )
+  },
+  notFoundComponent: NotFoundError,
+  errorComponent: GeneralError,
+})
diff --git a/memind-ui/src/routes/_app/buffers.tsx b/memind-ui/src/routes/_app/buffers.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/routes/_app/buffers.tsx
@@ -0,0 +1,38 @@
+import { createFileRoute } from '@tanstack/react-router'
+import { BuffersPage } from '@/features/buffers'
+
+type BuffersSearch = {
+  memoryId?: string
+  tab?: string
+  pageNo?: number
+  pageSize?: number
+  sessionId?: string
+  insightTypeName?: string
+  state?: string
+}
+
+export const Route = createFileRoute('/_app/buffers')({
+  validateSearch: (search): BuffersSearch => ({
+    memoryId: readString(search.memoryId),
+    tab: readString(search.tab),
+    pageNo: readNumber(search.pageNo),
+    pageSize: readNumber(search.pageSize),
+    sessionId: readString(search.sessionId),
+    insightTypeName: readString(search.insightTypeName),
+    state: readString(search.state),
+  }),
+  component: BuffersPage,
+})
+
+function readString(value: unknown) {
+  return typeof value === 'string' && value.trim() !== '' ? value : undefined
+}
+
+function readNumber(value: unknown) {
+  if (typeof value === 'number' && Number.isFinite(value)) return value
+  if (typeof value === 'string' && value.trim() !== '') {
+    const parsed = Number(value)
+    return Number.isFinite(parsed) ? parsed : undefined
+  }
+  return undefined
+}
diff --git a/memind-ui/src/routes/_app/config.tsx b/memind-ui/src/routes/_app/config.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/routes/_app/config.tsx
@@ -0,0 +1,6 @@
+import { createFileRoute } from '@tanstack/react-router'
+import { ConfigPage } from '@/features/config'
+
+export const Route = createFileRoute('/_app/config')({
+  component: ConfigPage,
+})
diff --git a/memind-ui/src/routes/_app/index.tsx b/memind-ui/src/routes/_app/index.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/routes/_app/index.tsx
@@ -0,0 +1,28 @@
+import { createFileRoute } from '@tanstack/react-router'
+import { DashboardPage } from '@/features/dashboard'
+
+type DashboardSearch = {
+  memoryId?: string
+  days?: number
+}
+
+export const Route = createFileRoute('/_app/')({
+  validateSearch: (search): DashboardSearch => ({
+    memoryId: readString(search.memoryId),
+    days: readNumber(search.days),
+  }),
+  component: DashboardPage,
+})
+
+function readString(value: unknown) {
+  return typeof value === 'string' && value.trim() !== '' ? value : undefined
+}
+
+function readNumber(value: unknown) {
+  if (typeof value === 'number' && Number.isFinite(value)) return value
+  if (typeof value === 'string' && value.trim() !== '') {
+    const parsed = Number(value)
+    return Number.isFinite(parsed) ? parsed : undefined
+  }
+  return undefined
+}
diff --git a/memind-ui/src/routes/_app/insights.tsx b/memind-ui/src/routes/_app/insights.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/routes/_app/insights.tsx
@@ -0,0 +1,36 @@
+import { createFileRoute } from '@tanstack/react-router'
+import { InsightsPage } from '@/features/insights'
+
+type InsightsSearch = {
+  memoryId?: string
+  pageNo?: number
+  pageSize?: number
+  scope?: string
+  type?: string
+  tier?: string
+}
+
+export const Route = createFileRoute('/_app/insights')({
+  validateSearch: (search): InsightsSearch => ({
+    memoryId: readString(search.memoryId),
+    pageNo: readNumber(search.pageNo),
+    pageSize: readNumber(search.pageSize),
+    scope: readString(search.scope),
+    type: readString(search.type),
+    tier: readString(search.tier),
+  }),
+  component: InsightsPage,
+})
+
+function readString(value: unknown) {
+  return typeof value === 'string' && value.trim() !== '' ? value : undefined
+}
+
+function readNumber(value: unknown) {
+  if (typeof value === 'number' && Number.isFinite(value)) return value
+  if (typeof value === 'string' && value.trim() !== '') {
+    const parsed = Number(value)
+    return Number.isFinite(parsed) ? parsed : undefined
+  }
+  return undefined
+}
diff --git a/memind-ui/src/routes/_app/item-graph.tsx b/memind-ui/src/routes/_app/item-graph.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/routes/_app/item-graph.tsx
@@ -0,0 +1,46 @@
+import { createFileRoute } from '@tanstack/react-router'
+import { ItemGraphPage } from '@/features/item-graph'
+
+type ItemGraphSearch = {
+  memoryId?: string
+  tab?: string
+  pageNo?: number
+  pageSize?: number
+  entityType?: string
+  entityKey?: string
+  itemId?: number
+  linkType?: string
+  evidenceSource?: string
+  state?: string
+  q?: string
+}
+
+export const Route = createFileRoute('/_app/item-graph')({
+  validateSearch: (search): ItemGraphSearch => ({
+    memoryId: readString(search.memoryId),
+    tab: readString(search.tab),
+    pageNo: readNumber(search.pageNo),
+    pageSize: readNumber(search.pageSize),
+    entityType: readString(search.entityType),
+    entityKey: readString(search.entityKey),
+    itemId: readNumber(search.itemId),
+    linkType: readString(search.linkType),
+    evidenceSource: readString(search.evidenceSource),
+    state: readString(search.state),
+    q: readString(search.q),
+  }),
+  component: ItemGraphPage,
+})
+
+function readString(value: unknown) {
+  return typeof value === 'string' && value.trim() !== '' ? value : undefined
+}
+
+function readNumber(value: unknown) {
+  if (typeof value === 'number' && Number.isFinite(value)) return value
+  if (typeof value === 'string' && value.trim() !== '') {
+    const parsed = Number(value)
+    return Number.isFinite(parsed) ? parsed : undefined
+  }
+  return undefined
+}
diff --git a/memind-ui/src/routes/_app/items.tsx b/memind-ui/src/routes/_app/items.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/routes/_app/items.tsx
@@ -0,0 +1,38 @@
+import { createFileRoute } from '@tanstack/react-router'
+import { ItemsPage } from '@/features/items'
+
+type ItemsSearch = {
+  memoryId?: string
+  pageNo?: number
+  pageSize?: number
+  scope?: string
+  category?: string
+  type?: string
+  rawDataId?: string
+}
+
+export const Route = createFileRoute('/_app/items')({
+  validateSearch: (search): ItemsSearch => ({
+    memoryId: readString(search.memoryId),
+    pageNo: readNumber(search.pageNo),
+    pageSize: readNumber(search.pageSize),
+    scope: readString(search.scope),
+    category: readString(search.category),
+    type: readString(search.type),
+    rawDataId: readString(search.rawDataId),
+  }),
+  component: ItemsPage,
+})
+
+function readString(value: unknown) {
+  return typeof value === 'string' && value.trim() !== '' ? value : undefined
+}
+
+function readNumber(value: unknown) {
+  if (typeof value === 'number' && Number.isFinite(value)) return value
+  if (typeof value === 'string' && value.trim() !== '') {
+    const parsed = Number(value)
+    return Number.isFinite(parsed) ? parsed : undefined
+  }
+  return undefined
+}
diff --git a/memind-ui/src/routes/_app/memory-threads.tsx b/memind-ui/src/routes/_app/memory-threads.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/routes/_app/memory-threads.tsx
@@ -0,0 +1,34 @@
+import { createFileRoute } from '@tanstack/react-router'
+import { MemoryThreadsPage } from '@/features/memory-threads'
+
+type MemoryThreadsSearch = {
+  memoryId?: string
+  pageNo?: number
+  pageSize?: number
+  status?: string
+  focus?: string
+}
+
+export const Route = createFileRoute('/_app/memory-threads')({
+  validateSearch: (search): MemoryThreadsSearch => ({
+    memoryId: readString(search.memoryId),
+    pageNo: readNumber(search.pageNo),
+    pageSize: readNumber(search.pageSize),
+    status: readString(search.status),
+    focus: readString(search.focus),
+  }),
+  component: MemoryThreadsPage,
+})
+
+function readString(value: unknown) {
+  return typeof value === 'string' && value.trim() !== '' ? value : undefined
+}
+
+function readNumber(value: unknown) {
+  if (typeof value === 'number' && Number.isFinite(value)) return value
+  if (typeof value === 'string' && value.trim() !== '') {
+    const parsed = Number(value)
+    return Number.isFinite(parsed) ? parsed : undefined
+  }
+  return undefined
+}
diff --git a/memind-ui/src/routes/_app/raw-data.tsx b/memind-ui/src/routes/_app/raw-data.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/routes/_app/raw-data.tsx
@@ -0,0 +1,34 @@
+import { createFileRoute } from '@tanstack/react-router'
+import { RawDataPage } from '@/features/raw-data'
+
+type RawDataSearch = {
+  memoryId?: string
+  pageNo?: number
+  pageSize?: number
+  startTimeFrom?: string
+  startTimeTo?: string
+}
+
+export const Route = createFileRoute('/_app/raw-data')({
+  validateSearch: (search): RawDataSearch => ({
+    memoryId: readString(search.memoryId),
+    pageNo: readNumber(search.pageNo),
+    pageSize: readNumber(search.pageSize),
+    startTimeFrom: readString(search.startTimeFrom),
+    startTimeTo: readString(search.startTimeTo),
+  }),
+  component: RawDataPage,
+})
+
+function readString(value: unknown) {
+  return typeof value === 'string' && value.trim() !== '' ? value : undefined
+}
+
+function readNumber(value: unknown) {
+  if (typeof value === 'number' && Number.isFinite(value)) return value
+  if (typeof value === 'string' && value.trim() !== '') {
+    const parsed = Number(value)
+    return Number.isFinite(parsed) ? parsed : undefined
+  }
+  return undefined
+}
diff --git a/memind-ui/src/routes/_app/retrieve.tsx b/memind-ui/src/routes/_app/retrieve.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/routes/_app/retrieve.tsx
@@ -0,0 +1,17 @@
+import { createFileRoute } from '@tanstack/react-router'
+import { RetrievePage } from '@/features/retrieve'
+
+type RetrieveSearch = {
+  memoryId?: string
+}
+
+export const Route = createFileRoute('/_app/retrieve')({
+  validateSearch: (search): RetrieveSearch => ({
+    memoryId: readString(search.memoryId),
+  }),
+  component: RetrievePage,
+})
+
+function readString(value: unknown) {
+  return typeof value === 'string' && value.trim() !== '' ? value : undefined
+}
diff --git a/memind-ui/src/routes/_app/route.tsx b/memind-ui/src/routes/_app/route.tsx
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/routes/_app/route.tsx
@@ -0,0 +1,6 @@
+import { createFileRoute } from '@tanstack/react-router'
+import { AppLayout } from '@/components/layout/app-layout'
+
+export const Route = createFileRoute('/_app')({
+  component: AppLayout,
+})
diff --git a/memind-ui/src/styles/index.css b/memind-ui/src/styles/index.css
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/styles/index.css
@@ -0,0 +1,87 @@
+@import 'tailwindcss';
+@import 'tw-animate-css';
+@import './theme.css';
+
+@custom-variant dark (&:is(.dark *));
+
+@layer base {
+  * {
+    @apply border-border outline-ring/50;
+    scrollbar-width: thin;
+    scrollbar-color: var(--border) transparent;
+  }
+  html {
+    @apply overflow-x-hidden;
+  }
+  body {
+    @apply min-h-svh w-full bg-background text-foreground has-[div[data-variant='inset']]:bg-sidebar;
+  }
+
+  /* Override Radix scroll locking for sticky headers */
+  body[data-scroll-locked] {
+    overflow: unset !important;
+  }
+
+  /* Cursor pointer for buttons */
+  button:not(:disabled),
+  [role='button']:not(:disabled) {
+    cursor: pointer;
+  }
+
+  /* Prevent focus zoom on mobile devices */
+  @media screen and (max-width: 767px) {
+    input,
+    select,
+    textarea {
+      font-size: 16px !important;
+    }
+  }
+}
+
+@utility container {
+  margin-inline: auto;
+  padding-inline: 2rem;
+}
+
+@utility no-scrollbar {
+  /* Hide scrollbar for Chrome, Safari and Opera */
+  &::-webkit-scrollbar {
+    display: none;
+  }
+  /* Hide scrollbar for IE, Edge and Firefox */
+  -ms-overflow-style: none; /* IE and Edge */
+  scrollbar-width: none; /* Firefox */
+}
+
+@utility faded-bottom {
+  @apply after:pointer-events-none after:absolute after:inset-s-0 after:bottom-0 after:hidden after:h-32 after:w-full after:rounded-b-2xl after:bg-[linear-gradient(180deg,transparent_10%,var(--background)_70%)] md:after:block;
+}
+
+/* styles.css */
+.CollapsibleContent {
+  overflow: hidden;
+}
+.CollapsibleContent[data-state='open'] {
+  animation: slideDown 300ms ease-out;
+}
+.CollapsibleContent[data-state='closed'] {
+  animation: slideUp 300ms ease-out;
+}
+
+@keyframes slideDown {
+  from {
+    height: 0;
+  }
+  to {
+    height: var(--radix-collapsible-content-height);
+  }
+}
+
+@keyframes slideUp {
+  from {
+    height: var(--radix-collapsible-content-height);
+  }
+  to {
+    height: 0;
+  }
+}
diff --git a/memind-ui/src/styles/theme.css b/memind-ui/src/styles/theme.css
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/styles/theme.css
@@ -0,0 +1,102 @@
+:root {
+  --radius: 0.625rem;
+  --background: oklch(1 0 0);
+  --foreground: oklch(0.129 0.042 264.695);
+  --card: oklch(1 0 0);
+  --card-foreground: oklch(0.129 0.042 264.695);
+  --popover: oklch(1 0 0);
+  --popover-foreground: oklch(0.129 0.042 264.695);
+  --primary: oklch(0.208 0.042 265.755);
+  --primary-foreground: oklch(0.984 0.003 247.858);
+  --secondary: oklch(0.968 0.007 247.896);
+  --secondary-foreground: oklch(0.208 0.042 265.755);
+  --muted: oklch(0.968 0.007 247.896);
+  --muted-foreground: oklch(0.554 0.046 257.417);
+  --accent: oklch(0.968 0.007 247.896);
+  --accent-foreground: oklch(0.208 0.042 265.755);
+  --destructive: oklch(0.577 0.245 27.325);
+  --border: oklch(0.929 0.013 255.508);
+  --input: oklch(0.929 0.013 255.508);
+  --ring: oklch(0.704 0.04 256.788);
+  --chart-1: oklch(0.646 0.222 41.116);
+  --chart-2: oklch(0.6 0.118 184.704);
+  --chart-3: oklch(0.398 0.07 227.392);
+  --chart-4: oklch(0.828 0.189 84.429);
+  --chart-5: oklch(0.769 0.188 70.08);
+
+  --sidebar: var(--background);
+  --sidebar-foreground: var(--foreground);
+  --sidebar-primary: var(--primary);
+  --sidebar-primary-foreground: var(--primary-foreground);
+  --sidebar-accent: var(--accent);
+  --sidebar-accent-foreground: var(--accent-foreground);
+  --sidebar-border: var(--border);
+  --sidebar-ring: var(--ring);
+}
+
+.dark {
+  --background: oklch(0.129 0.042 264.695);
+  --foreground: oklch(0.984 0.003 247.858);
+  --card: oklch(0.14 0.04 259.21);
+  --card-foreground: oklch(0.984 0.003 247.858);
+  --popover: oklch(0.208 0.042 265.755);
+  --popover-foreground: oklch(0.984 0.003 247.858);
+  --primary: oklch(0.929 0.013 255.508);
+  --primary-foreground: oklch(0.208 0.042 265.755);
+  --secondary: oklch(0.279 0.041 260.031);
+  --secondary-foreground: oklch(0.984 0.003 247.858);
+  --muted: oklch(0.279 0.041 260.031);
+  --muted-foreground: oklch(0.704 0.04 256.788);
+  --accent: oklch(0.279 0.041 260.031);
+  --accent-foreground: oklch(0.984 0.003 247.858);
+  --destructive: oklch(0.704 0.191 22.216);
+  --border: oklch(1 0 0 / 10%);
+  --input: oklch(1 0 0 / 15%);
+  --ring: oklch(0.551 0.027 264.364);
+  --chart-1: oklch(0.488 0.243 264.376);
+  --chart-2: oklch(0.696 0.17 162.48);
+  --chart-3: oklch(0.769 0.188 70.08);
+  --chart-4: oklch(0.627 0.265 303.9);
+  --chart-5: oklch(0.645 0.246 16.439);
+}
+
+@theme inline {
+  --font-inter: 'Inter', 'sans-serif';
+  --font-manrope: 'Manrope', 'sans-serif';
+
+  --radius-sm: calc(var(--radius) - 4px);
+  --radius-md: calc(var(--radius) - 2px);
+  --radius-lg: var(--radius);
+  --radius-xl: calc(var(--radius) + 4px);
+  --color-background: var(--background);
+  --color-foreground: var(--foreground);
+  --color-card: var(--card);
+  --color-card-foreground: var(--card-foreground);
+  --color-popover: var(--popover);
+  --color-popover-foreground: var(--popover-foreground);
+  --color-primary: var(--primary);
+  --color-primary-foreground: var(--primary-foreground);
+  --color-secondary: var(--secondary);
+  --color-secondary-foreground: var(--secondary-foreground);
+  --color-muted: var(--muted);
+  --color-muted-foreground: var(--muted-foreground);
+  --color-accent: var(--accent);
+  --color-accent-foreground: var(--accent-foreground);
+  --color-destructive: var(--destructive);
+  --color-border: var(--border);
+  --color-input: var(--input);
+  --color-ring: var(--ring);
+  --color-chart-1: var(--chart-1);
+  --color-chart-2: var(--chart-2);
+  --color-chart-3: var(--chart-3);
+  --color-chart-4: var(--chart-4);
+  --color-chart-5: var(--chart-5);
+  --color-sidebar: var(--sidebar);
+  --color-sidebar-foreground: var(--sidebar-foreground);
+  --color-sidebar-primary: var(--sidebar-primary);
+  --color-sidebar-primary-foreground: var(--sidebar-primary-foreground);
+  --color-sidebar-accent: var(--sidebar-accent);
+  --color-sidebar-accent-foreground: var(--sidebar-accent-foreground);
+  --color-sidebar-border: var(--sidebar-border);
+  --color-sidebar-ring: var(--sidebar-ring);
+}
diff --git a/memind-ui/src/tanstack-table.d.ts b/memind-ui/src/tanstack-table.d.ts
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/tanstack-table.d.ts
@@ -0,0 +1,10 @@
+import '@tanstack/react-table'
+
+declare module '@tanstack/react-table' {
+  // eslint-disable-next-line @typescript-eslint/no-unused-vars
+  interface ColumnMeta<TData, TValue> {
+    className?: string // apply to both th and td
+    tdClassName?: string
+    thClassName?: string
+  }
+}
diff --git a/memind-ui/src/vite-env.d.ts b/memind-ui/src/vite-env.d.ts
new file mode 100644
--- /dev/null
+++ b/memind-ui/src/vite-env.d.ts
@@ -0,0 +1,5 @@
+/// <reference types="vite/client" />
+
+interface ImportMetaEnv {
+  readonly VITE_MEMIND_MOCK_API?: string
+}
diff --git a/memind-ui/tsconfig.app.json b/memind-ui/tsconfig.app.json
new file mode 100644
--- /dev/null
+++ b/memind-ui/tsconfig.app.json
@@ -0,0 +1,31 @@
+{
+  "compilerOptions": {
+    "tsBuildInfoFile": "./node_modules/.tmp/tsconfig.app.tsbuildinfo",
+    "target": "ES2020",
+    "useDefineForClassFields": true,
+    "lib": ["ES2020", "DOM", "DOM.Iterable"],
+    "module": "ESNext",
+    "skipLibCheck": true,
+
+    /* Bundler mode */
+    "moduleResolution": "Bundler",
+    "allowImportingTsExtensions": true,
+    "isolatedModules": true,
+    "moduleDetection": "force",
+    "noEmit": true,
+    "jsx": "react-jsx",
+
+    /* Alias */
+    "paths": {
+      "@/*": ["./src/*"]
+    },
+
+    /* Linting */
+    "strict": true,
+    "noUnusedLocals": true,
+    "noUnusedParameters": true,
+    "noFallthroughCasesInSwitch": true,
+    "noUncheckedSideEffectImports": true
+  },
+  "include": ["src"]
+}
diff --git a/memind-ui/tsconfig.json b/memind-ui/tsconfig.json
new file mode 100644
--- /dev/null
+++ b/memind-ui/tsconfig.json
@@ -0,0 +1,12 @@
+{
+  "files": [],
+  "references": [
+    { "path": "./tsconfig.app.json" },
+    { "path": "./tsconfig.node.json" }
+  ],
+  "compilerOptions": {
+    "paths": {
+      "@/*": ["./src/*"]
+    }
+  }
+}
diff --git a/memind-ui/tsconfig.node.json b/memind-ui/tsconfig.node.json
new file mode 100644
--- /dev/null
+++ b/memind-ui/tsconfig.node.json
@@ -0,0 +1,24 @@
+{
+  "compilerOptions": {
+    "tsBuildInfoFile": "./node_modules/.tmp/tsconfig.node.tsbuildinfo",
+    "target": "ES2022",
+    "lib": ["ES2023"],
+    "module": "ESNext",
+    "skipLibCheck": true,
+
+    /* Bundler mode */
+    "moduleResolution": "Bundler",
+    "allowImportingTsExtensions": true,
+    "isolatedModules": true,
+    "moduleDetection": "force",
+    "noEmit": true,
+
+    /* Linting */
+    "strict": true,
+    "noUnusedLocals": true,
+    "noUnusedParameters": true,
+    "noFallthroughCasesInSwitch": true,
+    "noUncheckedSideEffectImports": true
+  },
+  "include": ["vite.config.ts"]
+}
diff --git a/memind-ui/vite.config.ts b/memind-ui/vite.config.ts
new file mode 100644
--- /dev/null
+++ b/memind-ui/vite.config.ts
@@ -0,0 +1,70 @@
+/// <reference types="vitest/config" />
+import path from 'path'
+import { defineConfig } from 'vite'
+import react from '@vitejs/plugin-react'
+import tailwindcss from '@tailwindcss/vite'
+import { tanstackRouter } from '@tanstack/router-plugin/vite'
+import { playwright } from '@vitest/browser-playwright'
+
+// https://vite.dev/config/
+export default defineConfig({
+  plugins: [
+    tanstackRouter({
+      target: 'react',
+      autoCodeSplitting: true,
+    }),
+    react(),
+    tailwindcss(),
+  ],
+  resolve: {
+    alias: {
+      '@': path.resolve(__dirname, './src'),
+    },
+  },
+  server: {
+    proxy: {
+      '/admin': {
+        target: 'http://127.0.0.1:8366',
+        changeOrigin: true,
+      },
+      '/open': {
+        target: 'http://127.0.0.1:8366',
+        changeOrigin: true,
+      },
+    },
+  },
+  optimizeDeps: {
+    include: [
+      '@radix-ui/react-alert-dialog',
+      '@radix-ui/react-checkbox',
+      '@radix-ui/react-dialog',
+      '@radix-ui/react-dropdown-menu',
+      '@radix-ui/react-label',
+      '@radix-ui/react-separator',
+      '@radix-ui/react-switch',
+      '@radix-ui/react-tabs',
+      '@radix-ui/react-tooltip',
+      '@tanstack/react-query',
+    ],
+  },
+  test: {
+    silent: 'passed-only',
+    unstubEnvs: true,
+    browser: {
+      enabled: true,
+      provider: playwright(),
+      instances: [{ browser: 'chromium' }],
+    },
+    coverage: {
+      // include: ['src/**/*.{js,jsx,ts,tsx}'], // Uncomment to expand the report to all src/**/* so untested modules appear as 0% coverage.
+      exclude: [
+        'src/components/ui/**',
+        'src/assets/**',
+        'src/tanstack-table.d.ts',
+        'src/routeTree.gen.ts',
+        'src/test-utils/**',
+        'src/routes/**',
+      ],
+    },
+  },
+})
diff --git a/pom.xml b/pom.xml
--- a/pom.xml
+++ b/pom.xml
@@ -300,6 +300,7 @@
                         <exclude>etc/**</exclude>
                         <exclude>eval-data/**</exclude>
                         <exclude>memind-integrations/codex/**</exclude>
+                        <exclude>memind-ui/**</exclude>
                         <exclude>memind-evaluation/data/**</exclude>
                     </excludes>
                 </configuration>
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
