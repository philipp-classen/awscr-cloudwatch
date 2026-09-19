require "../base_client"
require "./datum"
require "./dimension_filter"
require "./metric"
require "./metric_stat"
require "./metric_data_query"

module Awscr::CloudWatch
  # Publishes and queries metrics.
  #
  # ```
  # client = MetricClient.new("us-east-1", "key", "secret")
  # client.put_counter("MyApp", "Requests", dimensions: {"Env" => "prod"})
  # ```
  class MetricClient < BaseClient
    # Publishes up to 1000 `MetricDatum` (1 MB) in one request.
    def put_metric_data(namespace : String, metric_data : Array(MetricDatum)) : Nil
      request Params.new("PutMetricData")
        .add("Namespace", namespace)
        .add_structs("MetricData", metric_data)
    end

    # Publishes a single `Count` value.
    def put_counter(namespace : String, metric_name : String, value : Number = 1,
                    dimensions : Hash(String, String)? = nil, timestamp : Time? = nil) : Nil
      put_metric_data(namespace, [MetricDatum.counter(metric_name, value, dimensions, timestamp)])
    end

    # Lists metrics, 500 per page. New metrics show up after a few minutes.
    # With *recently_active*, only metrics with data in the last three hours are returned.
    def list_metrics(namespace : String? = nil, metric_name : String? = nil,
                     dimensions : Array(DimensionFilter)? = nil, recently_active : Bool = false,
                     next_token : String? = nil) : Response::ListMetricsOutput
      query Response::ListMetricsOutput, Params.new("ListMetrics")
        .add("Namespace", namespace)
        .add("MetricName", metric_name)
        .add_structs("Dimensions", dimensions)
        .add("RecentlyActive", recently_active ? "PT3H" : nil)
        .add("NextToken", next_token)
    end

    # Aggregates one metric over *period* seconds. *statistics* are
    # `SampleCount`, `Average`, `Sum`, `Minimum`, `Maximum`; *extended_statistics*
    # are percentiles like `p99`. Returns at most 1440 data points.
    def get_metric_statistics(namespace : String, metric_name : String, *,
                              start_time : Time, end_time : Time, period : Int32,
                              statistics : Array(String)? = nil,
                              extended_statistics : Array(String)? = nil,
                              dimensions : Hash(String, String)? = nil,
                              unit : String? = nil) : Response::GetMetricStatisticsOutput
      query Response::GetMetricStatisticsOutput, Params.new("GetMetricStatistics")
        .add("Namespace", namespace)
        .add("MetricName", metric_name)
        .add("StartTime", start_time)
        .add("EndTime", end_time)
        .add("Period", period)
        .add_list("Statistics", statistics)
        .add_list("ExtendedStatistics", extended_statistics)
        .add_pairs("Dimensions", dimensions)
        .add("Unit", unit)
    end

    # Fetches several metrics or metric math expressions at once.
    # *scan_by* is `TimestampDescending` (default) or `TimestampAscending`.
    def get_metric_data(queries : Array(MetricDataQuery), *,
                        start_time : Time, end_time : Time,
                        scan_by : String? = nil, max_datapoints : Int32? = nil,
                        next_token : String? = nil) : Response::GetMetricDataOutput
      query Response::GetMetricDataOutput, Params.new("GetMetricData")
        .add_structs("MetricDataQueries", queries)
        .add("StartTime", start_time)
        .add("EndTime", end_time)
        .add("ScanBy", scan_by)
        .add("MaxDatapoints", max_datapoints)
        .add("NextToken", next_token)
    end

    # Renders a graph as PNG. *metric_widget* is the widget JSON from the
    # console's "View source".
    def get_metric_widget_image(metric_widget : String) : Response::GetMetricWidgetImageOutput
      query Response::GetMetricWidgetImageOutput, Params.new("GetMetricWidgetImage")
        .add("MetricWidget", metric_widget)
        .add("OutputFormat", "png")
    end

    # Creates or replaces a dashboard. *dashboard_body* is the widget JSON.
    def put_dashboard(dashboard_name : String, dashboard_body : String) : Nil
      request Params.new("PutDashboard")
        .add("DashboardName", dashboard_name)
        .add("DashboardBody", dashboard_body)
    end

    def get_dashboard(dashboard_name : String) : Response::GetDashboardOutput
      query Response::GetDashboardOutput, Params.new("GetDashboard").add("DashboardName", dashboard_name)
    end

    def delete_dashboards(dashboard_names : Array(String)) : Nil
      request Params.new("DeleteDashboards").add_list("DashboardNames", dashboard_names)
    end

    def list_dashboards(dashboard_name_prefix : String? = nil, next_token : String? = nil) : Response::ListDashboardsOutput
      query Response::ListDashboardsOutput, Params.new("ListDashboards")
        .add("DashboardNamePrefix", dashboard_name_prefix)
        .add("NextToken", next_token)
    end

    # Trains an anomaly detection model for one metric and statistic.
    def put_anomaly_detector(namespace : String, metric_name : String, stat : String,
                             dimensions : Hash(String, String)? = nil) : Nil
      request Params.new("PutAnomalyDetector")
        .add("SingleMetricAnomalyDetector.Namespace", namespace)
        .add("SingleMetricAnomalyDetector.MetricName", metric_name)
        .add("SingleMetricAnomalyDetector.Stat", stat)
        .add_pairs("SingleMetricAnomalyDetector.Dimensions", dimensions)
    end

    def describe_anomaly_detectors(namespace : String? = nil, metric_name : String? = nil,
                                   dimensions : Hash(String, String)? = nil,
                                   next_token : String? = nil) : Response::DescribeAnomalyDetectorsOutput
      query Response::DescribeAnomalyDetectorsOutput, Params.new("DescribeAnomalyDetectors")
        .add("Namespace", namespace)
        .add("MetricName", metric_name)
        .add_pairs("Dimensions", dimensions)
        .add("NextToken", next_token)
    end

    def delete_anomaly_detector(namespace : String, metric_name : String, stat : String,
                                dimensions : Hash(String, String)? = nil) : Nil
      request Params.new("DeleteAnomalyDetector")
        .add("SingleMetricAnomalyDetector.Namespace", namespace)
        .add("SingleMetricAnomalyDetector.MetricName", metric_name)
        .add("SingleMetricAnomalyDetector.Stat", stat)
        .add_pairs("SingleMetricAnomalyDetector.Dimensions", dimensions)
    end
  end
end
