#!/bin/bash
set -uxo pipefail

BASE_SHA="420e494b4ede9a16c4bfb59de099c797bcd7f5f1"

cd /testbed
# Keep local test servers from being routed through host proxy settings.
export NO_PROXY="localhost,127.0.0.1,0.0.0.0,::1${NO_PROXY:+,$NO_PROXY}"
export no_proxy="localhost,127.0.0.1,0.0.0.0,::1${no_proxy:+,$no_proxy}"
echo "OMNIGRIL_LOCAL_NO_PROXY_ADDED=1"


RUNNABLE_TEST_FILES=(
  backend/plugins/rootly/e2e/incident_test.go
  backend/plugins/rootly/tasks/incidents_collector_test.go
  backend/plugins/rootly/tasks/incidents_converter_test.go
  backend/plugins/rootly/tasks/incidents_extractor_test.go
  backend/plugins/table_info_test.go
  backend/test/e2e/services/server_startup_test.go
)
DELETED_TEST_PATCH_FILES=()

# --- Pre-patch cleanup: restore runnable targets if they existed at base, otherwise remove ---
for f in "${RUNNABLE_TEST_FILES[@]}"; do
  if git cat-file -e "${BASE_SHA}:$f" 2>/dev/null; then
    git checkout "${BASE_SHA}" -- "$f"
  else
    rm -f "$f"
  fi
done

# --- Apply test patch (content injected by harness) ---
TEST_PATCH_FILE="$(mktemp)"
cat > "$TEST_PATCH_FILE" <<'EOF_114329324912'
diff --git a/backend/plugins/rootly/e2e/incident_test.go b/backend/plugins/rootly/e2e/incident_test.go
new file mode 100644
--- /dev/null
+++ b/backend/plugins/rootly/e2e/incident_test.go
@@ -0,0 +1,126 @@
+/*
+Licensed to the Apache Software Foundation (ASF) under one or more
+contributor license agreements.  See the NOTICE file distributed with
+this work for additional information regarding copyright ownership.
+The ASF licenses this file to You under the Apache License, Version 2.0
+(the "License"); you may not use this file except in compliance with
+the License.  You may obtain a copy of the License at
+
+    http://www.apache.org/licenses/LICENSE-2.0
+
+Unless required by applicable law or agreed to in writing, software
+distributed under the License is distributed on an "AS IS" BASIS,
+WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
+See the License for the specific language governing permissions and
+limitations under the License.
+*/
+
+package e2e
+
+import (
+	"fmt"
+	"testing"
+
+	"github.com/apache/incubator-devlake/core/models/common"
+	"github.com/apache/incubator-devlake/core/models/domainlayer/ticket"
+	"github.com/apache/incubator-devlake/helpers/e2ehelper"
+	"github.com/apache/incubator-devlake/plugins/rootly/impl"
+	"github.com/apache/incubator-devlake/plugins/rootly/models"
+	"github.com/apache/incubator-devlake/plugins/rootly/tasks"
+	"github.com/stretchr/testify/require"
+)
+
+func TestIncidentDataFlow(t *testing.T) {
+	var plugin impl.Rootly
+	dataflowTester := e2ehelper.NewDataFlowTester(t, "rootly", plugin)
+	options := tasks.RootlyOptions{
+		ConnectionId: 1,
+		ServiceId:    "svc_01",
+		ServiceName:  "Payments",
+	}
+	taskData := &tasks.RootlyTaskData{
+		Options: &options,
+	}
+
+	// scope
+	dataflowTester.FlushTabler(&models.Service{})
+	service := models.Service{
+		Scope: common.Scope{
+			ConnectionId: options.ConnectionId,
+		},
+		Url:  fmt.Sprintf("https://rootly.com/account/services/%s", options.ServiceId),
+		Id:   options.ServiceId,
+		Name: options.ServiceName,
+	}
+	require.NoError(t, dataflowTester.Dal.CreateOrUpdate(&service))
+
+	// import raw data table
+	dataflowTester.ImportCsvIntoRawTable(
+		"./raw_tables/_raw_rootly_incidents.csv",
+		"_raw_rootly_incidents",
+	)
+
+	// verify extraction
+	dataflowTester.FlushTabler(&models.Incident{})
+	dataflowTester.FlushTabler(&models.User{})
+	dataflowTester.Subtask(tasks.ExtractIncidentsMeta, taskData)
+	dataflowTester.VerifyTableWithOptions(
+		models.Service{},
+		e2ehelper.TableOptions{
+			CSVRelPath:  "./snapshot_tables/_tool_rootly_services.csv",
+			IgnoreTypes: []any{common.Scope{}},
+		},
+	)
+	dataflowTester.VerifyTableWithOptions(
+		models.Incident{},
+		e2ehelper.TableOptions{
+			CSVRelPath:  "./snapshot_tables/_tool_rootly_incidents.csv",
+			IgnoreTypes: []any{common.NoPKModel{}},
+		},
+	)
+	dataflowTester.VerifyTableWithOptions(
+		models.User{},
+		e2ehelper.TableOptions{
+			CSVRelPath:  "./snapshot_tables/_tool_rootly_users.csv",
+			IgnoreTypes: []any{common.NoPKModel{}},
+		},
+	)
+
+	// verify conversion
+	dataflowTester.FlushTabler(&ticket.Board{})
+	dataflowTester.Subtask(tasks.ConvertServicesMeta, taskData)
+	dataflowTester.VerifyTableWithOptions(
+		ticket.Board{},
+		e2ehelper.TableOptions{
+			CSVRelPath:  "./snapshot_tables/boards.csv",
+			IgnoreTypes: []any{common.NoPKModel{}},
+		},
+	)
+
+	dataflowTester.FlushTabler(&ticket.Issue{})
+	dataflowTester.FlushTabler(&ticket.IssueAssignee{})
+	dataflowTester.FlushTabler(&ticket.BoardIssue{})
+	dataflowTester.Subtask(tasks.ConvertIncidentsMeta, taskData)
+	dataflowTester.VerifyTableWithOptions(
+		ticket.Issue{},
+		e2ehelper.TableOptions{
+			CSVRelPath:   "./snapshot_tables/issues.csv",
+			IgnoreTypes:  []any{common.NoPKModel{}},
+			IgnoreFields: []string{"original_project"},
+		},
+	)
+	dataflowTester.VerifyTableWithOptions(
+		ticket.IssueAssignee{},
+		e2ehelper.TableOptions{
+			CSVRelPath:  "./snapshot_tables/issue_assignees.csv",
+			IgnoreTypes: []any{common.NoPKModel{}},
+		},
+	)
+	dataflowTester.VerifyTableWithOptions(
+		ticket.BoardIssue{},
+		e2ehelper.TableOptions{
+			CSVRelPath:  "./snapshot_tables/board_issues.csv",
+			IgnoreTypes: []any{common.NoPKModel{}},
+		},
+	)
+}
diff --git a/backend/plugins/rootly/tasks/incidents_collector_test.go b/backend/plugins/rootly/tasks/incidents_collector_test.go
new file mode 100644
--- /dev/null
+++ b/backend/plugins/rootly/tasks/incidents_collector_test.go
@@ -0,0 +1,46 @@
+/*
+Licensed to the Apache Software Foundation (ASF) under one or more
+contributor license agreements.  See the NOTICE file distributed with
+this work for additional information regarding copyright ownership.
+The ASF licenses this file to You under the Apache License, Version 2.0
+(the "License"); you may not use this file except in compliance with
+the License.  You may obtain a copy of the License at
+
+    http://www.apache.org/licenses/LICENSE-2.0
+
+Unless required by applicable law or agreed to in writing, software
+distributed under the License is distributed on an "AS IS" BASIS,
+WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
+See the License for the specific language governing permissions and
+limitations under the License.
+*/
+
+package tasks
+
+import (
+	"testing"
+	"time"
+
+	"github.com/stretchr/testify/assert"
+)
+
+func TestBuildIncidentsQuery_FirstPageNoSince(t *testing.T) {
+	q := buildIncidentsQuery("svc_42", 100, 1, nil)
+	assert.Equal(t, "svc_42", q.Get("filter[service_ids]"))
+	assert.Equal(t, "100", q.Get("page[size]"))
+	assert.Equal(t, "1", q.Get("page[number]"))
+	assert.Equal(t, "-updated_at", q.Get("sort"))
+	assert.Equal(t, "", q.Get("filter[updated_at][gt]"))
+	assert.Equal(t, "", q.Get("filter[services]"), "regression guard: must be filter[service_ids], not filter[services]")
+}
+
+func TestBuildIncidentsQuery_SubsequentPage(t *testing.T) {
+	q := buildIncidentsQuery("svc_42", 100, 3, nil)
+	assert.Equal(t, "3", q.Get("page[number]"))
+}
+
+func TestBuildIncidentsQuery_WithSince(t *testing.T) {
+	since := time.Date(2026, 5, 1, 12, 0, 0, 0, time.UTC)
+	q := buildIncidentsQuery("svc_42", 100, 1, &since)
+	assert.Equal(t, "2026-05-01T12:00:00Z", q.Get("filter[updated_at][gt]"))
+}
diff --git a/backend/plugins/rootly/tasks/incidents_converter_test.go b/backend/plugins/rootly/tasks/incidents_converter_test.go
new file mode 100644
--- /dev/null
+++ b/backend/plugins/rootly/tasks/incidents_converter_test.go
@@ -0,0 +1,210 @@
+/*
+Licensed to the Apache Software Foundation (ASF) under one or more
+contributor license agreements.  See the NOTICE file distributed with
+this work for additional information regarding copyright ownership.
+The ASF licenses this file to You under the Apache License, Version 2.0
+(the "License"); you may not use this file except in compliance with
+the License.  You may obtain a copy of the License at
+
+    http://www.apache.org/licenses/LICENSE-2.0
+
+Unless required by applicable law or agreed to in writing, software
+distributed under the License is distributed on an "AS IS" BASIS,
+WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
+See the License for the specific language governing permissions and
+limitations under the License.
+*/
+
+package tasks
+
+import (
+	"testing"
+	"time"
+
+	"github.com/stretchr/testify/assert"
+	"github.com/stretchr/testify/require"
+
+	"github.com/apache/incubator-devlake/core/models/domainlayer/ticket"
+	"github.com/apache/incubator-devlake/plugins/rootly/models"
+)
+
+func TestMapStatus(t *testing.T) {
+	cases := []struct {
+		in            string
+		expectMapped  string
+		expectedKnown bool
+	}{
+		{"triage", ticket.TODO, true},
+		{"started", ticket.TODO, true},
+		{"mitigated", ticket.IN_PROGRESS, true},
+		{"resolved", ticket.DONE, true},
+		{"closed", ticket.DONE, true},
+		{"cancelled", ticket.DONE, true},
+		{"wat", ticket.IN_PROGRESS, false},
+		{"", ticket.IN_PROGRESS, false},
+	}
+	for _, c := range cases {
+		t.Run(c.in, func(t *testing.T) {
+			mapped, known := mapStatus(c.in)
+			assert.Equal(t, c.expectMapped, mapped)
+			assert.Equal(t, c.expectedKnown, known)
+		})
+	}
+}
+
+func TestMapStatusDoesNotPanic(t *testing.T) {
+	assert.NotPanics(t, func() {
+		_, _ = mapStatus("brand-new-status-rootly-invented-yesterday")
+	})
+}
+
+func TestMapSeverityToPriority(t *testing.T) {
+	cases := []struct {
+		in       string
+		expected string
+	}{
+		{"sev0", "CRITICAL"},
+		{"SEV0", "CRITICAL"},
+		{"Sev0", "CRITICAL"},
+		{"sev1", "HIGH"},
+		{"SEV1", "HIGH"},
+		{"sev2", "MEDIUM"},
+		{"sev3", "LOW"},
+		{"sev4", "LOW"},
+		{"sev5", "sev5"},
+		{"critical-ish", "critical-ish"},
+		{"", ""},
+	}
+	for _, c := range cases {
+		t.Run(c.in, func(t *testing.T) {
+			assert.Equal(t, c.expected, mapSeverityToPriority(c.in))
+		})
+	}
+}
+
+func TestComputeLeadTime_Resolved(t *testing.T) {
+	started := time.Date(2026, 5, 10, 10, 0, 0, 0, time.UTC)
+	resolved := time.Date(2026, 5, 10, 11, 30, 0, 0, time.UTC)
+	leadTime, resolutionDate := computeLeadTime(started, &resolved)
+	require.NotNil(t, leadTime)
+	require.NotNil(t, resolutionDate)
+	assert.Equal(t, uint(90), *leadTime)
+	assert.Equal(t, resolved, *resolutionDate)
+}
+
+func TestComputeLeadTime_Unresolved(t *testing.T) {
+	started := time.Date(2026, 5, 10, 10, 0, 0, 0, time.UTC)
+	leadTime, resolutionDate := computeLeadTime(started, nil)
+	assert.Nil(t, leadTime)
+	assert.Nil(t, resolutionDate)
+}
+
+func TestComputeLeadTime_ZeroDuration(t *testing.T) {
+	started := time.Date(2026, 5, 10, 10, 0, 0, 0, time.UTC)
+	resolved := started
+	leadTime, resolutionDate := computeLeadTime(started, &resolved)
+	require.NotNil(t, leadTime)
+	require.NotNil(t, resolutionDate)
+	assert.Equal(t, uint(0), *leadTime)
+}
+
+func TestComputeLeadTime_ResolvedBeforeStarted(t *testing.T) {
+	started := time.Date(2026, 5, 10, 11, 0, 0, 0, time.UTC)
+	resolved := time.Date(2026, 5, 10, 10, 0, 0, 0, time.UTC)
+	leadTime, resolutionDate := computeLeadTime(started, &resolved)
+	assert.Nil(t, leadTime)
+	assert.Nil(t, resolutionDate)
+}
+
+func TestIssueKeyFor(t *testing.T) {
+	cases := []struct {
+		name     string
+		incident models.Incident
+		expected string
+	}{
+		{"positive sequential id", models.Incident{Number: 42, Id: "inc_abc"}, "42"},
+		{"zero sequential id falls back to slug", models.Incident{Number: 0, Id: "inc_abc"}, "inc_abc"},
+		{"negative sequential id falls back to slug", models.Incident{Number: -1, Id: "inc_abc"}, "inc_abc"},
+	}
+	for _, c := range cases {
+		t.Run(c.name, func(t *testing.T) {
+			assert.Equal(t, c.expected, issueKeyFor(&c.incident))
+		})
+	}
+}
+
+func TestAssigneeDedup(t *testing.T) {
+	cases := []struct {
+		name     string
+		incident models.Incident
+		expected []string
+	}{
+		{
+			name:     "all roles empty",
+			incident: models.Incident{},
+			expected: []string{},
+		},
+		{
+			name:     "single creator",
+			incident: models.Incident{CreatorUserId: "u1"},
+			expected: []string{"u1"},
+		},
+		{
+			name: "same user in creator and resolver",
+			incident: models.Incident{
+				CreatorUserId:    "u1",
+				ResolvedByUserId: "u1",
+			},
+			expected: []string{"u1"},
+		},
+		{
+			name: "distinct users across all roles",
+			incident: models.Incident{
+				CreatorUserId:     "u1",
+				StartedByUserId:   "u2",
+				MitigatedByUserId: "u3",
+				ResolvedByUserId:  "u4",
+				ClosedByUserId:    "u5",
+			},
+			expected: []string{"u1", "u2", "u3", "u4", "u5"},
+		},
+		{
+			name: "empty interleaved with populated",
+			incident: models.Incident{
+				CreatorUserId:     "u1",
+				StartedByUserId:   "",
+				MitigatedByUserId: "u2",
+				ResolvedByUserId:  "",
+				ClosedByUserId:    "u1",
+			},
+			expected: []string{"u1", "u2"},
+		},
+	}
+	for _, c := range cases {
+		t.Run(c.name, func(t *testing.T) {
+			seen := map[string]bool{}
+			var got []string
+			for _, uid := range c.incident.RoleUserIds() {
+				if uid == "" || seen[uid] {
+					continue
+				}
+				seen[uid] = true
+				got = append(got, uid)
+			}
+			if len(c.expected) == 0 {
+				assert.Empty(t, got)
+			} else {
+				assert.Equal(t, c.expected, got)
+			}
+		})
+	}
+}
+
+func TestMapStatus_MitigatedIsKnown(t *testing.T) {
+	mapped, known := mapStatus("mitigated")
+	assert.Equal(t, ticket.IN_PROGRESS, mapped)
+	assert.True(t, known)
+	mapped, known = mapStatus("something-else")
+	assert.Equal(t, ticket.IN_PROGRESS, mapped)
+	assert.False(t, known)
+}
diff --git a/backend/plugins/rootly/tasks/incidents_extractor_test.go b/backend/plugins/rootly/tasks/incidents_extractor_test.go
new file mode 100644
--- /dev/null
+++ b/backend/plugins/rootly/tasks/incidents_extractor_test.go
@@ -0,0 +1,382 @@
+/*
+Licensed to the Apache Software Foundation (ASF) under one or more
+contributor license agreements.  See the NOTICE file distributed with
+this work for additional information regarding copyright ownership.
+The ASF licenses this file to You under the Apache License, Version 2.0
+(the "License"); you may not use this file except in compliance with
+the License.  You may obtain a copy of the License at
+
+    http://www.apache.org/licenses/LICENSE-2.0
+
+Unless required by applicable law or agreed to in writing, software
+distributed under the License is distributed on an "AS IS" BASIS,
+WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
+See the License for the specific language governing permissions and
+limitations under the License.
+*/
+
+package tasks
+
+import (
+	"testing"
+	"time"
+
+	"github.com/stretchr/testify/assert"
+	"github.com/stretchr/testify/require"
+
+	"github.com/apache/incubator-devlake/plugins/rootly/models"
+)
+
+const baseHappyPathActive = `{
+	"id": "inc_01",
+	"type": "incidents",
+	"attributes": {
+		"sequential_id": 42,
+		"title": "db outage",
+		"summary": "replica lag blew past threshold",
+		"url": "https://rootly.example.com/incidents/inc_01",
+		"status": "started",
+		"severity": {"data": {"id": "sev-uuid-1", "type": "severities", "attributes": {"slug": "sev1", "name": "SEV1", "severity": "high"}}},
+		"started_at": "2026-05-10T10:00:00Z",
+		"updated_at": "2026-05-10T10:05:00Z",
+		"user": {"data": {"id": "usr_100", "type": "users", "attributes": {"name": "Reporter One", "full_name": "Reporter One", "email": "reporter@example.com"}}}
+	},
+	"relationships": {
+		"services": {"data": [{"id": "svc_02", "type": "services"}]}
+	}
+}`
+
+func newTestOptions() *RootlyOptions {
+	return &RootlyOptions{
+		ConnectionId: 7,
+		ServiceId:    "svc_02",
+	}
+}
+
+func collectUsers(results []interface{}) []*models.User {
+	users := []*models.User{}
+	for _, r := range results {
+		if u, ok := r.(*models.User); ok {
+			users = append(users, u)
+		}
+	}
+	return users
+}
+
+func TestExtractRootlyIncident_HappyPathActive(t *testing.T) {
+	op := newTestOptions()
+	results, err := extractRootlyIncident([]byte(baseHappyPathActive), op)
+	require.NoError(t, err)
+	require.Len(t, results, 2)
+
+	incident, ok := results[0].(*models.Incident)
+	require.True(t, ok, "first result should be *models.Incident")
+	assert.Equal(t, uint64(7), incident.ConnectionId)
+	assert.Equal(t, "inc_01", incident.Id)
+	assert.Equal(t, 42, incident.Number)
+	assert.Equal(t, "svc_02", incident.ServiceId)
+	assert.Equal(t, "db outage", incident.Title)
+	assert.Equal(t, "replica lag blew past threshold", incident.Summary)
+	assert.Equal(t, "https://rootly.example.com/incidents/inc_01", incident.Url)
+	assert.Equal(t, "started", incident.Status)
+	assert.Equal(t, "sev1", incident.Severity)
+	assert.Equal(t, time.Date(2026, 5, 10, 10, 0, 0, 0, time.UTC), incident.StartedDate)
+	assert.Nil(t, incident.AcknowledgedDate)
+	assert.Nil(t, incident.MitigatedDate)
+	assert.Nil(t, incident.ResolvedDate)
+	assert.Equal(t, time.Date(2026, 5, 10, 10, 5, 0, 0, time.UTC), incident.UpdatedDate)
+
+	assert.Equal(t, "usr_100", incident.CreatorUserId)
+	assert.Empty(t, incident.StartedByUserId)
+	assert.Empty(t, incident.MitigatedByUserId)
+	assert.Empty(t, incident.ResolvedByUserId)
+	assert.Empty(t, incident.ClosedByUserId)
+
+	users := collectUsers(results)
+	require.Len(t, users, 1)
+	assert.Equal(t, "usr_100", users[0].Id)
+	assert.Equal(t, uint64(7), users[0].ConnectionId)
+	assert.Equal(t, "Reporter One", users[0].Name)
+	assert.Equal(t, "reporter@example.com", users[0].Email)
+}
+
+func TestExtractRootlyIncident_Resolved(t *testing.T) {
+	raw := []byte(`{
+		"id": "inc_02",
+		"type": "incidents",
+		"attributes": {
+			"sequential_id": 43,
+			"title": "cache cleared",
+			"status": "resolved",
+			"severity": {"data": {"id": "sev-uuid-3", "type": "severities", "attributes": {"slug": "sev3", "severity": "low"}}},
+			"started_at": "2026-05-09T08:00:00Z",
+			"acknowledged_at": "2026-05-09T08:05:00Z",
+			"mitigated_at": "2026-05-09T08:30:00Z",
+			"resolved_at": "2026-05-09T09:00:00Z",
+			"updated_at": "2026-05-09T09:01:00Z",
+			"user": {"data": {"id": "usr_100", "type": "users", "attributes": {"full_name": "Reporter One"}}},
+			"resolved_by": {"data": {"id": "usr_200", "type": "users", "attributes": {"full_name": "Resolver Two"}}}
+		},
+		"relationships": {
+			"services": {"data": [{"id": "svc_02", "type": "services"}]}
+		}
+	}`)
+	op := newTestOptions()
+	results, err := extractRootlyIncident(raw, op)
+	require.NoError(t, err)
+	require.Len(t, results, 3)
+
+	incident := results[0].(*models.Incident)
+	require.NotNil(t, incident.AcknowledgedDate)
+	require.NotNil(t, incident.MitigatedDate)
+	require.NotNil(t, incident.ResolvedDate)
+	assert.Equal(t, "resolved", incident.Status)
+	assert.Equal(t, time.Date(2026, 5, 9, 9, 0, 0, 0, time.UTC), *incident.ResolvedDate)
+	assert.Equal(t, time.Date(2026, 5, 9, 8, 30, 0, 0, time.UTC), *incident.MitigatedDate)
+	assert.Equal(t, time.Date(2026, 5, 9, 8, 5, 0, 0, time.UTC), *incident.AcknowledgedDate)
+
+	assert.Equal(t, "usr_100", incident.CreatorUserId)
+	assert.Equal(t, "usr_200", incident.ResolvedByUserId)
+
+	users := collectUsers(results)
+	require.Len(t, users, 2)
+	ids := map[string]string{}
+	for _, u := range users {
+		ids[u.Id] = u.Name
+	}
+	assert.Equal(t, "Reporter One", ids["usr_100"])
+	assert.Equal(t, "Resolver Two", ids["usr_200"])
+}
+
+func TestExtractRootlyIncident_MissingOptionalTimestamps(t *testing.T) {
+	raw := []byte(`{
+		"id": "inc_03",
+		"type": "incidents",
+		"attributes": {
+			"sequential_id": 44,
+			"title": "ongoing issue",
+			"status": "started",
+			"started_at": "2026-05-10T12:00:00Z",
+			"updated_at": "2026-05-10T12:05:00Z"
+		},
+		"relationships": {
+			"services": {"data": [{"id": "svc_02", "type": "services"}]}
+		}
+	}`)
+	op := newTestOptions()
+	results, err := extractRootlyIncident(raw, op)
+	require.NoError(t, err)
+	require.Len(t, results, 1)
+	incident := results[0].(*models.Incident)
+	assert.Nil(t, incident.MitigatedDate)
+	assert.Nil(t, incident.ResolvedDate)
+	assert.Nil(t, incident.AcknowledgedDate)
+}
+
+func TestExtractRootlyIncident_NullSeverity(t *testing.T) {
+	raw := []byte(`{
+		"id": "inc_04",
+		"type": "incidents",
+		"attributes": {
+			"sequential_id": 45,
+			"title": "no sev yet",
+			"status": "mitigated",
+			"severity": null,
+			"started_at": "2026-05-10T14:00:00Z",
+			"updated_at": "2026-05-10T14:05:00Z"
+		},
+		"relationships": {
+			"services": {"data": [{"id": "svc_02", "type": "services"}]}
+		}
+	}`)
+	op := newTestOptions()
+	results, err := extractRootlyIncident(raw, op)
+	require.NoError(t, err)
+	require.Len(t, results, 1)
+	incident := results[0].(*models.Incident)
+	assert.Equal(t, "", incident.Severity)
+}
+
+func TestExtractRootlyIncident_NoRolesFilled(t *testing.T) {
+	raw := []byte(`{
+		"id": "inc_05",
+		"type": "incidents",
+		"attributes": {
+			"sequential_id": 46,
+			"title": "ghost incident",
+			"status": "started",
+			"started_at": "2026-05-10T15:00:00Z",
+			"updated_at": "2026-05-10T15:05:00Z",
+			"user": null,
+			"started_by": null,
+			"mitigated_by": null,
+			"resolved_by": null,
+			"closed_by": null
+		},
+		"relationships": {
+			"services": {"data": [{"id": "svc_02", "type": "services"}]}
+		}
+	}`)
+	op := newTestOptions()
+	results, err := extractRootlyIncident(raw, op)
+	require.NoError(t, err)
+	require.Len(t, results, 1)
+	incident := results[0].(*models.Incident)
+	assert.Empty(t, incident.CreatorUserId)
+	assert.Empty(t, incident.StartedByUserId)
+	assert.Empty(t, incident.MitigatedByUserId)
+	assert.Empty(t, incident.ResolvedByUserId)
+	assert.Empty(t, incident.ClosedByUserId)
+	assert.Empty(t, collectUsers(results))
+}
+
+func TestExtractRootlyIncident_SameUserInMultipleRoles(t *testing.T) {
+	raw := []byte(`{
+		"id": "inc_dup",
+		"type": "incidents",
+		"attributes": {
+			"sequential_id": 47,
+			"title": "solo fire",
+			"status": "resolved",
+			"started_at": "2026-05-10T16:00:00Z",
+			"resolved_at": "2026-05-10T16:30:00Z",
+			"updated_at": "2026-05-10T16:31:00Z",
+			"user":        {"data": {"id": "usr_100", "type": "users", "attributes": {"full_name": "Solo Operator"}}},
+			"resolved_by": {"data": {"id": "usr_100", "type": "users", "attributes": {"full_name": "Solo Operator"}}}
+		},
+		"relationships": {
+			"services": {"data": [{"id": "svc_02", "type": "services"}]}
+		}
+	}`)
+	op := newTestOptions()
+	results, err := extractRootlyIncident(raw, op)
+	require.NoError(t, err)
+	require.Len(t, results, 2, "one incident + one deduped user")
+
+	incident := results[0].(*models.Incident)
+	assert.Equal(t, "usr_100", incident.CreatorUserId)
+	assert.Equal(t, "usr_100", incident.ResolvedByUserId)
+
+	users := collectUsers(results)
+	require.Len(t, users, 1)
+	assert.Equal(t, "usr_100", users[0].Id)
+	assert.Equal(t, "Solo Operator", users[0].Name)
+}
+
+func TestExtractRootlyIncident_UserNamePreference(t *testing.T) {
+	raw := []byte(`{
+		"id": "inc_names",
+		"type": "incidents",
+		"attributes": {
+			"sequential_id": 48,
+			"title": "name preference",
+			"status": "started",
+			"started_at": "2026-05-10T17:00:00Z",
+			"updated_at": "2026-05-10T17:05:00Z",
+			"user":        {"data": {"id": "usr_full",  "type": "users", "attributes": {"full_name": "Full Name",  "name": "Ignored", "email": "ignored@example.com"}}},
+			"started_by":  {"data": {"id": "usr_short", "type": "users", "attributes": {"name": "Short Name",      "email": "ignored@example.com"}}},
+			"resolved_by": {"data": {"id": "usr_mail",  "type": "users", "attributes": {"email": "fallback@example.com"}}}
+		},
+		"relationships": {
+			"services": {"data": [{"id": "svc_02", "type": "services"}]}
+		}
+	}`)
+	op := newTestOptions()
+	results, err := extractRootlyIncident(raw, op)
+	require.NoError(t, err)
+
+	users := collectUsers(results)
+	require.Len(t, users, 3)
+	byId := map[string]*models.User{}
+	for _, u := range users {
+		byId[u.Id] = u
+	}
+	require.Contains(t, byId, "usr_full")
+	require.Contains(t, byId, "usr_short")
+	require.Contains(t, byId, "usr_mail")
+	assert.Equal(t, "Full Name", byId["usr_full"].Name)
+	assert.Equal(t, "Short Name", byId["usr_short"].Name)
+	assert.Equal(t, "fallback@example.com", byId["usr_mail"].Name)
+}
+
+func TestExtractRootlyIncident_WrongServiceSkipped(t *testing.T) {
+	raw := []byte(`{
+		"id": "inc_wrong_svc",
+		"type": "incidents",
+		"attributes": {
+			"sequential_id": 49,
+			"title": "other service",
+			"status": "started",
+			"started_at": "2026-05-10T18:00:00Z",
+			"updated_at": "2026-05-10T18:05:00Z"
+		},
+		"relationships": {
+			"services": {"data": [{"id": "svc_99", "type": "services"}]}
+		}
+	}`)
+	op := newTestOptions()
+	results, err := extractRootlyIncident(raw, op)
+	require.NoError(t, err)
+	assert.Empty(t, results, "incident for unrelated service should produce no rows")
+}
+
+func TestExtractRootlyIncident_EmptyServicesAccepted(t *testing.T) {
+	raw := []byte(`{
+		"id": "inc_no_svc",
+		"type": "incidents",
+		"attributes": {
+			"sequential_id": 50,
+			"title": "services omitted",
+			"status": "started",
+			"started_at": "2026-05-10T19:00:00Z",
+			"updated_at": "2026-05-10T19:05:00Z"
+		}
+	}`)
+	op := newTestOptions()
+	results, err := extractRootlyIncident(raw, op)
+	require.NoError(t, err)
+	require.Len(t, results, 1)
+	incident := results[0].(*models.Incident)
+	assert.Equal(t, "svc_02", incident.ServiceId)
+}
+
+func TestExtractRootlyIncident_MissingStartedAtReturnsError(t *testing.T) {
+	raw := []byte(`{
+		"id": "inc_bad",
+		"type": "incidents",
+		"attributes": {
+			"sequential_id": 51,
+			"title": "bad row",
+			"status": "started",
+			"updated_at": "2026-05-10T20:05:00Z"
+		},
+		"relationships": {
+			"services": {"data": [{"id": "svc_02", "type": "services"}]}
+		}
+	}`)
+	op := newTestOptions()
+	_, err := extractRootlyIncident(raw, op)
+	assert.Error(t, err)
+}
+
+func TestExtractRootlyIncident_MissingSequentialId(t *testing.T) {
+	raw := []byte(`{
+		"id": "inc_no_num",
+		"type": "incidents",
+		"attributes": {
+			"title": "no sequential id",
+			"status": "started",
+			"started_at": "2026-05-10T21:00:00Z",
+			"updated_at": "2026-05-10T21:05:00Z"
+		},
+		"relationships": {
+			"services": {"data": [{"id": "svc_02", "type": "services"}]}
+		}
+	}`)
+	op := newTestOptions()
+	results, err := extractRootlyIncident(raw, op)
+	require.NoError(t, err)
+	require.Len(t, results, 1)
+	incident := results[0].(*models.Incident)
+	assert.Equal(t, 0, incident.Number)
+}
diff --git a/backend/plugins/table_info_test.go b/backend/plugins/table_info_test.go
--- a/backend/plugins/table_info_test.go
+++ b/backend/plugins/table_info_test.go
@@ -49,6 +49,7 @@ import (
 	pagerduty "github.com/apache/incubator-devlake/plugins/pagerduty/impl"
 	q_dev "github.com/apache/incubator-devlake/plugins/q_dev/impl"
 	refdiff "github.com/apache/incubator-devlake/plugins/refdiff/impl"
+	rootly "github.com/apache/incubator-devlake/plugins/rootly/impl"
 	slack "github.com/apache/incubator-devlake/plugins/slack/impl"
 	sonarqube "github.com/apache/incubator-devlake/plugins/sonarqube/impl"
 	starrocks "github.com/apache/incubator-devlake/plugins/starrocks/impl"
@@ -88,6 +89,7 @@ func Test_GetPluginTablesInfo(t *testing.T) {
 	checker.FeedIn("org", org.Org{}.GetTablesInfo)
 	checker.FeedIn("pagerduty/models", pagerduty.PagerDuty{}.GetTablesInfo)
 	checker.FeedIn("refdiff/models", refdiff.RefDiff{}.GetTablesInfo)
+	checker.FeedIn("rootly/models", rootly.Rootly{}.GetTablesInfo)
 	checker.FeedIn("slack/models", slack.Slack{}.GetTablesInfo)
 	checker.FeedIn("sonarqube/models", sonarqube.Sonarqube{}.GetTablesInfo)
 	checker.FeedIn("starrocks", starrocks.StarRocks{}.GetTablesInfo)
diff --git a/backend/test/e2e/services/server_startup_test.go b/backend/test/e2e/services/server_startup_test.go
--- a/backend/test/e2e/services/server_startup_test.go
+++ b/backend/test/e2e/services/server_startup_test.go
@@ -39,6 +39,7 @@ import (
 	org "github.com/apache/incubator-devlake/plugins/org/impl"
 	pagerduty "github.com/apache/incubator-devlake/plugins/pagerduty/impl"
 	refdiff "github.com/apache/incubator-devlake/plugins/refdiff/impl"
+	rootly "github.com/apache/incubator-devlake/plugins/rootly/impl"
 	slack "github.com/apache/incubator-devlake/plugins/slack/impl"
 	sonarqube "github.com/apache/incubator-devlake/plugins/sonarqube/impl"
 	starrocks "github.com/apache/incubator-devlake/plugins/starrocks/impl"
@@ -78,6 +79,7 @@ func loadGoPlugins() []plugin.PluginMeta {
 		org.Org{},
 		pagerduty.PagerDuty{},
 		refdiff.RefDiff{},
+		rootly.Rootly{},
 		slack.Slack{},
 		sonarqube.Sonarqube{},
 		starrocks.StarRocks{},
EOF_114329324912
if [ -s "$TEST_PATCH_FILE" ]; then
  git apply -v "$TEST_PATCH_FILE"
fi
rm -f "$TEST_PATCH_FILE"

# --- If patch deletes tests, remove and verify absent (none for this task) ---
for f in "${DELETED_TEST_PATCH_FILES[@]}"; do
  rm -f "$f"
done
for f in "${DELETED_TEST_PATCH_FILES[@]}"; do
  if [ -e "$f" ]; then
    echo "ERROR: deleted-by-patch file still exists: $f"
    exit 2
  fi
done

# --- Go module root is backend/ ---
cd /testbed/backend

# Deduplicate runnable list (defensive)
mapfile -t RUNNABLE_UNIQ < <(printf '%s\n' "${RUNNABLE_TEST_FILES[@]}" | awk '!seen[$0]++')

# --- Skip E2E packages if E2E_DB_URL is not set ---
should_skip_e2e=0
if [ -z "${E2E_DB_URL:-}" ]; then
  should_skip_e2e=1
  echo "NOTE: E2E_DB_URL is not set; skipping E2E packages to avoid hard failure."
fi

is_e2e_pkg() {
  local pkg="$1"
  [[ "$pkg" == ./*/e2e* ]] || [[ "$pkg" == ./test/e2e* ]]
}

# --- Build exact package list from each target file's directory (module-relative) ---
# Guard against overly-broad ./plugins which is known to fail at this commit.
declare -A DIR_TO_PKG=()
declare -A FILE_TO_DIR=()
TARGET_PKGS=()

for f in "${RUNNABLE_UNIQ[@]}"; do
  rel="${f#backend/}"              # module-relative file path
  d="$(dirname "$rel")"            # module-relative directory
  FILE_TO_DIR["$f"]="$d"

  # Avoid running the meta-package ./plugins (too broad; pulls in missing mocks deps).
  if [ "$d" = "plugins" ]; then
    DIR_TO_PKG["$d"]="__SKIP_META_PLUGINS__"
    continue
  fi

  if [ -z "${DIR_TO_PKG[$d]+x}" ]; then
    if go list "./$d" >/dev/null 2>&1; then
      DIR_TO_PKG["$d"]="./$d"
      TARGET_PKGS+=("./$d")
    else
      DIR_TO_PKG["$d"]=""
    fi
  fi
done

rc=0
declare -A PKG_STATUS=()   # key: package arg (./path), value: PASS/FAIL/SKIP

set +e
if [ "${#RUNNABLE_UNIQ[@]}" -eq 0 ]; then
  go test -p 1 ./...
  cmd_rc=$?
  rc=$cmd_rc
else
  for pkg in "${TARGET_PKGS[@]}"; do
    if [ $should_skip_e2e -eq 1 ] && is_e2e_pkg "$pkg"; then
      echo "=== SKIP_PACKAGE $pkg (missing E2E_DB_URL) ==="
      PKG_STATUS["$pkg"]="SKIP"
      continue
    fi

    echo "=== RUN_PACKAGE $pkg ==="
    go test -p 1 -count=1 -v "$pkg"
    cmd_rc=$?
    if [ $cmd_rc -eq 0 ]; then
      PKG_STATUS["$pkg"]="PASS"
    else
      PKG_STATUS["$pkg"]="FAIL"
      rc=1
    fi
    echo "=== END_PACKAGE $pkg rc=$cmd_rc ==="
  done
fi
set -e

# --- Per-file status output (required) ---
echo "=== TARGET_FILE_STATUS ==="
for f in "${RUNNABLE_UNIQ[@]}"; do
  d="${FILE_TO_DIR[$f]}"
  pkg="${DIR_TO_PKG[$d]:-}"

  # Special handling: do not run ./plugins; mark as SKIP (environment/commit limitation).
  if [ "$pkg" = "__SKIP_META_PLUGINS__" ]; then
    echo "$f SKIP (not running meta-package ./plugins)"
    continue
  fi

  if [ -z "$pkg" ]; then
    echo "$f UNKNOWN"
    rc=1
    continue
  fi

  if [ $should_skip_e2e -eq 1 ] && is_e2e_pkg "$pkg"; then
    echo "$f SKIP"
    continue
  fi

  st="${PKG_STATUS[$pkg]:-UNKNOWN}"
  echo "$f $st"
  if [ "$st" = "FAIL" ] || [ "$st" = "UNKNOWN" ]; then
    rc=1
  fi
done

echo "OMNIGRIL_EXIT_CODE=$rc"
set +e

# --- Cleanup: reset runnable targets back to base state (best-effort) ---
cd /testbed
for f in "${RUNNABLE_UNIQ[@]}"; do
  if git cat-file -e "${BASE_SHA}:$f" 2>/dev/null; then
    git checkout "${BASE_SHA}" -- "$f" || true
  else
    rm -f "$f" || true
  fi
done
exit $rc
