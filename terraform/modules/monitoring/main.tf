resource "google_monitoring_notification_channel" "email" {
  display_name = "Platform Team Email"
  type         = "email"
  labels = {
    email_address = var.alert_email
  }
}

# Alert: pod crash-looping 
resource "google_monitoring_alert_policy" "crash_loop" {
  display_name = "Flask App - CrashLoopBackOff"
  combiner      = "OR"

  conditions {
    display_name = "Container restart count high"
    condition_threshold {
      filter          = "resource.type=\"k8s_container\" AND resource.labels.namespace_name=\"flask-app\" AND metric.type=\"kubernetes.io/container/restart_count\""
      comparison      = "COMPARISON_GT"
      threshold_value = 3
      duration        = "300s"
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_DELTA"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
}

# Alert: SLO-style latency alert 
resource "google_monitoring_alert_policy" "high_latency" {
  display_name = "Flask App - P99 Latency Above SLO"
  combiner      = "OR"

  conditions {
    display_name = "P99 request latency > 1s for 5min"
    condition_threshold {
      filter          = "resource.type=\"k8s_container\" AND resource.labels.namespace_name=\"flask-app\" AND metric.type=\"custom.googleapis.com/http/request_latency\""
      comparison      = "COMPARISON_GT"
      threshold_value = 1000
      duration        = "300s"
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_PERCENTILE_99"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
}

# Alert: readiness probe failing across the deployment — early warning before a full outage
resource "google_monitoring_alert_policy" "readiness_failing" {
  display_name = "Flask App - Readiness Probe Failures"
  combiner      = "OR"

  conditions {
    display_name = "Pods failing readiness"
    condition_threshold {
      filter          = "resource.type=\"k8s_pod\" AND resource.labels.namespace_name=\"flask-app\" AND metric.type=\"kubernetes.io/pod/ready\""
      comparison      = "COMPARISON_LT"
      threshold_value = 1
      duration        = "180s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_FRACTION_TRUE"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
}

resource "google_monitoring_dashboard" "flask_app" {
  dashboard_json = jsonencode({
    displayName = "Flask App - Reference Dashboard"
    gridLayout = {
      widgets = [
        {
          title = "Request count"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"k8s_container\" AND resource.labels.namespace_name=\"flask-app\" AND metric.type=\"kubernetes.io/container/cpu/core_usage_time\""
                }
              }
            }]
          }
        },
        {
          title = "Pod restarts"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"k8s_container\" AND resource.labels.namespace_name=\"flask-app\" AND metric.type=\"kubernetes.io/container/restart_count\""
                }
              }
            }]
          }
        }
      ]
    }
  })
}
