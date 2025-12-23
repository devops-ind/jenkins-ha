// Infrastructure Health Dashboard
// Modern Grafonnet implementation for infrastructure monitoring

local g = import 'grafonnet/gen/g.libsonnet';
local common = import './lib/common.libsonnet';
local dashboard = g.dashboard;
local row = g.row;

// Dashboard configuration
local dashboardTitle = 'Infrastructure Health';
local dashboardUid = 'infrastructure-health-modern';
local dashboardDescription = 'VM and container infrastructure metrics';

// Row helper function
local createRow(title) = row.new(title=title, collapsed=false);

// Create the main dashboard
common.defaultDashboard(
  title=dashboardTitle,
  description=dashboardDescription,
  uid=dashboardUid,
  tags=['infrastructure', 'health']
)
.addPanels([
  // Row: System Metrics
  createRow('System Metrics')
  .addPanel(
    common.timeSeriesPanel(
      title='CPU Usage',
      query='100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)',
      legendDisplayMode='list',
      unit='percent',
      decimals=1,
    ),
    gridPos=common.gridPos(h=8, w=12, x=0, y=1)
  )
  .addPanel(
    common.timeSeriesPanel(
      title='Memory Usage',
      query='(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100',
      legendDisplayMode='list',
      unit='percent',
      decimals=1,
    ),
    gridPos=common.gridPos(h=8, w=12, x=12, y=1)
  )
])