require "../spec_helper"

# Runs against real AWS. See spec_helper.cr for the environment variables.
if CW::Spec.integration?
  describe "MetricClient (integration)" do
    client = CW::Spec.integration_client.metrics
    namespace = CW::Spec.test_prefix
    dims = {"Run" => Time.utc.to_unix.to_s}

    it "publishes metrics and reads them back" do
      start_time = Time.utc - 1.minute
      client.put_metric_data(namespace, [
        CW::MetricDatum.counter("Requests", 3, dims),
        CW::MetricDatum.new("Requests", 2, unit: "Count", dimensions: dims),
        CW::MetricDatum.new("Latency", values: [1.5, 2.5], counts: [2.0, 1.0], unit: "Milliseconds", dimensions: dims),
        CW::MetricDatum.new("Batch", dimensions: dims,
          statistic_values: CW::StatisticSet.new(sample_count: 4, sum: 10, minimum: 1, maximum: 4)),
        CW::MetricDatum.new("Extreme", 1e20, dimensions: dims),
        CW::MetricDatum.new("Tiny", 1e-7, dimensions: dims),
        CW::MetricDatum.new("HighRes", 1, storage_resolution: 1, timestamp: Time.utc, dimensions: dims),
      ])
      client.put_counter(namespace, "Requests", dimensions: dims)

      stats = ->(metric : String, statistics : Array(String), extended : Array(String)?) do
        client.get_metric_statistics(namespace, metric,
          start_time: start_time, end_time: Time.utc + 1.minute, period: 300,
          statistics: statistics, extended_statistics: extended, dimensions: dims)
      end

      requests = stats.call("Requests", ["Sum", "SampleCount", "Minimum", "Maximum"], nil)
      CW::Spec.eventually do
        requests = stats.call("Requests", ["Sum", "SampleCount", "Minimum", "Maximum"], nil)
        requests.datapoints.sum { |d| d.sample_count || 0.0 } == 3.0
      end
      requests.label.should eq "Requests"
      requests.datapoints.sum { |d| d.sum || 0.0 }.should eq 6.0
      requests.datapoints.compact_map(&.minimum).min.should eq 1.0
      requests.datapoints.compact_map(&.maximum).max.should eq 3.0
      requests.datapoints.first.unit.should eq "Count"

      latency = stats.call("Latency", ["SampleCount", "Sum"], ["p50"])
      CW::Spec.eventually do
        latency = stats.call("Latency", ["SampleCount", "Sum"], ["p50"])
        latency.datapoints.sum { |d| d.sample_count || 0.0 } == 3.0
      end
      latency.datapoints.sum { |d| d.sum || 0.0 }.should eq 5.5
      latency.datapoints.first.extended_statistics["p50"].should be_close(1.5, 1.0)

      batch = stats.call("Batch", ["SampleCount", "Sum", "Minimum", "Maximum"], nil)
      CW::Spec.eventually do
        batch = stats.call("Batch", ["SampleCount", "Sum", "Minimum", "Maximum"], nil)
        batch.datapoints.sum { |d| d.sample_count || 0.0 } == 4.0
      end
      batch.datapoints.sum { |d| d.sum || 0.0 }.should eq 10.0
      batch.datapoints.compact_map(&.minimum).min.should eq 1.0
      batch.datapoints.compact_map(&.maximum).max.should eq 4.0

      CW::Spec.eventually { stats.call("Extreme", ["Sum"], nil).datapoints.sum { |d| d.sum || 0.0 } == 1e20 }
      CW::Spec.eventually { stats.call("Tiny", ["Sum"], nil).datapoints.sum { |d| d.sum || 0.0 } == 1e-7 }
      CW::Spec.eventually { stats.call("HighRes", ["Sum"], nil).datapoints.sum { |d| d.sum || 0.0 } == 1.0 }

      queries = [
        CW::MetricDataQuery.new("requests", metric_stat: CW::MetricStat.new(CW::Metric.new(namespace, "Requests", dims), 300, "Sum")),
        CW::MetricDataQuery.new("doubled", expression: "requests * 2", label: "Doubled"),
      ]
      data = client.get_metric_data(queries, start_time: start_time, end_time: Time.utc + 1.minute)
      data.metric_data_results.map(&.id).should eq ["requests", "doubled"]
      data.metric_data_results[0].values.sum.should eq 6.0
      data.metric_data_results[1].values.sum.should eq 12.0
      data.metric_data_results[1].label.should eq "Doubled"
      data.metric_data_results.map(&.status_code).should eq ["Complete", "Complete"]

      # New metrics can take minutes to show up here, so only the call is checked.
      client.list_metrics(namespace: namespace, recently_active: true).metrics.each do |metric|
        metric.namespace.should eq namespace
      end
    end

    it "preserves special characters in names and dimensions" do
      # AWS only accepts ASCII in metric names and dimensions.
      special_dims = {"Path" => "/a b+c&d=e%f #{dims["Run"]}"}
      start_time = Time.utc - 1.minute
      client.put_counter(namespace, "Special Chars", 7, dimensions: special_dims)

      CW::Spec.eventually do
        stats = client.get_metric_statistics(namespace, "Special Chars",
          start_time: start_time, end_time: Time.utc + 1.minute, period: 300, statistics: ["Sum"], dimensions: special_dims)
        stats.datapoints.sum { |d| d.sum || 0.0 } == 7.0
      end
    end

    it "raises AWS errors" do
      ex = expect_raises(CW::Exception, "MissingParameter") { client.put_metric_data(namespace, [] of CW::MetricDatum) }
      ex.code.should eq "MissingParameter"
      ex.status.should eq HTTP::Status::BAD_REQUEST
      ex.request_id.should_not be_nil

      too_many = (1..1001).map { |i| CW::MetricDatum.counter("Metric#{i}") }
      expect_raises(CW::Exception, "InvalidParameterValue: The collection MetricData must not have a size greater than 1000.") do
        client.put_metric_data(namespace, too_many)
      end

      both = [CW::MetricDatum.new("Requests", 1, values: [1.0], dimensions: dims)]
      expect_raises(CW::Exception, "InvalidParameterCombination") { client.put_metric_data(namespace, both) }

      wrong_secret = CW::MetricClient.new(client.region, ENV["AWS_ACCESS_KEY_ID"], "wrong", endpoint: ENV["AWS_ENDPOINT_URL"]?)
      ex = expect_raises(CW::Exception, "SignatureDoesNotMatch") { wrong_secret.list_metrics(namespace: namespace) }
      ex.status.should eq HTTP::Status::FORBIDDEN
      ex.retryable?.should be_false
    end

    it "works with a factory that reuses the connection" do
      factory = CW::Spec::SingleConnectionFactory.new
      reusing = CW::MetricClient.new(client.region, ENV["AWS_ACCESS_KEY_ID"], ENV["AWS_SECRET_ACCESS_KEY"], ENV["AWS_SESSION_TOKEN"]?,
        endpoint: ENV["AWS_ENDPOINT_URL"]?, client_factory: factory)
      3.times do |i|
        sleep 2.seconds if i > 0
        reusing.put_counter(namespace, "Reused", dimensions: dims)
      end
      factory.acquired.should eq 3
    end

    it "renders a widget image" do
      widget = %({"metrics":[["#{namespace}","Requests","Run","#{dims["Run"]}"]],"width":100,"height":100})
      client.get_metric_widget_image(widget).image[0, 4].should eq Bytes[0x89, 0x50, 0x4E, 0x47]
    end

    it "manages dashboards" do
      name = "#{namespace}-dashboard-#{dims["Run"]}"
      body = %({"widgets":[{"type":"text","x":0,"y":0,"width":6,"height":3,"properties":{"markdown":"# awscr-cloudwatch"}}]})
      begin
        client.put_dashboard(name, body)
        client.get_dashboard(name).dashboard_body.should eq body
        client.list_dashboards(dashboard_name_prefix: name).dashboard_entries.map(&.dashboard_name).should eq [name]
      ensure
        client.delete_dashboards([name])
      end
      client.list_dashboards(dashboard_name_prefix: name).dashboard_entries.should be_empty
    end

    it "manages anomaly detectors" do
      begin
        client.put_anomaly_detector(namespace, "Requests", "Sum", dimensions: dims)
        detectors = client.describe_anomaly_detectors(namespace: namespace, metric_name: "Requests", dimensions: dims).anomaly_detectors
        detectors.map(&.stat).should eq ["Sum"]
        detectors.first.dimensions.should eq dims
        detectors.first.state_value.should eq "PENDING_TRAINING"
      ensure
        client.delete_anomaly_detector(namespace, "Requests", "Sum", dimensions: dims)
      end
      client.describe_anomaly_detectors(namespace: namespace, metric_name: "Requests", dimensions: dims).anomaly_detectors.should be_empty
    end
  end
end
