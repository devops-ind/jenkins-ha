// Security Metrics Dashboard
// Modern Grafonnet implementation for security monitoring

local g = import 'grafonnet/gen/g.libsonnet';
local common = import './lib/common.libsonnet';
local dashboard = g.dashboard;
local row = g.row;

// Dashboard configuration
local dashboardTitle = 'Security Metrics';
local dashboardUid = 'security-metrics-modern';
local dashboardDescription = 'Security events and compliance monitoring';

// Row helper function
local createRow(title) = row.new(title=title, collapsed=false);

// Create the main dashboard
common.defaultDashboard(
  title=dashboardTitle,
  description=dashboardDescription,
  uid=dashboardUid,
  tags=['security', 'compliance']
)
.addPanels([
  // Row: Security Metrics
  createRow('Security Metrics')
  .addPanel(
    common.statPanel(
      title='Security Events',
      query='jenkins_security_events_total',
      unit='short',
      decimals=0,
    ),
    gridPos=common.gridPos(h=4, w=6, x=0, y=1)
  )
  .addPanel(
    common.timeSeriesPanel(
      title='Failed Login Attempts',
      query='rate(jenkins_login_failures_total[5m])',
      legendDisplayMode='list',
      unit='short',
      decimals=2,
    ),
    gridPos=common.gridPos(h=8, w=12, x=0, y=5)
  )
])
