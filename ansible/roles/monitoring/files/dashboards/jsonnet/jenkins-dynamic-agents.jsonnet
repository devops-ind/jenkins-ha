// Jenkins Dynamic Agents Dashboard
// Modern Grafonnet implementation for Jenkins dynamic agent monitoring

local g = import 'grafonnet/gen/g.libsonnet';
local common = import './lib/common.libsonnet';
local dashboard = g.dashboard;
local row = g.row;
local stat = g.stat;
local piechart = g.pieChart;
local timeseries = g.timeSeries;
local logs = g.logs;
local table = g.table;
local bargauge = g.barGauge;
local heatmap = g.heatmap;


// Dashboard configuration
local dashboardTitle = 'Jenkins Dynamic Agents';
local dashboardUid = 'jenkins-dynamic-agents-modern';
local dashboardDescription = 'Dynamic agent monitoring and resource usage';

// Create the main dashboard
common.defaultDashboard(
  title=dashboardTitle,
  description=dashboardDescription,
  uid=dashboardUid,
  tags=['jenkins', 'agents', 'dynamic', 'containers']
)
.addPanels([
  // Row: Agent Overview
  row.new(title='Agent Overview')
  .addPanel(
    stat.new(
      title='Agent Status Overview',
      datasource='Prometheus',
      targets=[
        g.target.prometheus.new(
          expr='count(container_last_seen{container_label_com_jenkins_agent="true", container_label_team=~"$team", container_label_agent_type=~"$agent_type"} > (time() - 300))',
          refId='A',
          legendFormat='Active Agents'
        )
      ],
      reduceOptions={
        calcs: [
          "lastNotNull"
        ]
      },
      fieldConfig={
        defaults: {
          color: {
            mode: 'thresholds'
          },
          thresholds: {
            steps: [
              {
                color: 'red',
                value: 0
              },
              {
                color: 'yellow',
                value: 1
              },
              {
                color: 'green',
                value: 5
              }
            ]
          },
          unit: 'short'
        }
      },
      options={
        colorMode: 'background',
        graphMode: 'area',
        orientation: 'horizontal'
      }
    ),
    gridPos={
      h: 4,
      w: 6,
      x: 0,
      y: 1
    }
  )
  .addPanel(
    piechart.new(
      title='Agents by Team',
      datasource='Prometheus',
      targets=[
        g.target.prometheus.new(
          expr='count by (container_label_team) (container_last_seen{container_label_com_jenkins_agent="true", jenkins_team=~"$team"} > (time() - 300))',
          refId='A',
          legendFormat='{{container_label_team}}'
        )
      ],
      reduceOptions={
        calcs: [
          "lastNotNull"
        ]
      },
      options={
        pieType: 'pie',
        tooltip: {
          mode: 'single'
        },
        legend: {
          displayMode: 'list',
          placement: 'right'
        }
      }
    ),
    gridPos={
      h: 4,
      w: 6,
      x: 6,
      y: 1
    }
  )
  .addPanel(
    piechart.new(
      title='Agents by Type',
      datasource='Prometheus',
      targets=[
        g.target.prometheus.new(
          expr='count by (container_label_agent_type) (container_last_seen{container_label_com_jenkins_agent="true", jenkins_team=~"$team", agent_type=~"$agent_type"} > (time() - 300))',
          refId='A',
          legendFormat='{{container_label_agent_type}}'
        )
      ],
      reduceOptions={
        calcs: [
          "lastNotNull"
        ]
      },
      options={
        pieType: 'donut',
        tooltip: {
          mode: 'single'
        },
        legend: {
          displayMode: 'list',
          placement: 'right'
        }
      }
    ),
    gridPos={
      h: 4,
      w: 6,
      x: 12,
      y: 1
    }
  )
  .addPanel(
    stat.new(
      title='Agent Queue Depth',
      datasource='Prometheus',
      targets=[
        g.target.prometheus.new(
          expr='sum(jenkins_queue_size_value{jenkins_team=~"$team"})',
          refId='A',
          legendFormat='Queue Depth'
        )
      ],
      reduceOptions={
        calcs: [
          "lastNotNull"
        ]
      },
      fieldConfig={
        defaults: {
          color: {
            mode: 'thresholds'
          },
          thresholds: {
            steps: [
              {
                color: 'green',
                value: 0
              },
              {
                color: 'yellow',
                value: 5
              },
              {
                color: 'red',
                value: 10
              }
            ]
          },
          unit: 'short'
        }
      },
      options={
        colorMode: 'background',
        graphMode: 'area',
        orientation: 'horizontal'
      }
    ),
    gridPos={
      h: 4,
      w: 6,
      x: 18,
      y: 1
    }
  ),
  // Row: Agent Performance
  row.new(title='Agent Performance')
  .addPanel(
    timeseries.new(
      title='Agent Provisioning Rate',
      datasource='Prometheus',
      targets=[
        g.target.prometheus.new(
          expr='rate(jenkins_agent_launches_total{jenkins_team=~"$team", agent_type=~"$agent_type"}[5m]) * 60',
          refId='A',
          legendFormat='{{container_label_team}}-{{container_label_agent_type}}'
        )
      ],
      fieldConfig={
        defaults: {
          color: {
            mode: 'palette-classic'
          },
          custom: {
            axisPlacement: 'auto',
            barAlignment: 0,
            drawStyle: 'line',
            fillOpacity: 20,
            gradientMode: 'none',
            hideFrom: {
              legend: false,
              tooltip: false,
              vis: false
            },
            lineInterpolation: 'linear',
            lineWidth: 2,
            pointSize: 5,
            scaleDistribution: {
              type: 'linear'
            },
            showPoints: 'never',
            spanNulls: false,
            stacking: {
              group: 'A',
              mode: 'none'
            },
            thresholdsStyle: {
              mode: 'off'
            }
          },
          unit: 'agents/min'
        }
      },
      options={
        legend: {
          displayMode: 'list',
          placement: 'bottom'
        },
        tooltip: {
          mode: 'multi'
        }
      }
    ),
    gridPos={
      h: 6,
      w: 12,
      x: 0,
      y: 6
    }
  )
  .addPanel(
    timeseries.new(
      title='Agent Build Queue Trends',
      datasource='Prometheus',
      targets=[
        g.target.prometheus.new(
          expr='jenkins_queue_size_value{jenkins_team=~"$team"}',
          refId='A',
          legendFormat='{{container_label_team}} Queue'
        )
      ],
      fieldConfig={
        defaults: {
          color: {
            mode: 'palette-classic'
          },
          custom: {
            axisPlacement: 'auto',
            barAlignment: 0,
            drawStyle: 'line',
            fillOpacity: 30,
            gradientMode: 'hue',
            hideFrom: {
              legend: false,
              tooltip: false,
              vis: false
            },
            lineInterpolation: 'smooth',
            lineWidth: 2,
            pointSize: 5,
            scaleDistribution: {
              type: 'linear'
            },
            showPoints: 'auto',
            spanNulls: false,
            stacking: {
              group: 'A',
              mode: 'none'
            },
            thresholdsStyle: {
              mode: 'off'
            }
          },
          unit: 'jobs'
        }
      },
      options={
        legend: {
          displayMode: 'list',
          placement: 'bottom'
        },
        tooltip: {
          mode: 'multi'
        }
      }
    ),
    gridPos={
      h: 6,
      w: 12,
      x: 12,
      y: 6
    }
  ),
  // Row: Agent Resource Usage
  row.new(title='Agent Resource Usage')
  .addPanel(
    timeseries.new(
      title='Agent CPU Utilization',
      datasource='Prometheus',
      targets=[
        g.target.prometheus.new(
          expr='rate(container_cpu_usage_seconds_total{container_label_com_jenkins_agent="true", jenkins_team=~"$team", agent_type=~"$agent_type"}[5m]) * 100',
          refId='A',
          legendFormat='{{container_label_team}}-{{container_label_agent_type}}-{{name}}'
        )
      ],
      fieldConfig={
        defaults: {
          color: {
            mode: 'palette-classic'
          },
          custom: {
            axisPlacement: 'auto',
            barAlignment: 0,
            drawStyle: 'line',
            fillOpacity: 20,
            gradientMode: 'none',
            hideFrom: {
              legend: false,
              tooltip: false,
              vis: false
            },
            lineInterpolation: 'linear',
            lineWidth: 1,
            pointSize: 5,
            scaleDistribution: {
              type: 'linear'
            },
            showPoints: 'never',
            spanNulls: false,
            stacking: {
              group: 'A',
              mode: 'none'
            },
            thresholdsStyle: {
              mode: 'off'
            }
          },
          max: 100,
          min: 0,
          unit: 'percent'
        }
      },
      options={
        legend: {
          displayMode: 'table',
          placement: 'right'
        },
        tooltip: {
          mode: 'multi'
        }
      }
    ),
    gridPos={
      h: 6,
      w: 12,
      x: 0,
      y: 13
    }
  )
  .addPanel(
    timeseries.new(
      title='Agent Memory Utilization',
      datasource='Prometheus',
      targets=[
        g.target.prometheus.new(
          expr='container_memory_usage_bytes{container_label_com_jenkins_agent="true", jenkins_team=~"$team", agent_type=~"$agent_type"} / 1024^3',
          refId='A',
          legendFormat='{{container_label_team}}-{{container_label_agent_type}}-{{name}}'
        )
      ],
      fieldConfig={
        defaults: {
          color: {
            mode: 'palette-classic'
          },
          custom: {
            axisPlacement: 'auto',
            barAlignment: 0,
            drawStyle: 'line',
            fillOpacity: 20,
            gradientMode: 'none',
            hideFrom: {
              legend: false,
              tooltip: false,
              vis: false
            },
            lineInterpolation: 'linear',
            lineWidth: 1,
            pointSize: 5,
            scaleDistribution: {
              type: 'linear'
            },
            showPoints: 'never',
            spanNulls: false,
            stacking: {
              group: 'A',
              mode: 'none'
            },
            thresholdsStyle: {
              mode: 'off'
            }
          },
          min: 0,
          unit: 'gbytes'
        }
      },
      options={
        legend: {
          displayMode: 'table',
          placement: 'right'
        },
        tooltip: {
          mode: 'multi'
        }
      }
    ),
    gridPos={
      h: 6,
      w: 12,
      x: 12,
      y: 13
    }
  )
])
