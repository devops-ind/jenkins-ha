// Jenkins Overview Dashboard
// Modern Grafonnet implementation for comprehensive Jenkins monitoring
// Covers: Build metrics, Job status, Agents, Queue, DORA metrics

local g = import 'grafonnet/gen/g.libsonnet';
local common = import './lib/common.libsonnet';
local dashboard = g.dashboard;
local row = g.row;

// Dashboard configuration
local dashboardTitle = 'Jenkins Overview';
local dashboardUid = 'jenkins-overview-modern';
local dashboardDescription = 'Comprehensive Jenkins monitoring dashboard using modern Grafonnet architecture';

// Row helper function
local createRow(title) = row.new(title=title, collapsed=false);

// Create the main dashboard
common.defaultDashboard(
  title=dashboardTitle,
  description=dashboardDescription,
  uid=dashboardUid,
  team='',
  environment='blue',
  tags=['jenkins', 'ci-cd', 'pipelines', 'devops']
)
.addPanels([
  // Row: Jenkins Status
  createRow('Jenkins Status')
  .addPanel(
    common.statPanel(
      title='Jenkins Masters Up',
      query='count(jenkins_up{jenkins_team="$team"})',
      unit='short',
      decimals=0,
    ),
    gridPos=common.gridPos(h=8, w=4, x=0, y=1)
  )
  .addPanel(
    common.statPanel(
      title='Online Executors',
      query='sum(jenkins_executor_count_value{jenkins_team="$team"}) - sum(jenkins_executor_in_use_count_value{jenkins_team="$team"})',
      unit='short',
      decimals=0,
    ),
    gridPos=common.gridPos(h=8, w=4, x=4, y=1)
  )
  .addPanel(
    common.statPanel(
      title='Busy Executors',
      query='sum(jenkins_executor_in_use_count_value{jenkins_team="$team"})',
      unit='short',
      decimals=0,
    ),
    gridPos=common.gridPos(h=8, w=4, x=8, y=1)
  )
  .addPanel(
    common.statPanel(
      title='Queue Length',
      query='sum(jenkins_queue_size{jenkins_team="$team"})',
      unit='short',
      decimals=0,
    ),
    gridPos=common.gridPos(h=8, w=4, x=12, y=1)
  )
  .addPanel(
    common.statPanel(
      title='Total Jobs',
      query='sum(jenkins_job_count{jenkins_team="$team"})',
      unit='short',
      decimals=0,
    ),
    gridPos=common.gridPos(h=8, w=4, x=16, y=1)
  )
  .addPanel(
    common.statPanel(
      title='Dynamic Agents',
      query='count(container_last_seen{container_label_com_docker_compose_service=~"jenkins-agent-.*", container_label_com_docker_compose_project=~".*$team.*"})',
      unit='short',
      decimals=0,
    ),
    gridPos=common.gridPos(h=8, w=4, x=20, y=1)
  ),

  // Row: Build Metrics (Last 5m)
  createRow('Build Metrics (Last 5 Minutes)')
  .addPanel(
    common.statPanel(
      title='Builds Started',
      query='sum(increase(jenkins_builds_started_total{jenkins_team="$team"}[5m]))',
      unit='short',
      decimals=0,
    ),
    gridPos=common.gridPos(h=8, w=3, x=0, y=10)
  )
  .addPanel(
    common.statPanel(
      title='Builds Success',
      query='sum(increase(jenkins_builds_success_total{jenkins_team="$team"}[5m]))',
      unit='short',
      decimals=0,
    ),
    gridPos=common.gridPos(h=8, w=3, x=3, y=10)
  )
  .addPanel(
    common.statPanel(
      title='Builds Failed',
      query='sum(increase(jenkins_builds_failure_total{jenkins_team="$team"}[5m]))',
      unit='short',
      decimals=0,
    ),
    gridPos=common.gridPos(h=8, w=3, x=6, y=10)
  )
  .addPanel(
    common.statPanel(
      title='Build Success Rate',
      query='(sum(increase(jenkins_builds_success_total{jenkins_team="$team"}[5m])) / sum(increase(jenkins_builds_started_total{jenkins_team="$team"}[5m])) * 100) or 0',
      unit='percent',
      decimals=1,
    ),
    gridPos=common.gridPos(h=8, w=3, x=9, y=10)
  )
  .addPanel(
    common.gaugePanel(
      title='Avg Build Duration',
      query='sum(rate(jenkins_builds_duration_seconds_bucket{jenkins_team="$team"}[5m])) / sum(rate(jenkins_builds_duration_seconds_count{jenkins_team="$team"}[5m]))',
      unit='s',
      min=0,
      max=3600,
    ),
    gridPos=common.gridPos(h=8, w=3, x=12, y=10)
  )
  .addPanel(
    common.timeSeriesPanel(
      title='Build Trends',
      query='sum(increase(jenkins_builds_started_total{jenkins_team="$team"}[1m]))',
      legendDisplayMode='list',
      unit='short',
      decimals=0,
    ),
    gridPos=common.gridPos(h=8, w=6, x=15, y=10)
  ),

  // Row: Job Status Distribution
  createRow('Job Status Distribution')
  .addPanel(
    common.statPanel(
      title='Enabled Jobs',
      query='sum(jenkins_job_count_value{jenkins_team="$team", status="enabled"})',
      unit='short',
      decimals=0,
    ),
    gridPos=common.gridPos(h=8, w=4, x=0, y=19)
  )
  .addPanel(
    common.statPanel(
      title='Disabled Jobs',
      query='sum(jenkins_job_count_value{jenkins_team="$team", status="disabled"})',
      unit='short',
      decimals=0,
    ),
    gridPos=common.gridPos(h=8, w=4, x=4, y=19)
  )
  .addPanel(
    common.statPanel(
      title='Last Build Successful',
      query='sum(jenkins_job_last_success_seconds{jenkins_team="$team"} > 0)',
      unit='short',
      decimals=0,
    ),
    gridPos=common.gridPos(h=8, w=4, x=8, y=19)
  )
  .addPanel(
    common.statPanel(
      title='Last Build Failed',
      query='sum(jenkins_job_last_failure_seconds{jenkins_team="$team"} > 0)',
      unit='short',
      decimals=0,
    ),
    gridPos=common.gridPos(h=8, w=4, x=12, y=19)
  )
  .addPanel(
    common.timeSeriesPanel(
      title='Job Status Trends',
      query='sum by (status) (jenkins_job_count_value{jenkins_team="$team"})',
      legendDisplayMode='list',
      unit='short',
      decimals=0,
    ),
    gridPos=common.gridPos(h=8, w=8, x=16, y=19)
  ),

  // Row: Build Duration Analysis
  createRow('Build Duration Analysis')
  .addPanel(
    common.timeSeriesPanel(
      title='P50 Build Duration',
      query='histogram_quantile(0.50, sum(rate(jenkins_builds_duration_seconds_bucket{jenkins_team="$team"}[5m])) by (le))',
      legendDisplayMode='list',
      unit='s',
      decimals=2,
    ),
    gridPos=common.gridPos(h=8, w=6, x=0, y=28)
  )
  .addPanel(
    common.timeSeriesPanel(
      title='P95 Build Duration',
      query='histogram_quantile(0.95, sum(rate(jenkins_builds_duration_seconds_bucket{jenkins_team="$team"}[5m])) by (le))',
      legendDisplayMode='list',
      unit='s',
      decimals=2,
    ),
    gridPos=common.gridPos(h=8, w=6, x=6, y=28)
  )
  .addPanel(
    common.timeSeriesPanel(
      title='P99 Build Duration',
      query='histogram_quantile(0.99, sum(rate(jenkins_builds_duration_seconds_bucket{jenkins_team="$team"}[5m])) by (le))',
      legendDisplayMode='list',
      unit='s',
      decimals=2,
    ),
    gridPos=common.gridPos(h=8, w=6, x=12, y=28)
  )
  .addPanel(
    common.timeSeriesPanel(
      title='Max Build Duration',
      query='max(jenkins_builds_duration_seconds{jenkins_team="$team"})',
      legendDisplayMode='list',
      unit='s',
      decimals=1,
    ),
    gridPos=common.gridPos(h=8, w=6, x=18, y=28)
  ),

  // Row: Executor and Queue Analysis
  createRow('Executor and Queue Analysis')
  .addPanel(
    common.timeSeriesPanel(
      title='Executor Utilization',
      query='sum(jenkins_executor_in_use_count_value{jenkins_team="$team"}) / sum(jenkins_executor_count_value{jenkins_team="$team"}) * 100',
      legendDisplayMode='list',
      unit='percent',
      decimals=1,
    ),
    gridPos=common.gridPos(h=8, w=12, x=0, y=37)
  )
  .addPanel(
    common.timeSeriesPanel(
      title='Queue Length Trend',
      query='sum(jenkins_queue_size{jenkins_team="$team"})',
      legendDisplayMode='list',
      unit='short',
      decimals=0,
    ),
    gridPos=common.gridPos(h=8, w=12, x=12, y=37)
  ),

  // Row: DORA Metrics (Deployment Frequency)
  createRow('DORA Metrics')
  .addPanel(
    common.timeSeriesPanel(
      title='Deployment Frequency (Builds/Day)',
      query='sum(increase(jenkins_builds_started_total{jenkins_team="$team"}[24h]))',
      legendDisplayMode='list',
      unit='short',
      decimals=0,
    ),
    gridPos=common.gridPos(h=8, w=6, x=0, y=46)
  )
  .addPanel(
    common.timeSeriesPanel(
      title='Change Failure Rate (%)',
      query='(sum(increase(jenkins_builds_failure_total{jenkins_team="$team"}[24h])) / sum(increase(jenkins_builds_started_total{jenkins_team="$team"}[24h])) * 100) or 0',
      legendDisplayMode='list',
      unit='percent',
      decimals=1,
    ),
    gridPos=common.gridPos(h=8, w=6, x=6, y=46)
  )
  .addPanel(
    common.gaugePanel(
      title='Mean Build Time',
      query='sum(rate(jenkins_builds_duration_seconds_sum{jenkins_team="$team"}[24h])) / sum(rate(jenkins_builds_duration_seconds_count{jenkins_team="$team"}[24h]))',
      unit='s',
      min=0,
      max=7200,
    ),
    gridPos=common.gridPos(h=8, w=6, x=12, y=46)
  )
  .addPanel(
    common.gaugePanel(
      title='Build Success Rate (24h)',
      query='(sum(increase(jenkins_builds_success_total{jenkins_team="$team"}[24h])) / sum(increase(jenkins_builds_started_total{jenkins_team="$team"}[24h])) * 100) or 0',
      unit='percent',
      min=0,
      max=100,
    ),
    gridPos=common.gridPos(h=8, w=6, x=18, y=46)
  ),

  // Row: Error Tracking
  createRow('Error and Performance Tracking')
  .addPanel(
    common.timeSeriesPanel(
      title='HTTP Request Errors (5m)',
      query='sum(increase(jenkins_http_requests_errors_total{jenkins_team="$team"}[5m]))',
      legendDisplayMode='list',
      unit='short',
      decimals=0,
    ),
    gridPos=common.gridPos(h=8, w=6, x=0, y=55)
  )
  .addPanel(
    common.timeSeriesPanel(
      title='Plugin Errors (5m)',
      query='sum(increase(jenkins_plugins_error_total{jenkins_team="$team"}[5m]))',
      legendDisplayMode='list',
      unit='short',
      decimals=0,
    ),
    gridPos=common.gridPos(h=8, w=6, x=6, y=55)
  )
  .addPanel(
    common.timeSeriesPanel(
      title='Node Offline Events',
      query='sum(increase(jenkins_node_offline_total{jenkins_team="$team"}[1h]))',
      legendDisplayMode='list',
      unit='short',
      decimals=0,
    ),
    gridPos=common.gridPos(h=8, w=6, x=12, y=55)
  )
  .addPanel(
    common.timeSeriesPanel(
      title='Average Response Time (ms)',
      query='sum(rate(jenkins_http_requests_duration_seconds_sum{jenkins_team="$team"}[5m])) / sum(rate(jenkins_http_requests_duration_seconds_count{jenkins_team="$team"}[5m])) * 1000',
      legendDisplayMode='list',
      unit='ms',
      decimals=1,
    ),
    gridPos=common.gridPos(h=8, w=6, x=18, y=55)
  ),
])
