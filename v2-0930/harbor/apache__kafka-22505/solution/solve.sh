#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/core/src/main/scala/kafka/raft/KafkaRaftManager.scala b/core/src/main/scala/kafka/raft/KafkaRaftManager.scala
--- a/core/src/main/scala/kafka/raft/KafkaRaftManager.scala
+++ b/core/src/main/scala/kafka/raft/KafkaRaftManager.scala
@@ -22,6 +22,7 @@ import java.nio.file.Files
 import java.nio.file.Paths
 import java.util.{OptionalInt, Collection => JCollection, Map => JMap}
 import java.util.concurrent.CompletableFuture
+import java.util.concurrent.CompletionStage
 import kafka.server.KafkaConfig
 import kafka.utils.Logging
 import org.apache.kafka.clients.{ApiVersions, ManualMetadataUpdater, MetadataRecoveryStrategy, NetworkClient}
@@ -157,7 +158,7 @@ class KafkaRaftManager[T](
     header: RequestHeader,
     request: ApiMessage,
     createdTimeMs: Long
-  ): CompletableFuture[ApiMessage] = {
+  ): CompletionStage[ApiMessage] = {
     clientDriver.handleRequest(context, header, request, createdTimeMs)
   }
 
diff --git a/core/src/main/scala/kafka/server/ControllerApis.scala b/core/src/main/scala/kafka/server/ControllerApis.scala
--- a/core/src/main/scala/kafka/server/ControllerApis.scala
+++ b/core/src/main/scala/kafka/server/ControllerApis.scala
@@ -682,10 +682,14 @@ class ControllerApis(
     }
   }
 
-  private def handleRaftRequest(request: Request,
-                                buildResponse: ApiMessage => AbstractResponse): CompletableFuture[Unit] = {
+  private def handleRaftRequest(
+    request: Request,
+    buildResponse: ApiMessage => AbstractResponse
+  ): CompletableFuture[Unit] = {
     val requestBody = request.body(classOf[AbstractRequest])
-    val future = raftManager.handleRequest(request.context, request.header, requestBody.data, time.milliseconds())
+    val future = raftManager
+      .handleRequest(request.context, request.header, requestBody.data, time.milliseconds())
+      .toCompletableFuture
     future.handle[Unit] { (responseData, exception) =>
       val response = if (exception != null) {
         requestBody.getErrorResponse(exception)
diff --git a/raft/src/main/java/org/apache/kafka/raft/EpochState.java b/raft/src/main/java/org/apache/kafka/raft/EpochState.java
--- a/raft/src/main/java/org/apache/kafka/raft/EpochState.java
+++ b/raft/src/main/java/org/apache/kafka/raft/EpochState.java
@@ -16,10 +16,10 @@
  */
 package org.apache.kafka.raft;
 
-import java.io.Closeable;
 import java.util.Optional;
 
-public interface EpochState extends Closeable {
+public sealed interface EpochState extends AutoCloseable
+    permits LeaderState, FollowerState, UnattachedState, ResignedState, NomineeState {
 
     default Optional<LogOffsetMetadata> highWatermark() {
         return Optional.empty();
@@ -48,6 +48,11 @@ default Optional<LogOffsetMetadata> highWatermark() {
      */
     int epoch();
 
+    /**
+     * Get the current leader and epoch.
+     */
+    LeaderAndEpoch leaderAndEpoch();
+
     /**
      * Returns the known endpoints for the leader.
      *
@@ -61,8 +66,7 @@ default Optional<LogOffsetMetadata> highWatermark() {
     String name();
 
     /**
-     * Since all subclasses implement the Closeable interface while none throw any IOException,
-     * this implementation is provided to eliminate the need for exception handling in the close operation.
+     * Epoch states should be auto closeable but shouldn't throw any checked exceptions.
      */
     @Override
     void close();
diff --git a/raft/src/main/java/org/apache/kafka/raft/FollowerState.java b/raft/src/main/java/org/apache/kafka/raft/FollowerState.java
--- a/raft/src/main/java/org/apache/kafka/raft/FollowerState.java
+++ b/raft/src/main/java/org/apache/kafka/raft/FollowerState.java
@@ -26,10 +26,11 @@
 import org.slf4j.Logger;
 
 import java.util.Optional;
+import java.util.OptionalInt;
 import java.util.OptionalLong;
 import java.util.Set;
 
-public class FollowerState implements EpochState {
+public final class FollowerState implements EpochState {
     private final Logger log;
 
     private final int fetchTimeoutMs;
@@ -91,6 +92,11 @@ public int epoch() {
         return epoch;
     }
 
+    @Override
+    public LeaderAndEpoch leaderAndEpoch() {
+        return new LeaderAndEpoch(OptionalInt.of(leaderId), epoch);
+    }
+
     @Override
     public Endpoints leaderEndpoints() {
         return leaderEndpoints;
diff --git a/raft/src/main/java/org/apache/kafka/raft/KafkaNetworkChannel.java b/raft/src/main/java/org/apache/kafka/raft/KafkaNetworkChannel.java
--- a/raft/src/main/java/org/apache/kafka/raft/KafkaNetworkChannel.java
+++ b/raft/src/main/java/org/apache/kafka/raft/KafkaNetworkChannel.java
@@ -53,6 +53,8 @@
 import java.util.Collection;
 import java.util.List;
 import java.util.Queue;
+import java.util.concurrent.CompletableFuture;
+import java.util.concurrent.CompletionStage;
 import java.util.concurrent.ConcurrentLinkedQueue;
 import java.util.concurrent.atomic.AtomicInteger;
 
@@ -116,29 +118,35 @@ public int newCorrelationId() {
     }
 
     @Override
-    public void send(RaftRequest.Outbound request) {
+    public CompletionStage<RaftResponse.Inbound> send(RaftRequest.Outbound request) {
         Node node = request.destination();
         if (node != null) {
-            requestThread.sendRequest(new RequestAndCompletionHandler(
-                request.createdTimeMs(),
-                node,
-                buildRequest(request.data()),
-                response -> sendOnComplete(request, response)
-            ));
-        } else
-            sendCompleteFuture(request, errorResponse(request.data(), Errors.BROKER_NOT_AVAILABLE));
-    }
-
-    private void sendCompleteFuture(RaftRequest.Outbound request, ApiMessage message) {
-        RaftResponse.Inbound response = new RaftResponse.Inbound(
-                request.correlationId(),
-                message,
-                request.destination()
-        );
-        request.completion.complete(response);
+            var future = new CompletableFuture<RaftResponse.Inbound>();
+            requestThread.sendRequest(
+                new RequestAndCompletionHandler(
+                    request.createdTimeMs(),
+                    node,
+                    buildRequest(request.data()),
+                    response -> sendOnCompleted(request, response, future)
+                )
+            );
+            return future;
+        } else {
+            return CompletableFuture.completedFuture(
+                new RaftResponse.Inbound(
+                    request.correlationId(),
+                    errorResponse(request.data(), Errors.BROKER_NOT_AVAILABLE),
+                    request.destination()
+                )
+            );
+        }
     }
 
-    private void sendOnComplete(RaftRequest.Outbound request, ClientResponse clientResponse) {
+    private void sendOnCompleted(
+        RaftRequest.Outbound request,
+        ClientResponse clientResponse,
+        CompletableFuture<RaftResponse.Inbound> future
+    ) {
         ApiMessage response;
         if (clientResponse.versionMismatch() != null) {
             log.error("Request {} failed due to unsupported version error", request, clientResponse.versionMismatch());
@@ -155,7 +163,14 @@ private void sendOnComplete(RaftRequest.Outbound request, ClientResponse clientR
         } else {
             response = clientResponse.responseBody().data();
         }
-        sendCompleteFuture(request, response);
+
+        future.complete(
+            new RaftResponse.Inbound(
+                request.correlationId(),
+                response,
+                request.destination()
+            )
+        );
     }
 
     private ApiMessage errorResponse(ApiMessage request, Errors error) {
diff --git a/raft/src/main/java/org/apache/kafka/raft/KafkaRaftClient.java b/raft/src/main/java/org/apache/kafka/raft/KafkaRaftClient.java
--- a/raft/src/main/java/org/apache/kafka/raft/KafkaRaftClient.java
+++ b/raft/src/main/java/org/apache/kafka/raft/KafkaRaftClient.java
@@ -112,6 +112,7 @@
 import java.util.Random;
 import java.util.Set;
 import java.util.concurrent.CompletableFuture;
+import java.util.concurrent.CompletionStage;
 import java.util.concurrent.ConcurrentLinkedQueue;
 import java.util.concurrent.ExecutionException;
 import java.util.concurrent.TimeoutException;
@@ -372,10 +373,9 @@ private void onUpdateLeaderHighWatermark(
             logger.debug("Leader high watermark updated to {}", highWatermark);
             log.updateHighWatermark(highWatermark);
 
-            // Notify the add and remove voter handlers that the HWM has been updated in case there are
+            // Notify the voter change handlers that the HWM has been updated in case there are
             // add or remove voter request that need to be completed
-            addVoterHandler.highWatermarkUpdated(state);
-            removeVoterHandler.highWatermarkUpdated(state);
+            maybeNotifyVoterHandlerOnHWmUpdate(state, highWatermark.offset());
 
             // After updating the high watermark, we first clear the append
             // purgatory so that we have an opportunity to route the pending
@@ -394,6 +394,11 @@ private void onUpdateLeaderHighWatermark(
         });
     }
 
+    private void maybeNotifyVoterHandlerOnHWmUpdate(LeaderState<T> state, long highWatermark) {
+        addVoterHandler.highWatermarkUpdated(state, highWatermark);
+        removeVoterHandler.highWatermarkUpdated(state, highWatermark);
+    }
+
     private void updateListenersProgress(long highWatermark) {
         for (ListenerContext listenerContext : listenerContexts.values()) {
             listenerContext.nextExpectedOffset().ifPresent(nextExpectedOffset -> {
@@ -600,7 +605,6 @@ public void initialize(
 
         // Specialized update voter handler
         this.updateVoterHandler = new UpdateVoterHandler(
-            nodeId,
             partitionState,
             channel.listenerName(),
             logContext
@@ -1478,7 +1482,7 @@ private boolean hasValidClusterId(String requestClusterId) {
      * - {@link Errors#INVALID_REQUEST} if the request epoch is larger than the leader's current epoch
      *     or if either the fetch offset or the last fetched epoch is invalid
      */
-    private CompletableFuture<FetchResponseData> handleFetchRequest(
+    private CompletionStage<FetchResponseData> handleFetchRequest(
         RaftRequest.Inbound requestMetadata,
         long currentTimeMs
     ) {
@@ -1542,12 +1546,10 @@ private CompletableFuture<FetchResponseData> handleFetchRequest(
             return completedFuture(response);
         }
 
-        CompletableFuture<Long> future = fetchPurgatory.await(
+        return fetchPurgatory.await(
             fetchPartition.fetchOffset(),
             request.maxWaitMs()
-        );
-
-        return future.handle((completionTimeMs, exception) -> {
+        ).handle((completionTimeMs, exception) -> {
             if (exception != null) {
                 Throwable cause = exception instanceof ExecutionException ?
                     exception.getCause() : exception;
@@ -2247,7 +2249,7 @@ private boolean handleFetchSnapshotResponse(
      * - {@link Errors#UNSUPPORTED_VERSION} if the cluster does not support kraft.version 1
      * - {@link Errors#INVALID_REQUEST} if the request does not include a valid voter or endpoint
      */
-    private CompletableFuture<AddRaftVoterResponseData> handleAddVoterRequest(
+    private CompletionStage<AddRaftVoterResponseData> handleAddVoterRequest(
         RaftRequest.Inbound requestMetadata,
         long currentTimeMs
     ) {
@@ -2386,7 +2388,7 @@ private boolean handleAddVoterResponse(
      * - {@link Errors#UNSUPPORTED_VERSION} if the cluster does not support the required kraft.version
      * - {@link Errors#INVALID_REQUEST} if the request does not include a valid voter or endpoint
      */
-    private CompletableFuture<RemoveRaftVoterResponseData> handleRemoveVoterRequest(
+    private CompletionStage<RemoveRaftVoterResponseData> handleRemoveVoterRequest(
         RaftRequest.Inbound requestMetadata,
         long currentTimeMs
     ) {
@@ -2469,7 +2471,7 @@ private boolean handleRemoveVoterResponse(
      *     directory id, endpoint, or KRaft version
      * - {@link Errors#VOTER_NOT_FOUND} if the specified voter does not exist in the current set
      */
-    private CompletableFuture<UpdateRaftVoterResponseData> handleUpdateVoterRequest(
+    private CompletionStage<UpdateRaftVoterResponseData> handleUpdateVoterRequest(
         RaftRequest.Inbound requestMetadata,
         long currentTimeMs
     ) {
@@ -2805,9 +2807,13 @@ private Optional<Errors> validateLeaderOnlyRequest(int requestEpoch) {
         }
     }
 
-    private void handleRequest(RaftRequest.Inbound request, long currentTimeMs) {
+    private void handleRequest(
+        RaftRequest.Inbound request,
+        CompletableFuture<RaftMessage> future,
+        long currentTimeMs
+    ) {
         ApiKeys apiKey = ApiKeys.forId(request.data().apiKey());
-        final CompletableFuture<? extends ApiMessage> responseFuture = switch (apiKey) {
+        final CompletionStage<? extends ApiMessage> responseStage = switch (apiKey) {
             case FETCH -> handleFetchRequest(request, currentTimeMs);
             case VOTE -> completedFuture(handleVoteRequest(request));
             case BEGIN_QUORUM_EPOCH -> completedFuture(handleBeginQuorumEpochRequest(request, currentTimeMs));
@@ -2820,29 +2826,36 @@ private void handleRequest(RaftRequest.Inbound request, long currentTimeMs) {
             default -> throw new IllegalArgumentException("Unexpected request type " + apiKey);
         };
 
-        responseFuture.whenComplete((response, exception) -> {
-            ApiMessage message = response;
-            if (message == null) {
-                message = RaftUtil.errorResponse(apiKey, Errors.forException(exception));
-            }
+        responseStage.whenComplete((response, exception) -> {
+            var message = response == null ?
+                RaftUtil.errorResponse(apiKey, Errors.forException(exception)) :
+                response;
+
+            var raftResponse = new RaftResponse.Outbound(request.correlationId(), message);
 
-            RaftResponse.Outbound responseMessage = new RaftResponse.Outbound(request.correlationId(), message);
-            request.completion.complete(responseMessage);
-            logger.trace("Sent response {} to inbound request {}", responseMessage, request);
+            future.complete(raftResponse);
+            logger.trace("Sent response {} to inbound request {}", raftResponse, request);
         });
     }
 
-    private void handleInboundMessage(RaftMessage message, long currentTimeMs) {
+    private void handleInboundMessage(
+        RaftMessage message,
+        CompletableFuture<RaftMessage> future,
+        long currentTimeMs
+    ) {
         logger.trace("Received inbound message {}", message);
 
         if (message instanceof RaftRequest.Inbound request) {
-            handleRequest(request, currentTimeMs);
+            handleRequest(request, future, currentTimeMs);
         } else if (message instanceof RaftResponse.Inbound response) {
             if (requestManager.isResponseExpected(response.source(), response.correlationId())) {
                 handleResponse(response, currentTimeMs);
             } else {
                 logger.debug("Ignoring response {} since it is no longer needed", response);
             }
+            // Inboud response messages do not have an associated outbound message. Nothing should
+            // be reacting to the future's completion. Let's complete the future for completeness.
+            future.complete(null);
         } else {
             throw new IllegalArgumentException("Unexpected message " + message);
         }
@@ -2883,24 +2896,12 @@ private RequestSendResult maybeSendRequest(
                 currentTimeMs
             );
 
-            requestMessage.completion.whenComplete((response, exception) -> {
-                if (exception != null) {
-                    ApiKeys api = ApiKeys.forId(request.apiKey());
-                    Errors error = Errors.forException(exception);
-                    ApiMessage errorResponse = RaftUtil.errorResponse(api, error);
-
-                    response = new RaftResponse.Inbound(
-                        correlationId,
-                        errorResponse,
-                        destination
-                    );
-                }
-
-                messageQueue.add(response);
-            });
-
             requestManager.onRequestSent(destination, correlationId, currentTimeMs);
-            channel.send(requestMessage);
+            channel
+                .send(requestMessage)
+                .whenComplete(
+                    (response, exception) -> messageQueue.add(response)
+                );
             requestSent = true;
             logger.trace("Sent outbound request: {}", requestMessage);
         }
@@ -3053,10 +3054,11 @@ private void appendBatch(
             int epoch = state.epoch();
             LogAppendInfo info = appendAsLeader(batch.data);
             OffsetAndEpoch offsetAndEpoch = new OffsetAndEpoch(info.lastOffset(), epoch);
-            CompletableFuture<Long> future = appendPurgatory.await(
-                offsetAndEpoch.offset() + 1, Integer.MAX_VALUE);
 
-            future.whenComplete((commitTimeMs, exception) -> {
+            appendPurgatory.await(
+                offsetAndEpoch.offset() + 1,
+                Integer.MAX_VALUE
+            ).whenComplete((commitTimeMs, exception) -> {
                 if (exception != null) {
                     logger.debug(
                         "Failed to commit {} records up to last offset {}",
@@ -3179,7 +3181,9 @@ private long pollLeader(long currentTimeMs) {
             return 0L;
         }
 
-        long timeUntilVoterChangeExpires = state.maybeExpirePendingOperation(currentTimeMs);
+        long timeUntilVoterChangeExpires = state
+            .changeVoterState()
+            .maybeExpirePendingOperation(currentTimeMs);
 
         long timeUntilFlush = maybeAppendBatches(
             state,
@@ -3647,13 +3651,20 @@ private void wakeup() {
     }
 
     /**
-     * Handle an inbound request. The response will be returned through
-     * {@link RaftRequest.Inbound#completion}.
+     * Handle an inbound request.
      *
      * @param request The inbound request
+     * @return A completion stage that completes with the outbound response
      */
-    public void handle(RaftRequest.Inbound request) {
-        messageQueue.add(Objects.requireNonNull(request));
+    public CompletionStage<RaftResponse.Outbound> handle(RaftRequest.Inbound request) {
+        return messageQueue.add(Objects.requireNonNull(request)).thenApply(message -> {
+            if (message instanceof RaftResponse.Outbound response) {
+                return response;
+            } else {
+                logger.error("Message must be a response: {}", message);
+                throw new IllegalStateException("KRaft didn't return an expected response");
+            }
+        });
     }
 
     /**
@@ -3677,14 +3688,12 @@ public void poll() {
         long startWaitTimeMs = time.milliseconds();
         kafkaRaftMetrics.updatePollStart(startWaitTimeMs);
 
-        RaftMessage message = messageQueue.poll(pollTimeoutMs);
+        var maybeEntry = messageQueue.poll(pollTimeoutMs);
 
         long endWaitTimeMs = time.milliseconds();
         kafkaRaftMetrics.updatePollEnd(endWaitTimeMs);
 
-        if (message != null) {
-            handleInboundMessage(message, endWaitTimeMs);
-        }
+        maybeEntry.ifPresent(entry -> handleInboundMessage(entry.message(), entry.future(), endWaitTimeMs));
 
         pollListeners();
     }
@@ -3741,7 +3750,7 @@ public void schedulePreparedAppend() {
     }
 
     @Override
-    public CompletableFuture<Void> shutdown(int timeoutMs) {
+    public CompletionStage<Void> shutdown(int timeoutMs) {
         logger.info("Beginning graceful shutdown");
         CompletableFuture<Void> shutdownComplete = new CompletableFuture<>();
         shutdown.set(new GracefulShutdown(timeoutMs, shutdownComplete));
@@ -3906,8 +3915,10 @@ private class GracefulShutdown {
         final Timer finishTimer;
         final CompletableFuture<Void> completeFuture;
 
-        public GracefulShutdown(long shutdownTimeoutMs,
-                                CompletableFuture<Void> completeFuture) {
+        public GracefulShutdown(
+            long shutdownTimeoutMs,
+            CompletableFuture<Void> completeFuture
+        ) {
             this.finishTimer = time.timer(shutdownTimeoutMs);
             this.completeFuture = completeFuture;
         }
diff --git a/raft/src/main/java/org/apache/kafka/raft/KafkaRaftClientDriver.java b/raft/src/main/java/org/apache/kafka/raft/KafkaRaftClientDriver.java
--- a/raft/src/main/java/org/apache/kafka/raft/KafkaRaftClientDriver.java
+++ b/raft/src/main/java/org/apache/kafka/raft/KafkaRaftClientDriver.java
@@ -25,7 +25,7 @@
 
 import org.slf4j.Logger;
 
-import java.util.concurrent.CompletableFuture;
+import java.util.concurrent.CompletionStage;
 
 /**
  * A single-threaded driver for {@link KafkaRaftClient}. Client APIs will only do useful work
@@ -101,7 +101,7 @@ public boolean isRunning() {
         return client.isRunning() && !isThreadFailed();
     }
 
-    public CompletableFuture<ApiMessage> handleRequest(
+    public CompletionStage<ApiMessage> handleRequest(
         RequestContext context,
         RequestHeader header,
         ApiMessage request,
@@ -115,9 +115,7 @@ public CompletableFuture<ApiMessage> handleRequest(
             createdTimeMs
         );
 
-        client.handle(inboundRequest);
-
-        return inboundRequest.completion.thenApply(RaftMessage::data);
+        return client.handle(inboundRequest).thenApply(RaftMessage::data);
     }
 
     public KafkaRaftClient<T> client() {
diff --git a/raft/src/main/java/org/apache/kafka/raft/LeaderState.java b/raft/src/main/java/org/apache/kafka/raft/LeaderState.java
--- a/raft/src/main/java/org/apache/kafka/raft/LeaderState.java
+++ b/raft/src/main/java/org/apache/kafka/raft/LeaderState.java
@@ -30,11 +30,10 @@
 import org.apache.kafka.common.utils.Timer;
 import org.apache.kafka.common.utils.internals.LogContext;
 import org.apache.kafka.raft.errors.NotLeaderException;
-import org.apache.kafka.raft.internals.AddVoterHandlerState;
 import org.apache.kafka.raft.internals.BatchAccumulator;
+import org.apache.kafka.raft.internals.ChangeVoterHandlerState;
 import org.apache.kafka.raft.internals.KRaftVersionUpgrade;
 import org.apache.kafka.raft.internals.KafkaRaftMetrics;
-import org.apache.kafka.raft.internals.RemoveVoterHandlerState;
 import org.apache.kafka.server.common.KRaftVersion;
 
 import org.slf4j.Logger;
@@ -47,6 +46,7 @@
 import java.util.Map;
 import java.util.Objects;
 import java.util.Optional;
+import java.util.OptionalInt;
 import java.util.OptionalLong;
 import java.util.Set;
 import java.util.concurrent.TimeUnit;
@@ -60,7 +60,7 @@
  * More specifically, the set of unacknowledged voters are targets for BeginQuorumEpoch requests from the leader until
  * they acknowledge the leader.
  */
-public class LeaderState<T> implements EpochState {
+public final class LeaderState<T> implements EpochState {
     static final long OBSERVER_SESSION_TIMEOUT_MS = 300_000L;
     static final double CHECK_QUORUM_TIMEOUT_FACTOR = 1.5;
 
@@ -72,11 +72,10 @@ public class LeaderState<T> implements EpochState {
     // This field is non-empty if the voter set at epoch start came from a snapshot or log segment
     private final OptionalLong offsetOfVotersAtEpochStart;
     private final KRaftVersion kraftVersionAtEpochStart;
+    private final ChangeVoterHandlerState changeVoterState;
 
     private Optional<LogOffsetMetadata> highWatermark = Optional.empty();
     private Map<Integer, ReplicaState> voterStates = new HashMap<>();
-    private Optional<AddVoterHandlerState> addVoterHandlerState = Optional.empty();
-    private Optional<RemoveVoterHandlerState> removeVoterHandlerState = Optional.empty();
 
     private final Map<ReplicaKey, ReplicaState> observerStates = new HashMap<>();
     private final Logger log;
@@ -158,6 +157,7 @@ protected LeaderState(
         this.voterSetAtEpochStart =  voterSetAtEpochStart;
         this.offsetOfVotersAtEpochStart = offsetOfVotersAtEpochStart;
         this.kraftVersionAtEpochStart = kraftVersionAtEpochStart;
+        this.changeVoterState = new ChangeVoterHandlerState(kafkaRaftMetrics);
 
         kafkaRaftMetrics.addLeaderMetrics();
         this.kafkaRaftMetrics = kafkaRaftMetrics;
@@ -282,80 +282,8 @@ public BatchAccumulator<T> accumulator() {
         return accumulator;
     }
 
-    public Optional<AddVoterHandlerState> addVoterHandlerState() {
-        return addVoterHandlerState;
-    }
-
-    public void resetAddVoterHandlerState(
-        Errors error,
-        String message,
-        Optional<AddVoterHandlerState> state
-    ) {
-        addVoterHandlerState.ifPresent(
-            handlerState -> handlerState
-                .future()
-                .complete(RaftUtil.addVoterResponse(error, message))
-        );
-        addVoterHandlerState = state;
-        updateUncommittedVoterChangeMetric();
-    }
-
-    public Optional<RemoveVoterHandlerState> removeVoterHandlerState() {
-        return removeVoterHandlerState;
-    }
-
-    public void resetRemoveVoterHandlerState(
-        Errors error,
-        String message,
-        Optional<RemoveVoterHandlerState> state
-    ) {
-        removeVoterHandlerState.ifPresent(
-            handlerState -> handlerState
-                .future()
-                .complete(RaftUtil.removeVoterResponse(error, message))
-        );
-        removeVoterHandlerState = state;
-        updateUncommittedVoterChangeMetric();
-    }
-
-    private void updateUncommittedVoterChangeMetric() {
-        kafkaRaftMetrics.updateUncommittedVoterChange(
-            addVoterHandlerState.isPresent() || removeVoterHandlerState.isPresent()
-        );
-    }
-
-    public long maybeExpirePendingOperation(long currentTimeMs) {
-        // First abort any expired operations
-        long timeUntilAddVoterExpiration = addVoterHandlerState()
-            .map(state -> state.timeUntilOperationExpiration(currentTimeMs))
-            .orElse(Long.MAX_VALUE);
-
-        if (timeUntilAddVoterExpiration == 0) {
-            resetAddVoterHandlerState(Errors.REQUEST_TIMED_OUT, null, Optional.empty());
-        }
-
-        long timeUntilRemoveVoterExpiration = removeVoterHandlerState()
-            .map(state -> state.timeUntilOperationExpiration(currentTimeMs))
-            .orElse(Long.MAX_VALUE);
-
-        if (timeUntilRemoveVoterExpiration == 0) {
-            resetRemoveVoterHandlerState(Errors.REQUEST_TIMED_OUT, null, Optional.empty());
-        }
-
-        // Reread the timeouts and return the smaller of them
-        return Math.min(
-            addVoterHandlerState()
-                .map(state -> state.timeUntilOperationExpiration(currentTimeMs))
-                .orElse(Long.MAX_VALUE),
-            removeVoterHandlerState()
-                .map(state -> state.timeUntilOperationExpiration(currentTimeMs))
-                .orElse(Long.MAX_VALUE)
-        );
-    }
-
-    public boolean isOperationPending(long currentTimeMs) {
-        maybeExpirePendingOperation(currentTimeMs);
-        return addVoterHandlerState.isPresent() || removeVoterHandlerState.isPresent();
+    public ChangeVoterHandlerState changeVoterState() {
+        return changeVoterState;
     }
 
     private static List<Voter> convertToVoters(Set<Integer> voterIds) {
@@ -695,6 +623,11 @@ public int epoch() {
         return epoch;
     }
 
+    @Override
+    public LeaderAndEpoch leaderAndEpoch() {
+        return new LeaderAndEpoch(OptionalInt.of(localVoterNode.voterKey().id()), epoch);
+    }
+
     @Override
     public Endpoints leaderEndpoints() {
         return localVoterNode.listeners();
@@ -1144,8 +1077,7 @@ public String name() {
 
     @Override
     public void close() {
-        resetAddVoterHandlerState(Errors.NOT_LEADER_OR_FOLLOWER, null, Optional.empty());
-        resetRemoveVoterHandlerState(Errors.NOT_LEADER_OR_FOLLOWER, null, Optional.empty());
+        changeVoterState.maybeResetPendingVoterHandlerState(Errors.NOT_LEADER_OR_FOLLOWER);
         kafkaRaftMetrics.removeLeaderMetrics();
 
         accumulator.close();
diff --git a/raft/src/main/java/org/apache/kafka/raft/NetworkChannel.java b/raft/src/main/java/org/apache/kafka/raft/NetworkChannel.java
--- a/raft/src/main/java/org/apache/kafka/raft/NetworkChannel.java
+++ b/raft/src/main/java/org/apache/kafka/raft/NetworkChannel.java
@@ -18,6 +18,8 @@
 
 import org.apache.kafka.common.network.ListenerName;
 
+import java.util.concurrent.CompletionStage;
+
 /**
  * A simple network interface with few assumptions. We do not assume ordering
  * of requests or even that every outbound request will receive a response.
@@ -26,22 +28,27 @@ public interface NetworkChannel extends AutoCloseable {
 
     /**
      * Generate a new and unique correlationId for a new request to be sent.
+     *
+     * @return a unique integer for the lifetime of the channel
      */
     int newCorrelationId();
 
     /**
      * Send an outbound request message.
      *
+     * The complete stage return never completes with an exception. It always completes
+     * successfully. Exceptions are turn into error responses.
+     *
      * @param request outbound request to send
+     * @return a complete stage always complete successfully. Errors are always returned in the
+     *         response object
      */
-    void send(RaftRequest.Outbound request);
+    CompletionStage<RaftResponse.Inbound> send(RaftRequest.Outbound request);
 
     /**
      * The name of listener used when sending requests.
      *
      * @return the name of the listener
      */
     ListenerName listenerName();
-
-    default void close() throws InterruptedException {}
 }
diff --git a/raft/src/main/java/org/apache/kafka/raft/NomineeState.java b/raft/src/main/java/org/apache/kafka/raft/NomineeState.java
--- a/raft/src/main/java/org/apache/kafka/raft/NomineeState.java
+++ b/raft/src/main/java/org/apache/kafka/raft/NomineeState.java
@@ -18,7 +18,9 @@
 
 import org.apache.kafka.raft.internals.EpochElection;
 
-interface NomineeState extends EpochState {
+sealed interface NomineeState extends EpochState
+    permits ProspectiveState, CandidateState {
+
     EpochElection epochElection();
 
     /**
diff --git a/raft/src/main/java/org/apache/kafka/raft/ProspectiveState.java b/raft/src/main/java/org/apache/kafka/raft/ProspectiveState.java
--- a/raft/src/main/java/org/apache/kafka/raft/ProspectiveState.java
+++ b/raft/src/main/java/org/apache/kafka/raft/ProspectiveState.java
@@ -28,7 +28,7 @@
 
 import static org.apache.kafka.raft.QuorumState.unattachedOrProspectiveCanGrantVote;
 
-public class ProspectiveState implements NomineeState {
+public final class ProspectiveState implements NomineeState {
     private final int localId;
     private final int epoch;
     private final OptionalInt leaderId;
@@ -140,6 +140,11 @@ public int epoch() {
         return epoch;
     }
 
+    @Override
+    public LeaderAndEpoch leaderAndEpoch() {
+        return new LeaderAndEpoch(leaderId, epoch);
+    }
+
     @Override
     public Endpoints leaderEndpoints() {
         return leaderEndpoints;
diff --git a/raft/src/main/java/org/apache/kafka/raft/QuorumState.java b/raft/src/main/java/org/apache/kafka/raft/QuorumState.java
--- a/raft/src/main/java/org/apache/kafka/raft/QuorumState.java
+++ b/raft/src/main/java/org/apache/kafka/raft/QuorumState.java
@@ -831,8 +831,7 @@ public NomineeState nomineeStateOrThrow() {
     }
 
     public LeaderAndEpoch leaderAndEpoch() {
-        ElectionState election = state.election();
-        return new LeaderAndEpoch(election.optionalLeaderId(), election.epoch());
+        return state.leaderAndEpoch();
     }
 
     public boolean isFollower() {
diff --git a/raft/src/main/java/org/apache/kafka/raft/RaftClient.java b/raft/src/main/java/org/apache/kafka/raft/RaftClient.java
--- a/raft/src/main/java/org/apache/kafka/raft/RaftClient.java
+++ b/raft/src/main/java/org/apache/kafka/raft/RaftClient.java
@@ -30,7 +30,7 @@
 import java.util.Optional;
 import java.util.OptionalInt;
 import java.util.OptionalLong;
-import java.util.concurrent.CompletableFuture;
+import java.util.concurrent.CompletionStage;
 
 public interface RaftClient<T> extends AutoCloseable {
 
@@ -200,9 +200,9 @@ default void beginShutdown() {}
      * in use.
      *
      * @param timeoutMs How long to wait for graceful completion of pending operations.
-     * @return A future which is completed when shutdown completes successfully or the timeout expires.
+     * @return A stage which is completed when shutdown completes successfully or the timeout expires.
      */
-    CompletableFuture<Void> shutdown(int timeoutMs);
+    CompletionStage<Void> shutdown(int timeoutMs);
 
     /**
      * Resign the leadership. The leader will give up its leadership in the passed epoch
diff --git a/raft/src/main/java/org/apache/kafka/raft/RaftManager.java b/raft/src/main/java/org/apache/kafka/raft/RaftManager.java
--- a/raft/src/main/java/org/apache/kafka/raft/RaftManager.java
+++ b/raft/src/main/java/org/apache/kafka/raft/RaftManager.java
@@ -22,11 +22,11 @@
 import org.apache.kafka.common.requests.RequestHeader;
 import org.apache.kafka.server.common.serialization.RecordSerde;
 
-import java.util.concurrent.CompletableFuture;
+import java.util.concurrent.CompletionStage;
 
 public interface RaftManager<T> {
 
-    CompletableFuture<ApiMessage> handleRequest(
+    CompletionStage<ApiMessage> handleRequest(
         RequestContext context,
         RequestHeader header,
         ApiMessage request,
diff --git a/raft/src/main/java/org/apache/kafka/raft/RaftMessageQueue.java b/raft/src/main/java/org/apache/kafka/raft/RaftMessageQueue.java
--- a/raft/src/main/java/org/apache/kafka/raft/RaftMessageQueue.java
+++ b/raft/src/main/java/org/apache/kafka/raft/RaftMessageQueue.java
@@ -16,6 +16,10 @@
  */
 package org.apache.kafka.raft;
 
+import java.util.Optional;
+import java.util.concurrent.CompletableFuture;
+import java.util.concurrent.CompletionStage;
+
 /**
  * This class is used to serialize inbound requests or responses to outbound requests.
  * It basically just allows us to wrap a blocking queue so that we can have a mocked
@@ -29,18 +33,19 @@ public interface RaftMessageQueue {
      * Block for the arrival of a new message.
      *
      * @param timeoutMs timeout in milliseconds to wait for a new event
-     * @return the event or null if either the timeout was reached or there was
+     * @return the event or {@code Optional.empty()} if either the timeout was reached or there was
      *     a call to {@link #wakeup()} before any events became available
      */
-    RaftMessage poll(long timeoutMs);
+    Optional<QueueEntry> poll(long timeoutMs);
 
     /**
      * Add a new message to the queue.
      *
      * @param message the message to deliver
+     * @return a completion stage that will be completed when the message is processed
      * @throws IllegalStateException if the queue cannot accept the message
      */
-    void add(RaftMessage message);
+    CompletionStage<RaftMessage> add(RaftMessage message);
 
     /**
      * Check whether there are pending messages awaiting delivery.
@@ -55,4 +60,18 @@ public interface RaftMessageQueue {
      */
     void wakeup();
 
+    /**
+     * Represents an entry in the message queue.
+     */
+    interface QueueEntry {
+        /**
+         * @return the message associated with this entry
+         */
+        RaftMessage message();
+
+        /**
+         * @return the future associated with this entry
+         */
+        CompletableFuture<RaftMessage> future();
+    }
 }
diff --git a/raft/src/main/java/org/apache/kafka/raft/RaftRequest.java b/raft/src/main/java/org/apache/kafka/raft/RaftRequest.java
--- a/raft/src/main/java/org/apache/kafka/raft/RaftRequest.java
+++ b/raft/src/main/java/org/apache/kafka/raft/RaftRequest.java
@@ -20,8 +20,6 @@
 import org.apache.kafka.common.network.ListenerName;
 import org.apache.kafka.common.protocol.ApiMessage;
 
-import java.util.concurrent.CompletableFuture;
-
 public abstract class RaftRequest implements RaftMessage {
     private final int correlationId;
     private final ApiMessage data;
@@ -51,8 +49,6 @@ public static final class Inbound extends RaftRequest {
         private final short apiVersion;
         private final ListenerName listenerName;
 
-        public final CompletableFuture<RaftResponse.Outbound> completion = new CompletableFuture<>();
-
         public Inbound(
             ListenerName listenerName,
             int correlationId,
@@ -90,9 +86,13 @@ public String toString() {
 
     public static final class Outbound extends RaftRequest {
         private final Node destination;
-        public final CompletableFuture<RaftResponse.Inbound> completion = new CompletableFuture<>();
 
-        public Outbound(int correlationId, ApiMessage data, Node destination, long createdTimeMs) {
+        public Outbound(
+            int correlationId,
+            ApiMessage data,
+            Node destination,
+            long createdTimeMs
+        ) {
             super(correlationId, data, createdTimeMs);
             this.destination = destination;
         }
diff --git a/raft/src/main/java/org/apache/kafka/raft/ResignedState.java b/raft/src/main/java/org/apache/kafka/raft/ResignedState.java
--- a/raft/src/main/java/org/apache/kafka/raft/ResignedState.java
+++ b/raft/src/main/java/org/apache/kafka/raft/ResignedState.java
@@ -25,6 +25,7 @@
 import java.util.HashSet;
 import java.util.List;
 import java.util.Optional;
+import java.util.OptionalInt;
 import java.util.Set;
 
 /**
@@ -41,7 +42,7 @@
  * another election, or our own election timeout expires and we become a
  * Candidate.
  */
-public class ResignedState implements EpochState {
+public final class ResignedState implements EpochState {
     private final int localId;
     private final int epoch;
     private final Endpoints endpoints;
@@ -84,6 +85,11 @@ public int epoch() {
         return epoch;
     }
 
+    @Override
+    public LeaderAndEpoch leaderAndEpoch() {
+        return new LeaderAndEpoch(OptionalInt.of(localId), epoch);
+    }
+
     @Override
     public Endpoints leaderEndpoints() {
         return endpoints;
diff --git a/raft/src/main/java/org/apache/kafka/raft/TimingWheelExpirationService.java b/raft/src/main/java/org/apache/kafka/raft/TimingWheelExpirationService.java
--- a/raft/src/main/java/org/apache/kafka/raft/TimingWheelExpirationService.java
+++ b/raft/src/main/java/org/apache/kafka/raft/TimingWheelExpirationService.java
@@ -58,7 +58,14 @@ private static class TimerTaskCompletableFuture<T> extends TimerTask {
 
         @Override
         public void run() {
-            future.completeExceptionally(new TimeoutException("Future failed to be completed before timeout of " + delayMs + " ms was reached"));
+            future.completeExceptionally(
+                new TimeoutException(
+                    String.format(
+                        "Future failed to be completed before timeout of %s ms was reached",
+                        delayMs
+                    )
+                )
+            );
         }
     }
 
diff --git a/raft/src/main/java/org/apache/kafka/raft/UnattachedState.java b/raft/src/main/java/org/apache/kafka/raft/UnattachedState.java
--- a/raft/src/main/java/org/apache/kafka/raft/UnattachedState.java
+++ b/raft/src/main/java/org/apache/kafka/raft/UnattachedState.java
@@ -41,7 +41,7 @@
  * request from the leader.
  */
 
-public class UnattachedState implements EpochState {
+public final class UnattachedState implements EpochState {
     private final int epoch;
     private final OptionalInt leaderId;
     private final Optional<ReplicaKey> votedKey;
@@ -87,6 +87,11 @@ public int epoch() {
         return epoch;
     }
 
+    @Override
+    public LeaderAndEpoch leaderAndEpoch() {
+        return new LeaderAndEpoch(leaderId, epoch);
+    }
+
     @Override
     public Endpoints leaderEndpoints() {
         return Endpoints.empty();
diff --git a/raft/src/main/java/org/apache/kafka/raft/internals/AddVoterHandler.java b/raft/src/main/java/org/apache/kafka/raft/internals/AddVoterHandler.java
--- a/raft/src/main/java/org/apache/kafka/raft/internals/AddVoterHandler.java
+++ b/raft/src/main/java/org/apache/kafka/raft/internals/AddVoterHandler.java
@@ -38,6 +38,7 @@
 import java.util.Optional;
 import java.util.OptionalLong;
 import java.util.concurrent.CompletableFuture;
+import java.util.concurrent.CompletionStage;
 
 /**
  * This type implements the protocol for adding a voter to a KRaft partition.
@@ -83,15 +84,16 @@ public AddVoterHandler(
         this.logger = logContext.logger(AddVoterHandler.class);
     }
 
-    public CompletableFuture<AddRaftVoterResponseData> handleAddVoterRequest(
+    public CompletionStage<AddRaftVoterResponseData> handleAddVoterRequest(
         LeaderState<?> leaderState,
         ReplicaKey voterKey,
         Endpoints voterEndpoints,
         boolean ackWhenCommitted,
         long currentTimeMs
     ) {
+        var changeVoterState = leaderState.changeVoterState();
         // Check if there are any pending voter change requests
-        if (leaderState.isOperationPending(currentTimeMs)) {
+        if (changeVoterState.isOperationPending(currentTimeMs)) {
             return CompletableFuture.completedFuture(
                 RaftUtil.addVoterResponse(
                     Errors.REQUEST_TIMED_OUT,
@@ -188,7 +190,7 @@ public CompletableFuture<AddRaftVoterResponseData> handleAddVoterRequest(
             ackWhenCommitted,
             time.timer(timeout.getAsLong())
         );
-        leaderState.resetAddVoterHandlerState(
+        changeVoterState.resetAddVoterHandlerState(
             Errors.UNKNOWN_SERVER_ERROR,
             null,
             Optional.of(state)
@@ -204,7 +206,8 @@ public boolean handleApiVersionsResponse(
         Optional<ApiVersionsResponseData.SupportedFeatureKey> supportedKraftVersions,
         long currentTimeMs
     ) {
-        Optional<AddVoterHandlerState> handlerState = leaderState.addVoterHandlerState();
+        var changeVoterState = leaderState.changeVoterState();
+        var handlerState = changeVoterState.addVoterHandlerState();
         if (handlerState.isEmpty()) {
             // There are no pending add operation just ignore the api response
             return true;
@@ -232,7 +235,7 @@ public boolean handleApiVersionsResponse(
                 error
             );
 
-            leaderState.resetAddVoterHandlerState(
+            changeVoterState.resetAddVoterHandlerState(
                 Errors.REQUEST_TIMED_OUT,
                 String.format(
                     "Aborted add voter operation for since API_VERSIONS returned an error %s",
@@ -255,7 +258,7 @@ public boolean handleApiVersionsResponse(
                 supportedKraftVersions
             );
 
-            leaderState.resetAddVoterHandlerState(
+            changeVoterState.resetAddVoterHandlerState(
                 Errors.INVALID_REQUEST,
                 String.format(
                     "Aborted add voter operation for %s since the %s range %s doesn't " +
@@ -288,7 +291,7 @@ public boolean handleApiVersionsResponse(
                 leaderState.getReplicaState(current.voterKey())
             );
 
-            leaderState.resetAddVoterHandlerState(
+            changeVoterState.resetAddVoterHandlerState(
                 Errors.REQUEST_TIMED_OUT,
                 String.format(
                     "Aborted add voter operation for %s since it is lagging behind",
@@ -331,17 +334,20 @@ public boolean handleApiVersionsResponse(
         return true;
     }
 
-    public void highWatermarkUpdated(LeaderState<?> leaderState) {
-        leaderState.addVoterHandlerState().ifPresent(current ->
-            leaderState.highWatermark().ifPresent(highWatermark ->
+    public void highWatermarkUpdated(LeaderState<?> leaderState, long highWatermark) {
+        var changeVoterState = leaderState.changeVoterState();
+
+        changeVoterState
+            .addVoterHandlerState()
+            .ifPresent(current ->
                 current.lastOffset().ifPresent(lastOffset -> {
-                    if (highWatermark.offset() > lastOffset) {
+                    if (highWatermark > lastOffset) {
                         // VotersRecord with the added voter was committed; complete the RPC
-                        leaderState.resetAddVoterHandlerState(Errors.NONE, null, Optional.empty());
+                        changeVoterState
+                            .resetAddVoterHandlerState(Errors.NONE, null, Optional.empty());
                     }
                 })
-            )
-        );
+            );
     }
 
     private ApiVersionsRequestData buildApiVersionsRequest() {
diff --git a/raft/src/main/java/org/apache/kafka/raft/internals/BlockingMessageQueue.java b/raft/src/main/java/org/apache/kafka/raft/internals/BlockingMessageQueue.java
--- a/raft/src/main/java/org/apache/kafka/raft/internals/BlockingMessageQueue.java
+++ b/raft/src/main/java/org/apache/kafka/raft/internals/BlockingMessageQueue.java
@@ -17,60 +17,104 @@
 package org.apache.kafka.raft.internals;
 
 import org.apache.kafka.common.errors.InterruptException;
-import org.apache.kafka.common.protocol.ApiMessage;
 import org.apache.kafka.raft.RaftMessage;
 import org.apache.kafka.raft.RaftMessageQueue;
 
+import java.util.Optional;
 import java.util.concurrent.BlockingQueue;
+import java.util.concurrent.CompletableFuture;
+import java.util.concurrent.CompletionStage;
 import java.util.concurrent.LinkedBlockingQueue;
 import java.util.concurrent.TimeUnit;
 import java.util.concurrent.atomic.AtomicInteger;
 
 public class BlockingMessageQueue implements RaftMessageQueue {
-    private static final RaftMessage WAKEUP_MESSAGE = new RaftMessage() {
+    private final BlockingQueue<InternalQueueEntry> queue = new LinkedBlockingQueue<>();
+    private final AtomicInteger messageCount = new AtomicInteger(0);
+
+    /**
+     * Internal queue entry type used to discriminate between messages and wakeup signals.
+     *
+     * This sealed interface ensures type safety when polling the queue.
+     */
+    private sealed interface InternalQueueEntry { }
+
+    /**
+     * Marker entry used to unblock threads waiting on {@link #poll(long)} without delivering a message.
+     *
+     * Wakeup entries are drained during polling and do not contribute to the message count.
+     */
+    private record WakeupMarker() implements InternalQueueEntry { }
+
+    private static final WakeupMarker WAKEUP = new WakeupMarker();
+
+    /**
+     * A queue entry that contains a message and its associated future.
+     */
+    private static final class MessageEntry implements QueueEntry, InternalQueueEntry {
+        private final CompletableFuture<RaftMessage> future = new CompletableFuture<>();
+        private final RaftMessage message;
+
+        MessageEntry(RaftMessage message) {
+            this.message = message;
+        }
+
         @Override
-        public int correlationId() {
-            return 0;
+        public RaftMessage message() {
+            return message;
         }
 
         @Override
-        public ApiMessage data() {
-            return null;
+        public CompletableFuture<RaftMessage> future() {
+            return future;
         }
-    };
 
-    private final BlockingQueue<RaftMessage> queue = new LinkedBlockingQueue<>();
-    private final AtomicInteger size = new AtomicInteger(0);
+        @Override
+        public String toString() {
+            return String.format(
+                "MessageEntry(message=%s, future.isDone=%s)",
+                message,
+                future.isDone()
+            );
+        }
+    }
 
     @Override
-    public RaftMessage poll(long timeoutMs) {
+    public Optional<QueueEntry> poll(long timeoutMs) {
         try {
-            RaftMessage message = queue.poll(timeoutMs, TimeUnit.MILLISECONDS);
-            if (message == null || message == WAKEUP_MESSAGE) {
-                return null;
-            } else {
-                size.decrementAndGet();
-                return message;
+            InternalQueueEntry entry = queue.poll(timeoutMs, TimeUnit.MILLISECONDS);
+            // Drain all wakeup markers until we find a message or the queue is empty
+            while (entry instanceof WakeupMarker) {
+                entry = queue.poll();
             }
+            if (entry instanceof MessageEntry messageEntry) {
+                messageCount.decrementAndGet();
+                return Optional.of(messageEntry);
+            }
+            return Optional.empty();
         } catch (InterruptedException e) {
             throw new InterruptException(e);
         }
     }
 
     @Override
-    public void add(RaftMessage message) {
-        queue.add(message);
-        size.incrementAndGet();
+    public CompletionStage<RaftMessage> add(RaftMessage message) {
+        if (message == null) {
+            throw new IllegalArgumentException("message cannot be null");
+        }
+        var entry = new MessageEntry(message);
+        queue.add(entry);
+        messageCount.incrementAndGet();
+        return entry.future();
     }
 
     @Override
     public boolean isEmpty() {
-        return size.get() == 0;
+        return messageCount.get() == 0;
     }
 
     @Override
     public void wakeup() {
-        queue.add(WAKEUP_MESSAGE);
+        queue.add(WAKEUP);
     }
-
 }
diff --git a/raft/src/main/java/org/apache/kafka/raft/internals/ChangeVoterHandlerState.java b/raft/src/main/java/org/apache/kafka/raft/internals/ChangeVoterHandlerState.java
new file mode 100644
--- /dev/null
+++ b/raft/src/main/java/org/apache/kafka/raft/internals/ChangeVoterHandlerState.java
@@ -0,0 +1,208 @@
+/*
+ * Licensed to the Apache Software Foundation (ASF) under one or more
+ * contributor license agreements. See the NOTICE file distributed with
+ * this work for additional information regarding copyright ownership.
+ * The ASF licenses this file to You under the Apache License, Version 2.0
+ * (the "License"); you may not use this file except in compliance with
+ * the License. You may obtain a copy of the License at
+ *
+ *    http://www.apache.org/licenses/LICENSE-2.0
+ *
+ * Unless required by applicable law or agreed to in writing, software
+ * distributed under the License is distributed on an "AS IS" BASIS,
+ * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
+ * See the License for the specific language governing permissions and
+ * limitations under the License.
+ */
+package org.apache.kafka.raft.internals;
+
+import org.apache.kafka.common.protocol.Errors;
+import org.apache.kafka.raft.RaftUtil;
+
+import java.util.Optional;
+
+/**
+ * Manages the state of add and remove voter operations.
+ * <p>
+ * This class maintains at most one pending voter change operation at a time. Add voter and
+ * remove voter operations are mutually exclusive - only one type can be in progress at any
+ * given time. When an operation is reset or expires, its associated future is completed with
+ * an appropriate error response.
+ * <p>
+ * The class also updates the uncommitted voter change metric to reflect whether a voter
+ * change operation is currently pending.
+ */
+public final class ChangeVoterHandlerState {
+    private Optional<AddVoterHandlerState> addVoterHandlerState = Optional.empty();
+    private Optional<RemoveVoterHandlerState> removeVoterHandlerState = Optional.empty();
+    private final KafkaRaftMetrics kafkaRaftMetrics;
+
+    /**
+     * Constructs a new ChangeVoterHandlerState.
+     *
+     * @param kafkaRaftMetrics the metrics instance to update when voter change state changes
+     */
+    public ChangeVoterHandlerState(KafkaRaftMetrics kafkaRaftMetrics) {
+        this.kafkaRaftMetrics = kafkaRaftMetrics;
+    }
+
+    /**
+     * Returns the current add voter handler state, if one exists.
+     *
+     * @return an Optional containing the add voter handler state, or empty if no add voter
+     *         operation is pending
+     */
+    public Optional<AddVoterHandlerState> addVoterHandlerState() {
+        return addVoterHandlerState;
+    }
+
+    /**
+     * Resets the add voter handler state to the specified state.
+     * <p>
+     * If an add voter handler state already exists, its future will be completed with the
+     * provided error and message before being replaced. If the new state is non-empty and a
+     * remove voter handler state is currently present, this method throws an IllegalStateException
+     * to enforce mutual exclusivity.
+     *
+     * @param error the error to complete any existing add voter operation with
+     * @param message the error message to include in the response, or null for no message
+     * @param state the new add voter handler state, or empty to clear the state
+     * @throws IllegalStateException if attempting to set a non-empty add voter state while a
+     *         remove voter state is already present
+     */
+    public void resetAddVoterHandlerState(
+        Errors error,
+        String message,
+        Optional<AddVoterHandlerState> state
+    ) {
+        if (state.isPresent() && removeVoterHandlerState.isPresent()) {
+            throw new IllegalStateException(
+                "Cannot set add voter handler state when remove voter handler state is already present"
+            );
+        }
+        addVoterHandlerState.ifPresent(
+            handlerState -> handlerState
+                .future()
+                .complete(RaftUtil.addVoterResponse(error, message))
+        );
+        addVoterHandlerState = state;
+        updateUncommittedVoterChangeMetric();
+    }
+
+    /**
+     * Returns the current remove voter handler state, if one exists.
+     *
+     * @return an Optional containing the remove voter handler state, or empty if no remove voter
+     *         operation is pending
+     */
+    public Optional<RemoveVoterHandlerState> removeVoterHandlerState() {
+        return removeVoterHandlerState;
+    }
+
+    /**
+     * Resets the remove voter handler state to the specified state.
+     * <p>
+     * If a remove voter handler state already exists, its future will be completed with the
+     * provided error and message before being replaced. If the new state is non-empty and an
+     * add voter handler state is currently present, this method throws an IllegalStateException
+     * to enforce mutual exclusivity.
+     *
+     * @param error the error to complete any existing remove voter operation with
+     * @param message the error message to include in the response, or null for no message
+     * @param state the new remove voter handler state, or empty to clear the state
+     * @throws IllegalStateException if attempting to set a non-empty remove voter state while an
+     *         add voter state is already present
+     */
+    public void resetRemoveVoterHandlerState(
+        Errors error,
+        String message,
+        Optional<RemoveVoterHandlerState> state
+    ) {
+        if (state.isPresent() && addVoterHandlerState.isPresent()) {
+            throw new IllegalStateException(
+                "Cannot set remove voter handler state when add voter handler state is already present"
+            );
+        }
+        removeVoterHandlerState.ifPresent(
+            handlerState -> handlerState
+                .future()
+                .complete(RaftUtil.removeVoterResponse(error, message))
+        );
+        removeVoterHandlerState = state;
+        updateUncommittedVoterChangeMetric();
+    }
+
+    private void updateUncommittedVoterChangeMetric() {
+        kafkaRaftMetrics.updateUncommittedVoterChange(
+            addVoterHandlerState.isPresent() || removeVoterHandlerState.isPresent()
+        );
+    }
+
+    /**
+     * Checks for and expires any pending voter change operations that have timed out.
+     * <p>
+     * This method evaluates both add voter and remove voter operations. Any operation that
+     * has expired (timeUntilOperationExpiration returns 0) is reset with a REQUEST_TIMED_OUT
+     * error. The method then returns the minimum time remaining until the next operation
+     * expiration.
+     *
+     * @param currentTimeMs the current time in milliseconds
+     * @return the time in milliseconds until the next operation expires, or Long.MAX_VALUE if
+     *         no operations are pending
+     */
+    public long maybeExpirePendingOperation(long currentTimeMs) {
+        // First abort any expired operations
+        long timeUntilAddVoterExpiration = addVoterHandlerState()
+            .map(state -> state.timeUntilOperationExpiration(currentTimeMs))
+            .orElse(Long.MAX_VALUE);
+
+        if (timeUntilAddVoterExpiration == 0) {
+            resetAddVoterHandlerState(Errors.REQUEST_TIMED_OUT, null, Optional.empty());
+        }
+
+        long timeUntilRemoveVoterExpiration = removeVoterHandlerState()
+            .map(state -> state.timeUntilOperationExpiration(currentTimeMs))
+            .orElse(Long.MAX_VALUE);
+
+        if (timeUntilRemoveVoterExpiration == 0) {
+            resetRemoveVoterHandlerState(Errors.REQUEST_TIMED_OUT, null, Optional.empty());
+        }
+
+        // Reread the timeouts and return the smaller of them
+        return Math.min(
+            addVoterHandlerState()
+                .map(state -> state.timeUntilOperationExpiration(currentTimeMs))
+                .orElse(Long.MAX_VALUE),
+            removeVoterHandlerState()
+                .map(state -> state.timeUntilOperationExpiration(currentTimeMs))
+                .orElse(Long.MAX_VALUE)
+        );
+    }
+
+    /**
+     * Resets all pending voter handler states, completing their futures with the specified error.
+     * <p>
+     * This method clears both add voter and remove voter handler states if they exist. Each
+     * pending operation's future is completed with the provided error.
+     *
+     * @param error the error to complete any pending operations with
+     */
+    public void maybeResetPendingVoterHandlerState(Errors error) {
+        resetAddVoterHandlerState(error, null, Optional.empty());
+        resetRemoveVoterHandlerState(error, null, Optional.empty());
+    }
+
+    /**
+     * Checks whether any voter change operation is currently pending.
+     * <p>
+     * This method first expires any operations that have timed out at the given timestamp,
+     * then returns true if either an add voter or remove voter operation remains pending.
+     *
+     * @param currentTimeMs the current time in milliseconds
+     * @return true if a voter change operation is pending, false otherwise
+     */
+    public boolean isOperationPending(long currentTimeMs) {
+        maybeExpirePendingOperation(currentTimeMs);
+        return addVoterHandlerState.isPresent() || removeVoterHandlerState.isPresent();
+    }
+}
diff --git a/raft/src/main/java/org/apache/kafka/raft/internals/DefaultRequestSender.java b/raft/src/main/java/org/apache/kafka/raft/internals/DefaultRequestSender.java
--- a/raft/src/main/java/org/apache/kafka/raft/internals/DefaultRequestSender.java
+++ b/raft/src/main/java/org/apache/kafka/raft/internals/DefaultRequestSender.java
@@ -18,15 +18,11 @@
 
 import org.apache.kafka.common.Node;
 import org.apache.kafka.common.network.ListenerName;
-import org.apache.kafka.common.protocol.ApiKeys;
 import org.apache.kafka.common.protocol.ApiMessage;
-import org.apache.kafka.common.protocol.Errors;
 import org.apache.kafka.common.utils.internals.LogContext;
 import org.apache.kafka.raft.NetworkChannel;
 import org.apache.kafka.raft.RaftMessageQueue;
 import org.apache.kafka.raft.RaftRequest;
-import org.apache.kafka.raft.RaftResponse;
-import org.apache.kafka.raft.RaftUtil;
 import org.apache.kafka.raft.RequestManager;
 
 import org.slf4j.Logger;
@@ -67,9 +63,7 @@ public OptionalLong send(
             long remainingBackoffMs = requestManager.remainingBackoffMs(destination, currentTimeMs);
             logger.debug("Connection for {} is backing off for {} ms", destination, remainingBackoffMs);
             return OptionalLong.empty();
-        }
-
-        if (!requestManager.isReady(destination, currentTimeMs)) {
+        } else if (!requestManager.isReady(destination, currentTimeMs)) {
             long remainingMs = requestManager.remainingRequestTimeMs(destination, currentTimeMs);
             logger.debug("Connection for {} has a pending request for {} ms", destination, remainingMs);
             return OptionalLong.empty();
@@ -85,24 +79,13 @@ public OptionalLong send(
             currentTimeMs
         );
 
-        requestMessage.completion.whenComplete((response, exception) -> {
-            if (exception != null) {
-                ApiKeys api = ApiKeys.forId(request.apiKey());
-                Errors error = Errors.forException(exception);
-                ApiMessage errorResponse = RaftUtil.errorResponse(api, error);
-
-                response = new RaftResponse.Inbound(
-                    correlationId,
-                    errorResponse,
-                    destination
-                );
-            }
-
-            messageQueue.add(response);
-        });
-
         requestManager.onRequestSent(destination, correlationId, currentTimeMs);
-        channel.send(requestMessage);
+        channel
+            .send(requestMessage)
+            .whenComplete(
+                (response, exception) -> messageQueue.add(response)
+            );
+
         logger.trace("Sent outbound request: {}", requestMessage);
 
         return OptionalLong.of(requestManager.remainingRequestTimeMs(destination, currentTimeMs));
diff --git a/raft/src/main/java/org/apache/kafka/raft/internals/FuturePurgatory.java b/raft/src/main/java/org/apache/kafka/raft/internals/FuturePurgatory.java
--- a/raft/src/main/java/org/apache/kafka/raft/internals/FuturePurgatory.java
+++ b/raft/src/main/java/org/apache/kafka/raft/internals/FuturePurgatory.java
@@ -16,76 +16,72 @@
  */
 package org.apache.kafka.raft.internals;
 
-import java.util.concurrent.CompletableFuture;
+import java.util.concurrent.CompletionStage;
 
 /**
  * Simple purgatory interface which supports waiting with expiration for a given threshold
  * to be reached. The threshold is specified through {@link #await(Comparable, long)}.
- * The returned future can be completed in the following ways:
+ * The returned stage can be completed in the following ways:
  *
- * 1) The future is completed successfully if the threshold value is reached
+ * 1) The stage is completed successfully if the threshold value is reached
  *    in a call to {@link #maybeComplete(Comparable, long)}.
- * 2) The future is completed successfully if {@link #completeAll(long)} is called.
- * 3) The future is completed exceptionally if {@link #completeAllExceptionally(Throwable)}
+ * 2) The stage is completed successfully if {@link #completeAll(long)} is called.
+ * 3) The stage is completed exceptionally if {@link #completeAllExceptionally(Throwable)}
  *    is called.
  * 4) If none of the above happens before the expiration of the timeout passed to
- *    {@link #await(Comparable, long)}, then the future will be completed exceptionally
+ *    {@link #await(Comparable, long)}, then the stage will be completed exceptionally
  *    with a {@link org.apache.kafka.common.errors.TimeoutException}.
  *
- * It is also possible for the future to be completed externally, but this should
- * generally be avoided.
- *
- * Note that the future objects should be organized in order so that completing awaiting
- * futures would stop early and not traverse all awaiting futures.
+ * Note that the stage objects should be organized in order so that completing awaiting
+ * stages would stop early and not traverse all awaiting stages.
  *
  * @param <T> threshold value type
  */
 public interface FuturePurgatory<T extends Comparable<T>> {
-
     /**
-     * Create a new future which is tracked by the purgatory.
+     * Create a new completion stage which is tracked by the purgatory.
      *
-     * @param threshold     the minimum value that must be reached for the future
+     * @param threshold     the minimum value that must be reached for the stage
      *                      to be successfully completed by {@link #maybeComplete(Comparable, long)}
      * @param maxWaitTimeMs the maximum time to wait for completion. If this
-     *                      timeout is reached, then the future will be completed exceptionally
+     *                      timeout is reached, then the stage will be completed exceptionally
      *                      with a {@link org.apache.kafka.common.errors.TimeoutException}
      *
-     * @return              the future tracking the expected completion
+     * @return              the stage tracking the expected completion
      */
-    CompletableFuture<Long> await(T threshold, long maxWaitTimeMs);
+    CompletionStage<Long> await(T threshold, long maxWaitTimeMs);
 
     /**
-     * Complete awaiting futures whose threshold value from {@link FuturePurgatory#await} are smaller
+     * Complete awaiting stages whose threshold value from {@link FuturePurgatory#await} are smaller
      * than the given threshold value. The completion callbacks will be triggered from the calling thread.
      *
-     * @param value         the threshold value used to determine which futures can be completed
+     * @param value         the threshold value used to determine which stages can be completed
      * @param currentTimeMs the current time in milliseconds that will be passed to
-     *                      {@link CompletableFuture#complete(Object)} when the futures are completed
+     *                      {@link CompletableFuture#complete(Object)} when the stages are completed
      */
     void maybeComplete(T value, long currentTimeMs);
 
     /**
-     * Complete all awaiting futures successfully.
+     * Complete all awaiting stages successfully.
      *
      * @param currentTimeMs the current time in milliseconds that will be passed to
-     *                      {@link CompletableFuture#complete(Object)} when the futures are completed
+     *                      {@link CompletableFuture#complete(Object)} when the stages are completed
      */
     void completeAll(long currentTimeMs);
 
     /**
-     * Complete all awaiting futures exceptionally. The completion callbacks will be
+     * Complete all awaiting stages exceptionally. The completion callbacks will be
      * triggered with the passed in exception.
      *
-     * @param exception     the current time in milliseconds that will be passed to
+     * @param exception     the exception that will be passed to
      *                      {@link CompletableFuture#completeExceptionally(Throwable)}
      */
     void completeAllExceptionally(Throwable exception);
 
     /**
-     * The number of currently waiting futures.
+     * The number of currently waiting stages.
      *
-     * @return the number of waiting futures
+     * @return the number of waiting stages
      */
     int numWaiting();
 }
diff --git a/raft/src/main/java/org/apache/kafka/raft/internals/RemoveVoterHandler.java b/raft/src/main/java/org/apache/kafka/raft/internals/RemoveVoterHandler.java
--- a/raft/src/main/java/org/apache/kafka/raft/internals/RemoveVoterHandler.java
+++ b/raft/src/main/java/org/apache/kafka/raft/internals/RemoveVoterHandler.java
@@ -33,6 +33,7 @@
 import java.util.Optional;
 import java.util.OptionalInt;
 import java.util.concurrent.CompletableFuture;
+import java.util.concurrent.CompletionStage;
 
 /**
  * This type implements the protocol for removing a voter from a KRaft partition.
@@ -74,13 +75,14 @@ public RemoveVoterHandler(
         this.logger = logContext.logger(RemoveVoterHandler.class);
     }
 
-    public CompletableFuture<RemoveRaftVoterResponseData> handleRemoveVoterRequest(
+    public CompletionStage<RemoveRaftVoterResponseData> handleRemoveVoterRequest(
         LeaderState<?> leaderState,
         ReplicaKey voterKey,
         long currentTimeMs
     ) {
+        var changeVoterState = leaderState.changeVoterState();
         // Check if there are any pending voter change requests
-        if (leaderState.isOperationPending(currentTimeMs)) {
+        if (changeVoterState.isOperationPending(currentTimeMs)) {
             return CompletableFuture.completedFuture(
                 RaftUtil.removeVoterResponse(
                     Errors.REQUEST_TIMED_OUT,
@@ -150,17 +152,20 @@ public CompletableFuture<RemoveRaftVoterResponseData> handleRemoveVoterRequest(
             leaderState.appendVotersRecord(newVoters.get(), currentTimeMs),
             time.timer(requestTimeoutMs)
         );
-        leaderState.resetRemoveVoterHandlerState(Errors.UNKNOWN_SERVER_ERROR, null, Optional.of(state));
+        changeVoterState.resetRemoveVoterHandlerState(Errors.UNKNOWN_SERVER_ERROR, null, Optional.of(state));
 
         return state.future();
     }
 
-    public void highWatermarkUpdated(LeaderState<?> leaderState) {
-        leaderState.removeVoterHandlerState().ifPresent(current ->
-            leaderState.highWatermark().ifPresent(highWatermark -> {
-                if (highWatermark.offset() > current.lastOffset()) {
+    public void highWatermarkUpdated(LeaderState<?> leaderState, long highWatermark) {
+        var changeVoterState = leaderState.changeVoterState();
+
+        changeVoterState
+            .removeVoterHandlerState()
+            .ifPresent(current -> {
+                if (highWatermark > current.lastOffset()) {
                     // VotersRecord with the removed voter was committed; complete the RPC
-                    leaderState.resetRemoveVoterHandlerState(Errors.NONE, null, Optional.empty());
+                    changeVoterState.resetRemoveVoterHandlerState(Errors.NONE, null, Optional.empty());
 
                     // Resign if the leader is not part of the new committed voter set
                     VoterSet voters = partitionState.lastVoterSet();
@@ -182,7 +187,6 @@ public void highWatermarkUpdated(LeaderState<?> leaderState) {
                         leaderState.requestResign();
                     }
                 }
-            })
-        );
+            });
     }
 }
diff --git a/raft/src/main/java/org/apache/kafka/raft/internals/ThresholdPurgatory.java b/raft/src/main/java/org/apache/kafka/raft/internals/ThresholdPurgatory.java
--- a/raft/src/main/java/org/apache/kafka/raft/internals/ThresholdPurgatory.java
+++ b/raft/src/main/java/org/apache/kafka/raft/internals/ThresholdPurgatory.java
@@ -20,6 +20,7 @@
 
 import java.util.NavigableMap;
 import java.util.concurrent.CompletableFuture;
+import java.util.concurrent.CompletionStage;
 import java.util.concurrent.ConcurrentNavigableMap;
 import java.util.concurrent.ConcurrentSkipListMap;
 import java.util.concurrent.atomic.AtomicLong;
@@ -35,7 +36,7 @@ public ThresholdPurgatory(ExpirationService expirationService) {
     }
 
     @Override
-    public CompletableFuture<Long> await(T threshold, long maxWaitTimeMs) {
+    public CompletionStage<Long> await(T threshold, long maxWaitTimeMs) {
         ThresholdKey<T> key = new ThresholdKey<>(idGenerator.incrementAndGet(), threshold);
         CompletableFuture<Long> future = expirationService.failAfter(maxWaitTimeMs);
         thresholdMap.put(key, future);
@@ -83,5 +84,4 @@ public int compareTo(ThresholdKey<T> o) {
             }
         }
     }
-
 }
diff --git a/raft/src/main/java/org/apache/kafka/raft/internals/UpdateVoterHandler.java b/raft/src/main/java/org/apache/kafka/raft/internals/UpdateVoterHandler.java
--- a/raft/src/main/java/org/apache/kafka/raft/internals/UpdateVoterHandler.java
+++ b/raft/src/main/java/org/apache/kafka/raft/internals/UpdateVoterHandler.java
@@ -23,7 +23,6 @@
 import org.apache.kafka.common.protocol.Errors;
 import org.apache.kafka.common.utils.internals.LogContext;
 import org.apache.kafka.raft.Endpoints;
-import org.apache.kafka.raft.LeaderAndEpoch;
 import org.apache.kafka.raft.LeaderState;
 import org.apache.kafka.raft.LogOffsetMetadata;
 import org.apache.kafka.raft.RaftUtil;
@@ -34,8 +33,8 @@
 import org.slf4j.Logger;
 
 import java.util.Optional;
-import java.util.OptionalInt;
 import java.util.concurrent.CompletableFuture;
+import java.util.concurrent.CompletionStage;
 
 /**
  * This type implements the protocol for updating a voter from a KRaft partition.
@@ -55,24 +54,21 @@
  * 7. Send the UpdateVoter successful response to the voter.
  */
 public final class UpdateVoterHandler {
-    private final OptionalInt localId;
     private final KRaftControlRecordStateMachine partitionState;
     private final ListenerName defaultListenerName;
     private final Logger log;
 
     public UpdateVoterHandler(
-        OptionalInt localId,
         KRaftControlRecordStateMachine partitionState,
         ListenerName defaultListenerName,
         LogContext logContext
     ) {
-        this.localId = localId;
         this.partitionState = partitionState;
         this.defaultListenerName = defaultListenerName;
         this.log = logContext.logger(getClass());
     }
 
-    public CompletableFuture<UpdateRaftVoterResponseData> handleUpdateVoterRequest(
+    public CompletionStage<UpdateRaftVoterResponseData> handleUpdateVoterRequest(
         LeaderState<?> leaderState,
         ListenerName requestListenerName,
         ReplicaKey voterKey,
@@ -81,15 +77,12 @@ public CompletableFuture<UpdateRaftVoterResponseData> handleUpdateVoterRequest(
         long currentTimeMs
     ) {
         // Check if there are any pending voter change requests
-        if (leaderState.isOperationPending(currentTimeMs)) {
+        if (leaderState.changeVoterState().isOperationPending(currentTimeMs)) {
             return CompletableFuture.completedFuture(
                 RaftUtil.updateVoterResponse(
                     Errors.REQUEST_TIMED_OUT,
                     requestListenerName,
-                    new LeaderAndEpoch(
-                        localId,
-                        leaderState.epoch()
-                    ),
+                    leaderState.leaderAndEpoch(),
                     leaderState.leaderEndpoints()
                 )
             );
@@ -102,10 +95,7 @@ public CompletableFuture<UpdateRaftVoterResponseData> handleUpdateVoterRequest(
                 RaftUtil.updateVoterResponse(
                     Errors.REQUEST_TIMED_OUT,
                     requestListenerName,
-                    new LeaderAndEpoch(
-                        localId,
-                        leaderState.epoch()
-                    ),
+                    leaderState.leaderAndEpoch(),
                     leaderState.leaderEndpoints()
                 )
             );
@@ -135,10 +125,7 @@ public CompletableFuture<UpdateRaftVoterResponseData> handleUpdateVoterRequest(
                     RaftUtil.updateVoterResponse(
                         Errors.REQUEST_TIMED_OUT,
                         requestListenerName,
-                        new LeaderAndEpoch(
-                            localId,
-                            leaderState.epoch()
-                        ),
+                        leaderState.leaderAndEpoch(),
                         leaderState.leaderEndpoints()
                     )
                 );
@@ -151,10 +138,7 @@ public CompletableFuture<UpdateRaftVoterResponseData> handleUpdateVoterRequest(
                 RaftUtil.updateVoterResponse(
                     Errors.REQUEST_TIMED_OUT,
                     requestListenerName,
-                    new LeaderAndEpoch(
-                        localId,
-                        leaderState.epoch()
-                    ),
+                    leaderState.leaderAndEpoch(),
                     leaderState.leaderEndpoints()
                 )
             );
@@ -165,10 +149,7 @@ public CompletableFuture<UpdateRaftVoterResponseData> handleUpdateVoterRequest(
                 RaftUtil.updateVoterResponse(
                     Errors.INVALID_REQUEST,
                     requestListenerName,
-                    new LeaderAndEpoch(
-                        localId,
-                        leaderState.epoch()
-                    ),
+                    leaderState.leaderAndEpoch(),
                     leaderState.leaderEndpoints()
                 )
             );
@@ -180,10 +161,7 @@ public CompletableFuture<UpdateRaftVoterResponseData> handleUpdateVoterRequest(
                 RaftUtil.updateVoterResponse(
                     Errors.INVALID_REQUEST,
                     requestListenerName,
-                    new LeaderAndEpoch(
-                        localId,
-                        leaderState.epoch()
-                    ),
+                    leaderState.leaderAndEpoch(),
                     leaderState.leaderEndpoints()
                 )
             );
@@ -207,10 +185,7 @@ public CompletableFuture<UpdateRaftVoterResponseData> handleUpdateVoterRequest(
                 RaftUtil.updateVoterResponse(
                     Errors.VOTER_NOT_FOUND,
                     requestListenerName,
-                    new LeaderAndEpoch(
-                        localId,
-                        leaderState.epoch()
-                    ),
+                    leaderState.leaderAndEpoch(),
                     leaderState.leaderEndpoints()
                 )
             );
@@ -244,7 +219,7 @@ private Optional<VoterSet> updateVoters(
             voters.updateVoterIgnoringDirectoryId(updatedVoter);
     }
 
-    private CompletableFuture<UpdateRaftVoterResponseData> storeUpdatedVoters(
+    private CompletionStage<UpdateRaftVoterResponseData> storeUpdatedVoters(
         LeaderState<?> leaderState,
         ReplicaKey voterKey,
         Optional<KRaftVersionUpgrade.Voters> inMemoryVoters,
@@ -277,10 +252,7 @@ private CompletableFuture<UpdateRaftVoterResponseData> storeUpdatedVoters(
                     RaftUtil.updateVoterResponse(
                         Errors.REQUEST_TIMED_OUT,
                         requestListenerName,
-                        new LeaderAndEpoch(
-                            localId,
-                            leaderState.epoch()
-                        ),
+                        leaderState.leaderAndEpoch(),
                         leaderState.leaderEndpoints()
                     )
                 );
@@ -294,10 +266,7 @@ private CompletableFuture<UpdateRaftVoterResponseData> storeUpdatedVoters(
             RaftUtil.updateVoterResponse(
                 Errors.NONE,
                 requestListenerName,
-                new LeaderAndEpoch(
-                    localId,
-                    leaderState.epoch()
-                ),
+                leaderState.leaderAndEpoch(),
                 leaderState.leaderEndpoints()
             )
         );
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
