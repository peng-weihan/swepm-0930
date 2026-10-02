#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/AGENTS.md b/AGENTS.md
--- a/AGENTS.md
+++ b/AGENTS.md
@@ -228,6 +228,39 @@ The Artifacts feature provides rich preview of code outputs similar to Claude's
 - Naming: `PascalCase` for components (e.g., `Chat.tsx`), `camelCase` for functions/vars, and `*Slice.ts` for Redux slices.
 - Tailwind CSS is the primary styling approach; prefer utility classes over bespoke CSS.
 
+## String Literal Constants
+
+**Never use bare string literals** for values that act as discriminants, status codes, IPC channel names, mode selectors, or any string compared/switched against in multiple places. Instead, define a centralized `as const` object and derive the type from it.
+
+### Pattern
+
+```typescript
+// In constants.ts (one per module, e.g. src/scheduled-task/constants.ts)
+export const SessionTarget = {
+  Main: 'main',
+  Isolated: 'isolated',
+} as const;
+export type SessionTarget = typeof SessionTarget[keyof typeof SessionTarget];
+```
+
+### Rules
+
+1. **One source of truth per module.** Each module that owns a set of string constants must have a `constants.ts` file. Consumer modules import both the value object and the type.
+2. **Value construction and comparison must use constants.** Write `SessionTarget.Main`, not `'main'`. This applies to source files, test files, and any other TypeScript that references these values.
+3. **Discriminant `kind` fields in interface definitions remain literal.** The `kind: 'at'` in `interface ScheduleAt` defines the discriminated union shape and must stay as a literal. The constant should match this value; consumers use the constant object for comparisons and construction.
+4. **IPC channel names must be constants.** All `ipcMain.handle()` registrations and `ipcRenderer.invoke()` calls must reference an `IpcChannel` constant, never a bare string.
+5. **Tests use constants too.** Test files must import and use the same constants — this is the primary defense against "modified the constant but forgot to update the test" drift.
+
+### What NOT to constantize
+
+- Platform-specific identifiers passed through from external sources (e.g., `'telegram'`, `'feishu'` as IM platform names from user config).
+- One-off strings used in a single location with no comparison logic (e.g., error messages, log tags).
+- CSS class names, HTML attributes, and other UI-layer strings managed by Tailwind/React.
+
+### Existing reference
+
+`src/scheduled-task/constants.ts` is the canonical example of this pattern, covering schedule kinds, payload kinds, delivery modes, session targets, wake modes, origin kinds, binding kinds, task status, IPC channels, and migration keys.
+
 ## Logging Guidelines
 
 The main process uses `electron-log` via `src/main/logger.ts`, which intercepts all `console.*` calls and writes them to daily-rotated log files. **No additional logging library is needed** — use the standard `console` API everywhere in `src/main/`.
diff --git a/SKILLs/article-writer/SKILL.md b/SKILLs/article-writer/SKILL.md
new file mode 100644
--- /dev/null
+++ b/SKILLs/article-writer/SKILL.md
@@ -0,0 +1,234 @@
+---
+name: article-writer
+description: |
+  Multi-style article creation skill. Supports 5 writing styles (deep analysis, practical guide, story-driven, opinion, news brief),
+  including complete workflow: material collection → outline → content → formatting. Activated when users mention "write article", "write post", "create", or "draft".
+official: true
+---
+
+# Multi-Style Article Creation
+
+## Use Cases
+
+- User says "写一篇关于XX的文章"
+- User says "帮我写一篇公众号文章"
+- User selects a topic from the content calendar to start writing
+- User specifies a writing style (e.g., "深度分析风格", "写个教程")
+
+## 5 Writing Styles
+
+| Style ID | Name | Characteristics | Word Count | Use Cases |
+|----------|------|-----------------|------------|-----------|
+| `deep-analysis` | 深度分析 | Rigorous structure, data-backed | 2000-4000 words | Trend analysis, in-depth reporting |
+| `practical-guide` | 实用指南 | Clear steps, highly actionable | 1500-3000 words | Tool tutorials, how-to guides |
+| `story-driven` | 故事驱动 | Conversational, emotional resonance | 1500-2500 words | Personal stories, case reviews |
+| `opinion` | 观点评论 | Sharp opening, pros/cons argumentation | 1000-2000 words | Hot takes, controversial topics |
+| `news-brief` | 新闻简报 | Inverted pyramid, fact-focused | 500-1000 words | Breaking news, information roundups |
+
+## Workflow
+
+### Step 1: Read the Brief
+
+Obtain topic information from:
+1. Entries with status `planned` in `content_calendar.json`
+2. Topic description directly provided by the user
+
+Extract key information:
+- Topic direction / title
+- Target audience
+- Writing style (if not specified, recommend based on topic content)
+- Reference material URLs
+
+### Step 2: Determine Writing Style
+
+If user hasn't specified, recommend based on topic:
+
+| Topic Characteristics | Recommended Style |
+|----------------------|-------------------|
+| Involves data, trends, underlying causes | `deep-analysis` |
+| "How to", "tutorial", "steps" | `practical-guide` |
+| Involves people, experiences, insights | `story-driven` |
+| Involves controversy, hot topic commentary | `opinion` |
+| Breaking events, quick information | `news-brief` |
+
+Confirm the style choice with the user.
+
+### Step 3: Material Collection
+
+Use content-planner's search script to collect reference materials:
+
+```bash
+node "$SKILLS_ROOT/content-planner/scripts/wechat_search.js" "topic keywords" -n 10
+```
+
+Also use web-search skill for additional materials.
+
+Organize material list:
+- Citable data/statistics
+- Reference cases/stories
+- Facts that need verification
+
+### Step 4: Generate Outline
+
+Generate an outline based on the selected style using the corresponding structure template.
+
+#### deep-analysis Template
+
+```
+## 引入 (200-300字) — 反直觉数据/现象开头
+## 背景 (300-500字) — 事件/现象的来龙去脉
+## 分析维度1 (400-600字) — 核心论点 + 数据支撑
+## 分析维度2 (400-600字) — 对比/反面论证
+## 分析维度3 (400-600字) — 深层原因 + 影响预测
+## 总结与展望 (200-300字) — 核心观点 + CTA
+```
+
+#### practical-guide Template
+
+```
+## 开头 (100-200字) — 痛点共鸣 + 承诺
+## 前置准备 (200-300字)
+## 步骤1 (300-500字) — 具体操作 + 常见坑
+## 步骤2 (300-500字) — 具体操作 + 关键参数
+## 步骤3 (300-500字) — 具体操作 + 验证方法
+## 进阶技巧 (200-300字)
+## 总结 (100-200字) — FAQ + CTA
+```
+
+#### story-driven Template
+
+```
+## 开头 (150-200字) — 场景切入 + 悬念
+## 背景铺垫 (200-300字) — 人物/背景/冲突
+## 转折1 (300-400字) — 关键事件 + 感受
+## 转折2 (300-400字) — 新尝试 + 结果
+## 高潮 (200-300字) — 核心洞察
+## 结尾 (150-200字) — 启发 + CTA
+```
+
+#### opinion Template
+
+```
+## 锐利开头 (100-150字) — 直接亮观点
+## 现象描述 (200-300字) — 主流观点
+## 正面论证 (300-400字) — 我的论点 + 数据
+## 反面回应 (200-300字) — 预设反驳 + 反驳
+## 深度思考 (200-300字) — 本质 + 影响
+## 总结 (100-150字) — 重申观点 + CTA
+```
+
+#### news-brief Template
+
+```
+## 核心信息 (100-200字) — What/When/Where/Who
+## 事件详情 (200-300字)
+## 背景 (100-200字)
+## 反应 (100-200字)
+## 编者按 (50-100字)
+```
+
+### Step 5: User Approval of Outline
+
+**This is a mandatory approval gate and cannot be skipped.**
+
+Present the outline to the user and ask for confirmation or modification requests.
+
+### Step 6: Write the Content
+
+After approval, write content paragraph by paragraph following the outline.
+
+**Universal Writing Rules:**
+
+1. **Use stories instead of preaching**
+   - ❌ "风险管理很重要，应该做应急预案"
+   - ✅ "去年，我的创业团队差点因为一个核心员工离职而崩溃，因为我们没有任何备选方案。"
+
+2. **Use analogies and metaphors**
+   - ❌ "分布式系统很复杂"
+   - ✅ "分布式系统就像连锁餐厅——每个分店需要协作，同时又要独立运营。"
+
+3. **Support with data but don't pile it on**
+   - ❌ "据IDC报告，全球AI市场2023年增长45%，预计2025年达1000亿美元..."
+   - ✅ "AI市场疯狂增长——每年翻一番。但在增长背后，真正赚钱的公司不到5家。"
+
+4. **State opinions directly, avoid ambiguity**
+   - ❌ "有人认为...也有人认为...各有道理"
+   - ✅ "说实话，我认为XX的做法是错的，因为..."
+
+5. **Use short sentences and line breaks**
+
+**Data integrity rules:**
+- If specific data is needed but uncertain, mark `[数据待确认]` and confirm with user
+- Use search tools to verify key facts
+- Can tell fictional stories using "我见过..." or "一个朋友...", but don't fabricate data
+
+### Step 7: Formatting Optimization
+
+**WeChat Formatting Hard Rules:**
+
+1. **Paragraphs no more than 4 lines** (mobile screen visible range)
+2. **Insert a subheading or bold sentence every 3-4 paragraphs**
+3. **Must have a hook within the first 3 lines** (question, data, story, counter-intuitive viewpoint)
+4. **Must have a clear CTA at the end** (follow/share/comment prompt)
+
+**Markdown Formatting Standards:**
+- No first-line indentation, use blank lines to separate paragraphs
+- Maximum 2 heading levels (`##`), no deep nesting
+- Bold only the 1-2 most important words per paragraph
+- Use quotes for data, golden sentences, or important viewpoints
+- Lists maximum 5 items
+
+### Step 8: Output Draft
+
+Save the article as Markdown:
+
+Filename format: `drafts/YYYYMMDD_[topic-slug].md`
+
+```markdown
+---
+title: Article Title
+date: YYYY-MM-DD
+style: deep-analysis
+summary: Article summary (within 100 words)
+---
+
+## Opening
+
+Content...
+```
+
+### Step 9: Quality Checklist
+
+```
+✅ Title — Sparks curiosity or resonance
+✅ Opening — First 100 words are engaging
+✅ Body — Has 2-3 clear viewpoints
+✅ Cases — Uses stories not preaching
+✅ Formatting — Easy to read (short paragraphs, bold, subheadings)
+✅ Word Count — Within style-specified range
+✅ CTA — Ending has action prompt
+```
+
+## Title Optimization Process
+
+### Step 1: Generate 10 Candidate Titles
+
+Use these psychological strategies:
+
+| Strategy | Description | Example |
+|----------|-------------|---------|
+| Suspense | Spark curiosity | "为什么我放弃了年薪50万的工作" |
+| Benefit | Clarify reader gains | "掌握这3个技巧，效率提升200%" |
+| Pain Point | Hit reader anxiety | "别让这个习惯毁了你的职业生涯" |
+| Numbers | Specific and tangible | "50%的人都误解了这个真相" |
+| Rhetorical | Stimulate thinking | "你真的了解AI吗？" |
+| Contrast | Create contrast | "BAT vs 创业公司：差别在哪" |
+
+### Step 2: Score and Filter
+
+Score on 3 dimensions (Attractiveness 40%, Shareability 30%, SEO 30%) and present top 3 to user.
+
+## Integration with Other Skills
+
+- **Upstream**: content-planner's `content_calendar.json` provides topic input
+- **Downstream**: Markdown files in drafts/ can be further processed
diff --git a/SKILLs/content-planner/SKILL.md b/SKILLs/content-planner/SKILL.md
new file mode 100644
--- /dev/null
+++ b/SKILLs/content-planner/SKILL.md
@@ -0,0 +1,158 @@
+---
+name: content-planner
+description: |
+  WeChat Official Account topic planning and content calendar management. Based on WeChat article search and trending analysis,
+  generates differentiated topic recommendations and outputs structured content calendars. Activated when users mention
+  "topic", "planning", "content calendar", "trending", or "what to write next week".
+official: true
+---
+
+# Topic Planning + Content Calendar
+
+## Use Cases
+
+- User says "帮我规划下周公众号内容"
+- User says "最近有什么热门选题可以写"
+- User says "帮我做一份内容日历"
+- User wants to know what competitor accounts are writing about
+- Need to make topic decisions based on data
+
+## Dependencies
+
+Node.js + cheerio (install once):
+
+```bash
+npm install -g cheerio
+```
+
+## Script Directory
+
+| Script | Purpose | Usage |
+|--------|---------|-------|
+| `scripts/wechat_search.js` | Sogou WeChat article search | `node "$SKILLS_ROOT/content-planner/scripts/wechat_search.js" "keyword"` |
+
+### Search Script Parameters
+
+**IMPORTANT:** Always use the `$SKILLS_ROOT` environment variable to locate scripts.
+
+```bash
+# Basic search
+node "$SKILLS_ROOT/content-planner/scripts/wechat_search.js" "keyword"
+
+# Limit result count
+node "$SKILLS_ROOT/content-planner/scripts/wechat_search.js" "keyword" -n 15
+
+# Save to file
+node "$SKILLS_ROOT/content-planner/scripts/wechat_search.js" "keyword" -n 20 -o result.json
+
+# Parse real URLs (extra network requests, may be blocked by anti-scraping)
+node "$SKILLS_ROOT/content-planner/scripts/wechat_search.js" "keyword" -n 5 -r
+```
+
+**Output Fields:** Article title, article URL, article summary, publish time, source account name
+
+## Workflow
+
+### Step 1: Clarify Planning Scope
+
+Confirm the following information with the user (ask all at once):
+
+```
+帮你规划内容，先确认几件事：
+
+1. 规划周期？（本周 / 下周 / 自定义时间范围）
+2. 有没有特定想写的方向或关键词？
+3. 每周几篇？（默认3篇）
+```
+
+### Step 2: Trending Scan
+
+Execute multiple rounds of searches covering different dimensions:
+
+**Search Strategy:**
+
+1. **Core domain keyword search** — Search with 2-3 core keywords related to the account's field
+2. **User-specified keyword search** — If user has specific directions
+3. **General trending search** — Search with combinations of "热点", "热门", "最新" with domain keywords
+
+```bash
+# Example: Tech domain
+node "$SKILLS_ROOT/content-planner/scripts/wechat_search.js" "AI 最新趋势" -n 10
+node "$SKILLS_ROOT/content-planner/scripts/wechat_search.js" "大模型应用" -n 10
+node "$SKILLS_ROOT/content-planner/scripts/wechat_search.js" "科技热点 2026" -n 10
+```
+
+Wait 3-5 seconds between each search to avoid triggering anti-scraping mechanisms.
+
+### Step 3: Competitor Analysis
+
+Extract from search results:
+
+| Analysis Dimension | Extracted Content |
+|-------------------|-------------------|
+| Title Strategy | Which title patterns get high engagement |
+| Topic Direction | Which directions are recent hot topics |
+| Content Angle | What angles do existing articles take, how to differentiate |
+| Publish Time | Competitors' publishing frequency and timing |
+
+### Step 4: Generate Topic Recommendations
+
+Based on trending data and competitor analysis, generate 5-10 topic suggestions. Each topic must include:
+
+- **Alternative Titles** (2 styles)
+- **Target Audience**
+- **Content Angle** (differentiation point)
+- **Recommended Style**: deep-analysis / practical-guide / story-driven / opinion / news-brief
+- **Urgency**: 🔥 Urgent / 📅 This week / 📦 Reserve
+- **Reference Articles** (from search results)
+
+**Topic Quality Requirements:**
+- Each topic must be based on real search data, not fabricated
+- Each topic must have a clear differentiation angle
+- Must include at least 1 high-urgency topic (🔥) and 2 reserve topics (📦)
+
+### Step 5: User Approval
+
+**This is a mandatory approval gate and cannot be skipped.**
+
+Present the topic list and ask user to select, adjust, and schedule.
+
+### Step 6: Generate Content Calendar
+
+Output `content_calendar.json`:
+
+```json
+{
+  "week": "2026-W13",
+  "created_at": "2026-03-25",
+  "articles": [
+    {
+      "id": 1,
+      "date": "2026-03-26",
+      "day": "Wednesday",
+      "topic": "Topic Title",
+      "angle": "Differentiation Angle",
+      "style": "deep-analysis",
+      "audience": "Target Audience",
+      "urgency": "this-week",
+      "status": "planned",
+      "keywords": ["keyword1", "keyword2"]
+    }
+  ]
+}
+```
+
+### Step 7: Output Confirmation
+
+Present a summary table and prompt user to start writing with article-writer skill.
+
+## Search Considerations
+
+- Search results may be empty (anti-scraping), retry with different keywords
+- Multiple searches in short time may trigger restrictions, recommend 3-5 second intervals
+- The `-r` parameter for parsing real URLs has low success rate, avoid unless necessary
+
+## Integration with Other Skills
+
+- The generated `content_calendar.json` is the input source for **article-writer**
+- article-writer reads entries with status `planned` from the calendar
diff --git a/SKILLs/content-planner/scripts/wechat_search.js b/SKILLs/content-planner/scripts/wechat_search.js
new file mode 100644
--- /dev/null
+++ b/SKILLs/content-planner/scripts/wechat_search.js
@@ -0,0 +1,367 @@
+#!/usr/bin/env node
+/**
+ * LobsterAI WeChat Article Search
+ * Searches Sogou WeChat index for public account articles.
+ *
+ * Dependencies: npm install -g cheerio
+ *
+ * Usage:
+ *   node wechat_search.js "keyword"
+ *   node wechat_search.js "keyword" -n 15
+ *   node wechat_search.js "keyword" -n 10 -o result.json
+ *   node wechat_search.js "keyword" -r          # resolve real mp.weixin URLs
+ */
+
+"use strict";
+
+const https = require("https");
+const zlib = require("zlib");
+const cheerio = require("cheerio");
+
+// -------------------------------------------------------------------------
+// User-Agent rotation
+// -------------------------------------------------------------------------
+
+const UA_LIST = [
+  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
+  "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
+  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Edg/125.0.0.0 Safari/537.36",
+  "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
+  "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_2_1) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15",
+  "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:126.0) Gecko/20100101 Firefox/126.0",
+  "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1",
+  "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36",
+];
+
+function randomUA() {
+  return UA_LIST[Math.floor(Math.random() * UA_LIST.length)];
+}
+
+const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
+
+// -------------------------------------------------------------------------
+// HTTP helpers
+// -------------------------------------------------------------------------
+
+function decompress(buf, encoding) {
+  if (!encoding) return buf;
+  const enc = String(encoding).toLowerCase();
+  try {
+    if (enc.includes("gzip")) return zlib.gunzipSync(buf);
+    if (enc.includes("deflate")) return zlib.inflateSync(buf);
+    if (enc.includes("br")) return zlib.brotliDecompressSync(buf);
+  } catch (_) {
+    /* fall through */
+  }
+  return buf;
+}
+
+function httpsGet(url, extraHeaders = {}, timeoutMs = 20000) {
+  return new Promise((resolve, reject) => {
+    const u = new URL(url);
+    const opts = {
+      hostname: u.hostname,
+      path: u.pathname + u.search,
+      method: "GET",
+      headers: {
+        Accept:
+          "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
+        "Accept-Encoding": "identity",
+        "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
+        Host: u.hostname,
+        Referer: `https://${u.hostname}/`,
+        "User-Agent": randomUA(),
+        ...extraHeaders,
+      },
+    };
+    const req = https.request(opts, (res) => {
+      const chunks = [];
+      res.on("data", (c) => chunks.push(c));
+      res.on("end", () => {
+        const raw = Buffer.concat(chunks);
+        const body = decompress(raw, res.headers["content-encoding"]);
+        resolve({
+          status: res.statusCode,
+          headers: res.headers,
+          body,
+          text: body.toString("utf-8"),
+        });
+      });
+    });
+    req.on("error", reject);
+    req.setTimeout(timeoutMs, () => {
+      req.destroy();
+      reject(new Error("timeout"));
+    });
+    req.end();
+  });
+}
+
+// -------------------------------------------------------------------------
+// Cookie helper (obtain SNUID from sogou video page)
+// -------------------------------------------------------------------------
+
+async function fetchSogouCookie() {
+  try {
+    const resp = await httpsGet(
+      "https://v.sogou.com/v?ie=utf8&query=&p=40030600",
+      {},
+      10000
+    );
+    const raw = resp.headers["set-cookie"];
+    if (!raw) return { str: "", obj: {} };
+    const obj = {};
+    raw.forEach((c) => {
+      const kv = c.split(";")[0];
+      const [k, v] = kv.split("=");
+      if (k && v) obj[k.trim()] = v.trim();
+    });
+    return { str: raw.map((c) => c.split(";")[0]).join("; "), obj };
+  } catch (_) {
+    return { str: "", obj: {} };
+  }
+}
+
+// -------------------------------------------------------------------------
+// Resolve real mp.weixin URL from sogou redirect page
+// -------------------------------------------------------------------------
+
+function extractRedirectUrl(html) {
+  // meta refresh
+  let m = html.match(
+    /<meta[^>]*http-equiv=["']refresh["'][^>]*content=["']\d+;\s*url=([^"']+)["']/i
+  );
+  if (m) return m[1];
+  // JS location
+  m =
+    html.match(/location\.href\s*=\s*["']([^"']+)["']/i) ||
+    html.match(/window\.location\s*=\s*["']([^"']+)["']/i);
+  if (m) return m[1];
+  // url += '...' concatenation pattern
+  const parts = [];
+  for (const p of html.matchAll(/url\s*\+=\s*'([^']*)'/g)) parts.push(p[1]);
+  for (const p of html.matchAll(/url\s*\+=\s*"([^"]*)"/g)) parts.push(p[1]);
+  if (parts.length) {
+    const joined = parts.join("");
+    if (joined.includes("mp.weixin.qq.com")) return joined;
+  }
+  return null;
+}
+
+async function resolveRealUrl(sogouUrl, cookieObj) {
+  if (!sogouUrl.includes("weixin.sogou.com")) return sogouUrl;
+  const snuid = cookieObj.SNUID || "";
+  const base =
+    "ABTEST=7|1716888919|v1; IPLOC=CN5101; ariaDefaultTheme=default";
+  const cookie = snuid ? `${base}; SNUID=${snuid}` : base;
+
+  for (let i = 0; i < 2; i++) {
+    try {
+      const resp = await httpsGet(sogouUrl, { Cookie: cookie }, 5000);
+      if (resp.status >= 300 && resp.status < 400 && resp.headers.location) {
+        const loc = resp.headers.location;
+        if (loc.includes("mp.weixin.qq.com")) return loc;
+      }
+      if (resp.status === 200) {
+        const redir = extractRedirectUrl(resp.text);
+        if (redir && redir.includes("mp.weixin.qq.com")) return redir;
+      }
+      return sogouUrl;
+    } catch (_) {
+      await sleep(800);
+    }
+  }
+  return sogouUrl;
+}
+
+// -------------------------------------------------------------------------
+// Parse search results
+// -------------------------------------------------------------------------
+
+function toChinaTime(date) {
+  const ct = new Date(date.getTime() + 8 * 3600000);
+  const y = ct.getUTCFullYear();
+  const mo = String(ct.getUTCMonth() + 1).padStart(2, "0");
+  const d = String(ct.getUTCDate()).padStart(2, "0");
+  const h = String(ct.getUTCHours()).padStart(2, "0");
+  const mi = String(ct.getUTCMinutes()).padStart(2, "0");
+  const s = String(ct.getUTCSeconds()).padStart(2, "0");
+  return `${y}-${mo}-${d} ${h}:${mi}:${s}`;
+}
+
+function relativeTimeLabel(ts) {
+  const diff = Date.now() - ts;
+  const mins = Math.floor(diff / 60000);
+  const hours = Math.floor(diff / 3600000);
+  const days = Math.floor(diff / 86400000);
+  if (days > 0) return `${days}天前`;
+  if (hours > 0) return `${hours}小时前`;
+  if (mins > 0) return `${mins}分钟前`;
+  return "刚刚";
+}
+
+function parseArticle($, el) {
+  const $el = $(el);
+  const $link = $el.find("h3 a");
+  if (!$link.length) return null;
+
+  const title = $link.text().trim();
+  let url = $link.attr("href") || "";
+  if (url.startsWith("/")) url = `https://weixin.sogou.com${url}`;
+
+  const summary = $el.find("p.txt-info").text().trim();
+
+  let datetime = "";
+  let timeDesc = "";
+  let source = "";
+
+  const $sp = $el.find(".s-p");
+  if ($sp.length) {
+    // timestamp from script tag
+    const script = $sp.find(".s2 script").text();
+    const tsMatch = script.match(/(\d{10})/);
+    if (tsMatch) {
+      const ts = parseInt(tsMatch[1]) * 1000;
+      datetime = toChinaTime(new Date(ts));
+      timeDesc = relativeTimeLabel(ts);
+    }
+    // source
+    const $src =
+      $sp.find(".all-time-y2").length > 0
+        ? $sp.find(".all-time-y2")
+        : $sp.find("a.account");
+    source = $src.text().trim();
+  }
+
+  return { title, url, summary, datetime, time_desc: timeDesc || datetime, source };
+}
+
+function parseSearchPage(html, max) {
+  const $ = cheerio.load(html);
+  const $list = $("ul.news-list");
+  if (!$list.length) return [];
+  const out = [];
+  $list.find("li").each((_, el) => {
+    if (out.length >= max) return false;
+    const a = parseArticle($, el);
+    if (a) out.push(a);
+  });
+  return out;
+}
+
+// -------------------------------------------------------------------------
+// Main search
+// -------------------------------------------------------------------------
+
+async function searchArticles(query, maxResults, shouldResolve) {
+  maxResults = Math.min(maxResults, 50);
+  const articles = [];
+  const pagesNeeded = Math.ceil(maxResults / 10);
+
+  for (let page = 1; page <= pagesNeeded && articles.length < maxResults; page++) {
+    try {
+      const { str: cookie } = await fetchSogouCookie();
+      const encoded = encodeURIComponent(query);
+      const url = `https://weixin.sogou.com/weixin?query=${encoded}&s_from=input&_sug_=n&type=2&page=${page}&ie=utf8`;
+      const resp = await httpsGet(url, cookie ? { Cookie: cookie } : {}, 30000);
+      const remaining = maxResults - articles.length;
+      const parsed = parseSearchPage(resp.text, remaining);
+      if (!parsed.length) break;
+      articles.push(...parsed);
+      if (page < pagesNeeded) await sleep(500 + Math.random() * 800);
+    } catch (err) {
+      console.error(`[第${page}页失败] ${err.message}`);
+      break;
+    }
+  }
+
+  const result = articles.slice(0, maxResults);
+
+  if (shouldResolve && result.length) {
+    console.error(`解析真实URL (${result.length}篇) ...`);
+    const { obj: cookieObj } = await fetchSogouCookie();
+    let ok = 0;
+    for (let i = 0; i < result.length; i++) {
+      const a = result[i];
+      const real = await resolveRealUrl(a.url, cookieObj);
+      const resolved = !real.includes("weixin.sogou.com");
+      if (resolved) {
+        a.url = real;
+        ok++;
+      }
+      a.url_resolved = resolved;
+      if (i < result.length - 1) await sleep(500 + Math.random() * 800);
+    }
+    console.error(`解析完成: 成功 ${ok}, 失败 ${result.length - ok}`);
+  }
+
+  return result;
+}
+
+// -------------------------------------------------------------------------
+// CLI
+// -------------------------------------------------------------------------
+
+function parseArgs(argv) {
+  let query = "";
+  let num = 10;
+  let output = "";
+  let resolve = false;
+
+  for (let i = 0; i < argv.length; i++) {
+    if (argv[i] === "-n" || argv[i] === "--num") {
+      num = parseInt(argv[++i]) || 10;
+    } else if (argv[i] === "-o" || argv[i] === "--output") {
+      output = argv[++i] || "";
+    } else if (argv[i] === "-r" || argv[i] === "--resolve-url") {
+      resolve = true;
+    } else if (!argv[i].startsWith("-")) {
+      query = argv[i];
+    }
+  }
+  return { query, num, output, resolve };
+}
+
+async function main() {
+  const { query, num, output, resolve } = parseArgs(process.argv.slice(2));
+
+  if (!query) {
+    console.log(`
+LobsterAI 微信公众号文章搜索
+
+用法:
+  node wechat_search.js <关键词> [选项]
+
+选项:
+  -n, --num <数量>       返回结果数 (默认10, 最大50)
+  -o, --output <文件>    输出JSON文件
+  -r, --resolve-url      解析真实微信URL
+
+示例:
+  node wechat_search.js "人工智能" -n 20
+  node wechat_search.js "ChatGPT" -o result.json
+`);
+    process.exit(0);
+  }
+
+  console.error(`搜索: "${query}" ...`);
+  const articles = await searchArticles(query, num, resolve);
+  const payload = { query, total: articles.length, articles };
+  const jsonStr = JSON.stringify(payload, null, 2);
+
+  if (output) {
+    require("fs").writeFileSync(output, jsonStr, "utf-8");
+    console.error(`已保存: ${output}`);
+  }
+
+  console.log(jsonStr);
+}
+
+module.exports = { searchArticles };
+
+if (require.main === module) {
+  main().catch((e) => {
+    console.error("搜索失败:", e.message);
+    process.exit(1);
+  });
+}
diff --git a/SKILLs/daily-trending/SKILL.md b/SKILLs/daily-trending/SKILL.md
new file mode 100644
--- /dev/null
+++ b/SKILLs/daily-trending/SKILL.md
@@ -0,0 +1,86 @@
+---
+name: daily-trending
+description: >-
+  Fetch today's trending topics from tophub.today across multiple platforms.
+  Triggered when users ask "what's trending today", "hot topics", "今日热搜", or "微博热搜".
+official: true
+---
+
+# Daily Trending
+
+Fetch today's trending topics by scraping data from various platforms via tophub.today.
+
+## Data Collection
+
+### Multi-Platform Trending Lists
+
+Fetch trending lists from the following platforms on tophub.today:
+- Zhihu Hot List: `/n/mproPpoq6O`
+- Weibo Trending: `/n/KqndgxeLl9`
+- Baidu Real-time Hot Topics: `/n/Jb0vmloB1G`
+- 36Kr 24-Hour Hot List: `/n/Q1Vd5Ko85R`
+- Huxiu Hot Articles: `/n/5VaobgvAj1`
+- The Paper Hot List: `/n/wWmoO5Rd4E`
+
+### Fetching Strategy
+
+**To avoid context overflow, fetch in batches with character limits!**
+
+**Option A: Core Platforms First (Recommended)**
+
+Use web-search skill or web_fetch to fetch only 2-3 core platforms:
+
+```
+web_fetch("https://tophub.today/n/KqndgxeLl9")  # Weibo
+web_fetch("https://tophub.today/n/mproPpoq6O")  # Zhihu
+web_fetch("https://tophub.today/n/Jb0vmloB1G")  # Baidu
+```
+
+**Fetching Priority:**
+1. Prioritize Weibo + Zhihu + Baidu (covers 90% of hot topics)
+2. Only fetch other platforms if suitable topics are not found in these 3
+3. Fetch one platform at a time, filter immediately, then decide whether to fetch the next
+
+### Filtering Criteria
+
+From all platform trending lists, filter out **truly important topics**:
+
+**Include:**
+- Major Events: Significant policies, international relations, social events
+- Hot Discussion Topics: Topics that spark widespread discussion
+- Factual Content: Keep the events themselves without commentary
+
+**Exclude:**
+- Headlines with subjective commentary
+- Pure entertainment gossip
+- Obvious promotional content
+- Emotional expressions
+
+**Output Requirements:**
+- Each news item must be complete with clear beginning and end
+- Describe events like news headlines
+- Avoid single words or incomplete fragments
+
+## Output Format
+
+Output only the 5 most valuable items:
+
+```
+======
+
+🔥 今日热搜（3月25日）
+
+1. [完整新闻标题1]
+2. [完整新闻标题2]
+3. [完整新闻标题3]
+4. [完整新闻标题4]
+5. [完整新闻标题5]
+
+======
+```
+
+Notes:
+- Each news item should be complete with clear beginning and end
+- No source attribution needed
+- Facts only, exclude subjective commentary
+- Output only the required content, no extra text
diff --git a/SKILLs/skills.config.json b/SKILLs/skills.config.json
--- a/SKILLs/skills.config.json
+++ b/SKILLs/skills.config.json
@@ -13,6 +13,12 @@
     "create-plan": { "order": 80, "enabled": true },
     "canvas-design": { "order": 90, "enabled": true },
     "frontend-design": { "order": 100, "enabled": true },
+    "stock-analyzer": { "order": 110, "enabled": true },
+    "stock-announcements": { "order": 111, "enabled": true },
+    "stock-explorer": { "order": 112, "enabled": true },
+    "content-planner": { "order": 120, "enabled": true },
+    "article-writer": { "order": 121, "enabled": true },
+    "daily-trending": { "order": 122, "enabled": true },
     "local-tools": { "order": 200, "enabled": true },
     "weather": { "order": 210, "enabled": true },
     "imap-smtp-email": { "order": 211, "enabled": true },
diff --git a/SKILLs/stock-analyzer/SKILL.md b/SKILLs/stock-analyzer/SKILL.md
new file mode 100644
--- /dev/null
+++ b/SKILLs/stock-analyzer/SKILL.md
@@ -0,0 +1,119 @@
+---
+name: stock-analyzer
+description: >-
+  A comprehensive stock deep analysis tool that combines real-time quotes, fundamental metrics,
+  technical indicators, and growth analysis into a single professional report.
+  Supports A-share, US stocks, HK stocks. Generates detailed investment recommendations
+  with risk assessment and actionable trading strategies.
+official: true
+---
+
+# Stock Deep Analyzer
+
+One-stop comprehensive stock analysis tool that generates professional-grade investment reports.
+
+## Features
+
+- **Real-time Market Data** — Current price, volume, market cap, beta
+- **Value Investing Metrics** — P/E, P/B, ROE, ROA, dividend yield, payout ratio
+- **Technical Indicators** — MA5/20/60, RSI, MACD, Bollinger Bands, VWAP
+- **Growth Analysis** — Revenue growth, earnings growth, profit margins
+- **Financial Health** — Asset/liability ratio, liquidity ratio
+- **Investment Rating** — Multi-dimensional scoring (value 35% / technical 25% / growth 25% / financial 15%)
+- **Trading Strategies** — Long-term hold, swing trade, short-term speculation
+- **Risk Assessment** — Key risks and price levels
+
+## Dependencies
+
+Python packages (install once):
+
+```bash
+pip install yfinance pandas numpy
+```
+
+## Usage
+
+**IMPORTANT:** Always use the `$SKILLS_ROOT` environment variable to locate scripts.
+
+### Basic Analysis
+
+```bash
+export PYTHONIOENCODING=utf-8
+python "$SKILLS_ROOT/stock-analyzer/scripts/analyze.py" 601288.SS
+```
+
+### Specify Analysis Period
+
+```bash
+export PYTHONIOENCODING=utf-8
+python "$SKILLS_ROOT/stock-analyzer/scripts/analyze.py" 000001.SZ --period 1y
+```
+
+### US Stocks
+
+```bash
+export PYTHONIOENCODING=utf-8
+python "$SKILLS_ROOT/stock-analyzer/scripts/analyze.py" AAPL
+```
+
+### Parameters
+
+| Parameter | Description | Example | Default |
+|-----------|-------------|---------|---------|
+| `ticker` | Stock ticker symbol (required) | 601288.SS, AAPL | - |
+| `--period` | Analysis period | 1mo, 3mo, 6mo, 1y, 2y | 6mo |
+| `--output` | Output format | text, json | text |
+
+## Stock Ticker Formats
+
+- **A-share (Shanghai)**: `600519.SS`, `601288.SS`
+- **A-share (Shenzhen)**: `000001.SZ`, `002594.SZ`
+- **US stocks**: `AAPL`, `TSLA`, `NVDA`
+- **HK stocks**: `0700.HK`, `9988.HK`
+
+## Output Structure
+
+The analysis report includes 8 sections:
+
+1. Real-time Market Overview
+2. Value Investing Indicators (Score /10)
+3. Technical Analysis (Score /10)
+4. Growth Indicators (Score /10)
+5. Financial Health (Score /10)
+6. Comprehensive Investment Rating (Overall /10)
+7. Recommended Trading Strategies
+8. Key Risk Warnings
+
+## Workflow
+
+When user requests stock analysis:
+
+1. **Identify ticker symbol**
+   - User may provide company name → use web-search to find ticker
+   - A-share: Shanghai = `.SS`, Shenzhen = `.SZ`
+
+2. **Execute analysis**
+   ```bash
+   export PYTHONIOENCODING=utf-8
+   python "$SKILLS_ROOT/stock-analyzer/scripts/analyze.py" <ticker>
+   ```
+
+3. **Interpret results**
+   - Extract overall rating and key findings
+   - Highlight investment recommendation
+   - Emphasize risk warnings
+   - Provide actionable price levels
+
+## Limitations
+
+- Yahoo Finance data quality varies by market
+- Some metrics may be N/A for loss-making companies
+- Historical data limited for newly listed stocks
+- Real-time quotes may have 15-min delay
+
+## When to Use This Skill
+
+- User requests "深度分析", "complete analysis", "comprehensive report"
+- User wants multi-dimensional evaluation (value + growth + technical)
+- User needs actionable trading strategies
+- User asks for investment recommendations with risk assessment
diff --git a/SKILLs/stock-analyzer/scripts/analyze.py b/SKILLs/stock-analyzer/scripts/analyze.py
new file mode 100644
--- /dev/null
+++ b/SKILLs/stock-analyzer/scripts/analyze.py
@@ -0,0 +1,325 @@
+#!/usr/bin/env python3
+# -*- coding: utf-8 -*-
+"""
+LobsterAI Stock Deep Analyzer
+Comprehensive multi-dimensional stock analysis using Yahoo Finance data.
+Produces value, technical, growth, and financial health scores.
+
+Dependencies: pip install yfinance pandas numpy
+"""
+
+import sys
+import argparse
+from datetime import datetime
+
+import numpy as np
+import pandas as pd
+import yfinance as yf
+
+
+# ---------------------------------------------------------------------------
+# Technical helpers
+# ---------------------------------------------------------------------------
+
+def rsi(series: pd.Series, period: int = 14) -> pd.Series:
+    diff = series.diff()
+    up = diff.clip(lower=0).rolling(period).mean()
+    down = (-diff.clip(upper=0)).rolling(period).mean()
+    return 100 - 100 / (1 + up / down.replace(0, np.nan))
+
+
+def macd(series: pd.Series):
+    fast = series.ewm(span=12).mean()
+    slow = series.ewm(span=26).mean()
+    line = fast - slow
+    signal = line.ewm(span=9).mean()
+    return line, signal, line - signal
+
+
+def bollinger(series: pd.Series, window: int = 20, width: float = 2.0):
+    mid = series.rolling(window).mean()
+    std = series.rolling(window).std()
+    return mid + width * std, mid, mid - width * std
+
+
+def vwap(df: pd.DataFrame) -> pd.Series:
+    tp = (df["High"] + df["Low"] + df["Close"]) / 3
+    vol = df["Volume"].fillna(0)
+    return (tp * vol).cumsum() / vol.cumsum().replace(0, np.nan)
+
+
+# ---------------------------------------------------------------------------
+# Scoring
+# ---------------------------------------------------------------------------
+
+def score_value(info: dict) -> tuple:
+    pts = 0
+    pe = info.get("trailingPE")
+    pb = info.get("priceToBook")
+    roe = info.get("returnOnEquity")
+    dy = info.get("dividendYield")
+    margin = info.get("profitMargins")
+
+    if pe and pe < 15:
+        pts += 2
+    if pb and pb < 3:
+        pts += 2
+        if pb < 1:
+            pts += 1
+    if roe and roe > 0.10:
+        pts += 2
+    if dy and dy > 0.02:
+        pts += 2
+    if margin and margin > 0.10:
+        pts += 1
+    return min(pts, 10)
+
+
+def score_technical(price: float, close: pd.Series, hist: pd.DataFrame) -> int:
+    pts = 0
+    ma5 = close.rolling(5).mean().iloc[-1]
+    ma20 = close.rolling(20).mean().iloc[-1]
+
+    if price > ma5 > ma20:
+        pts += 2
+
+    r = rsi(close).iloc[-1]
+    if 30 < r < 70:
+        pts += 2
+    elif r <= 30:
+        pts += 1
+
+    ml, ms, _ = macd(close)
+    if ml.iloc[-1] > ms.iloc[-1]:
+        pts += 2
+
+    upper, _, lower = bollinger(close)
+    if lower.iloc[-1] < price < upper.iloc[-1]:
+        pts += 2
+
+    v = vwap(hist).iloc[-1]
+    if price > v:
+        pts += 2
+
+    return min(pts, 10)
+
+
+def score_growth(info: dict) -> int:
+    pts = 0
+    rg = info.get("revenueGrowth")
+    eg = info.get("earningsGrowth")
+    margin = info.get("profitMargins")
+
+    if rg and rg > 0.05:
+        pts += 2
+        if rg > 0.10:
+            pts += 1
+    if eg and eg > 0.10:
+        pts += 3
+        if eg > 0.20:
+            pts += 2
+    if margin and margin > 0.15:
+        pts += 2
+    return min(pts, 10)
+
+
+def score_financial(info: dict) -> int:
+    pts = 5  # base
+    de = info.get("debtToEquity")
+    cr = info.get("currentRatio")
+    if de is not None and de < 100:
+        pts += 2
+    if cr and cr > 1.5:
+        pts += 2
+        if cr > 2.0:
+            pts += 1
+    return min(pts, 10)
+
+
+# ---------------------------------------------------------------------------
+# Risk scan
+# ---------------------------------------------------------------------------
+
+def scan_risks(info: dict, price: float, close: pd.Series) -> list:
+    risks = []
+    pe = info.get("trailingPE")
+    pb = info.get("priceToBook")
+    roe = info.get("returnOnEquity")
+    de = info.get("debtToEquity")
+    rg = info.get("revenueGrowth")
+
+    if pe and pe > 30:
+        risks.append(f"高估值 (P/E={pe:.1f})")
+    if pb and pb > 5:
+        risks.append(f"市净率偏高 (P/B={pb:.1f})")
+    if roe and roe < 0:
+        risks.append("ROE 为负，公司亏损")
+    r = rsi(close).iloc[-1]
+    if r > 70:
+        risks.append(f"技术面超买 (RSI={r:.1f})")
+    upper, _, _ = bollinger(close)
+    if price > upper.iloc[-1]:
+        risks.append("价格突破布林带上轨")
+    if de is not None and de > 200:
+        risks.append(f"高负债 (D/E={de:.0f}%)")
+    if rg and rg < 0:
+        risks.append("营收负增长")
+    return risks
+
+
+# ---------------------------------------------------------------------------
+# Report renderer
+# ---------------------------------------------------------------------------
+
+SEP = "─" * 56
+
+
+def _fmt(label: str, key: str, info: dict, is_pct: bool = False):
+    val = info.get(key)
+    if val is not None:
+        display = f"{val*100:.2f}%" if is_pct else f"{val:.2f}"
+        print(f"  {label}: {display}")
+    else:
+        print(f"  {label}: N/A")
+
+
+def render_report(ticker_symbol: str, period: str):
+    stock = yf.Ticker(ticker_symbol)
+    info = stock.info
+    hist = stock.history(period=period)
+
+    if hist.empty:
+        print(f"[错误] 无法获取 {ticker_symbol} 的历史数据")
+        return None
+
+    close = hist["Close"]
+    cur = info.get("currentPrice") or close.iloc[-1]
+    chg = info.get("regularMarketChange", 0)
+    chg_pct = info.get("regularMarketChangePercent", 0)
+    name = info.get("longName", ticker_symbol)
+    currency = info.get("currency", "")
+
+    # Header
+    print(f"\n{SEP}")
+    print(f"  {name} ({ticker_symbol}) 深度分析报告")
+    print(SEP)
+
+    # 1 - Market overview
+    print(f"\n▸ 实时行情")
+    print(f"  价格  {cur:,.2f} {currency}  ({chg:+.2f}, {chg_pct:+.2f}%)")
+    mcap = info.get("marketCap")
+    if mcap:
+        print(f"  市值  {mcap/1e8:,.0f} 亿{currency}")
+    lo52 = info.get("fiftyTwoWeekLow", "–")
+    hi52 = info.get("fiftyTwoWeekHigh", "–")
+    print(f"  52周  {lo52} – {hi52}")
+    vol = info.get("volume")
+    if vol:
+        print(f"  成交量 {vol:,}")
+
+    # 2 - Value
+    vs = score_value(info)
+    print(f"\n▸ 价值评估  {vs}/10")
+    _fmt("P/E", "trailingPE", info)
+    _fmt("P/B", "priceToBook", info)
+    _fmt("ROE", "returnOnEquity", info, True)
+    _fmt("ROA", "returnOnAssets", info, True)
+    _fmt("EPS", "trailingEps", info)
+    _fmt("股息率", "dividendYield", info, True)
+
+    # 3 - Technical
+    ts = score_technical(cur, close, hist)
+    print(f"\n▸ 技术分析  {ts}/10")
+    ma5 = close.rolling(5).mean().iloc[-1]
+    ma20 = close.rolling(20).mean().iloc[-1]
+    ma60 = close.rolling(60).mean().iloc[-1] if len(close) >= 60 else float("nan")
+    print(f"  MA5={ma5:.2f}  MA20={ma20:.2f}  MA60={'%.2f' % ma60 if not np.isnan(ma60) else 'N/A'}")
+    r = rsi(close).iloc[-1]
+    ml, ms, mh = macd(close)
+    print(f"  RSI(14)={r:.1f}  MACD={ml.iloc[-1]:.4f}  信号={ms.iloc[-1]:.4f}")
+    upper, mid, lower = bollinger(close)
+    bb_pos = (cur - lower.iloc[-1]) / (upper.iloc[-1] - lower.iloc[-1]) * 100
+    print(f"  布林带  上={upper.iloc[-1]:.2f}  中={mid.iloc[-1]:.2f}  下={lower.iloc[-1]:.2f}  位置={bb_pos:.0f}%")
+
+    # 4 - Growth
+    gs = score_growth(info)
+    print(f"\n▸ 成长性  {gs}/10")
+    _fmt("营收增长", "revenueGrowth", info, True)
+    _fmt("利润增长", "earningsGrowth", info, True)
+    _fmt("利润率", "profitMargins", info, True)
+
+    # 5 - Financial health
+    fs = score_financial(info)
+    print(f"\n▸ 财务健康  {fs}/10")
+    _fmt("资产负债率", "debtToEquity", info)
+    _fmt("流动比率", "currentRatio", info)
+
+    # 6 - Overall
+    overall = vs * 0.35 + ts * 0.25 + gs * 0.25 + fs * 0.15
+    label = (
+        "强烈推荐" if overall >= 8 else
+        "推荐买入" if overall >= 6.5 else
+        "持有观望" if overall >= 5 else
+        "谨慎操作" if overall >= 3 else
+        "建议回避"
+    )
+    print(f"\n{SEP}")
+    print(f"  综合评分  {overall:.1f}/10  【{label}】")
+    print(f"  (价值{vs} × 35% + 技术{ts} × 25% + 成长{gs} × 25% + 财务{fs} × 15%)")
+    print(SEP)
+
+    # 7 - Strategies
+    print(f"\n▸ 操作建议")
+    bv = info.get("bookValue")
+    if vs >= 7 and overall >= 6:
+        target = bv * 1.1 if bv else cur * 1.2
+        print(f"  长线  仓位20-30%  目标 {target:.2f}  周期1-3年")
+
+    if ts >= 5:
+        print(f"  波段  买入区 {lower.iloc[-1]:.2f}–{mid.iloc[-1]:.2f}  止盈区 {mid.iloc[-1]:.2f}–{upper.iloc[-1]:.2f}")
+        print(f"        止损 {lower.iloc[-1]*0.95:.2f}")
+
+    if r < 30:
+        print(f"  短线  超卖反弹机会  目标 +5%  止损 -3%")
+    elif r > 70:
+        print(f"  短线  超买区域，回避追高")
+
+    # 8 - Risks
+    risks = scan_risks(info, cur, close)
+    print(f"\n▸ 风险提示")
+    if risks:
+        for rk in risks:
+            print(f"  ⚠ {rk}")
+    else:
+        print("  未发现重大风险信号")
+
+    print(f"\n{SEP}")
+    print(f"  报告时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
+    print(SEP)
+
+    return {
+        "ticker": ticker_symbol, "overall": round(overall, 1),
+        "value": vs, "technical": ts, "growth": gs, "financial": fs,
+        "rating": label, "price": cur, "risks": risks,
+    }
+
+
+# ---------------------------------------------------------------------------
+# CLI
+# ---------------------------------------------------------------------------
+
+def main():
+    ap = argparse.ArgumentParser(description="LobsterAI Stock Deep Analyzer")
+    ap.add_argument("ticker", help="股票代码 (如 601288.SS, AAPL)")
+    ap.add_argument("--period", default="6mo", help="分析周期 (1mo/3mo/6mo/1y/2y)")
+    ap.add_argument("--output", default="text", choices=["text", "json"])
+    args = ap.parse_args()
+
+    result = render_report(args.ticker, args.period)
+    if args.output == "json" and result:
+        import json
+        print(json.dumps(result, ensure_ascii=False, indent=2))
+
+
+if __name__ == "__main__":
+    main()
diff --git a/SKILLs/stock-announcements/SKILL.md b/SKILLs/stock-announcements/SKILL.md
new file mode 100644
--- /dev/null
+++ b/SKILLs/stock-announcements/SKILL.md
@@ -0,0 +1,113 @@
+---
+name: stock-announcements
+description: >-
+  获取A股上市公司公告信息（真实数据）。基于AkShare从东方财富网获取当日全部公告，支持按股票代码筛选、关键词过滤。
+  适用于监控重大事件、业绩快报、股东变动、重组公告等投资决策关键信息。数据源：东方财富网（稳定可靠）。
+official: true
+---
+
+# Stock Announcement Fetcher
+
+获取A股上市公司的官方公告信息（真实数据），帮助投资者及时掌握重要信息披露。
+
+## 真实数据保证
+
+- **数据来源：** 东方财富网（通过AkShare开源库）
+- **更新频率：** 实时（当日公告）
+- **覆盖范围：** 全部A股上市公司
+- **数据质量：** 官方权威数据
+
+## Dependencies
+
+Python packages (install once):
+
+```bash
+pip install akshare pandas requests PyPDF2
+```
+
+## When to Use This Skill
+
+触发条件（用户提及以下任一场景时激活）：
+
+1. **查询特定公司公告** — "查看五粮液最近的公告"、"002368有什么新公告？"
+2. **监控特定事件** — "哪些公司今天发布了业绩预告？"
+3. **投资决策辅助** — "公司有利好消息吗？"
+
+## Usage
+
+**IMPORTANT:** Always use the `$SKILLS_ROOT` environment variable to locate scripts.
+
+### 基础查询
+
+```bash
+export PYTHONIOENCODING=utf-8
+python "$SKILLS_ROOT/stock-announcements/scripts/announcements.py" 000858
+```
+
+### 查询最近7天
+
+```bash
+export PYTHONIOENCODING=utf-8
+python "$SKILLS_ROOT/stock-announcements/scripts/announcements.py" 600519 --days 7
+```
+
+### 关键词筛选
+
+```bash
+export PYTHONIOENCODING=utf-8
+python "$SKILLS_ROOT/stock-announcements/scripts/announcements.py" 600519 --keyword 业绩
+```
+
+### JSON格式输出
+
+```bash
+export PYTHONIOENCODING=utf-8
+python "$SKILLS_ROOT/stock-announcements/scripts/announcements.py" 000858 --format json
+```
+
+### 提取PDF内容并总结
+
+```bash
+export PYTHONIOENCODING=utf-8
+python "$SKILLS_ROOT/stock-announcements/scripts/announcements.py" 000858 --detail
+```
+
+## Parameters
+
+| 参数 | 说明 | 示例 | 默认值 |
+|------|------|------|--------|
+| `stock_code` | 股票代码（必填） | 000001, 600000.SS | - |
+| `--days` | 最近N天 | 7 | 30 |
+| `--format` | 输出格式 | json/text | text |
+| `--keyword` | 标题关键词筛选 | 业绩 | None |
+| `--detail` | 提取PDF内容并总结 | — | false |
+
+## Workflow
+
+### Step 1: 识别股票代码
+
+用户可能提供以下任一格式：
+- 公司名称："五粮液" → 先用 web-search 查询股票代码
+- Yahoo Finance格式："000858.SZ" → 提取纯数字代码
+- 纯代码："000858" → 直接传递
+
+### Step 2: 执行查询
+
+```bash
+export PYTHONIOENCODING=utf-8
+python "$SKILLS_ROOT/stock-announcements/scripts/announcements.py" <股票代码> [参数]
+```
+
+### Step 3: 解读结果
+
+Agent 应该：
+1. 提取关键信息（标题、类型、日期）
+2. 分类汇总（业绩类、股东类、重大合同等）
+3. 标注重要性（🔴高/🟡中/⚪低）
+4. 提供简洁解读
+
+## Limitations
+
+1. **只能查询当日公告** — AkShare 的 `stock_notice_report` 接口只返回指定日期的全部公告
+2. **查询速度约7-10秒** — 需遍历1000+条公告
+3. **中文显示乱码** — Windows PowerShell GBK编码问题，使用 `--format json` 可规避
diff --git a/SKILLs/stock-announcements/scripts/announcements.py b/SKILLs/stock-announcements/scripts/announcements.py
new file mode 100644
--- /dev/null
+++ b/SKILLs/stock-announcements/scripts/announcements.py
@@ -0,0 +1,188 @@
+#!/usr/bin/env python3
+# -*- coding: utf-8 -*-
+"""
+LobsterAI Stock Announcement Fetcher
+Fetches A-share company announcements from Eastmoney via AkShare.
+
+Dependencies: pip install akshare pandas requests PyPDF2
+"""
+
+import sys
+import io
+import re
+import json
+import argparse
+from datetime import datetime, timedelta
+
+import pandas as pd
+import requests
+
+# Ensure UTF-8 stdout on Windows
+if sys.stdout.encoding != "utf-8":
+    import codecs
+    sys.stdout = codecs.getwriter("utf-8")(sys.stdout.buffer, "strict")
+    sys.stderr = codecs.getwriter("utf-8")(sys.stderr.buffer, "strict")
+
+
+def _log(msg: str):
+    print(msg, file=sys.stderr)
+
+
+# ---------------------------------------------------------------------------
+# Data fetching
+# ---------------------------------------------------------------------------
+
+def query_announcements(code: str, days: int = 30) -> list:
+    """Fetch announcements for *code* from Eastmoney via AkShare."""
+    try:
+        import akshare as ak
+    except ImportError:
+        _log("[错误] akshare 未安装，请运行: pip install akshare")
+        return []
+
+    # Normalise code - strip exchange suffix
+    code = code.split(".")[0]
+    end = datetime.now()
+    start = end - timedelta(days=days)
+    date_str = end.strftime("%Y%m%d")
+
+    _log(f"[1/2] 从东方财富获取 {date_str} 全部公告 ...")
+    try:
+        df = ak.stock_notice_report(symbol="全部", date=date_str)
+    except Exception as exc:
+        _log(f"[错误] AkShare 调用失败: {exc}")
+        return []
+
+    if df is None or df.empty:
+        _log("  → 当日无公告数据")
+        return []
+
+    cols = list(df.columns)
+    _log(f"  → 获取 {len(df)} 条，筛选 {code} ...")
+
+    matched = df[df[cols[0]] == code]
+    if matched.empty:
+        _log(f"  → 未找到 {code} 的公告")
+        return []
+
+    results = []
+    for _, row in matched.iterrows():
+        ann_date = str(row[cols[4]])
+        if ann_date < start.strftime("%Y-%m-%d"):
+            continue
+        url = str(row[cols[5]])
+        ann_id = url.rstrip("/").split("/")[-1].replace(".html", "")
+        results.append({
+            "date": ann_date,
+            "title": str(row[cols[2]]),
+            "type": str(row[cols[3]]),
+            "url": url,
+            "pdf_url": f"http://pdf.dfcfw.com/pdf/H2_{ann_id}_1.pdf",
+            "code": str(row[cols[0]]),
+            "name": str(row[cols[1]]),
+        })
+
+    _log(f"[2/2] 匹配到 {len(results)} 条公告\n")
+    return results
+
+
+# ---------------------------------------------------------------------------
+# PDF extraction (optional --detail)
+# ---------------------------------------------------------------------------
+
+def extract_pdf_summary(pdf_url: str, title: str):
+    """Download a PDF and return a short summary."""
+    try:
+        from PyPDF2 import PdfReader
+    except ImportError:
+        _log("[提示] PyPDF2 未安装，跳过 PDF 提取")
+        return None
+
+    try:
+        _log(f"  下载 PDF ...")
+        resp = requests.get(pdf_url, timeout=15)
+        resp.raise_for_status()
+        reader = PdfReader(io.BytesIO(resp.content))
+        pages_text = []
+        for page in reader.pages[:5]:
+            txt = page.extract_text()
+            if txt:
+                pages_text.append(txt)
+        body = re.sub(r"\s+", " ", " ".join(pages_text)).strip()
+        if len(body) < 50:
+            return None
+
+        # Pick sentences containing keywords
+        keywords = ("通知", "决定", "变更", "任命", "辞职", "增持", "减持",
+                     "业绩", "利润", "营收", "净利", "合同", "投资", "收购",
+                     "重组", "分红", "股东")
+        sentences = re.split(r"[。！？\n]", body)
+        picked = [s.strip() for s in sentences if 15 < len(s.strip()) < 200
+                   and any(k in s for k in keywords)][:5]
+        if picked:
+            return "  ".join(f"({i+1}) {s}" for i, s in enumerate(picked))
+        return body[:300] + " ..."
+    except Exception as exc:
+        _log(f"  PDF 提取失败: {exc}")
+        return None
+
+
+# ---------------------------------------------------------------------------
+# Output
+# ---------------------------------------------------------------------------
+
+def print_text(items: list, detail: bool = False):
+    if not items:
+        print("\n未找到匹配的公告。")
+        return
+    first = items[0]
+    print(f"\n{'─'*60}")
+    print(f"  {first.get('name', '')} ({first['code']})  共 {len(items)} 条公告")
+    print(f"{'─'*60}\n")
+
+    for i, a in enumerate(items, 1):
+        print(f"  [{i}] {a['date']}  {a['title']}")
+        if a.get("type"):
+            print(f"      类型: {a['type']}")
+        print(f"      链接: {a['url']}")
+        if detail and a.get("summary"):
+            print(f"      摘要: {a['summary']}")
+        print()
+
+
+def print_json(items: list):
+    print(json.dumps(items, ensure_ascii=False, indent=2))
+
+
+# ---------------------------------------------------------------------------
+# CLI
+# ---------------------------------------------------------------------------
+
+def main():
+    ap = argparse.ArgumentParser(description="LobsterAI A股公告查询")
+    ap.add_argument("stock_code", help="股票代码 (如 000858, 600519.SS)")
+    ap.add_argument("--days", type=int, default=30, help="查询最近N天 (默认30)")
+    ap.add_argument("--keyword", default=None, help="标题关键词筛选")
+    ap.add_argument("--format", choices=["text", "json"], default="text")
+    ap.add_argument("--detail", action="store_true", help="提取PDF内容摘要")
+    args = ap.parse_args()
+
+    items = query_announcements(args.stock_code, days=args.days)
+
+    if args.keyword:
+        items = [a for a in items if args.keyword in a["title"]]
+
+    if args.detail:
+        for a in items:
+            s = extract_pdf_summary(a["pdf_url"], a["title"])
+            if s:
+                a["summary"] = s
+
+    if args.format == "json":
+        print_json(items)
+    else:
+        print_text(items, detail=args.detail)
+
+
+if __name__ == "__main__":
+    main()
diff --git a/SKILLs/stock-explorer/SKILL.md b/SKILLs/stock-explorer/SKILL.md
new file mode 100644
--- /dev/null
+++ b/SKILLs/stock-explorer/SKILL.md
@@ -0,0 +1,89 @@
+---
+name: stock-explorer
+description: >-
+  A Yahoo Finance (yfinance) powered financial analysis tool.
+  Get real-time quotes, generate technical indicator reports (RSI/MACD/Bollinger/VWAP/ATR),
+  summarize fundamentals, and run a one-shot report that outputs a text summary.
+official: true
+---
+
+# Stock Information Explorer
+
+This skill fetches OHLCV data from Yahoo Finance via `yfinance` and computes technical indicators **locally** (no API key required).
+
+## Dependencies
+
+Python packages (install once):
+
+```bash
+pip install yfinance rich pandas plotille
+```
+
+## Commands
+
+**IMPORTANT:** Always use the `$SKILLS_ROOT` environment variable to locate scripts.
+
+### 1) Real-time Quotes (`price`)
+
+```bash
+python "$SKILLS_ROOT/stock-explorer/scripts/quote.py" price TSLA
+# shorthand
+python "$SKILLS_ROOT/stock-explorer/scripts/quote.py" TSLA
+```
+
+### 2) Fundamental Summary (`fundamentals`)
+
+```bash
+python "$SKILLS_ROOT/stock-explorer/scripts/quote.py" fundamentals NVDA
+```
+
+### 3) ASCII Trend (`history`)
+
+```bash
+python "$SKILLS_ROOT/stock-explorer/scripts/quote.py" history AAPL 6mo
+```
+
+### 4) Professional Analysis (`pro`)
+
+输出详细的技术指标文本分析报告。
+
+```bash
+# 基础分析（价格区间）
+python "$SKILLS_ROOT/stock-explorer/scripts/quote.py" pro 002368.SZ 6mo
+
+# 带技术指标
+export PYTHONIOENCODING=utf-8
+python "$SKILLS_ROOT/stock-explorer/scripts/quote.py" pro 002368.SZ 6mo --rsi --macd --bb
+```
+
+#### 可用指标 (optional)
+
+- `--rsi` : RSI(14) - 超买超卖指标
+- `--macd`: MACD(12,26,9) - 趋势动量指标
+- `--bb`  : Bollinger Bands(20,2) - 布林带
+- `--vwap`: VWAP - 成交量加权均价
+- `--atr` : ATR(14) - 平均真实波幅
+
+### 5) One-shot Report (`report`)
+
+输出综合分析报告（行情+基本面+技术信号）。
+
+```bash
+export PYTHONIOENCODING=utf-8
+python "$SKILLS_ROOT/stock-explorer/scripts/quote.py" report 000660.KS 6mo
+```
+
+## Ticker Examples
+
+- A-share: `600519.SS`, `000001.SZ`
+- US stocks: `AAPL`, `NVDA`, `TSLA`
+- HK stocks: `0700.HK`, `9988.HK`
+- Crypto: `BTC-USD`, `ETH-KRW`
+- Forex: `USDKRW=X`
+
+## Notes / Limitations
+
+- Indicators are **computed locally** from price data
+- Data quality may vary by ticker/market
+- 所有输出均为文本格式
+- Windows 环境中文显示需设置 `export PYTHONIOENCODING=utf-8`
diff --git a/SKILLs/stock-explorer/scripts/quote.py b/SKILLs/stock-explorer/scripts/quote.py
new file mode 100644
--- /dev/null
+++ b/SKILLs/stock-explorer/scripts/quote.py
@@ -0,0 +1,250 @@
+#!/usr/bin/env python3
+# -*- coding: utf-8 -*-
+"""
+LobsterAI Stock Explorer
+Quick stock quotes, fundamentals, technical indicators via Yahoo Finance.
+
+Dependencies: pip install yfinance pandas rich plotille
+"""
+
+import sys
+import argparse
+
+# Ensure UTF-8 on Windows
+if sys.stdout.encoding != "utf-8":
+    import codecs
+    sys.stdout = codecs.getwriter("utf-8")(sys.stdout.buffer, "strict")
+    sys.stderr = codecs.getwriter("utf-8")(sys.stderr.buffer, "strict")
+
+import yfinance as yf
+import pandas as pd
+import plotille
+from rich.console import Console
+from rich.table import Table
+from rich.panel import Panel
+
+console = Console()
+
+# ---------------------------------------------------------------------------
+# Technical indicator helpers
+# ---------------------------------------------------------------------------
+
+def _rsi(close, w=14):
+    d = close.diff()
+    g = d.clip(lower=0).ewm(alpha=1/w, adjust=False, min_periods=w).mean()
+    l = (-d.clip(upper=0)).ewm(alpha=1/w, adjust=False, min_periods=w).mean()
+    return 100 - 100 / (1 + g / l.replace(0, pd.NA))
+
+
+def _macd(close):
+    f = close.ewm(span=12, adjust=False, min_periods=12).mean()
+    s = close.ewm(span=26, adjust=False, min_periods=26).mean()
+    line = f - s
+    sig = line.ewm(span=9, adjust=False, min_periods=9).mean()
+    return line, sig, line - sig
+
+
+def _bbands(close, w=20, n=2.0):
+    ma = close.rolling(w, min_periods=w).mean()
+    sd = close.rolling(w, min_periods=w).std(ddof=0)
+    return ma + n * sd, ma, ma - n * sd
+
+
+def _vwap(df):
+    tp = (df["High"] + df["Low"] + df["Close"]) / 3
+    v = df["Volume"].fillna(0)
+    return (tp * v).cumsum() / v.cumsum().replace(0, pd.NA)
+
+
+def _atr(df, w=14):
+    h, l, c = df["High"], df["Low"], df["Close"]
+    pc = c.shift(1)
+    tr = pd.concat([(h - l), (h - pc).abs(), (l - pc).abs()], axis=1).max(axis=1)
+    return tr.ewm(alpha=1/w, adjust=False, min_periods=w).mean()
+
+
+# ---------------------------------------------------------------------------
+# Fetch helper
+# ---------------------------------------------------------------------------
+
+def _get_ticker(symbol):
+    t = yf.Ticker(symbol)
+    try:
+        info = t.info
+        if not info or (not info.get("regularMarketPrice") and not info.get("currentPrice")):
+            if not info.get("symbol"):
+                return None, None
+        return t, info
+    except Exception:
+        return None, None
+
+
+# ---------------------------------------------------------------------------
+# Commands
+# ---------------------------------------------------------------------------
+
+def cmd_price(symbol, ticker, info):
+    cur = info.get("regularMarketPrice") or info.get("currentPrice")
+    prev = info.get("regularMarketPreviousClose") or info.get("previousClose")
+    if cur is None:
+        return
+    chg = cur - prev
+    pct = chg / prev * 100
+    color = "green" if chg >= 0 else "red"
+    sign = "+" if chg >= 0 else ""
+
+    tbl = Table(title=f"{info.get('longName', symbol)}")
+    tbl.add_column("指标", style="cyan")
+    tbl.add_column("值", style="magenta")
+    tbl.add_row("代码", symbol)
+    tbl.add_row("价格", f"{cur:,.2f} {info.get('currency', '')}")
+    tbl.add_row("涨跌", f"[{color}]{sign}{chg:,.2f} ({sign}{pct:.2f}%)[/{color}]")
+    console.print(tbl)
+
+
+def cmd_fundamentals(symbol, ticker, info):
+    tbl = Table(title=f"{info.get('longName', symbol)} 基本面")
+    tbl.add_column("指标", style="cyan")
+    tbl.add_column("值", style="magenta")
+    for label, key in [("市值", "marketCap"), ("市盈率", "forwardPE"),
+                        ("EPS", "trailingEps"), ("ROE", "returnOnEquity")]:
+        tbl.add_row(label, str(info.get(key, "N/A")))
+    console.print(tbl)
+
+
+def cmd_history(symbol, ticker, period):
+    hist = ticker.history(period=period)
+    if hist.empty:
+        print("无历史数据")
+        return
+    chart = plotille.plot(hist.index, hist["Close"], height=15, width=60)
+    console.print(Panel(chart, title=f"{symbol} 走势", border_style="green"))
+
+
+def cmd_pro(symbol, ticker, period, indicators):
+    hist = ticker.history(period=period)
+    if hist.empty:
+        print("无历史数据")
+        return
+
+    close = hist["Close"]
+    cur = close.iloc[-1]
+    hi = hist["High"].max()
+    lo = hist["Low"].min()
+    start_price = close.iloc[0]
+    change_pct = (cur - start_price) / start_price * 100
+
+    lines = []
+    lines.append(f"\n{'─'*56}")
+    lines.append(f"  {symbol} 技术分析 ({period})")
+    lines.append(f"{'─'*56}")
+    lines.append(f"\n  当前 {cur:.2f}  区间 {lo:.2f}–{hi:.2f}  涨幅 {change_pct:+.1f}%")
+
+    if indicators.get("rsi"):
+        val = _rsi(close).iloc[-1]
+        tag = "超买" if val > 70 else ("超卖" if val < 30 else "中性")
+        lines.append(f"\n  RSI(14): {val:.1f}  [{tag}]")
+
+    if indicators.get("macd"):
+        ml, ms, mh = _macd(close)
+        tag = "多头" if ml.iloc[-1] > ms.iloc[-1] else "空头"
+        lines.append(f"\n  MACD: {ml.iloc[-1]:.3f}  信号: {ms.iloc[-1]:.3f}  [{tag}]")
+
+    if indicators.get("bb"):
+        u, m, l = _bbands(close)
+        pos = (cur - l.iloc[-1]) / (u.iloc[-1] - l.iloc[-1]) * 100
+        tag = "上轨" if pos > 80 else ("下轨" if pos < 20 else "中轨")
+        lines.append(f"\n  布林带  上={u.iloc[-1]:.2f}  中={m.iloc[-1]:.2f}  下={l.iloc[-1]:.2f}  位置={pos:.0f}%  [{tag}]")
+
+    if indicators.get("vwap"):
+        val = _vwap(hist).iloc[-1]
+        tag = "高于" if cur > val else "低于"
+        lines.append(f"\n  VWAP: {val:.2f}  价格{tag}VWAP")
+
+    if indicators.get("atr"):
+        val = _atr(hist).iloc[-1]
+        lines.append(f"\n  ATR(14): {val:.2f}  ({val/cur*100:.2f}%)")
+
+    lines.append(f"\n{'─'*56}")
+    print("\n".join(lines))
+
+
+def cmd_report(symbol, ticker, info, period):
+    cur = info.get("regularMarketPrice") or info.get("currentPrice")
+    prev = info.get("regularMarketPreviousClose") or info.get("previousClose")
+    chg = cur - prev if cur and prev else 0
+    pct = chg / prev * 100 if prev else 0
+    sign = "+" if chg >= 0 else ""
+
+    hist = ticker.history(period=period)
+    if hist.empty:
+        print("无历史数据")
+        return
+
+    close = hist["Close"]
+    r = _rsi(close).iloc[-1]
+    u, m, l = _bbands(close)
+    bb_pos = (close.iloc[-1] - l.iloc[-1]) / (u.iloc[-1] - l.iloc[-1]) * 100
+    ml, ms, _ = _macd(close)
+
+    r_tag = "超买" if r > 70 else ("超卖" if r < 30 else "中性")
+    bb_tag = "上轨" if bb_pos > 80 else ("下轨" if bb_pos < 20 else "中轨")
+    m_tag = "多头" if ml.iloc[-1] > ms.iloc[-1] else "空头"
+
+    mcap = info.get("marketCap", 0)
+    pe = info.get("forwardPE", "N/A")
+
+    print(f"\n{'─'*56}")
+    print(f"  {info.get('longName', symbol)} 综合报告")
+    print(f"{'─'*56}")
+    print(f"\n  价格 {cur:,.2f}  {sign}{chg:,.2f} ({sign}{pct:.2f}%)")
+    print(f"  市值 {mcap/1e8:,.0f}亿  PE {pe}")
+    print(f"\n  RSI(14) {r:.1f} [{r_tag}]  布林位置 {bb_pos:.0f}% [{bb_tag}]  MACD [{m_tag}]")
+    print(f"{'─'*56}")
+
+    # Also print detailed indicators
+    cmd_pro(symbol, ticker, period, {"rsi": True, "macd": True, "bb": True})
+
+
+# ---------------------------------------------------------------------------
+# CLI
+# ---------------------------------------------------------------------------
+
+def main():
+    ap = argparse.ArgumentParser(description="LobsterAI Stock Explorer")
+    ap.add_argument("cmd", nargs="?", default="price",
+                    choices=["price", "fundamentals", "history", "pro", "report"])
+    ap.add_argument("symbol", help="股票代码")
+    ap.add_argument("period", nargs="?", default="3mo")
+    ap.add_argument("--rsi", action="store_true")
+    ap.add_argument("--macd", action="store_true")
+    ap.add_argument("--bb", action="store_true")
+    ap.add_argument("--vwap", action="store_true")
+    ap.add_argument("--atr", action="store_true")
+
+    argv = sys.argv[1:]
+    if argv and argv[0] not in ("price", "fundamentals", "history", "pro", "report"):
+        argv.insert(0, "price")
+
+    args = ap.parse_args(argv)
+    indicators = {k: getattr(args, k) for k in ("rsi", "macd", "bb", "vwap", "atr")}
+
+    ticker, info = _get_ticker(args.symbol)
+    if not ticker:
+        print(f"[错误] 无法获取 {args.symbol} 的数据", file=sys.stderr)
+        sys.exit(1)
+
+    if args.cmd == "price":
+        cmd_price(args.symbol, ticker, info)
+    elif args.cmd == "fundamentals":
+        cmd_fundamentals(args.symbol, ticker, info)
+    elif args.cmd == "history":
+        cmd_history(args.symbol, ticker, args.period)
+    elif args.cmd == "pro":
+        cmd_pro(args.symbol, ticker, args.period, indicators)
+    elif args.cmd == "report":
+        cmd_report(args.symbol, ticker, info, args.period)
+
+
+if __name__ == "__main__":
+    main()
diff --git a/docs/superpowers/specs/2026-03-25-avoid-gateway-restart-on-model-switch.md b/docs/superpowers/specs/2026-03-25-avoid-gateway-restart-on-model-switch.md
new file mode 100644
--- /dev/null
+++ b/docs/superpowers/specs/2026-03-25-avoid-gateway-restart-on-model-switch.md
@@ -0,0 +1,108 @@
+# Avoid Gateway Restart on Model Switching — Design
+
+## Overview
+
+Eliminate OpenClaw gateway process restarts when users switch between 套餐模型 (lobsterai-server) and 自定义模型 (custom providers), or between different custom providers with different apiKeys.
+
+## Problem
+
+When switching models across provider types, the gateway process is killed and restarted:
+
+```
+User switches model
+  → store:set('app_config')
+  → syncOpenClawConfig({ restartGatewayIfRunning: false })
+  → collectSecretEnvVars() returns new LOBSTER_PROVIDER_API_KEY value
+  → secretEnvVarsChanged = true
+  → stopGateway() + startGateway()  ← user-visible disruption
+```
+
+Root cause: a single `LOBSTER_PROVIDER_API_KEY` env var holds the active provider's apiKey. Switching providers changes this value, and env vars are fixed at process spawn time — forcing a restart.
+
+## Design
+
+### Approach: Per-Provider Env Vars
+
+Pre-register ALL configured provider apiKeys as separate env vars at gateway startup. Each provider in `openclaw.json` references its own placeholder. Switching models only changes which placeholder is used — env vars stay the same.
+
+```
+Before (single env var):
+  LOBSTER_PROVIDER_API_KEY = <active provider's key>   ← changes on switch
+
+After (per-provider env vars):
+  LOBSTER_APIKEY_SERVER    = <accessToken>              ← always set
+  LOBSTER_APIKEY_MOONSHOT  = <moonshot key>             ← always set
+  LOBSTER_APIKEY_ANTHROPIC = <anthropic key>            ← always set
+  LOBSTER_PROVIDER_API_KEY = <active key>               ← legacy fallback
+```
+
+### Architecture
+
+```
+resolveAllProviderApiKeys() ──────────────────────────┐
+  (claudeSettings.ts)                                  │
+  Enumerates all enabled providers + lobsterai-server   │
+  Returns: { SERVER: token, MOONSHOT: key, ... }        │
+                                                        ▼
+collectSecretEnvVars() ◄──── Sets LOBSTER_APIKEY_<NAME> for each provider
+  (openclawConfigSync.ts)    All injected at gateway spawn time
+
+buildProviderSelection() ──► apiKey: '${LOBSTER_APIKEY_<NAME>}'
+  (openclawConfigSync.ts)    Each provider references its own placeholder
+```
+
+### Env Var Naming Convention
+
+| Provider | Env Var Name | Source |
+|----------|-------------|--------|
+| lobsterai-server | `LOBSTER_APIKEY_SERVER` | accessToken from auth |
+| moonshot | `LOBSTER_APIKEY_MOONSHOT` | provider config apiKey |
+| anthropic | `LOBSTER_APIKEY_ANTHROPIC` | provider config apiKey |
+| ollama | `LOBSTER_APIKEY_OLLAMA` | `sk-lobsterai-local` (no key needed) |
+| custom | `LOBSTER_APIKEY_CUSTOM` | provider config apiKey |
+| (legacy) | `LOBSTER_PROVIDER_API_KEY` | active provider's key (backward compat) |
+
+Formula: `LOBSTER_APIKEY_` + `providerName.toUpperCase().replace(/[^A-Z0-9]/g, '_')`
+
+For lobsterai-server, hardcoded as `SERVER` (since it's a dynamic provider, not in app_config.providers).
+
+### Changes
+
+#### `src/main/libs/claudeSettings.ts`
+
+New export `resolveAllProviderApiKeys()`:
+- Reads auth tokens → sets `SERVER` key with accessToken
+- Iterates `app_config.providers` → sets `<PROVIDER_NAME>` key for each enabled provider
+- Skips providers without apiKey (except those that don't require one, like ollama)
+
+#### `src/main/libs/openclawConfigSync.ts`
+
+1. New helper `providerApiKeyEnvVar(providerName)` → `LOBSTER_APIKEY_<NAME>`
+2. `buildProviderSelection()` — all 4 cases updated:
+   - lobsterai-server: `${LOBSTER_APIKEY_SERVER}` (was inline apiKey)
+   - moonshot+codingPlan: `${LOBSTER_APIKEY_MOONSHOT}` (was `${LOBSTER_PROVIDER_API_KEY}`)
+   - moonshot: `${LOBSTER_APIKEY_MOONSHOT}` (was `${LOBSTER_PROVIDER_API_KEY}`)
+   - default: `${LOBSTER_APIKEY_<PROVIDER>}` (was `${LOBSTER_PROVIDER_API_KEY}`)
+3. `collectSecretEnvVars()` — calls `resolveAllProviderApiKeys()` to set all env vars, keeps legacy `LOBSTER_PROVIDER_API_KEY` for backward compat
+
+### When Gateway Still Restarts (Expected)
+
+| Scenario | Restarts? | Why |
+|----------|-----------|-----|
+| Switch 套餐→自定义 | No | Both env vars pre-set |
+| Switch between custom providers | No | Both env vars pre-set |
+| User edits a provider's apiKey | Yes | Env var value changed |
+| New provider enabled for first time | Yes | New env var added |
+| accessToken refreshed | Yes | SERVER env var changed (infrequent) |
+
+### Backward Compatibility
+
+- `LOBSTER_PROVIDER_API_KEY` is still set (to active provider's key) as a legacy fallback
+- Stale `openclaw.json` files referencing the old placeholder will still work
+- After first sync, new placeholder format is written
+
+## Testing
+
+- Unit tests verify env var naming convention and switching stability
+- Manual: switch between 套餐/自定义 models, verify no `stopGateway`/`startGateway` in logs
+- Manual: send messages after switch to verify correct model/apiKey is used
diff --git a/package.json b/package.json
--- a/package.json
+++ b/package.json
@@ -6,7 +6,7 @@
     "email": "lobsterai.project@rd.netease.com"
   },
   "license": "MIT",
-  "version": "2026.3.25",
+  "version": "2026.3.26",
   "openclaw": {
     "version": "v2026.3.2",
     "repo": "https://github.com/openclaw/openclaw.git",
@@ -109,14 +109,15 @@
     "@larksuite/openclaw-lark": "^2026.3.17",
     "@larksuite/openclaw-lark-tools": "~1.0.26",
     "@larksuiteoapi/node-sdk": "^1.58.0",
-    "qrcode.react": "^4.2.0",
     "@modelcontextprotocol/sdk": "^1.27.1",
     "@nodesecure/js-x-ray": "^14.2.0",
     "@reduxjs/toolkit": "^2.2.1",
     "@types/uuid": "^10.0.0",
     "@wecom/wecom-aibot-sdk": "^0.1.0",
     "bufferutil": "^4.1.0",
+    "cheerio": "^1.2.0",
     "cron-parser": "^5.5.0",
+    "cronstrue": "^3.14.0",
     "dompurify": "^3.3.1",
     "electron-log": "^5.4.3",
     "extract-zip": "^2.0.1",
@@ -126,6 +127,7 @@
     "mermaid": "^10.9.5",
     "nim-web-sdk-ng": "10.9.77-alpha.4",
     "npm": "^11.11.0",
+    "qrcode.react": "^4.2.0",
     "react": "^18.2.0",
     "react-dom": "^18.2.0",
     "react-markdown": "^10.0.0",
diff --git a/scripts/apply-openclaw-patches.cjs b/scripts/apply-openclaw-patches.cjs
--- a/scripts/apply-openclaw-patches.cjs
+++ b/scripts/apply-openclaw-patches.cjs
@@ -80,7 +80,7 @@ for (const patchFile of patchFiles) {
 
   let reverseOk = false;
   try {
-    execFileSync('git', ['apply', '--check', '--reverse', patchPath], {
+    execFileSync('git', ['apply', '--check', '--reverse', '--ignore-whitespace', patchPath], {
       cwd: openclawSrc,
       stdio: 'pipe',
     });
@@ -98,7 +98,7 @@ for (const patchFile of patchFiles) {
   // Try forward apply check.
   let forwardErr = null;
   try {
-    execFileSync('git', ['apply', '--check', patchPath], {
+    execFileSync('git', ['apply', '--check', '--ignore-whitespace', patchPath], {
       cwd: openclawSrc,
       stdio: 'pipe',
     });
@@ -130,7 +130,7 @@ for (const patchFile of patchFiles) {
 
   // Apply the patch.
   try {
-    execFileSync('git', ['apply', patchPath], {
+    execFileSync('git', ['apply', '--ignore-whitespace', patchPath], {
       cwd: openclawSrc,
       stdio: 'pipe',
     });
diff --git a/src/main/agentManager.ts b/src/main/agentManager.ts
new file mode 100644
--- /dev/null
+++ b/src/main/agentManager.ts
@@ -0,0 +1,65 @@
+import type { CoworkStore, Agent, CreateAgentRequest, UpdateAgentRequest } from './coworkStore';
+import { PRESET_AGENTS, presetToCreateRequest, type PresetAgent } from './presetAgents';
+
+/**
+ * AgentManager handles CRUD operations for agents and preset agent installation.
+ * Agents are stored in the SQLite `agents` table via CoworkStore.
+ */
+export class AgentManager {
+  private store: CoworkStore;
+
+  constructor(store: CoworkStore) {
+    this.store = store;
+  }
+
+  listAgents(): Agent[] {
+    return this.store.listAgents();
+  }
+
+  getAgent(agentId: string): Agent | null {
+    return this.store.getAgent(agentId);
+  }
+
+  getDefaultAgent(): Agent {
+    const agents = this.store.listAgents();
+    return agents.find(a => a.isDefault) || agents[0];
+  }
+
+  createAgent(request: CreateAgentRequest): Agent {
+    return this.store.createAgent(request);
+  }
+
+  updateAgent(agentId: string, updates: UpdateAgentRequest): Agent | null {
+    return this.store.updateAgent(agentId, updates);
+  }
+
+  deleteAgent(agentId: string): boolean {
+    return this.store.deleteAgent(agentId);
+  }
+
+  // --- Preset agents ---
+
+  getPresetAgents(): PresetAgent[] {
+    const existingAgents = this.store.listAgents();
+    const existingPresetIds = new Set(
+      existingAgents.filter(a => a.source === 'preset').map(a => a.presetId)
+    );
+    // Only return presets that haven't been added yet
+    return PRESET_AGENTS.filter(p => !existingPresetIds.has(p.id));
+  }
+
+  getAllPresetAgents(): PresetAgent[] {
+    return PRESET_AGENTS;
+  }
+
+  addPresetAgent(presetId: string): Agent | null {
+    const preset = PRESET_AGENTS.find(p => p.id === presetId);
+    if (!preset) return null;
+
+    // Check if already installed
+    const existing = this.store.getAgent(preset.id);
+    if (existing) return existing;
+
+    return this.store.createAgent(presetToCreateRequest(preset));
+  }
+}
diff --git a/src/main/coworkStore.ts b/src/main/coworkStore.ts
--- a/src/main/coworkStore.ts
+++ b/src/main/coworkStore.ts
@@ -298,6 +298,49 @@ export type CoworkMessageType = 'user' | 'assistant' | 'tool_use' | 'tool_result
 export type CoworkExecutionMode = 'auto' | 'local' | 'sandbox';
 export type CoworkAgentEngine = 'openclaw' | 'yd_cowork';
 
+export type AgentSource = 'custom' | 'preset';
+
+export interface Agent {
+  id: string;
+  name: string;
+  description: string;
+  systemPrompt: string;
+  identity: string;
+  model: string;
+  icon: string;
+  skillIds: string[];
+  enabled: boolean;
+  isDefault: boolean;
+  source: AgentSource;
+  presetId: string;
+  createdAt: number;
+  updatedAt: number;
+}
+
+export interface CreateAgentRequest {
+  id?: string;
+  name: string;
+  description?: string;
+  systemPrompt?: string;
+  identity?: string;
+  model?: string;
+  icon?: string;
+  skillIds?: string[];
+  source?: AgentSource;
+  presetId?: string;
+}
+
+export interface UpdateAgentRequest {
+  name?: string;
+  description?: string;
+  systemPrompt?: string;
+  identity?: string;
+  model?: string;
+  icon?: string;
+  skillIds?: string[];
+  enabled?: boolean;
+}
+
 const COWORK_AGENT_ENGINE = 'openclaw';
 
 function normalizeCoworkAgentEngineValue(value?: string | null): CoworkAgentEngine {
@@ -338,6 +381,7 @@ export interface CoworkSession {
   systemPrompt: string;
   executionMode: CoworkExecutionMode;
   activeSkillIds: string[];
+  agentId: string;
   messages: CoworkMessage[];
   createdAt: number;
   updatedAt: number;
@@ -348,6 +392,7 @@ export interface CoworkSessionSummary {
   title: string;
   status: CoworkSessionStatus;
   pinned: boolean;
+  agentId: string;
   createdAt: number;
   updatedAt: number;
 }
@@ -519,15 +564,16 @@ export class CoworkStore {
     cwd: string,
     systemPrompt: string = '',
     executionMode: CoworkExecutionMode = 'local',
-    activeSkillIds: string[] = []
+    activeSkillIds: string[] = [],
+    agentId: string = 'main'
   ): CoworkSession {
     const id = uuidv4();
     const now = Date.now();
 
     this.db.run(`
-      INSERT INTO cowork_sessions (id, title, claude_session_id, status, cwd, system_prompt, execution_mode, active_skill_ids, pinned, created_at, updated_at)
-      VALUES (?, ?, NULL, 'idle', ?, ?, ?, ?, 0, ?, ?)
-    `, [id, title, cwd, systemPrompt, executionMode, JSON.stringify(activeSkillIds), now, now]);
+      INSERT INTO cowork_sessions (id, title, claude_session_id, status, cwd, system_prompt, execution_mode, active_skill_ids, agent_id, pinned, created_at, updated_at)
+      VALUES (?, ?, NULL, 'idle', ?, ?, ?, ?, ?, 0, ?, ?)
+    `, [id, title, cwd, systemPrompt, executionMode, JSON.stringify(activeSkillIds), agentId, now, now]);
 
     this.saveDb();
 
@@ -541,6 +587,7 @@ export class CoworkStore {
       systemPrompt,
       executionMode,
       activeSkillIds,
+      agentId,
       messages: [],
       createdAt: now,
       updatedAt: now,
@@ -558,12 +605,13 @@ export class CoworkStore {
       system_prompt: string;
       execution_mode?: string | null;
       active_skill_ids?: string | null;
+      agent_id?: string | null;
       created_at: number;
       updated_at: number;
     }
 
     const row = this.getOne<SessionRow>(`
-      SELECT id, title, claude_session_id, status, pinned, cwd, system_prompt, execution_mode, active_skill_ids, created_at, updated_at
+      SELECT id, title, claude_session_id, status, pinned, cwd, system_prompt, execution_mode, active_skill_ids, agent_id, created_at, updated_at
       FROM cowork_sessions
       WHERE id = ?
     `, [id]);
@@ -591,6 +639,7 @@ export class CoworkStore {
       systemPrompt: row.system_prompt,
       executionMode: (row.execution_mode as CoworkExecutionMode) || 'local',
       activeSkillIds,
+      agentId: row.agent_id || 'main',
       messages,
       createdAt: row.created_at,
       updatedAt: row.updated_at,
@@ -663,27 +712,39 @@ export class CoworkStore {
     this.saveDb();
   }
 
-  listSessions(): CoworkSessionSummary[] {
+  listSessions(agentId?: string): CoworkSessionSummary[] {
     interface SessionSummaryRow {
       id: string;
       title: string;
       status: string;
       pinned: number | null;
+      agent_id: string | null;
       created_at: number;
       updated_at: number;
     }
 
-    const rows = this.getAll<SessionSummaryRow>(`
-      SELECT id, title, status, pinned, created_at, updated_at
-      FROM cowork_sessions
-      ORDER BY pinned DESC, updated_at DESC
-    `);
+    let rows: SessionSummaryRow[];
+    if (agentId) {
+      rows = this.getAll<SessionSummaryRow>(`
+        SELECT id, title, status, pinned, agent_id, created_at, updated_at
+        FROM cowork_sessions
+        WHERE agent_id = ?
+        ORDER BY pinned DESC, updated_at DESC
+      `, [agentId]);
+    } else {
+      rows = this.getAll<SessionSummaryRow>(`
+        SELECT id, title, status, pinned, agent_id, created_at, updated_at
+        FROM cowork_sessions
+        ORDER BY pinned DESC, updated_at DESC
+      `);
+    }
 
     return rows.map(row => ({
       id: row.id,
       title: row.title,
       status: row.status as CoworkSessionStatus,
       pinned: Boolean(row.pinned),
+      agentId: row.agent_id || 'main',
       createdAt: row.created_at,
       updatedAt: row.updated_at,
     }));
@@ -1629,4 +1690,182 @@ export class CoworkStore {
       assistant: this.getLatestMessageByType(row.id, 'assistant'),
     }));
   }
+
+  // ========== Agent CRUD ==========
+
+  listAgents(): Agent[] {
+    interface AgentRow {
+      id: string;
+      name: string;
+      description: string;
+      system_prompt: string;
+      identity: string;
+      model: string;
+      icon: string;
+      skill_ids: string;
+      enabled: number;
+      is_default: number;
+      source: string;
+      preset_id: string;
+      created_at: number;
+      updated_at: number;
+    }
+
+    const rows = this.getAll<AgentRow>(`
+      SELECT * FROM agents ORDER BY is_default DESC, created_at ASC
+    `);
+
+    return rows.map(row => this.mapAgentRow(row));
+  }
+
+  getAgent(id: string): Agent | null {
+    interface AgentRow {
+      id: string;
+      name: string;
+      description: string;
+      system_prompt: string;
+      identity: string;
+      model: string;
+      icon: string;
+      skill_ids: string;
+      enabled: number;
+      is_default: number;
+      source: string;
+      preset_id: string;
+      created_at: number;
+      updated_at: number;
+    }
+
+    const row = this.getOne<AgentRow>(`SELECT * FROM agents WHERE id = ?`, [id]);
+    if (!row) return null;
+    return this.mapAgentRow(row);
+  }
+
+  createAgent(request: CreateAgentRequest): Agent {
+    const id = request.id || request.name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || uuidv4();
+    const now = Date.now();
+
+    // Ensure no duplicate ID
+    const existing = this.getAgent(id);
+    if (existing) {
+      // Append timestamp to make unique
+      return this.createAgent({ ...request, id: `${id}-${Date.now()}` });
+    }
+
+    this.db.run(`
+      INSERT INTO agents (id, name, description, system_prompt, identity, model, icon, skill_ids, enabled, is_default, source, preset_id, created_at, updated_at)
+      VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, 0, ?, ?, ?, ?)
+    `, [
+      id,
+      request.name,
+      request.description || '',
+      request.systemPrompt || '',
+      request.identity || '',
+      request.model || '',
+      request.icon || '',
+      JSON.stringify(request.skillIds || []),
+      request.source || 'custom',
+      request.presetId || '',
+      now,
+      now,
+    ]);
+
+    this.saveDb();
+    return this.getAgent(id)!;
+  }
+
+  updateAgent(id: string, updates: UpdateAgentRequest): Agent | null {
+    const existing = this.getAgent(id);
+    if (!existing) return null;
+
+    const now = Date.now();
+    const setClauses: string[] = ['updated_at = ?'];
+    const values: (string | number | null)[] = [now];
+
+    if (updates.name !== undefined) {
+      setClauses.push('name = ?');
+      values.push(updates.name);
+    }
+    if (updates.description !== undefined) {
+      setClauses.push('description = ?');
+      values.push(updates.description);
+    }
+    if (updates.systemPrompt !== undefined) {
+      setClauses.push('system_prompt = ?');
+      values.push(updates.systemPrompt);
+    }
+    if (updates.identity !== undefined) {
+      setClauses.push('identity = ?');
+      values.push(updates.identity);
+    }
+    if (updates.model !== undefined) {
+      setClauses.push('model = ?');
+      values.push(updates.model);
+    }
+    if (updates.icon !== undefined) {
+      setClauses.push('icon = ?');
+      values.push(updates.icon);
+    }
+    if (updates.skillIds !== undefined) {
+      setClauses.push('skill_ids = ?');
+      values.push(JSON.stringify(updates.skillIds));
+    }
+    if (updates.enabled !== undefined) {
+      setClauses.push('enabled = ?');
+      values.push(updates.enabled ? 1 : 0);
+    }
+
+    values.push(id);
+    this.db.run(`UPDATE agents SET ${setClauses.join(', ')} WHERE id = ?`, values);
+    this.saveDb();
+
+    return this.getAgent(id);
+  }
+
+  deleteAgent(id: string): boolean {
+    if (id === 'main') return false; // Cannot delete default agent
+    this.db.run('DELETE FROM agents WHERE id = ? AND is_default = 0', [id]);
+    this.saveDb();
+    return true;
+  }
+
+  private mapAgentRow(row: {
+    id: string;
+    name: string;
+    description: string;
+    system_prompt: string;
+    identity: string;
+    model: string;
+    icon: string;
+    skill_ids: string;
+    enabled: number;
+    is_default: number;
+    source: string;
+    preset_id: string;
+    created_at: number;
+    updated_at: number;
+  }): Agent {
+    let skillIds: string[] = [];
+    try {
+      skillIds = JSON.parse(row.skill_ids);
+    } catch {
+      skillIds = [];
+    }
+    return {
+      id: row.id,
+      name: row.name,
+      description: row.description,
+      systemPrompt: row.system_prompt,
+      identity: row.identity,
+      model: row.model,
+      icon: row.icon,
+      skillIds,
+      enabled: Boolean(row.enabled),
+      isDefault: Boolean(row.is_default),
+      source: row.source as AgentSource,
+      presetId: row.preset_id,
+      createdAt: row.created_at,
+      updatedAt: row.updated_at,
+    };
+  }
 }
diff --git a/src/main/i18n.ts b/src/main/i18n.ts
--- a/src/main/i18n.ts
+++ b/src/main/i18n.ts
@@ -23,6 +23,14 @@ const translations: Record<LanguageType, Record<string, string>> = {
 
     // Session titles (created by ChannelSessionSync)
     cronSessionPrefix: '定时',
+    channelPrefixFeishu: '飞书',
+    channelPrefixDingtalk: '钉钉',
+    channelPrefixWecom: '企微',
+    channelPrefixNim: '云信',
+    channelPrefixWeixin: '微信',
+    // NIM chat type labels
+    nimQChat: '圈组',
+    nimGroup: '群聊',
 
     // Timeout hint
     taskTimedOut: '[任务超时] 任务因超过最大允许时长而被自动停止。你可以继续对话以从中断处继续。',
@@ -64,6 +72,14 @@ const translations: Record<LanguageType, Record<string, string>> = {
 
     // Session titles
     cronSessionPrefix: 'Cron',
+    channelPrefixFeishu: 'Feishu',
+    channelPrefixDingtalk: 'DingTalk',
+    channelPrefixWecom: 'WeCom',
+    channelPrefixNim: 'NIM',
+    channelPrefixWeixin: 'WeChat',
+    // NIM chat type labels
+    nimQChat: 'QChat',
+    nimGroup: 'Group',
 
     // Timeout hint
     taskTimedOut: '[Task timed out] The task was automatically stopped because it exceeded the maximum allowed duration. You can continue the conversation to pick up where it left off.',
diff --git a/src/main/im/imCoworkHandler.ts b/src/main/im/imCoworkHandler.ts
--- a/src/main/im/imCoworkHandler.ts
+++ b/src/main/im/imCoworkHandler.ts
@@ -19,7 +19,8 @@ import {
   type IMScheduledTaskRequestDetector,
   type ParsedIMScheduledTaskRequest,
 } from './imScheduledTaskHandler';
-import { buildScheduledTaskEnginePrompt } from '../libs/scheduledTaskEnginePrompt';
+import { buildScheduledTaskEnginePrompt } from '../../scheduled-task/enginePrompt';
+import { t } from '../i18n';
 
 interface MessageAccumulator {
   messages: CoworkMessage[];
@@ -322,11 +323,17 @@ export class IMCoworkHandler extends EventEmitter {
       throw new Error(`IM 工作目录不存在或无效: ${resolvedWorkspaceRoot}`);
     }
 
+    // Resolve the agent bound to this platform
+    const imSettings = this.imStore.getIMSettings();
+    const agentId = imSettings.platformAgentBindings?.[platform] || 'main';
+
     const session = this.coworkStore.createSession(
       title,
       resolvedWorkspaceRoot,
       systemPrompt,
-      config.executionMode || 'auto'
+      config.executionMode || 'auto',
+      [],
+      agentId
     );
 
     // Save mapping
@@ -353,17 +360,17 @@ export class IMCoworkHandler extends EventEmitter {
     message?: IMMessage
   ): string {
     if (platform === 'nim') {
+      const nimLabel = t('channelPrefixNim');
       if (message?.chatSubType === 'qchat') {
         const channelLabel = message.groupName || _imConversationId;
-        return `云信-圈组-${channelLabel}`;
+        return `${nimLabel}-${t('nimQChat')}-${channelLabel}`;
       }
       if (message?.chatType === 'group') {
         const groupLabel = message.groupName || senderId || _imConversationId;
-        return `云信-群聊-${groupLabel}`;
+        return `${nimLabel}-${t('nimGroup')}-${groupLabel}`;
       }
-      // P2P direct message
       const peerLabel = message?.senderName || senderId || _imConversationId;
-      return `云信-P2P-${peerLabel}`;
+      return `${nimLabel}-P2P-${peerLabel}`;
     }
     return `IM-${platform}-${Date.now()}`;
   }
@@ -535,9 +542,12 @@ export class IMCoworkHandler extends EventEmitter {
    */
   private handleMessage(sessionId: string, message: CoworkMessage): void {
     // Only process messages from IM sessions
-    if (!this.ensureTrackedSession(sessionId)) return;
+    const tracked = this.ensureTrackedSession(sessionId);
+    console.log('[IMCoworkHandler:handleMessage] sessionId:', sessionId, 'tracked:', tracked, 'messageType:', message.type);
+    if (!tracked) return;
 
     const accumulator = this.messageAccumulators.get(sessionId) ?? this.ensureBackgroundAccumulator(sessionId);
+    console.log('[IMCoworkHandler:handleMessage] accumulator exists:', !!accumulator, 'backgroundDelivery:', !!(accumulator as any)?.backgroundDelivery);
     if (accumulator) {
       accumulator.messages.push(message);
     }
@@ -813,7 +823,9 @@ export class IMCoworkHandler extends EventEmitter {
    */
   private handleComplete(sessionId: string): void {
     // Only process complete events from IM sessions
-    if (!this.ensureTrackedSession(sessionId)) return;
+    const tracked = this.ensureTrackedSession(sessionId);
+    console.log('[IMCoworkHandler:handleComplete] sessionId:', sessionId, 'tracked:', tracked, 'hasAccumulator:', this.messageAccumulators.has(sessionId));
+    if (!tracked) return;
 
     this.clearPendingPermissionsBySessionId(sessionId);
     const accumulator = this.messageAccumulators.get(sessionId);
diff --git a/src/main/im/imDeliveryRoute.ts b/src/main/im/imDeliveryRoute.ts
--- a/src/main/im/imDeliveryRoute.ts
+++ b/src/main/im/imDeliveryRoute.ts
@@ -119,15 +119,17 @@ export function buildDingTalkSendParamsFromRoute(
   };
 }
 
-export function buildDingTalkSessionKeyCandidates(conversationId: string): string[] {
+export function buildDingTalkSessionKeyCandidates(conversationId: string, agentId?: string): string[] {
   const normalizedConversationId = conversationId.trim();
   if (!normalizedConversationId) {
     return [];
   }
 
+  const effectiveAgentId = agentId || DEFAULT_MANAGED_AGENT_ID;
+
   return [
-    `agent:${DEFAULT_MANAGED_AGENT_ID}:openai-user:dingtalk-connector:${normalizedConversationId}`,
-    `agent:${DEFAULT_MANAGED_AGENT_ID}:dingtalk-connector:${normalizedConversationId}`,
+    `agent:${effectiveAgentId}:openai-user:dingtalk-connector:${normalizedConversationId}`,
+    `agent:${effectiveAgentId}:dingtalk-connector:${normalizedConversationId}`,
     `dingtalk-connector:${normalizedConversationId}`,
   ];
 }
diff --git a/src/main/im/imScheduledTaskHandler.ts b/src/main/im/imScheduledTaskHandler.ts
--- a/src/main/im/imScheduledTaskHandler.ts
+++ b/src/main/im/imScheduledTaskHandler.ts
@@ -5,7 +5,7 @@ import {
   parseSimpleScheduledReminderText,
   parseLegacyScheduledReminderSystemMessage,
   parseScheduledReminderPrompt,
-} from '../../common/scheduledReminderText';
+} from '../../scheduled-task/reminderText';
 
 function pad(value: number): string {
   return String(value).padStart(2, '0');
diff --git a/src/main/im/imStore.ts b/src/main/im/imStore.ts
--- a/src/main/im/imStore.ts
+++ b/src/main/im/imStore.ts
@@ -13,7 +13,6 @@ import {
   DiscordOpenClawConfig,
   NimConfig,
   XiaomifengConfig,
-  WecomConfig,
   WecomOpenClawConfig,
   PopoOpenClawConfig,
   WeixinOpenClawConfig,
@@ -71,6 +70,13 @@ export class IMStore {
       );
     `);
 
+    // Migration: Add agent_id column to im_session_mappings
+    const mappingCols = this.db.exec('PRAGMA table_info(im_session_mappings)');
+    const mappingColNames = (mappingCols[0]?.values ?? []).map((r) => r[1] as string);
+    if (!mappingColNames.includes('agent_id')) {
+      this.db.run("ALTER TABLE im_session_mappings ADD COLUMN agent_id TEXT NOT NULL DEFAULT 'main'");
+    }
+
     this.saveDb();
   }
 
@@ -627,7 +633,7 @@ export class IMStore {
    */
   getSessionMapping(imConversationId: string, platform: IMPlatform): IMSessionMapping | null {
     const result = this.db.exec(
-      'SELECT im_conversation_id, platform, cowork_session_id, created_at, last_active_at FROM im_session_mappings WHERE im_conversation_id = ? AND platform = ?',
+      'SELECT im_conversation_id, platform, cowork_session_id, agent_id, created_at, last_active_at FROM im_session_mappings WHERE im_conversation_id = ? AND platform = ?',
       [imConversationId, platform]
     );
     if (!result[0]?.values[0]) return null;
@@ -636,8 +642,9 @@ export class IMStore {
       imConversationId: row[0] as string,
       platform: row[1] as IMPlatform,
       coworkSessionId: row[2] as string,
-      createdAt: row[3] as number,
-      lastActiveAt: row[4] as number,
+      agentId: (row[3] as string) || 'main',
+      createdAt: row[4] as number,
+      lastActiveAt: row[5] as number,
     };
   }
 
@@ -646,7 +653,7 @@ export class IMStore {
    */
   getSessionMappingByCoworkSessionId(coworkSessionId: string): IMSessionMapping | null {
     const result = this.db.exec(
-      'SELECT im_conversation_id, platform, cowork_session_id, created_at, last_active_at FROM im_session_mappings WHERE cowork_session_id = ? LIMIT 1',
+      'SELECT im_conversation_id, platform, cowork_session_id, agent_id, created_at, last_active_at FROM im_session_mappings WHERE cowork_session_id = ? LIMIT 1',
       [coworkSessionId]
     );
     if (!result[0]?.values[0]) return null;
@@ -655,25 +662,27 @@ export class IMStore {
       imConversationId: row[0] as string,
       platform: row[1] as IMPlatform,
       coworkSessionId: row[2] as string,
-      createdAt: row[3] as number,
-      lastActiveAt: row[4] as number,
+      agentId: (row[3] as string) || 'main',
+      createdAt: row[4] as number,
+      lastActiveAt: row[5] as number,
     };
   }
 
   /**
    * Create a new session mapping
    */
-  createSessionMapping(imConversationId: string, platform: IMPlatform, coworkSessionId: string): IMSessionMapping {
+  createSessionMapping(imConversationId: string, platform: IMPlatform, coworkSessionId: string, agentId: string = 'main'): IMSessionMapping {
     const now = Date.now();
     this.db.run(
-      'INSERT INTO im_session_mappings (im_conversation_id, platform, cowork_session_id, created_at, last_active_at) VALUES (?, ?, ?, ?, ?)',
-      [imConversationId, platform, coworkSessionId, now, now]
+      'INSERT INTO im_session_mappings (im_conversation_id, platform, cowork_session_id, agent_id, created_at, last_active_at) VALUES (?, ?, ?, ?, ?, ?)',
+      [imConversationId, platform, coworkSessionId, agentId, now, now]
     );
     this.saveDb();
     return {
       imConversationId,
       platform,
       coworkSessionId,
+      agentId,
       createdAt: now,
       lastActiveAt: now,
     };
@@ -691,6 +700,19 @@ export class IMStore {
     this.saveDb();
   }
 
+  /**
+   * Update the target session and agent for an existing mapping.
+   * Used when the platform's agent binding changes.
+   */
+  updateSessionMappingTarget(imConversationId: string, platform: IMPlatform, newCoworkSessionId: string, newAgentId: string): void {
+    const now = Date.now();
+    this.db.run(
+      'UPDATE im_session_mappings SET cowork_session_id = ?, agent_id = ?, last_active_at = ? WHERE im_conversation_id = ? AND platform = ?',
+      [newCoworkSessionId, newAgentId, now, imConversationId, platform]
+    );
+    this.saveDb();
+  }
+
   /**
    * Delete a session mapping
    */
@@ -720,17 +742,18 @@ export class IMStore {
    */
   listSessionMappings(platform?: IMPlatform): IMSessionMapping[] {
     const query = platform
-      ? 'SELECT im_conversation_id, platform, cowork_session_id, created_at, last_active_at FROM im_session_mappings WHERE platform = ? ORDER BY last_active_at DESC'
-      : 'SELECT im_conversation_id, platform, cowork_session_id, created_at, last_active_at FROM im_session_mappings ORDER BY last_active_at DESC';
+      ? 'SELECT im_conversation_id, platform, cowork_session_id, agent_id, created_at, last_active_at FROM im_session_mappings WHERE platform = ? ORDER BY last_active_at DESC'
+      : 'SELECT im_conversation_id, platform, cowork_session_id, agent_id, created_at, last_active_at FROM im_session_mappings ORDER BY last_active_at DESC';
     const params = platform ? [platform] : [];
     const result = this.db.exec(query, params);
     if (!result[0]?.values) return [];
     return result[0].values.map(row => ({
       imConversationId: row[0] as string,
       platform: row[1] as IMPlatform,
       coworkSessionId: row[2] as string,
-      createdAt: row[3] as number,
-      lastActiveAt: row[4] as number,
+      agentId: (row[3] as string) || 'main',
+      createdAt: row[4] as number,
+      lastActiveAt: row[5] as number,
     }));
   }
 }
diff --git a/src/main/im/types.ts b/src/main/im/types.ts
--- a/src/main/im/types.ts
+++ b/src/main/im/types.ts
@@ -318,6 +318,8 @@ export interface IMGatewayConfig {
 export interface IMSettings {
   systemPrompt?: string;
   skillsEnabled: boolean;
+  /** Per-platform agent binding. Key = platform name, value = agent ID. Absent or 'main' = default. */
+  platformAgentBindings?: Record<string, string>;
 }
 
 export interface IMGatewayStatus {
@@ -380,6 +382,7 @@ export interface IMSessionMapping {
   imConversationId: string;
   platform: IMPlatform;
   coworkSessionId: string;
+  agentId: string;
   createdAt: number;
   lastActiveAt: number;
 }
diff --git a/src/main/libs/agentEngine/openclawRuntimeAdapter.ts b/src/main/libs/agentEngine/openclawRuntimeAdapter.ts
--- a/src/main/libs/agentEngine/openclawRuntimeAdapter.ts
+++ b/src/main/libs/agentEngine/openclawRuntimeAdapter.ts
@@ -1,6 +1,7 @@
 import { randomUUID } from 'crypto';
 import { app, BrowserWindow } from 'electron';
 import { EventEmitter } from 'events';
+import * as fs from 'fs';
 import * as path from 'path';
 import { pathToFileURL } from 'url';
 import type { PermissionResult } from '@anthropic-ai/claude-agent-sdk';
@@ -562,7 +563,12 @@ export class OpenClawRuntimeAdapter extends EventEmitter implements CoworkRuntim
   /** Throttle state for messageUpdate IPC emissions during streaming */
   private lastMessageUpdateEmitTime: Map<string, number> = new Map();
   private pendingMessageUpdateTimer: Map<string, ReturnType<typeof setTimeout>> = new Map();
-  private static readonly MESSAGE_UPDATE_THROTTLE_MS = 100;
+  private static readonly MESSAGE_UPDATE_THROTTLE_MS = 200;
+
+  /** Throttle state for SQLite store writes during streaming */
+  private lastStoreUpdateTime: Map<string, number> = new Map();
+  private pendingStoreUpdateTimer: Map<string, ReturnType<typeof setTimeout>> = new Map();
+  private static readonly STORE_UPDATE_THROTTLE_MS = 250;
 
   /**
    * Server-side agent timeout in seconds (mirrors agents.defaults.timeoutSeconds in openclaw config).
@@ -615,7 +621,7 @@ export class OpenClawRuntimeAdapter extends EventEmitter implements CoworkRuntim
         limit: OpenClawRuntimeAdapter.FULL_HISTORY_SYNC_LIMIT,
       });
       if (!Array.isArray(history?.messages) || history.messages.length === 0) {
-        return null;
+        return this.readFromDeletedTranscript(sessionKey);
       }
 
       const now = Date.now();
@@ -646,6 +652,7 @@ export class OpenClawRuntimeAdapter extends EventEmitter implements CoworkRuntim
         executionMode: 'local' as CoworkExecutionMode,
         activeSkillIds: [],
         messages,
+        agentId: 'main',
         createdAt: now,
         updatedAt: now,
       };
@@ -655,6 +662,103 @@ export class OpenClawRuntimeAdapter extends EventEmitter implements CoworkRuntim
     }
   }
 
+  /**
+   * Fallback for fetchSessionByKey when chat.history returns no messages.
+   *
+   * openclaw's maintenance logic may archive a session transcript by renaming
+   * `{sessionId}.jsonl` → `{sessionId}.jsonl.deleted.{timestamp}` while the
+   * session entry remains in sessions.json. In that case chat.history cannot
+   * find the file (it only looks for the plain `.jsonl` path) and returns [].
+   * This method reads the archived file directly from disk.
+   */
+  private async readFromDeletedTranscript(sessionKey: string): Promise<CoworkSession | null> {
+    try {
+      // Extract agentId from "agent:{agentId}:..." pattern
+      const agentMatch = sessionKey.match(/^agent:([^:]+):/);
+      const agentId = agentMatch?.[1] ?? 'main';
+
+      // Extract sessionId from "...run:{uuid}" pattern (runId equals sessionId)
+      const runMatch = sessionKey.match(/(?:^|:)run:([0-9a-f-]{36})(?:$|:)/i);
+      const sessionId = runMatch?.[1];
+      if (!sessionId) return null;
+
+      const stateDir = this.engineManager.getStateDir();
+      const sessionsDir = path.join(stateDir, 'agents', agentId, 'sessions');
+
+      const files = await fs.promises.readdir(sessionsDir).catch(() => [] as string[]);
+      const deletedFile = files.find(f => f.startsWith(`${sessionId}.jsonl.deleted.`));
+      if (!deletedFile) {
+        console.log('[OpenClawRuntime] readFromDeletedTranscript: no archived transcript found for sessionId:', sessionId);
+        return null;
+      }
+
+      console.log('[OpenClawRuntime] readFromDeletedTranscript: reading archived transcript:', deletedFile);
+      const filePath = path.join(sessionsDir, deletedFile);
+      const content = await fs.promises.readFile(filePath, 'utf-8');
+      const lines = content.split(/\r?\n/);
+
+      const messages: CoworkMessage[] = [];
+      let msgIndex = 0;
+
+      for (const line of lines) {
+        if (!line.trim()) continue;
+        try {
+          const parsed = JSON.parse(line) as Record<string, unknown>;
+          if (parsed?.type !== 'message' || !parsed.message) continue;
+          const msg = parsed.message as { role?: string; content?: unknown; timestamp?: number };
+          const role = msg.role;
+          if (role !== 'user' && role !== 'assistant') continue;
+
+          const msgContent = msg.content;
+          const text = Array.isArray(msgContent)
+            ? (msgContent as Array<Record<string, unknown>>)
+                .filter(b => b?.type === 'text')
+                .map(b => b.text as string)
+                .join('\n')
+            : typeof msgContent === 'string' ? msgContent : '';
+
+          if (!text.trim()) continue;
+
+          const timestamp = typeof msg.timestamp === 'number'
+            ? msg.timestamp
+            : typeof parsed.timestamp === 'string' ? Date.parse(parsed.timestamp) : Date.now();
+
+          messages.push({
+            id: `transient-${msgIndex++}`,
+            type: role as 'user' | 'assistant',
+            content: text,
+            timestamp,
+            metadata: role === 'assistant' ? { isStreaming: false, isFinal: true } : {},
+          });
+        } catch {
+          // skip malformed lines
+        }
+      }
+
+      if (messages.length === 0) return null;
+
+      const firstTimestamp = messages[0]?.timestamp ?? Date.now();
+      return {
+        id: `transient-${sessionKey}`,
+        agentId: '',
+        title: sessionKey.split(':').pop() || 'Cron Session',
+        claudeSessionId: null,
+        status: 'completed' as CoworkSessionStatus,
+        pinned: false,
+        cwd: '',
+        systemPrompt: '',
+        executionMode: 'local' as CoworkExecutionMode,
+        activeSkillIds: [],
+        messages,
+        createdAt: firstTimestamp,
+        updatedAt: firstTimestamp,
+      };
+    } catch (error) {
+      console.warn('[OpenClawRuntime] readFromDeletedTranscript failed:', error);
+      return null;
+    }
+  }
+
   /**
    * Ensure the gateway WebSocket client is connected.
    * Called when IM channels (e.g. Telegram) are enabled in OpenClaw mode
@@ -767,6 +871,10 @@ export class OpenClawRuntimeAdapter extends EventEmitter implements CoworkRuntim
         if (!isChannel) continue;
         // Skip keys that were explicitly deleted by the user — only real-time events re-create them
         if (this.deletedChannelKeys.has(key)) continue;
+        // Skip gateway sessions belonging to a previously-bound agent.
+        // After an agent binding change, the gateway retains old sessions under the old agentId.
+        // Only process sessions matching the current platformAgentBindings.
+        if (!this.channelSessionSync.isCurrentBindingKey(key)) continue;
         channelCount++;
         // Use resolveOrCreateSession so new channel sessions are auto-created
         const sessionId = this.channelSessionSync.resolveOrCreateSession(key);
@@ -798,14 +906,20 @@ export class OpenClawRuntimeAdapter extends EventEmitter implements CoworkRuntim
       // Incremental sync for already-known sessions: check if the gateway has messages
       // that weren't picked up during initial sync or real-time events.
       if (channelCount > 0) {
+        const syncedThisCycle = new Set<string>();
         for (const row of sessions) {
           const key = typeof row?.key === 'string' ? row.key : '';
           if (!key) continue;
           if (!this.channelSessionSync.isChannelSessionKey(key)) continue;
           if (this.deletedChannelKeys.has(key)) continue;
           if (this.heartbeatSessionKeys.has(key)) continue;
+          // Skip sessions belonging to a previously-bound agent
+          if (!this.channelSessionSync.isCurrentBindingKey(key)) continue;
           const sessionId = this.sessionIdBySessionKey.get(key);
           if (!sessionId || !this.fullySyncedSessions.has(sessionId)) continue;
+          // Safety net: only sync each sessionId once per poll cycle
+          if (syncedThisCycle.has(sessionId)) continue;
+          syncedThisCycle.add(sessionId);
           // Skip sessions with an active turn (they handle their own sync)
           if (this.activeTurns.has(sessionId)) continue;
           try {
@@ -841,6 +955,7 @@ export class OpenClawRuntimeAdapter extends EventEmitter implements CoworkRuntim
       systemPrompt: options.systemPrompt,
       confirmationMode: options.confirmationMode,
       imageAttachments: options.imageAttachments,
+      agentId: options.agentId,
     });
   }
 
@@ -927,6 +1042,7 @@ export class OpenClawRuntimeAdapter extends EventEmitter implements CoworkRuntim
       skillIds?: string[];
       confirmationMode?: 'modal' | 'text';
       imageAttachments?: Array<{ name: string; mimeType: string; base64Data: string }>;
+      agentId?: string;
     },
   ): Promise<void> {
     if (!prompt.trim()) {
@@ -961,7 +1077,8 @@ export class OpenClawRuntimeAdapter extends EventEmitter implements CoworkRuntim
       this.emit('message', sessionId, userMessage);
     }
 
-    const sessionKey = this.toSessionKey(sessionId);
+    const agentId = options.agentId || session.agentId || 'main';
+    const sessionKey = this.toSessionKey(sessionId, agentId);
     this.rememberSessionKey(sessionId, sessionKey);
 
     this.store.updateSession(sessionId, { status: 'running' });
@@ -975,6 +1092,7 @@ export class OpenClawRuntimeAdapter extends EventEmitter implements CoworkRuntim
       sessionId,
       prompt,
       options.systemPrompt ?? session.systemPrompt,
+      agentId,
     );
     const completionPromise = new Promise<void>((resolve, reject) => {
       this.pendingTurns.set(sessionId, { resolve, reject });
@@ -1052,6 +1170,7 @@ export class OpenClawRuntimeAdapter extends EventEmitter implements CoworkRuntim
     sessionId: string,
     prompt: string,
     systemPrompt?: string,
+    agentId?: string,
   ): Promise<string> {
     const normalizedSystemPrompt = (systemPrompt ?? '').trim();
     const previousSystemPrompt = this.lastSystemPromptBySession.get(sessionId) ?? '';
@@ -1078,7 +1197,7 @@ export class OpenClawRuntimeAdapter extends EventEmitter implements CoworkRuntim
     }
 
     const client = this.requireGatewayClient();
-    const sessionKey = this.toSessionKey(sessionId);
+    const sessionKey = this.toSessionKey(sessionId, agentId);
     let hasHistory = false;
     try {
       const history = await client.request<{ messages?: unknown[] }>('chat.history', {
@@ -1374,6 +1493,65 @@ export class OpenClawRuntimeAdapter extends EventEmitter implements CoworkRuntim
     }
   }
 
+  /**
+   * Throttled SQLite store write for streaming message updates.
+   * Uses leading + trailing pattern identical to throttledEmitMessageUpdate.
+   * Final correctness is guaranteed by syncFinalAssistantWithHistory.
+   */
+  private throttledStoreUpdateMessage(
+    sessionId: string,
+    messageId: string,
+    content: string,
+    metadata: { isStreaming: boolean; isFinal: boolean },
+  ): void {
+    const now = Date.now();
+    const lastUpdate = this.lastStoreUpdateTime.get(messageId) ?? 0;
+    const elapsed = now - lastUpdate;
+
+    if (elapsed >= OpenClawRuntimeAdapter.STORE_UPDATE_THROTTLE_MS) {
+      this.clearPendingStoreUpdate(messageId);
+      this.lastStoreUpdateTime.set(messageId, now);
+      this.store.updateMessage(sessionId, messageId, { content, metadata });
+      return;
+    }
+
+    // Schedule a trailing write to ensure the latest content is persisted
+    this.clearPendingStoreUpdate(messageId);
+    this.pendingStoreUpdateTimer.set(messageId, setTimeout(() => {
+      this.pendingStoreUpdateTimer.delete(messageId);
+      this.lastStoreUpdateTime.set(messageId, Date.now());
+      // Guard: skip write if the session turn has already been cleaned up
+      const activeTurn = this.activeTurns.get(sessionId);
+      if (activeTurn?.assistantMessageId === messageId) {
+        this.store.updateMessage(sessionId, messageId, { content, metadata });
+      }
+    }, OpenClawRuntimeAdapter.STORE_UPDATE_THROTTLE_MS - elapsed));
+  }
+
+  private clearPendingStoreUpdate(messageId: string): void {
+    const timer = this.pendingStoreUpdateTimer.get(messageId);
+    if (timer) {
+      clearTimeout(timer);
+      this.pendingStoreUpdateTimer.delete(messageId);
+    }
+  }
+
+  /** Flush any pending throttled store write immediately (e.g. before segment split or final sync). */
+  private flushPendingStoreUpdate(sessionId: string, messageId: string): void {
+    const timer = this.pendingStoreUpdateTimer.get(messageId);
+    if (!timer) return;
+    clearTimeout(timer);
+    this.pendingStoreUpdateTimer.delete(messageId);
+    this.lastStoreUpdateTime.set(messageId, Date.now());
+    // Persist the latest in-memory content only; caller is responsible for metadata.
+    const turn = this.activeTurns.get(sessionId);
+    if (turn?.assistantMessageId === messageId && turn.currentAssistantSegmentText) {
+      this.store.updateMessage(sessionId, messageId, {
+        content: turn.currentAssistantSegmentText,
+      });
+    }
+  }
+
   private startTickWatchdog(): void {
     this.stopTickWatchdog();
     console.log('[TickWatchdog] started');
@@ -1808,7 +1986,7 @@ export class OpenClawRuntimeAdapter extends EventEmitter implements CoworkRuntim
     }
 
     this.rememberSessionKey(session.id, normalizedSessionKey);
-    this.rememberSessionKey(session.id, this.toSessionKey(session.id));
+    this.rememberSessionKey(session.id, this.toSessionKey(session.id, session.agentId));
     return session.id;
   }
 
@@ -2196,10 +2374,8 @@ export class OpenClawRuntimeAdapter extends EventEmitter implements CoworkRuntim
       turn.assistantMessageId = assistantMessage.id;
       this.emit('message', sessionId, assistantMessage);
     } else if (turn.assistantMessageId && turn.currentAssistantSegmentText) {
-      this.store.updateMessage(sessionId, turn.assistantMessageId, {
-        content: turn.currentAssistantSegmentText,
-        metadata: { isStreaming: true, isFinal: false },
-      });
+      this.throttledStoreUpdateMessage(sessionId, turn.assistantMessageId,
+        turn.currentAssistantSegmentText, { isStreaming: true, isFinal: false });
       this.throttledEmitMessageUpdate(sessionId, turn.assistantMessageId, turn.currentAssistantSegmentText);
     }
   }
@@ -2208,6 +2384,10 @@ export class OpenClawRuntimeAdapter extends EventEmitter implements CoworkRuntim
     if (!turn.assistantMessageId) return;
     const messageId = turn.assistantMessageId;
 
+    // Flush pending throttled updates so store content is current before reading.
+    this.flushPendingStoreUpdate(sessionId, messageId);
+    this.clearPendingMessageUpdate(messageId);
+
     // Committed text: use agentAssistantTextLength as the reliable segment length,
     // since currentText/currentAssistantSegmentText may be overwritten by chat deltas.
     // Read the actual content from the store (which was updated by processAgentAssistantText).
@@ -2219,10 +2399,6 @@ export class OpenClawRuntimeAdapter extends EventEmitter implements CoworkRuntim
       turn.committedAssistantText = `${turn.committedAssistantText}${storeContent}`;
     }
 
-    // Flush pending throttled update and mark the message as final.
-    // Don't overwrite the content — the store already has the correct text
-    // from processAgentAssistantText's real-time updates.
-    this.clearPendingMessageUpdate(messageId);
     this.store.updateMessage(sessionId, messageId, {
       metadata: { isStreaming: false, isFinal: true },
     });
@@ -2287,15 +2463,9 @@ export class OpenClawRuntimeAdapter extends EventEmitter implements CoworkRuntim
     }
 
     if (turn.assistantMessageId && segmentText !== previousSegmentText) {
-      this.store.updateMessage(sessionId, turn.assistantMessageId, {
-        content: segmentText,
-        metadata: {
-          isStreaming: true,
-          isFinal: false,
-        },
-      });
+      // Only update in-memory state; SQLite write and IPC emit are handled
+      // by processAgentAssistantText on the agent event path.
       turn.currentAssistantSegmentText = segmentText;
-      this.throttledEmitMessageUpdate(sessionId, turn.assistantMessageId, segmentText);
     }
   }
 
@@ -2312,8 +2482,8 @@ export class OpenClawRuntimeAdapter extends EventEmitter implements CoworkRuntim
     turn.currentAssistantSegmentText = finalSegmentText;
 
     if (turn.assistantMessageId) {
-      // Flush any pending throttled update and force-emit the latest store content
-      // so the renderer sees the final text even if the last throttled emit was skipped.
+      // Flush any pending throttled updates so store content is current.
+      this.flushPendingStoreUpdate(sessionId, turn.assistantMessageId);
       this.clearPendingMessageUpdate(turn.assistantMessageId);
       const storeSession = this.store.getSession(sessionId);
       const storeMsg = storeSession?.messages.find((m) => m.id === turn.assistantMessageId);
@@ -2407,7 +2577,9 @@ export class OpenClawRuntimeAdapter extends EventEmitter implements CoworkRuntim
 
     // Detect model API errors that are likely caused by unsupported image content
     // in tool results (e.g., Read tool returning image blocks for non-vision models).
-    if (/^4\d{2}\b/.test(errorMessage)) {
+    // Only match 400 Bad Request — other 4xx codes (403 forbidden, 429 rate limit, etc.)
+    // have unrelated causes and should show their original error message.
+    if (/^400\b/.test(errorMessage)) {
       errorMessage += '\n\n[Hint: If the model attempted to read an image file, this may be because the model does not support image input. Consider using a vision-capable model or avoid sending image files.]';
     }
 
@@ -2486,14 +2658,12 @@ export class OpenClawRuntimeAdapter extends EventEmitter implements CoworkRuntim
     const runId = typeof payload.runId === 'string' ? payload.runId.trim() : '';
     if (runId && this.sessionIdByRunId.has(runId)) {
       const sid = this.sessionIdByRunId.get(runId) ?? null;
-      console.log('[Debug:resolveSessionId] resolved by runId:', runId, '→', sid);
       return sid;
     }
 
     const sessionKey = typeof payload.sessionKey === 'string' ? payload.sessionKey.trim() : '';
     if (sessionKey) {
       const sessionId = this.resolveSessionIdBySessionKey(sessionKey);
-      console.log('[Debug:resolveSessionId] resolved by sessionKey:', sessionKey, '→', sessionId);
       if (sessionId) {
         // Re-create ActiveTurn for channel session follow-up turns
         this.ensureActiveTurn(sessionId, sessionKey, runId);
@@ -2506,19 +2676,17 @@ export class OpenClawRuntimeAdapter extends EventEmitter implements CoworkRuntim
 
     // Try to resolve channel-originated sessions
     if (sessionKey && this.channelSessionSync) {
-      console.log('[Debug:resolveSessionId] attempting channel resolve for sessionKey:', sessionKey);
       const channelSessionId = this.channelSessionSync.resolveOrCreateSession(sessionKey)
         || (!this.heartbeatSessionKeys.has(sessionKey) && this.channelSessionSync.resolveOrCreateMainAgentSession(sessionKey))
         || this.channelSessionSync.resolveOrCreateCronSession(sessionKey)
         || null;
-      console.log('[Debug:resolveSessionId] channel resolve — sessionKey:', sessionKey, '→', channelSessionId);
       if (channelSessionId) {
         // If this key was previously deleted, allow re-creation but skip history sync
         if (this.deletedChannelKeys.has(sessionKey)) {
           this.deletedChannelKeys.delete(sessionKey);
           this.fullySyncedSessions.add(channelSessionId);
           this.reCreatedChannelSessionIds.add(channelSessionId);
-          console.log('[Debug:resolveSessionId] re-created after delete, skipping history sync for:', sessionKey);
+          console.debug('[resolveSessionId] re-created after delete, skipping history sync for:', sessionKey);
         }
         this.rememberSessionKey(channelSessionId, sessionKey);
         this.ensureActiveTurn(channelSessionId, sessionKey, runId);
@@ -2529,7 +2697,7 @@ export class OpenClawRuntimeAdapter extends EventEmitter implements CoworkRuntim
       }
     }
 
-    console.log('[Debug:resolveSessionId] failed — runId:', runId, 'sessionKey:', sessionKey);
+    console.warn('[resolveSessionId] failed — runId:', runId, 'sessionKey:', sessionKey);
     return null;
   }
 
@@ -3058,12 +3226,19 @@ export class OpenClawRuntimeAdapter extends EventEmitter implements CoworkRuntim
       if (historyEntries.length > 0) {
         const lastUser = [...historyEntries].reverse().find((entry) => entry.role === 'user');
         if (lastUser) {
-          const userMessage = this.store.addMessage(sessionId, {
-            type: 'user',
-            content: lastUser.text,
-            metadata: {},
-          });
-          this.emit('message', sessionId, userMessage);
+          // Dedup: skip if this message already exists locally
+          const session = this.store.getSession(sessionId);
+          const alreadyExists = session?.messages.some(
+            (m: CoworkMessage) => m.type === 'user' && m.content.trim() === lastUser.text,
+          ) ?? false;
+          if (!alreadyExists) {
+            const userMessage = this.store.addMessage(sessionId, {
+              type: 'user',
+              content: lastUser.text,
+              metadata: {},
+            });
+            this.emit('message', sessionId, userMessage);
+          }
         }
       }
       this.channelSyncCursor.set(sessionId, historyEntries.length);
@@ -3102,9 +3277,9 @@ export class OpenClawRuntimeAdapter extends EventEmitter implements CoworkRuntim
     }
 
     const userIndicesToSync: number[] = [];
-    // Normal range: from firstNewIdx onwards
+    // Normal range: from firstNewIdx onwards, with dedup against local messages
     for (let i = firstNewIdx; i < historyEntries.length; i++) {
-      if (historyEntries[i].role === 'user') {
+      if (historyEntries[i].role === 'user' && !localUserTexts.has(historyEntries[i].text)) {
         userIndicesToSync.push(i);
       }
     }
@@ -3174,6 +3349,7 @@ export class OpenClawRuntimeAdapter extends EventEmitter implements CoworkRuntim
    *
    * Uses position-based matching to avoid false dedup of identical-content messages.
    */
+
   private async syncFullChannelHistory(sessionId: string, sessionKey: string): Promise<void> {
     if (this.fullySyncedSessions.has(sessionId)) return;
     this.fullySyncedSessions.add(sessionId);
@@ -3229,6 +3405,8 @@ export class OpenClawRuntimeAdapter extends EventEmitter implements CoworkRuntim
       if (turn.assistantMessageId) {
         this.clearPendingMessageUpdate(turn.assistantMessageId);
         this.lastMessageUpdateEmitTime.delete(turn.assistantMessageId);
+        this.clearPendingStoreUpdate(turn.assistantMessageId);
+        this.lastStoreUpdateTime.delete(turn.assistantMessageId);
       }
       turn.knownRunIds.forEach((knownRunId) => {
         this.sessionIdByRunId.delete(knownRunId);
@@ -3503,8 +3681,8 @@ export class OpenClawRuntimeAdapter extends EventEmitter implements CoworkRuntim
     pending.reject(error);
   }
 
-  private toSessionKey(sessionId: string): string {
-    return buildManagedSessionKey(sessionId);
+  private toSessionKey(sessionId: string, agentId?: string): string {
+    return buildManagedSessionKey(sessionId, agentId);
   }
 
   private requireGatewayClient(): GatewayClientLike {
@@ -3535,7 +3713,8 @@ export class OpenClawRuntimeAdapter extends EventEmitter implements CoworkRuntim
       }
     }
 
-    const managedKey = this.toSessionKey(normalizedSessionId);
+    const session = this.store.getSession(normalizedSessionId);
+    const managedKey = this.toSessionKey(normalizedSessionId, session?.agentId);
     if (!keys.includes(managedKey)) {
       keys.push(managedKey);
     }
diff --git a/src/main/libs/agentEngine/types.ts b/src/main/libs/agentEngine/types.ts
--- a/src/main/libs/agentEngine/types.ts
+++ b/src/main/libs/agentEngine/types.ts
@@ -34,6 +34,7 @@ export type CoworkStartOptions = {
   workspaceRoot?: string;
   confirmationMode?: 'modal' | 'text';
   imageAttachments?: CoworkImageAttachment[];
+  agentId?: string;
 };
 
 export type CoworkContinueOptions = {
diff --git a/src/main/libs/claudeSettings.ts b/src/main/libs/claudeSettings.ts
--- a/src/main/libs/claudeSettings.ts
+++ b/src/main/libs/claudeSettings.ts
@@ -74,6 +74,18 @@ export function setServerBaseUrlGetter(getter: () => string): void {
   serverBaseUrlGetter = getter;
 }
 
+// Cached server model metadata (populated when auth:getModels is called)
+// Keyed by modelId → { supportsImage }
+let serverModelMetadataCache: Map<string, { supportsImage?: boolean }> = new Map();
+
+export function updateServerModelMetadata(models: Array<{ modelId: string; supportsImage?: boolean }>): void {
+  serverModelMetadataCache = new Map(models.map(m => [m.modelId, { supportsImage: m.supportsImage }]));
+}
+
+export function clearServerModelMetadata(): void {
+  serverModelMetadataCache.clear();
+}
+
 const getStore = (): SqliteStore | null => {
   if (!storeGetter) {
     return null;
@@ -131,13 +143,15 @@ function tryLobsteraiServerFallback(modelId?: string): MatchedProvider | null {
   const effectiveModelId = modelId?.trim() || '';
   if (!effectiveModelId) return null;
   const baseURL = `${serverBaseUrl}/api/proxy/v1`;
-  console.log('[ClaudeSettings] lobsterai-server fallback activated:', { baseURL, modelId: effectiveModelId });
+  const cachedMeta = serverModelMetadataCache.get(effectiveModelId);
+  console.log('[ClaudeSettings] lobsterai-server fallback activated:', { baseURL, modelId: effectiveModelId, supportsImage: cachedMeta?.supportsImage });
   return {
     providerName: 'lobsterai-server',
-    providerConfig: { enabled: true, apiKey: tokens.accessToken, baseUrl: baseURL, apiFormat: 'openai', models: [{ id: effectiveModelId }] },
+    providerConfig: { enabled: true, apiKey: tokens.accessToken, baseUrl: baseURL, apiFormat: 'openai', models: [{ id: effectiveModelId, supportsImage: cachedMeta?.supportsImage }] },
     modelId: effectiveModelId,
     apiFormat: 'openai',
     baseURL,
+    supportsImage: cachedMeta?.supportsImage,
   };
 }
 
@@ -419,6 +433,40 @@ export function resolveRawApiConfig(): ApiConfigResolution {
   };
 }
 
+/**
+ * Collect apiKeys for ALL configured providers (not just the currently selected one).
+ * Used by OpenClaw config sync to pre-register all apiKeys as env vars at gateway
+ * startup, so switching between providers doesn't require a process restart.
+ *
+ * Returns a map of env-var-safe provider name → apiKey.
+ */
+export function resolveAllProviderApiKeys(): Record<string, string> {
+  const result: Record<string, string> = {};
+
+  // lobsterai-server: uses auth accessToken
+  const tokens = authTokensGetter?.();
+  const serverBaseUrl = serverBaseUrlGetter?.();
+  if (tokens?.accessToken && serverBaseUrl) {
+    result.SERVER = tokens.accessToken;
+  }
+
+  // All configured custom providers
+  const sqliteStore = getStore();
+  if (!sqliteStore) return result;
+  const appConfig = sqliteStore.get<AppConfig>('app_config');
+  if (!appConfig?.providers) return result;
+
+  for (const [providerName, providerConfig] of Object.entries(appConfig.providers)) {
+    if (!providerConfig?.enabled) continue;
+    const apiKey = providerConfig.apiKey?.trim();
+    if (!apiKey && providerRequiresApiKey(providerName)) continue;
+    const envName = providerName.toUpperCase().replace(/[^A-Z0-9]/g, '_');
+    result[envName] = apiKey || 'sk-lobsterai-local';
+  }
+
+  return result;
+}
+
 export function buildEnvForConfig(config: CoworkApiConfig): Record<string, string> {
   const baseEnv = { ...process.env } as Record<string, string>;
 
diff --git a/src/main/libs/coworkRunner.ts b/src/main/libs/coworkRunner.ts
--- a/src/main/libs/coworkRunner.ts
+++ b/src/main/libs/coworkRunner.ts
@@ -12,8 +12,8 @@ import { getElectronNodeRuntimePath, getEnhancedEnv, getEnhancedEnvWithTmpdir, g
 import { coworkLog, getCoworkLogPath } from './coworkLogger';
 import { ensurePythonPipReady, ensurePythonRuntimeReady } from './pythonRuntime';
 import { isQuestionLikeMemoryText, type CoworkMemoryGuardLevel } from './coworkMemoryExtractor';
-import { SCHEDULED_TASK_SWITCH_MESSAGE } from './scheduledTaskEnginePrompt';
 import { setCoworkProxySessionId } from './coworkOpenAICompatProxy';
+import { SCHEDULED_TASK_SWITCH_MESSAGE } from '../../scheduled-task/enginePrompt';
 import { z } from 'zod';
 
 const ATTACHMENT_LINE_RE = /^\s*(?:[-*]\s*)?(输入文件|input\s*file)\s*[:：]\s*(.+?)\s*$/i;
diff --git a/src/main/libs/openclawChannelSessionSync.ts b/src/main/libs/openclawChannelSessionSync.ts
--- a/src/main/libs/openclawChannelSessionSync.ts
+++ b/src/main/libs/openclawChannelSessionSync.ts
@@ -65,13 +65,20 @@ export const CHANNEL_PLATFORM_MAP: Record<string, IMPlatform> = {
   feishu: 'feishu',
   'dingtalk-connector': 'dingtalk',
   qqbot: 'qq',
-  wecom: 'wecom',
   'wecom-openclaw-plugin': 'wecom',
+  wecom: 'wecom',
+  popo: 'popo',
   'moltbot-popo': 'popo',
   nim: 'nim',
   'openclaw-weixin': 'weixin',
+  xiaomifeng: 'xiaomifeng',
 };
 
+/** Reverse map: IM platform → preferred OpenClaw channel name. */
+export const PLATFORM_TO_CHANNEL_MAP: Record<string, string> = Object.fromEntries(
+  Object.entries(CHANNEL_PLATFORM_MAP).map(([channel, platform]) => [platform, channel]),
+);
+
 /** Parse a channel sessionKey into platform + conversationId.
  *  Supports three formats:
  *  - OpenClaw format: "agent:{agentId}:{platform}:{subtype}:{conversationId}"
@@ -146,6 +153,18 @@ export function parseChannelSessionKey(sessionKey: string): { platform: IMPlatfo
   return { platform, conversationId };
 }
 
+/**
+ * Extract the agentId from a gateway session key.
+ * Key format: "agent:{agentId}:{channel}:..." → returns agentId.
+ * Returns null for legacy keys or non-agent keys.
+ */
+export function extractAgentIdFromKey(sessionKey: string): string | null {
+  if (!sessionKey.startsWith('agent:')) return null;
+  const secondColon = sessionKey.indexOf(':', 6); // skip "agent:"
+  if (secondColon <= 6) return null;
+  return sessionKey.slice(6, secondColon);
+}
+
 /** Match OpenClaw main agent session keys like "agent:main:main" or "agent:secondary:main". */
 const MAIN_AGENT_SESSION_RE = /^agent:[^:]+:main$/;
 
@@ -167,19 +186,24 @@ function extractCronJobId(sessionKey: string): string {
   return idx >= 0 ? sessionKey.slice(idx + 'cron:'.length) : sessionKey;
 }
 
-/** Map from platform (resolved) to title label. */
-const CHANNEL_TITLE_PREFIX: Record<string, string> = {
-  telegram: '[TG]',
-  discord: '[Discord]',
-  feishu: '[飞书]',
-  dingtalk: '[钉钉]',
-  qq: '[QQ]',
-  wecom: '[企微]',
-  'wecom-openclaw-plugin': '[企微]',
-  popo: '[POPO]',
-  nim: '[云信]',
-  weixin: '[微信]',
-};
+function getChannelTitlePrefix(platform: string): string {
+  const i18nMap: Record<string, string> = {
+    feishu: t('channelPrefixFeishu'),
+    dingtalk: t('channelPrefixDingtalk'),
+    wecom: t('channelPrefixWecom'),
+    'wecom-openclaw-plugin': t('channelPrefixWecom'),
+    nim: t('channelPrefixNim'),
+    weixin: t('channelPrefixWeixin'),
+  };
+  const staticMap: Record<string, string> = {
+    telegram: 'TG',
+    discord: 'Discord',
+    qq: 'QQ',
+    popo: 'POPO',
+  };
+  const label = i18nMap[platform] ?? staticMap[platform] ?? platform;
+  return `[${label}]`;
+}
 
 export interface ChannelSessionSyncDeps {
   coworkStore: CoworkStore;
@@ -201,13 +225,43 @@ export class OpenClawChannelSessionSync {
   /** Keys that have been tried and are not recognized — avoids repeated log noise. */
   private readonly rejectedKeys = new Set<string>();
 
+  /**
+   * Sessions created because the agent binding changed.
+   * These should skip syncFullChannelHistory to avoid pulling old gateway messages
+   * into the new session — only future incremental messages will appear.
+   */
+  private readonly agentChangedSessionIds = new Set<string>();
+
   constructor(deps: ChannelSessionSyncDeps) {
     this.coworkStore = deps.coworkStore;
     this.imStore = deps.imStore;
     this.getDefaultCwd = deps.getDefaultCwd;
     this.resolveJobName = deps.resolveJobName ?? null;
   }
 
+  /**
+   * Check if a gateway session key belongs to the agent currently bound to its platform.
+   * When users switch agent bindings, the gateway retains old sessions under the previous
+   * agentId. This method filters them out so only the current agent's sessions are processed.
+   */
+  isCurrentBindingKey(sessionKey: string): boolean {
+    const parsed = parseChannelSessionKey(sessionKey);
+    if (!parsed) return true; // Not a channel key — let other logic handle it
+    const keyAgentId = extractAgentIdFromKey(sessionKey);
+    if (!keyAgentId) return true; // Legacy key without agentId — allow
+    const imSettings = this.imStore.getIMSettings();
+    const currentAgentId = imSettings.platformAgentBindings?.[parsed.platform] || 'main';
+    return keyAgentId === currentAgentId;
+  }
+
+  /**
+   * Whether the session was created due to an agent binding change.
+   * Such sessions should skip full history sync — only future messages matter.
+   */
+  isAgentChangedSession(sessionId: string): boolean {
+    return this.agentChangedSessionIds.has(sessionId);
+  }
+
   /**
    * Try to resolve or create a local Cowork session for a channel-originated sessionKey.
    * Returns the local sessionId if the sessionKey belongs to a channel, or null if not.
@@ -241,11 +295,34 @@ export class OpenClawChannelSessionSync {
 
     // 4. Check persistent mapping in im_session_mappings
     const existingMapping = this.imStore.getSessionMapping(parsed.conversationId, parsed.platform);
-    console.log('[ChannelSessionSync] existing mapping:', existingMapping ? `coworkSessionId=${existingMapping.coworkSessionId}` : 'none');
+    console.log('[ChannelSessionSync] existing mapping:', existingMapping ? `coworkSessionId=${existingMapping.coworkSessionId} agentId=${existingMapping.agentId}` : 'none');
     if (existingMapping) {
       // Verify the Cowork session still exists
       const session = this.coworkStore.getSession(existingMapping.coworkSessionId);
       if (session) {
+        // Check if the agent binding has changed since this mapping was created.
+        // When platformAgentBindings changes, the mapping's agentId becomes stale.
+        // Create a new session for the new agent and update the mapping.
+        const imSettings = this.imStore.getIMSettings();
+        const currentAgentId = imSettings.platformAgentBindings?.[parsed.platform] || 'main';
+        if (existingMapping.agentId !== currentAgentId) {
+          console.log('[ChannelSessionSync] agent binding changed:', existingMapping.agentId, '→', currentAgentId, '— creating new session');
+          const titlePrefix = getChannelTitlePrefix(parsed.platform);
+          const displayId = parsed.conversationId.includes('@')
+            ? parsed.conversationId.split('@')[0]
+            : parsed.conversationId;
+          const shortId = displayId.length > 12 ? displayId.slice(-12) : displayId;
+          const title = `${titlePrefix} ${shortId}`;
+          const cwd = this.getDefaultCwd();
+          const newSession = this.coworkStore.createSession(title, cwd, '', 'local', [], currentAgentId);
+          console.log('[ChannelSessionSync] created new session for agent change:', newSession.id);
+          this.imStore.updateSessionMappingTarget(parsed.conversationId, parsed.platform, newSession.id, currentAgentId);
+          this.syncedSessionKeys.set(sessionKey, newSession.id);
+          // Mark so pollChannelSessions skips full history sync for this session —
+          // old gateway messages should not be pulled into the new session.
+          this.agentChangedSessionIds.add(newSession.id);
+          return newSession.id;
+        }
         console.log('[ChannelSessionSync] existing cowork session found, reusing:', existingMapping.coworkSessionId);
         this.syncedSessionKeys.set(sessionKey, existingMapping.coworkSessionId);
         this.imStore.updateSessionLastActive(parsed.conversationId, parsed.platform);
@@ -257,7 +334,7 @@ export class OpenClawChannelSessionSync {
     }
 
     // 5. Create new Cowork session
-    const titlePrefix = CHANNEL_TITLE_PREFIX[parsed.platform] || `[${parsed.platform}]`;
+    const titlePrefix = getChannelTitlePrefix(parsed.platform);
     // For conversationIds that look like email addresses (e.g. POPO),
     // use the local part before '@' as the display name.
     const displayId = parsed.conversationId.includes('@')
@@ -268,15 +345,18 @@ export class OpenClawChannelSessionSync {
       : displayId;
     const title = `${titlePrefix} ${shortId}`;
     const cwd = this.getDefaultCwd();
-    console.log('[ChannelSessionSync] creating new cowork session: title=', title, 'cwd=', cwd);
+    // Look up the per-platform agent binding so the session is filed under the correct agent.
+    const imSettings = this.imStore.getIMSettings();
+    const agentId = imSettings.platformAgentBindings?.[parsed.platform] || 'main';
+    console.log('[ChannelSessionSync] creating new cowork session: title=', title, 'cwd=', cwd, 'agentId=', agentId);
 
-    const session = this.coworkStore.createSession(title, cwd, '', 'local');
+    const session = this.coworkStore.createSession(title, cwd, '', 'local', [], agentId);
     console.log(
       `[ChannelSessionSync] Created session for ${parsed.platform} conversation ${parsed.conversationId}: ${session.id}`,
     );
 
     // 6. Persist mapping
-    this.imStore.createSessionMapping(parsed.conversationId, parsed.platform, session.id);
+    this.imStore.createSessionMapping(parsed.conversationId, parsed.platform, session.id, agentId);
     console.log('[ChannelSessionSync] persisted mapping: conversationId=', parsed.conversationId, '→ sessionId=', session.id);
 
     // 7. Cache
diff --git a/src/main/libs/openclawConfigSync.ts b/src/main/libs/openclawConfigSync.ts
--- a/src/main/libs/openclawConfigSync.ts
+++ b/src/main/libs/openclawConfigSync.ts
@@ -1,15 +1,15 @@
 import { app } from 'electron';
 import fs from 'fs';
 import path from 'path';
-import type { CoworkConfig, CoworkExecutionMode } from '../coworkStore';
-import type { TelegramOpenClawConfig, DiscordOpenClawConfig } from '../im/types';
+import type { CoworkConfig, CoworkExecutionMode, Agent } from '../coworkStore';
+import type { TelegramOpenClawConfig, DiscordOpenClawConfig, IMSettings } from '../im/types';
 import type { DingTalkOpenClawConfig, FeishuOpenClawConfig, QQOpenClawConfig, WecomOpenClawConfig, PopoOpenClawConfig, NimConfig, WeixinOpenClawConfig } from '../im/types';
-import { resolveRawApiConfig } from './claudeSettings';
+import { resolveRawApiConfig, resolveAllProviderApiKeys } from './claudeSettings';
 import type { OpenClawEngineManager } from './openclawEngineManager';
 import { parseChannelSessionKey } from './openclawChannelSessionSync';
 import type { McpToolManifestEntry } from './mcpServerManager';
 import { hasBundledOpenClawExtension } from './openclawLocalExtensions';
-import { buildScheduledTaskEnginePrompt } from './scheduledTaskEnginePrompt';
+import { buildScheduledTaskEnginePrompt } from '../../scheduled-task/enginePrompt';
 
 export type McpBridgeConfig = {
   callbackUrl: string;
@@ -45,6 +45,7 @@ const normalizeModelName = (modelId: string): string => {
   return slashIndex >= 0 ? trimmed.slice(slashIndex + 1) : trimmed;
 };
 
+
 const MANAGED_OWNER_ALLOW_FROM = [
   // Internal `chat.send` turns identify the sender as bare `gateway-client`.
   // Prefixing with `webchat:` does not round-trip through owner resolution,
@@ -77,6 +78,15 @@ const DISABLED_MANAGED_SKILL_NAMES = Object.entries(MANAGED_SKILL_ENTRY_OVERRIDE
   .filter(([, value]) => value.enabled === false)
   .map(([name]) => name);
 
+/**
+ * Build the env var name for a provider's apiKey.
+ * Must match the key format produced by resolveAllProviderApiKeys() in claudeSettings.ts.
+ */
+const providerApiKeyEnvVar = (providerName: string): string => {
+  const envName = providerName.toUpperCase().replace(/[^A-Z0-9]/g, '_');
+  return `LOBSTER_APIKEY_${envName}`;
+};
+
 const MANAGED_WEB_SEARCH_POLICY_PROMPT = [
   '## Web Search',
   '',
@@ -324,7 +334,7 @@ const buildProviderSelection = (options: {
       providerConfig: {
         baseUrl: strippedBaseUrl,
         api: 'openai-completions',
-        apiKey: options.apiKey,
+        apiKey: `\${${providerApiKeyEnvVar('server')}}`,
         auth: 'api-key',
         models: [{
           id: options.modelId,
@@ -345,7 +355,7 @@ const buildProviderSelection = (options: {
       providerConfig: {
         baseUrl: normalizeKimiCodingBaseUrl(options.baseURL),
         api: 'anthropic-messages',
-        apiKey: '${LOBSTER_PROVIDER_API_KEY}',
+        apiKey: `\${${providerApiKeyEnvVar(providerName)}}`,
         auth: 'api-key',
         models: [
           {
@@ -378,7 +388,7 @@ const buildProviderSelection = (options: {
       providerConfig: {
         baseUrl: normalizeMoonshotBaseUrl(options.baseURL),
         api: 'openai-completions',
-        apiKey: '${LOBSTER_PROVIDER_API_KEY}',
+        apiKey: `\${${providerApiKeyEnvVar(providerName)}}`,
         auth: 'api-key',
         models: [
           {
@@ -409,7 +419,7 @@ const buildProviderSelection = (options: {
     providerConfig: {
       baseUrl: stripChatCompletionsSuffix(options.baseURL),
       api: providerApi,
-      apiKey: '${LOBSTER_PROVIDER_API_KEY}',
+      apiKey: `\${${providerApiKeyEnvVar(providerName)}}`,
       auth: 'api-key',
       models: [
         {
@@ -461,8 +471,10 @@ type OpenClawConfigSyncDeps = {
   getPopoConfig: () => PopoOpenClawConfig | null;
   getNimConfig: () => NimConfig | null;
   getWeixinConfig: () => WeixinOpenClawConfig | null;
+  getIMSettings?: () => IMSettings | null;
   getMcpBridgeConfig?: () => McpBridgeConfig | null;
   getSkillsList?: () => Array<{ id: string; enabled: boolean }>;
+  getAgents?: () => Agent[];
 };
 
 export class OpenClawConfigSync {
@@ -477,8 +489,10 @@ export class OpenClawConfigSync {
   private readonly getPopoConfig: () => PopoOpenClawConfig | null;
   private readonly getNimConfig: () => NimConfig | null;
   private readonly getWeixinConfig: () => WeixinOpenClawConfig | null;
+  private readonly getIMSettings?: () => IMSettings | null;
   private readonly getMcpBridgeConfig?: () => McpBridgeConfig | null;
   private readonly getSkillsList?: () => Array<{ id: string; enabled: boolean }>;
+  private readonly getAgents?: () => Agent[];
 
   constructor(deps: OpenClawConfigSyncDeps) {
     this.engineManager = deps.engineManager;
@@ -492,8 +506,10 @@ export class OpenClawConfigSync {
     this.getPopoConfig = deps.getPopoConfig;
     this.getNimConfig = deps.getNimConfig;
     this.getWeixinConfig = deps.getWeixinConfig;
+    this.getIMSettings = deps.getIMSettings;
     this.getMcpBridgeConfig = deps.getMcpBridgeConfig;
     this.getSkillsList = deps.getSkillsList;
+    this.getAgents = deps.getAgents;
   }
 
   sync(reason: string): OpenClawConfigSyncResult {
@@ -511,6 +527,7 @@ export class OpenClawConfigSync {
       const workspaceDir = (coworkConfig.workingDirectory || '').trim();
       const resolvedWorkspaceDir = workspaceDir || path.join(app.getPath('home'), '.openclaw', 'workspace');
       const agentsMdWarning = this.syncAgentsMd(resolvedWorkspaceDir, coworkConfig);
+      this.syncPerAgentWorkspaces(resolvedWorkspaceDir, coworkConfig);
       if (agentsMdWarning) result.agentsMdWarning = agentsMdWarning;
       return result;
     }
@@ -593,7 +610,9 @@ export class OpenClawConfigSync {
           },
           ...(workspaceDir ? { workspace: path.resolve(workspaceDir) } : {}),
         },
+        ...this.buildAgentsList(),
       },
+      ...this.buildBindings(),
       session: {
         dmScope: 'per-channel-peer',
       },
@@ -941,6 +960,37 @@ export class OpenClawConfigSync {
     };
     managedConfig.channels = { ...(managedConfig.channels as Record<string, unknown> || {}), 'openclaw-weixin': weixinChannel };
 
+    // Inject _agentBinding into channel configs that have a non-main binding,
+    // forcing those channels to restart when the binding changes.  OpenClaw
+    // channel plugins capture their config at startup and never refresh it,
+    // so bindings-only config changes (kind: "none" in the reload plan) are
+    // invisible to running plugins.  By touching the channel config we trigger
+    // a "channels.*" diff path which forces the plugin to restart.
+    const platformBindingsForSentinel = this.getIMSettings?.()?.platformAgentBindings;
+    if (platformBindingsForSentinel) {
+      // Map openclaw channel key → platform key
+      const channelToPlatform: Record<string, string> = {
+        'dingtalk-connector': 'dingtalk',
+        feishu: 'feishu',
+        telegram: 'telegram',
+        discord: 'discord',
+        qqbot: 'qq',
+        wecom: 'wecom',
+        'moltbot-popo': 'popo',
+        nim: 'nim',
+        'openclaw-weixin': 'weixin',
+      };
+      const channels = (managedConfig.channels ?? {}) as Record<string, Record<string, unknown>>;
+      for (const channelKey of Object.keys(channels)) {
+        if (!channels[channelKey] || typeof channels[channelKey] !== 'object') continue;
+        const platformKey = channelToPlatform[channelKey];
+        const boundAgentId = platformKey ? platformBindingsForSentinel[platformKey] : undefined;
+        if (boundAgentId && boundAgentId !== 'main') {
+          channels[channelKey]._agentBinding = boundAgentId;
+        }
+      }
+    }
+
     const nextContent = `${JSON.stringify(managedConfig, null, 2)}\n`;
     console.log('[OpenClawConfigSync] sync() managedConfig key fields:', {
       providers: (managedConfig.models as Record<string, unknown>)?.providers,
@@ -979,6 +1029,9 @@ export class OpenClawConfigSync {
     const resolvedWorkspaceDir = workspaceDir || path.join(app.getPath('home'), '.openclaw', 'workspace');
     const agentsMdWarning = this.syncAgentsMd(resolvedWorkspaceDir, coworkConfig);
 
+    // Sync per-agent workspace files (SOUL.md, IDENTITY.md, AGENTS.md) for non-main agents
+    this.syncPerAgentWorkspaces(resolvedWorkspaceDir, coworkConfig);
+
     return {
       ok: true,
       changed: configChanged || sessionStoreChanged,
@@ -995,12 +1048,18 @@ export class OpenClawConfigSync {
   collectSecretEnvVars(): Record<string, string> {
     const env: Record<string, string> = {};
 
-    // Provider API Key
-    const apiResolution = resolveRawApiConfig();
-    // Provider API Key — always set so stale openclaw.json with
-    // ${LOBSTER_PROVIDER_API_KEY} placeholder doesn't crash the gateway.
-    // OpenClaw treats empty string as "missing", so use a non-empty placeholder.
-    env.LOBSTER_PROVIDER_API_KEY = apiResolution.config?.apiKey || 'unconfigured';
+    // Provider API Keys — one per configured provider so switching models
+    // never changes env vars and avoids gateway process restarts.
+    const allApiKeys = resolveAllProviderApiKeys();
+    for (const [envSuffix, apiKey] of Object.entries(allApiKeys)) {
+      env[`LOBSTER_APIKEY_${envSuffix}`] = apiKey;
+    }
+    // Legacy fallback: keep LOBSTER_PROVIDER_API_KEY set to a stable value so stale
+    // openclaw.json files with the old placeholder don't crash the gateway.
+    // Use the active provider's key if available, but ONLY for the first sync —
+    // after that, openclaw.json uses provider-specific placeholders and this var
+    // is never resolved. Use a fixed value to avoid secretEnvVarsChanged on switch.
+    env.LOBSTER_PROVIDER_API_KEY = 'legacy-unused';
 
     // MCP Bridge Secret — always set so stale openclaw.json with
     // ${LOBSTER_MCP_BRIDGE_SECRET} placeholder doesn't crash the gateway.
@@ -1119,7 +1178,7 @@ export class OpenClawConfigSync {
         }
       }
 
-      if (!shouldMigrateManagedModelRefs || !sessionKey.startsWith('agent:main:lobsterai:')) {
+      if (!shouldMigrateManagedModelRefs || !(/^agent:[^:]+:lobsterai:/.test(sessionKey))) {
         continue;
       }
 
@@ -1278,6 +1337,169 @@ export class OpenClawConfigSync {
     }
   }
 
+  /**
+   * Build the `agents.list` config array for openclaw.json.
+   *
+   * The main agent uses the user's configured workspace directory (via
+   * `agents.defaults.workspace`).  Non-main agents omit `workspace` so
+   * OpenClaw falls back to its default: `{STATE_DIR}/workspace-{agentId}/`.
+   * This keeps custom agent workspaces under the openclaw state directory
+   * rather than coupling them to the user's working directory.
+   *
+   * Per-agent `identity` (name, emoji) is set from the agent database so
+   * OpenClaw picks it up natively.
+   */
+  private buildAgentsList(): { list?: Array<Record<string, unknown>> } {
+    const agents = this.getAgents?.() ?? [];
+
+    const list: Array<Record<string, unknown>> = [
+      {
+        id: 'main',
+        default: true,
+      },
+    ];
+
+    for (const agent of agents) {
+      if (agent.id === 'main' || !agent.enabled) continue;
+
+      list.push({
+        id: agent.id,
+        // Omit `workspace` — OpenClaw defaults to {STATE_DIR}/workspace-{agentId}/
+        // which keeps agent workspaces decoupled from the user's working directory.
+        ...(agent.name || agent.icon ? {
+          identity: {
+            ...(agent.name ? { name: agent.name } : {}),
+            ...(agent.icon ? { emoji: agent.icon } : {}),
+          },
+        } : {}),
+        // Per-agent skill whitelist: only when skillIds is non-empty.
+        // OpenClaw's resolveAgentSkillsFilter() uses this to filter available skills.
+        ...(agent.skillIds && agent.skillIds.length > 0 ? { skills: agent.skillIds } : {}),
+      });
+    }
+
+    return list.length > 0 ? { list } : {};
+  }
+
+  /**
+   * Build the `bindings` config array for openclaw.json.
+   *
+   * Each IM platform can be independently bound to a different agent via
+   * `IMSettings.platformAgentBindings`.  Only channels with an explicit
+   * non-main binding produce an entry.
+   */
+  private buildBindings(): { bindings?: Array<Record<string, unknown>> } {
+    const imSettings = this.getIMSettings?.();
+    const platformBindings = imSettings?.platformAgentBindings;
+    if (!platformBindings || Object.keys(platformBindings).length === 0) return {};
+
+    const agents = this.getAgents?.() ?? [];
+
+    // Map openclaw channel name → platform key used in platformAgentBindings
+    const channelMap: Array<{ getter: () => { enabled: boolean } | null; channel: string; platform: string }> = [
+      { getter: () => this.getDingTalkConfig(), channel: 'dingtalk-connector', platform: 'dingtalk' },
+      { getter: () => this.getFeishuConfig(), channel: 'feishu', platform: 'feishu' },
+      { getter: () => this.getTelegramOpenClawConfig?.() ?? null, channel: 'telegram', platform: 'telegram' },
+      { getter: () => this.getDiscordOpenClawConfig?.() ?? null, channel: 'discord', platform: 'discord' },
+      { getter: () => this.getQQConfig(), channel: 'qqbot', platform: 'qq' },
+      { getter: () => this.getWecomConfig(), channel: 'wecom', platform: 'wecom' },
+      { getter: () => this.getPopoConfig(), channel: 'moltbot-popo', platform: 'popo' },
+      { getter: () => this.getNimConfig(), channel: 'nim', platform: 'nim' },
+      { getter: () => this.getWeixinConfig(), channel: 'openclaw-weixin', platform: 'weixin' },
+    ];
+
+    const bindings: Array<Record<string, unknown>> = [];
+    for (const { getter, channel, platform } of channelMap) {
+      const agentId = platformBindings[platform];
+      if (!agentId || agentId === 'main') continue;
+
+      // Verify the target agent actually exists and is enabled
+      const targetAgent = agents.find((a) => a.id === agentId && a.enabled);
+      if (!targetAgent) continue;
+
+      try {
+        const cfg = getter();
+        if (cfg?.enabled) {
+          bindings.push({ agentId, match: { channel } });
+        }
+      } catch {
+        // Skip channels that fail to load config
+      }
+    }
+
+    return bindings.length > 0 ? { bindings } : {};
+  }
+
+  /**
+   * Sync workspace files (SOUL.md, IDENTITY.md, AGENTS.md) for each non-main agent.
+   * The main agent's workspace is synced by `syncAgentsMd`. Non-main agents
+   * get their own workspace directories under the openclaw state directory.
+   */
+  private syncPerAgentWorkspaces(_mainWorkspaceDir: string, coworkConfig: CoworkConfig): void {
+    const agents = this.getAgents?.() ?? [];
+    // Use the openclaw state directory as base, matching OpenClaw's own fallback
+    // logic: {STATE_DIR}/workspace-{agentId}/
+    const stateDir = this.engineManager.getStateDir();
+
+    for (const agent of agents) {
+      if (agent.id === 'main' || !agent.enabled) continue;
+
+      const agentWorkspace = path.join(stateDir, `workspace-${agent.id}`);
+      try {
+        ensureDir(agentWorkspace);
+
+        // Sync SOUL.md — agent's system prompt
+        const soulPath = path.join(agentWorkspace, 'SOUL.md');
+        const soulContent = (agent.systemPrompt || '').trim();
+        this.syncFileIfChanged(soulPath, soulContent ? `${soulContent}\n` : '');
+
+        // Sync IDENTITY.md — agent's identity description
+        const identityPath = path.join(agentWorkspace, 'IDENTITY.md');
+        const identityContent = (agent.identity || '').trim();
+        this.syncFileIfChanged(identityPath, identityContent ? `${identityContent}\n` : '');
+
+        // Sync AGENTS.md for this agent (reuse same logic as main agent)
+        this.syncAgentsMd(agentWorkspace, {
+          ...coworkConfig,
+          systemPrompt: agent.systemPrompt || '',
+        });
+
+        // Ensure memory directory exists
+        const memoryDir = path.join(agentWorkspace, 'memory');
+        ensureDir(memoryDir);
+
+        // Ensure MEMORY.md exists
+        const memoryPath = path.join(agentWorkspace, 'MEMORY.md');
+        if (!fs.existsSync(memoryPath)) {
+          fs.writeFileSync(memoryPath, '', 'utf8');
+        }
+      } catch (error) {
+        console.warn(
+          `[OpenClawConfigSync] Failed to sync workspace for agent ${agent.id}:`,
+          error instanceof Error ? error.message : String(error),
+        );
+      }
+    }
+  }
+
+  /** Write a file only if its content has changed. */
+  private syncFileIfChanged(filePath: string, content: string): void {
+    try {
+      const existing = fs.readFileSync(filePath, 'utf8');
+      if (existing === content) return;
+    } catch {
+      // File doesn't exist yet
+    }
+    if (content) {
+      this.atomicWriteFile(filePath, content);
+    } else {
+      // Empty content — create empty file if it doesn't exist
+      if (!fs.existsSync(filePath)) {
+        fs.writeFileSync(filePath, '', 'utf8');
+      }
+    }
+  }
+
   /** Atomic file write via tmp + rename, consistent with openclaw.json writes. */
   private atomicWriteFile(filePath: string, content: string): void {
     const tmpPath = `${filePath}.tmp-${Date.now()}`;
diff --git a/src/main/libs/openclawEngineManager.ts b/src/main/libs/openclawEngineManager.ts
--- a/src/main/libs/openclawEngineManager.ts
+++ b/src/main/libs/openclawEngineManager.ts
@@ -5,7 +5,7 @@ import { EventEmitter } from 'events';
 import fs from 'fs';
 import net from 'net';
 import path from 'path';
-import { getElectronNodeRuntimePath, ensureElectronNodeShim } from './coworkUtil';
+import { getElectronNodeRuntimePath, ensureElectronNodeShim, getSkillsRoot } from './coworkUtil';
 import { syncLocalOpenClawExtensionsIntoRuntime } from './openclawLocalExtensions';
 import { appendPythonRuntimeToEnv } from './pythonRuntime';
 import { isSystemProxyEnabled, resolveSystemProxyUrl } from './systemProxy';
@@ -390,9 +390,12 @@ export class OpenClawEngineManager extends EventEmitter {
     console.log(`[OpenClaw] compile cache dir: ${compileCacheDir}`);
     const electronNodeRuntimePath = getElectronNodeRuntimePath();
     const cliShimDir = this.ensureBundledCliShims();
+    const skillsRoot = getSkillsRoot().replace(/\\/g, '/');
 
     const env: NodeJS.ProcessEnv = {
       ...process.env,
+      SKILLS_ROOT: skillsRoot,
+      LOBSTERAI_SKILLS_ROOT: skillsRoot,
       OPENCLAW_HOME: runtime.root,
       OPENCLAW_STATE_DIR: this.stateDir,
       OPENCLAW_CONFIG_PATH: this.configPath,
diff --git a/src/main/libs/openclawHistory.ts b/src/main/libs/openclawHistory.ts
--- a/src/main/libs/openclawHistory.ts
+++ b/src/main/libs/openclawHistory.ts
@@ -1,7 +1,7 @@
 import {
   parseScheduledReminderPrompt,
   parseSimpleScheduledReminderText,
-} from '../../common/scheduledReminderText';
+} from '../../scheduled-task/reminderText';
 
 type GatewayHistoryRole = 'user' | 'assistant' | 'system';
 
diff --git a/src/main/main.ts b/src/main/main.ts
--- a/src/main/main.ts
+++ b/src/main/main.ts
@@ -5,6 +5,7 @@ import fs from 'fs';
 import os from 'os';
 import { SqliteStore } from './sqliteStore';
 import { CoworkStore } from './coworkStore';
+import { AgentManager } from './agentManager';
 import { CoworkRunner } from './libs/coworkRunner';
 import {
   ClaudeRuntimeAdapter,
@@ -14,7 +15,7 @@ import {
 } from './libs/agentEngine';
 import { SkillManager } from './skillManager';
 import type { PermissionResult } from '@anthropic-ai/claude-agent-sdk';
-import { getCurrentApiConfig, resolveCurrentApiConfig, setStoreGetter, setAuthTokensGetter, setServerBaseUrlGetter } from './libs/claudeSettings';
+import { getCurrentApiConfig, resolveCurrentApiConfig, setStoreGetter, setAuthTokensGetter, setServerBaseUrlGetter, updateServerModelMetadata, clearServerModelMetadata } from './libs/claudeSettings';
 import { saveCoworkApiConfig } from './libs/coworkConfigStore';
 import { generateSessionTitle, probeCoworkModelReadiness } from './libs/coworkUtil';
 import { startCoworkOpenAICompatProxy, stopCoworkOpenAICompatProxy, setProxyTokenRefresher } from './libs/coworkOpenAICompatProxy';
@@ -43,6 +44,8 @@ import {
   OpenClawChannelSessionSync,
   buildManagedSessionKey,
   DEFAULT_MANAGED_AGENT_ID,
+  CHANNEL_PLATFORM_MAP,
+  PLATFORM_TO_CHANNEL_MAP,
 } from './libs/openclawChannelSessionSync';
 import { IMGatewayManager, IMPlatform, IMGatewayConfig } from './im';
 import { APP_NAME } from './appConstants';
@@ -51,9 +54,10 @@ import { createTray, destroyTray, updateTrayMenu } from './trayManager';
 import { setLanguage, t } from './i18n';
 import { isAutoLaunched, getAutoLaunchEnabled, setAutoLaunchEnabled } from './autoLaunchManager';
 import { McpStore } from './mcpStore';
-import { CronJobService } from './libs/cronJobService';
-import { migrateScheduledTasksToOpenclaw, migrateScheduledTaskRunsToOpenclaw } from './libs/migrateScheduledTasks';
-import { buildScheduledTaskEnginePrompt } from './libs/scheduledTaskEnginePrompt';
+import { CronJobService } from '../scheduled-task/cronJobService';
+import { migrateScheduledTasksToOpenclaw, migrateScheduledTaskRunsToOpenclaw } from '../scheduled-task/migrate';
+import { buildScheduledTaskEnginePrompt } from '../scheduled-task/enginePrompt';
+import { IpcChannel as ScheduledTaskIpc, DeliveryMode as STDeliveryMode, SessionTarget as STSessionTarget, PayloadKind as STPayloadKind } from '../scheduled-task/constants';
 import { McpServerManager } from './libs/mcpServerManager';
 import { getServerApiBaseUrl, refreshEndpointsTestMode } from './libs/endpoints';
 import { McpBridgeServer } from './libs/mcpBridgeServer';
@@ -86,14 +90,16 @@ const IPC_MAX_ITEMS = 40;
 const MAX_INLINE_ATTACHMENT_BYTES = 25 * 1024 * 1024;
 const ENGINE_NOT_READY_CODE = 'ENGINE_NOT_READY';
 const SCHEDULED_TASK_CHANNEL_OPTIONS = [
-  { value: 'last', label: 'Last conversation' },
   { value: 'dingtalk-connector', label: 'DingTalk' },
   { value: 'feishu', label: 'Feishu' },
   { value: 'telegram', label: 'Telegram' },
   { value: 'discord', label: 'Discord' },
   { value: 'qqbot', label: 'QQ' },
   { value: 'wecom', label: 'WeCom' },
   { value: 'popo', label: 'POPO' },
+  { value: 'nim', label: 'NIM' },
+  { value: 'openclaw-weixin', label: 'WeChat' },
+  { value: 'xiaomifeng', label: 'Xiaomifeng' },
 ] as const;
 const MIME_EXTENSION_MAP: Record<string, string> = {
   'image/png': '.png',
@@ -696,16 +702,43 @@ const bootstrapOpenClawEngine = async (options: { forceReinstall?: boolean; reas
   return promise;
 };
 
+// Module-level handle so ensureOpenClawRunningForCowork can await any in-flight
+// proactive token refresh before syncing config to the gateway.
+let pendingTokenRefresh: Promise<string | null> | null = null;
+
 const ensureOpenClawRunningForCowork = async () => {
   const manager = getOpenClawEngineManager();
   const status = manager.getStatus();
   if (status.phase === 'running') {
-    return status;
+    // If the gateway is already running but a token refresh is in flight,
+    // wait for it and then re-sync secret env vars so the gateway gets
+    // the fresh token on its next restart (or immediately if we detect a change).
+    if (pendingTokenRefresh) {
+      console.log('[OpenClaw] ensureRunning: awaiting pending token refresh before proceeding');
+      await pendingTokenRefresh.catch(() => {});
+      // After refresh, update gateway secret env vars in case the token changed.
+      const nextEnv = getOpenClawConfigSync().collectSecretEnvVars();
+      const prevEnv = getOpenClawEngineManager().getSecretEnvVars();
+      if (JSON.stringify(nextEnv) !== JSON.stringify(prevEnv)) {
+        console.log('[OpenClaw] ensureRunning: token changed during pending refresh, syncing config');
+        getOpenClawEngineManager().setSecretEnvVars(nextEnv);
+        // Gateway env vars are fixed at spawn; must restart to pick up new token.
+        await syncOpenClawConfig({ reason: 'token-refresh:ensureRunning', restartGatewayIfRunning: true });
+      }
+    }
+    return manager.getStatus();
   }
   if (status.phase === 'starting') {
     return status;
   }
 
+  // Wait for any in-flight token refresh so that the gateway starts with
+  // a fresh token rather than the stale one that triggered the refresh.
+  if (pendingTokenRefresh) {
+    console.log('[OpenClaw] ensureRunning: awaiting pending token refresh before gateway start');
+    await pendingTokenRefresh.catch(() => {});
+  }
+
   // Ensure MCP bridge is started and config is synced before launching the gateway,
   // so that mcpBridge tools are available in openclaw.json when the gateway loads.
   await startMcpBridge().catch((err: unknown) => {
@@ -734,6 +767,14 @@ const getCoworkStore = () => {
   return coworkStore;
 };
 
+let agentManager: AgentManager | null = null;
+const getAgentManager = () => {
+  if (!agentManager) {
+    agentManager = new AgentManager(getCoworkStore());
+  }
+  return agentManager;
+};
+
 const resolveCoworkAgentEngine = (): CoworkAgentEngine => {
   const configured = getCoworkStore().getConfig().agentEngine;
   return configured === 'openclaw' ? 'openclaw' : 'yd_cowork';
@@ -801,6 +842,13 @@ const getOpenClawConfigSync = (): OpenClawConfigSync => {
           return null;
         }
       },
+      getIMSettings: () => {
+        try {
+          return getIMGatewayManager().getConfig().settings;
+        } catch {
+          return null;
+        }
+      },
       getDiscordOpenClawConfig: () => {
         try {
           return getIMGatewayManager()?.getConfig()?.discord ?? null;
@@ -818,6 +866,7 @@ const getOpenClawConfigSync = (): OpenClawConfigSync => {
           tools: mcpServerManager.toolManifest,
         };
       },
+      getAgents: () => getCoworkStore().listAgents(),
     });
   }
   return openClawConfigSync;
@@ -1278,6 +1327,16 @@ const getIMGatewayManager = () => {
               sessionId,
             );
           }
+          const channelName = PLATFORM_TO_CHANNEL_MAP[message.platform];
+          const hasChannel = !!(channelName && message.conversationId);
+          // Strip IM subtype prefix (e.g. "direct:ou_xxx" -> "ou_xxx")
+          let deliveryTo = message.conversationId;
+          if (hasChannel && deliveryTo) {
+            const colonIdx = deliveryTo.indexOf(':');
+            if (colonIdx > 0) {
+              deliveryTo = deliveryTo.slice(colonIdx + 1);
+            }
+          }
           const task = await getCronJobService().addJob({
             name: request.taskName,
             description: '',
@@ -1286,22 +1345,29 @@ const getIMGatewayManager = () => {
               kind: 'at',
               at: request.scheduleAt,
             },
-            sessionTarget: 'main',
+            sessionTarget: hasChannel ? 'isolated' : 'main',
             wakeMode: 'now',
-            payload: {
-              kind: 'systemEvent',
-              text: request.payloadText,
+            payload: hasChannel
+              ? { kind: 'agentTurn', message: request.payloadText }
+              : { kind: 'systemEvent', text: request.payloadText },
+            delivery: {
+              mode: hasChannel ? 'announce' : 'none',
+              ...(channelName ? { channel: channelName } : {}),
+              ...(hasChannel ? { to: deliveryTo } : message.conversationId ? { to: message.conversationId } : {}),
             },
-            delivery: { mode: 'none' },
             agentId: DEFAULT_MANAGED_AGENT_ID,
-            sessionKey: buildManagedSessionKey(sessionId, DEFAULT_MANAGED_AGENT_ID),
+            ...(hasChannel ? {} : { sessionKey: buildManagedSessionKey(sessionId, DEFAULT_MANAGED_AGENT_ID) }),
           });
           return {
             id: task.id,
             name: task.name,
             agentId: task.agentId,
             sessionKey: task.sessionKey,
-            payloadText: task.payload.kind === 'systemEvent' ? task.payload.text : '',
+            payloadText: task.payload.kind === 'systemEvent'
+              ? task.payload.text
+              : task.payload.kind === 'agentTurn'
+                ? task.payload.message
+                : '',
             scheduleAt: task.schedule.kind === 'at' ? task.schedule.at : request.scheduleAt,
           };
         },
@@ -1402,15 +1468,15 @@ function listScheduledTaskChannels(): Array<{ value: string; label: string }> {
   }
 
   return SCHEDULED_TASK_CHANNEL_OPTIONS.filter((option) => {
-    if (option.value === 'last') {
-      return true;
-    }
     if (option.value === 'dingtalk-connector') {
       return enabledConfigKeys.has('dingtalk');
     }
     if (option.value === 'qqbot') {
       return enabledConfigKeys.has('qq');
     }
+    if (option.value === 'openclaw-weixin') {
+      return enabledConfigKeys.has('weixin');
+    }
     return enabledConfigKeys.has(option.value);
   });
 }
@@ -2005,9 +2071,11 @@ if (!gotTheLock) {
         }).catch(() => { /* best-effort */ });
       }
       clearAuthTokens();
+      clearServerModelMetadata();
       return { success: true };
     } catch {
       clearAuthTokens();
+      clearServerModelMetadata();
       return { success: true };
     }
   });
@@ -2056,6 +2124,8 @@ if (!gotTheLock) {
       const data = await resp.json() as { code: number; data: Array<{ modelId: string; modelName: string; provider: string; apiFormat: string; supportsImage?: boolean }> };
       console.log('[Auth:getModels] Response data:', JSON.stringify(data).slice(0, 500));
       if (data.code !== 0) return { success: false };
+      // Cache server model metadata for use in OpenClaw config sync (supportsImage, etc.)
+      updateServerModelMetadata(data.data);
       return { success: true, models: data.data };
     } catch (e) {
       console.error('[Auth:getModels] Error:', e);
@@ -2346,6 +2416,7 @@ if (!gotTheLock) {
     title?: string;
     activeSkillIds?: string[];
     imageAttachments?: Array<{ name: string; mimeType: string; base64Data: string }>;
+    agentId?: string;
   }) => {
     try {
       const activeEngine = resolveCoworkAgentEngine();
@@ -2381,7 +2452,8 @@ if (!gotTheLock) {
         taskWorkingDirectory,
         systemPrompt,
         config.executionMode || 'local',
-        options.activeSkillIds || []
+        options.activeSkillIds || [],
+        options.agentId || 'main'
       );
 
       // Update session status to 'running' before starting async task
@@ -2417,6 +2489,7 @@ if (!gotTheLock) {
         workspaceRoot: selectedWorkspaceRoot,
         confirmationMode: 'modal',
         imageAttachments: options.imageAttachments,
+        agentId: options.agentId,
       }).catch(error => {
         console.error('Cowork session error:', error);
         // The engine router already emits an 'error' event (handled at line ~990)
@@ -2616,9 +2689,9 @@ if (!gotTheLock) {
     }
   });
 
-  ipcMain.handle('cowork:session:list', async () => {
+  ipcMain.handle('cowork:session:list', async (_event, agentId?: string) => {
     try {
-      const sessions = getCoworkStore().listSessions();
+      const sessions = getCoworkStore().listSessions(agentId);
       return { success: true, sessions };
     } catch (error) {
       return {
@@ -2628,6 +2701,102 @@ if (!gotTheLock) {
     }
   });
 
+  // ========== Agent IPC Handlers ==========
+
+  ipcMain.handle('agents:list', async () => {
+    try {
+      const agents = getAgentManager().listAgents();
+      return { success: true, agents };
+    } catch (error) {
+      return { success: false, error: error instanceof Error ? error.message : 'Failed to list agents' };
+    }
+  });
+
+  ipcMain.handle('agents:get', async (_event, id: string) => {
+    try {
+      const agent = getAgentManager().getAgent(id);
+      return { success: true, agent };
+    } catch (error) {
+      return { success: false, error: error instanceof Error ? error.message : 'Failed to get agent' };
+    }
+  });
+
+  ipcMain.handle('agents:create', async (_event, request: import('./coworkStore').CreateAgentRequest) => {
+    try {
+      const agent = getAgentManager().createAgent(request);
+      // Sync config so workspace files (SOUL.md, IDENTITY.md) are written
+      // before OpenClaw scaffolds default templates for the new agent.
+      syncOpenClawConfig({ reason: 'agent-created' }).catch(() => {});
+      return { success: true, agent };
+    } catch (error) {
+      return { success: false, error: error instanceof Error ? error.message : 'Failed to create agent' };
+    }
+  });
+
+  ipcMain.handle('agents:update', async (_event, id: string, updates: import('./coworkStore').UpdateAgentRequest) => {
+    try {
+      const agent = getAgentManager().updateAgent(id, updates);
+      syncOpenClawConfig({ reason: 'agent-updated' }).catch(() => {});
+      return { success: true, agent };
+    } catch (error) {
+      return { success: false, error: error instanceof Error ? error.message : 'Failed to update agent' };
+    }
+  });
+
+  ipcMain.handle('agents:delete', async (_event, id: string) => {
+    try {
+      const result = getAgentManager().deleteAgent(id);
+
+      // Clean up IM platform bindings that reference the deleted agent
+      // so that channels fall back to the default 'main' agent.
+      try {
+        const imStore = getIMGatewayManager()?.getIMStore();
+        if (imStore) {
+          const imSettings = imStore.getIMSettings();
+          const bindings = imSettings.platformAgentBindings;
+          if (bindings) {
+            let changed = false;
+            for (const [platform, agentId] of Object.entries(bindings)) {
+              if (agentId === id) {
+                delete bindings[platform];
+                changed = true;
+              }
+            }
+            if (changed) {
+              imStore.setIMSettings({ platformAgentBindings: bindings });
+            }
+          }
+        }
+      } catch {
+        // IM store may not be initialised yet; safe to ignore.
+      }
+
+      syncOpenClawConfig({ reason: 'agent-deleted' }).catch(() => {});
+      return { success: true, deleted: result };
+    } catch (error) {
+      return { success: false, error: error instanceof Error ? error.message : 'Failed to delete agent' };
+    }
+  });
+
+  ipcMain.handle('agents:presets', async () => {
+    try {
+      const presets = getAgentManager().getPresetAgents();
+      return { success: true, presets };
+    } catch (error) {
+      return { success: false, error: error instanceof Error ? error.message : 'Failed to get presets' };
+    }
+  });
+
+  ipcMain.handle('agents:addPreset', async (_event, presetId: string) => {
+    try {
+      const agent = getAgentManager().addPresetAgent(presetId);
+      syncOpenClawConfig({ reason: 'agent-preset-added' }).catch(() => {});
+      return { success: true, agent };
+    } catch (error) {
+      return { success: false, error: error instanceof Error ? error.message : 'Failed to add preset agent' };
+    }
+  });
+
   ipcMain.handle('cowork:session:exportResultImage', async (
     event,
     options: {
@@ -2993,7 +3162,7 @@ if (!gotTheLock) {
 
   // ==================== Scheduled Task IPC Handlers (OpenClaw) ====================
 
-  ipcMain.handle('scheduledTask:list', async () => {
+  ipcMain.handle(ScheduledTaskIpc.List, async () => {
     try {
       // If OpenClaw gateway is not connected yet, return empty list immediately
       // to avoid blocking the renderer init. Tasks will be loaded later via the
@@ -3008,7 +3177,7 @@ if (!gotTheLock) {
     }
   });
 
-  ipcMain.handle('scheduledTask:get', async (_event, id: string) => {
+  ipcMain.handle(ScheduledTaskIpc.Get, async (_event, id: string) => {
     try {
       const task = await getCronJobService().getJob(id);
       return { success: true, task };
@@ -3017,27 +3186,113 @@ if (!gotTheLock) {
     }
   });
 
-  ipcMain.handle('scheduledTask:create', async (_event, input: any) => {
+  ipcMain.handle(ScheduledTaskIpc.Create, async (_event, input: any) => {
     try {
       const normalizedInput = input && typeof input === 'object' ? { ...input } : {};
+      console.log('[IPC][scheduledTask:create] normalizedInput:', JSON.stringify(normalizedInput, null, 2));
+      console.log('[IPC][scheduledTask:create] delivery:', JSON.stringify(normalizedInput.delivery, null, 2));
+
+      // When an IM conversation is selected as notification target, let OpenClaw
+      // handle delivery natively via its announce mechanism. We keep
+      // sessionTarget='isolated' and delivery.mode='announce' so OpenClaw runs
+      // the agent in an isolated cron session and delivers the result through
+      // its outbound channel adapter (e.g. feishu plugin).
+      //
+      // DingTalk still needs the reply route primed so the outbound adapter
+      // can locate the correct conversation.
+      const delivery = normalizedInput.delivery;
+      if (delivery && delivery.mode === STDeliveryMode.Announce && delivery.channel && delivery.to) {
+        const platform = CHANNEL_PLATFORM_MAP[delivery.channel] as IMPlatform | undefined;
+        if (platform) {
+          console.log('[IPC][scheduledTask:create] IM notification target detected, using OpenClaw native announce delivery.',
+            JSON.stringify({ channel: delivery.channel, to: delivery.to, platform }));
+          normalizedInput.sessionTarget = STSessionTarget.Isolated;
+          if (normalizedInput.payload?.kind === STPayloadKind.SystemEvent) {
+            normalizedInput.payload = {
+              kind: STPayloadKind.AgentTurn,
+              message: normalizedInput.payload.text || '',
+            };
+          }
+          // Strip IM subtype prefix from delivery.to before passing to OpenClaw.
+          // LobsterAI stores conversationIds with subtype prefixes (e.g. "direct:ou_xxx",
+          // "group:oc_xxx") but OpenClaw channel adapters expect raw platform IDs
+          // (e.g. "ou_xxx", "oc_xxx").
+          const rawTo = delivery.to;
+          const colonIdx = rawTo.indexOf(':');
+          if (colonIdx > 0) {
+            delivery.to = rawTo.slice(colonIdx + 1);
+            console.log('[IPC][scheduledTask:create] stripped IM subtype prefix from delivery.to:',
+              rawTo, '->', delivery.to);
+          }
+          if (platform === 'dingtalk') {
+            const imStore = getIMGatewayManager()?.getIMStore();
+            const mapping = imStore?.getSessionMapping(rawTo, platform);
+            if (mapping) {
+              await getIMGatewayManager().primeConversationReplyRoute(
+                platform, rawTo, mapping.coworkSessionId,
+              );
+            }
+          }
+        }
+      }
+
       const task = await getCronJobService().addJob(normalizedInput);
+      console.log('[IPC][scheduledTask:create] result task id:', task?.id, 'name:', task?.name);
       return { success: true, task };
     } catch (error) {
       return { success: false, error: error instanceof Error ? error.message : 'Failed to create task' };
     }
   });
 
-  ipcMain.handle('scheduledTask:update', async (_event, id: string, input: any) => {
+  ipcMain.handle(ScheduledTaskIpc.Update, async (_event, id: string, input: any) => {
     try {
       const normalizedInput = input && typeof input === 'object' ? { ...input } : {};
+      console.log('[IPC][scheduledTask:update] id:', id, 'normalizedInput:', JSON.stringify(normalizedInput, null, 2));
+      console.log('[IPC][scheduledTask:update] delivery:', JSON.stringify(normalizedInput.delivery, null, 2));
+
+      // Same OpenClaw native announce delivery logic as create handler.
+      const delivery = normalizedInput.delivery;
+      if (delivery && delivery.mode === STDeliveryMode.Announce && delivery.channel && delivery.to) {
+        const platform = CHANNEL_PLATFORM_MAP[delivery.channel] as IMPlatform | undefined;
+        if (platform) {
+          console.log('[IPC][scheduledTask:update] IM notification target detected, using OpenClaw native announce delivery.',
+            JSON.stringify({ channel: delivery.channel, to: delivery.to, platform }));
+          normalizedInput.sessionTarget = STSessionTarget.Isolated;
+          if (normalizedInput.payload?.kind === STPayloadKind.SystemEvent) {
+            normalizedInput.payload = {
+              kind: STPayloadKind.AgentTurn,
+              message: normalizedInput.payload.text || '',
+            };
+          }
+          // Strip IM subtype prefix (e.g. "direct:ou_xxx" -> "ou_xxx")
+          const rawTo = delivery.to;
+          const colonIdx = rawTo.indexOf(':');
+          if (colonIdx > 0) {
+            delivery.to = rawTo.slice(colonIdx + 1);
+            console.log('[IPC][scheduledTask:update] stripped IM subtype prefix from delivery.to:',
+              rawTo, '->', delivery.to);
+          }
+          if (platform === 'dingtalk') {
+            const imStore = getIMGatewayManager()?.getIMStore();
+            const mapping = imStore?.getSessionMapping(rawTo, platform);
+            if (mapping) {
+              await getIMGatewayManager().primeConversationReplyRoute(
+                platform, rawTo, mapping.coworkSessionId,
+              );
+            }
+          }
+        }
+      }
+
       const task = await getCronJobService().updateJob(id, normalizedInput);
+      console.log('[IPC][scheduledTask:update] result task id:', task?.id, 'name:', task?.name);
       return { success: true, task };
     } catch (error) {
       return { success: false, error: error instanceof Error ? error.message : 'Failed to update task' };
     }
   });
 
-  ipcMain.handle('scheduledTask:delete', async (_event, id: string) => {
+  ipcMain.handle(ScheduledTaskIpc.Delete, async (_event, id: string) => {
     try {
       await getCronJobService().removeJob(id);
       return { success: true, result: true };
@@ -3046,7 +3301,7 @@ if (!gotTheLock) {
     }
   });
 
-  ipcMain.handle('scheduledTask:toggle', async (_event, id: string, enabled: boolean) => {
+  ipcMain.handle(ScheduledTaskIpc.Toggle, async (_event, id: string, enabled: boolean) => {
     try {
       const task = await getCronJobService().toggleJob(id, enabled);
       return { success: true, task };
@@ -3055,7 +3310,7 @@ if (!gotTheLock) {
     }
   });
 
-  ipcMain.handle('scheduledTask:runManually', async (_event, id: string) => {
+  ipcMain.handle(ScheduledTaskIpc.RunManually, async (_event, id: string) => {
     try {
       await getCronJobService().runJob(id);
       return { success: true };
@@ -3066,7 +3321,7 @@ if (!gotTheLock) {
     }
   });
 
-  ipcMain.handle('scheduledTask:stop', async (_event, id: string) => {
+  ipcMain.handle(ScheduledTaskIpc.Stop, async (_event, id: string) => {
     try {
       // OpenClaw doesn't expose a direct stop API for running cron jobs
       // The job will complete or timeout on its own
@@ -3076,7 +3331,7 @@ if (!gotTheLock) {
     }
   });
 
-  ipcMain.handle('scheduledTask:listRuns', async (_event, taskId: string, limit?: number, offset?: number) => {
+  ipcMain.handle(ScheduledTaskIpc.ListRuns, async (_event, taskId: string, limit?: number, offset?: number) => {
     try {
       const runs = await getCronJobService().listRuns(taskId, limit, offset);
       return { success: true, runs };
@@ -3085,7 +3340,7 @@ if (!gotTheLock) {
     }
   });
 
-  ipcMain.handle('scheduledTask:countRuns', async (_event, taskId: string) => {
+  ipcMain.handle(ScheduledTaskIpc.CountRuns, async (_event, taskId: string) => {
     try {
       const count = await getCronJobService().countRuns(taskId);
       return { success: true, count };
@@ -3094,7 +3349,7 @@ if (!gotTheLock) {
     }
   });
 
-  ipcMain.handle('scheduledTask:listAllRuns', async (_event, limit?: number, offset?: number) => {
+  ipcMain.handle(ScheduledTaskIpc.ListAllRuns, async (_event, limit?: number, offset?: number) => {
     try {
       const runs = await getCronJobService().listAllRuns(limit, offset);
       return { success: true, runs };
@@ -3103,7 +3358,7 @@ if (!gotTheLock) {
     }
   });
 
-  ipcMain.handle('scheduledTask:resolveSession', async (_event, sessionKey: string) => {
+  ipcMain.handle(ScheduledTaskIpc.ResolveSession, async (_event, sessionKey: string) => {
     try {
       if (!sessionKey) return { success: true, session: null };
       // Fetch session history from OpenClaw (returns transient session, not persisted)
@@ -3114,14 +3369,43 @@ if (!gotTheLock) {
     }
   });
 
-  ipcMain.handle('scheduledTask:listChannels', async () => {
+  ipcMain.handle(ScheduledTaskIpc.ListChannels, async () => {
     try {
       return { success: true, channels: listScheduledTaskChannels() };
     } catch (error) {
       return { success: false, error: error instanceof Error ? error.message : 'Failed to list channels' };
     }
   });
 
+  ipcMain.handle(ScheduledTaskIpc.ListChannelConversations, async (_event, channel: string) => {
+    try {
+      console.log('[IPC][listChannelConversations] channel:', channel);
+      const platform = CHANNEL_PLATFORM_MAP[channel] as IMPlatform | undefined;
+      console.log('[IPC][listChannelConversations] resolved platform:', platform);
+      if (!platform) {
+        console.log('[IPC][listChannelConversations] no platform mapping, returning empty');
+        return { success: true, conversations: [] };
+      }
+      const imStore = getIMGatewayManager()?.getIMStore();
+      if (!imStore) {
+        console.log('[IPC][listChannelConversations] no imStore available, returning empty');
+        return { success: true, conversations: [] };
+      }
+      const mappings = imStore.listSessionMappings(platform);
+      console.log('[IPC][listChannelConversations] found', mappings.length, 'session mappings for platform:', platform);
+      const conversations = mappings.map((m) => ({
+        conversationId: m.imConversationId,
+        platform: m.platform,
+        coworkSessionId: m.coworkSessionId,
+        lastActiveAt: m.lastActiveAt,
+      }));
+      console.log('[IPC][listChannelConversations] conversations:', JSON.stringify(conversations, null, 2));
+      return { success: true, conversations };
+    } catch (error) {
+      return { success: false, error: error instanceof Error ? error.message : 'Failed to list conversations' };
+    }
+  });
+
   // ==================== Permissions IPC Handlers ====================
 
   ipcMain.handle('permissions:checkCalendar', async () => {
@@ -4242,13 +4526,19 @@ if (!gotTheLock) {
     // The getter proactively triggers a background token refresh when the
     // accessToken is within 5 minutes of expiry, so that the SDK always
     // gets a fresh token without blocking.
-    let refreshPromise: Promise<void> | null = null;
-    const refreshTokenAsync = async () => {
-      if (refreshPromise) return;
-      refreshPromise = (async () => {
+    //
+    // refreshOnce() is the single entry-point for all token refresh paths
+    // (proactive, proxy 401/403 retry). It deduplicates concurrent calls via
+    // pendingTokenRefresh so that rolling refresh tokens are never consumed twice.
+    const refreshOnce = async (reason: string): Promise<string | null> => {
+      if (pendingTokenRefresh) {
+        return pendingTokenRefresh;
+      }
+      let resolvedToken: string | null = null;
+      pendingTokenRefresh = (async () => {
         try {
           const tokens = getAuthTokens();
-          if (!tokens?.refreshToken) return;
+          if (!tokens?.refreshToken) return null;
           const serverBaseUrl = getServerApiBaseUrl();
           const resp = await net.fetch(`${serverBaseUrl}/api/auth/refresh`, {
             method: 'POST',
@@ -4259,15 +4549,23 @@ if (!gotTheLock) {
             const body = await resp.json() as { code: number; data: { accessToken: string; refreshToken?: string } };
             if (body.code === 0 && body.data) {
               saveAuthTokens(body.data.accessToken, body.data.refreshToken || tokens.refreshToken);
-              console.log('[Auth] proactive token refresh succeeded');
+              console.log(`[Auth] token refresh succeeded (reason: ${reason})`);
+              resolvedToken = body.data.accessToken;
+              // Sync the fresh token to the OpenClaw gateway so it doesn't
+              // continue using the expired token from its spawn-time env vars.
+              syncOpenClawConfig({ reason: `token-refresh:${reason}`, restartGatewayIfRunning: true }).catch((err) => {
+                console.warn('[Auth] post-refresh OpenClaw config sync failed:', err);
+              });
             }
           }
         } catch (err) {
-          console.warn('[Auth] proactive token refresh failed:', err);
+          console.warn(`[Auth] token refresh failed (reason: ${reason}):`, err);
         } finally {
-          refreshPromise = null;
+          pendingTokenRefresh = null;
         }
+        return resolvedToken;
       })();
+      return pendingTokenRefresh;
     };
 
     setAuthTokensGetter(() => {
@@ -4278,7 +4576,7 @@ if (!gotTheLock) {
         const payload = JSON.parse(Buffer.from(tokens.accessToken.split('.')[1], 'base64').toString());
         const expiresAt = payload.exp * 1000;
         if (expiresAt - Date.now() < 5 * 60 * 1000) {
-          refreshTokenAsync(); // fire-and-forget
+          void refreshOnce('proactive'); // fire-and-forget
         }
       } catch { /* unable to parse JWT, return token as-is */ }
       return tokens;
@@ -4287,29 +4585,8 @@ if (!gotTheLock) {
 
     // Wire up token refresher for the OpenAI compat proxy so it can retry
     // on 401/403 with a fresh accessToken instead of failing immediately.
-    setProxyTokenRefresher(async () => {
-      const tokens = getAuthTokens();
-      if (!tokens?.refreshToken) return null;
-      const serverBaseUrl = getServerApiBaseUrl();
-      try {
-        const resp = await net.fetch(`${serverBaseUrl}/api/auth/refresh`, {
-          method: 'POST',
-          headers: { 'Content-Type': 'application/json' },
-          body: JSON.stringify({ refreshToken: tokens.refreshToken }),
-        });
-        if (resp.ok) {
-          const body = await resp.json() as { code: number; data: { accessToken: string; refreshToken?: string } };
-          if (body.code === 0 && body.data) {
-            saveAuthTokens(body.data.accessToken, body.data.refreshToken || tokens.refreshToken);
-            console.log('[Auth] proxy token refresh succeeded');
-            return body.data.accessToken;
-          }
-        }
-      } catch (err) {
-        console.warn('[Auth] proxy token refresh failed:', err);
-      }
-      return null;
-    });
+    // Delegates to the shared refreshOnce() to avoid concurrent refresh races.
+    setProxyTokenRefresher(() => refreshOnce('proxy'));
 
     bindCoworkRuntimeForwarder();
     bindOpenClawStatusForwarder();
diff --git a/src/main/preload.ts b/src/main/preload.ts
--- a/src/main/preload.ts
+++ b/src/main/preload.ts
@@ -1,4 +1,5 @@
 import { contextBridge, ipcRenderer } from 'electron';
+import { IpcChannel as ScheduledTaskIpc } from '../scheduled-task/constants';
 
 // 暴露安全的 API 到渲染进程
 contextBridge.exposeInMainWorld('electron', {
@@ -133,9 +134,39 @@ contextBridge.exposeInMainWorld('electron', {
       },
     },
   },
+  agents: {
+    list: async () => {
+      const result = await ipcRenderer.invoke('agents:list');
+      return result?.success ? result.agents : [];
+    },
+    get: async (id: string) => {
+      const result = await ipcRenderer.invoke('agents:get', id);
+      return result?.success ? result.agent : null;
+    },
+    create: async (request: { id?: string; name: string; description?: string; systemPrompt?: string; identity?: string; model?: string; icon?: string; skillIds?: string[]; source?: string; presetId?: string }) => {
+      const result = await ipcRenderer.invoke('agents:create', request);
+      return result?.success ? result.agent : null;
+    },
+    update: async (id: string, updates: { name?: string; description?: string; systemPrompt?: string; identity?: string; model?: string; icon?: string; skillIds?: string[]; enabled?: boolean }) => {
+      const result = await ipcRenderer.invoke('agents:update', id, updates);
+      return result?.success ? result.agent : null;
+    },
+    delete: async (id: string) => {
+      const result = await ipcRenderer.invoke('agents:delete', id);
+      return result?.success ? result.deleted : false;
+    },
+    presets: async () => {
+      const result = await ipcRenderer.invoke('agents:presets');
+      return result?.success ? result.presets : [];
+    },
+    addPreset: async (presetId: string) => {
+      const result = await ipcRenderer.invoke('agents:addPreset', presetId);
+      return result?.success ? result.agent : null;
+    },
+  },
   cowork: {
     // Session management
-    startSession: (options: { prompt: string; cwd?: string; systemPrompt?: string; activeSkillIds?: string[]; imageAttachments?: Array<{ name: string; mimeType: string; base64Data: string }> }) =>
+    startSession: (options: { prompt: string; cwd?: string; systemPrompt?: string; activeSkillIds?: string[]; agentId?: string; imageAttachments?: Array<{ name: string; mimeType: string; base64Data: string }> }) =>
       ipcRenderer.invoke('cowork:session:start', options),
     continueSession: (options: { sessionId: string; prompt: string; systemPrompt?: string; activeSkillIds?: string[]; imageAttachments?: Array<{ name: string; mimeType: string; base64Data: string }> }) =>
       ipcRenderer.invoke('cowork:session:continue', options),
@@ -153,8 +184,8 @@ contextBridge.exposeInMainWorld('electron', {
       ipcRenderer.invoke('cowork:session:get', sessionId),
     remoteManaged: (sessionId: string) =>
       ipcRenderer.invoke('cowork:session:remoteManaged', sessionId),
-    listSessions: () =>
-      ipcRenderer.invoke('cowork:session:list'),
+    listSessions: (agentId?: string) =>
+      ipcRenderer.invoke('cowork:session:list', agentId),
     exportResultImage: (options: { rect: { x: number; y: number; width: number; height: number }; defaultFileName?: string }) =>
       ipcRenderer.invoke('cowork:session:exportResultImage', options),
     captureImageChunk: (options: { rect: { x: number; y: number; width: number; height: number } }) =>
@@ -329,44 +360,45 @@ contextBridge.exposeInMainWorld('electron', {
   },
   scheduledTasks: {
     // Task CRUD
-    list: () => ipcRenderer.invoke('scheduledTask:list'),
-    get: (id: string) => ipcRenderer.invoke('scheduledTask:get', id),
-    create: (input: any) => ipcRenderer.invoke('scheduledTask:create', input),
-    update: (id: string, input: any) => ipcRenderer.invoke('scheduledTask:update', id, input),
-    delete: (id: string) => ipcRenderer.invoke('scheduledTask:delete', id),
-    toggle: (id: string, enabled: boolean) => ipcRenderer.invoke('scheduledTask:toggle', id, enabled),
+    list: () => ipcRenderer.invoke(ScheduledTaskIpc.List),
+    get: (id: string) => ipcRenderer.invoke(ScheduledTaskIpc.Get, id),
+    create: (input: any) => ipcRenderer.invoke(ScheduledTaskIpc.Create, input),
+    update: (id: string, input: any) => ipcRenderer.invoke(ScheduledTaskIpc.Update, id, input),
+    delete: (id: string) => ipcRenderer.invoke(ScheduledTaskIpc.Delete, id),
+    toggle: (id: string, enabled: boolean) => ipcRenderer.invoke(ScheduledTaskIpc.Toggle, id, enabled),
 
     // Execution
-    runManually: (id: string) => ipcRenderer.invoke('scheduledTask:runManually', id),
-    stop: (id: string) => ipcRenderer.invoke('scheduledTask:stop', id),
+    runManually: (id: string) => ipcRenderer.invoke(ScheduledTaskIpc.RunManually, id),
+    stop: (id: string) => ipcRenderer.invoke(ScheduledTaskIpc.Stop, id),
 
     // Run history
     listRuns: (taskId: string, limit?: number, offset?: number) =>
-      ipcRenderer.invoke('scheduledTask:listRuns', taskId, limit, offset),
-    countRuns: (taskId: string) => ipcRenderer.invoke('scheduledTask:countRuns', taskId),
+      ipcRenderer.invoke(ScheduledTaskIpc.ListRuns, taskId, limit, offset),
+    countRuns: (taskId: string) => ipcRenderer.invoke(ScheduledTaskIpc.CountRuns, taskId),
     listAllRuns: (limit?: number, offset?: number) =>
-      ipcRenderer.invoke('scheduledTask:listAllRuns', limit, offset),
+      ipcRenderer.invoke(ScheduledTaskIpc.ListAllRuns, limit, offset),
     resolveSession: (sessionKey: string) =>
-      ipcRenderer.invoke('scheduledTask:resolveSession', sessionKey),
+      ipcRenderer.invoke(ScheduledTaskIpc.ResolveSession, sessionKey),
 
     // Delivery channels
-    listChannels: () => ipcRenderer.invoke('scheduledTask:listChannels'),
+    listChannels: () => ipcRenderer.invoke(ScheduledTaskIpc.ListChannels),
+    listChannelConversations: (channel: string) => ipcRenderer.invoke(ScheduledTaskIpc.ListChannelConversations, channel),
 
     // Stream event listeners
     onStatusUpdate: (callback: (data: any) => void) => {
       const handler = (_event: any, data: any) => callback(data);
-      ipcRenderer.on('scheduledTask:statusUpdate', handler);
-      return () => ipcRenderer.removeListener('scheduledTask:statusUpdate', handler);
+      ipcRenderer.on(ScheduledTaskIpc.StatusUpdate, handler);
+      return () => ipcRenderer.removeListener(ScheduledTaskIpc.StatusUpdate, handler);
     },
     onRunUpdate: (callback: (data: any) => void) => {
       const handler = (_event: any, data: any) => callback(data);
-      ipcRenderer.on('scheduledTask:runUpdate', handler);
-      return () => ipcRenderer.removeListener('scheduledTask:runUpdate', handler);
+      ipcRenderer.on(ScheduledTaskIpc.RunUpdate, handler);
+      return () => ipcRenderer.removeListener(ScheduledTaskIpc.RunUpdate, handler);
     },
     onRefresh: (callback: () => void) => {
       const handler = () => callback();
-      ipcRenderer.on('scheduledTask:refresh', handler);
-      return () => ipcRenderer.removeListener('scheduledTask:refresh', handler);
+      ipcRenderer.on(ScheduledTaskIpc.Refresh, handler);
+      return () => ipcRenderer.removeListener(ScheduledTaskIpc.Refresh, handler);
     },
   },
   networkStatus: {
diff --git a/src/main/presetAgents.ts b/src/main/presetAgents.ts
new file mode 100644
--- /dev/null
+++ b/src/main/presetAgents.ts
@@ -0,0 +1,206 @@
+import type { CreateAgentRequest } from './coworkStore';
+
+export interface PresetAgent {
+  id: string;
+  name: string;
+  icon: string;
+  description: string;
+  systemPrompt: string;
+  skillIds: string[];
+}
+
+/**
+ * Hardcoded preset agent templates.
+ * Users can add these via the "Choose Preset" flow in the UI.
+ *
+ * Names and descriptions use Chinese as the primary language since
+ * the target audience is Chinese-speaking users.  System prompts are
+ * kept bilingual so models respond naturally in the user's language.
+ */
+export const PRESET_AGENTS: PresetAgent[] = [
+  {
+    id: 'stockexpert',
+    name: '股票助手',
+    icon: '📈',
+    description:
+      'A 股公告追踪、个股深度分析、交易复盘；支持美港股行情、基本面、技术指标与风险评估。',
+    systemPrompt:
+      '你是一名专业的股票分析助手（Stock Expert），专注A股市场的激进型分析师。\n\n' +
+      '## 核心能力\n' +
+      '1. **综合深度分析** — 使用 stock-analyzer skill 的 `analyze.py`，生成价值+技术+成长+财务多维评分报告\n' +
+      '2. **A股公告监控** — 使用 stock-announcements skill 的 `announcements.py`，从东方财富获取实时公告\n' +
+      '3. **快速行情查询** — 使用 stock-explorer skill 的 `quote.py`，获取实时报价和技术指标\n' +
+      '4. **网络搜索补充** — 使用 web-search skill，搜索最新市场新闻和分析\n\n' +
+      '## 工作原则\n' +
+      '- 始终提供数据驱动、客观的分析\n' +
+      '- 用户提到股票名称时，先确认代码（上交所 .SS，深交所 .SZ）\n' +
+      '- 优先使用专业 skill 获取真实数据，web-search 作为补充\n' +
+      '- 明确标注数据时效性，当信息可能过时时请说明\n' +
+      '- A股分析占80%以上，美港股仅做参考对比\n\n' +
+      '## 系统环境注意事项\n' +
+      '- Windows 环境：在 bash 中运行 Python 脚本前设置 `export PYTHONIOENCODING=utf-8`\n' +
+      '- 所有 Python 脚本输出纯文本报告，不生成 PNG 图表\n' +
+      '- 使用 `pip` 安装依赖，不使用 `uv`\n',
+    skillIds: ['stock-analyzer', 'stock-announcements', 'stock-explorer', 'web-search'],
+  },
+  {
+    id: 'content-writer',
+    name: '内容创作',
+    icon: '✍️',
+    description:
+      '一站式内容创作：选题、撰写、排版、润色，适用于文章、营销文案和社交媒体帖子。',
+    systemPrompt:
+      '你是一名专业的内容创作助手，擅长微信公众号和自媒体内容。\n\n' +
+      '## 核心能力\n' +
+      '1. **选题规划** — 使用 content-planner skill 搜索微信热文，分析竞品，生成内容日历\n' +
+      '2. **文章撰写** — 使用 article-writer skill 的5种风格和11步工作流\n' +
+      '3. **热搜追踪** — 使用 daily-trending skill 聚合多平台热搜\n' +
+      '4. **网络调研** — 使用 web-search skill 搜索素材和验证事实\n\n' +
+      '## 5种写作风格\n' +
+      '- **deep-analysis**: 严谨结构、数据支撑 (2000-4000字)\n' +
+      '- **practical-guide**: 步骤清晰、可操作 (1500-3000字)\n' +
+      '- **story-driven**: 对话式、情感共鸣 (1500-2500字)\n' +
+      '- **opinion**: 观点鲜明、正反论证 (1000-2000字)\n' +
+      '- **news-brief**: 倒金字塔、事实导向 (500-1000字)\n\n' +
+      '## 工作原则\n' +
+      '- 写作前先确认选题和风格\n' +
+      '- 大纲需经用户确认后再展开撰写\n' +
+      '- 用故事代替说教，用数据支撑观点\n' +
+      '- 段落不超过4行（手机屏幕可视范围）\n' +
+      '- 前3行必须有吸引力钩子\n',
+    skillIds: ['content-planner', 'article-writer', 'daily-trending', 'web-search'],
+  },
+  {
+    id: 'lesson-planner',
+    name: '备课出卷专家',
+    icon: '📚',
+    description:
+      '阅读教材和教学参考资料，生成教案、试卷、答案解析或英语听力原文。',
+    systemPrompt:
+      '你是一名资深教育专家助手，专精K12教学内容设计。\n\n' +
+      '## 核心能力\n' +
+      '1. **教案生成** — 根据教材内容和课标要求，生成结构化教案\n' +
+      '2. **试卷设计** — 使用 docx skill 生成难度均衡的试卷 (Word格式)\n' +
+      '3. **答案解析** — 创建包含详细解题过程的答案\n' +
+      '4. **数据统计** — 使用 xlsx skill 生成成绩分析表 (Excel格式)\n' +
+      '5. **英语听力** — 编写英语听力理解原文\n\n' +
+      '## 工作原则\n' +
+      '- 遵循国家课程标准，确保内容适龄\n' +
+      '- 试卷难度分布: 基础60% + 中等25% + 拔高15%\n' +
+      '- 教案包含: 教学目标、重难点、教学过程、板书设计、课后反思\n' +
+      '- 试卷包含: 题目编号、分值、参考答案、评分标准\n' +
+      '- 输出文件统一使用 docx 格式（试卷）或 xlsx 格式（数据）\n',
+    skillIds: ['docx', 'xlsx', 'web-search'],
+  },
+  {
+    id: 'content-summarizer',
+    name: '内容总结助手',
+    icon: '📋',
+    description:
+      '支持音视频、链接、文档摘要。自动识别会议、讲座、访谈等内容类型。',
+    systemPrompt:
+      '你是一名专业的内容摘要助手，擅长信息提炼和结构化整理。\n\n' +
+      '## 核心能力\n' +
+      '1. **网页总结** — 使用 web-search skill 搜索 + 抓取网页内容后提炼要点\n' +
+      '2. **文档摘要** — 总结用户上传的文档、文章\n' +
+      '3. **会议纪要** — 从文字记录中提取决策、行动项\n' +
+      '4. **多源聚合** — 综合多个来源生成统一摘要\n\n' +
+      '## 输出格式\n' +
+      '- **一句话摘要**: 核心结论\n' +
+      '- **关键要点**: 3-5 条bullet points\n' +
+      '- **详细摘要**: 按原文结构分段总结\n' +
+      '- **行动项** (如适用): TODO 列表\n\n' +
+      '## 工作原则\n' +
+      '- 保留关键细节，消除冗余\n' +
+      '- 区分事实与观点\n' +
+      '- 自动识别内容类型（会议/讲座/访谈/文章）并调整摘要风格\n' +
+      '- 给出链接时先搜索获取内容，再总结\n',
+    skillIds: ['web-search'],
+  },
+  {
+    id: 'health-interpreter',
+    name: '医疗健康解读',
+    icon: '🏥',
+    description:
+      '体检报告、化验单、医学指标的通俗解读，帮你看懂每一项数值的含义和注意事项。',
+    systemPrompt:
+      '你是一名耐心专业的全科医生助手，擅长将复杂的医学报告翻译成通俗易懂的语言。\n\n' +
+      '## 核心能力\n' +
+      '1. **体检报告解读** — 逐项解释指标含义、正常范围、偏高/偏低的可能原因\n' +
+      '2. **化验单翻译** — 血常规、肝功能、肾功能、血脂、血糖等常见检验项目\n' +
+      '3. **健康建议** — 根据异常指标给出饮食、运动、作息方面的调理建议\n' +
+      '4. **医学科普** — 用大白话解释专业术语和疾病知识\n' +
+      '5. **网络查询** — 使用 web-search 查询最新医学指南和健康资讯\n\n' +
+      '## 工作流程\n' +
+      '1. 用户发送体检报告文字或图片 → 识别所有指标项\n' +
+      '2. 按系统分类（血液、肝功、肾功、血脂等）逐项解读\n' +
+      '3. 对异常指标（↑↓）重点标注，解释可能原因\n' +
+      '4. 给出综合健康评价和生活建议\n\n' +
+      '## 输出格式\n' +
+      '- 每个指标：指标名 → 你的数值 → 参考范围 → 通俗解读\n' +
+      '- 异常项用 ⚠️ 标注，严重异常用 🔴 标注\n' +
+      '- 最后给出「综合建议」和「建议复查项目」\n\n' +
+      '## 工作原则\n' +
+      '- 语言通俗，避免堆砌专业术语，必要时用比喻帮助理解\n' +
+      '- 区分「需要关注」和「无需担心」的指标，不制造焦虑\n' +
+      '- 遇到严重异常值时，明确建议尽快就医\n' +
+      '- 不做具体疾病确诊，不推荐具体药物\n\n' +
+      '## ⚠️ 免责声明（每次回答必须附带）\n' +
+      '每次回答末尾必须附上以下声明：\n' +
+      '> 📋 以上解读仅供健康参考，不构成医疗诊断或治疗建议。如有异常指标，请及时咨询专业医生。\n\n' +
+      '## 图片支持说明\n' +
+      '- 如果当前模型支持图片输入，可以直接分析用户上传的体检报告图片\n' +
+      '- 如果不支持图片，请引导用户将报告中的数值以文字形式发送\n',
+    skillIds: ['web-search'],
+  },
+  {
+    id: 'pet-care',
+    name: '萌宠管家',
+    icon: '🐾',
+    description:
+      '猫狗日常饲养、异常行为分析、食品配料解读，做你身边有温度的宠物百科。',
+    systemPrompt:
+      '你是一名温暖专业的宠物饲养顾问，熟悉猫狗的健康护理、行为心理和营养学知识。\n\n' +
+      '## 核心能力\n' +
+      '1. **行为分析** — 解读宠物异常行为的原因和应对方法（乱叫、乱尿、食欲变化等）\n' +
+      '2. **健康咨询** — 常见疾病症状识别、就医时机判断、术后护理指导\n' +
+      '3. **营养指导** — 猫粮狗粮配料表解读、自制鲜食建议、营养补充方案\n' +
+      '4. **日常护理** — 疫苗驱虫时间表、洗护美容、季节护理要点\n' +
+      '5. **网络搜索** — 使用 web-search 查询最新宠物医学资讯和产品评测\n\n' +
+      '## 工作流程\n' +
+      '1. 先了解宠物基本信息（品种、年龄、体重、是否绝育）\n' +
+      '2. 详细了解问题表现（持续多久、频率、伴随症状）\n' +
+      '3. 分析可能原因（按可能性从高到低排列）\n' +
+      '4. 给出具体可操作的建议\n\n' +
+      '## 沟通风格\n' +
+      '- 语气温暖亲切，理解宠物主人的焦虑心情\n' +
+      '- 称呼宠物为「毛孩子」「小家伙」等亲切用语\n' +
+      '- 先安抚情绪，再给专业分析\n' +
+      '- 建议要具体可操作，不说空话\n\n' +
+      '## 工作原则\n' +
+      '- 遇到疑似严重疾病症状（持续呕吐、血便、呼吸困难等），立即建议就医，不耽误\n' +
+      '- 食物推荐以安全为第一原则，明确标注禁忌食物（如猫不能吃洋葱、狗不能吃巧克力）\n' +
+      '- 不推荐具体商业品牌，只分析配料表成分\n' +
+      '- 区分猫和狗的差异，不混淆护理方案\n\n' +
+      '## ⚠️ 免责声明（涉及疾病时附带）\n' +
+      '当涉及疾病判断时，回答末尾附上：\n' +
+      '> 🐾 以上分析仅供参考，宠物健康问题请以宠物医院专业诊断为准。如症状持续或加重，请尽快带毛孩子就医。\n',
+    skillIds: ['web-search'],
+  },
+];
+
+/**
+ * Convert a preset agent template to a CreateAgentRequest.
+ */
+export function presetToCreateRequest(preset: PresetAgent): CreateAgentRequest {
+  return {
+    id: preset.id,
+    name: preset.name,
+    description: preset.description,
+    systemPrompt: preset.systemPrompt,
+    icon: preset.icon,
+    skillIds: preset.skillIds,
+    source: 'preset',
+    presetId: preset.id,
+  };
+}
diff --git a/src/renderer/App.tsx b/src/renderer/App.tsx
--- a/src/renderer/App.tsx
+++ b/src/renderer/App.tsx
@@ -9,6 +9,7 @@ import { CoworkView } from './components/cowork';
 import { SkillsView } from './components/skills';
 import { ScheduledTasksView } from './components/scheduledTasks';
 import { McpView } from './components/mcp';
+import AgentsView from './components/agent/AgentsView';
 import CoworkPermissionModal from './components/cowork/CoworkPermissionModal';
 import CoworkQuestionWizard from './components/cowork/CoworkQuestionWizard';
 import EngineStartupOverlay from './components/cowork/EngineStartupOverlay';
@@ -34,7 +35,7 @@ import PrivacyDialog from './components/PrivacyDialog';
 const App: React.FC = () => {
   const [showSettings, setShowSettings] = useState(false);
   const [settingsOptions, setSettingsOptions] = useState<SettingsOpenOptions>({});
-  const [mainView, setMainView] = useState<'cowork' | 'skills' | 'scheduledTasks' | 'mcp'>('cowork');
+  const [mainView, setMainView] = useState<'cowork' | 'skills' | 'scheduledTasks' | 'mcp' | 'agents'>('cowork');
   const [isInitialized, setIsInitialized] = useState(false);
   const [initError, setInitError] = useState<string | null>(null);
   const [toastMessage, setToastMessage] = useState<string | null>(null);
@@ -245,6 +246,10 @@ const App: React.FC = () => {
     setMainView('mcp');
   }, []);
 
+  const handleShowAgents = useCallback(() => {
+    setMainView('agents');
+  }, []);
+
   const handleToggleSidebar = useCallback(() => {
     setIsSidebarCollapsed((prev) => !prev);
   }, []);
@@ -637,6 +642,7 @@ const App: React.FC = () => {
           onShowCowork={handleShowCowork}
           onShowScheduledTasks={handleShowScheduledTasks}
           onShowMcp={handleShowMcp}
+          onShowAgents={handleShowAgents}
           onNewChat={handleNewChat}
           isCollapsed={isSidebarCollapsed}
           onToggleCollapse={handleToggleSidebar}
@@ -666,6 +672,14 @@ const App: React.FC = () => {
                 onNewChat={handleNewChat}
                 updateBadge={isSidebarCollapsed ? updateBadge : null}
               />
+            ) : mainView === 'agents' ? (
+              <AgentsView
+                isSidebarCollapsed={isSidebarCollapsed}
+                onToggleSidebar={handleToggleSidebar}
+                onNewChat={handleNewChat}
+                onShowCowork={handleShowCowork}
+                updateBadge={isSidebarCollapsed ? updateBadge : null}
+              />
             ) : (
               <CoworkView
                 onRequestAppSettings={handleShowSettings}
diff --git a/src/renderer/components/ModelSelector.tsx b/src/renderer/components/ModelSelector.tsx
--- a/src/renderer/components/ModelSelector.tsx
+++ b/src/renderer/components/ModelSelector.tsx
@@ -65,7 +65,14 @@ const ModelSelector: React.FC<ModelSelectorProps> = ({ dropdownDirection = 'down
       }`}
     >
       <div className="flex flex-col">
-        <span className="text-sm">{model.name}</span>
+        <div className="flex items-center gap-1.5">
+          <span className="text-sm">{model.name}</span>
+          {model.supportsImage && (
+            <span className="text-[10px] leading-none px-1.5 py-0.5 rounded-md bg-claude-accent/10 text-claude-accent whitespace-nowrap">
+              {i18nService.t('imageInput')}
+            </span>
+          )}
+        </div>
         {model.provider && (
           <span className="text-xs dark:text-claude-darkTextSecondary text-claude-textSecondary">{model.provider}</span>
         )}
@@ -93,7 +100,7 @@ const ModelSelector: React.FC<ModelSelectorProps> = ({ dropdownDirection = 'down
       </button>
 
       {isOpen && (
-        <div className={`absolute ${dropdownPositionClass} w-52 dark:bg-claude-darkSurface bg-claude-surface rounded-xl popover-enter shadow-popover z-50 dark:border-claude-darkBorder border-claude-border border overflow-hidden`}>
+        <div className={`absolute ${dropdownPositionClass} w-60 dark:bg-claude-darkSurface bg-claude-surface rounded-xl popover-enter shadow-popover z-50 dark:border-claude-darkBorder border-claude-border border overflow-hidden`}>
           <div className="max-h-64 overflow-y-auto">
             {hasBothGroups ? (
               <>
diff --git a/src/renderer/components/Sidebar.tsx b/src/renderer/components/Sidebar.tsx
--- a/src/renderer/components/Sidebar.tsx
+++ b/src/renderer/components/Sidebar.tsx
@@ -1,6 +1,7 @@
 import React, { useEffect, useState, useCallback } from 'react';
 import { useSelector } from 'react-redux';
 import { RootState } from '../store';
+import { agentService } from '../services/agent';
 import { coworkService } from '../services/cowork';
 import { i18nService } from '../services/i18n';
 import CoworkSessionList from './cowork/CoworkSessionList';
@@ -13,16 +14,17 @@ import ClockIcon from './icons/ClockIcon';
 import PuzzleIcon from './icons/PuzzleIcon';
 import SidebarToggleIcon from './icons/SidebarToggleIcon';
 import TrashIcon from './icons/TrashIcon';
-import { ExclamationTriangleIcon } from '@heroicons/react/24/outline';
+import { ExclamationTriangleIcon, UserGroupIcon } from '@heroicons/react/24/outline';
 
 interface SidebarProps {
   onShowSettings: () => void;
   onShowLogin?: () => void;
-  activeView: 'cowork' | 'skills' | 'scheduledTasks' | 'mcp';
+  activeView: 'cowork' | 'skills' | 'scheduledTasks' | 'mcp' | 'agents';
   onShowSkills: () => void;
   onShowCowork: () => void;
   onShowScheduledTasks: () => void;
   onShowMcp: () => void;
+  onShowAgents: () => void;
   onNewChat: () => void;
   isCollapsed: boolean;
   onToggleCollapse: () => void;
@@ -36,12 +38,15 @@ const Sidebar: React.FC<SidebarProps> = ({
   onShowCowork,
   onShowScheduledTasks,
   onShowMcp,
+  onShowAgents,
   onNewChat,
   isCollapsed,
   onToggleCollapse,
   updateBadge,
 }) => {
+  const currentAgentId = useSelector((state: RootState) => state.agent.currentAgentId);
   const sessions = useSelector((state: RootState) => state.cowork.sessions);
+  const filteredSessions = sessions.filter((s) => !s.agentId || s.agentId === currentAgentId);
   const currentSessionId = useSelector((state: RootState) => state.cowork.currentSessionId);
   const [isSearchOpen, setIsSearchOpen] = useState(false);
   const [isBatchMode, setIsBatchMode] = useState(false);
@@ -110,12 +115,12 @@ const Sidebar: React.FC<SidebarProps> = ({
 
   const handleSelectAll = useCallback(() => {
     setSelectedIds(prev => {
-      if (prev.size === sessions.length) {
+      if (prev.size === filteredSessions.length) {
         return new Set();
       }
-      return new Set(sessions.map(s => s.id));
+      return new Set(filteredSessions.map(s => s.id));
     });
-  }, [sessions]);
+  }, [filteredSessions]);
 
   const handleBatchDeleteClick = useCallback(() => {
     if (selectedIds.size === 0) return;
@@ -218,14 +223,32 @@ const Sidebar: React.FC<SidebarProps> = ({
             <ConnectorIcon className="h-4 w-4" />
             {i18nService.t('mcpServers')}
           </button>
+          <button
+            type="button"
+            onClick={() => {
+              setIsSearchOpen(false);
+              onShowAgents();
+            }}
+            className={`w-full inline-flex items-center gap-2 rounded-lg px-2.5 py-2 text-sm font-medium transition-colors ${
+              activeView === 'agents'
+                ? 'bg-claude-accent/10 text-claude-accent hover:bg-claude-accent/20'
+                : 'dark:text-claude-darkTextSecondary text-claude-textSecondary hover:text-claude-text dark:hover:text-claude-darkText hover:bg-claude-surfaceHover dark:hover:bg-claude-darkSurfaceHover'
+            }`}
+          >
+            <UserGroupIcon className="h-4 w-4" />
+            {i18nService.t('myAgents')}
+          </button>
         </div>
       </div>
       <div className="flex-1 overflow-y-auto px-2.5 pb-4">
+        <SidebarAgentList
+          onShowCowork={onShowCowork}
+        />
         <div className="px-3 pb-2 text-sm font-medium dark:text-claude-darkTextSecondary text-claude-textSecondary">
           {i18nService.t('coworkHistory')}
         </div>
         <CoworkSessionList
-          sessions={sessions}
+          sessions={filteredSessions}
           currentSessionId={currentSessionId}
           isBatchMode={isBatchMode}
           selectedIds={selectedIds}
@@ -240,7 +263,7 @@ const Sidebar: React.FC<SidebarProps> = ({
       <CoworkSearchModal
         isOpen={isSearchOpen}
         onClose={() => setIsSearchOpen(false)}
-        sessions={sessions}
+        sessions={filteredSessions}
         currentSessionId={currentSessionId}
         onSelectSession={handleSelectSession}
         onDeleteSession={handleDeleteSession}
@@ -252,7 +275,7 @@ const Sidebar: React.FC<SidebarProps> = ({
           <label className="flex items-center gap-2 cursor-pointer text-sm dark:text-claude-darkTextSecondary text-claude-textSecondary">
             <input
               type="checkbox"
-              checked={selectedIds.size === sessions.length && sessions.length > 0}
+              checked={selectedIds.size === filteredSessions.length && filteredSessions.length > 0}
               onChange={handleSelectAll}
               className="h-4 w-4 rounded border-gray-300 dark:border-gray-600 accent-claude-accent cursor-pointer"
             />
@@ -340,4 +363,52 @@ const Sidebar: React.FC<SidebarProps> = ({
   );
 };
 
+/* ── Simplified agent list for sidebar quick-switch ─── */
+
+const SidebarAgentList: React.FC<{
+  onShowCowork: () => void;
+}> = ({ onShowCowork }) => {
+  const agents = useSelector((state: RootState) => state.agent.agents);
+  const currentAgentId = useSelector((state: RootState) => state.agent.currentAgentId);
+
+  useEffect(() => {
+    agentService.loadAgents();
+  }, []);
+
+  const enabledAgents = agents.filter((a) => a.enabled);
+
+  // Hide section if only the default main agent exists
+  if (enabledAgents.length <= 1 && !enabledAgents.some((a) => a.source === 'preset')) {
+    return null;
+  }
+
+  const handleSwitch = (agentId: string) => {
+    if (agentId === currentAgentId) return;
+    agentService.switchAgent(agentId);
+    coworkService.loadSessions(agentId);
+    onShowCowork();
+  };
+
+  return (
+    <div className="px-3 pb-2">
+      <div className="space-y-0.5">
+        {enabledAgents.map((agent) => (
+          <div
+            key={agent.id}
+            className={`group flex items-center gap-2 rounded-lg px-2 py-1.5 text-sm cursor-pointer transition-colors ${
+              currentAgentId === agent.id
+                ? 'bg-claude-accent/10 text-claude-accent'
+                : 'dark:text-claude-darkTextSecondary text-claude-textSecondary hover:bg-claude-surfaceHover dark:hover:bg-claude-darkSurfaceHover'
+            }`}
+            onClick={() => handleSwitch(agent.id)}
+          >
+            <span className="text-base leading-none">{agent.icon || '🦞'}</span>
+            <span className="truncate flex-1 text-xs font-medium">{agent.name}</span>
+          </div>
+        ))}
+      </div>
+    </div>
+  );
+};
+
 export default Sidebar;
diff --git a/src/renderer/components/agent/AgentCreateModal.tsx b/src/renderer/components/agent/AgentCreateModal.tsx
new file mode 100644
--- /dev/null
+++ b/src/renderer/components/agent/AgentCreateModal.tsx
@@ -0,0 +1,133 @@
+import React, { useState } from 'react';
+import { agentService } from '../../services/agent';
+import { i18nService } from '../../services/i18n';
+import { XMarkIcon } from '@heroicons/react/24/outline';
+import AgentSkillSelector from './AgentSkillSelector';
+
+interface AgentCreateModalProps {
+  isOpen: boolean;
+  onClose: () => void;
+}
+
+const AgentCreateModal: React.FC<AgentCreateModalProps> = ({ isOpen, onClose }) => {
+  const [name, setName] = useState('');
+  const [description, setDescription] = useState('');
+  const [systemPrompt, setSystemPrompt] = useState('');
+  const [icon, setIcon] = useState('');
+  const [skillIds, setSkillIds] = useState<string[]>([]);
+  const [creating, setCreating] = useState(false);
+
+  if (!isOpen) return null;
+
+  const handleCreate = async () => {
+    if (!name.trim()) return;
+    setCreating(true);
+    try {
+      const agent = await agentService.createAgent({
+        name: name.trim(),
+        description: description.trim(),
+        systemPrompt: systemPrompt.trim(),
+        icon: icon.trim() || undefined,
+        skillIds,
+      });
+      if (agent) {
+        agentService.switchAgent(agent.id);
+        onClose();
+        setName('');
+        setDescription('');
+        setSystemPrompt('');
+        setIcon('');
+        setSkillIds([]);
+      }
+    } finally {
+      setCreating(false);
+    }
+  };
+
+  return (
+    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50" onClick={onClose}>
+      <div
+        className="w-full max-w-md mx-4 rounded-xl shadow-xl bg-white dark:bg-claude-darkSurface border dark:border-claude-darkBorder border-claude-border"
+        onClick={(e) => e.stopPropagation()}
+      >
+        <div className="flex items-center justify-between px-5 py-4 border-b dark:border-claude-darkBorder border-claude-border">
+          <h3 className="text-base font-semibold dark:text-claude-darkText text-claude-text">
+            {i18nService.t('createAgent') || 'Create Agent'}
+          </h3>
+          <button type="button" onClick={onClose} className="p-1 rounded-lg hover:bg-claude-surfaceHover dark:hover:bg-claude-darkSurfaceHover">
+            <XMarkIcon className="h-5 w-5 dark:text-claude-darkTextSecondary text-claude-textSecondary" />
+          </button>
+        </div>
+        <div className="px-5 py-4 space-y-4">
+          <div>
+            <label className="block text-sm font-medium dark:text-claude-darkTextSecondary text-claude-textSecondary mb-1">
+              {i18nService.t('agentName') || 'Name'} *
+            </label>
+            <div className="flex gap-2">
+              <input
+                type="text"
+                value={icon}
+                onChange={(e) => setIcon(e.target.value)}
+                placeholder="🤖"
+                className="w-12 px-2 py-2 text-center rounded-lg border dark:border-claude-darkBorder border-claude-border bg-transparent dark:text-claude-darkText text-claude-text text-lg"
+                maxLength={4}
+              />
+              <input
+                type="text"
+                value={name}
+                onChange={(e) => setName(e.target.value)}
+                placeholder={i18nService.t('agentNamePlaceholder') || 'Agent name'}
+                className="flex-1 px-3 py-2 rounded-lg border dark:border-claude-darkBorder border-claude-border bg-transparent dark:text-claude-darkText text-claude-text text-sm"
+                autoFocus
+              />
+            </div>
+          </div>
+          <div>
+            <label className="block text-sm font-medium dark:text-claude-darkTextSecondary text-claude-textSecondary mb-1">
+              {i18nService.t('agentDescription') || 'Description'}
+            </label>
+            <input
+              type="text"
+              value={description}
+              onChange={(e) => setDescription(e.target.value)}
+              placeholder={i18nService.t('agentDescriptionPlaceholder') || 'Brief description'}
+              className="w-full px-3 py-2 rounded-lg border dark:border-claude-darkBorder border-claude-border bg-transparent dark:text-claude-darkText text-claude-text text-sm"
+            />
+          </div>
+          <div>
+            <label className="block text-sm font-medium dark:text-claude-darkTextSecondary text-claude-textSecondary mb-1">
+              {i18nService.t('systemPrompt') || 'System Prompt'}
+            </label>
+            <textarea
+              value={systemPrompt}
+              onChange={(e) => setSystemPrompt(e.target.value)}
+              placeholder={i18nService.t('systemPromptPlaceholder') || 'Describe the agent\'s role and behavior...'}
+              rows={4}
+              className="w-full px-3 py-2 rounded-lg border dark:border-claude-darkBorder border-claude-border bg-transparent dark:text-claude-darkText text-claude-text text-sm resize-none"
+            />
+          </div>
+          <AgentSkillSelector selectedSkillIds={skillIds} onChange={setSkillIds} />
+        </div>
+        <div className="flex justify-end gap-2 px-5 py-4 border-t dark:border-claude-darkBorder border-claude-border">
+          <button
+            type="button"
+            onClick={onClose}
+            className="px-4 py-2 text-sm font-medium rounded-lg dark:text-claude-darkTextSecondary text-claude-textSecondary hover:bg-claude-surfaceHover dark:hover:bg-claude-darkSurfaceHover transition-colors"
+          >
+            {i18nService.t('cancel') || 'Cancel'}
+          </button>
+          <button
+            type="button"
+            onClick={handleCreate}
+            disabled={!name.trim() || creating}
+            className="px-4 py-2 text-sm font-medium rounded-lg bg-claude-accent text-white hover:bg-claude-accent/90 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
+          >
+            {creating ? (i18nService.t('creating') || 'Creating...') : (i18nService.t('create') || 'Create')}
+          </button>
+        </div>
+      </div>
+    </div>
+  );
+};
+
+export default AgentCreateModal;
diff --git a/src/renderer/components/agent/AgentSettingsPanel.tsx b/src/renderer/components/agent/AgentSettingsPanel.tsx
new file mode 100644
--- /dev/null
+++ b/src/renderer/components/agent/AgentSettingsPanel.tsx
@@ -0,0 +1,389 @@
+import React, { useEffect, useState } from 'react';
+import { useSelector } from 'react-redux';
+import { RootState } from '../../store';
+import { agentService } from '../../services/agent';
+import { imService } from '../../services/im';
+import { i18nService } from '../../services/i18n';
+import { XMarkIcon, TrashIcon } from '@heroicons/react/24/outline';
+import type { Agent } from '../../types/agent';
+import type { IMPlatform, IMGatewayConfig } from '../../types/im';
+import { getVisibleIMPlatforms } from '../../utils/regionFilter';
+import AgentSkillSelector from './AgentSkillSelector';
+
+type SettingsTab = 'basic' | 'skills' | 'im';
+
+const IM_PLATFORMS: { key: IMPlatform; logo: string }[] = [
+  { key: 'dingtalk', logo: 'dingding.png' },
+  { key: 'feishu', logo: 'feishu.png' },
+  { key: 'qq', logo: 'qq_bot.jpeg' },
+  { key: 'telegram', logo: 'telegram.svg' },
+  { key: 'discord', logo: 'discord.svg' },
+  { key: 'nim', logo: 'nim.png' },
+  { key: 'xiaomifeng', logo: 'xiaomifeng.png' },
+  { key: 'weixin', logo: 'weixin.png' },
+  { key: 'wecom', logo: 'wecom.png' },
+  { key: 'popo', logo: 'popo.png' },
+];
+
+interface AgentSettingsPanelProps {
+  agentId: string | null;
+  onClose: () => void;
+  onSwitchAgent?: (agentId: string) => void;
+}
+
+const AgentSettingsPanel: React.FC<AgentSettingsPanelProps> = ({ agentId, onClose, onSwitchAgent }) => {
+  const currentAgentId = useSelector((state: RootState) => state.agent.currentAgentId);
+  const [, setAgent] = useState<Agent | null>(null);
+  const [name, setName] = useState('');
+  const [description, setDescription] = useState('');
+  const [systemPrompt, setSystemPrompt] = useState('');
+  const [identity, setIdentity] = useState('');
+  const [icon, setIcon] = useState('');
+  const [skillIds, setSkillIds] = useState<string[]>([]);
+  const [saving, setSaving] = useState(false);
+  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
+  const [activeTab, setActiveTab] = useState<SettingsTab>('basic');
+
+  // IM binding state
+  const [imConfig, setImConfig] = useState<IMGatewayConfig | null>(null);
+  const [boundPlatforms, setBoundPlatforms] = useState<Set<IMPlatform>>(new Set());
+  const [initialBoundPlatforms, setInitialBoundPlatforms] = useState<Set<IMPlatform>>(new Set());
+
+  useEffect(() => {
+    if (!agentId) return;
+    setActiveTab('basic');
+    setShowDeleteConfirm(false);
+    window.electron?.agents?.get(agentId).then((a) => {
+      if (a) {
+        setAgent(a);
+        setName(a.name);
+        setDescription(a.description);
+        setSystemPrompt(a.systemPrompt);
+        setIdentity(a.identity);
+        setIcon(a.icon);
+        setSkillIds(a.skillIds ?? []);
+      }
+    });
+    // Load IM config for bindings
+    imService.loadConfig().then((cfg) => {
+      if (cfg) {
+        setImConfig(cfg);
+        const bindings = cfg.settings?.platformAgentBindings || {};
+        const bound = new Set<IMPlatform>();
+        for (const [platform, boundAgentId] of Object.entries(bindings)) {
+          if (boundAgentId === agentId) {
+            bound.add(platform as IMPlatform);
+          }
+        }
+        setBoundPlatforms(bound);
+        setInitialBoundPlatforms(new Set(bound));
+      }
+    });
+  }, [agentId]);
+
+  if (!agentId) return null;
+
+  const handleSave = async () => {
+    if (!name.trim()) return;
+    setSaving(true);
+    try {
+      await agentService.updateAgent(agentId, {
+        name: name.trim(),
+        description: description.trim(),
+        systemPrompt: systemPrompt.trim(),
+        identity: identity.trim(),
+        icon: icon.trim(),
+        skillIds,
+      });
+      // Persist IM bindings if changed
+      const bindingsChanged =
+        boundPlatforms.size !== initialBoundPlatforms.size ||
+        [...boundPlatforms].some((p) => !initialBoundPlatforms.has(p));
+      if (bindingsChanged && imConfig) {
+        const currentBindings = { ...(imConfig.settings?.platformAgentBindings || {}) };
+        // Remove old bindings for this agent
+        for (const key of Object.keys(currentBindings)) {
+          if (currentBindings[key] === agentId) {
+            delete currentBindings[key];
+          }
+        }
+        // Add new bindings
+        for (const platform of boundPlatforms) {
+          currentBindings[platform] = agentId;
+        }
+        await imService.persistConfig({
+          settings: { ...imConfig.settings, platformAgentBindings: currentBindings },
+        });
+        await imService.saveAndSyncConfig();
+      }
+      onClose();
+    } finally {
+      setSaving(false);
+    }
+  };
+
+  const handleDelete = async () => {
+    const success = await agentService.deleteAgent(agentId);
+    if (success) {
+      onClose();
+    }
+  };
+
+  const handleToggleIMBinding = (platform: IMPlatform) => {
+    const next = new Set(boundPlatforms);
+    if (next.has(platform)) {
+      next.delete(platform);
+    } else {
+      next.add(platform);
+    }
+    setBoundPlatforms(next);
+  };
+
+  const isPlatformConfigured = (platform: IMPlatform): boolean => {
+    if (!imConfig) return false;
+    return imConfig[platform]?.enabled === true;
+  };
+
+  const isMainAgent = agentId === 'main';
+
+  const tabs: { key: SettingsTab; label: string }[] = [
+    { key: 'basic', label: i18nService.t('agentTabBasic') || 'Basic Info' },
+    { key: 'skills', label: i18nService.t('agentTabSkills') || 'Skills' },
+    { key: 'im', label: i18nService.t('agentTabIM') || 'IM Channels' },
+  ];
+
+  return (
+    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50" onClick={onClose}>
+      <div
+        className="w-full max-w-2xl mx-4 rounded-xl shadow-xl bg-white dark:bg-claude-darkSurface border dark:border-claude-darkBorder border-claude-border max-h-[80vh] flex flex-col"
+        onClick={(e) => e.stopPropagation()}
+      >
+        {/* Header: agent icon + name + close */}
+        <div className="flex items-center justify-between px-5 py-4 border-b dark:border-claude-darkBorder border-claude-border">
+          <div className="flex items-center gap-2">
+            <span className="text-xl">{icon || '🤖'}</span>
+            <h3 className="text-base font-semibold dark:text-claude-darkText text-claude-text">
+              {name || (i18nService.t('agentSettings') || 'Agent Settings')}
+            </h3>
+          </div>
+          <button type="button" onClick={onClose} className="p-1 rounded-lg hover:bg-claude-surfaceHover dark:hover:bg-claude-darkSurfaceHover">
+            <XMarkIcon className="h-5 w-5 dark:text-claude-darkTextSecondary text-claude-textSecondary" />
+          </button>
+        </div>
+
+        {/* Tab bar */}
+        <div className="flex border-b dark:border-claude-darkBorder border-claude-border px-5">
+          {tabs.map((tab) => (
+            <button
+              key={tab.key}
+              type="button"
+              onClick={() => setActiveTab(tab.key)}
+              className={`px-4 py-2.5 text-sm font-medium transition-colors relative ${
+                activeTab === tab.key
+                  ? 'text-claude-accent'
+                  : 'dark:text-claude-darkTextSecondary text-claude-textSecondary hover:text-claude-text dark:hover:text-claude-darkText'
+              }`}
+            >
+              {tab.label}
+              {activeTab === tab.key && (
+                <div className="absolute bottom-0 left-0 right-0 h-0.5 bg-claude-accent rounded-full" />
+              )}
+            </button>
+          ))}
+        </div>
+
+        {/* Tab content */}
+        <div className="px-5 py-4 overflow-y-auto flex-1 min-h-[300px]">
+          {activeTab === 'basic' && (
+            <div className="space-y-4">
+              <div>
+                <label className="block text-sm font-medium dark:text-claude-darkTextSecondary text-claude-textSecondary mb-1">
+                  {i18nService.t('agentName') || 'Name'}
+                </label>
+                <div className="flex gap-2">
+                  <input
+                    type="text"
+                    value={icon}
+                    onChange={(e) => setIcon(e.target.value)}
+                    placeholder="🤖"
+                    className="w-12 px-2 py-2 text-center rounded-lg border dark:border-claude-darkBorder border-claude-border bg-transparent dark:text-claude-darkText text-claude-text text-lg"
+                    maxLength={4}
+                  />
+                  <input
+                    type="text"
+                    value={name}
+                    onChange={(e) => setName(e.target.value)}
+                    className="flex-1 px-3 py-2 rounded-lg border dark:border-claude-darkBorder border-claude-border bg-transparent dark:text-claude-darkText text-claude-text text-sm"
+                  />
+                </div>
+              </div>
+              <div>
+                <label className="block text-sm font-medium dark:text-claude-darkTextSecondary text-claude-textSecondary mb-1">
+                  {i18nService.t('agentDescription') || 'Description'}
+                </label>
+                <input
+                  type="text"
+                  value={description}
+                  onChange={(e) => setDescription(e.target.value)}
+                  className="w-full px-3 py-2 rounded-lg border dark:border-claude-darkBorder border-claude-border bg-transparent dark:text-claude-darkText text-claude-text text-sm"
+                />
+              </div>
+              <div>
+                <label className="block text-sm font-medium dark:text-claude-darkTextSecondary text-claude-textSecondary mb-1">
+                  {i18nService.t('systemPrompt') || 'System Prompt'}
+                </label>
+                <textarea
+                  value={systemPrompt}
+                  onChange={(e) => setSystemPrompt(e.target.value)}
+                  rows={4}
+                  className="w-full px-3 py-2 rounded-lg border dark:border-claude-darkBorder border-claude-border bg-transparent dark:text-claude-darkText text-claude-text text-sm resize-none"
+                />
+              </div>
+              <div>
+                <label className="block text-sm font-medium dark:text-claude-darkTextSecondary text-claude-textSecondary mb-1">
+                  {i18nService.t('agentIdentity') || 'Identity'}
+                </label>
+                <textarea
+                  value={identity}
+                  onChange={(e) => setIdentity(e.target.value)}
+                  rows={3}
+                  placeholder={i18nService.t('agentIdentityPlaceholder') || 'Identity description (IDENTITY.md)...'}
+                  className="w-full px-3 py-2 rounded-lg border dark:border-claude-darkBorder border-claude-border bg-transparent dark:text-claude-darkText text-claude-text text-sm resize-none"
+                />
+              </div>
+            </div>
+          )}
+
+          {activeTab === 'skills' && (
+            <AgentSkillSelector selectedSkillIds={skillIds} onChange={setSkillIds} variant="expanded" />
+          )}
+
+          {activeTab === 'im' && (
+            <div>
+              <p className="text-xs dark:text-claude-darkTextSecondary/60 text-claude-textSecondary/60 mb-4">
+                {i18nService.t('agentIMBindHint') || 'Select IM channels this Agent responds to'}
+              </p>
+              <div className="space-y-1">
+                {IM_PLATFORMS
+                  .filter(({ key }) => (getVisibleIMPlatforms(i18nService.getLanguage()) as readonly string[]).includes(key))
+                  .map(({ key: platform, logo }) => {
+                  const configured = isPlatformConfigured(platform);
+                  const bound = boundPlatforms.has(platform);
+                  return (
+                    <div
+                      key={platform}
+                      className={`flex items-center justify-between px-3 py-2.5 rounded-lg transition-colors ${
+                        configured
+                          ? 'hover:bg-claude-surfaceHover dark:hover:bg-claude-darkSurfaceHover cursor-pointer'
+                          : 'opacity-50'
+                      }`}
+                      onClick={() => configured && handleToggleIMBinding(platform)}
+                    >
+                      <div className="flex items-center gap-3">
+                        <div className="flex h-8 w-8 items-center justify-center">
+                          <img src={logo} alt={i18nService.t(platform)} className="w-6 h-6 object-contain rounded" />
+                        </div>
+                        <div>
+                          <div className="text-sm font-medium dark:text-claude-darkText text-claude-text">
+                            {i18nService.t(platform)}
+                          </div>
+                          {!configured && (
+                            <div className="text-xs dark:text-claude-darkTextSecondary/50 text-claude-textSecondary/50">
+                              {i18nService.t('agentIMNotConfiguredHint') || 'Please configure in Settings > IM Bots first'}
+                            </div>
+                          )}
+                        </div>
+                      </div>
+                      <div className="flex items-center gap-2">
+                        {configured ? (
+                          <div
+                            className={`relative w-9 h-5 rounded-full transition-colors ${
+                              bound ? 'bg-claude-accent' : 'bg-gray-300 dark:bg-gray-600'
+                            }`}
+                          >
+                            <div
+                              className={`absolute top-0.5 w-4 h-4 rounded-full bg-white shadow transition-transform ${
+                                bound ? 'translate-x-4' : 'translate-x-0.5'
+                              }`}
+                            />
+                          </div>
+                        ) : (
+                          <span className="text-xs dark:text-claude-darkTextSecondary/50 text-claude-textSecondary/50">
+                            {i18nService.t('agentIMNotConfigured') || 'Not configured'}
+                          </span>
+                        )}
+                      </div>
+                    </div>
+                  );
+                })}
+              </div>
+            </div>
+          )}
+        </div>
+
+        {/* Footer */}
+        <div className="flex items-center justify-between px-5 py-4 border-t dark:border-claude-darkBorder border-claude-border">
+          <div>
+            {!isMainAgent && !showDeleteConfirm && (
+              <button
+                type="button"
+                onClick={() => setShowDeleteConfirm(true)}
+                className="inline-flex items-center gap-1 px-3 py-2 text-sm font-medium rounded-lg text-red-500 hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors"
+              >
+                <TrashIcon className="h-4 w-4" />
+                {i18nService.t('delete') || 'Delete'}
+              </button>
+            )}
+            {showDeleteConfirm && (
+              <div className="flex items-center gap-2">
+                <span className="text-xs text-red-500">{i18nService.t('confirmDelete') || 'Confirm?'}</span>
+                <button
+                  type="button"
+                  onClick={handleDelete}
+                  className="px-2 py-1 text-xs font-medium rounded bg-red-500 text-white hover:bg-red-600"
+                >
+                  {i18nService.t('delete') || 'Delete'}
+                </button>
+                <button
+                  type="button"
+                  onClick={() => setShowDeleteConfirm(false)}
+                  className="px-2 py-1 text-xs font-medium rounded dark:text-claude-darkTextSecondary text-claude-textSecondary hover:bg-claude-surfaceHover dark:hover:bg-claude-darkSurfaceHover"
+                >
+                  {i18nService.t('cancel') || 'Cancel'}
+                </button>
+              </div>
+            )}
+          </div>
+          <div className="flex gap-2">
+            {onSwitchAgent && agentId !== currentAgentId && (
+              <button
+                type="button"
+                onClick={() => onSwitchAgent(agentId)}
+                className="px-4 py-2 text-sm font-medium rounded-lg border border-claude-accent text-claude-accent hover:bg-claude-accent/10 transition-colors"
+              >
+                {i18nService.t('switchToAgent') || 'Use this Agent'}
+              </button>
+            )}
+            <button
+              type="button"
+              onClick={onClose}
+              className="px-4 py-2 text-sm font-medium rounded-lg dark:text-claude-darkTextSecondary text-claude-textSecondary hover:bg-claude-surfaceHover dark:hover:bg-claude-darkSurfaceHover transition-colors"
+            >
+              {i18nService.t('cancel') || 'Cancel'}
+            </button>
+            <button
+              type="button"
+              onClick={handleSave}
+              disabled={!name.trim() || saving}
+              className="px-4 py-2 text-sm font-medium rounded-lg bg-claude-accent text-white hover:bg-claude-accent/90 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
+            >
+              {saving ? (i18nService.t('saving') || 'Saving...') : (i18nService.t('save') || 'Save')}
+            </button>
+          </div>
+        </div>
+      </div>
+    </div>
+  );
+};
+
+export default AgentSettingsPanel;
diff --git a/src/renderer/components/agent/AgentSkillSelector.tsx b/src/renderer/components/agent/AgentSkillSelector.tsx
new file mode 100644
--- /dev/null
+++ b/src/renderer/components/agent/AgentSkillSelector.tsx
@@ -0,0 +1,150 @@
+import React, { useState, useMemo } from 'react';
+import { useSelector } from 'react-redux';
+import { RootState } from '../../store';
+import { i18nService } from '../../services/i18n';
+import { CheckIcon, MagnifyingGlassIcon, ChevronDownIcon, ChevronUpIcon } from '@heroicons/react/24/outline';
+
+interface AgentSkillSelectorProps {
+  selectedSkillIds: string[];
+  onChange: (skillIds: string[]) => void;
+  /** 'compact' = collapsible dropdown (default), 'expanded' = always-open list */
+  variant?: 'compact' | 'expanded';
+}
+
+const AgentSkillSelector: React.FC<AgentSkillSelectorProps> = ({ selectedSkillIds, onChange, variant = 'compact' }) => {
+  const skills = useSelector((state: RootState) => state.skill.skills);
+  const [expanded, setExpanded] = useState(false);
+  const [search, setSearch] = useState('');
+
+  const enabledSkills = useMemo(
+    () => skills.filter((s) => s.enabled),
+    [skills],
+  );
+
+  const filteredSkills = useMemo(() => {
+    if (!search.trim()) return enabledSkills;
+    const q = search.toLowerCase();
+    return enabledSkills.filter(
+      (s) => s.name.toLowerCase().includes(q) || s.description.toLowerCase().includes(q),
+    );
+  }, [enabledSkills, search]);
+
+  const toggle = (skillId: string) => {
+    if (selectedSkillIds.includes(skillId)) {
+      onChange(selectedSkillIds.filter((id) => id !== skillId));
+    } else {
+      onChange([...selectedSkillIds, skillId]);
+    }
+  };
+
+  const selectedCount = selectedSkillIds.length;
+  const isExpanded = variant === 'expanded';
+  const showList = isExpanded || expanded;
+
+  /* ── Skill list content (shared between compact & expanded) ── */
+  const skillList = (
+    <>
+      {enabledSkills.length > 5 && (
+        <div className={isExpanded ? 'mb-2' : 'px-3 py-2 border-b dark:border-claude-darkBorder border-claude-border'}>
+          <div className="relative">
+            <MagnifyingGlassIcon className="absolute left-2 top-1/2 -translate-y-1/2 h-4 w-4 dark:text-claude-darkTextSecondary/50 text-claude-textSecondary/50" />
+            <input
+              type="text"
+              value={search}
+              onChange={(e) => setSearch(e.target.value)}
+              placeholder={i18nService.t('agentSkillsSearch') || 'Search skills...'}
+              className="w-full pl-8 pr-3 py-1.5 text-sm rounded border dark:border-claude-darkBorder border-claude-border bg-transparent dark:text-claude-darkText text-claude-text"
+            />
+          </div>
+        </div>
+      )}
+      <div className={isExpanded ? 'flex-1 overflow-y-auto' : 'max-h-48 overflow-y-auto'}>
+        {filteredSkills.length === 0 ? (
+          <div className="px-3 py-3 text-sm dark:text-claude-darkTextSecondary/50 text-claude-textSecondary/50 text-center">
+            {enabledSkills.length === 0 ? 'No skills installed' : 'No matching skills'}
+          </div>
+        ) : (
+          filteredSkills.map((skill) => {
+            const isSelected = selectedSkillIds.includes(skill.id);
+            return (
+              <button
+                key={skill.id}
+                type="button"
+                onClick={() => toggle(skill.id)}
+                className={`w-full flex items-start gap-2.5 px-3 py-2 text-left hover:bg-claude-surfaceHover dark:hover:bg-claude-darkSurfaceHover transition-colors rounded-lg ${
+                  isSelected ? 'bg-claude-accent/5 dark:bg-claude-accent/10' : ''
+                }`}
+              >
+                <div className={`mt-0.5 flex-shrink-0 w-4 h-4 rounded border flex items-center justify-center ${
+                  isSelected
+                    ? 'bg-claude-accent border-claude-accent'
+                    : 'dark:border-claude-darkBorder border-claude-border'
+                }`}>
+                  {isSelected && <CheckIcon className="h-3 w-3 text-white" />}
+                </div>
+                <div className="min-w-0 flex-1">
+                  <div className="text-sm font-medium dark:text-claude-darkText text-claude-text truncate">
+                    {skill.name}
+                  </div>
+                  {skill.description && (
+                    <div className="text-xs dark:text-claude-darkTextSecondary/60 text-claude-textSecondary/60 truncate">
+                      {skill.description}
+                    </div>
+                  )}
+                </div>
+              </button>
+            );
+          })
+        )}
+      </div>
+    </>
+  );
+
+  /* ── Expanded variant: no collapsible wrapper ── */
+  if (isExpanded) {
+    return (
+      <div className="flex flex-col h-full">
+        <p className="text-xs dark:text-claude-darkTextSecondary/60 text-claude-textSecondary/60 mb-3">
+          {i18nService.t('agentSkillsHint') || 'Select skills available to this Agent. Leave empty to use all enabled skills.'}
+        </p>
+        {skillList}
+      </div>
+    );
+  }
+
+  /* ── Compact variant: collapsible dropdown ── */
+  return (
+    <div>
+      <label className="block text-sm font-medium dark:text-claude-darkTextSecondary text-claude-textSecondary mb-1">
+        {i18nService.t('agentSkills') || 'Skills'}
+      </label>
+      <button
+        type="button"
+        onClick={() => setExpanded(!expanded)}
+        className="w-full flex items-center justify-between px-3 py-2 rounded-lg border dark:border-claude-darkBorder border-claude-border bg-transparent dark:text-claude-darkText text-claude-text text-sm hover:bg-claude-surfaceHover dark:hover:bg-claude-darkSurfaceHover transition-colors"
+      >
+        <span className={selectedCount > 0 ? '' : 'dark:text-claude-darkTextSecondary/50 text-claude-textSecondary/50'}>
+          {selectedCount > 0
+            ? enabledSkills
+                .filter((s) => selectedSkillIds.includes(s.id))
+                .map((s) => s.name)
+                .join(', ')
+            : i18nService.t('agentSkillsNone') || 'Click to select skills'}
+        </span>
+        {expanded
+          ? <ChevronUpIcon className="h-4 w-4 dark:text-claude-darkTextSecondary text-claude-textSecondary" />
+          : <ChevronDownIcon className="h-4 w-4 dark:text-claude-darkTextSecondary text-claude-textSecondary" />}
+      </button>
+      {showList && (
+        <div className="mt-1 rounded-lg border dark:border-claude-darkBorder border-claude-border overflow-hidden">
+          {skillList}
+        </div>
+      )}
+      <p className="mt-1 text-xs dark:text-claude-darkTextSecondary/60 text-claude-textSecondary/60">
+        {i18nService.t('agentSkillsHint') || 'Select skills available to this Agent. Leave empty to use all enabled skills.'}
+      </p>
+    </div>
+  );
+};
+
+export default AgentSkillSelector;
diff --git a/src/renderer/components/agent/AgentsView.tsx b/src/renderer/components/agent/AgentsView.tsx
new file mode 100644
--- /dev/null
+++ b/src/renderer/components/agent/AgentsView.tsx
@@ -0,0 +1,252 @@
+import React, { useEffect, useState } from 'react';
+import { useSelector } from 'react-redux';
+import { RootState } from '../../store';
+import { agentService } from '../../services/agent';
+import { coworkService } from '../../services/cowork';
+import { i18nService } from '../../services/i18n';
+import { PlusIcon } from '@heroicons/react/24/outline';
+import type { PresetAgent } from '../../types/agent';
+import AgentCreateModal from './AgentCreateModal';
+import AgentSettingsPanel from './AgentSettingsPanel';
+import SidebarToggleIcon from '../icons/SidebarToggleIcon';
+import ComposeIcon from '../icons/ComposeIcon';
+import WindowTitleBar from '../window/WindowTitleBar';
+
+interface AgentsViewProps {
+  isSidebarCollapsed?: boolean;
+  onToggleSidebar?: () => void;
+  onNewChat?: () => void;
+  onShowCowork?: () => void;
+  updateBadge?: React.ReactNode;
+}
+
+const AgentsView: React.FC<AgentsViewProps> = ({
+  isSidebarCollapsed,
+  onToggleSidebar,
+  onNewChat,
+  onShowCowork,
+  updateBadge,
+}) => {
+  const isMac = window.electron.platform === 'darwin';
+  const agents = useSelector((state: RootState) => state.agent.agents);
+  const currentAgentId = useSelector((state: RootState) => state.agent.currentAgentId);
+  const [presets, setPresets] = useState<PresetAgent[]>([]);
+  const [isCreateOpen, setIsCreateOpen] = useState(false);
+  const [settingsAgentId, setSettingsAgentId] = useState<string | null>(null);
+  const [addingPreset, setAddingPreset] = useState<string | null>(null);
+
+  useEffect(() => {
+    agentService.loadAgents();
+    agentService.getPresets().then(setPresets);
+  }, []);
+
+  // Refresh presets when agents change (to update installed status)
+  useEffect(() => {
+    agentService.getPresets().then(setPresets);
+  }, [agents]);
+
+  const enabledAgents = agents.filter((a) => a.enabled && a.id !== 'main');
+  const presetAgents = enabledAgents.filter((a) => a.source === 'preset');
+  const customAgents = enabledAgents.filter((a) => a.source === 'custom');
+  const uninstalledPresets = presets.filter((p) => !p.installed);
+
+  const handleAddPreset = async (presetId: string) => {
+    setAddingPreset(presetId);
+    try {
+      await agentService.addPreset(presetId);
+    } finally {
+      setAddingPreset(null);
+    }
+  };
+
+  const handleSwitchAgent = (agentId: string) => {
+    agentService.switchAgent(agentId);
+    coworkService.loadSessions(agentId);
+    onShowCowork?.();
+  };
+
+  return (
+    <div className="flex-1 flex flex-col dark:bg-claude-darkBg bg-claude-bg h-full">
+      {/* Header */}
+      <div className="draggable flex h-12 items-center justify-between px-4 border-b dark:border-claude-darkBorder border-claude-border shrink-0">
+        <div className="flex items-center space-x-3 h-8">
+          {isSidebarCollapsed && (
+            <div className={`non-draggable flex items-center gap-1 ${isMac ? 'pl-[68px]' : ''}`}>
+              <button
+                type="button"
+                onClick={onToggleSidebar}
+                className="h-8 w-8 inline-flex items-center justify-center rounded-lg dark:text-claude-darkTextSecondary text-claude-textSecondary hover:bg-claude-surfaceHover dark:hover:bg-claude-darkSurfaceHover transition-colors"
+              >
+                <SidebarToggleIcon className="h-4 w-4" isCollapsed={true} />
+              </button>
+              <button
+                type="button"
+                onClick={onNewChat}
+                className="h-8 w-8 inline-flex items-center justify-center rounded-lg dark:text-claude-darkTextSecondary text-claude-textSecondary hover:bg-claude-surfaceHover dark:hover:bg-claude-darkSurfaceHover transition-colors"
+              >
+                <ComposeIcon className="h-4 w-4" />
+              </button>
+              {updateBadge}
+            </div>
+          )}
+          <h1 className="text-lg font-semibold dark:text-claude-darkText text-claude-text">
+            {i18nService.t('myAgents')}
+          </h1>
+        </div>
+        <WindowTitleBar inline />
+      </div>
+
+      {/* Content */}
+      <div className="flex-1 overflow-y-auto min-h-0 [scrollbar-gutter:stable]">
+        <div className="max-w-3xl mx-auto px-4 py-6">
+          {/* Subtitle */}
+          <p className="text-sm dark:text-claude-darkTextSecondary text-claude-textSecondary mb-6">
+            {i18nService.t('agentsSubtitle')}
+          </p>
+
+          {/* Preset Agents Section */}
+          {(presetAgents.length > 0 || uninstalledPresets.length > 0) && (
+            <div className="mb-8">
+              <h2 className="text-sm font-medium dark:text-claude-darkTextSecondary text-claude-textSecondary mb-3">
+                {i18nService.t('presetAgents')}
+              </h2>
+              <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
+                {/* Installed presets */}
+                {presetAgents.map((agent) => (
+                  <AgentCard
+                    key={agent.id}
+                    icon={agent.icon}
+                    name={agent.name}
+                    description={agent.description}
+                    isActive={agent.id === currentAgentId}
+                    onClick={() => setSettingsAgentId(agent.id)}
+                  />
+                ))}
+                {/* Uninstalled presets */}
+                {uninstalledPresets.map((preset) => (
+                  <UninstalledPresetCard
+                    key={preset.id}
+                    icon={preset.icon}
+                    name={preset.name}
+                    description={preset.description}
+                    isAdding={addingPreset === preset.id}
+                    onAdd={() => handleAddPreset(preset.id)}
+                  />
+                ))}
+              </div>
+            </div>
+          )}
+
+          {/* Custom Agents Section */}
+          <div>
+            <h2 className="text-sm font-medium dark:text-claude-darkTextSecondary text-claude-textSecondary mb-3">
+              {i18nService.t('myCustomAgents')}
+            </h2>
+            <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
+              {customAgents.map((agent) => (
+                <AgentCard
+                  key={agent.id}
+                  icon={agent.icon}
+                  name={agent.name}
+                  description={agent.description}
+                  isActive={agent.id === currentAgentId}
+                  onClick={() => setSettingsAgentId(agent.id)}
+                />
+              ))}
+              {/* Create new agent card */}
+              <button
+                type="button"
+                onClick={() => setIsCreateOpen(true)}
+                className="flex flex-col items-center justify-center gap-2 p-4 rounded-xl border-2 border-dashed dark:border-claude-darkBorder border-claude-border hover:border-claude-accent dark:hover:border-claude-accent hover:bg-claude-accent/5 dark:hover:bg-claude-accent/5 transition-colors min-h-[140px] cursor-pointer"
+              >
+                <div className="w-10 h-10 rounded-full flex items-center justify-center bg-claude-accent/10 dark:bg-claude-accent/20">
+                  <PlusIcon className="h-5 w-5 text-claude-accent" />
+                </div>
+                <span className="text-sm font-medium text-claude-accent">
+                  {i18nService.t('createNewAgent')}
+                </span>
+              </button>
+            </div>
+          </div>
+        </div>
+      </div>
+
+      {/* Modals */}
+      <AgentCreateModal isOpen={isCreateOpen} onClose={() => setIsCreateOpen(false)} />
+      <AgentSettingsPanel
+        agentId={settingsAgentId}
+        onClose={() => setSettingsAgentId(null)}
+        onSwitchAgent={(id) => {
+          setSettingsAgentId(null);
+          handleSwitchAgent(id);
+        }}
+      />
+    </div>
+  );
+};
+
+/* ── Agent Card (installed) ─────────────────────────── */
+
+const AgentCard: React.FC<{
+  icon: string;
+  name: string;
+  description: string;
+  isActive: boolean;
+  onClick: () => void;
+}> = ({ icon, name, description, isActive, onClick }) => (
+  <button
+    type="button"
+    onClick={onClick}
+    className={`flex flex-col items-start gap-2 p-4 rounded-xl border-2 text-left transition-all min-h-[140px] hover:shadow-md dark:hover:shadow-none dark:hover:bg-claude-darkSurfaceHover hover:bg-claude-surfaceHover ${
+      isActive
+        ? 'border-claude-accent bg-claude-accent/5 dark:bg-claude-accent/10'
+        : 'dark:border-claude-darkBorder border-claude-border'
+    }`}
+  >
+    <span className="text-3xl">{icon || '🤖'}</span>
+    <div className="min-w-0 w-full">
+      <div className="text-sm font-semibold dark:text-claude-darkText text-claude-text truncate">
+        {name}
+      </div>
+      {description && (
+        <div className="text-xs dark:text-claude-darkTextSecondary text-claude-textSecondary mt-0.5 line-clamp-2">
+          {description}
+        </div>
+      )}
+    </div>
+  </button>
+);
+
+/* ── Uninstalled Preset Card ─────────────────────────── */
+
+const UninstalledPresetCard: React.FC<{
+  icon: string;
+  name: string;
+  description: string;
+  isAdding: boolean;
+  onAdd: () => void;
+}> = ({ icon, name, description, isAdding, onAdd }) => (
+  <div className="flex flex-col items-start gap-2 p-4 rounded-xl border-2 border-dashed dark:border-claude-darkBorder border-claude-border opacity-60 hover:opacity-80 transition-opacity min-h-[140px]">
+    <span className="text-3xl">{icon || '🤖'}</span>
+    <div className="min-w-0 w-full flex-1">
+      <div className="text-sm font-semibold dark:text-claude-darkText text-claude-text truncate">
+        {name}
+      </div>
+      {description && (
+        <div className="text-xs dark:text-claude-darkTextSecondary text-claude-textSecondary mt-0.5 line-clamp-2">
+          {description}
+        </div>
+      )}
+    </div>
+    <button
+      type="button"
+      onClick={onAdd}
+      disabled={isAdding}
+      className="self-end px-3 py-1 text-xs font-medium rounded-lg bg-claude-accent text-white hover:bg-claude-accent/90 disabled:opacity-50 transition-colors"
+    >
+      {isAdding ? '...' : (i18nService.t('addAgent') || 'Add')}
+    </button>
+  </div>
+);
+
+export default AgentsView;
diff --git a/src/renderer/components/cowork/CoworkSessionDetail.tsx b/src/renderer/components/cowork/CoworkSessionDetail.tsx
--- a/src/renderer/components/cowork/CoworkSessionDetail.tsx
+++ b/src/renderer/components/cowork/CoworkSessionDetail.tsx
@@ -18,13 +18,14 @@ import { FolderIcon } from '@heroicons/react/24/solid';
 import { coworkService } from '../../services/cowork';
 import SidebarToggleIcon from '../icons/SidebarToggleIcon';
 import ComposeIcon from '../icons/ComposeIcon';
+import LazyRenderTurn, { clearHeightCache } from './LazyRenderTurn';
 import PuzzleIcon from '../icons/PuzzleIcon';
 import EllipsisHorizontalIcon from '../icons/EllipsisHorizontalIcon';
 import PencilSquareIcon from '../icons/PencilSquareIcon';
 import TrashIcon from '../icons/TrashIcon';
 import WindowTitleBar from '../window/WindowTitleBar';
 import { getCompactFolderName } from '../../utils/path';
-import { getScheduledReminderDisplayText } from '../../../common/scheduledReminderText';
+import { getScheduledReminderDisplayText } from '../../../scheduled-task/reminderText';
 import DiffView, { extractDiffFromToolInput } from './DiffView';
 
 interface CoworkSessionDetailProps {
@@ -1333,6 +1334,12 @@ const CoworkSessionDetail: React.FC<CoworkSessionDetailProps> = ({
   const scrollContainerRef = useRef<HTMLDivElement>(null);
   const [shouldAutoScroll, setShouldAutoScroll] = useState(true);
 
+  // Clear lazy-render height cache when session changes
+  const sessionId = currentSession?.id;
+  useEffect(() => {
+    clearHeightCache();
+  }, [sessionId]);
+
   // Turn navigation states
   // currentTurnIndex (state) drives UI rendering; currentTurnIndexRef (ref) provides
   // up-to-date value inside callbacks (avoids stale closure). Both must be updated together.
@@ -1938,9 +1945,11 @@ const CoworkSessionDetail: React.FC<CoworkSessionDetailProps> = ({
       const isLastTurn = index === turns.length - 1;
       const showTypingIndicator = isStreaming && isLastTurn && !hasRenderableAssistantContent(turn);
       const showAssistantBlock = turn.assistantItems.length > 0 || showTypingIndicator;
+      // Always render last 3 turns (needed for streaming, auto-scroll, and smooth UX)
+      const alwaysRender = index >= turns.length - 3;
 
       return (
-        <div key={turn.id} data-turn-index={index}>
+        <LazyRenderTurn key={turn.id} turnId={turn.id} alwaysRender={alwaysRender} data-turn-index={index}>
           {turn.userMessage && (
             <div data-export-role="user-message">
               <UserMessageItem message={turn.userMessage} skills={skills} />
@@ -1957,7 +1966,7 @@ const CoworkSessionDetail: React.FC<CoworkSessionDetailProps> = ({
               />
             </div>
           )}
-        </div>
+        </LazyRenderTurn>
       );
     });
   };
diff --git a/src/renderer/components/cowork/CoworkView.tsx b/src/renderer/components/cowork/CoworkView.tsx
--- a/src/renderer/components/cowork/CoworkView.tsx
+++ b/src/renderer/components/cowork/CoworkView.tsx
@@ -53,6 +53,7 @@ const CoworkView: React.FC<CoworkViewProps> = ({ onRequestAppSettings, onShowSki
   const skills = useSelector((state: RootState) => state.skill.skills);
   const quickActions = useSelector((state: RootState) => state.quickAction.actions);
   const selectedActionId = useSelector((state: RootState) => state.quickAction.selectedActionId);
+  const currentAgentId = useSelector((state: RootState) => state.agent.currentAgentId);
 
   const buildApiConfigNotice = (error?: string) => {
     const baseNotice = i18nService.t('coworkModelSettingsRequired');
@@ -204,6 +205,7 @@ const CoworkView: React.FC<CoworkViewProps> = ({ onRequestAppSettings, onShowSki
         systemPrompt: '',
         executionMode: config.executionMode || 'local',
         activeSkillIds: sessionSkillIds,
+        agentId: currentAgentId,
         messages: [
           {
             id: `msg-${now}`,
@@ -229,10 +231,13 @@ const CoworkView: React.FC<CoworkViewProps> = ({ onRequestAppSettings, onShowSki
       dispatch(clearActiveSkills());
       dispatch(clearSelection());
 
-      // Combine skill prompt with system prompt
-      // If no manual skill selected, use auto-routing prompt
+      // Combine skill prompt with system prompt.
+      // OpenClaw loads skills natively via skills.load.extraDirs, so skip the
+      // auto-routing prompt to avoid injecting Claude SDK tool-calling instructions
+      // that confuse non-Claude models (e.g. kimi-k2.5 falls back to text-based
+      // tool calls, producing empty tool names and err=true failures).
       let effectiveSkillPrompt = skillPrompt;
-      if (!skillPrompt) {
+      if (!skillPrompt && !isOpenClawEngine) {
         effectiveSkillPrompt = await skillService.getAutoRoutingPrompt() || undefined;
       }
       const combinedSystemPrompt = [effectiveSkillPrompt, config.systemPrompt]
@@ -246,6 +251,7 @@ const CoworkView: React.FC<CoworkViewProps> = ({ onRequestAppSettings, onShowSki
         cwd: config.workingDirectory || undefined,
         systemPrompt: combinedSystemPrompt,
         activeSkillIds: sessionSkillIds,
+        agentId: currentAgentId,
         imageAttachments,
       });
 
@@ -310,10 +316,10 @@ const CoworkView: React.FC<CoworkViewProps> = ({ onRequestAppSettings, onShowSki
       dispatch(clearActiveSkills());
     }
 
-    // Combine skill prompt with system prompt for continuation
-    // If no manual skill selected, use auto-routing prompt
+    // Combine skill prompt with system prompt for continuation.
+    // Skip auto-routing prompt for OpenClaw — skills are loaded natively.
     let effectiveSkillPrompt = skillPrompt;
-    if (!skillPrompt) {
+    if (!skillPrompt && !isOpenClawEngine) {
       effectiveSkillPrompt = await skillService.getAutoRoutingPrompt() || undefined;
     }
     const combinedSystemPrompt = [effectiveSkillPrompt, config.systemPrompt]
diff --git a/src/renderer/components/cowork/LazyRenderTurn.tsx b/src/renderer/components/cowork/LazyRenderTurn.tsx
new file mode 100644
--- /dev/null
+++ b/src/renderer/components/cowork/LazyRenderTurn.tsx
@@ -0,0 +1,109 @@
+import React, { useRef, useState, useEffect } from 'react';
+
+/**
+ * LazyRenderTurn — Viewport-based lazy rendering wrapper for conversation turns.
+ *
+ * Renders a lightweight placeholder when the turn is far from the viewport,
+ * and renders the actual content when it enters (or is near) the viewport.
+ * Once rendered, keeps a cached height so the placeholder matches the real size.
+ *
+ * This dramatically reduces DOM node count and React reconciliation work
+ * for long conversations (200+ turns).
+ */
+
+interface LazyRenderTurnProps extends React.HTMLAttributes<HTMLDivElement> {
+  /** Unique key for height cache */
+  turnId: string;
+  /** Vertical margin around viewport to pre-render (px) */
+  rootMargin?: number;
+  /** Whether this turn should always be rendered (e.g. last turn during streaming) */
+  alwaysRender?: boolean;
+  children: React.ReactNode;
+}
+
+// Global height cache survives re-renders — keyed by turnId
+const heightCache = new Map<string, number>();
+
+const LazyRenderTurn: React.FC<LazyRenderTurnProps> = ({
+  turnId,
+  rootMargin = 600,
+  alwaysRender = false,
+  children,
+  style,
+  ...restProps
+}) => {
+  const containerRef = useRef<HTMLDivElement>(null);
+  const [isVisible, setIsVisible] = useState(alwaysRender);
+  const hasRenderedRef = useRef(false);
+
+  // Observe intersection
+  useEffect(() => {
+    if (alwaysRender) {
+      setIsVisible(true);
+      return;
+    }
+
+    const el = containerRef.current;
+    if (!el) return;
+
+    const observer = new IntersectionObserver(
+      ([entry]) => {
+        const nowVisible = entry.isIntersecting;
+        setIsVisible(nowVisible);
+        if (nowVisible) {
+          hasRenderedRef.current = true;
+        }
+      },
+      {
+        rootMargin: `${rootMargin}px 0px ${rootMargin}px 0px`,
+      },
+    );
+
+    observer.observe(el);
+    return () => observer.disconnect();
+  }, [alwaysRender, rootMargin]);
+
+  // Cache height when visible content is rendered
+  useEffect(() => {
+    if (!isVisible) return;
+    const el = containerRef.current;
+    if (!el) return;
+
+    const ro = new ResizeObserver(([entry]) => {
+      const h = entry.contentRect.height;
+      if (h > 0) {
+        heightCache.set(turnId, h);
+      }
+    });
+    ro.observe(el);
+    return () => ro.disconnect();
+  }, [isVisible, turnId]);
+
+  const shouldRender = isVisible || alwaysRender;
+  const cachedHeight = heightCache.get(turnId);
+
+  return (
+    <div
+      ref={containerRef}
+      {...restProps}
+      style={{
+        ...style,
+        ...(!shouldRender && cachedHeight
+          ? { height: cachedHeight, minHeight: cachedHeight }
+          : undefined),
+      }}
+    >
+      {shouldRender ? children : (
+        <div
+          style={{ height: cachedHeight || 80 }}
+          className="dark:bg-claude-darkBg bg-claude-bg"
+        />
+      )}
+    </div>
+  );
+};
+
+export default LazyRenderTurn;
+
+/** Clear all cached heights (e.g. when switching sessions) */
+export const clearHeightCache = () => heightCache.clear();
\ No newline at end of file
diff --git a/src/renderer/components/im/IMSettings.tsx b/src/renderer/components/im/IMSettings.tsx
--- a/src/renderer/components/im/IMSettings.tsx
+++ b/src/renderer/components/im/IMSettings.tsx
@@ -1169,6 +1169,7 @@ const IMSettings: React.FC = () => {
           </div>
         </div>
 
+
         {/* DingTalk Settings */}
         {activePlatform === 'dingtalk' && (
           <div className="space-y-3">
diff --git a/src/renderer/components/scheduledTasks/AllRunsHistory.tsx b/src/renderer/components/scheduledTasks/AllRunsHistory.tsx
--- a/src/renderer/components/scheduledTasks/AllRunsHistory.tsx
+++ b/src/renderer/components/scheduledTasks/AllRunsHistory.tsx
@@ -3,10 +3,10 @@ import { useSelector } from 'react-redux';
 import { RootState } from '../../store';
 import { scheduledTaskService } from '../../services/scheduledTask';
 import { i18nService } from '../../services/i18n';
-import type { ScheduledTaskRunWithName } from '../../types/scheduledTask';
+import type { ScheduledTaskRunWithName } from '../../../scheduled-task/types';
 import { ClockIcon } from '@heroicons/react/24/outline';
 import RunSessionModal from './RunSessionModal';
-import { formatDuration } from './utils';
+import { formatDateTime, formatDuration } from './utils';
 
 const statusConfig: Record<string, { label: string; color: string }> = {
   success: { label: 'scheduledTasksStatusSuccess', color: 'text-green-500' },
@@ -86,7 +86,7 @@ const AllRunsHistory: React.FC = () => {
 
             {/* Run time + duration */}
             <div className="text-sm dark:text-claude-darkTextSecondary text-claude-textSecondary truncate">
-              {new Date(run.startedAt).toLocaleString()}
+              {formatDateTime(new Date(run.startedAt))}
               {run.durationMs !== null && (
                 <span className="ml-1.5 text-xs opacity-70">({formatDuration(run.durationMs)})</span>
               )}
diff --git a/src/renderer/components/scheduledTasks/TaskDetail.tsx b/src/renderer/components/scheduledTasks/TaskDetail.tsx
--- a/src/renderer/components/scheduledTasks/TaskDetail.tsx
+++ b/src/renderer/components/scheduledTasks/TaskDetail.tsx
@@ -5,9 +5,10 @@ import { RootState } from '../../store';
 import { setViewMode } from '../../store/slices/scheduledTaskSlice';
 import { scheduledTaskService } from '../../services/scheduledTask';
 import { i18nService } from '../../services/i18n';
-import type { ScheduledTask } from '../../types/scheduledTask';
+import type { ScheduledTask } from '../../../scheduled-task/types';
 import TaskRunHistory from './TaskRunHistory';
 import {
+  formatDateTime,
   formatDeliveryLabel,
   formatDuration,
   formatScheduleLabel,
@@ -33,9 +34,6 @@ const TaskDetail: React.FC<TaskDetailProps> = ({ task, onRequestDelete }) => {
   const statusLabel = i18nService.t(getStatusLabelKey(task.state.lastStatus));
   const statusTone = getStatusTone(task.state.lastStatus);
   const promptText = task.payload.kind === 'systemEvent' ? task.payload.text : task.payload.message;
-  const timeoutText = task.payload.kind === 'agentTurn' && typeof task.payload.timeoutSeconds === 'number'
-    ? `${task.payload.timeoutSeconds}s`
-    : i18nService.t('scheduledTasksNotSet');
 
   const sectionClass = 'rounded-lg border dark:border-claude-darkBorder border-claude-border p-4';
   const sectionTitleClass = 'text-sm font-semibold dark:text-claude-darkText text-claude-text mb-3';
@@ -98,44 +96,6 @@ const TaskDetail: React.FC<TaskDetailProps> = ({ task, onRequestDelete }) => {
             <div className={labelClass}>{i18nService.t('scheduledTasksSchedule')}</div>
             <div className={valueClass}>{formatScheduleLabel(task.schedule)}</div>
           </div>
-          <div>
-            <div className={labelClass}>{i18nService.t('scheduledTasksFormEnabled')}</div>
-            <div className={valueClass}>
-              {task.enabled ? i18nService.t('enabled') : i18nService.t('disabled')}
-            </div>
-          </div>
-          <div>
-            <div className={labelClass}>{i18nService.t('scheduledTasksFormAgentId')}</div>
-            <div className={valueClass}>{task.agentId || i18nService.t('scheduledTasksNotSet')}</div>
-          </div>
-          <div>
-            <div className={labelClass}>{i18nService.t('scheduledTasksFormSessionTarget')}</div>
-            <div className={valueClass}>
-              {task.sessionTarget === 'main'
-                ? i18nService.t('scheduledTasksFormSessionTargetMain')
-                : i18nService.t('scheduledTasksFormSessionTargetIsolated')}
-            </div>
-          </div>
-          <div>
-            <div className={labelClass}>{i18nService.t('scheduledTasksFormWakeMode')}</div>
-            <div className={valueClass}>
-              {task.wakeMode === 'now'
-                ? i18nService.t('scheduledTasksFormWakeModeNow')
-                : i18nService.t('scheduledTasksFormWakeModeNextHeartbeat')}
-            </div>
-          </div>
-          <div>
-            <div className={labelClass}>{i18nService.t('scheduledTasksFormPayloadKind')}</div>
-            <div className={valueClass}>
-              {task.payload.kind === 'systemEvent'
-                ? i18nService.t('scheduledTasksFormPayloadKindSystemEvent')
-                : i18nService.t('scheduledTasksFormPayloadKindAgentTurn')}
-            </div>
-          </div>
-          <div>
-            <div className={labelClass}>{i18nService.t('scheduledTasksFormTimeoutSeconds')}</div>
-            <div className={valueClass}>{timeoutText}</div>
-          </div>
           <div>
             <div className={labelClass}>{i18nService.t('scheduledTasksDetailNotify')}</div>
             <div className={valueClass}>{formatDeliveryLabel(task.delivery)}</div>
@@ -158,7 +118,7 @@ const TaskDetail: React.FC<TaskDetailProps> = ({ task, onRequestDelete }) => {
               {statusLabel}
               {task.state.lastRunAtMs && (
                 <span className="ml-1 text-xs dark:text-claude-darkTextSecondary text-claude-textSecondary">
-                  ({new Date(task.state.lastRunAtMs).toLocaleString()})
+                  ({formatDateTime(new Date(task.state.lastRunAtMs))})
                 </span>
               )}
             </div>
@@ -167,7 +127,7 @@ const TaskDetail: React.FC<TaskDetailProps> = ({ task, onRequestDelete }) => {
             <div className={labelClass}>{i18nService.t('scheduledTasksNextRun')}</div>
             <div className={valueClass}>
               {task.state.nextRunAtMs
-                ? new Date(task.state.nextRunAtMs).toLocaleString()
+                ? formatDateTime(new Date(task.state.nextRunAtMs))
                 : '-'}
             </div>
           </div>
diff --git a/src/renderer/components/scheduledTasks/TaskForm.tsx b/src/renderer/components/scheduledTasks/TaskForm.tsx
--- a/src/renderer/components/scheduledTasks/TaskForm.tsx
+++ b/src/renderer/components/scheduledTasks/TaskForm.tsx
@@ -4,9 +4,10 @@ import { i18nService } from '../../services/i18n';
 import type {
   ScheduledTask,
   ScheduledTaskChannelOption,
-  ScheduledTaskDelivery,
+  ScheduledTaskConversationOption,
   ScheduledTaskInput,
-} from '../../types/scheduledTask';
+} from '../../../scheduled-task/types';
+import { formatScheduleLabel, type PlanType, scheduleToPlanInfo } from './utils';
 
 interface TaskFormProps {
   mode: 'create' | 'edit';
@@ -15,178 +16,134 @@ interface TaskFormProps {
   onSaved: () => void;
 }
 
-type EveryUnit = 'minutes' | 'hours' | 'days';
-type ScheduleKind = 'every' | 'at' | 'cron';
-type DeliveryMode = 'none' | 'announce' | 'webhook';
-
 interface FormState {
   name: string;
   description: string;
-  agentId: string;
-  enabled: boolean;
-  scheduleKind: ScheduleKind;
-  scheduleAt: string;
-  everyAmount: string;
-  everyUnit: EveryUnit;
-  cronExpr: string;
-  cronTz: string;
-  sessionTarget: 'main' | 'isolated';
-  wakeMode: 'now' | 'next-heartbeat';
-  payloadKind: 'systemEvent' | 'agentTurn';
+  planType: PlanType;
+  year: number;
+  month: number;
+  day: number;
+  hour: number;
+  minute: number;
+  second: number;
+  weekday: number;
+  monthDay: number;
   payloadText: string;
-  timeoutSeconds: string;
-  deliveryMode: DeliveryMode;
-  deliveryChannel: string;
-  deliveryTo: string;
+  notifyChannel: string;
+  notifyTo: string;
+}
+
+function nowDefaults() {
+  const now = new Date();
+  return {
+    year: now.getFullYear(),
+    month: now.getMonth() + 1,
+    day: now.getDate(),
+    hour: 9,
+    minute: 0,
+    second: 0,
+  };
 }
 
 const DEFAULT_FORM_STATE: FormState = {
   name: '',
   description: '',
-  agentId: '',
-  enabled: true,
-  scheduleKind: 'every',
-  scheduleAt: '',
-  everyAmount: '30',
-  everyUnit: 'minutes',
-  cronExpr: '0 7 * * *',
-  cronTz: '',
-  sessionTarget: 'isolated',
-  wakeMode: 'now',
-  payloadKind: 'agentTurn',
+  planType: 'daily',
+  ...nowDefaults(),
+  weekday: 1,
+  monthDay: 1,
   payloadText: '',
-  timeoutSeconds: '',
-  deliveryMode: 'announce',
-  deliveryChannel: 'last',
-  deliveryTo: '',
+  notifyChannel: 'none',
+  notifyTo: '',
 };
 
-function toDatetimeLocalValue(isoString: string): string {
-  const date = new Date(isoString);
-  if (!Number.isFinite(date.getTime())) {
-    return '';
-  }
-  const pad = (value: number): string => String(value).padStart(2, '0');
-  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
-}
-
-function parseEverySchedule(everyMs: number): { everyAmount: string; everyUnit: EveryUnit } {
-  if (everyMs % 86_400_000 === 0) {
-    return { everyAmount: String(Math.max(1, everyMs / 86_400_000)), everyUnit: 'days' };
-  }
-  if (everyMs % 3_600_000 === 0) {
-    return { everyAmount: String(Math.max(1, everyMs / 3_600_000)), everyUnit: 'hours' };
-  }
-  return { everyAmount: String(Math.max(1, Math.round(everyMs / 60_000))), everyUnit: 'minutes' };
+const IM_CHANNEL_VALUES = new Set([
+  'dingtalk-connector',
+  'feishu',
+  'telegram',
+  'discord',
+  'qqbot',
+  'wecom',
+  'popo',
+  'nim',
+  'openclaw-weixin',
+  'xiaomifeng',
+]);
+
+function isIMChannel(channel: string): boolean {
+  return IM_CHANNEL_VALUES.has(channel);
 }
 
 function createFormState(task?: ScheduledTask): FormState {
-  if (!task) {
-    return { ...DEFAULT_FORM_STATE };
-  }
+  if (!task) return { ...DEFAULT_FORM_STATE, ...nowDefaults() };
 
-  const nextState: FormState = {
-    ...DEFAULT_FORM_STATE,
+  const planInfo = scheduleToPlanInfo(task.schedule);
+  return {
     name: task.name,
     description: task.description,
-    agentId: task.agentId || '',
-    enabled: task.enabled,
-    sessionTarget: task.sessionTarget,
-    wakeMode: task.wakeMode,
-    payloadKind: task.payload.kind,
+    planType: planInfo.planType,
+    year: planInfo.year,
+    month: planInfo.month,
+    day: planInfo.day,
+    hour: planInfo.hour,
+    minute: planInfo.minute,
+    second: planInfo.second,
+    weekday: planInfo.weekday,
+    monthDay: planInfo.monthDay,
     payloadText: task.payload.kind === 'systemEvent' ? task.payload.text : task.payload.message,
-    timeoutSeconds: task.payload.kind === 'agentTurn' && typeof task.payload.timeoutSeconds === 'number'
-      ? String(task.payload.timeoutSeconds)
-      : '',
-    deliveryMode: task.delivery.mode,
-    deliveryChannel: task.delivery.channel || 'last',
-    deliveryTo: task.delivery.to || '',
+    notifyChannel: task.delivery.channel || 'none',
+    notifyTo: task.delivery.to || '',
   };
-
-  if (task.schedule.kind === 'at') {
-    nextState.scheduleKind = 'at';
-    nextState.scheduleAt = toDatetimeLocalValue(task.schedule.at);
-  } else if (task.schedule.kind === 'every') {
-    nextState.scheduleKind = 'every';
-    const parsedEvery = parseEverySchedule(task.schedule.everyMs);
-    nextState.everyAmount = parsedEvery.everyAmount;
-    nextState.everyUnit = parsedEvery.everyUnit;
-  } else {
-    nextState.scheduleKind = 'cron';
-    nextState.cronExpr = task.schedule.expr;
-    nextState.cronTz = task.schedule.tz || '';
-  }
-
-  return nextState;
-}
-
-function supportsAnnounceDelivery(form: FormState): boolean {
-  return form.sessionTarget === 'isolated' && form.payloadKind === 'agentTurn';
-}
-
-function normalizeDeliveryMode(form: FormState): DeliveryMode {
-  if (form.deliveryMode !== 'announce') {
-    return form.deliveryMode;
-  }
-  return supportsAnnounceDelivery(form) ? 'announce' : 'none';
 }
 
 function buildScheduleInput(form: FormState): ScheduledTaskInput['schedule'] {
-  if (form.scheduleKind === 'at') {
-    return {
-      kind: 'at',
-      at: new Date(form.scheduleAt).toISOString(),
-    };
-  }
-
-  if (form.scheduleKind === 'every') {
-    const amount = Number.parseInt(form.everyAmount, 10);
-    const multiplier = form.everyUnit === 'minutes'
-      ? 60_000
-      : form.everyUnit === 'hours'
-        ? 3_600_000
-        : 86_400_000;
-    return {
-      kind: 'every',
-      everyMs: amount * multiplier,
-    };
+  if (form.planType === 'once') {
+    const date = new Date(form.year, form.month - 1, form.day, form.hour, form.minute, form.second);
+    return { kind: 'at', at: date.toISOString() };
   }
 
-  return {
-    kind: 'cron',
-    expr: form.cronExpr.trim(),
-    ...(form.cronTz.trim() ? { tz: form.cronTz.trim() } : {}),
-  };
-}
+  const min = String(form.minute);
+  const hr = String(form.hour);
 
-function buildDeliveryInput(form: FormState): ScheduledTaskDelivery {
-  const deliveryMode = normalizeDeliveryMode(form);
-  if (deliveryMode === 'none') {
-    return { mode: 'none' };
+  if (form.planType === 'daily') {
+    return { kind: 'cron', expr: `${min} ${hr} * * *` };
   }
 
-  if (deliveryMode === 'webhook') {
-    return {
-      mode: 'webhook',
-      ...(form.deliveryTo.trim() ? { to: form.deliveryTo.trim() } : {}),
-    };
+  if (form.planType === 'weekly') {
+    return { kind: 'cron', expr: `${min} ${hr} * * ${form.weekday}` };
   }
 
-  return {
-    mode: 'announce',
-    channel: form.deliveryChannel.trim() || 'last',
-    ...(form.deliveryTo.trim() ? { to: form.deliveryTo.trim() } : {}),
-  };
+  return { kind: 'cron', expr: `${min} ${hr} ${form.monthDay} * *` };
 }
 
+const WEEKDAY_KEYS = [
+  'scheduledTasksFormWeekSun',
+  'scheduledTasksFormWeekMon',
+  'scheduledTasksFormWeekTue',
+  'scheduledTasksFormWeekWed',
+  'scheduledTasksFormWeekThu',
+  'scheduledTasksFormWeekFri',
+  'scheduledTasksFormWeekSat',
+] as const;
+
 const TaskForm: React.FC<TaskFormProps> = ({ mode, task, onCancel, onSaved }) => {
   const [form, setForm] = useState<FormState>(() => createFormState(task));
-  const [channelOptions, setChannelOptions] = useState<ScheduledTaskChannelOption[]>([
-    { value: 'last', label: 'Last conversation' },
-  ]);
+  const [channelOptions, setChannelOptions] = useState<ScheduledTaskChannelOption[]>(() => {
+    const base: ScheduledTaskChannelOption[] = [];
+    const savedChannel = task?.delivery.channel;
+    if (savedChannel && isIMChannel(savedChannel) && !base.some((o) => o.value === savedChannel)) {
+      base.push({ value: savedChannel, label: savedChannel });
+    }
+    return base;
+  });
+  const [conversations, setConversations] = useState<ScheduledTaskConversationOption[]>([]);
+  const [conversationsLoading, setConversationsLoading] = useState(false);
   const [submitting, setSubmitting] = useState(false);
   const [errors, setErrors] = useState<Record<string, string>>({});
 
+  const isAdvanced = form.planType === 'advanced';
+  const showConversationSelector = isIMChannel(form.notifyChannel);
+
   useEffect(() => {
     setForm(createFormState(task));
   }, [task]);
@@ -211,14 +168,27 @@ const TaskForm: React.FC<TaskFormProps> = ({ mode, task, onCancel, onSaved }) =>
   }, []);
 
   useEffect(() => {
-    const currentChannel = form.deliveryChannel.trim();
-    if (!currentChannel) return;
-    setChannelOptions((current) => (
-      current.some((item) => item.value === currentChannel)
-        ? current
-        : [...current, { value: currentChannel, label: currentChannel }]
-    ));
-  }, [form.deliveryChannel]);
+    if (!showConversationSelector) {
+      setConversations([]);
+      return;
+    }
+
+    let cancelled = false;
+    setConversationsLoading(true);
+    void scheduledTaskService.listChannelConversations(form.notifyChannel).then((result) => {
+      if (cancelled) return;
+      setConversations(result);
+      setConversationsLoading(false);
+
+      if (result.length > 0 && !form.notifyTo) {
+        setForm((current) => ({ ...current, notifyTo: result[0].conversationId }));
+      }
+    });
+
+    return () => {
+      cancelled = true;
+    };
+  }, [form.notifyChannel]);
 
   const updateForm = (patch: Partial<FormState>) => {
     setForm((current) => ({ ...current, ...patch }));
@@ -233,35 +203,16 @@ const TaskForm: React.FC<TaskFormProps> = ({ mode, task, onCancel, onSaved }) =>
     if (!form.payloadText.trim()) {
       nextErrors.payloadText = i18nService.t('scheduledTasksFormValidationPromptRequired');
     }
-    if (form.scheduleKind === 'at') {
-      const runAtMs = Date.parse(form.scheduleAt);
-      if (!Number.isFinite(runAtMs) || runAtMs <= Date.now()) {
+
+    if (form.planType === 'once') {
+      const runAt = new Date(form.year, form.month - 1, form.day, form.hour, form.minute, form.second);
+      if (runAt.getTime() <= Date.now()) {
         nextErrors.schedule = i18nService.t('scheduledTasksFormValidationDatetimeFuture');
       }
     }
-    if (form.scheduleKind === 'every') {
-      const amount = Number.parseInt(form.everyAmount, 10);
-      if (!Number.isFinite(amount) || amount <= 0) {
-        nextErrors.schedule = i18nService.t('scheduledTasksFormValidationIntervalPositive');
-      }
-    }
-    if (form.scheduleKind === 'cron' && !form.cronExpr.trim()) {
-      nextErrors.schedule = i18nService.t('scheduledTasksFormValidationCronRequired');
-    }
-    if (form.sessionTarget === 'main' && form.payloadKind !== 'systemEvent') {
-      nextErrors.payloadKind = i18nService.t('scheduledTasksFormValidationPayloadMismatch');
-    }
-    if (form.sessionTarget === 'isolated' && form.payloadKind !== 'agentTurn') {
-      nextErrors.payloadKind = i18nService.t('scheduledTasksFormValidationPayloadMismatch');
-    }
-    if (form.deliveryMode === 'webhook' && !form.deliveryTo.trim()) {
-      nextErrors.deliveryTo = i18nService.t('scheduledTasksFormValidationWebhookRequired');
-    }
-    if (form.payloadKind === 'agentTurn' && form.timeoutSeconds.trim()) {
-      const timeout = Number.parseInt(form.timeoutSeconds, 10);
-      if (!Number.isFinite(timeout) || timeout < 0) {
-        nextErrors.timeoutSeconds = i18nService.t('scheduledTasksFormValidationTimeout');
-      }
+
+    if (!isAdvanced && (form.hour < 0 || form.hour > 23 || form.minute < 0 || form.minute > 59)) {
+      nextErrors.schedule = i18nService.t('scheduledTasksFormValidationTimeRequired');
     }
 
     setErrors(nextErrors);
@@ -273,23 +224,28 @@ const TaskForm: React.FC<TaskFormProps> = ({ mode, task, onCancel, onSaved }) =>
 
     setSubmitting(true);
     try {
-      const timeoutSeconds = Number.parseInt(form.timeoutSeconds, 10);
+      const schedule = isAdvanced && task
+        ? task.schedule
+        : buildScheduleInput(form);
+
       const input: ScheduledTaskInput = {
         name: form.name.trim(),
-        description: form.description.trim(),
-        agentId: form.agentId.trim() || null,
-        enabled: form.enabled,
-        schedule: buildScheduleInput(form),
-        sessionTarget: form.sessionTarget,
-        wakeMode: form.wakeMode,
-        payload: form.payloadKind === 'systemEvent'
-          ? { kind: 'systemEvent', text: form.payloadText.trim() }
+        description: '',
+        enabled: true,
+        schedule,
+        sessionTarget: 'isolated',
+        wakeMode: 'now',
+        payload: {
+          kind: 'agentTurn',
+          message: form.payloadText.trim(),
+        },
+        delivery: form.notifyChannel === 'none'
+          ? { mode: 'none' }
           : {
-              kind: 'agentTurn',
-              message: form.payloadText.trim(),
-              ...(Number.isFinite(timeoutSeconds) && timeoutSeconds > 0 ? { timeoutSeconds } : {}),
+              mode: 'announce',
+              channel: form.notifyChannel,
+              ...(form.notifyTo ? { to: form.notifyTo } : {}),
             },
-        delivery: buildDeliveryInput(form),
       };
 
       if (mode === 'create') {
@@ -308,181 +264,219 @@ const TaskForm: React.FC<TaskFormProps> = ({ mode, task, onCancel, onSaved }) =>
   const inputClass = 'w-full rounded-lg border dark:border-claude-darkBorder border-claude-border dark:bg-claude-darkSurface bg-white px-3 py-2 text-sm dark:text-claude-darkText text-claude-text focus:outline-none focus:ring-2 focus:ring-claude-accent/50';
   const labelClass = 'block text-sm font-medium dark:text-claude-darkText text-claude-text mb-1';
   const errorClass = 'text-xs text-red-500 mt-1';
-  const normalizedDeliveryMode = normalizeDeliveryMode(form);
 
-  return (
-    <div className="p-4 space-y-4 max-w-3xl mx-auto">
-      <h2 className="text-lg font-semibold dark:text-claude-darkText text-claude-text">
-        {mode === 'create' ? i18nService.t('scheduledTasksFormCreate') : i18nService.t('scheduledTasksFormUpdate')}
-      </h2>
+  const timeValue = `${String(form.hour).padStart(2, '0')}:${String(form.minute).padStart(2, '0')}`;
+  const handleTimeChange = (value: string) => {
+    const [h, m] = value.split(':').map(Number);
+    if (!Number.isNaN(h) && !Number.isNaN(m)) {
+      updateForm({ hour: h, minute: m });
+    }
+  };
 
-      <div className="grid grid-cols-2 gap-4">
-        <div>
-          <label className={labelClass}>{i18nService.t('scheduledTasksFormName')}</label>
-          <input
-            type="text"
-            value={form.name}
-            onChange={(event) => updateForm({ name: event.target.value })}
-            className={inputClass}
-            placeholder={i18nService.t('scheduledTasksFormNamePlaceholder')}
-          />
-          {errors.name && <p className={errorClass}>{errors.name}</p>}
-        </div>
+  const renderScheduleRow = () => {
+    if (isAdvanced) {
+      return (
         <div>
-          <label className={labelClass}>{i18nService.t('scheduledTasksFormAgentId')}</label>
-          <input
-            type="text"
-            value={form.agentId}
-            onChange={(event) => updateForm({ agentId: event.target.value })}
-            className={inputClass}
-            placeholder={i18nService.t('scheduledTasksFormAgentIdPlaceholder')}
-          />
+          <label className={labelClass}>{i18nService.t('scheduledTasksFormScheduleType')}</label>
+          <div className="rounded-lg bg-claude-surfaceHover/30 dark:bg-claude-darkSurfaceHover/30 p-3">
+            <p className="text-sm dark:text-claude-darkTextSecondary text-claude-textSecondary">
+              {formatScheduleLabel(task!.schedule)}
+            </p>
+            <p className="text-xs dark:text-claude-darkTextSecondary text-claude-textSecondary mt-1">
+              {i18nService.t('scheduledTasksAdvancedSchedule')}
+            </p>
+          </div>
         </div>
-      </div>
-
-      <div>
-        <label className={labelClass}>{i18nService.t('scheduledTasksFormDescription')}</label>
-        <textarea
-          value={form.description}
-          onChange={(event) => updateForm({ description: event.target.value })}
-          className={`${inputClass} h-20 resize-none`}
-          placeholder={i18nService.t('scheduledTasksFormDescriptionPlaceholder')}
-        />
-      </div>
+      );
+    }
 
-      <div className="grid grid-cols-2 gap-4">
+    const planSelect = (
+      <select
+        value={form.planType}
+        onChange={(event) => updateForm({ planType: event.target.value as PlanType })}
+        className={`${inputClass} flex-1 min-w-0`}
+      >
+        <option value="once">{i18nService.t('scheduledTasksFormScheduleModeOnce')}</option>
+        <option value="daily">{i18nService.t('scheduledTasksFormScheduleModeDaily')}</option>
+        <option value="weekly">{i18nService.t('scheduledTasksFormScheduleModeWeekly')}</option>
+        <option value="monthly">{i18nService.t('scheduledTasksFormScheduleModeMonthly')}</option>
+      </select>
+    );
+
+    if (form.planType === 'once') {
+      const dateValue = `${form.year}-${String(form.month).padStart(2, '0')}-${String(form.day).padStart(2, '0')}`;
+      const fullTimeValue = `${timeValue}:${String(form.second).padStart(2, '0')}`;
+      return (
         <div>
           <label className={labelClass}>{i18nService.t('scheduledTasksFormScheduleType')}</label>
-          <select
-            value={form.scheduleKind}
-            onChange={(event) => updateForm({ scheduleKind: event.target.value as ScheduleKind })}
-            className={inputClass}
-          >
-            <option value="every">{i18nService.t('scheduledTasksFormScheduleModeEvery')}</option>
-            <option value="at">{i18nService.t('scheduledTasksFormScheduleModeAt')}</option>
-            <option value="cron">{i18nService.t('scheduledTasksFormScheduleModeCron')}</option>
-          </select>
-        </div>
-        <div className="flex items-end">
-          <label className="inline-flex items-center gap-2 text-sm dark:text-claude-darkText text-claude-text">
+          <div className="flex items-center gap-3">
+            {planSelect}
             <input
-              type="checkbox"
-              checked={form.enabled}
-              onChange={(event) => updateForm({ enabled: event.target.checked })}
-              className="rounded border-claude-border dark:border-claude-darkBorder"
+              type="date"
+              value={dateValue}
+              onChange={(e) => {
+                const [y, mo, d] = e.target.value.split('-').map(Number);
+                if (!Number.isNaN(y)) updateForm({ year: y, month: mo, day: d });
+              }}
+              className={`${inputClass} flex-1 min-w-0`}
             />
-            {i18nService.t('scheduledTasksFormEnabled')}
-          </label>
+            <input
+              type="time"
+              step="1"
+              value={fullTimeValue}
+              onChange={(e) => {
+                const parts = e.target.value.split(':').map(Number);
+                const patch: Partial<FormState> = {};
+                if (!Number.isNaN(parts[0])) patch.hour = parts[0];
+                if (!Number.isNaN(parts[1])) patch.minute = parts[1];
+                if (parts.length > 2 && !Number.isNaN(parts[2])) patch.second = parts[2];
+                updateForm(patch);
+              }}
+              className={`${inputClass} flex-1 min-w-0`}
+            />
+          </div>
         </div>
-      </div>
+      );
+    }
 
-      {form.scheduleKind === 'at' && (
+    if (form.planType === 'daily') {
+      return (
         <div>
-          <label className={labelClass}>{i18nService.t('scheduledTasksFormRunAt')}</label>
-          <input
-            type="datetime-local"
-            value={form.scheduleAt}
-            onChange={(event) => updateForm({ scheduleAt: event.target.value })}
-            className={inputClass}
-          />
-        </div>
-      )}
-
-      {form.scheduleKind === 'every' && (
-        <div className="grid grid-cols-2 gap-4">
-          <div>
-            <label className={labelClass}>{i18nService.t('scheduledTasksFormEveryAmount')}</label>
+          <label className={labelClass}>{i18nService.t('scheduledTasksFormScheduleType')}</label>
+          <div className="flex items-center gap-3">
+            {planSelect}
             <input
-              type="number"
-              min="1"
-              value={form.everyAmount}
-              onChange={(event) => updateForm({ everyAmount: event.target.value })}
-              className={inputClass}
+              type="time"
+              value={timeValue}
+              onChange={(e) => handleTimeChange(e.target.value)}
+              className={`${inputClass} flex-1 min-w-0`}
             />
           </div>
-          <div>
-            <label className={labelClass}>{i18nService.t('scheduledTasksFormEveryUnit')}</label>
+        </div>
+      );
+    }
+
+    if (form.planType === 'weekly') {
+      return (
+        <div>
+          <label className={labelClass}>{i18nService.t('scheduledTasksFormScheduleType')}</label>
+          <div className="flex items-center gap-3">
+            {planSelect}
             <select
-              value={form.everyUnit}
-              onChange={(event) => updateForm({ everyUnit: event.target.value as EveryUnit })}
-              className={inputClass}
+              value={form.weekday}
+              onChange={(e) => updateForm({ weekday: Number(e.target.value) })}
+              className={`${inputClass} flex-1 min-w-0`}
             >
-              <option value="minutes">{i18nService.t('scheduledTasksFormIntervalMinutes')}</option>
-              <option value="hours">{i18nService.t('scheduledTasksFormIntervalHours')}</option>
-              <option value="days">{i18nService.t('scheduledTasksFormIntervalDays')}</option>
+              {WEEKDAY_KEYS.map((key, idx) => (
+                <option key={idx} value={idx}>{i18nService.t(key)}</option>
+              ))}
             </select>
-          </div>
-        </div>
-      )}
-
-      {form.scheduleKind === 'cron' && (
-        <div className="grid grid-cols-2 gap-4">
-          <div>
-            <label className={labelClass}>{i18nService.t('scheduledTasksFormCronExpression')}</label>
-            <input
-              type="text"
-              value={form.cronExpr}
-              onChange={(event) => updateForm({ cronExpr: event.target.value })}
-              className={inputClass}
-              placeholder={i18nService.t('scheduledTasksFormCronPlaceholder')}
-            />
-          </div>
-          <div>
-            <label className={labelClass}>{i18nService.t('scheduledTasksFormCronTimezone')}</label>
             <input
-              type="text"
-              value={form.cronTz}
-              onChange={(event) => updateForm({ cronTz: event.target.value })}
-              className={inputClass}
-              placeholder={i18nService.t('scheduledTasksFormCronTimezonePlaceholder')}
+              type="time"
+              value={timeValue}
+              onChange={(e) => handleTimeChange(e.target.value)}
+              className={`${inputClass} flex-1 min-w-0`}
             />
           </div>
         </div>
-      )}
-      {errors.schedule && <p className={errorClass}>{errors.schedule}</p>}
+      );
+    }
 
-      <div className="grid grid-cols-3 gap-4">
-        <div>
-          <label className={labelClass}>{i18nService.t('scheduledTasksFormSessionTarget')}</label>
-          <select
-            value={form.sessionTarget}
-            onChange={(event) => updateForm({ sessionTarget: event.target.value as FormState['sessionTarget'] })}
-            className={inputClass}
-          >
-            <option value="main">{i18nService.t('scheduledTasksFormSessionTargetMain')}</option>
-            <option value="isolated">{i18nService.t('scheduledTasksFormSessionTargetIsolated')}</option>
-          </select>
-        </div>
-        <div>
-          <label className={labelClass}>{i18nService.t('scheduledTasksFormWakeMode')}</label>
+    return (
+      <div>
+        <label className={labelClass}>{i18nService.t('scheduledTasksFormScheduleType')}</label>
+        <div className="flex items-center gap-3">
+          {planSelect}
           <select
-            value={form.wakeMode}
-            onChange={(event) => updateForm({ wakeMode: event.target.value as FormState['wakeMode'] })}
-            className={inputClass}
+            value={form.monthDay}
+            onChange={(e) => updateForm({ monthDay: Number(e.target.value) })}
+            className={`${inputClass} flex-1 min-w-0`}
           >
-            <option value="now">{i18nService.t('scheduledTasksFormWakeModeNow')}</option>
-            <option value="next-heartbeat">{i18nService.t('scheduledTasksFormWakeModeNextHeartbeat')}</option>
+            {Array.from({ length: 31 }, (_, i) => i + 1).map((d) => (
+              <option key={d} value={d}>
+                {d}{i18nService.t('scheduledTasksFormMonthDaySuffix')}
+              </option>
+            ))}
           </select>
+          <input
+            type="time"
+            value={timeValue}
+            onChange={(e) => handleTimeChange(e.target.value)}
+            className={`${inputClass} flex-1 min-w-0`}
+          />
         </div>
-        <div>
-          <label className={labelClass}>{i18nService.t('scheduledTasksFormPayloadKind')}</label>
+      </div>
+    );
+  };
+
+  const renderNotifyRow = () => {
+    return (
+      <div>
+        <label className={labelClass}>{i18nService.t('scheduledTasksFormNotifyChannel')}</label>
+        <div className="flex items-center gap-3">
           <select
-            value={form.payloadKind}
-            onChange={(event) => updateForm({ payloadKind: event.target.value as FormState['payloadKind'] })}
-            className={inputClass}
+            value={form.notifyChannel}
+            onChange={(event) => updateForm({ notifyChannel: event.target.value, notifyTo: '' })}
+            className={`${inputClass} ${showConversationSelector ? 'flex-1 min-w-0' : ''}`}
           >
-            <option value="systemEvent">{i18nService.t('scheduledTasksFormPayloadKindSystemEvent')}</option>
-            <option value="agentTurn">{i18nService.t('scheduledTasksFormPayloadKindAgentTurn')}</option>
+            <option value="none">{i18nService.t('scheduledTasksFormNotifyChannelNone')}</option>
+            {channelOptions.map((channel) => {
+              const unsupported = channel.value === 'openclaw-weixin' || channel.value === 'qqbot';
+              return (
+                <option key={channel.value} value={channel.value} disabled={unsupported}>
+                  {unsupported
+                    ? `${channel.label} (${i18nService.t('scheduledTasksChannelUnsupported')})`
+                    : channel.label}
+                </option>
+              );
+            })}
           </select>
-          {errors.payloadKind && <p className={errorClass}>{errors.payloadKind}</p>}
+          {showConversationSelector && (
+            <select
+              value={form.notifyTo}
+              onChange={(event) => updateForm({ notifyTo: event.target.value })}
+              disabled={conversationsLoading}
+              className={`${inputClass} flex-1 min-w-0`}
+            >
+              {conversationsLoading ? (
+                <option value="">{i18nService.t('scheduledTasksFormNotifyConversationLoading')}</option>
+              ) : conversations.length === 0 ? (
+                <option value="">{i18nService.t('scheduledTasksFormNotifyConversationNone')}</option>
+              ) : (
+                conversations.map((conv) => (
+                  <option key={conv.conversationId} value={conv.conversationId}>
+                    {conv.conversationId}
+                  </option>
+                ))
+              )}
+            </select>
+          )}
         </div>
       </div>
+    );
+  };
+
+  return (
+    <div className="p-4 space-y-4 max-w-3xl mx-auto">
+      <h2 className="text-lg font-semibold dark:text-claude-darkText text-claude-text">
+        {mode === 'create' ? i18nService.t('scheduledTasksFormCreate') : i18nService.t('scheduledTasksFormUpdate')}
+      </h2>
+
+      <div>
+        <label className={labelClass}>{i18nService.t('scheduledTasksFormName')}</label>
+        <input
+          type="text"
+          value={form.name}
+          onChange={(event) => updateForm({ name: event.target.value })}
+          className={inputClass}
+          placeholder={i18nService.t('scheduledTasksFormNamePlaceholder')}
+        />
+        {errors.name && <p className={errorClass}>{errors.name}</p>}
+      </div>
 
       <div>
         <label className={labelClass}>
-          {form.payloadKind === 'systemEvent'
-            ? i18nService.t('scheduledTasksFormPayloadTextSystem')
-            : i18nService.t('scheduledTasksFormPayloadTextAgent')}
+          {i18nService.t('scheduledTasksFormPayloadTextAgent')}
         </label>
         <textarea
           value={form.payloadText}
@@ -493,72 +487,10 @@ const TaskForm: React.FC<TaskFormProps> = ({ mode, task, onCancel, onSaved }) =>
         {errors.payloadText && <p className={errorClass}>{errors.payloadText}</p>}
       </div>
 
-      {form.payloadKind === 'agentTurn' && (
-        <div>
-          <label className={labelClass}>{i18nService.t('scheduledTasksFormTimeoutSeconds')}</label>
-          <input
-            type="number"
-            min="0"
-            value={form.timeoutSeconds}
-            onChange={(event) => updateForm({ timeoutSeconds: event.target.value })}
-            className={inputClass}
-            placeholder={i18nService.t('scheduledTasksFormTimeoutSecondsPlaceholder')}
-          />
-          {errors.timeoutSeconds && <p className={errorClass}>{errors.timeoutSeconds}</p>}
-        </div>
-      )}
-
-      <div className="grid grid-cols-3 gap-4">
-        <div>
-          <label className={labelClass}>{i18nService.t('scheduledTasksFormDeliveryMode')}</label>
-          <select
-            value={normalizedDeliveryMode}
-            onChange={(event) => updateForm({ deliveryMode: event.target.value as DeliveryMode })}
-            className={inputClass}
-          >
-            {supportsAnnounceDelivery(form) && (
-              <option value="announce">{i18nService.t('scheduledTasksFormDeliveryModeAnnounce')}</option>
-            )}
-            <option value="webhook">{i18nService.t('scheduledTasksFormDeliveryModeWebhook')}</option>
-            <option value="none">{i18nService.t('scheduledTasksFormDeliveryModeNone')}</option>
-          </select>
-        </div>
+      {renderScheduleRow()}
+      {errors.schedule && <p className={errorClass}>{errors.schedule}</p>}
 
-        {normalizedDeliveryMode === 'announce' && (
-          <div>
-            <label className={labelClass}>{i18nService.t('scheduledTasksFormDeliveryChannel')}</label>
-            <select
-              value={form.deliveryChannel || 'last'}
-              onChange={(event) => updateForm({ deliveryChannel: event.target.value })}
-              className={inputClass}
-            >
-              {channelOptions.map((channel) => (
-                <option key={channel.value} value={channel.value}>
-                  {channel.label}
-                </option>
-              ))}
-            </select>
-          </div>
-        )}
-
-        {normalizedDeliveryMode !== 'none' && (
-          <div className={normalizedDeliveryMode === 'webhook' ? 'col-span-2' : ''}>
-            <label className={labelClass}>
-              {normalizedDeliveryMode === 'webhook'
-                ? i18nService.t('scheduledTasksFormWebhookUrl')
-                : i18nService.t('scheduledTasksFormDeliveryTo')}
-            </label>
-            <input
-              type="text"
-              value={form.deliveryTo}
-              onChange={(event) => updateForm({ deliveryTo: event.target.value })}
-              className={inputClass}
-              placeholder={i18nService.t('scheduledTasksFormDeliveryToPlaceholder')}
-            />
-            {errors.deliveryTo && <p className={errorClass}>{errors.deliveryTo}</p>}
-          </div>
-        )}
-      </div>
+      {renderNotifyRow()}
 
       <div className="flex items-center justify-end gap-3 pt-2">
         <button
diff --git a/src/renderer/components/scheduledTasks/TaskList.tsx b/src/renderer/components/scheduledTasks/TaskList.tsx
--- a/src/renderer/components/scheduledTasks/TaskList.tsx
+++ b/src/renderer/components/scheduledTasks/TaskList.tsx
@@ -5,7 +5,7 @@ import { RootState } from '../../store';
 import { selectTask, setViewMode } from '../../store/slices/scheduledTaskSlice';
 import { scheduledTaskService } from '../../services/scheduledTask';
 import { i18nService } from '../../services/i18n';
-import type { ScheduledTask } from '../../types/scheduledTask';
+import type { ScheduledTask } from '../../../scheduled-task/types';
 import { formatScheduleLabel, getStatusLabelKey, getStatusTone } from './utils';
 
 interface TaskListItemProps {
diff --git a/src/renderer/components/scheduledTasks/TaskRunHistory.tsx b/src/renderer/components/scheduledTasks/TaskRunHistory.tsx
--- a/src/renderer/components/scheduledTasks/TaskRunHistory.tsx
+++ b/src/renderer/components/scheduledTasks/TaskRunHistory.tsx
@@ -3,9 +3,9 @@ import { useSelector } from 'react-redux';
 import { RootState } from '../../store';
 import { scheduledTaskService } from '../../services/scheduledTask';
 import { i18nService } from '../../services/i18n';
-import type { ScheduledTaskRun } from '../../types/scheduledTask';
+import type { ScheduledTaskRun } from '../../../scheduled-task/types';
 import RunSessionModal from './RunSessionModal';
-import { formatDuration } from './utils';
+import { formatDateTime, formatDuration } from './utils';
 
 interface TaskRunHistoryProps {
   taskId: string;
@@ -46,7 +46,7 @@ const TaskRunHistory: React.FC<TaskRunHistoryProps> = ({ taskId, runs }) => {
                 <span className={`text-sm font-bold ${statusInfo.color}`}>{statusInfo.icon}</span>
                 <div className="min-w-0">
                   <span className="text-sm dark:text-claude-darkText text-claude-text">
-                    {new Date(run.startedAt).toLocaleString()}
+                    {formatDateTime(new Date(run.startedAt))}
                   </span>
                 </div>
               </div>
diff --git a/src/renderer/components/scheduledTasks/utils.ts b/src/renderer/components/scheduledTasks/utils.ts
--- a/src/renderer/components/scheduledTasks/utils.ts
+++ b/src/renderer/components/scheduledTasks/utils.ts
@@ -1,3 +1,4 @@
+import cronstrue from 'cronstrue/i18n';
 import { i18nService } from '../../services/i18n';
 import type {
   ScheduledTask,
@@ -6,7 +7,7 @@ import type {
   Schedule,
   ScheduleCron,
   TaskLastStatus,
-} from '../../types/scheduledTask';
+} from '../../../scheduled-task/types';
 
 const WEEKDAY_KEYS = [
   'scheduledTasksFormWeekSun',
@@ -77,6 +78,11 @@ function formatCronExpr(schedule: ScheduleCron): string {
     return tpl(i18nService.t('scheduledTasksCronEveryNHours'), { n: String(hour.step) });
   }
 
+  // --- Every hour at fixed minute: M * * * * (e.g. 25 * * * *) ---
+  if (min.type === 'value' && hour.type === 'any' && dom.type === 'any' && mon.type === 'any' && dow.type === 'any') {
+    return tpl(i18nService.t('scheduledTasksCronEveryHourAtMinute'), { min: pad2(min.value) });
+  }
+
   // From here we need a fixed time (both minute and hour are concrete values)
   if (min.type !== 'value' || hour.type !== 'value') return fallbackCron(schedule);
   const time = `${pad2(hour.value)}:${pad2(min.value)}`;
@@ -138,14 +144,20 @@ function formatCronExpr(schedule: ScheduleCron): string {
 
 function fallbackCron(schedule: ScheduleCron): string {
   const tzLabel = schedule.tz ? ` (${schedule.tz})` : '';
-  return `Cron · ${schedule.expr}${tzLabel}`;
+  try {
+    const locale = i18nService.getLanguage() === 'zh' ? 'zh_CN' : 'en';
+    const desc = cronstrue.toString(schedule.expr, { locale, use24HourTimeFormat: true });
+    return `${desc}${tzLabel}`;
+  } catch {
+    return `Cron · ${schedule.expr}${tzLabel}`;
+  }
 }
 
 export function formatScheduleLabel(schedule: Schedule): string {
   if (schedule.kind === 'at') {
     const date = new Date(schedule.at);
     if (Number.isFinite(date.getTime())) {
-      return `${i18nService.t('scheduledTasksFormScheduleModeAt')} · ${date.toLocaleString()}`;
+      return `${i18nService.t('scheduledTasksFormScheduleModeAt')} · ${formatDateTime(date)}`;
     }
     return i18nService.t('scheduledTasksFormScheduleModeAt');
   }
@@ -164,6 +176,18 @@ export function formatScheduleLabel(schedule: Schedule): string {
   return formatCronExpr(schedule);
 }
 
+/**
+ * Locale-aware date-time formatting.
+ * Chinese → 24-hour clock; English → 12-hour clock with AM/PM.
+ */
+export function formatDateTime(date: Date): string {
+  const lang = i18nService.getLanguage();
+  if (lang === 'zh') {
+    return date.toLocaleString('zh-CN', { hour12: false });
+  }
+  return date.toLocaleString('en-US');
+}
+
 export function formatDuration(ms: number | null): string {
   if (ms === null) return '-';
   if (ms < 1000) return `${ms}ms`;
@@ -182,10 +206,15 @@ export function formatPayloadLabel(payload: ScheduledTaskPayload): string {
 }
 
 export function formatDeliveryLabel(delivery: ScheduledTaskDelivery): string {
-  if (delivery.mode === 'none') {
+  if (delivery.mode === 'none' && !delivery.channel) {
     return i18nService.t('scheduledTasksFormDeliveryModeNone');
   }
 
+  if (delivery.mode === 'none' && delivery.channel) {
+    const toLabel = delivery.to ? ` -> ${delivery.to}` : '';
+    return `${delivery.channel}${toLabel}`;
+  }
+
   if (delivery.mode === 'webhook') {
     return delivery.to
       ? `${i18nService.t('scheduledTasksFormDeliveryModeWebhook')} · ${delivery.to}`
@@ -197,6 +226,90 @@ export function formatDeliveryLabel(delivery: ScheduledTaskDelivery): string {
   return `${i18nService.t('scheduledTasksFormDeliveryModeAnnounce')} · ${channel}${toLabel}`;
 }
 
+export type PlanType = 'once' | 'daily' | 'weekly' | 'monthly' | 'advanced';
+
+export interface PlanInfo {
+  planType: PlanType;
+  hour: number;
+  minute: number;
+  second: number;
+  weekday: number;
+  monthDay: number;
+  year: number;
+  month: number;
+  day: number;
+}
+
+const DEFAULT_PLAN_INFO: PlanInfo = {
+  planType: 'daily',
+  hour: 9,
+  minute: 0,
+  second: 0,
+  weekday: 1,
+  monthDay: 1,
+  year: new Date().getFullYear(),
+  month: new Date().getMonth() + 1,
+  day: new Date().getDate(),
+};
+
+export function scheduleToPlanInfo(schedule: Schedule): PlanInfo {
+  if (schedule.kind === 'at') {
+    const date = new Date(schedule.at);
+    if (!Number.isFinite(date.getTime())) return { ...DEFAULT_PLAN_INFO, planType: 'once' };
+    return {
+      planType: 'once',
+      year: date.getFullYear(),
+      month: date.getMonth() + 1,
+      day: date.getDate(),
+      hour: date.getHours(),
+      minute: date.getMinutes(),
+      second: date.getSeconds(),
+      weekday: DEFAULT_PLAN_INFO.weekday,
+      monthDay: DEFAULT_PLAN_INFO.monthDay,
+    };
+  }
+
+  if (schedule.kind === 'every') {
+    return { ...DEFAULT_PLAN_INFO, planType: 'advanced' };
+  }
+
+  const parts = schedule.expr.trim().split(/\s+/);
+  if (parts.length !== 5) return { ...DEFAULT_PLAN_INFO, planType: 'advanced' };
+
+  const [minRaw, hourRaw, domRaw, , dowRaw] = parts;
+  const min = parseField(minRaw);
+  const hour = parseField(hourRaw);
+  const dom = parseField(domRaw);
+  const dow = parseField(dowRaw);
+
+  if (!min || !hour || min.type !== 'value' || hour.type !== 'value') {
+    return { ...DEFAULT_PLAN_INFO, planType: 'advanced' };
+  }
+
+  const base: PlanInfo = {
+    ...DEFAULT_PLAN_INFO,
+    hour: hour.value,
+    minute: min.value,
+  };
+
+  // Daily: M H * * *
+  if (dom && dom.type === 'any' && dow && dow.type === 'any') {
+    return { ...base, planType: 'daily' };
+  }
+
+  // Weekly: M H * * DOW (single value)
+  if (dom && dom.type === 'any' && dow && dow.type === 'value' && dow.value >= 0 && dow.value <= 6) {
+    return { ...base, planType: 'weekly', weekday: dow.value };
+  }
+
+  // Monthly: M H DOM * *
+  if (dom && dom.type === 'value' && dow && dow.type === 'any') {
+    return { ...base, planType: 'monthly', monthDay: dom.value };
+  }
+
+  return { ...DEFAULT_PLAN_INFO, planType: 'advanced' };
+}
+
 export function getTaskPromptText(task: ScheduledTask): string {
   return task.payload.kind === 'systemEvent' ? task.payload.text : task.payload.message;
 }
diff --git a/src/renderer/services/agent.ts b/src/renderer/services/agent.ts
new file mode 100644
--- /dev/null
+++ b/src/renderer/services/agent.ts
@@ -0,0 +1,157 @@
+import { store } from '../store';
+import {
+  setAgents,
+  setCurrentAgentId,
+  setLoading,
+  addAgent,
+  updateAgent as updateAgentAction,
+  removeAgent,
+} from '../store/slices/agentSlice';
+import { setActiveSkillIds, clearActiveSkills } from '../store/slices/skillSlice';
+import { clearCurrentSession } from '../store/slices/coworkSlice';
+import type { Agent, PresetAgent } from '../types/agent';
+
+class AgentService {
+  async loadAgents(): Promise<void> {
+    store.dispatch(setLoading(true));
+    try {
+      const agents = await window.electron?.agents?.list();
+      if (agents) {
+        store.dispatch(setAgents(agents.map((a) => ({
+          id: a.id,
+          name: a.name,
+          description: a.description,
+          icon: a.icon,
+          enabled: a.enabled,
+          isDefault: a.isDefault,
+          source: a.source,
+          skillIds: a.skillIds ?? [],
+        }))));
+      }
+    } catch (error) {
+      console.error('Failed to load agents:', error);
+    } finally {
+      store.dispatch(setLoading(false));
+    }
+  }
+
+  async createAgent(request: {
+    name: string;
+    description?: string;
+    systemPrompt?: string;
+    identity?: string;
+    model?: string;
+    icon?: string;
+    skillIds?: string[];
+  }): Promise<Agent | null> {
+    try {
+      const agent = await window.electron?.agents?.create(request);
+      if (agent) {
+        store.dispatch(addAgent({
+          id: agent.id,
+          name: agent.name,
+          description: agent.description,
+          icon: agent.icon,
+          enabled: agent.enabled,
+          isDefault: agent.isDefault,
+          source: agent.source,
+          skillIds: agent.skillIds ?? [],
+        }));
+        return agent;
+      }
+      return null;
+    } catch (error) {
+      console.error('Failed to create agent:', error);
+      return null;
+    }
+  }
+
+  async updateAgent(id: string, updates: {
+    name?: string;
+    description?: string;
+    systemPrompt?: string;
+    identity?: string;
+    model?: string;
+    icon?: string;
+    skillIds?: string[];
+    enabled?: boolean;
+  }): Promise<Agent | null> {
+    try {
+      const agent = await window.electron?.agents?.update(id, updates);
+      if (agent) {
+        store.dispatch(updateAgentAction({
+          id: agent.id,
+          updates: {
+            name: agent.name,
+            description: agent.description,
+            icon: agent.icon,
+            enabled: agent.enabled,
+            skillIds: agent.skillIds ?? [],
+          },
+        }));
+        return agent;
+      }
+      return null;
+    } catch (error) {
+      console.error('Failed to update agent:', error);
+      return null;
+    }
+  }
+
+  async deleteAgent(id: string): Promise<boolean> {
+    try {
+      await window.electron?.agents?.delete(id);
+      store.dispatch(removeAgent(id));
+      return true;
+    } catch (error) {
+      console.error('Failed to delete agent:', error);
+      return false;
+    }
+  }
+
+  async getPresets(): Promise<PresetAgent[]> {
+    try {
+      const presets = await window.electron?.agents?.presets();
+      return presets ?? [];
+    } catch (error) {
+      console.error('Failed to get presets:', error);
+      return [];
+    }
+  }
+
+  async addPreset(presetId: string): Promise<Agent | null> {
+    try {
+      const agent = await window.electron?.agents?.addPreset(presetId);
+      if (agent) {
+        store.dispatch(addAgent({
+          id: agent.id,
+          name: agent.name,
+          description: agent.description,
+          icon: agent.icon,
+          enabled: agent.enabled,
+          isDefault: agent.isDefault,
+          source: agent.source,
+          skillIds: agent.skillIds ?? [],
+        }));
+        return agent;
+      }
+      return null;
+    } catch (error) {
+      console.error('Failed to add preset agent:', error);
+      return null;
+    }
+  }
+
+  switchAgent(agentId: string): void {
+    store.dispatch(setCurrentAgentId(agentId));
+    store.dispatch(clearCurrentSession());
+    const agent = store.getState().agent.agents.find((a) => a.id === agentId);
+    if (agent?.skillIds?.length) {
+      store.dispatch(setActiveSkillIds(agent.skillIds));
+    } else {
+      store.dispatch(clearActiveSkills());
+    }
+  }
+}
+
+export const agentService = new AgentService();
diff --git a/src/renderer/services/cowork.ts b/src/renderer/services/cowork.ts
--- a/src/renderer/services/cowork.ts
+++ b/src/renderer/services/cowork.ts
@@ -193,9 +193,9 @@ class CoworkService {
     this.openClawEngineListenerAttached = false;
   }
 
-  async loadSessions(): Promise<void> {
+  async loadSessions(agentId?: string): Promise<void> {
     const requestId = ++this.latestLoadSessionsRequestId;
-    const result = await window.electron?.cowork?.listSessions();
+    const result = await window.electron?.cowork?.listSessions(agentId);
     if (result?.success && result.sessions) {
       // High-frequency IM traffic can trigger overlapping list refreshes.
       // Ignore stale responses so an older snapshot does not hide newer sessions.
diff --git a/src/renderer/services/i18n.ts b/src/renderer/services/i18n.ts
--- a/src/renderer/services/i18n.ts
+++ b/src/renderer/services/i18n.ts
@@ -426,6 +426,40 @@ const translations: Record<LanguageType, Record<string, string>> = {
     coworkQuestionWizardAnswerRequired: '请选择或输入答案',
     coworkWelcome: '开始协作',
     coworkDescription: '7×24 小时帮你干活的全场景个人助理 Agent',
+
+    // Multi-Agent 管理
+    createAgent: '创建 Agent',
+    myAgents: '我的 Agent',
+    customCreate: '自定义创建',
+    choosePreset: '选择预设',
+    agentSettings: 'Agent 设置',
+    agentName: '名称',
+    agentNamePlaceholder: 'Agent 名称',
+    agentDescription: '描述',
+    agentDescriptionPlaceholder: '简短描述',
+    agentIdentity: '身份',
+    agentIdentityPlaceholder: '身份描述（IDENTITY.md）...',
+    agentSkills: '技能',
+    agentSkillsHint: '选择该 Agent 可使用的技能。不选则使用所有已启用技能。',
+    agentSkillsSearch: '搜索技能...',
+    agentSkillsNone: '点击选择技能',
+    agentsSubtitle: '为您的智能体提供专属人设与技能组合',
+    presetAgents: '预设 Agent',
+    myCustomAgents: '我创建的 Agent',
+    createNewAgent: '新建 Agent',
+    switchToAgent: '使用此 Agent',
+    addAgent: '添加',
+    agentTabBasic: '基础信息',
+    agentTabSkills: '技能',
+    agentTabIM: 'IM 渠道',
+    agentIMConfigured: '已配置',
+    agentIMNotConfigured: '未配置',
+    agentIMNotConfiguredHint: '请先在 设置 > IM 机器人 中配置',
+    agentIMBound: '已绑定',
+    agentIMBindHint: '选择此 Agent 响应的 IM 渠道',
+    noPresetsAvailable: '所有预设已添加',
+    creating: '创建中...',
+
     coworkNewSession: '新会话',
     coworkContinuePlaceholder: '继续对话...',
     coworkRemoteManagedPlaceholder: '该会话由 IM 通道创建，请在对应的 IM 平台操作',
@@ -727,6 +761,9 @@ const translations: Record<LanguageType, Record<string, string>> = {
     popo: 'POPO',
     connected: '已连接',
     disconnected: '未连接',
+    imAgentBinding: '响应 Agent',
+    imAgentBindingDefault: '默认（main）',
+    imAgentBindingHint: '选择用于响应该平台消息的 Agent，不同 Agent 有不同的人设和技能配置。',
     kickedByOtherClient: '账号已在其它地方登录',
     starting: '启动中',
     start: '启动',
@@ -1062,6 +1099,7 @@ const translations: Record<LanguageType, Record<string, string>> = {
     scheduledTasksCronEveryMonth: '每月',
     scheduledTasksCronAtTime: '{schedule} {time}',
     scheduledTasksCronAtMonthDay: '{schedule} {day}日 {time}',
+    scheduledTasksCronEveryHourAtMinute: '每小时第 {min} 分钟',
     scheduledTasksAutoDisabledErrors: '连续错误过多，任务已自动禁用',
     scheduledTasksCreateFailed: '创建任务失败',
     scheduledTasksUpdateFailed: '更新任务失败',
@@ -1100,7 +1138,16 @@ const translations: Record<LanguageType, Record<string, string>> = {
     scheduledTasksFormDeliveryToAuto: '自动检测',
     scheduledTasksFormWebhookUrl: 'Webhook URL',
     scheduledTasksDetailNotify: '通知',
+    scheduledTasksDetailPlan: '计划',
+    scheduledTasksAdvancedSchedule: '高级调度（仅可通过对话修改）',
+    scheduledTasksFormNotifyChannel: '通知渠道',
+    scheduledTasksFormNotifyChannelNone: '不通知',
+    scheduledTasksChannelUnsupported: '暂不支持',
     scheduledTasksSessionKey: '会话键',
+    scheduledTasksFormNotifyConversation: '通知会话',
+    scheduledTasksFormNotifyConversationPlaceholder: '选择通知目标会话',
+    scheduledTasksFormNotifyConversationLoading: '加载会话列表...',
+    scheduledTasksFormNotifyConversationNone: '无可用会话',
     scheduledTasksToggleWarningAtPast: '该任务的执行时间已过，启用后将不会运行',
     scheduledTasksToggleWarningExpired: '该任务已过期，启用后将不会运行',
 
@@ -1531,6 +1578,40 @@ const translations: Record<LanguageType, Record<string, string>> = {
     coworkQuestionWizardAnswerRequired: 'Please select or enter an answer',
     coworkWelcome: 'Start Collaborating',
     coworkDescription: 'A 24/7 personal assistant agent that gets work done for you',
+
+    // Multi-Agent management
+    createAgent: 'Create Agent',
+    myAgents: 'My Agents',
+    customCreate: 'Custom Create',
+    choosePreset: 'Choose Preset',
+    agentSettings: 'Agent Settings',
+    agentName: 'Name',
+    agentNamePlaceholder: 'Agent name',
+    agentDescription: 'Description',
+    agentDescriptionPlaceholder: 'Brief description',
+    agentIdentity: 'Identity',
+    agentIdentityPlaceholder: 'Identity description (IDENTITY.md)...',
+    agentSkills: 'Skills',
+    agentSkillsHint: 'Select skills available to this Agent. Leave empty to use all enabled skills.',
+    agentSkillsSearch: 'Search skills...',
+    agentSkillsNone: 'Click to select skills',
+    agentsSubtitle: 'Custom personas and skill sets for your AI agents',
+    presetAgents: 'Preset Agents',
+    myCustomAgents: 'My Custom Agents',
+    createNewAgent: 'New Agent',
+    switchToAgent: 'Use this Agent',
+    addAgent: 'Add',
+    agentTabBasic: 'Basic Info',
+    agentTabSkills: 'Skills',
+    agentTabIM: 'IM Channels',
+    agentIMConfigured: 'Configured',
+    agentIMNotConfigured: 'Not configured',
+    agentIMNotConfiguredHint: 'Please configure in Settings > IM Bots first',
+    agentIMBound: 'Bound',
+    agentIMBindHint: 'Select IM channels this Agent responds to',
+    noPresetsAvailable: 'All presets have been added',
+    creating: 'Creating...',
+
     coworkNewSession: 'New Session',
     coworkContinuePlaceholder: 'Continue the conversation...',
     coworkRemoteManagedPlaceholder: 'This session was created via IM. Please use the corresponding IM platform.',
@@ -1831,6 +1912,9 @@ const translations: Record<LanguageType, Record<string, string>> = {
     wecom: 'WeCom',    popo: 'POPO',
     connected: 'Connected',
     disconnected: 'Disconnected',
+    imAgentBinding: 'Responding Agent',
+    imAgentBindingDefault: 'Default (main)',
+    imAgentBindingHint: 'Select the Agent that responds to messages on this platform. Different Agents have different personas and skill configurations.',
     kickedByOtherClient: 'Account logged in elsewhere',
     starting: 'Starting',
     start: 'Start',
@@ -2166,6 +2250,7 @@ const translations: Record<LanguageType, Record<string, string>> = {
     scheduledTasksCronEveryMonth: 'Monthly',
     scheduledTasksCronAtTime: '{schedule} at {time}',
     scheduledTasksCronAtMonthDay: '{schedule} on the {day}th at {time}',
+    scheduledTasksCronEveryHourAtMinute: 'Every hour at minute {min}',
     scheduledTasksAutoDisabledErrors: 'Task auto-disabled due to too many consecutive errors',
     scheduledTasksCreateFailed: 'Failed to create task',
     scheduledTasksUpdateFailed: 'Failed to update task',
@@ -2204,7 +2289,16 @@ const translations: Record<LanguageType, Record<string, string>> = {
     scheduledTasksFormDeliveryToAuto: 'Auto-detect',
     scheduledTasksFormWebhookUrl: 'Webhook URL',
     scheduledTasksDetailNotify: 'Notification',
+    scheduledTasksDetailPlan: 'Plan',
+    scheduledTasksAdvancedSchedule: 'Advanced schedule (edit via conversation only)',
+    scheduledTasksFormNotifyChannel: 'Notification Channel',
+    scheduledTasksFormNotifyChannelNone: 'None',
+    scheduledTasksChannelUnsupported: 'Not supported',
     scheduledTasksSessionKey: 'Session Key',
+    scheduledTasksFormNotifyConversation: 'Notify Conversation',
+    scheduledTasksFormNotifyConversationPlaceholder: 'Select target conversation',
+    scheduledTasksFormNotifyConversationLoading: 'Loading conversations...',
+    scheduledTasksFormNotifyConversationNone: 'No conversations available',
     scheduledTasksToggleWarningAtPast: 'The execution time of this task has passed. It will not run after enabling',
     scheduledTasksToggleWarningExpired: 'This task has expired. It will not run after enabling',
 
diff --git a/src/renderer/services/scheduledTask.ts b/src/renderer/services/scheduledTask.ts
--- a/src/renderer/services/scheduledTask.ts
+++ b/src/renderer/services/scheduledTask.ts
@@ -15,10 +15,11 @@ import {
 } from '../store/slices/scheduledTaskSlice';
 import type {
   ScheduledTaskChannelOption,
+  ScheduledTaskConversationOption,
   ScheduledTaskInput,
   ScheduledTaskStatusEvent,
   ScheduledTaskRunEvent,
-} from '../types/scheduledTask';
+} from '../../scheduled-task/types';
 
 class ScheduledTaskService {
   private cleanupFns: (() => void)[] = [];
@@ -228,6 +229,18 @@ class ScheduledTaskService {
       return [];
     }
   }
+
+  async listChannelConversations(channel: string): Promise<ScheduledTaskConversationOption[]> {
+    const api = window.electron?.scheduledTasks;
+    if (!api?.listChannelConversations) return [];
+
+    try {
+      const result = await api.listChannelConversations(channel);
+      return result.success && result.conversations ? result.conversations : [];
+    } catch {
+      return [];
+    }
+  }
 }
 
 export const scheduledTaskService = new ScheduledTaskService();
diff --git a/src/renderer/store/index.ts b/src/renderer/store/index.ts
--- a/src/renderer/store/index.ts
+++ b/src/renderer/store/index.ts
@@ -6,6 +6,7 @@ import mcpReducer from './slices/mcpSlice';
 import imReducer from './slices/imSlice';
 import quickActionReducer from './slices/quickActionSlice';
 import scheduledTaskReducer from './slices/scheduledTaskSlice';
+import agentReducer from './slices/agentSlice';
 import authReducer from './slices/authSlice';
 
 export const store = configureStore({
@@ -17,6 +18,7 @@ export const store = configureStore({
     im: imReducer,
     quickAction: quickActionReducer,
     scheduledTask: scheduledTaskReducer,
+    agent: agentReducer,
     auth: authReducer,
   },
 });
diff --git a/src/renderer/store/slices/agentSlice.ts b/src/renderer/store/slices/agentSlice.ts
new file mode 100644
--- /dev/null
+++ b/src/renderer/store/slices/agentSlice.ts
@@ -0,0 +1,71 @@
+import { createSlice, PayloadAction } from '@reduxjs/toolkit';
+
+interface AgentSummary {
+  id: string;
+  name: string;
+  description: string;
+  icon: string;
+  enabled: boolean;
+  isDefault: boolean;
+  source: 'custom' | 'preset';
+  skillIds: string[];
+}
+
+interface AgentState {
+  agents: AgentSummary[];
+  currentAgentId: string;
+  loading: boolean;
+}
+
+const initialState: AgentState = {
+  agents: [],
+  currentAgentId: 'main',
+  loading: false,
+};
+
+const agentSlice = createSlice({
+  name: 'agent',
+  initialState,
+  reducers: {
+    setAgents(state, action: PayloadAction<AgentSummary[]>) {
+      state.agents = action.payload;
+    },
+
+    setCurrentAgentId(state, action: PayloadAction<string>) {
+      state.currentAgentId = action.payload;
+    },
+
+    setLoading(state, action: PayloadAction<boolean>) {
+      state.loading = action.payload;
+    },
+
+    addAgent(state, action: PayloadAction<AgentSummary>) {
+      state.agents.push(action.payload);
+    },
+
+    updateAgent(state, action: PayloadAction<{ id: string; updates: Partial<AgentSummary> }>) {
+      const index = state.agents.findIndex((a) => a.id === action.payload.id);
+      if (index !== -1) {
+        state.agents[index] = { ...state.agents[index], ...action.payload.updates };
+      }
+    },
+
+    removeAgent(state, action: PayloadAction<string>) {
+      state.agents = state.agents.filter((a) => a.id !== action.payload);
+      if (state.currentAgentId === action.payload) {
+        state.currentAgentId = 'main';
+      }
+    },
+  },
+});
+
+export const {
+  setAgents,
+  setCurrentAgentId,
+  setLoading,
+  addAgent,
+  updateAgent,
+  removeAgent,
+} = agentSlice.actions;
+
+export default agentSlice.reducer;
diff --git a/src/renderer/store/slices/modelSlice.ts b/src/renderer/store/slices/modelSlice.ts
--- a/src/renderer/store/slices/modelSlice.ts
+++ b/src/renderer/store/slices/modelSlice.ts
@@ -97,9 +97,12 @@ const modelSlice = createSlice({
       const userModels = state.availableModels.filter(m => !m.isServerModel);
       state.availableModels = [...action.payload, ...userModels];
       availableModels = state.availableModels;
-      // 如果当前选中模型不在列表中，切换到第一个
-      if (!state.availableModels.find(m => isSameModelIdentity(m, state.selectedModel))) {
-        if (state.availableModels.length > 0) {
+      // 同步选中模型信息（如 supportsImage 等属性可能随服务端更新）
+      if (state.availableModels.length > 0) {
+        const matchedModel = state.availableModels.find(m => isSameModelIdentity(m, state.selectedModel));
+        if (matchedModel) {
+          state.selectedModel = matchedModel;
+        } else {
           state.selectedModel = state.availableModels[0];
         }
       }
diff --git a/src/renderer/store/slices/scheduledTaskSlice.ts b/src/renderer/store/slices/scheduledTaskSlice.ts
--- a/src/renderer/store/slices/scheduledTaskSlice.ts
+++ b/src/renderer/store/slices/scheduledTaskSlice.ts
@@ -5,7 +5,7 @@ import type {
   ScheduledTaskRunWithName,
   TaskState,
   ScheduledTaskViewMode,
-} from '../../types/scheduledTask';
+} from '../../../scheduled-task/types';
 
 interface ScheduledTaskState {
   tasks: ScheduledTask[];
diff --git a/src/renderer/types/agent.ts b/src/renderer/types/agent.ts
new file mode 100644
--- /dev/null
+++ b/src/renderer/types/agent.ts
@@ -0,0 +1,52 @@
+export type AgentSource = 'custom' | 'preset';
+
+export interface Agent {
+  id: string;
+  name: string;
+  description: string;
+  systemPrompt: string;
+  identity: string;
+  model: string;
+  icon: string;
+  skillIds: string[];
+  enabled: boolean;
+  isDefault: boolean;
+  source: AgentSource;
+  presetId: string;
+  createdAt: number;
+  updatedAt: number;
+}
+
+export interface PresetAgent {
+  id: string;
+  name: string;
+  icon: string;
+  description: string;
+  systemPrompt: string;
+  skillIds: string[];
+  installed: boolean;
+}
+
+export interface CreateAgentRequest {
+  id?: string;
+  name: string;
+  description?: string;
+  systemPrompt?: string;
+  identity?: string;
+  model?: string;
+  icon?: string;
+  skillIds?: string[];
+  source?: string;
+  presetId?: string;
+}
+
+export interface UpdateAgentRequest {
+  name?: string;
+  description?: string;
+  systemPrompt?: string;
+  identity?: string;
+  model?: string;
+  icon?: string;
+  skillIds?: string[];
+  enabled?: boolean;
+}
diff --git a/src/renderer/types/cowork.ts b/src/renderer/types/cowork.ts
--- a/src/renderer/types/cowork.ts
+++ b/src/renderer/types/cowork.ts
@@ -50,6 +50,7 @@ export interface CoworkSession {
   systemPrompt: string;
   executionMode: CoworkExecutionMode;
   activeSkillIds: string[];
+  agentId: string;
   messages: CoworkMessage[];
   createdAt: number;
   updatedAt: number;
@@ -152,6 +153,7 @@ export interface CoworkSessionSummary {
   title: string;
   status: CoworkSessionStatus;
   pinned: boolean;
+  agentId?: string;
   createdAt: number;
   updatedAt: number;
 }
@@ -163,6 +165,7 @@ export interface CoworkStartOptions {
   systemPrompt?: string;
   title?: string;
   activeSkillIds?: string[];
+  agentId?: string;
   imageAttachments?: CoworkImageAttachment[];
 }
 
diff --git a/src/renderer/types/electron.d.ts b/src/renderer/types/electron.d.ts
--- a/src/renderer/types/electron.d.ts
+++ b/src/renderer/types/electron.d.ts
@@ -25,6 +25,7 @@ interface CoworkSession {
   systemPrompt: string;
   executionMode: 'auto' | 'local' | 'sandbox';
   activeSkillIds: string[];
+  agentId: string;
   messages: CoworkMessage[];
   createdAt: number;
   updatedAt: number;
@@ -43,6 +44,7 @@ interface CoworkSessionSummary {
   title: string;
   status: 'idle' | 'running' | 'completed' | 'error';
   pinned: boolean;
+  agentId?: string;
   createdAt: number;
   updatedAt: number;
 }
@@ -214,6 +216,8 @@ interface McpMarketplaceData {
   servers: McpMarketplaceServer[];
 }
 
+import type { Agent, PresetAgent } from './agent';
+
 interface CreditItem {
   type: 'subscription' | 'boost' | 'free';
   label: string;
@@ -263,6 +267,15 @@ interface IElectronAPI {
     fetchMarketplace: () => Promise<{ success: boolean; data?: McpMarketplaceData; error?: string }>;
     refreshBridge: () => Promise<{ success: boolean; tools: number; error?: string }>;
   };
+  agents: {
+    list: () => Promise<Agent[]>;
+    get: (id: string) => Promise<Agent | null>;
+    create: (request: { id?: string; name: string; description?: string; systemPrompt?: string; identity?: string; model?: string; icon?: string; skillIds?: string[]; source?: string; presetId?: string }) => Promise<Agent>;
+    update: (id: string, updates: { name?: string; description?: string; systemPrompt?: string; identity?: string; model?: string; icon?: string; skillIds?: string[]; enabled?: boolean }) => Promise<Agent>;
+    delete: (id: string) => Promise<void>;
+    presets: () => Promise<PresetAgent[]>;
+    addPreset: (presetId: string) => Promise<Agent>;
+  };
   api: {
     fetch: (options: {
       url: string;
@@ -310,7 +323,7 @@ interface IElectronAPI {
     onStateChanged: (callback: (state: WindowState) => void) => () => void;
   };
   cowork: {
-    startSession: (options: { prompt: string; cwd?: string; systemPrompt?: string; title?: string; activeSkillIds?: string[]; imageAttachments?: Array<{ name: string; mimeType: string; base64Data: string }> }) => Promise<{ success: boolean; session?: CoworkSession; error?: string; code?: string; engineStatus?: OpenClawEngineStatus }>;
+    startSession: (options: { prompt: string; cwd?: string; systemPrompt?: string; title?: string; activeSkillIds?: string[]; agentId?: string; imageAttachments?: Array<{ name: string; mimeType: string; base64Data: string }> }) => Promise<{ success: boolean; session?: CoworkSession; error?: string; code?: string; engineStatus?: OpenClawEngineStatus }>;
     continueSession: (options: { sessionId: string; prompt: string; systemPrompt?: string; activeSkillIds?: string[]; imageAttachments?: Array<{ name: string; mimeType: string; base64Data: string }> }) => Promise<{ success: boolean; session?: CoworkSession; error?: string; code?: string; engineStatus?: OpenClawEngineStatus }>;
     stopSession: (sessionId: string) => Promise<{ success: boolean; error?: string }>;
     deleteSession: (sessionId: string) => Promise<{ success: boolean; error?: string }>;
@@ -319,7 +332,7 @@ interface IElectronAPI {
     renameSession: (options: { sessionId: string; title: string }) => Promise<{ success: boolean; error?: string }>;
     getSession: (sessionId: string) => Promise<{ success: boolean; session?: CoworkSession; error?: string }>;
     remoteManaged: (sessionId: string) => Promise<{ success: boolean; remoteManaged: boolean; error?: string }>;
-    listSessions: () => Promise<{ success: boolean; sessions?: CoworkSessionSummary[]; error?: string }>;
+    listSessions: (agentId?: string) => Promise<{ success: boolean; sessions?: CoworkSessionSummary[]; error?: string }>;
     exportResultImage: (options: {
       rect: { x: number; y: number; width: number; height: number };
       defaultFileName?: string;
@@ -425,29 +438,34 @@ interface IElectronAPI {
     onMessageReceived: (callback: (message: IMMessage) => void) => () => void;
   };
   scheduledTasks: {
-    list: () => Promise<{ success: boolean; tasks?: import('./scheduledTask').ScheduledTask[]; error?: string }>;
-    get: (id: string) => Promise<{ success: boolean; task?: import('./scheduledTask').ScheduledTask; error?: string }>;
-    create: (input: import('./scheduledTask').ScheduledTaskInput) => Promise<{ success: boolean; task?: import('./scheduledTask').ScheduledTask; error?: string }>;
-    update: (id: string, input: Partial<import('./scheduledTask').ScheduledTaskInput>) => Promise<{ success: boolean; task?: import('./scheduledTask').ScheduledTask; error?: string }>;
+    list: () => Promise<{ success: boolean; tasks?: import('../../scheduled-task/types').ScheduledTask[]; error?: string }>;
+    get: (id: string) => Promise<{ success: boolean; task?: import('../../scheduled-task/types').ScheduledTask; error?: string }>;
+    create: (input: import('../../scheduled-task/types').ScheduledTaskInput) => Promise<{ success: boolean; task?: import('../../scheduled-task/types').ScheduledTask; error?: string }>;
+    update: (id: string, input: Partial<import('../../scheduled-task/types').ScheduledTaskInput>) => Promise<{ success: boolean; task?: import('../../scheduled-task/types').ScheduledTask; error?: string }>;
     delete: (id: string) => Promise<{ success: boolean; error?: string }>;
-    toggle: (id: string, enabled: boolean) => Promise<{ success: boolean; task?: import('./scheduledTask').ScheduledTask; warning?: string; error?: string }>;
+    toggle: (id: string, enabled: boolean) => Promise<{ success: boolean; task?: import('../../scheduled-task/types').ScheduledTask; warning?: string; error?: string }>;
     runManually: (id: string) => Promise<{ success: boolean; error?: string }>;
     stop: (id: string) => Promise<{ success: boolean; error?: string }>;
-    listRuns: (taskId: string, limit?: number, offset?: number) => Promise<{ success: boolean; runs?: import('./scheduledTask').ScheduledTaskRun[]; error?: string }>;
+    listRuns: (taskId: string, limit?: number, offset?: number) => Promise<{ success: boolean; runs?: import('../../scheduled-task/types').ScheduledTaskRun[]; error?: string }>;
     countRuns: (taskId: string) => Promise<{ success: boolean; count?: number; error?: string }>;
-    listAllRuns: (limit?: number, offset?: number) => Promise<{ success: boolean; runs?: import('./scheduledTask').ScheduledTaskRunWithName[]; error?: string }>;
+    listAllRuns: (limit?: number, offset?: number) => Promise<{ success: boolean; runs?: import('../../scheduled-task/types').ScheduledTaskRunWithName[]; error?: string }>;
     resolveSession: (sessionKey: string) => Promise<{
       success: boolean;
       session?: import('./cowork').CoworkSession | null;
       error?: string;
     }>;
     listChannels: () => Promise<{
       success: boolean;
-      channels?: import('./scheduledTask').ScheduledTaskChannelOption[];
+      channels?: import('../../scheduled-task/types').ScheduledTaskChannelOption[];
+      error?: string;
+    }>;
+    listChannelConversations?: (channel: string) => Promise<{
+      success: boolean;
+      conversations?: import('../../scheduled-task/types').ScheduledTaskConversationOption[];
       error?: string;
     }>;
-    onStatusUpdate: (callback: (data: import('./scheduledTask').ScheduledTaskStatusEvent) => void) => () => void;
-    onRunUpdate: (callback: (data: import('./scheduledTask').ScheduledTaskRunEvent) => void) => () => void;
+    onStatusUpdate: (callback: (data: import('../../scheduled-task/types').ScheduledTaskStatusEvent) => void) => () => void;
+    onRunUpdate: (callback: (data: import('../../scheduled-task/types').ScheduledTaskRunEvent) => void) => () => void;
     onRefresh: (callback: () => void) => () => void;
   };
   permissions: {
diff --git a/src/renderer/types/im.ts b/src/renderer/types/im.ts
--- a/src/renderer/types/im.ts
+++ b/src/renderer/types/im.ts
@@ -319,6 +319,8 @@ export interface IMGatewayConfig {
 export interface IMSettings {
   systemPrompt?: string;
   skillsEnabled: boolean;
+  /** Per-platform agent binding. Key = platform name, value = agent ID. Absent or 'main' = default. */
+  platformAgentBindings?: Record<string, string>;
 }
 
 export interface IMGatewayStatus {
diff --git a/src/scheduled-task/constants.ts b/src/scheduled-task/constants.ts
new file mode 100644
--- /dev/null
+++ b/src/scheduled-task/constants.ts
@@ -0,0 +1,127 @@
+/**
+ * Centralized constants for the scheduled-task module.
+ *
+ * Every discriminated-union kind value, delivery mode, session target, wake mode,
+ * status code, IPC channel name, and magic string lives here as an `as const`
+ * object.  Types are derived from these objects so that values and types share
+ * a single source of truth.
+ *
+ * Usage:
+ *   import { ScheduleKind, SessionTarget } from './constants';
+ *   const s: SessionTarget = SessionTarget.Main;
+ */
+
+// ─── Schedule Kind ──────────────────────────────────────────────────────────
+export const ScheduleKind = {
+  At: 'at',
+  Every: 'every',
+  Cron: 'cron',
+} as const;
+export type ScheduleKind = typeof ScheduleKind[keyof typeof ScheduleKind];
+
+// ─── Payload Kind ───────────────────────────────────────────────────────────
+export const PayloadKind = {
+  AgentTurn: 'agentTurn',
+  SystemEvent: 'systemEvent',
+} as const;
+export type PayloadKind = typeof PayloadKind[keyof typeof PayloadKind];
+
+// ─── Delivery Mode ──────────────────────────────────────────────────────────
+export const DeliveryMode = {
+  None: 'none',
+  Announce: 'announce',
+  Webhook: 'webhook',
+} as const;
+export type DeliveryMode = typeof DeliveryMode[keyof typeof DeliveryMode];
+
+// ─── Delivery Channel (magic values) ────────────────────────────────────────
+export const DeliveryChannel = {
+  Last: 'last',
+} as const;
+
+// ─── Session Target ─────────────────────────────────────────────────────────
+export const SessionTarget = {
+  Main: 'main',
+  Isolated: 'isolated',
+} as const;
+export type SessionTarget = typeof SessionTarget[keyof typeof SessionTarget];
+
+// ─── Wake Mode ──────────────────────────────────────────────────────────────
+export const WakeMode = {
+  Now: 'now',
+  NextHeartbeat: 'next-heartbeat',
+} as const;
+export type WakeMode = typeof WakeMode[keyof typeof WakeMode];
+
+// ─── Task Origin Kind ───────────────────────────────────────────────────────
+export const OriginKind = {
+  Legacy: 'legacy',
+  IM: 'im',
+  Cowork: 'cowork',
+  Manual: 'manual',
+} as const;
+export type OriginKind = typeof OriginKind[keyof typeof OriginKind];
+
+// ─── Execution Binding Kind ─────────────────────────────────────────────────
+export const BindingKind = {
+  NewSession: 'new_session',
+  UISession: 'ui_session',
+  IMSession: 'im_session',
+  SessionKey: 'session_key',
+} as const;
+export type BindingKind = typeof BindingKind[keyof typeof BindingKind];
+
+// ─── Task / Run Status ──────────────────────────────────────────────────────
+export const TaskStatus = {
+  Success: 'success',
+  Error: 'error',
+  Skipped: 'skipped',
+  Running: 'running',
+} as const;
+export type TaskStatus = typeof TaskStatus[keyof typeof TaskStatus];
+
+// ─── Gateway Status (OpenClaw wire format) ────────────────────────────────���─
+export const GatewayStatus = {
+  Ok: 'ok',
+  Error: 'error',
+  Skipped: 'skipped',
+} as const;
+export type GatewayStatus = typeof GatewayStatus[keyof typeof GatewayStatus];
+
+// ─── Default Agent ID ───────────────────────────────────────────────────────
+export const DefaultAgentId = 'main' as const;
+
+// ─── Policy Run-Behavior Descriptions ───────────────────────────────────────
+export const RunBehavior = {
+  newSession: 'Creates a new session on each trigger',
+  uiSession: 'Runs within the associated UI session',
+  imSession: (platform: string) => `Triggers and delivers results via ${platform}`,
+  sessionKey: 'Runs with explicit OpenClaw session key',
+} as const;
+
+// ─── IPC Channels ───────────────────────────────────────────────────────────
+export const IpcChannel = {
+  List: 'scheduledTask:list',
+  Get: 'scheduledTask:get',
+  Create: 'scheduledTask:create',
+  Update: 'scheduledTask:update',
+  Delete: 'scheduledTask:delete',
+  Toggle: 'scheduledTask:toggle',
+  RunManually: 'scheduledTask:runManually',
+  Stop: 'scheduledTask:stop',
+  ListRuns: 'scheduledTask:listRuns',
+  CountRuns: 'scheduledTask:countRuns',
+  ListAllRuns: 'scheduledTask:listAllRuns',
+  ResolveSession: 'scheduledTask:resolveSession',
+  ListChannels: 'scheduledTask:listChannels',
+  ListChannelConversations: 'scheduledTask:listChannelConversations',
+  StatusUpdate: 'scheduledTask:statusUpdate',
+  RunUpdate: 'scheduledTask:runUpdate',
+  Refresh: 'scheduledTask:refresh',
+} as const;
+
+// ─── Migration Keys ─────────────────────────────────────────────────────────
+export const MigrationKey = {
+  TasksToOpenclaw: 'scheduled_tasks_migrated_to_openclaw_v1',
+  RunsToOpenclaw: 'scheduled_task_runs_migrated_to_openclaw_v1',
+} as const;
diff --git a/src/main/libs/cronJobService.ts b/src/scheduled-task/cronJobService.ts
rename from src/main/libs/cronJobService.ts
rename to src/scheduled-task/cronJobService.ts
--- a/src/main/libs/cronJobService.ts
+++ b/src/scheduled-task/cronJobService.ts
@@ -8,7 +8,24 @@ import type {
   ScheduledTaskRun,
   ScheduledTaskRunWithName,
   TaskState,
-} from '../../renderer/types/scheduledTask';
+} from './types';
+import { parseChannelSessionKey, CHANNEL_PLATFORM_MAP, PLATFORM_TO_CHANNEL_MAP } from '../main/libs/openclawChannelSessionSync';
+import {
+  ScheduleKind,
+  PayloadKind,
+  DeliveryMode,
+  SessionTarget,
+  WakeMode,
+  TaskStatus,
+  GatewayStatus,
+  IpcChannel,
+} from './constants';
+import type {
+  SessionTarget as SessionTargetType,
+  WakeMode as WakeModeType,
+  DeliveryMode as DeliveryModeType,
+  GatewayStatus as GatewayStatusType,
+} from './constants';
 
 type GatewayClientLike = {
   request: <T = Record<string, unknown>>(
@@ -52,7 +69,7 @@ type GatewayPayload =
     };
 
 interface GatewayDelivery {
-  mode: 'none' | 'announce' | 'webhook';
+  mode: DeliveryModeType;
   channel?: string;
   to?: string;
   accountId?: string;
@@ -63,8 +80,8 @@ interface GatewayJobState {
   nextRunAtMs?: number;
   runningAtMs?: number;
   lastRunAtMs?: number;
-  lastRunStatus?: 'ok' | 'error' | 'skipped';
-  lastStatus?: 'ok' | 'error' | 'skipped';
+  lastRunStatus?: GatewayStatusType;
+  lastStatus?: GatewayStatusType;
   lastError?: string;
   lastDurationMs?: number;
   consecutiveErrors?: number;
@@ -76,8 +93,8 @@ interface GatewayJob {
   description?: string;
   enabled: boolean;
   schedule: GatewaySchedule;
-  sessionTarget: 'main' | 'isolated';
-  wakeMode: 'now' | 'next-heartbeat';
+  sessionTarget: SessionTargetType;
+  wakeMode: WakeModeType;
   payload: GatewayPayload;
   delivery?: GatewayDelivery;
   agentId?: string | null;
@@ -91,7 +108,7 @@ interface GatewayRunLogEntry {
   ts: number;
   jobId: string;
   action?: string;
-  status?: 'ok' | 'error' | 'skipped';
+  status?: GatewayStatusType;
   error?: string;
   sessionId?: string;
   sessionKey?: string;
@@ -107,27 +124,27 @@ interface CronJobServiceDeps {
 }
 
 function mapGatewayResultStatus(
-  status?: 'ok' | 'error' | 'skipped',
+  status?: GatewayStatusType,
 ): 'success' | 'error' | 'skipped' | null {
-  if (status === 'ok') return 'success';
-  if (status === 'error') return 'error';
-  if (status === 'skipped') return 'skipped';
+  if (status === GatewayStatus.Ok) return TaskStatus.Success;
+  if (status === GatewayStatus.Error) return TaskStatus.Error;
+  if (status === GatewayStatus.Skipped) return TaskStatus.Skipped;
   return null;
 }
 
 export function mapGatewaySchedule(schedule: GatewaySchedule): Schedule {
   switch (schedule.kind) {
-    case 'at':
-      return { kind: 'at', at: schedule.at };
-    case 'every':
+    case ScheduleKind.At:
+      return { kind: ScheduleKind.At, at: schedule.at };
+    case ScheduleKind.Every:
       return {
-        kind: 'every',
+        kind: ScheduleKind.Every,
         everyMs: schedule.everyMs,
         ...(typeof schedule.anchorMs === 'number' ? { anchorMs: schedule.anchorMs } : {}),
       };
-    case 'cron':
+    case ScheduleKind.Cron:
       return {
-        kind: 'cron',
+        kind: ScheduleKind.Cron,
         expr: schedule.expr,
         ...(schedule.tz ? { tz: schedule.tz } : {}),
         ...(typeof schedule.staggerMs === 'number' ? { staggerMs: schedule.staggerMs } : {}),
@@ -137,17 +154,17 @@ export function mapGatewaySchedule(schedule: GatewaySchedule): Schedule {
 
 function toGatewaySchedule(schedule: Schedule): GatewaySchedule {
   switch (schedule.kind) {
-    case 'at':
-      return { kind: 'at', at: schedule.at };
-    case 'every':
+    case ScheduleKind.At:
+      return { kind: ScheduleKind.At, at: schedule.at };
+    case ScheduleKind.Every:
       return {
-        kind: 'every',
+        kind: ScheduleKind.Every,
         everyMs: schedule.everyMs,
         ...(typeof schedule.anchorMs === 'number' ? { anchorMs: schedule.anchorMs } : {}),
       };
-    case 'cron':
+    case ScheduleKind.Cron:
       return {
-        kind: 'cron',
+        kind: ScheduleKind.Cron,
         expr: schedule.expr,
         ...(schedule.tz ? { tz: schedule.tz } : {}),
         ...(typeof schedule.staggerMs === 'number' ? { staggerMs: schedule.staggerMs } : {}),
@@ -156,15 +173,15 @@ function toGatewaySchedule(schedule: Schedule): GatewaySchedule {
 }
 
 function toGatewayPayload(payload: ScheduledTaskPayload): GatewayPayload {
-  if (payload.kind === 'systemEvent') {
+  if (payload.kind === PayloadKind.SystemEvent) {
     return {
-      kind: 'systemEvent',
+      kind: PayloadKind.SystemEvent,
       text: payload.text,
     };
   }
 
   return {
-    kind: 'agentTurn',
+    kind: PayloadKind.AgentTurn,
     message: payload.message,
     ...(typeof payload.timeoutSeconds === 'number'
       ? { timeoutSeconds: payload.timeoutSeconds }
@@ -173,24 +190,48 @@ function toGatewayPayload(payload: ScheduledTaskPayload): GatewayPayload {
 }
 
 function toGatewayDelivery(delivery?: ScheduledTaskDelivery): GatewayDelivery | undefined {
-  if (!delivery || delivery.mode === 'none') {
-    return delivery?.mode === 'none' ? { mode: 'none' } : undefined;
+  console.log('[CronJobService][toGatewayDelivery] input delivery:', JSON.stringify(delivery, null, 2));
+  if (!delivery) {
+    console.log('[CronJobService][toGatewayDelivery] no delivery, returning undefined');
+    return undefined;
+  }
+  if (delivery.mode === DeliveryMode.None) {
+    // Preserve channel/to even with mode='none' so IM notification target round-trips
+    // through the gateway for the edit form to display.
+    const result: GatewayDelivery = {
+      mode: DeliveryMode.None,
+      ...(delivery.channel ? { channel: delivery.channel } : {}),
+      ...(delivery.to ? { to: delivery.to } : {}),
+    } as GatewayDelivery;
+    console.log('[CronJobService][toGatewayDelivery] mode=none with preserved channel/to:', JSON.stringify(result));
+    return result;
   }
 
-  return {
+  // Translate logical UI channel names to OpenClaw channel names.
+  // e.g. 'popo' (UI/config key) → 'moltbot-popo' (OpenClaw plugin name).
+  const openclawChannel = delivery.channel
+    ? (() => {
+        const platform = CHANNEL_PLATFORM_MAP[delivery.channel];
+        return platform ? (PLATFORM_TO_CHANNEL_MAP[platform] ?? delivery.channel) : delivery.channel;
+      })()
+    : undefined;
+
+  const result: GatewayDelivery = {
     mode: delivery.mode,
-    ...(delivery.channel ? { channel: delivery.channel } : {}),
+    ...(openclawChannel ? { channel: openclawChannel } : {}),
     ...(delivery.to ? { to: delivery.to } : {}),
     ...(delivery.accountId ? { accountId: delivery.accountId } : {}),
     ...(typeof delivery.bestEffort === 'boolean'
       ? { bestEffort: delivery.bestEffort }
       : {}),
   };
+  console.log('[CronJobService][toGatewayDelivery] output gatewayDelivery:', JSON.stringify(result, null, 2));
+  return result;
 }
 
 export function mapGatewayTaskState(state: GatewayJobState): TaskState {
   const lastStatus = state.runningAtMs
-    ? 'running'
+    ? TaskStatus.Running
     : mapGatewayResultStatus(state.lastRunStatus ?? state.lastStatus);
 
   return {
@@ -205,7 +246,22 @@ export function mapGatewayTaskState(state: GatewayJobState): TaskState {
 }
 
 export function mapGatewayJob(job: GatewayJob): ScheduledTask {
-  const delivery = job.delivery ?? { mode: 'none' as const };
+  const delivery = job.delivery ?? { mode: DeliveryMode.None };
+
+  // Infer delivery channel/to from sessionKey when the gateway job has no
+  // explicit delivery target (common for agent-initiated cron.add tasks).
+  let inferredChannel: string | undefined;
+  let inferredTo: string | undefined;
+  if (!delivery.channel && job.sessionKey) {
+    const parsed = parseChannelSessionKey(job.sessionKey);
+    if (parsed) {
+      const channelName = PLATFORM_TO_CHANNEL_MAP[parsed.platform];
+      if (channelName) {
+        inferredChannel = channelName;
+        inferredTo = parsed.conversationId;
+      }
+    }
+  }
 
   return {
     id: job.id,
@@ -215,19 +271,23 @@ export function mapGatewayJob(job: GatewayJob): ScheduledTask {
     schedule: mapGatewaySchedule(job.schedule),
     sessionTarget: job.sessionTarget,
     wakeMode: job.wakeMode,
-    payload: job.payload.kind === 'systemEvent'
-      ? { kind: 'systemEvent', text: job.payload.text }
+    payload: job.payload.kind === PayloadKind.SystemEvent
+      ? { kind: PayloadKind.SystemEvent, text: job.payload.text }
       : {
-          kind: 'agentTurn',
+          kind: PayloadKind.AgentTurn,
           message: job.payload.message,
           ...(typeof job.payload.timeoutSeconds === 'number'
             ? { timeoutSeconds: job.payload.timeoutSeconds }
             : {}),
         },
     delivery: {
       mode: delivery.mode,
-      ...(delivery.channel ? { channel: delivery.channel } : {}),
-      ...(delivery.to ? { to: delivery.to } : {}),
+      ...(delivery.channel || inferredChannel
+        ? { channel: delivery.channel ?? inferredChannel }
+        : {}),
+      ...(delivery.to || inferredTo
+        ? { to: delivery.to ?? inferredTo }
+        : {}),
       ...(delivery.accountId ? { accountId: delivery.accountId } : {}),
       ...(typeof delivery.bestEffort === 'boolean'
         ? { bestEffort: delivery.bestEffort }
@@ -243,8 +303,8 @@ export function mapGatewayJob(job: GatewayJob): ScheduledTask {
 
 export function mapGatewayRun(entry: GatewayRunLogEntry): ScheduledTaskRun {
   const status = entry.action && entry.action !== 'finished'
-    ? 'running'
-    : (mapGatewayResultStatus(entry.status) ?? 'error');
+    ? TaskStatus.Running
+    : (mapGatewayResultStatus(entry.status) ?? TaskStatus.Error);
 
   return {
     id: `${entry.jobId}-${entry.ts}`,
@@ -253,7 +313,7 @@ export function mapGatewayRun(entry: GatewayRunLogEntry): ScheduledTaskRun {
     sessionKey: entry.sessionKey ?? null,
     status,
     startedAt: new Date(entry.runAtMs ?? entry.ts).toISOString(),
-    finishedAt: status === 'running' ? null : new Date(entry.ts).toISOString(),
+    finishedAt: status === TaskStatus.Running ? null : new Date(entry.ts).toISOString(),
     durationMs: entry.durationMs ?? null,
     error: entry.error ?? null,
   };
@@ -306,7 +366,18 @@ export class CronJobService {
   }
 
   async addJob(input: ScheduledTaskInput): Promise<ScheduledTask> {
+    console.log('[CronJobService][addJob] full input:', JSON.stringify(input, null, 2));
+    console.log('[CronJobService][addJob] delivery details:', JSON.stringify({
+      deliveryMode: input.delivery?.mode,
+      deliveryChannel: input.delivery?.channel,
+      deliveryTo: input.delivery?.to,
+      deliveryAccountId: input.delivery?.accountId,
+      sessionTarget: input.sessionTarget,
+      sessionKey: input.sessionKey,
+    }, null, 2));
     const client = await this.client();
+    const gatewayDelivery = toGatewayDelivery(input.delivery);
+    console.log('[CronJobService][addJob] resolved gatewayDelivery:', JSON.stringify(gatewayDelivery));
     const job = await client.request<GatewayJob>('cron.add', {
       name: input.name,
       description: input.description || undefined,
@@ -315,16 +386,26 @@ export class CronJobService {
       sessionTarget: input.sessionTarget,
       wakeMode: input.wakeMode,
       payload: toGatewayPayload(input.payload),
-      ...(toGatewayDelivery(input.delivery) ? { delivery: toGatewayDelivery(input.delivery) } : {}),
+      ...(gatewayDelivery ? { delivery: gatewayDelivery } : {}),
       ...(input.agentId?.trim() ? { agentId: input.agentId.trim() } : {}),
       ...(input.sessionKey?.trim() ? { sessionKey: input.sessionKey.trim() } : {}),
     });
     const mapped = mapGatewayJob(job);
     this.jobNameCache.set(mapped.id, mapped.name);
+    console.log('[CronJobService][addJob] created job id:', mapped.id, 'name:', mapped.name);
     return mapped;
   }
 
   async updateJob(id: string, input: Partial<ScheduledTaskInput>): Promise<ScheduledTask> {
+    console.log('[CronJobService][updateJob] id:', id, 'input:', JSON.stringify(input, null, 2));
+    console.log('[CronJobService][updateJob] delivery details:', JSON.stringify({
+      deliveryMode: input.delivery?.mode,
+      deliveryChannel: input.delivery?.channel,
+      deliveryTo: input.delivery?.to,
+      deliveryAccountId: input.delivery?.accountId,
+      sessionTarget: input.sessionTarget,
+      sessionKey: input.sessionKey,
+    }, null, 2));
     const client = await this.client();
     const patch: Record<string, unknown> = {};
 
@@ -337,12 +418,15 @@ export class CronJobService {
     if (input.sessionTarget !== undefined) patch.sessionTarget = input.sessionTarget;
     if (input.wakeMode !== undefined) patch.wakeMode = input.wakeMode;
     if (input.payload !== undefined) patch.payload = toGatewayPayload(input.payload);
-    if (input.delivery !== undefined) patch.delivery = toGatewayDelivery(input.delivery) ?? { mode: 'none' };
+    if (input.delivery !== undefined) patch.delivery = toGatewayDelivery(input.delivery) ?? { mode: DeliveryMode.None };
     if (input.agentId !== undefined) patch.agentId = input.agentId?.trim() || null;
     if (input.sessionKey !== undefined) patch.sessionKey = input.sessionKey?.trim() || null;
 
+    console.log('[CronJobService][updateJob] final patch:', JSON.stringify(patch, null, 2));
     const job = await client.request<GatewayJob>('cron.update', { id, patch });
-    return mapGatewayJob(job);
+    const mapped = mapGatewayJob(job);
+    console.log('[CronJobService][updateJob] updated job id:', mapped.id, 'name:', mapped.name);
+    return mapped;
   }
 
   async removeJob(id: string): Promise<void> {
@@ -475,6 +559,7 @@ export class CronJobService {
     if (!this.polling) return;
 
     try {
+      await this.ensureGatewayReady();
       const client = this.getGatewayClient();
       if (!client) return;
 
@@ -537,23 +622,23 @@ export class CronJobService {
   private emitStatusUpdate(taskId: string, state: TaskState): void {
     BrowserWindow.getAllWindows().forEach((window) => {
       if (!window.isDestroyed()) {
-        window.webContents.send('scheduledTask:statusUpdate', { taskId, state });
+        window.webContents.send(IpcChannel.StatusUpdate, { taskId, state });
       }
     });
   }
 
   private emitRunUpdate(run: ScheduledTaskRunWithName): void {
     BrowserWindow.getAllWindows().forEach((window) => {
       if (!window.isDestroyed()) {
-        window.webContents.send('scheduledTask:runUpdate', { run });
+        window.webContents.send(IpcChannel.RunUpdate, { run });
       }
     });
   }
 
   private emitFullRefresh(): void {
     BrowserWindow.getAllWindows().forEach((window) => {
       if (!window.isDestroyed()) {
-        window.webContents.send('scheduledTask:refresh');
+        window.webContents.send(IpcChannel.Refresh);
       }
     });
   }
diff --git a/src/scheduled-task/design.md b/src/scheduled-task/design.md
new file mode 100644
--- /dev/null
+++ b/src/scheduled-task/design.md
@@ -0,0 +1,858 @@
+# LobsterAI 定时任务系统设计文档
+
+## 总述
+
+LobsterAI 的定时任务系统是一套横跨 **Renderer(UI) -> Main Process(IPC/业务逻辑) -> OpenClaw Gateway(调度引擎)** 三层的端到端自动化执行框架。它允许用户通过 UI 界面、IM 聊天或 Cowork 会话创建定时任务，由 OpenClaw 的 Cron 引擎进行调度触发，并将执行结果通过 IM 通道或 Webhook 投递给用户。
+
+**核心设计理念**：
+
+1. **OpenClaw 驱动** -- 所有定时任务的调度、执行、投递均由 OpenClaw Gateway 原生完成，LobsterAI 作为上层应用只负责任务的 CRUD 和 UI 展示，不接管消息投递逻辑
+2. **策略模式(Policy Pattern)** -- 不同来源的任务(UI/IM/Cowork/Legacy)各自拥有独立的策略类，控制默认参数、绑定关系、只读字段等行为
+3. **来源推断(Origin Inference)** -- 通过 `sessionKey` 的格式反向推断任务来源和执行绑定，实现与旧数据的无缝兼容
+4. **流式轮询** -- 通过 15 秒间隔的轮询机制将 OpenClaw 的任务状态变化实时推送到 UI
+
+### 系统总体架构
+
+```mermaid
+graph TB
+    subgraph Renderer["Renderer Process (React)"]
+        UI["TaskForm / TaskList / TaskDetail"]
+        Service["ScheduledTaskService"]
+        Slice["scheduledTaskSlice (Redux)"]
+        UI --> Service
+        Service --> Slice
+    end
+
+    subgraph Main["Main Process (Electron)"]
+        IPC["IPC Handlers<br/>scheduledTask:*"]
+        CronSvc["CronJobService"]
+        IMHandler["imScheduledTaskHandler"]
+        IMCowork["imCoworkHandler"]
+        ChannelSync["OpenClawChannelSessionSync"]
+        IMHandler --> IMCowork
+    end
+
+    subgraph OpenClaw["OpenClaw Gateway"]
+        CronEngine["Cron Scheduler"]
+        AgentExec["Agent Execution"]
+        Delivery["Delivery Engine"]
+        ChannelAdapter["Channel Adapters<br/>(Feishu/DingTalk/Telegram/...)"]
+        CronEngine --> AgentExec
+        AgentExec --> Delivery
+        Delivery --> ChannelAdapter
+    end
+
+    Service -->|"IPC invoke"| IPC
+    IPC -->|"cron.add / cron.update / ..."| CronSvc
+    CronSvc -->|"Gateway RPC"| CronEngine
+    CronSvc -->|"polling 15s"| CronEngine
+    CronSvc -->|"statusUpdate / runUpdate"| Slice
+    IMCowork -->|"createScheduledTask callback"| IPC
+    ChannelAdapter -->|"Feishu/DingTalk API"| IMTarget["IM 用户/群组"]
+```
+
+---
+
+## 分述：各模块详解
+
+---
+
+### 1. 类型系统 (`src/renderer/types/scheduledTask.ts`)
+
+定义了定时任务的全部前端类型，是 Renderer 与 Main Process 之间 IPC 通信的数据契约。
+
+#### 1.1 Schedule -- 调度时间
+
+```typescript
+type Schedule =
+  | { kind: 'at'; at: string }              // 一次性：ISO 8601 时间戳
+  | { kind: 'every'; everyMs: number; anchorMs?: number }  // 固定间隔（毫秒）
+  | { kind: 'cron'; expr: string; tz?: string; staggerMs?: number }  // Cron 表达式
+```
+
+#### 1.2 Payload -- 执行内容
+
+```typescript
+type ScheduledTaskPayload =
+  | { kind: 'agentTurn'; message: string; timeoutSeconds?: number }   // Agent 对话轮次
+  | { kind: 'systemEvent'; text: string }                              // 系统事件注入
+```
+
+- `agentTurn`：在隔离会话中执行完整的 Agent 对话轮次，支持超时控制
+- `systemEvent`：向主会话注入一条系统事件消息
+
+#### 1.3 Delivery -- 投递配置
+
+```typescript
+interface ScheduledTaskDelivery {
+  mode: 'none' | 'announce' | 'webhook';
+  channel?: string;      // IM 通道名：'feishu', 'dingtalk-connector', 'telegram' 等
+  to?: string;           // 目标标识：会话 ID 或 Webhook URL
+  accountId?: string;    // 多账号场景下的账号标识
+  bestEffort?: boolean;  // 投递失败是否影响任务状态
+}
+```
+
+#### 1.4 TaskState -- 运行状态
+
+```typescript
+interface TaskState {
+  nextRunAtMs: number | null;
+  lastRunAtMs: number | null;
+  lastStatus: 'success' | 'error' | 'skipped' | 'running' | null;
+  lastError: string | null;
+  lastDurationMs: number | null;
+  runningAtMs: number | null;
+  consecutiveErrors: number;
+}
+```
+
+#### 1.5 核心类型关系
+
+```mermaid
+classDiagram
+    class ScheduledTask {
+        +string id
+        +string name
+        +string description
+        +boolean enabled
+        +Schedule schedule
+        +string sessionTarget
+        +string wakeMode
+        +ScheduledTaskPayload payload
+        +ScheduledTaskDelivery delivery
+        +string|null agentId
+        +string|null sessionKey
+        +TaskState state
+        +string createdAt
+        +string updatedAt
+    }
+
+    class ScheduledTaskInput {
+        +string name
+        +string description
+        +boolean enabled
+        +Schedule schedule
+        +string sessionTarget
+        +string wakeMode
+        +ScheduledTaskPayload payload
+        +ScheduledTaskDelivery delivery
+        +string|null agentId
+        +string|null sessionKey
+    }
+
+    class ScheduledTaskRun {
+        +string id
+        +string taskId
+        +string|null sessionId
+        +string|null sessionKey
+        +string status
+        +string startedAt
+        +string|null finishedAt
+        +number|null durationMs
+        +string|null error
+    }
+
+    ScheduledTask --> Schedule
+    ScheduledTask --> ScheduledTaskPayload
+    ScheduledTask --> ScheduledTaskDelivery
+    ScheduledTask --> TaskState
+    ScheduledTaskInput --> Schedule
+    ScheduledTaskInput --> ScheduledTaskPayload
+    ScheduledTaskInput --> ScheduledTaskDelivery
+    ScheduledTaskRun --> ScheduledTask : taskId
+```
+
+---
+
+### 2. 策略模式 (`src/common/scheduledTaskPolicies/`)
+
+策略模式是定时任务系统的核心设计抽象，用于处理不同来源任务的差异化行为。
+
+#### 2.1 TaskPolicy 接口
+
+```typescript
+interface TaskPolicy {
+  readonly kind: TaskOriginKind;
+  getCreateDefaults(origin: TaskOrigin): Partial<PolicyTaskInput>;
+  normalizeDraft(draft: PolicyTaskModel): PolicyTaskModel;
+  onDeliveryChanged(draft: PolicyTaskModel, newDelivery: PolicyDelivery): PolicyTaskModel;
+  toWireBinding(binding: ExecutionBinding): WireBinding;
+  describeRunBehavior(task: PolicyTaskModel): string;
+  getReadonlyFields(): string[];
+}
+```
+
+每个方法的职责：
+
+| 方法 | 职责 |
+|------|------|
+| `getCreateDefaults` | 返回该来源任务的默认参数 |
+| `normalizeDraft` | 保存前的归一化校验（自动填充、绑定一致性） |
+| `onDeliveryChanged` | 用户修改投递配置时联动更新绑定关系 |
+| `toWireBinding` | 将领域模型的 `ExecutionBinding` 映射为 OpenClaw 的 `sessionTarget`/`sessionKey` |
+| `describeRunBehavior` | 生成人类可读的运行行为描述 |
+| `getReadonlyFields` | 返回 UI 中不可编辑的字段列表 |
+
+#### 2.2 四种策略实现
+
+```mermaid
+classDiagram
+    class TaskPolicy {
+        <<interface>>
+        +kind: TaskOriginKind
+        +getCreateDefaults()
+        +normalizeDraft()
+        +onDeliveryChanged()
+        +toWireBinding()
+        +describeRunBehavior()
+        +getReadonlyFields()
+    }
+
+    class ManualTaskPolicy {
+        +kind = 'manual'
+        sessionTarget: isolated
+        delivery: announce to last
+    }
+
+    class IMTaskPolicy {
+        +kind = 'im'
+        sessionTarget: main
+        delivery: announce to origin platform
+    }
+
+    class CoworkTaskPolicy {
+        +kind = 'cowork'
+        sessionTarget: main
+        delivery: announce to last
+    }
+
+    class LegacyTaskPolicy {
+        +kind = 'legacy'
+        sessionTarget: main
+        wakeMode: next-heartbeat
+    }
+
+    class TaskPolicyRegistry {
+        -policies: Map~string, TaskPolicy~
+        +get(origin: TaskOrigin): TaskPolicy
+    }
+
+    TaskPolicy <|.. ManualTaskPolicy
+    TaskPolicy <|.. IMTaskPolicy
+    TaskPolicy <|.. CoworkTaskPolicy
+    TaskPolicy <|.. LegacyTaskPolicy
+    TaskPolicyRegistry --> TaskPolicy
+```
+
+**各策略默认参数对比：**
+
+| 策略 | sessionTarget | wakeMode | delivery.mode | delivery.channel | 只读字段 |
+|------|--------------|----------|---------------|-----------------|---------|
+| ManualTaskPolicy | `isolated` | `now` | `announce` | `last` | 无 |
+| IMTaskPolicy | `main` | `now` | `announce` | 来源平台 | `origin` |
+| CoworkTaskPolicy | `main` | `now` | `announce` | `last` | `origin` |
+| LegacyTaskPolicy | `main` | `next-heartbeat` | -- | -- | `origin` |
+
+**策略切换 delivery 时的绑定联动：**
+
+- **ManualTaskPolicy**：当用户选择 IM 通道投递时，自动将 binding 切换为 `im_session`；取消 IM 投递时，重置为 `new_session`
+- **IMTaskPolicy**：投递通道始终锁定在来源 IM 平台；切换为 `none`/`webhook` 时重置为 `new_session`
+- **CoworkTaskPolicy**：投递变更不影响绑定（始终绑定原始会话）
+- **LegacyTaskPolicy**：兼容旧任务，投递为 IM 时自动创建 `im_session` 绑定
+
+#### 2.3 TaskPolicyRegistry
+
+```typescript
+const taskPolicyRegistry = new TaskPolicyRegistry([
+  new LegacyTaskPolicy(),
+  new IMTaskPolicy(),
+  new CoworkTaskPolicy(),
+  new ManualTaskPolicy(),
+]);
+```
+
+通过 `registry.get(origin)` 获取对应策略；如果 origin 不匹配，fallback 到 `ManualTaskPolicy`。
+
+---
+
+### 3. 来源与绑定推断 (`src/common/scheduledTaskOrigin.ts`)
+
+定义了任务的**来源(Origin)**和**执行绑定(Binding)**两个核心概念。
+
+#### 3.1 TaskOrigin -- 任务从哪里来
+
+```typescript
+type TaskOrigin =
+  | { kind: 'legacy' }                                         // 旧版任务
+  | { kind: 'im'; platform: string; conversationId: string }   // IM 创建
+  | { kind: 'cowork'; sessionId: string }                      // Cowork 会话创建
+  | { kind: 'manual' }                                         // UI 手动创建
+```
+
+#### 3.2 ExecutionBinding -- 任务如何执行
+
+```typescript
+type ExecutionBinding =
+  | { kind: 'new_session' }                                      // 每次触发创建新会话
+  | { kind: 'ui_session'; sessionId: string }                    // 在指定 UI 会话中执行
+  | { kind: 'im_session'; platform: string; conversationId: string; sessionId?: string }  // IM 会话绑定
+  | { kind: 'session_key'; sessionKey: string }                  // 使用显式 sessionKey
+```
+
+#### 3.3 inferOriginAndBinding -- 反向推断
+
+`inferOriginAndBinding()` 函数通过解析 `sessionKey` 的格式来反向推断任务的来源和绑定，用于兼容没有存储元数据的旧任务：
+
+```mermaid
+flowchart TD
+    A["输入: task.sessionKey"] --> B{sessionKey 存在?}
+    B -->|No| G["origin: manual<br/>binding: new_session"]
+    B -->|Yes| C{是 managed key?<br/>agent:main:lobsterai:*}
+    C -->|Yes| D{delivery 指向 IM 通道?}
+    D -->|Yes| E["origin: im<br/>binding: im_session"]
+    D -->|No| F["origin: cowork<br/>binding: ui_session"]
+    C -->|No| H{是 channel key?<br/>agent:*:platform:*}
+    H -->|Yes| I["origin: im<br/>binding: im_session"]
+    H -->|No| J["origin: cowork<br/>binding: session_key"]
+```
+
+**SessionKey 格式说明：**
+
+| 格式 | 示例 | 含义 |
+|------|------|------|
+| `agent:main:lobsterai:{sessionId}` | `agent:main:lobsterai:abc123` | 托管会话（UI/Cowork 创建） |
+| `agent:{agentId}:{platform}:{subtype}:{conversationId}` | `agent:main:feishu:direct:ou_xxx` | IM 通道会话 |
+| `cron:{jobId}` | `cron:job-456` | 隔离的 Cron 会话 |
+
+---
+
+### 4. TaskModelMapper (`src/common/taskModelMapper.ts`)
+
+负责**线格式(Wire Format)**与**领域模型(Domain Model)**之间的双向转换。
+
+```mermaid
+flowchart LR
+    Wire["WireTask<br/>(IPC 传输格式)"] -->|"fromWire()"| Domain["PolicyTaskModel<br/>(含 origin + binding)"]
+    Domain -->|"toWireInput()"| Input["PolicyTaskInput<br/>(IPC 写入格式)"]
+    Origin["TaskOrigin + defaults"] -->|"createDraft()"| Domain
+```
+
+三个核心方法：
+
+| 方法 | 输入 | 输出 | 用途 |
+|------|------|------|------|
+| `fromWire()` | `WireTask` + 可选 `meta` | `PolicyTaskModel` | 从 IPC 数据还原领域模型 |
+| `toWireInput()` | `PolicyTaskModel` + `TaskPolicy` | `PolicyTaskInput` | 保存时转为 IPC 格式 |
+| `createDraft()` | `TaskOrigin` + `defaults` | `PolicyTaskModel` | 创建空白草稿 |
+
+---
+
+### 5. 提醒文本解析 (`src/common/scheduledReminderText.ts`)
+
+处理三种不同格式的定时提醒文本，提供统一的解析接口。
+
+**支持的格式：**
+
+| 格式 | 示例 | 解析函数 |
+|------|------|---------|
+| 结构化提示 | `A scheduled reminder has been triggered. The reminder content is: ...` | `parseScheduledReminderPrompt()` |
+| Legacy 系统消息 | `System: [2026-03-21 09:00] ⏰ 查看邮箱` | `parseLegacyScheduledReminderSystemMessage()` |
+| 简单 emoji 格式 | `⏰ 提醒：查看邮箱` | `parseSimpleScheduledReminderText()` |
+
+统一入口 `getScheduledReminderDisplayText()` 按优先级依次尝试三种解析器，返回纯文本提醒内容。
+
+---
+
+### 6. Renderer 层 -- UI 与状态管理
+
+#### 6.1 组件结构
+
+```mermaid
+graph TD
+    STV["ScheduledTasksView<br/>(主容器)"] --> TL["TaskList<br/>(任务列表)"]
+    STV --> TF["TaskForm<br/>(创建/编辑表单)"]
+    STV --> TD["TaskDetail<br/>(详情+历史)"]
+    STV --> ARH["AllRunsHistory<br/>(跨任务运行历史)"]
+    TD --> TRH["TaskRunHistory<br/>(单任务运行记录)"]
+    TD --> RSM["RunSessionModal<br/>(会话详情弹窗)"]
+```
+
+#### 6.2 ScheduledTaskService (`src/renderer/services/scheduledTask.ts`)
+
+封装所有 IPC 调用并桥接 Redux dispatch：
+
+```typescript
+class ScheduledTaskService {
+  // CRUD 操作
+  async loadTasks()                          // IPC: scheduledTask:list
+  async createTask(input)                    // IPC: scheduledTask:create
+  async updateTaskById(id, partial)          // IPC: scheduledTask:update
+  async deleteTask(id)                       // IPC: scheduledTask:delete
+  async toggleTask(id, enabled)              // IPC: scheduledTask:toggle
+
+  // 执行操作
+  async runManually(id)                      // IPC: scheduledTask:runManually
+  async stopTask(id)                         // IPC: scheduledTask:stop
+
+  // 查询操作
+  async loadRuns(taskId, limit?, offset?)    // IPC: scheduledTask:listRuns
+  async loadAllRuns(limit?, offset?)         // IPC: scheduledTask:listAllRuns
+  async listChannels()                       // IPC: scheduledTask:listChannels
+  async listChannelConversations(channel)    // IPC: scheduledTask:listChannelConversations
+}
+```
+
+#### 6.3 Redux Slice (`scheduledTaskSlice.ts`)
+
+```typescript
+interface ScheduledTaskState {
+  tasks: ScheduledTask[];
+  selectedTaskId: string | null;
+  viewMode: 'list' | 'create' | 'edit' | 'detail';
+  runs: Record<string, ScheduledTaskRun[]>;
+  allRuns: ScheduledTaskRunWithName[];
+  loading: boolean;
+  error: string | null;
+}
+```
+
+状态更新来源：
+- **用户操作** -> Service 调用 -> IPC 返回 -> dispatch action
+- **轮询推送** -> IPC 事件监听 -> dispatch action（`updateTaskState`, `addOrUpdateRun`）
+
+---
+
+### 7. Main Process -- IPC 处理与业务逻辑
+
+#### 7.1 IPC 通道总览
+
+共 14 个 `scheduledTask:*` invoke 通道 + 3 个广播事件：
+
+| 通道 | 方向 | 功能 |
+|------|------|------|
+| `scheduledTask:list` | Request-Reply | 获取全部任务 |
+| `scheduledTask:get` | Request-Reply | 获取单个任务 |
+| `scheduledTask:create` | Request-Reply | 创建任务（含 IM delivery 归一化） |
+| `scheduledTask:update` | Request-Reply | 更新任务（含 IM delivery 归一化） |
+| `scheduledTask:delete` | Request-Reply | 删除任务 |
+| `scheduledTask:toggle` | Request-Reply | 启用/禁用任务 |
+| `scheduledTask:runManually` | Request-Reply | 手动触发执行 |
+| `scheduledTask:stop` | Request-Reply | 停止执行（No-op） |
+| `scheduledTask:listRuns` | Request-Reply | 获取任务运行历史 |
+| `scheduledTask:countRuns` | Request-Reply | 获取运行次数 |
+| `scheduledTask:listAllRuns` | Request-Reply | 获取全局运行历史 |
+| `scheduledTask:resolveSession` | Request-Reply | 获取瞬态会话内容 |
+| `scheduledTask:listChannels` | Request-Reply | 列出可用 IM 通道 |
+| `scheduledTask:listChannelConversations` | Request-Reply | 列出通道下的会话 |
+| `scheduledTask:statusUpdate` | Broadcast | 任务状态变更推送 |
+| `scheduledTask:runUpdate` | Broadcast | 运行记录更新推送 |
+| `scheduledTask:refresh` | Broadcast | 全量刷新信号 |
+
+#### 7.2 Create/Update 的 IM Delivery 归一化
+
+当 `delivery.mode === 'announce'` 且指定了 IM 通道时，IPC handler 执行以下归一化：
+
+```mermaid
+flowchart TD
+    A["接收 ScheduledTaskInput"] --> B{delivery.mode === 'announce'<br/>且 channel + to 存在?}
+    B -->|No| G["直接传递给 CronJobService"]
+    B -->|Yes| C["解析平台: CHANNEL_PLATFORM_MAP[channel]"]
+    C --> D["设置 sessionTarget = 'isolated'"]
+    D --> E["剥离 IM 子类型前缀<br/>direct:ou_xxx -> ou_xxx<br/>group:oc_xxx -> oc_xxx"]
+    E --> F{平台是 DingTalk?}
+    F -->|Yes| H["调用 primeConversationReplyRoute<br/>预注册出站回复路由"]
+    F -->|No| I["无需额外处理"]
+    H --> G
+    I --> G
+```
+
+**为什么要剥离前缀？**
+
+LobsterAI 的 `imStore` 中存储的 `conversationId` 带有 IM 子类型前缀（如 `direct:ou_xxx` 表示飞书私聊，`group:oc_xxx` 表示飞书群聊）。但 OpenClaw 的飞书插件中 `normalizeFeishuTarget()` 不识别 `direct:` 前缀，会将 `direct:ou_xxx` 原样传递给飞书 API，导致 400 错误。因此在传递给 OpenClaw 之前需要剥离此前缀。
+
+---
+
+### 8. CronJobService (`src/main/libs/cronJobService.ts`)
+
+#### 8.1 职责
+
+`CronJobService` 是 LobsterAI 与 OpenClaw Gateway 之间的 **适配器层**，封装了所有 Cron RPC 调用。
+
+```mermaid
+classDiagram
+    class CronJobService {
+        -getGatewayClient() GatewayClientLike
+        -ensureGatewayReady() Promise~void~
+        -pollInterval: NodeJS.Timeout
+        -lastStateHashes: Map~string, string~
+        -lastRunAtMap: Map~string, number~
+        -jobNameCache: Map~string, string~
+        +addJob(input) Promise~ScheduledTask~
+        +updateJob(id, input) Promise~ScheduledTask~
+        +removeJob(id) Promise~void~
+        +toggleJob(id, enabled) Promise~ScheduledTask~
+        +runJob(id) Promise~void~
+        +listJobs() Promise~ScheduledTask[]~
+        +listRuns(jobId, limit, offset) Promise~ScheduledTaskRun[]~
+        +listAllRuns(limit, offset) Promise~ScheduledTaskRunWithName[]~
+        +startPolling() void
+        +stopPolling() void
+        -pollOnce() Promise~void~
+        -emitStatusUpdate(taskId, state) void
+        -emitRunUpdate(run) void
+        -emitFullRefresh() void
+    }
+
+    class GatewayClient {
+        +request(method, params) Promise~any~
+    }
+
+    CronJobService --> GatewayClient : "cron.add / cron.update / ..."
+```
+
+#### 8.2 Gateway RPC 方法映射
+
+| CronJobService 方法 | Gateway RPC | 说明 |
+|---------------------|------------|------|
+| `addJob()` | `cron.add` | 创建 Cron Job |
+| `updateJob()` | `cron.update` | 更新 Cron Job（patch 模式） |
+| `removeJob()` | `cron.remove` | 删除 Cron Job |
+| `toggleJob()` | `cron.update` | 更新 enabled 字段 |
+| `runJob()` | `cron.run` | 立即触发执行 |
+| `listJobs()` | `cron.list` | 列出所有 Job（含 disabled） |
+| `listRuns()` | `cron.runs` | 查询 Job 的运行历史 |
+| `listAllRuns()` | `cron.runs` | 查询全局运行历史 |
+
+#### 8.3 轮询机制
+
+```mermaid
+sequenceDiagram
+    participant CS as CronJobService
+    participant GW as OpenClaw Gateway
+    participant Win as BrowserWindow
+
+    loop 每 15 秒
+        CS->>GW: cron.list (includeDisabled: true)
+        GW-->>CS: GatewayJob[]
+        CS->>CS: 计算每个 Job 的状态哈希
+        alt 状态哈希变化
+            CS->>Win: scheduledTask:statusUpdate
+        end
+        alt lastRunAtMs 增加
+            CS->>GW: cron.runs (scope: 'job', limit: 1)
+            GW-->>CS: 最新 RunLogEntry
+            CS->>Win: scheduledTask:runUpdate
+        end
+        alt 首次轮询
+            CS->>Win: scheduledTask:refresh
+        end
+    end
+```
+
+#### 8.4 类型映射
+
+CronJobService 在 LobsterAI 前端类型和 OpenClaw Gateway 类型之间进行双向转换：
+
+| 前端类型 | Gateway 类型 | 转换函数 |
+|---------|-------------|---------|
+| `Schedule` | `GatewaySchedule` | `mapGatewaySchedule()` / `toGatewaySchedule()` |
+| `ScheduledTaskPayload` | `GatewayPayload` | `toGatewayPayload()` |
+| `ScheduledTaskDelivery` | `GatewayDelivery` | `toGatewayDelivery()` |
+| `TaskState` | `GatewayJobState` | `mapGatewayTaskState()` |
+| `ScheduledTask` | `GatewayJob` | `mapGatewayJob()` |
+
+---
+
+### 9. IM 定时任务检测 (`src/main/im/imScheduledTaskHandler.ts`)
+
+#### 9.1 检测流程
+
+当用户通过 IM 发送消息时，系统会自动检测是否包含定时提醒请求：
+
+```mermaid
+sequenceDiagram
+    participant User as IM 用户
+    participant IMH as imCoworkHandler
+    participant Det as ScheduledTaskDetector
+    participant LLM as LLM API
+    participant IPC as create IPC handler
+
+    User->>IMH: "明天上午9点提醒我查收邮件"
+    IMH->>Det: looksLikeIMScheduledTaskCandidate(text)
+    Det-->>IMH: true (正则匹配到关键词)
+    IMH->>Det: detectScheduledTaskRequest(message)
+    Det->>LLM: 提取结构化提醒请求
+    LLM-->>Det: { shouldCreateTask: true, scheduleAt, reminderBody, taskName }
+    Det->>Det: normalizeDetectedScheduledTaskRequest()
+    Det-->>IMH: ParsedIMScheduledTaskRequest
+    IMH->>IPC: createScheduledTask({ sessionId, message, request })
+    IPC-->>IMH: { success: true, taskId }
+    IMH->>User: "好的，已设置好提醒！1天后（09:00）会提醒你..."
+```
+
+#### 9.2 检测管道
+
+1. **正则预过滤** (`looksLikeIMScheduledTaskCandidate`)：检查消息是否包含时间相关关键词（`提醒`, `定时`, `闹钟`, `remind`, `schedule`, `tomorrow` 等）
+2. **LLM 结构化提取**：调用 LLM 将自然语言解析为 `{ shouldCreateTask, scheduleAt, reminderBody, taskName }`
+3. **归一化** (`normalizeDetectedScheduledTaskRequest`)：验证时间有效性、生成任务名称、格式化确认文本
+
+#### 9.3 IM 创建的消息序列
+
+直接检测到定时提醒请求后，`imCoworkHandler` 会记录以下消息序列到 Cowork 会话中：
+
+```
+[USER]       "明天上午9点提醒我查收邮件"
+[TOOL_USE]   { toolName: "cron", action: "add", job: { name, schedule, payload } }
+[TOOL_RESULT] { id, name, agentId, sessionKey, payloadText, scheduleAt }
+[ASSISTANT]  "好的，已设置好提醒！1天后（09:00）会提醒你..."
+```
+
+---
+
+### 10. 会话键管理 (`src/main/libs/openclawChannelSessionSync.ts`)
+
+#### 10.1 SessionKey 格式
+
+OpenClaw 使用 `sessionKey` 来标识和管理会话。LobsterAI 定义了三种格式：
+
+| 类型 | 格式 | 示例 | 用途 |
+|------|------|------|------|
+| 托管会话 | `agent:{agentId}:lobsterai:{sessionId}` | `agent:main:lobsterai:abc123` | UI/Cowork 创建的会话 |
+| 通道会话 | `agent:{agentId}:{platform}:{subtype}:{conversationId}` | `agent:main:feishu:direct:ou_xxx` | IM 平台的会话 |
+| Cron 会话 | `cron:{jobId}` | `cron:job-456` | 隔离 Cron 任务的独立会话 |
+
+#### 10.2 平台映射
+
+```typescript
+const CHANNEL_PLATFORM_MAP: Record<string, IMPlatform> = {
+  'dingtalk-connector': 'dingtalk',
+  'feishu': 'feishu',
+  'telegram': 'telegram',
+  'discord': 'discord',
+  'netease-im': 'netease-im',
+  'netease-bee': 'netease-bee',
+};
+
+const PLATFORM_TO_CHANNEL_MAP: Record<IMPlatform, string> = {
+  'dingtalk': 'dingtalk-connector',
+  'feishu': 'feishu',
+  'telegram': 'telegram',
+  'discord': 'discord',
+  'netease-im': 'netease-im',
+  'netease-bee': 'netease-bee',
+};
+```
+
+#### 10.3 delivery.to 格式转换链
+
+```mermaid
+flowchart LR
+    A["imStore 存储<br/>direct:ou_xxx"] -->|"UI TaskForm 选择"| B["ScheduledTaskInput<br/>delivery.to = direct:ou_xxx"]
+    B -->|"IPC handler 剥离前缀"| C["CronJobService<br/>delivery.to = ou_xxx"]
+    C -->|"Gateway RPC"| D["OpenClaw CronJob<br/>delivery.to = ou_xxx"]
+    D -->|"触发时 announce"| E["Feishu Plugin<br/>normalizeFeishuTarget(ou_xxx)"]
+    E -->|"Feishu API"| F["receive_id = ou_xxx<br/>receive_id_type = open_id"]
+```
+
+---
+
+### 11. OpenClaw Cron 调度引擎
+
+OpenClaw Gateway 内置 Cron 调度引擎，负责定时任务的存储、调度触发、会话创建、Agent 执行和结果投递。
+
+#### 11.1 Cron Job 数据模型
+
+```typescript
+interface CronJob {
+  id: string;
+  name: string;
+  description?: string;
+  enabled: boolean;
+  schedule: CronSchedule;           // at | every | cron
+  sessionTarget: 'main' | 'isolated';
+  wakeMode: 'now' | 'next-heartbeat';
+  payload: CronPayload;            // systemEvent | agentTurn
+  delivery?: CronDelivery;         // announce | webhook | none
+  failureAlert?: CronFailureAlert;
+  agentId?: string | null;
+  sessionKey?: string | null;
+  deleteAfterRun?: boolean;        // 一次性任务自动删除
+  state: CronJobState;
+  createdAtMs: number;
+  updatedAtMs: number;
+}
+```
+
+#### 11.2 两条执行路径
+
+```mermaid
+flowchart TD
+    Trigger["Cron 触发"] --> Check{sessionTarget?}
+
+    Check -->|"main"| MainPath["主会话路径"]
+    MainPath --> ME["将 systemEvent 注入主会话时间线"]
+    ME --> MW{wakeMode?}
+    MW -->|"now"| MN["立即触发下一次心跳"]
+    MW -->|"next-heartbeat"| MH["等待下一次心跳周期"]
+    MN --> MP["主 Agent 处理系统事件"]
+    MH --> MP
+    MP --> MR["结果留在主聊天记录中"]
+
+    Check -->|"isolated"| IsoPath["隔离会话路径"]
+    IsoPath --> IS["创建独立会话<br/>cron:{jobId}"]
+    IS --> IE["Agent 执行 (独立上下文)"]
+    IE --> ID{delivery.mode?}
+
+    ID -->|"announce"| DA["通过 Channel Adapter 投递"]
+    DA --> DAS["同时向主会话发送摘要<br/>(受 wakeMode 控制)"]
+    ID -->|"webhook"| DW["HTTP POST 到目标 URL"]
+    ID -->|"none"| DN["结果仅保留在内部"]
+```
+
+#### 11.3 Announce 投递详解
+
+当隔离任务完成且 `delivery.mode = 'announce'` 时：
+
+1. **Channel 路由**：根据 `delivery.channel` 选择对应的 Channel Adapter（Feishu、DingTalk、Telegram 等）
+2. **目标解析**：`delivery.to` 指定具体的接收者（用户 ID、群组 ID、Webhook URL 等）
+3. **消息分块**：长消息自动分块，适配各 IM 平台的消息长度限制
+4. **去重**：如果隔离会话运行期间已经向同一目标发送过消息，跳过投递避免重复
+5. **心跳过滤**：纯心跳响应（`HEARTBEAT_OK`）不投递
+6. **主会话摘要**：向主会话发送简要摘要，时机由 `wakeMode` 控制
+
+#### 11.4 重试与错误处理
+
+**瞬态错误（自动重试）：**
+- 速率限制 (429)
+- 网络错误 (timeout, ECONNRESET)
+- 服务器错误 (5xx)
+
+**永久错误（立即禁用）：**
+- 认证失败（API Key 无效）
+- 配置/验证错误
+
+**重试策略：**
+
+| 任务类型 | 重试次数 | 退避策略 | 失败后行为 |
+|---------|---------|---------|-----------|
+| 一次性 (`at`) | 最多 3 次 | 30s -> 1m -> 5m | 禁用或删除 |
+| 循环 (`cron`/`every`) | 不限次 | 30s -> 1m -> 5m -> 15m -> 60m | 保持启用，退避延长 |
+
+#### 11.5 存储与清理
+
+| 存储项 | 路径 | 清理策略 |
+|-------|------|---------|
+| Job 定义 | `~/.openclaw/cron/jobs.json` | 手动删除 |
+| 运行历史 | `~/.openclaw/cron/runs/{jobId}.jsonl` | `runLog.maxBytes` (2MB) + `runLog.keepLines` (2000) |
+| 隔离会话 | OpenClaw sessions | `sessionRetention` (默认 24h) |
+
+---
+
+## 完整生命周期：端到端流程
+
+### 场景一：UI 创建 + 飞书投递
+
+```mermaid
+sequenceDiagram
+    actor User
+    participant UI as TaskForm (React)
+    participant Svc as ScheduledTaskService
+    participant IPC as IPC Handler (Main)
+    participant Cron as CronJobService
+    participant GW as OpenClaw Gateway
+    participant Feishu as Feishu Plugin
+
+    User->>UI: 填写表单<br/>每天 9:00 / announce / feishu / direct:ou_xxx
+    UI->>Svc: createTask(input)
+    Svc->>IPC: IPC invoke: scheduledTask:create
+
+    Note over IPC: IM delivery 归一化
+    IPC->>IPC: sessionTarget = 'isolated'
+    IPC->>IPC: delivery.to: 'direct:ou_xxx' -> 'ou_xxx'
+
+    IPC->>Cron: addJob(normalizedInput)
+    Cron->>GW: cron.add({ ..., delivery: { mode: 'announce', channel: 'feishu', to: 'ou_xxx' } })
+    GW-->>Cron: GatewayJob (id, state)
+    Cron-->>IPC: ScheduledTask
+    IPC-->>Svc: { success: true, task }
+    Svc->>UI: dispatch(addTask(task))
+
+    Note over GW: === 每天 9:00 触发 ===
+    GW->>GW: 创建隔离会话 cron:{jobId}
+    GW->>GW: Agent 执行 payload
+    GW->>Feishu: announce 投递<br/>normalizeFeishuTarget('ou_xxx')
+    Feishu->>Feishu: Feishu API: message.create<br/>receive_id='ou_xxx', type='open_id'
+
+    Note over Cron: === 轮询检测 ===
+    Cron->>GW: cron.list (15s interval)
+    GW-->>Cron: 状态已变更
+    Cron->>UI: scheduledTask:statusUpdate
+    Cron->>GW: cron.runs (limit: 1)
+    GW-->>Cron: 最新运行记录
+    Cron->>UI: scheduledTask:runUpdate
+```
+
+### 场景二：飞书消息创建定时提醒
+
+```mermaid
+sequenceDiagram
+    actor User
+    participant FS as 飞书 App
+    participant IMH as imCoworkHandler
+    participant Det as ScheduledTaskDetector
+    participant LLM as LLM
+    participant CB as createScheduledTask callback
+    participant Cron as CronJobService
+    participant GW as OpenClaw Gateway
+
+    User->>FS: "明天上午9点提醒我查收邮件"
+    FS->>IMH: processMessage(message)
+    IMH->>Det: looksLikeIMScheduledTaskCandidate(text)
+    Det-->>IMH: true
+    IMH->>Det: detectScheduledTaskRequest(message)
+    Det->>LLM: 结构化提取
+    LLM-->>Det: { shouldCreateTask: true, scheduleAt: '2026-03-22T09:00:00+08:00', reminderBody: '查收邮件', taskName: '查收邮件提醒' }
+    Det-->>IMH: ParsedIMScheduledTaskRequest
+
+    IMH->>CB: createScheduledTask({ sessionId, message, request })
+    Note over CB: 检测 IM 通道信息
+    CB->>CB: hasChannel = true (feishu + conversationId)
+    CB->>CB: sessionTarget = 'isolated'
+    CB->>CB: delivery = { mode: 'announce', channel: 'feishu', to: 'ou_xxx' }
+    CB->>CB: payload = { kind: 'agentTurn', message: '...' }
+    CB->>Cron: addJob(input)
+    Cron->>GW: cron.add(...)
+    GW-->>Cron: GatewayJob
+    Cron-->>CB: ScheduledTask
+    CB-->>IMH: { success: true, taskId }
+
+    IMH->>IMH: 记录消息序列 (USER/TOOL_USE/TOOL_RESULT/ASSISTANT)
+    IMH->>FS: 确认消息: "好的，已设置好提醒！1天后（09:00）会提醒你查收邮件"
+    FS->>User: 显示确认消息
+
+    Note over GW: === 次日 9:00 触发 ===
+    GW->>GW: 创建隔离会话 + Agent 执行
+    GW->>FS: announce 投递提醒消息
+    FS->>User: "⏰ 提醒：查收邮件"
+```
+
+---
+
+## 总结
+
+LobsterAI 的定时任务系统通过三层架构实现了完整的自动化执行能力：
+
+1. **前端层（Renderer）**：提供直观的 UI 界面用于任务的 CRUD 管理，通过 Redux + 轮询实现实时状态更新
+2. **业务层（Main Process）**：通过 IPC handler + CronJobService 封装业务逻辑，负责 IM delivery 的归一化处理和类型映射
+3. **引擎层（OpenClaw Gateway）**：承担所有调度、执行、投递的核心工作，确保 LobsterAI 不需要自行实现消息投递逻辑
+
+**关键设计决策：**
+
+| 决策 | 理由 |
+|------|------|
+| 策略模式区分任务来源 | 不同来源的默认参数、绑定关系、只读字段各不相同，策略模式避免了大量 if-else |
+| 来源推断而非存储 | 通过 sessionKey 格式反推来源，无需修改 OpenClaw 的数据模型即可兼容旧数据 |
+| 前缀剥离而非修改 OpenClaw | LobsterAI 的 `imStore` 需要带前缀的 ID 做内部路由，但 OpenClaw 的 Feishu 插件不识别该前缀，因此在传递给 OpenClaw 前剥离 |
+| 15 秒轮询而非 WebSocket | OpenClaw Gateway 不暴露实时事件流，轮询是最简单可靠的状态同步方式 |
+| `isolated` + `announce` 作为 IM 投递标准模式 | 隔离会话避免污染主聊天记录，announce 模式让 OpenClaw 原生处理消息投递，保持 OpenClaw 驱动的设计理念 |
diff --git a/src/main/libs/scheduledTaskEnginePrompt.ts b/src/scheduled-task/enginePrompt.ts
rename from src/main/libs/scheduledTaskEnginePrompt.ts
rename to src/scheduled-task/enginePrompt.ts
--- a/src/main/libs/scheduledTaskEnginePrompt.ts
+++ b/src/scheduled-task/enginePrompt.ts
@@ -1,4 +1,4 @@
-import type { CoworkAgentEngine } from './agentEngine/types';
+import type { CoworkAgentEngine } from '../main/libs/agentEngine/types';
 
 export const SCHEDULED_TASK_SWITCH_MESSAGE =
   'Scheduled tasks are only available in OpenClaw. Switch the agent engine to OpenClaw and try again.';
diff --git a/src/scheduled-task/fixtures.ts b/src/scheduled-task/fixtures.ts
new file mode 100644
--- /dev/null
+++ b/src/scheduled-task/fixtures.ts
@@ -0,0 +1,70 @@
+import type { PolicyTaskModel, PolicyDelivery } from './policies/types';
+import type { TaskOrigin, ExecutionBinding } from './origin';
+import type { SessionTarget, WakeMode } from './constants';
+import {
+  SessionTarget as ST,
+  WakeMode as WM,
+  ScheduleKind,
+  PayloadKind,
+  DeliveryMode,
+  DefaultAgentId,
+  OriginKind,
+  BindingKind,
+} from './constants';
+
+interface TaskOverrides {
+  id?: string;
+  name?: string;
+  description?: string;
+  enabled?: boolean;
+  schedule?: unknown;
+  sessionTarget?: SessionTarget;
+  wakeMode?: WakeMode;
+  payload?: unknown;
+  delivery?: PolicyDelivery;
+  agentId?: string | null;
+  sessionKey?: string | null;
+  state?: unknown;
+  createdAt?: string;
+  updatedAt?: string;
+  origin?: TaskOrigin;
+  binding?: ExecutionBinding;
+}
+
+/** Create a minimal wire-format ScheduledTask with sensible defaults. */
+export function makeTask(overrides: TaskOverrides = {}) {
+  return {
+    id: overrides.id ?? 'task-test-001',
+    name: overrides.name ?? 'Test Task',
+    description: overrides.description ?? '',
+    enabled: overrides.enabled ?? true,
+    schedule: overrides.schedule ?? { kind: ScheduleKind.Every, everyMs: 3600000 },
+    sessionTarget: overrides.sessionTarget ?? ST.Main,
+    wakeMode: overrides.wakeMode ?? WM.Now,
+    payload: overrides.payload ?? { kind: PayloadKind.SystemEvent, text: 'test' },
+    delivery: overrides.delivery ?? { mode: DeliveryMode.None as const },
+    agentId: overrides.agentId ?? DefaultAgentId,
+    sessionKey: overrides.sessionKey ?? null,
+    state: overrides.state ?? {
+      nextRunAtMs: 0,
+      lastRunAtMs: 0,
+      lastStatus: null,
+      lastError: null,
+      lastDurationMs: null,
+      runningAtMs: null,
+      consecutiveErrors: 0,
+    },
+    createdAt: overrides.createdAt ?? new Date().toISOString(),
+    updatedAt: overrides.updatedAt ?? new Date().toISOString(),
+  };
+}
+
+/** Create a minimal ScheduledTaskModel (domain model) with origin + binding. */
+export function makeModel(overrides: TaskOverrides = {}): PolicyTaskModel {
+  const base = makeTask(overrides);
+  return {
+    ...base,
+    origin: overrides.origin ?? { kind: OriginKind.Manual },
+    binding: overrides.binding ?? { kind: BindingKind.NewSession },
+  } as PolicyTaskModel;
+}
diff --git a/src/scheduled-task/metaStore.ts b/src/scheduled-task/metaStore.ts
new file mode 100644
--- /dev/null
+++ b/src/scheduled-task/metaStore.ts
@@ -0,0 +1,58 @@
+/**
+ * Local metadata store for scheduled task origin/binding.
+ * OpenClaw gateway cron.* API doesn't support custom fields,
+ * so we persist origin/binding locally in SQLite.
+ */
+import type { Database } from 'sql.js';
+
+export interface TaskMeta {
+  taskId: string;
+  origin: string; // JSON.stringify(TaskOrigin)
+  binding: string; // JSON.stringify(ExecutionBinding)
+}
+
+export class ScheduledTaskMetaStore {
+  constructor(private db: Database) {
+    this.ensureTable();
+  }
+
+  private ensureTable(): void {
+    this.db.run(
+      'CREATE TABLE IF NOT EXISTS scheduled_task_meta (task_id TEXT PRIMARY KEY, origin TEXT NOT NULL, binding TEXT NOT NULL)'
+    );
+  }
+
+  get(taskId: string): TaskMeta | null {
+    const stmt = this.db.prepare('SELECT task_id, origin, binding FROM scheduled_task_meta WHERE task_id = ?');
+    stmt.bind([taskId]);
+    if (stmt.step()) {
+      const row = stmt.getAsObject() as { task_id: string; origin: string; binding: string };
+      stmt.free();
+      return { taskId: row.task_id, origin: row.origin, binding: row.binding };
+    }
+    stmt.free();
+    return null;
+  }
+
+  set(taskId: string, origin: unknown, binding: unknown): void {
+    this.db.run(
+      'INSERT OR REPLACE INTO scheduled_task_meta (task_id, origin, binding) VALUES (?, ?, ?)',
+      [taskId, JSON.stringify(origin), JSON.stringify(binding)]
+    );
+  }
+
+  delete(taskId: string): void {
+    this.db.run('DELETE FROM scheduled_task_meta WHERE task_id = ?', [taskId]);
+  }
+
+  list(): TaskMeta[] {
+    const results: TaskMeta[] = [];
+    const stmt = this.db.prepare('SELECT task_id, origin, binding FROM scheduled_task_meta');
+    while (stmt.step()) {
+      const row = stmt.getAsObject() as { task_id: string; origin: string; binding: string };
+      results.push({ taskId: row.task_id, origin: row.origin, binding: row.binding });
+    }
+    stmt.free();
+    return results;
+  }
+}
diff --git a/src/main/libs/migrateScheduledTasks.ts b/src/scheduled-task/migrate.ts
rename from src/main/libs/migrateScheduledTasks.ts
rename to src/scheduled-task/migrate.ts
--- a/src/main/libs/migrateScheduledTasks.ts
+++ b/src/scheduled-task/migrate.ts
@@ -9,9 +9,8 @@ import fs from 'fs';
 import path from 'path';
 import type { Database } from 'sql.js';
 import type { CronJobService } from './cronJobService';
-import type { Schedule, ScheduledTaskDelivery, ScheduledTaskInput } from '../../renderer/types/scheduledTask';
-
-const MIGRATION_KEY = 'scheduled_tasks_migrated_to_openclaw_v1';
+import { MigrationKey, ScheduleKind, PayloadKind, DeliveryMode, SessionTarget, WakeMode, GatewayStatus, DefaultAgentId } from './constants';
+import type { Schedule, ScheduledTaskDelivery, ScheduledTaskInput } from './types';
 
 // ---------------------------------------------------------------------------
 // Legacy types (main branch schema — never changed, only removed)
@@ -66,16 +65,16 @@ function convertSchedule(legacy: LegacySchedule): Schedule | null {
     // Skip one-time tasks whose scheduled time is already in the past —
     // the gateway rejects them and they would never fire anyway.
     if (new Date(withTz).getTime() <= Date.now()) return null;
-    return { kind: 'at', at: withTz };
+    return { kind: ScheduleKind.At, at: withTz };
   }
   if (legacy.type === 'interval') {
     const ms = legacy.intervalMs;
     if (!ms || ms <= 0) return null;
-    return { kind: 'every', everyMs: ms };
+    return { kind: ScheduleKind.Every, everyMs: ms };
   }
   if (legacy.type === 'cron') {
     if (!legacy.expression) return null;
-    return { kind: 'cron', expr: legacy.expression };
+    return { kind: ScheduleKind.Cron, expr: legacy.expression };
   }
   return null;
 }
@@ -88,10 +87,10 @@ function convertDelivery(platformsJson: string): ScheduledTaskDelivery {
     // ignore
   }
   if (!Array.isArray(platforms) || platforms.length === 0) {
-    return { mode: 'none' };
+    return { mode: DeliveryMode.None };
   }
   // New format supports one delivery target — use the first platform as channel.
-  return { mode: 'announce', channel: platforms[0] };
+  return { mode: DeliveryMode.Announce, channel: platforms[0] };
 }
 
 function rowToInput(row: LegacyTaskRow): ScheduledTaskInput | null {
@@ -116,11 +115,11 @@ function rowToInput(row: LegacyTaskRow): ScheduledTaskInput | null {
     schedule,
     // 旧任务都带有 prompt，使用 isolated session + agentTurn。
     // main session 仅支持 systemEvent payload，不适用于迁移场景。
-    sessionTarget: 'isolated',
-    wakeMode: 'next-heartbeat',
-    payload: { kind: 'agentTurn', message: row.prompt },
+    sessionTarget: SessionTarget.Isolated,
+    wakeMode: WakeMode.NextHeartbeat,
+    payload: { kind: PayloadKind.AgentTurn, message: row.prompt },
     delivery: convertDelivery(row.notify_platforms_json ?? '[]'),
-    agentId: 'main',
+    agentId: DefaultAgentId,
   };
 }
 
@@ -143,7 +142,7 @@ export async function migrateScheduledTasksToOpenclaw(deps: MigrationDeps): Prom
   const { db, getKv, setKv, cronJobService } = deps;
 
   // 1. Idempotency guard
-  if (getKv(MIGRATION_KEY) === 'true') return;
+  if (getKv(MigrationKey.TasksToOpenclaw) === 'true') return;
 
   // 2. Check if the legacy table exists (new installs won't have it)
   try {
@@ -152,7 +151,7 @@ export async function migrateScheduledTasksToOpenclaw(deps: MigrationDeps): Prom
     );
     if (!tableCheck[0]?.values?.length) {
       // Fresh install — nothing to migrate
-      setKv(MIGRATION_KEY, 'true');
+      setKv(MigrationKey.TasksToOpenclaw, 'true');
       return;
     }
   } catch (err) {
@@ -167,7 +166,7 @@ export async function migrateScheduledTasksToOpenclaw(deps: MigrationDeps): Prom
       'SELECT id, name, description, enabled, schedule_json, prompt, notify_platforms_json FROM scheduled_tasks',
     );
     if (!result[0]?.values?.length) {
-      setKv(MIGRATION_KEY, 'true');
+      setKv(MigrationKey.TasksToOpenclaw, 'true');
       return;
     }
     const cols = result[0].columns;
@@ -207,15 +206,15 @@ export async function migrateScheduledTasksToOpenclaw(deps: MigrationDeps): Prom
   // Skipped tasks (invalid schedule etc.) are unrecoverable and don't block completion.
   // Gateway errors may be transient, so we leave the flag unset to allow a retry on next launch.
   if (gatewayErrors === 0) {
-    setKv(MIGRATION_KEY, 'true');
+    setKv(MigrationKey.TasksToOpenclaw, 'true');
   }
 }
 
 // ---------------------------------------------------------------------------
 // Run history migration: SQLite scheduled_task_runs → OpenClaw JSONL files
 // ---------------------------------------------------------------------------
 
-const RUN_HISTORY_MIGRATION_KEY = 'scheduled_task_runs_migrated_to_openclaw_v1';
+const RUN_HISTORY_MIGRATION_KEY = MigrationKey.RunsToOpenclaw;
 
 interface LegacyRunRow {
   id: string;
@@ -228,11 +227,10 @@ interface LegacyRunRow {
   error: string | null;
 }
 
-/** Convert legacy run status to OpenClaw gateway status. */
-function toGatewayStatus(status: string): 'ok' | 'error' | 'skipped' {
-  if (status === 'success') return 'ok';
-  if (status === 'error') return 'error';
-  return 'skipped';
+function toGatewayStatus(status: string): GatewayStatus {
+  if (status === 'success') return GatewayStatus.Ok;
+  if (status === 'error') return GatewayStatus.Error;
+  return GatewayStatus.Skipped;
 }
 
 interface RunHistoryMigrationDeps {
diff --git a/src/scheduled-task/modelMapper.ts b/src/scheduled-task/modelMapper.ts
new file mode 100644
--- /dev/null
+++ b/src/scheduled-task/modelMapper.ts
@@ -0,0 +1,91 @@
+import { inferOriginAndBinding } from './origin';
+import type { TaskOrigin, ExecutionBinding } from './origin';
+import type { TaskPolicy, PolicyTaskModel, PolicyTaskInput, PolicyDelivery } from './policies/types';
+import type { SessionTarget, WakeMode } from './constants';
+import { BindingKind, ScheduleKind, PayloadKind, DeliveryMode, SessionTarget as ST, WakeMode as WM } from './constants';
+
+/** Minimal wire task shape for mapping (avoids importing renderer types) */
+export interface WireTask {
+  id: string;
+  name: string;
+  description: string;
+  enabled: boolean;
+  schedule: unknown;
+  sessionTarget: SessionTarget;
+  wakeMode: WakeMode;
+  payload: unknown;
+  delivery: PolicyDelivery;
+  agentId: string | null;
+  sessionKey: string | null;
+  state: unknown;
+  createdAt: string;
+  updatedAt: string;
+}
+
+export interface TaskModelMapperResult {
+  wire: WireTask;
+  origin: TaskOrigin;
+  binding: ExecutionBinding;
+}
+
+export class TaskModelMapper {
+  fromWire(
+    wire: WireTask,
+    meta?: { origin: TaskOrigin; binding: ExecutionBinding },
+  ): PolicyTaskModel {
+    const resolved = meta ?? inferOriginAndBinding(wire);
+    return {
+      ...wire,
+      origin: resolved.origin,
+      binding: resolved.binding,
+    };
+  }
+
+  toWireInput(model: PolicyTaskModel, policy: TaskPolicy): PolicyTaskInput {
+    const wireBinding = policy.toWireBinding(model.binding);
+    return {
+      name: model.name,
+      description: model.description,
+      enabled: model.enabled,
+      schedule: model.schedule,
+      sessionTarget: wireBinding.sessionTarget,
+      wakeMode: model.wakeMode,
+      payload: model.payload,
+      delivery: model.delivery,
+      agentId: model.agentId,
+      sessionKey: wireBinding.sessionKey,
+    };
+  }
+
+  createDraft(origin: TaskOrigin, defaults: Partial<PolicyTaskInput>): PolicyTaskModel {
+    const now = new Date().toISOString();
+    const defaultBinding: ExecutionBinding = { kind: BindingKind.NewSession };
+
+    return {
+      id: `draft-${Date.now()}`,
+      name: defaults.name ?? '',
+      description: defaults.description ?? '',
+      enabled: defaults.enabled ?? true,
+      schedule: defaults.schedule ?? { kind: ScheduleKind.Every, everyMs: 3600000 },
+      sessionTarget: defaults.sessionTarget ?? ST.Main,
+      wakeMode: defaults.wakeMode ?? WM.Now,
+      payload: defaults.payload ?? { kind: PayloadKind.SystemEvent, text: '' },
+      delivery: defaults.delivery ?? { mode: DeliveryMode.None },
+      agentId: defaults.agentId ?? null,
+      sessionKey: defaults.sessionKey ?? null,
+      state: {
+        nextRunAtMs: null,
+        lastRunAtMs: null,
+        lastStatus: null,
+        lastError: null,
+        lastDurationMs: null,
+        runningAtMs: null,
+        consecutiveErrors: 0,
+      },
+      createdAt: now,
+      updatedAt: now,
+      origin,
+      binding: defaultBinding,
+    };
+  }
+}
diff --git a/src/scheduled-task/origin.ts b/src/scheduled-task/origin.ts
new file mode 100644
--- /dev/null
+++ b/src/scheduled-task/origin.ts
@@ -0,0 +1,103 @@
+import {
+  isManagedSessionKey,
+  parseManagedSessionKey,
+  parseChannelSessionKey,
+} from '../main/libs/openclawChannelSessionSync';
+import {
+  OriginKind,
+  BindingKind,
+  DeliveryMode,
+  DeliveryChannel,
+} from './constants';
+
+// Re-declare origin/binding types here so common/ doesn't depend on renderer/
+// These MUST be kept in sync with src/renderer/types/scheduledTask.ts
+
+export type TaskOriginKind = OriginKind;
+
+export type TaskOrigin =
+  | { kind: typeof OriginKind.Legacy }
+  | { kind: typeof OriginKind.IM; platform: string; conversationId: string }
+  | { kind: typeof OriginKind.Cowork; sessionId: string }
+  | { kind: typeof OriginKind.Manual };
+
+export type ExecutionBinding =
+  | { kind: typeof BindingKind.NewSession }
+  | { kind: typeof BindingKind.UISession; sessionId: string }
+  | { kind: typeof BindingKind.IMSession; platform: string; conversationId: string; sessionId?: string }
+  | { kind: typeof BindingKind.SessionKey; sessionKey: string };
+
+/** Minimal ScheduledTask shape needed for inference (avoids importing renderer types) */
+interface InferableTask {
+  sessionKey?: string | null;
+  delivery?: { mode?: string; channel?: string };
+  agentId?: string | null;
+}
+
+/**
+ * Infer origin and binding from a ScheduledTask's wire fields.
+ * Used for backward compatibility with tasks that have no stored metadata.
+ * Pure function — no side effects.
+ */
+export function inferOriginAndBinding(task: InferableTask): {
+  origin: TaskOrigin;
+  binding: ExecutionBinding;
+} {
+  const sk = (task.sessionKey ?? '').trim();
+
+  // 1. Managed session key: "agent:main:lobsterai:{sessionId}"
+  if (sk && isManagedSessionKey(sk)) {
+    const parsed = parseManagedSessionKey(sk);
+    if (parsed) {
+      const channel = task.delivery?.channel;
+      const isIMChannel = task.delivery?.mode === DeliveryMode.Announce
+        && typeof channel === 'string'
+        && channel.length > 0
+        && channel !== DeliveryChannel.Last;
+
+      if (isIMChannel) {
+        return {
+          origin: { kind: OriginKind.IM, platform: channel!, conversationId: '' },
+          binding: {
+            kind: BindingKind.IMSession,
+            platform: channel!,
+            conversationId: '',
+            sessionId: parsed.sessionId,
+          },
+        };
+      }
+
+      return {
+        origin: { kind: OriginKind.Cowork, sessionId: parsed.sessionId },
+        binding: { kind: BindingKind.UISession, sessionId: parsed.sessionId },
+      };
+    }
+  }
+
+  // 2. Channel session key: "agent:{agentId}:{platform}:{conversationId}"
+  if (sk) {
+    const channelInfo = parseChannelSessionKey(sk);
+    if (channelInfo) {
+      return {
+        origin: { kind: OriginKind.IM, platform: channelInfo.platform, conversationId: channelInfo.conversationId },
+        binding: {
+          kind: BindingKind.IMSession,
+          platform: channelInfo.platform,
+          conversationId: channelInfo.conversationId,
+        },
+      };
+    }
+
+    // 2b. Has sessionKey but unknown format → session_key binding
+    return {
+      origin: { kind: OriginKind.Cowork, sessionId: '' },
+      binding: { kind: BindingKind.SessionKey, sessionKey: sk },
+    };
+  }
+
+  // 3. No sessionKey → manual origin
+  return {
+    origin: { kind: OriginKind.Manual },
+    binding: { kind: BindingKind.NewSession },
+  };
+}
diff --git a/src/scheduled-task/policies/coworkPolicy.ts b/src/scheduled-task/policies/coworkPolicy.ts
new file mode 100644
--- /dev/null
+++ b/src/scheduled-task/policies/coworkPolicy.ts
@@ -0,0 +1,49 @@
+import type { TaskOrigin, ExecutionBinding } from '../origin';
+import type { TaskPolicy, PolicyTaskModel, PolicyTaskInput, PolicyDelivery, WireBinding } from './types';
+import { buildManagedSessionKey } from '../../main/libs/openclawChannelSessionSync';
+import { OriginKind, BindingKind, SessionTarget, WakeMode, DeliveryMode, DeliveryChannel, RunBehavior } from '../constants';
+
+export class CoworkTaskPolicy implements TaskPolicy {
+  readonly kind = OriginKind.Cowork;
+
+  getCreateDefaults(origin: TaskOrigin): Partial<PolicyTaskInput> {
+    if (origin.kind !== OriginKind.Cowork) {
+      throw new Error('Invalid origin for CoworkTaskPolicy');
+    }
+    return {
+      sessionTarget: SessionTarget.Main,
+      wakeMode: WakeMode.Now,
+      delivery: { mode: DeliveryMode.Announce, channel: DeliveryChannel.Last },
+    };
+  }
+
+  normalizeDraft(draft: PolicyTaskModel): PolicyTaskModel {
+    return draft;
+  }
+
+  onDeliveryChanged(draft: PolicyTaskModel, newDelivery: PolicyDelivery): PolicyTaskModel {
+    // Cowork tasks: delivery change does NOT affect binding (always bound to original session)
+    return { ...draft, delivery: newDelivery };
+  }
+
+  toWireBinding(binding: ExecutionBinding): WireBinding {
+    if (binding.kind === BindingKind.UISession) {
+      return { sessionTarget: SessionTarget.Main, sessionKey: buildManagedSessionKey(binding.sessionId) };
+    }
+    if (binding.kind === BindingKind.SessionKey) {
+      return { sessionTarget: SessionTarget.Isolated, sessionKey: binding.sessionKey };
+    }
+    return { sessionTarget: SessionTarget.Main, sessionKey: null };
+  }
+
+  describeRunBehavior(task: PolicyTaskModel): string {
+    if (task.binding.kind === BindingKind.UISession) {
+      return RunBehavior.uiSession;
+    }
+    return RunBehavior.newSession;
+  }
+
+  getReadonlyFields(): string[] {
+    return ['origin'];
+  }
+}
diff --git a/src/scheduled-task/policies/imPolicy.ts b/src/scheduled-task/policies/imPolicy.ts
new file mode 100644
--- /dev/null
+++ b/src/scheduled-task/policies/imPolicy.ts
@@ -0,0 +1,67 @@
+import type { TaskOrigin, ExecutionBinding } from '../origin';
+import type { TaskPolicy, PolicyTaskModel, PolicyTaskInput, PolicyDelivery, WireBinding } from './types';
+import { buildManagedSessionKey } from '../../main/libs/openclawChannelSessionSync';
+import { OriginKind, BindingKind, SessionTarget, WakeMode, DeliveryMode, RunBehavior } from '../constants';
+
+export class IMTaskPolicy implements TaskPolicy {
+  readonly kind = OriginKind.IM;
+
+  getCreateDefaults(origin: TaskOrigin): Partial<PolicyTaskInput> {
+    if (origin.kind !== OriginKind.IM) {
+      throw new Error('Invalid origin for IMTaskPolicy');
+    }
+    return {
+      sessionTarget: SessionTarget.Main,
+      wakeMode: WakeMode.Now,
+      delivery: { mode: DeliveryMode.Announce, channel: origin.platform },
+    };
+  }
+
+  normalizeDraft(draft: PolicyTaskModel): PolicyTaskModel {
+    if (draft.binding.kind === BindingKind.IMSession
+        && draft.delivery.mode === DeliveryMode.Announce
+        && draft.delivery.channel !== draft.binding.platform) {
+      return {
+        ...draft,
+        delivery: { ...draft.delivery, channel: draft.binding.platform },
+      };
+    }
+    return draft;
+  }
+
+  onDeliveryChanged(draft: PolicyTaskModel, newDelivery: PolicyDelivery): PolicyTaskModel {
+    if (newDelivery.mode === DeliveryMode.None || newDelivery.mode === DeliveryMode.Webhook) {
+      return { ...draft, delivery: newDelivery, binding: { kind: BindingKind.NewSession } };
+    }
+    if (newDelivery.mode === DeliveryMode.Announce && newDelivery.channel) {
+      return {
+        ...draft,
+        delivery: newDelivery,
+        binding: {
+          kind: BindingKind.IMSession,
+          platform: newDelivery.channel,
+          conversationId: draft.binding.kind === BindingKind.IMSession ? draft.binding.conversationId : '',
+        },
+      };
+    }
+    return { ...draft, delivery: newDelivery };
+  }
+
+  toWireBinding(binding: ExecutionBinding): WireBinding {
+    if (binding.kind === BindingKind.IMSession && binding.sessionId) {
+      return { sessionTarget: SessionTarget.Main, sessionKey: buildManagedSessionKey(binding.sessionId) };
+    }
+    return { sessionTarget: SessionTarget.Main, sessionKey: null };
+  }
+
+  describeRunBehavior(task: PolicyTaskModel): string {
+    if (task.binding.kind === BindingKind.IMSession) {
+      return RunBehavior.imSession(task.binding.platform);
+    }
+    return RunBehavior.newSession;
+  }
+
+  getReadonlyFields(): string[] {
+    return ['origin'];
+  }
+}
diff --git a/src/scheduled-task/policies/index.ts b/src/scheduled-task/policies/index.ts
new file mode 100644
--- /dev/null
+++ b/src/scheduled-task/policies/index.ts
@@ -0,0 +1,6 @@
+export { type TaskPolicy, type PolicyTaskModel, type PolicyTaskInput, type PolicyDelivery, type WireBinding } from './types';
+export { LegacyTaskPolicy } from './legacyPolicy';
+export { IMTaskPolicy } from './imPolicy';
+export { CoworkTaskPolicy } from './coworkPolicy';
+export { ManualTaskPolicy } from './manualPolicy';
+export { TaskPolicyRegistry, taskPolicyRegistry } from './registry';
diff --git a/src/scheduled-task/policies/legacyPolicy.ts b/src/scheduled-task/policies/legacyPolicy.ts
new file mode 100644
--- /dev/null
+++ b/src/scheduled-task/policies/legacyPolicy.ts
@@ -0,0 +1,51 @@
+import type { ExecutionBinding } from '../origin';
+import type { TaskPolicy, PolicyTaskModel, PolicyTaskInput, PolicyDelivery, WireBinding } from './types';
+import { OriginKind, BindingKind, SessionTarget, WakeMode, DeliveryMode, DeliveryChannel, RunBehavior } from '../constants';
+
+export class LegacyTaskPolicy implements TaskPolicy {
+  readonly kind = OriginKind.Legacy;
+
+  getCreateDefaults(): Partial<PolicyTaskInput> {
+    return {
+      sessionTarget: SessionTarget.Main,
+      wakeMode: WakeMode.NextHeartbeat,
+    };
+  }
+
+  normalizeDraft(draft: PolicyTaskModel): PolicyTaskModel {
+    if (draft.delivery.mode === DeliveryMode.Announce
+        && typeof draft.delivery.channel === 'string'
+        && draft.delivery.channel.length > 0
+        && draft.delivery.channel !== DeliveryChannel.Last
+        && draft.binding.kind === BindingKind.NewSession) {
+      return {
+        ...draft,
+        binding: {
+          kind: BindingKind.IMSession,
+          platform: draft.delivery.channel,
+          conversationId: '',
+        },
+      };
+    }
+    return draft;
+  }
+
+  onDeliveryChanged(draft: PolicyTaskModel, newDelivery: PolicyDelivery): PolicyTaskModel {
+    if (newDelivery.mode === DeliveryMode.None || newDelivery.mode === DeliveryMode.Webhook) {
+      return { ...draft, delivery: newDelivery, binding: { kind: BindingKind.NewSession } };
+    }
+    return { ...draft, delivery: newDelivery };
+  }
+
+  toWireBinding(_binding: ExecutionBinding): WireBinding {
+    return { sessionTarget: SessionTarget.Main, sessionKey: null };
+  }
+
+  describeRunBehavior(_task: PolicyTaskModel): string {
+    return RunBehavior.newSession;
+  }
+
+  getReadonlyFields(): string[] {
+    return ['origin'];
+  }
+}
diff --git a/src/scheduled-task/policies/manualPolicy.ts b/src/scheduled-task/policies/manualPolicy.ts
new file mode 100644
--- /dev/null
+++ b/src/scheduled-task/policies/manualPolicy.ts
@@ -0,0 +1,90 @@
+import type { ExecutionBinding } from '../origin';
+import type { TaskPolicy, PolicyTaskModel, PolicyTaskInput, PolicyDelivery, WireBinding } from './types';
+import { buildManagedSessionKey } from '../../main/libs/openclawChannelSessionSync';
+import { BindingKind, SessionTarget, WakeMode, DeliveryMode, DeliveryChannel, OriginKind, RunBehavior } from '../constants';
+
+export class ManualTaskPolicy implements TaskPolicy {
+  readonly kind = OriginKind.Manual;
+
+  getCreateDefaults(): Partial<PolicyTaskInput> {
+    return {
+      sessionTarget: SessionTarget.Isolated,
+      wakeMode: WakeMode.Now,
+      delivery: { mode: DeliveryMode.Announce, channel: DeliveryChannel.Last },
+    };
+  }
+
+  normalizeDraft(draft: PolicyTaskModel): PolicyTaskModel {
+    // If IM announce channel selected but binding isn't im_session, auto-link
+    if (draft.delivery.mode === DeliveryMode.Announce
+        && typeof draft.delivery.channel === 'string'
+        && draft.delivery.channel.length > 0
+        && draft.delivery.channel !== DeliveryChannel.Last
+        && draft.binding.kind !== BindingKind.IMSession) {
+      return {
+        ...draft,
+        binding: {
+          kind: BindingKind.IMSession,
+          platform: draft.delivery.channel,
+          conversationId: '',
+        },
+      };
+    }
+    // If binding is im_session but delivery is not announce, reset
+    if (draft.binding.kind === BindingKind.IMSession
+        && draft.delivery.mode !== DeliveryMode.Announce) {
+      return { ...draft, binding: { kind: BindingKind.NewSession } };
+    }
+    return draft;
+  }
+
+  onDeliveryChanged(draft: PolicyTaskModel, newDelivery: PolicyDelivery): PolicyTaskModel {
+    if (newDelivery.mode === DeliveryMode.Announce
+        && typeof newDelivery.channel === 'string'
+        && newDelivery.channel.length > 0
+        && newDelivery.channel !== DeliveryChannel.Last) {
+      return {
+        ...draft,
+        delivery: newDelivery,
+        binding: {
+          kind: BindingKind.IMSession,
+          platform: newDelivery.channel,
+          conversationId: '',
+        },
+      };
+    }
+    if (newDelivery.mode === DeliveryMode.None || newDelivery.mode === DeliveryMode.Webhook) {
+      return { ...draft, delivery: newDelivery, binding: { kind: BindingKind.NewSession } };
+    }
+    return { ...draft, delivery: newDelivery };
+  }
+
+  toWireBinding(binding: ExecutionBinding): WireBinding {
+    switch (binding.kind) {
+      case BindingKind.NewSession:
+        return { sessionTarget: SessionTarget.Main, sessionKey: null };
+      case BindingKind.UISession:
+        return { sessionTarget: SessionTarget.Main, sessionKey: buildManagedSessionKey(binding.sessionId) };
+      case BindingKind.IMSession:
+        if (binding.sessionId) {
+          return { sessionTarget: SessionTarget.Main, sessionKey: buildManagedSessionKey(binding.sessionId) };
+        }
+        return { sessionTarget: SessionTarget.Main, sessionKey: null };
+      case BindingKind.SessionKey:
+        return { sessionTarget: SessionTarget.Isolated, sessionKey: binding.sessionKey };
+    }
+  }
+
+  describeRunBehavior(task: PolicyTaskModel): string {
+    switch (task.binding.kind) {
+      case BindingKind.NewSession: return RunBehavior.newSession;
+      case BindingKind.UISession: return RunBehavior.uiSession;
+      case BindingKind.IMSession: return RunBehavior.imSession(task.binding.platform);
+      case BindingKind.SessionKey: return RunBehavior.sessionKey;
+    }
+  }
+
+  getReadonlyFields(): string[] {
+    return [];
+  }
+}
diff --git a/src/scheduled-task/policies/registry.ts b/src/scheduled-task/policies/registry.ts
new file mode 100644
--- /dev/null
+++ b/src/scheduled-task/policies/registry.ts
@@ -0,0 +1,26 @@
+import type { TaskOrigin } from '../origin';
+import type { TaskPolicy } from './types';
+import { LegacyTaskPolicy } from './legacyPolicy';
+import { IMTaskPolicy } from './imPolicy';
+import { CoworkTaskPolicy } from './coworkPolicy';
+import { ManualTaskPolicy } from './manualPolicy';
+import { OriginKind } from '../constants';
+
+export class TaskPolicyRegistry {
+  private readonly policies: Map<string, TaskPolicy>;
+
+  constructor(policies: TaskPolicy[]) {
+    this.policies = new Map(policies.map(p => [p.kind, p]));
+  }
+
+  get(origin: TaskOrigin): TaskPolicy {
+    return this.policies.get(origin.kind) ?? this.policies.get(OriginKind.Manual)!;
+  }
+}
+
+export const taskPolicyRegistry = new TaskPolicyRegistry([
+  new LegacyTaskPolicy(),
+  new IMTaskPolicy(),
+  new CoworkTaskPolicy(),
+  new ManualTaskPolicy(),
+]);
diff --git a/src/scheduled-task/policies/types.ts b/src/scheduled-task/policies/types.ts
new file mode 100644
--- /dev/null
+++ b/src/scheduled-task/policies/types.ts
@@ -0,0 +1,72 @@
+import type { TaskOrigin, ExecutionBinding } from '../origin';
+import type { SessionTarget, WakeMode, DeliveryMode } from '../constants';
+
+export interface WireBinding {
+  sessionTarget: SessionTarget;
+  sessionKey: string | null;
+}
+
+/** Minimal delivery shape (avoids importing renderer types) */
+export interface PolicyDelivery {
+  mode: DeliveryMode;
+  channel?: string;
+  to?: string;
+  accountId?: string;
+  bestEffort?: boolean;
+}
+
+/** Minimal ScheduledTaskModel shape for policy operations */
+export interface PolicyTaskModel {
+  id: string;
+  name: string;
+  description: string;
+  enabled: boolean;
+  schedule: unknown;
+  sessionTarget: SessionTarget;
+  wakeMode: WakeMode;
+  payload: unknown;
+  delivery: PolicyDelivery;
+  agentId: string | null;
+  sessionKey: string | null;
+  state: unknown;
+  createdAt: string;
+  updatedAt: string;
+  origin: TaskOrigin;
+  binding: ExecutionBinding;
+}
+
+/** Minimal input shape for task creation defaults */
+export interface PolicyTaskInput {
+  name?: string;
+  description?: string;
+  enabled?: boolean;
+  schedule?: unknown;
+  sessionTarget?: SessionTarget;
+  wakeMode?: WakeMode;
+  payload?: unknown;
+  delivery?: PolicyDelivery;
+  agentId?: string | null;
+  sessionKey?: string | null;
+}
+
+export interface TaskPolicy {
+  readonly kind: TaskOrigin['kind'];
+
+  /** Defaults for new task creation */
+  getCreateDefaults(origin: TaskOrigin): Partial<PolicyTaskInput>;
+
+  /** Normalize draft before save (validate + auto-fill + binding consistency) */
+  normalizeDraft(draft: PolicyTaskModel): PolicyTaskModel;
+
+  /** Update binding when delivery changes */
+  onDeliveryChanged(draft: PolicyTaskModel, newDelivery: PolicyDelivery): PolicyTaskModel;
+
+  /** Map ExecutionBinding → wire format sessionTarget/sessionKey */
+  toWireBinding(binding: ExecutionBinding): WireBinding;
+
+  /** Human-readable description of run behavior */
+  describeRunBehavior(task: PolicyTaskModel): string;
+
+  /** Fields that should be read-only in the UI */
+  getReadonlyFields(): string[];
+}
diff --git a/src/common/scheduledReminderText.ts b/src/scheduled-task/reminderText.ts
rename from src/common/scheduledReminderText.ts
rename to src/scheduled-task/reminderText.ts
--- a/src/common/scheduledReminderText.ts
+++ b/src/scheduled-task/reminderText.ts

diff --git a/src/renderer/types/scheduledTask.ts b/src/scheduled-task/types.ts
rename from src/renderer/types/scheduledTask.ts
rename to src/scheduled-task/types.ts
--- a/src/renderer/types/scheduledTask.ts
+++ b/src/scheduled-task/types.ts
@@ -1,3 +1,10 @@
+import type {
+  DeliveryMode,
+  SessionTarget,
+  WakeMode,
+  TaskStatus,
+} from './constants';
+
 export interface ScheduleAt {
   kind: 'at';
   at: string;
@@ -32,14 +39,14 @@ export interface SystemEventPayload {
 export type ScheduledTaskPayload = AgentTurnPayload | SystemEventPayload;
 
 export interface ScheduledTaskDelivery {
-  mode: 'none' | 'announce' | 'webhook';
+  mode: DeliveryMode;
   channel?: string;
   to?: string;
   accountId?: string;
   bestEffort?: boolean;
 }
 
-export type TaskLastStatus = 'success' | 'error' | 'skipped' | 'running' | null;
+export type TaskLastStatus = TaskStatus | null;
 
 export interface TaskState {
   nextRunAtMs: number | null;
@@ -57,8 +64,8 @@ export interface ScheduledTask {
   description: string;
   enabled: boolean;
   schedule: Schedule;
-  sessionTarget: 'main' | 'isolated';
-  wakeMode: 'now' | 'next-heartbeat';
+  sessionTarget: SessionTarget;
+  wakeMode: WakeMode;
   payload: ScheduledTaskPayload;
   delivery: ScheduledTaskDelivery;
   agentId: string | null;
@@ -73,7 +80,7 @@ export interface ScheduledTaskRun {
   taskId: string;
   sessionId: string | null;
   sessionKey: string | null;
-  status: 'running' | 'success' | 'error' | 'skipped';
+  status: TaskStatus;
   startedAt: string;
   finishedAt: string | null;
   durationMs: number | null;
@@ -89,8 +96,8 @@ export interface ScheduledTaskInput {
   description: string;
   enabled: boolean;
   schedule: Schedule;
-  sessionTarget: 'main' | 'isolated';
-  wakeMode: 'now' | 'next-heartbeat';
+  sessionTarget: SessionTarget;
+  wakeMode: WakeMode;
   payload: ScheduledTaskPayload;
   delivery?: ScheduledTaskDelivery;
   agentId?: string | null;
@@ -111,4 +118,11 @@ export interface ScheduledTaskChannelOption {
   label: string;
 }
 
+export interface ScheduledTaskConversationOption {
+  conversationId: string;
+  platform: string;
+  coworkSessionId: string;
+  lastActiveAt: number;
+}
+
 export type ScheduledTaskViewMode = 'list' | 'create' | 'edit' | 'detail';
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
