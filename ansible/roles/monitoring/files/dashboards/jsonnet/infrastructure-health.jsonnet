// Infrastructure Health Dashboard
// Modern Grafonnet implementation for comprehensive system health monitoring
// Covers: Nodes, Containers, Storage, Network, Errors

local g = import 'grafonnet/gen/g.libsonnet';
local common = import './lib/common.libsonnet';
local dashboard = g.dashboard;
local row = g.row;

// Dashboard configuration
local dashboardTitle = 'Infrastructure Health';
local dashboardUid = 'infrastructure-health-modern';
local dashboardDescription = 'System health monitoring dashboard using modern Grafonnet architecture';

// Row helper function
local createRow(title) = row.new(title=title, collapsed=false);

// Create the main dashboard
common.defaultDashboard(
  title=dashboardTitle,
  description=dashboardDescription,
  uid=dashboardUid,
  team='',
  environment='blue',
  tags=['infrastructure', 'system', 'health', 'monitoring']
)
.addPanels([
  // Row: System Overview
  createRow('System Overview')
  .addPanel(
    common.statPanel(
      title='Nodes Up',
      query='count(node_up)',
      unit='short',
      decimals=0,
    ),
    gridPos=common.gridPos(h=8, w=4, x=0, y=1)
  )
  .addPanel(
    common.statPanel(
      title='CPU Usage Average',
      query='avg(100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100))',
      unit='percent',
      decimals=1,
    ),
    gridPos=common.gridPos(h=8, w=4, x=4, y=1)
  )
  .addPanel(
    common.statPanel(
      title='Memory Usage Average',
      query='avg((1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100)',
      unit='percent',
      decimals=1,
    ),
    gridPos=common.gridPos(h=8, w=4, x=8, y=1)
  )
  .addPanel(
    common.statPanel(
      title='Disk Usage Average',
      query='avg((1 - (node_filesystem_avail_bytes{fstype!~"tmpfs|fuse.locationfs|squashfs|vfat"} / node_filesystem_size_bytes)) * 100)',
      unit='percent',
      decimals=1,
    ),
    gridPos=common.gridPos(h=8, w=4, x=12, y=1)
  )
  .addPanel(
    common.statPanel(
      title='Network Errors (5m)',
      query='sum(increase(node_network_transmit_errs_total[5m])) + sum(increase(node_network_receive_errs_total[5m]))',
      unit='short',
      decimals=0,
    ),
    gridPos=common.gridPos(h=8, w=4, x=16, y=1)
  )
  .addPanel(
    common.statPanel(
      title='Alerts Firing',
      query='count(ALERTS)',
      unit='short',
      decimals=0,
    ),
    gridPos=common.gridPos(h=8, w=4, x=20, y=1)
  ),

  // Row: CPU and Memory Trends
  createRow('CPU and Memory Trends')
  .addPanel(
    common.timeSeriesPanel(
      title='CPU Usage per Node',
      query='avg by (instance) (100 - (rate(node_cpu_seconds_total{mode="idle"}[5m]) * 100))',
      legendDisplayMode='list',
      unit='percent',
      decimals=1,
    ),
    gridPos=common.gridPos(h=8, w=12, x=0, y=10)
  )
  .addPanel(
    common.timeSeriesPanel(
      title='Memory Usage per Node',
      query='(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100',
      legendDisplayMode='list',
      unit='percent',
      decimals=1,
    ),
    gridPos=common.gridPos(h=8, w=12, x=12, y=10)
  ),

  // Row: Container Metrics
  createRow('Container Metrics')
  .addPanel(
    common.statPanel(
      title='Running Containers',
      query='count(container_last_seen)',
      unit='short',
      decimals=0,
    ),
    gridPos=common.gridPos(h=8, w=4, x=0, y=19)
  )
  .addPanel(
    common.statPanel(
      title='Container CPU Usage',
      query='sum(rate(container_cpu_usage_seconds_total{container_label_com_docker_compose_service=~"jenkins-.*"}[5m])) * 100',
      unit='percent',
      decimals=1,
    ),
    gridPos=common.gridPos(h=8, w=4, x=4, y=19)
  )
  .addPanel(
    common.statPanel(
      title='Container Memory (GB)',
      query='sum(container_memory_usage_bytes{container_label_com_docker_compose_service=~"jenkins-.*"}) / 1024 / 1024 / 1024',
      unit='gbytes',
      decimals=2,
    ),
    gridPos=common.gridPos(h=8, w=4, x=8, y=19)
  )
  .addPanel(
    common.timeSeriesPanel(
      title='Container CPU per Team',
      query='sum by (container_label_com_docker_compose_service) (rate(container_cpu_usage_seconds_total{container_label_com_docker_compose_service=~"jenkins-.*"}[5m]) * 100)',
      legendDisplayMode='list',
      unit='percent',
      decimals=1,
    ),
    gridPos=common.gridPos(h=8, w=12, x=12, y=19)
  ),

  // Row: Disk and Network
  createRow('Disk and Network')
  .addPanel(
    common.timeSeriesPanel(
      title='Disk Usage per Mount',
      query='(1 - (node_filesystem_avail_bytes{fstype!~"tmpfs|fuse.locationfs|squashfs|vfat"} / node_filesystem_size_bytes)) * 100',
      legendDisplayMode='list',
      unit='percent',
      decimals=1,
    ),
    gridPos=common.gridPos(h=8, w=12, x=0, y=28)
  )
  .addPanel(
    common.timeSeriesPanel(
      title='Network I/O Bytes per Node',
      query='rate(node_network_transmit_bytes_total[5m]) + rate(node_network_receive_bytes_total[5m])',
      legendDisplayMode='list',
      unit='Bps',
      decimals=0,
    ),
    gridPos=common.gridPos(h=8, w=12, x=12, y=28)
  ),

  // Row: Service Health
  createRow('Service Health')
  .addPanel(
    common.gaugePanel(
      title='Prometheus Health',
      query='prometheus_up',
      unit='short',
      min=0,
      max=1,
    ),
    gridPos=common.gridPos(h=8, w=4, x=0, y=37)
  )
  .addPanel(
    common.gaugePanel(
      title='Loki Health',
      query='loki_up',
      unit='short',
      min=0,
      max=1,
    ),
    gridPos=common.gridPos(h=8, w=4, x=4, y=37)
  )
  .addPanel(
    common.statPanel(
      title='Prometheus Targets Up',
      query='count(up == 1) / count(up)',
      unit='percentunit',
      decimals=2,
    ),
    gridPos=common.gridPos(h=8, w=4, x=8, y=37)
  )
  .addPanel(
    common.timeSeriesPanel(
      title='Target Health Trends',
      query='count(up == 1) / count(up) * 100',
      legendDisplayMode='list',
      unit='percent',
      decimals=1,
    ),
    gridPos=common.gridPos(h=8, w=12, x=12, y=37)
  ),

  // Row: Error Tracking
  createRow('Error and Alert Tracking')
  .addPanel(
    common.statPanel(
      title='Critical Alerts',
      query='count(ALERTS{severity="critical"})',
      unit='short',
      decimals=0,
    ),
    gridPos=common.gridPos(h=8, w=3, x=0, y=46)
  )
  .addPanel(
    common.statPanel(
      title='Warning Alerts',
      query='count(ALERTS{severity="warning"})',
      unit='short',
      decimals=0,
    ),
    gridPos=common.gridPos(h=8, w=3, x=3, y=46)
  )
  .addPanel(
    common.statPanel(
      title='Node Network Errors (5m)',
      query='sum(increase(node_network_transmit_errs_total[5m])) + sum(increase(node_network_receive_errs_total[5m]))',
      unit='short',
      decimals=0,
    ),
    gridPos=common.gridPos(h=8, w=3, x=6, y=46)
  )
  .addPanel(
    common.statPanel(
      title='Node Network Dropped (5m)',
      query='sum(increase(node_network_transmit_drop_total[5m])) + sum(increase(node_network_receive_drop_total[5m]))',
      unit='short',
      decimals=0,
    ),
    gridPos=common.gridPos(h=8, w=3, x=9, y=46)
  )
  .addPanel(
    common.timeSeriesPanel(
      title='Active Alerts over Time',
      query='count(ALERTS) by (severity)',
      legendDisplayMode='list',
      unit='short',
      decimals=0,
    ),
    gridPos=common.gridPos(h=8, w=12, x=12, y=46)
  ),
])
