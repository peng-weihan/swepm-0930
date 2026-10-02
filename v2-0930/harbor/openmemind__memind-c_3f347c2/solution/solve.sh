#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/memind-core/src/main/java/com/openmemind/ai/memory/core/DefaultMemory.java b/memind-core/src/main/java/com/openmemind/ai/memory/core/DefaultMemory.java
--- a/memind-core/src/main/java/com/openmemind/ai/memory/core/DefaultMemory.java
+++ b/memind-core/src/main/java/com/openmemind/ai/memory/core/DefaultMemory.java
@@ -16,6 +16,8 @@
 import com.openmemind.ai.memory.core.buffer.MemoryBuffer;
 import com.openmemind.ai.memory.core.buffer.PendingConversationBuffer;
 import com.openmemind.ai.memory.core.buffer.RecentConversationBuffer;
+import com.openmemind.ai.memory.core.builder.MemoryBuildOptions;
+import com.openmemind.ai.memory.core.builder.RerankOptions;
 import com.openmemind.ai.memory.core.data.MemoryId;
 import com.openmemind.ai.memory.core.data.MemoryItem;
 import com.openmemind.ai.memory.core.data.ToolCallStats;
@@ -35,6 +37,8 @@
 import com.openmemind.ai.memory.core.retrieval.RetrievalConfig;
 import com.openmemind.ai.memory.core.retrieval.RetrievalRequest;
 import com.openmemind.ai.memory.core.retrieval.RetrievalResult;
+import com.openmemind.ai.memory.core.retrieval.strategy.DeepStrategyConfig;
+import com.openmemind.ai.memory.core.retrieval.strategy.SimpleStrategyConfig;
 import com.openmemind.ai.memory.core.stats.ToolStatsService;
 import com.openmemind.ai.memory.core.store.MemoryStore;
 import com.openmemind.ai.memory.core.utils.TokenUtils;
@@ -71,6 +75,7 @@ public class DefaultMemory implements Memory {
     private final ToolStatsService toolStatsService;
     private final InsightLayer insightLayer;
     private final AutoCloseable lifecycle;
+    private final MemoryBuildOptions buildOptions;
     private final AtomicBoolean closed = new AtomicBoolean();
 
     public DefaultMemory(
@@ -80,7 +85,16 @@ public DefaultMemory(
             MemoryBuffer memoryBuffer,
             MemoryVector vector,
             ToolStatsService toolStatsService) {
-        this(extractor, retriever, memoryStore, memoryBuffer, vector, toolStatsService, null, null);
+        this(
+                extractor,
+                retriever,
+                memoryStore,
+                memoryBuffer,
+                vector,
+                toolStatsService,
+                null,
+                null,
+                MemoryBuildOptions.defaults());
     }
 
     public DefaultMemory(
@@ -92,6 +106,28 @@ public DefaultMemory(
             ToolStatsService toolStatsService,
             InsightLayer insightLayer,
             AutoCloseable lifecycle) {
+        this(
+                extractor,
+                retriever,
+                memoryStore,
+                memoryBuffer,
+                vector,
+                toolStatsService,
+                insightLayer,
+                lifecycle,
+                MemoryBuildOptions.defaults());
+    }
+
+    public DefaultMemory(
+            MemoryExtractionPipeline extractor,
+            MemoryRetriever retriever,
+            MemoryStore memoryStore,
+            MemoryBuffer memoryBuffer,
+            MemoryVector vector,
+            ToolStatsService toolStatsService,
+            InsightLayer insightLayer,
+            AutoCloseable lifecycle,
+            MemoryBuildOptions buildOptions) {
         this.extractor = Objects.requireNonNull(extractor, "extractor must not be null");
         this.retriever = Objects.requireNonNull(retriever, "retriever must not be null");
         this.memoryStore = Objects.requireNonNull(memoryStore, "memoryStore must not be null");
@@ -101,13 +137,14 @@ public DefaultMemory(
                 Objects.requireNonNull(toolStatsService, "toolStatsService must not be null");
         this.insightLayer = insightLayer;
         this.lifecycle = lifecycle;
+        this.buildOptions = Objects.requireNonNull(buildOptions, "buildOptions must not be null");
     }
 
     // ===== Generic extraction =====
 
     @Override
     public Mono<ExtractionResult> extract(MemoryId memoryId, RawContent content) {
-        return extract(memoryId, content, ExtractionConfig.defaults());
+        return extract(memoryId, content, defaultExtractionConfig());
     }
 
     @Override
@@ -132,7 +169,7 @@ public Mono<ExtractionResult> addMessages(
 
     @Override
     public Mono<ExtractionResult> addMessage(MemoryId memoryId, Message message) {
-        return extractor.addMessage(memoryId, message, ExtractionConfig.defaults());
+        return extractor.addMessage(memoryId, message, defaultExtractionConfig());
     }
 
     @Override
@@ -162,7 +199,15 @@ public Mono<ContextWindow> getContext(ContextRequest request) {
 
         String query = buildQueryFromRecentMessages(messages);
         return retriever
-                .retrieve(RetrievalRequest.of(request.memoryId(), query, request.strategy()))
+                .retrieve(
+                        new RetrievalRequest(
+                                request.memoryId(),
+                                query,
+                                List.of(),
+                                defaultRetrievalConfig(request.strategy()),
+                                Map.of(),
+                                null,
+                                null))
                 .map(
                         memories -> {
                             int memoriesTokens = TokenUtils.countTokens(memories.formattedResult());
@@ -173,7 +218,7 @@ public Mono<ContextWindow> getContext(ContextRequest request) {
 
     @Override
     public Mono<ExtractionResult> commit(MemoryId memoryId) {
-        return commit(memoryId, ExtractionConfig.defaults());
+        return commit(memoryId, defaultExtractionConfig());
     }
 
     @Override
@@ -237,14 +282,105 @@ private static List<Message> trimRecentMessages(List<Message> messages, int maxT
     @Override
     public Mono<RetrievalResult> retrieve(
             MemoryId memoryId, String query, RetrievalConfig.Strategy strategy) {
-        return retriever.retrieve(RetrievalRequest.of(memoryId, query, strategy));
+        return retriever.retrieve(
+                new RetrievalRequest(
+                        memoryId,
+                        query,
+                        List.of(),
+                        defaultRetrievalConfig(strategy),
+                        Map.of(),
+                        null,
+                        null));
     }
 
     @Override
     public Mono<RetrievalResult> retrieve(RetrievalRequest request) {
         return retriever.retrieve(request);
     }
 
+    private ExtractionConfig defaultExtractionConfig() {
+        var extraction = buildOptions.extraction();
+        return new ExtractionConfig(
+                extraction.insight().enabled(),
+                extraction.common().defaultScope(),
+                extraction.item().foresightEnabled(),
+                extraction.common().timeout(),
+                extraction.common().language());
+    }
+
+    private RetrievalConfig defaultRetrievalConfig(RetrievalConfig.Strategy strategy) {
+        var retrieval = buildOptions.retrieval();
+        return switch (strategy) {
+            case SIMPLE -> {
+                var base =
+                        RetrievalConfig.simple(
+                                new SimpleStrategyConfig(
+                                        retrieval.simple().keywordSearchEnabled()));
+                yield applyCache(
+                        base.withTier1(copyTier(base.tier1(), retrieval.simple().insightTopK()))
+                                .withTier2(copyTier(base.tier2(), retrieval.simple().itemTopK()))
+                                .withTier3(copyTier(base.tier3(), retrieval.simple().rawDataTopK()))
+                                .withScoring(retrieval.advanced().scoring())
+                                .withTimeout(retrieval.simple().timeout()),
+                        retrieval.common().cacheEnabled());
+            }
+            case DEEP -> {
+                var base = RetrievalConfig.deep();
+                var baseStrategy = (DeepStrategyConfig) base.strategyConfig();
+                var strategyConfig =
+                        new DeepStrategyConfig(
+                                new DeepStrategyConfig.QueryExpansionConfig(
+                                        retrieval.deep().queryExpansion().maxExpandedQueries()),
+                                new DeepStrategyConfig.SufficiencyConfig(
+                                        retrieval.deep().sufficiency().itemTopK()),
+                                baseStrategy.tier2InitTopK(),
+                                baseStrategy.bm25InitTopK(),
+                                baseStrategy.minScore());
+                var tier3 =
+                        retrieval.deep().rawDataEnabled()
+                                ? new RetrievalConfig.TierConfig(
+                                        true,
+                                        retrieval.deep().rawDataTopK(),
+                                        base.tier3().minScore(),
+                                        base.tier3().truncation())
+                                : RetrievalConfig.TierConfig.disabled();
+                yield applyCache(
+                        RetrievalConfig.deep(strategyConfig)
+                                .withTier1(copyTier(base.tier1(), retrieval.deep().insightTopK()))
+                                .withTier2(copyTier(base.tier2(), retrieval.deep().itemTopK()))
+                                .withTier3(tier3)
+                                .withRerank(toRerankConfig(retrieval.advanced().rerank()))
+                                .withScoring(retrieval.advanced().scoring())
+                                .withTimeout(retrieval.deep().timeout()),
+                        retrieval.common().cacheEnabled());
+            }
+        };
+    }
+
+    private RetrievalConfig applyCache(RetrievalConfig config, boolean enabled) {
+        return enabled ? config : config.withoutCache();
+    }
+
+    private RetrievalConfig.TierConfig copyTier(RetrievalConfig.TierConfig base, int topK) {
+        return new RetrievalConfig.TierConfig(
+                base.enabled(), topK, base.minScore(), base.truncation());
+    }
+
+    private RetrievalConfig.RerankConfig toRerankConfig(RerankOptions options) {
+        return switch (options.mode()) {
+            case DISABLED -> RetrievalConfig.RerankConfig.disabled();
+            case PURE -> RetrievalConfig.RerankConfig.pure(options.topK());
+            case BLEND ->
+                    new RetrievalConfig.RerankConfig(
+                            true,
+                            true,
+                            options.top3Weight(),
+                            options.top10Weight(),
+                            options.otherWeight(),
+                            options.topK());
+        };
+    }
+
     @Override
     public Mono<Void> deleteItems(MemoryId memoryId, Collection<Long> itemIds) {
         var requestedIds = List.copyOf(itemIds);
diff --git a/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/DeepRetrievalOptions.java b/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/DeepRetrievalOptions.java
new file mode 100644
--- /dev/null
+++ b/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/DeepRetrievalOptions.java
@@ -0,0 +1,37 @@
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
+package com.openmemind.ai.memory.core.builder;
+
+import java.time.Duration;
+
+public record DeepRetrievalOptions(
+        Duration timeout,
+        int insightTopK,
+        int itemTopK,
+        boolean rawDataEnabled,
+        int rawDataTopK,
+        QueryExpansionOptions queryExpansion,
+        SufficiencyOptions sufficiency) {
+
+    public static DeepRetrievalOptions defaults() {
+        return new DeepRetrievalOptions(
+                Duration.ofSeconds(120),
+                5,
+                50,
+                false,
+                0,
+                QueryExpansionOptions.defaults(),
+                SufficiencyOptions.defaults());
+    }
+}
diff --git a/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/DefaultMemoryBuilder.java b/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/DefaultMemoryBuilder.java
--- a/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/DefaultMemoryBuilder.java
+++ b/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/DefaultMemoryBuilder.java
@@ -136,7 +136,8 @@ public Memory build() {
                         context.chatClientRegistry().defaultClient(),
                         context.memoryStore(),
                         context.memoryBuffer(),
-                        extractionAssembly.lifecycle()));
+                        extractionAssembly.lifecycle()),
+                options);
     }
 
     MemoryBuildOptions buildOptions() {
diff --git a/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/ExtractionCommonOptions.java b/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/ExtractionCommonOptions.java
new file mode 100644
--- /dev/null
+++ b/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/ExtractionCommonOptions.java
@@ -0,0 +1,26 @@
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
+package com.openmemind.ai.memory.core.builder;
+
+import com.openmemind.ai.memory.core.data.enums.MemoryScope;
+import com.openmemind.ai.memory.core.prompt.PromptResult;
+import java.time.Duration;
+
+public record ExtractionCommonOptions(MemoryScope defaultScope, Duration timeout, String language) {
+
+    public static ExtractionCommonOptions defaults() {
+        return new ExtractionCommonOptions(
+                MemoryScope.USER, Duration.ofMinutes(10), PromptResult.DEFAULT_LANGUAGE);
+    }
+}
diff --git a/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/ExtractionOptions.java b/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/ExtractionOptions.java
new file mode 100644
--- /dev/null
+++ b/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/ExtractionOptions.java
@@ -0,0 +1,29 @@
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
+package com.openmemind.ai.memory.core.builder;
+
+public record ExtractionOptions(
+        ExtractionCommonOptions common,
+        RawDataExtractionOptions rawdata,
+        ItemExtractionOptions item,
+        InsightExtractionOptions insight) {
+
+    public static ExtractionOptions defaults() {
+        return new ExtractionOptions(
+                ExtractionCommonOptions.defaults(),
+                RawDataExtractionOptions.defaults(),
+                ItemExtractionOptions.defaults(),
+                InsightExtractionOptions.defaults());
+    }
+}
diff --git a/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/InsightExtractionOptions.java b/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/InsightExtractionOptions.java
new file mode 100644
--- /dev/null
+++ b/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/InsightExtractionOptions.java
@@ -0,0 +1,25 @@
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
+package com.openmemind.ai.memory.core.builder;
+
+import com.openmemind.ai.memory.core.extraction.insight.scheduler.InsightBuildConfig;
+
+public record InsightExtractionOptions(boolean enabled, InsightBuildConfig build) {
+
+    private static final InsightBuildConfig DEFAULT_BUILD = new InsightBuildConfig(3, 2, 8, 2);
+
+    public static InsightExtractionOptions defaults() {
+        return new InsightExtractionOptions(true, DEFAULT_BUILD);
+    }
+}
diff --git a/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/ItemExtractionOptions.java b/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/ItemExtractionOptions.java
new file mode 100644
--- /dev/null
+++ b/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/ItemExtractionOptions.java
@@ -0,0 +1,21 @@
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
+package com.openmemind.ai.memory.core.builder;
+
+public record ItemExtractionOptions(boolean foresightEnabled) {
+
+    public static ItemExtractionOptions defaults() {
+        return new ItemExtractionOptions(false);
+    }
+}
diff --git a/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/MemoryBuildOptions.java b/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/MemoryBuildOptions.java
--- a/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/MemoryBuildOptions.java
+++ b/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/MemoryBuildOptions.java
@@ -13,34 +13,19 @@
  */
 package com.openmemind.ai.memory.core.builder;
 
-import com.openmemind.ai.memory.core.extraction.context.CommitDetectorConfig;
-import com.openmemind.ai.memory.core.extraction.insight.scheduler.InsightBuildConfig;
-import com.openmemind.ai.memory.core.extraction.rawdata.chunk.ConversationChunkingConfig;
-import com.openmemind.ai.memory.core.extraction.rawdata.chunk.ConversationChunkingConfig.ConversationSegmentStrategy;
 import java.util.Objects;
 
 /**
  * Core-owned runtime defaults used during memory bootstrap.
  */
 public final class MemoryBuildOptions {
 
-    private static final ConversationChunkingConfig DEFAULT_CONVERSATION_CHUNKING =
-            new ConversationChunkingConfig(10, ConversationSegmentStrategy.FIXED_SIZE, 20);
-    private static final InsightBuildConfig DEFAULT_INSIGHT_BUILD =
-            new InsightBuildConfig(3, 2, 8, 2);
-    private static final CommitDetectorConfig DEFAULT_BOUNDARY_DETECTOR =
-            CommitDetectorConfig.defaults();
-
-    private final ConversationChunkingConfig conversationChunking;
-    private final InsightBuildConfig insightBuild;
-    private final CommitDetectorConfig boundaryDetector;
+    private final ExtractionOptions extraction;
+    private final RetrievalOptions retrieval;
 
     private MemoryBuildOptions(Builder builder) {
-        this.conversationChunking =
-                Objects.requireNonNull(builder.conversationChunking, "conversationChunking");
-        this.insightBuild = Objects.requireNonNull(builder.insightBuild, "insightBuild");
-        this.boundaryDetector =
-                Objects.requireNonNull(builder.boundaryDetector, "boundaryDetector");
+        this.extraction = Objects.requireNonNull(builder.extraction, "extraction");
+        this.retrieval = Objects.requireNonNull(builder.retrieval, "retrieval");
     }
 
     public static Builder builder() {
@@ -51,39 +36,28 @@ public static MemoryBuildOptions defaults() {
         return builder().build();
     }
 
-    public ConversationChunkingConfig conversationChunking() {
-        return conversationChunking;
-    }
-
-    public InsightBuildConfig insightBuild() {
-        return insightBuild;
+    public ExtractionOptions extraction() {
+        return extraction;
     }
 
-    public CommitDetectorConfig boundaryDetector() {
-        return boundaryDetector;
+    public RetrievalOptions retrieval() {
+        return retrieval;
     }
 
     public static final class Builder {
 
-        private ConversationChunkingConfig conversationChunking = DEFAULT_CONVERSATION_CHUNKING;
-        private InsightBuildConfig insightBuild = DEFAULT_INSIGHT_BUILD;
-        private CommitDetectorConfig boundaryDetector = DEFAULT_BOUNDARY_DETECTOR;
+        private ExtractionOptions extraction = ExtractionOptions.defaults();
+        private RetrievalOptions retrieval = RetrievalOptions.defaults();
 
         private Builder() {}
 
-        public Builder conversationChunking(ConversationChunkingConfig conversationChunking) {
-            this.conversationChunking =
-                    Objects.requireNonNull(conversationChunking, "conversationChunking");
-            return this;
-        }
-
-        public Builder insightBuild(InsightBuildConfig insightBuild) {
-            this.insightBuild = Objects.requireNonNull(insightBuild, "insightBuild");
+        public Builder extraction(ExtractionOptions extraction) {
+            this.extraction = Objects.requireNonNull(extraction, "extraction");
             return this;
         }
 
-        public Builder boundaryDetector(CommitDetectorConfig boundaryDetector) {
-            this.boundaryDetector = Objects.requireNonNull(boundaryDetector, "boundaryDetector");
+        public Builder retrieval(RetrievalOptions retrieval) {
+            this.retrieval = Objects.requireNonNull(retrieval, "retrieval");
             return this;
         }
 
diff --git a/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/MemoryExtractionAssembler.java b/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/MemoryExtractionAssembler.java
--- a/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/MemoryExtractionAssembler.java
+++ b/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/MemoryExtractionAssembler.java
@@ -114,7 +114,7 @@ MemoryExtractionAssembly assemble(MemoryAssemblyContext context) {
                         insightTreeReorganizer,
                         context.memoryVector(),
                         IdUtils.snowflake(),
-                        context.options().insightBuild(),
+                        context.options().extraction().insight().build(),
                         null);
         InsightLayer insightLayer =
                 new InsightLayer(
@@ -124,7 +124,7 @@ MemoryExtractionAssembly assemble(MemoryAssemblyContext context) {
 
         ContextCommitDetector contextCommitDetector =
                 new LlmContextCommitDetector(
-                        context.options().boundaryDetector(),
+                        context.options().extraction().rawdata().commitDetection(),
                         registry.resolve(ChatClientSlot.CONTEXT_COMMIT_DETECTOR),
                         context.promptRegistry());
         MemoryExtractionPipeline pipeline =
@@ -155,7 +155,7 @@ private List<RawContentProcessor<?>> createProcessors(
                 new ConversationContentProcessor(
                         conversationChunker,
                         llmConversationChunker,
-                        options.conversationChunking(),
+                        options.extraction().rawdata().chunking(),
                         captionGenerator,
                         null);
         ToolCallContentProcessor toolCallProcessor =
diff --git a/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/QueryExpansionOptions.java b/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/QueryExpansionOptions.java
new file mode 100644
--- /dev/null
+++ b/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/QueryExpansionOptions.java
@@ -0,0 +1,21 @@
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
+package com.openmemind.ai.memory.core.builder;
+
+public record QueryExpansionOptions(int maxExpandedQueries) {
+
+    public static QueryExpansionOptions defaults() {
+        return new QueryExpansionOptions(3);
+    }
+}
diff --git a/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/RawDataExtractionOptions.java b/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/RawDataExtractionOptions.java
new file mode 100644
--- /dev/null
+++ b/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/RawDataExtractionOptions.java
@@ -0,0 +1,26 @@
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
+package com.openmemind.ai.memory.core.builder;
+
+import com.openmemind.ai.memory.core.extraction.context.CommitDetectorConfig;
+import com.openmemind.ai.memory.core.extraction.rawdata.chunk.ConversationChunkingConfig;
+
+public record RawDataExtractionOptions(
+        ConversationChunkingConfig chunking, CommitDetectorConfig commitDetection) {
+
+    public static RawDataExtractionOptions defaults() {
+        return new RawDataExtractionOptions(
+                ConversationChunkingConfig.DEFAULT, CommitDetectorConfig.defaults());
+    }
+}
diff --git a/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/RerankMode.java b/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/RerankMode.java
new file mode 100644
--- /dev/null
+++ b/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/RerankMode.java
@@ -0,0 +1,20 @@
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
+package com.openmemind.ai.memory.core.builder;
+
+public enum RerankMode {
+    DISABLED,
+    PURE,
+    BLEND
+}
diff --git a/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/RerankOptions.java b/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/RerankOptions.java
new file mode 100644
--- /dev/null
+++ b/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/RerankOptions.java
@@ -0,0 +1,22 @@
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
+package com.openmemind.ai.memory.core.builder;
+
+public record RerankOptions(
+        RerankMode mode, int topK, double top3Weight, double top10Weight, double otherWeight) {
+
+    public static RerankOptions defaults() {
+        return new RerankOptions(RerankMode.PURE, 10, 0.75, 0.60, 0.40);
+    }
+}
diff --git a/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/RetrievalAdvancedOptions.java b/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/RetrievalAdvancedOptions.java
new file mode 100644
--- /dev/null
+++ b/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/RetrievalAdvancedOptions.java
@@ -0,0 +1,23 @@
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
+package com.openmemind.ai.memory.core.builder;
+
+import com.openmemind.ai.memory.core.retrieval.scoring.ScoringConfig;
+
+public record RetrievalAdvancedOptions(RerankOptions rerank, ScoringConfig scoring) {
+
+    public static RetrievalAdvancedOptions defaults() {
+        return new RetrievalAdvancedOptions(RerankOptions.defaults(), ScoringConfig.defaults());
+    }
+}
diff --git a/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/RetrievalCommonOptions.java b/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/RetrievalCommonOptions.java
new file mode 100644
--- /dev/null
+++ b/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/RetrievalCommonOptions.java
@@ -0,0 +1,21 @@
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
+package com.openmemind.ai.memory.core.builder;
+
+public record RetrievalCommonOptions(boolean cacheEnabled) {
+
+    public static RetrievalCommonOptions defaults() {
+        return new RetrievalCommonOptions(true);
+    }
+}
diff --git a/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/RetrievalOptions.java b/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/RetrievalOptions.java
new file mode 100644
--- /dev/null
+++ b/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/RetrievalOptions.java
@@ -0,0 +1,29 @@
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
+package com.openmemind.ai.memory.core.builder;
+
+public record RetrievalOptions(
+        RetrievalCommonOptions common,
+        SimpleRetrievalOptions simple,
+        DeepRetrievalOptions deep,
+        RetrievalAdvancedOptions advanced) {
+
+    public static RetrievalOptions defaults() {
+        return new RetrievalOptions(
+                RetrievalCommonOptions.defaults(),
+                SimpleRetrievalOptions.defaults(),
+                DeepRetrievalOptions.defaults(),
+                RetrievalAdvancedOptions.defaults());
+    }
+}
diff --git a/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/SimpleRetrievalOptions.java b/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/SimpleRetrievalOptions.java
new file mode 100644
--- /dev/null
+++ b/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/SimpleRetrievalOptions.java
@@ -0,0 +1,28 @@
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
+package com.openmemind.ai.memory.core.builder;
+
+import java.time.Duration;
+
+public record SimpleRetrievalOptions(
+        Duration timeout,
+        int insightTopK,
+        int itemTopK,
+        int rawDataTopK,
+        boolean keywordSearchEnabled) {
+
+    public static SimpleRetrievalOptions defaults() {
+        return new SimpleRetrievalOptions(Duration.ofSeconds(10), 5, 15, 5, true);
+    }
+}
diff --git a/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/SufficiencyOptions.java b/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/SufficiencyOptions.java
new file mode 100644
--- /dev/null
+++ b/memind-core/src/main/java/com/openmemind/ai/memory/core/builder/SufficiencyOptions.java
@@ -0,0 +1,21 @@
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
+package com.openmemind.ai.memory.core.builder;
+
+public record SufficiencyOptions(int itemTopK) {
+
+    public static SufficiencyOptions defaults() {
+        return new SufficiencyOptions(20);
+    }
+}
diff --git a/memind-core/src/main/java/com/openmemind/ai/memory/core/retrieval/strategy/DeepStrategyConfig.java b/memind-core/src/main/java/com/openmemind/ai/memory/core/retrieval/strategy/DeepStrategyConfig.java
--- a/memind-core/src/main/java/com/openmemind/ai/memory/core/retrieval/strategy/DeepStrategyConfig.java
+++ b/memind-core/src/main/java/com/openmemind/ai/memory/core/retrieval/strategy/DeepStrategyConfig.java
@@ -70,10 +70,9 @@ public DeepStrategyConfig withMinScore(double minScore) {
     }
 
     /** Multi-query expansion */
-    public record QueryExpansionConfig(
-            int maxExpandedQueries, double originalWeight, double expandedWeight) {
+    public record QueryExpansionConfig(int maxExpandedQueries) {
         public static QueryExpansionConfig defaults() {
-            return new QueryExpansionConfig(3, 2.0, 1.0);
+            return new QueryExpansionConfig(3);
         }
     }
 
diff --git a/memind-examples/memind-example-java/src/main/java/com/openmemind/ai/memory/example/java/agent/AgentScopeMemoryExample.java b/memind-examples/memind-example-java/src/main/java/com/openmemind/ai/memory/example/java/agent/AgentScopeMemoryExample.java
--- a/memind-examples/memind-example-java/src/main/java/com/openmemind/ai/memory/example/java/agent/AgentScopeMemoryExample.java
+++ b/memind-examples/memind-example-java/src/main/java/com/openmemind/ai/memory/example/java/agent/AgentScopeMemoryExample.java
@@ -14,7 +14,13 @@
 package com.openmemind.ai.memory.example.java.agent;
 
 import com.openmemind.ai.memory.core.Memory;
+import com.openmemind.ai.memory.core.builder.ExtractionCommonOptions;
+import com.openmemind.ai.memory.core.builder.ExtractionOptions;
+import com.openmemind.ai.memory.core.builder.InsightExtractionOptions;
+import com.openmemind.ai.memory.core.builder.ItemExtractionOptions;
 import com.openmemind.ai.memory.core.builder.MemoryBuildOptions;
+import com.openmemind.ai.memory.core.builder.RawDataExtractionOptions;
+import com.openmemind.ai.memory.core.builder.RetrievalOptions;
 import com.openmemind.ai.memory.core.data.DefaultMemoryId;
 import com.openmemind.ai.memory.core.extraction.ExtractionConfig;
 import com.openmemind.ai.memory.core.extraction.insight.scheduler.InsightBuildConfig;
@@ -108,10 +114,21 @@ private static void retrieveAgentMemory(
     }
 
     private static MemoryBuildOptions agentOptions() {
-        InsightBuildConfig defaults = MemoryBuildOptions.defaults().insightBuild();
+        InsightBuildConfig defaults = MemoryBuildOptions.defaults().extraction().insight().build();
         return MemoryBuildOptions.builder()
-                .insightBuild(
-                        new InsightBuildConfig(2, 2, defaults.concurrency(), defaults.maxRetries()))
+                .extraction(
+                        new ExtractionOptions(
+                                ExtractionCommonOptions.defaults(),
+                                RawDataExtractionOptions.defaults(),
+                                ItemExtractionOptions.defaults(),
+                                new InsightExtractionOptions(
+                                        true,
+                                        new InsightBuildConfig(
+                                                2,
+                                                2,
+                                                defaults.concurrency(),
+                                                defaults.maxRetries()))))
+                .retrieval(RetrievalOptions.defaults())
                 .build();
     }
 
diff --git a/memind-examples/memind-example-java/src/main/java/com/openmemind/ai/memory/example/java/insight/InsightTreeExample.java b/memind-examples/memind-example-java/src/main/java/com/openmemind/ai/memory/example/java/insight/InsightTreeExample.java
--- a/memind-examples/memind-example-java/src/main/java/com/openmemind/ai/memory/example/java/insight/InsightTreeExample.java
+++ b/memind-examples/memind-example-java/src/main/java/com/openmemind/ai/memory/example/java/insight/InsightTreeExample.java
@@ -14,7 +14,13 @@
 package com.openmemind.ai.memory.example.java.insight;
 
 import com.openmemind.ai.memory.core.Memory;
+import com.openmemind.ai.memory.core.builder.ExtractionCommonOptions;
+import com.openmemind.ai.memory.core.builder.ExtractionOptions;
+import com.openmemind.ai.memory.core.builder.InsightExtractionOptions;
+import com.openmemind.ai.memory.core.builder.ItemExtractionOptions;
 import com.openmemind.ai.memory.core.builder.MemoryBuildOptions;
+import com.openmemind.ai.memory.core.builder.RawDataExtractionOptions;
+import com.openmemind.ai.memory.core.builder.RetrievalOptions;
 import com.openmemind.ai.memory.core.data.DefaultMemoryId;
 import com.openmemind.ai.memory.core.extraction.ExtractionConfig;
 import com.openmemind.ai.memory.core.extraction.insight.scheduler.InsightBuildConfig;
@@ -85,10 +91,21 @@ private static void run(Memory memory, ExampleDataLoader loader) {
     }
 
     private static MemoryBuildOptions insightOptions() {
-        InsightBuildConfig defaults = MemoryBuildOptions.defaults().insightBuild();
+        InsightBuildConfig defaults = MemoryBuildOptions.defaults().extraction().insight().build();
         return MemoryBuildOptions.builder()
-                .insightBuild(
-                        new InsightBuildConfig(2, 2, defaults.concurrency(), defaults.maxRetries()))
+                .extraction(
+                        new ExtractionOptions(
+                                ExtractionCommonOptions.defaults(),
+                                RawDataExtractionOptions.defaults(),
+                                ItemExtractionOptions.defaults(),
+                                new InsightExtractionOptions(
+                                        true,
+                                        new InsightBuildConfig(
+                                                2,
+                                                2,
+                                                defaults.concurrency(),
+                                                defaults.maxRetries()))))
+                .retrieval(RetrievalOptions.defaults())
                 .build();
     }
 
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
