// Common Grafonnet Library for Jenkins Infrastructure Dashboards
// Provides reusable components and utilities for consistent dashboard creation

local g = import 'grafonnet/gen/g.libsonnet';
local dashboard = g.dashboard;
local row = g.row;
local stat = g.stat;
local timeSeries = g.timeSeries;
local gauge = g.gauge;
local text = g.text;
local variable = g.queryVariable;
local datasource = g.datasource;
local custom = g.panel.timeSeries.fieldConfig.custom;

{
  // Default dashboard configuration
  defaultDashboard(
    title,
    description,
    uid,
    team='',
    environment='blue',
    tags=[]
  )::
    dashboard.new(
      title=title,
      description=description,
      uid=uid,
      timezone='browser',
      tags=if std.length(team) > 0 then tags + [team, environment] else tags,
      refresh='30s',
      time=g.time.range(from='now-6h', to='now'),
      panels=[],
    )
    .addTemplates([
      // Team variable (if applicable)
      if std.length(team) > 0 then
        variable.new(
          name='team',
          label='Team',
          datasource=g.string('prometheus'),
          query='label_values(container_last_seen{container_label_com_docker_compose_service=~"jenkins-%(team)s-.*"}, container_label_com_docker_compose_service)' % {team: team},
          current=team,
          multi=false,
        )
      else
        variable.new(
          name='team',
          label='Team',
          datasource=g.string('prometheus'),
          query='label_values(jenkins_up, jenkins_team)',
          current='all',
          multi=false,
        ),

      // Environment variable
      variable.new(
        name='environment',
        label='Environment',
        datasource=g.string('prometheus'),
        query='label_values(jenkins_up{jenkins_team=~"$team"}, jenkins_environment)',
        current=environment,
        multi=false,
      ),

      // Time range variable
      variable.new(
        name='interval',
        label='Interval',
        datasource=g.string('prometheus'),
        query='5m,10m,30m,1h,6h,24h',
        current='30m',
        multi=false,
      ),
    ]),

  // Standard prometheus datasource
  prometheusDatasource()::
    datasource.prometheus.new(
      name='Prometheus',
      uid='${DS_PROMETHEUS}',
    ),

  // Standard time series panel
  timeSeriesPanel(
    title,
    query,
    legendDisplayMode='list',
    legendPlacement='bottom',
    unit='short',
    min=null,
    max=null,
    decimals=2,
  )::
    timeSeries.new(
      title=title,
      targets=[
        g.target.prometheus.new(
          expr=query,
          legendFormat='{{ label_name }}',
          refId='A',
        ),
      ],
      unit=unit,
      custom=g.panel.timeSeries.fieldConfig.custom.new(
        hideFrom={legend: false, tooltip: false, viz: false},
        lineInterpolation='linear',
        lineWidth=1,
        showPoints='auto',
        spanNulls=true,
      ),
      decimals=decimals,
      min=min,
      max=max,
    )
    .setOption('legend', {
      calcs=['mean', 'max'],
      displayMode=legendDisplayMode,
      placement=legendPlacement,
    }),

  // Standard gauge panel
  gaugePanel(
    title,
    query,
    unit='short',
    min=0,
    max=100,
    thresholdMode='absolute',
    thresholds=null,
  )::
    gauge.new(
      title=title,
      targets=[
        g.target.prometheus.new(
          expr=query,
          refId='A',
        ),
      ],
      unit=unit,
      min=min,
      max=max,
    )
    .setOption('showThresholdLabels', false)
    .setOption('showThresholdMarkers', true),

  // Standard stat panel
  statPanel(
    title,
    query,
    unit='short',
    thresholds=null,
    decimals=0,
  )::
    stat.new(
      title=title,
      targets=[
        g.target.prometheus.new(
          expr=query,
          refId='A',
        ),
      ],
      unit=unit,
      decimals=decimals,
    )
    .setOption('colorMode', 'value')
    .setOption('graphMode', 'area')
    .setOption('justifyMode', 'auto')
    .setOption('textMode', 'auto'),

  // Text/markdown panel
  textPanel(
    title,
    content,
  )::
    text.new(
      title=title,
      content=content,
    ),

  // Row divider
  row(title)::
    row.new(
      title=title,
      collapsed=false,
    ),

  // Common prometheus queries
  promQueries:: {
    // Jenkins metrics
    jenkinsUp: 'jenkins_up{jenkins_team="$team"}',
    jenkinsActiveBuilds: 'increase(jenkins_builds_started_total{jenkins_team="$team"}[5m])',
    jenkinsBuildSuccess: 'increase(jenkins_builds_success_total{jenkins_team="$team"}[5m])',
    jenkinsBuildFailure: 'increase(jenkins_builds_failure_total{jenkins_team="$team"}[5m])',
    jenkinsQueueLength: 'jenkins_queue_size{jenkins_team="$team"}',
    jenkinsJobCount: 'jenkins_job_count{jenkins_team="$team"}',

    // System metrics
    nodeUpCount: 'count(node_up)',
    nodeCpuUsage: 'avg(100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100))',
    nodeMemoryUsage: 'avg((1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100)',
    nodeDiskUsage: 'avg((node_filesystem_avail_bytes{fstype!~"tmpfs|fuse.locationfs|squashfs|vfat"} / node_filesystem_size_bytes) * 100)',

    // Container metrics
    containerCpuUsage: 'sum(rate(container_cpu_usage_seconds_total{container_label_com_docker_compose_service=~"jenkins-.*"}[5m])) * 100',
    containerMemoryUsage: 'sum(container_memory_usage_bytes{container_label_com_docker_compose_service=~"jenkins-.*"}) / 1024 / 1024 / 1024',

    // Prometheus metrics
    prometheusUp: 'prometheus_up',
    prometheusTargetHealth: 'count(up == 1) / count(up)',

    // Loki metrics
    lokiUp: 'loki_up',
    lokiIngestionRate: 'rate(loki_distributor_bytes_received_total[5m])',

    // Infrastructure health
    alertsFiring: 'count(ALERTS{severity="critical"})',
    alertsWarning: 'count(ALERTS{severity="warning"})',
  },

  // Dashboard layout helpers
  gridPos(h, w, x, y):: {
    h: h,
    w: w,
    x: x,
    y: y,
  },

  // Threshold configuration
  thresholds(values):: {
    mode: 'absolute',
    steps: values,
  },

  // Color mapping
  colorMap(colorMode='value'):: {
    mode: colorMode,
    options: {},
  },
}
