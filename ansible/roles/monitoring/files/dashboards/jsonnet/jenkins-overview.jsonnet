// Jenkins Overview Dashboard
// Modern Grafonnet implementation for comprehensive Jenkins monitoring
// Covers: Build metrics, Job status, Agents, Queue, DORA metrics, and Loki Logs

local g = import 'grafonnet/gen/g.libsonnet';
local common = import './lib/common.libsonnet';
local dashboard = g.dashboard;
local row = g.row;
local logs = g.logs;

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
      title='Jenkins Status',
      query='up{job=~"jenkins.*", jenkins_team=~"$team", jenkins_environment=~"$environment"}',
      unit='short',
      decimals=0,
    ),
    gridPos=common.gridPos(h=4, w=6, x=0, y=1)
  )
  .addPanel(
    common.statPanel(
      title='Build Queue Length',
      query='jenkins_queue_size_value{jenkins_team=~"$team", jenkins_environment=~"$environment"}',
      unit='short',
      decimals=0,
    ),
    gridPos=common.gridPos(h=4, w=6, x=6, y=1)
  )
  .addPanel(
    common.statPanel(
      title='Active Builds',
      query='jenkins_builds_running_builds{jenkins_team=~"$team", jenkins_environment=~"$environment"}',
      unit='short',
      decimals=0,
    ),
    gridPos=common.gridPos(h=4, w=6, x=12, y=1)
  )
  .addPanel(
    common.statPanel(
      title='Error Rate (Last 5min)',
      query='rate(jenkins_builds_failure_build_count{jenkins_team=~"$team", jenkins_environment=~"$environment"}[5m])',
      unit='short',
      decimals=2,
    ),
    gridPos=common.gridPos(h=4, w=6, x=18, y=1)
  ),

  // Row: Logs
  createRow('Logs')
  .addPanel(
    logs.new(
      title='Jenkins Build Logs - Recent Activity',
      datasource='Loki',
      targets=[
        g.target.loki.new(
          expr='{job="jenkins", team=~"$team"} |= "BUILD"',
          refId='A',
        )
      ],
      showTime=true,
      showLabels=true,
      wrapLines=true,
      sortOrder='Descending',
    ),
    gridPos=common.gridPos(h=8, w=12, x=0, y=5)
  )
  .addPanel(
    logs.new(
      title='Error Logs - Critical Issues',
      datasource='Loki',
      targets=[
        g.target.loki.new(
          expr='{job="jenkins", team=~"$team"} |~ "(error|exception|failed|failure)"',
          refId='A',
        )
      ],
      showTime=true,
      showLabels=true,
      wrapLines=true,
      sortOrder='Descending',
    ),
    gridPos=common.gridPos(h=8, w=12, x=12, y=5)
  ),

  // Row: Build Metrics
  createRow('Build Metrics')
  .addPanel(
    common.timeSeriesPanel(
      title='Build Success vs Failure Rate (5min)',
      query='rate(jenkins_builds_success_build_count{jenkins_team=~"$team", jenkins_environment=~"$environment"}[5m])',
      legendDisplayMode='list',
      unit='ops',
      decimals=2,
    ),
    gridPos=common.gridPos(h=8, w=12, x=0, y=13)
  )
  .addPanel(
    common.statPanel(
      title='Log Volume by Level',
      query='count_over_time({job="jenkins", team=~"$team"} |~ "error" [5m])',
      unit='short',
      decimals=0,
    ),
    gridPos=common.gridPos(h=8, w=12, x=12, y=13)
  ),

  // Row: Security
  createRow('Security')
  .addPanel(
    logs.new(
      title='Security Events and Authentication Logs',
      datasource='Loki',
      targets=[
        g.target.loki.new(
          expr='{job="auth"} |~ "failed|successful|login|logout|authentication"',
          refId='A',
        ),
        g.target.loki.new(
          expr='{job="jenkins", team=~"$team"} |~ "login|logout|authentication|security|unauthorized"',
          refId='B',
        )
      ],
      showTime=true,
      showLabels=true,
      wrapLines=true,
      sortOrder='Descending',
    ),
    gridPos=common.gridPos(h=8, w=24, x=0, y=21)
  ),

  // Row: HAProxy
  createRow('HAProxy')
  .addPanel(
    logs.new(
      title='HAProxy Load Balancer Logs',
      datasource='Loki',
      targets=[
        g.target.loki.new(
          expr='{job="haproxy", team=~"$team"}',
          refId='A',
        )
      ],
      showTime=true,
      showLabels=true,
      wrapLines=true,
      sortOrder='Descending',
    ),
    gridPos=common.gridPos(h=8, w=24, x=0, y=29)
  )
])