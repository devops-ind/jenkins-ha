// Jenkins Builds Dashboard
// Modern Grafonnet implementation for Jenkins build monitoring

local g = import 'grafonnet/gen/g.libsonnet';
local common = import './lib/common.libsonnet';
local dashboard = g.dashboard;
local row = g.row;
local logs = g.logs;
local table = g.table;

// Dashboard configuration
local dashboardTitle = 'Jenkins Builds';
local dashboardUid = 'jenkins-builds-modern';
local dashboardDescription = 'Build performance and trends';

// Row helper function
local createRow(title) = row.new(title=title, collapsed=false);

// Create the main dashboard
common.defaultDashboard(
  title=dashboardTitle,
  description=dashboardDescription,
  uid=dashboardUid,
  team='',
  environment='blue',
  tags=['jenkins', 'builds']
)
.addPanels([
  // Row: Build Rates
  createRow('Build Rates')
  .addPanel(
    common.timeSeriesPanel(
      title='Build Rate',
      query='rate(jenkins_builds_total{jenkins_team=~"$team", jenkins_environment=~"$environment"}[5m])',
      legendDisplayMode='list',
      unit='ops',
      decimals=2,
    ),
    gridPos=common.gridPos(h=8, w=12, x=0, y=1)
  )
  .addPanel(
    common.timeSeriesPanel(
      title='Build Success vs Failure Rate',
      query='rate(jenkins_builds_success_build_count{jenkins_team=~"$team", jenkins_environment=~"$environment"}[5m])',
      legendDisplayMode='list',
      unit='ops',
      decimals=2,
    ),
    gridPos=common.gridPos(h=8, w=12, x=12, y=1)
  ),

  // Row: Build Duration
  createRow('Build Duration')
  .addPanel(
    common.timeSeriesPanel(
      title='Build Duration Trends',
      query='jenkins_builds_last_build_duration_milliseconds{jenkins_team=~"$team", jenkins_environment=~"$environment"}/ 1000',
      legendDisplayMode='list',
      unit='s',
      decimals=1,
    ),
    gridPos=common.gridPos(h=8, w=24, x=0, y=9)
  ),

  // Row: Build Logs
  createRow('Build Logs')
  .addPanel(
    logs.new(
      title='Build Logs - Success Events',
      datasource='Loki',
      targets=[
        g.target.loki.new(
          expr='{job="jenkins", team=~"$team"} |~ "(success|successful|completed|finished)"',
          refId='A',
        )
      ],
      showTime=true,
      showLabels=true,
      wrapLines=true,
      sortOrder='Descending',
    ),
    gridPos=common.gridPos(h=8, w=12, x=0, y=17)
  )
  .addPanel(
    logs.new(
      title='Build Logs - Failure Events',
      datasource='Loki',
      targets=[
        g.target.loki.new(
          expr='{job="jenkins", team=~"$team"} |~ "(error|exception|failed|failure|abort)"',
          refId='A',
        )
      ],
      showTime=true,
      showLabels=true,
      wrapLines=true,
      sortOrder='Descending',
    ),
    gridPos=common.gridPos(h=8, w=12, x=12, y=17)
  ),

  // Row: Build Log Volume vs Failure Rate Correlation
  createRow('Build Log Volume vs Failure Rate Correlation')
  .addPanel(
    common.timeSeriesPanel(
      title='Build Log Volume vs Failure Rate Correlation',
      query='rate(jenkins_builds_failure_build_count{jenkins_team=~"$team", jenkins_environment=~"$environment"}[5m])',
      legendDisplayMode='list',
      unit='ops',
      decimals=2,
    ),
    gridPos=common.gridPos(h=8, w=24, x=0, y=25)
  ),

  // Row: Job-Specific Build Analysis
  createRow('Job-Specific Build Analysis')
  .addPanel(
    table.new(
      title='Job-Specific Build Analysis',
      datasource='Prometheus',
      targets=[
        g.target.prometheus.new(
          expr='jenkins_builds_last_build_result{jenkins_team=~"$team", jenkins_environment=~"$environment"}',
          refId='A',
          format='table',
          instant=true,
        ),
        g.target.prometheus.new(
          expr='jenkins_builds_last_build_duration_milliseconds{jenkins_team=~"$team", jenkins_environment=~"$environment"} / 1000',
          refId='B',
          format='table',
          instant=true,
        )
      ],
      transformations=[
        {
          id: 'merge',
          options: {}
        },
        {
          id: 'organize',
          options: {
            excludeByName: {
              Time: true,
              __name__: true,
              instance: true
            },
            indexByName: {
              job: 0,
              jenkins_team: 1,
              jenkins_environment: 2,
              'Value #A': 3,
              'Value #B': 4
            },
            renameByName: {
              job: 'Job Name',
              jenkins_team: 'Team',
              jenkins_environment: 'Environment',
              'Value #A': 'Last Build Result',
              'Value #B': 'Last Build Duration (s)'
            }
          }
        }
      ]
    ),
    gridPos=common.gridPos(h=8, w=24, x=0, y=33)
  )
])
