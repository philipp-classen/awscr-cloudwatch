require "./spec_helper"

private def with_metric_client(&)
  CW::Spec.with_fake_server do |server|
    yield CW::Spec.metric_client(server), server
  end
end

describe CW::MetricClient do
  describe "#put_metric_data" do
    it "serializes every kind of datum" do
      with_metric_client do |client, server|
        server.reply(CW::Spec.fixture("put_metric_data"))
        client.put_metric_data("MyApp", [
          CW::MetricDatum.new("Requests", 3, unit: "Count", dimensions: {"Env" => "test", "Host" => "a"},
            timestamp: Time.utc(2026, 9, 15, 12, 0, 0), storage_resolution: 1),
          CW::MetricDatum.new("Latency", values: [1.5, 2.5], counts: [2.0, 1.0], unit: "Milliseconds"),
          CW::MetricDatum.new("Batch", statistic_values: CW::StatisticSet.new(sample_count: 4, sum: 10, minimum: 1, maximum: 4)),
        ])

        server.last_request.params.should eq CW::Spec.params("PutMetricData", {
          "Namespace"                                       => "MyApp",
          "MetricData.member.1.MetricName"                  => "Requests",
          "MetricData.member.1.Value"                       => "3.0",
          "MetricData.member.1.Unit"                        => "Count",
          "MetricData.member.1.Timestamp"                   => "2026-09-15T12:00:00Z",
          "MetricData.member.1.StorageResolution"           => "1",
          "MetricData.member.1.Dimensions.member.1.Name"    => "Env",
          "MetricData.member.1.Dimensions.member.1.Value"   => "test",
          "MetricData.member.1.Dimensions.member.2.Name"    => "Host",
          "MetricData.member.1.Dimensions.member.2.Value"   => "a",
          "MetricData.member.2.MetricName"                  => "Latency",
          "MetricData.member.2.Values.member.1"             => "1.5",
          "MetricData.member.2.Values.member.2"             => "2.5",
          "MetricData.member.2.Counts.member.1"             => "2.0",
          "MetricData.member.2.Counts.member.2"             => "1.0",
          "MetricData.member.2.Unit"                        => "Milliseconds",
          "MetricData.member.3.MetricName"                  => "Batch",
          "MetricData.member.3.StatisticValues.SampleCount" => "4.0",
          "MetricData.member.3.StatisticValues.Sum"         => "10.0",
          "MetricData.member.3.StatisticValues.Minimum"     => "1.0",
          "MetricData.member.3.StatisticValues.Maximum"     => "4.0",
        })
      end
    end

    it "raises when AWS rejects the request" do
      with_metric_client do |client, server|
        server.reply(CW::Spec.fixture("error_missing_param"), 400)
        ex = expect_raises(CW::Exception, "MissingParameter: At least one MetricDatum object must be present in the request.") do
          client.put_metric_data("MyApp", [] of CW::MetricDatum)
        end
        ex.code.should eq "MissingParameter"
      end
    end
  end

  describe "#put_counter" do
    it "publishes one Count datum" do
      with_metric_client do |client, server|
        client.put_counter("MyApp", "Requests", 5, dimensions: {"Env" => "prod"})
        server.last_request.params.should eq CW::Spec.params("PutMetricData", {
          "Namespace"                                     => "MyApp",
          "MetricData.member.1.MetricName"                => "Requests",
          "MetricData.member.1.Value"                     => "5.0",
          "MetricData.member.1.Unit"                      => "Count",
          "MetricData.member.1.Dimensions.member.1.Name"  => "Env",
          "MetricData.member.1.Dimensions.member.1.Value" => "prod",
        })

        client.put_counter("MyApp", "Requests")
        server.last_request.params["MetricData.member.1.Value"].should eq "1.0"

        client.put_counter("MyApp", "Requests", timestamp: Time.utc(2026, 9, 15, 12, 0, 0))
        server.last_request.params["MetricData.member.1.Timestamp"].should eq "2026-09-15T12:00:00Z"
      end
    end
  end

  describe "encoding" do
    it "preserves special characters" do
      with_metric_client do |client, server|
        dims = {"Path" => "/a b+c&d=e%f", "Name" => "Ünïcödé ✓"}
        client.put_counter("My App/Ünit", "Requests", dimensions: dims)

        params = server.last_request.params
        params["Namespace"].should eq "My App/Ünit"
        params["MetricData.member.1.Dimensions.member.1.Value"].should eq "/a b+c&d=e%f"
        params["MetricData.member.1.Dimensions.member.2.Value"].should eq "Ünïcödé ✓"
      end
    end
  end

  describe "large batches" do
    it "sends 1000 data points in one request" do
      with_metric_client do |client, server|
        data = (1..1000).map { |i| CW::MetricDatum.counter("Metric#{i}", i, {"Env" => "test"}) }
        client.put_metric_data("MyApp", data)

        params = server.last_request.params
        params.size.should eq 3 + 1000 * 5
        params["MetricData.member.1000.MetricName"].should eq "Metric1000"
        params["MetricData.member.1000.Value"].should eq "1000.0"
      end
    end
  end

  describe "#list_metrics" do
    it "sends filters and parses metrics" do
      with_metric_client do |client, server|
        server.reply(CW::Spec.fixture("list_metrics"))
        result = client.list_metrics(namespace: "MyApp", metric_name: "Requests",
          dimensions: [CW::DimensionFilter.new("Env", "test"), CW::DimensionFilter.new("Host")],
          recently_active: true, next_token: "abc")

        server.last_request.params.should eq CW::Spec.params("ListMetrics", {
          "Namespace"                 => "MyApp",
          "MetricName"                => "Requests",
          "Dimensions.member.1.Name"  => "Env",
          "Dimensions.member.1.Value" => "test",
          "Dimensions.member.2.Name"  => "Host",
          "RecentlyActive"            => "PT3H",
          "NextToken"                 => "abc",
        })
        result.metrics.size.should eq 4
        result.metrics.first.should eq CW::Metric.new("test-awscr-20260915", "Requests", {"Env" => "test"})
        result.metrics[1].dimensions.should be_empty
        result.next_token.should be_nil
        result.request_id.should eq "eb2714ec-f391-431c-bf75-0dbb49c2307f"
        result.status.should eq HTTP::Status::OK
        result.headers["Content-Type"].should eq "text/xml"
      end
    end

    it "returns the token of the next page" do
      with_metric_client do |client, server|
        server.reply(CW::Spec.fixture("list_metrics").sub("</Metrics>", "</Metrics><NextToken>page-2</NextToken>"))
        client.list_metrics(namespace: "MyApp").next_token.should eq "page-2"
      end
    end
  end

  describe "#get_metric_statistics" do
    it "parses datapoints" do
      with_metric_client do |client, server|
        server.reply(CW::Spec.fixture("get_metric_statistics"))
        result = client.get_metric_statistics("MyApp", "Requests",
          start_time: Time.utc(2026, 9, 15, 18, 0, 0), end_time: Time.utc(2026, 9, 15, 19, 0, 0), period: 300,
          statistics: ["Sum", "SampleCount"], dimensions: {"Env" => "test"}, unit: "Count")

        server.last_request.params.should eq CW::Spec.params("GetMetricStatistics", {
          "Namespace"                 => "MyApp",
          "MetricName"                => "Requests",
          "StartTime"                 => "2026-09-15T18:00:00Z",
          "EndTime"                   => "2026-09-15T19:00:00Z",
          "Period"                    => "300",
          "Statistics.member.1"       => "Sum",
          "Statistics.member.2"       => "SampleCount",
          "Dimensions.member.1.Name"  => "Env",
          "Dimensions.member.1.Value" => "test",
          "Unit"                      => "Count",
        })
        result.label.should eq "Requests"
        result.datapoints.size.should eq 1
        dp = result.datapoints.first
        dp.timestamp.should eq Time.utc(2026, 9, 15, 18, 59, 0)
        dp.sum.should eq 3.0
        dp.sample_count.should eq 1.0
        dp.average.should eq 3.0
        dp.minimum.should eq 3.0
        dp.maximum.should eq 3.0
        dp.unit.should eq "Count"
        dp.extended_statistics.should be_empty
      end
    end

    it "parses percentiles" do
      with_metric_client do |client, server|
        server.reply(CW::Spec.fixture("get_metric_statistics_percentiles"))
        result = client.get_metric_statistics("MyApp", "Latency",
          start_time: Time.utc(2026, 9, 15, 18, 0, 0), end_time: Time.utc(2026, 9, 15, 19, 0, 0), period: 300,
          extended_statistics: ["p50", "p99"])

        server.last_request.params["ExtendedStatistics.member.2"].should eq "p99"
        dp = result.datapoints.first
        dp.sample_count.should eq 3.0
        dp.sum.should be_nil
        dp.extended_statistics.should eq({"p99" => 2.1234567890127626, "p50" => 1.123456789012321})
      end
    end
  end

  describe "#get_metric_data" do
    it "serializes queries and parses results" do
      with_metric_client do |client, server|
        server.reply(CW::Spec.fixture("get_metric_data_values"))
        queries = [
          CW::MetricDataQuery.new("m1", return_data: false,
            metric_stat: CW::MetricStat.new(CW::Metric.new("MyApp", "Requests", {"Env" => "test"}), 300, "Sum", unit: "Count")),
          CW::MetricDataQuery.new("e1", expression: "m1 * 2", label: "Doubled", period: 300, account_id: "123456789012"),
        ]
        result = client.get_metric_data(queries,
          start_time: Time.utc(2026, 9, 15, 18, 0, 0), end_time: Time.utc(2026, 9, 15, 19, 0, 0),
          scan_by: "TimestampAscending", max_datapoints: 100, next_token: "tok")

        server.last_request.params.should eq CW::Spec.params("GetMetricData", {
          "MetricDataQueries.member.1.Id"                                          => "m1",
          "MetricDataQueries.member.1.ReturnData"                                  => "false",
          "MetricDataQueries.member.1.MetricStat.Metric.Namespace"                 => "MyApp",
          "MetricDataQueries.member.1.MetricStat.Metric.MetricName"                => "Requests",
          "MetricDataQueries.member.1.MetricStat.Metric.Dimensions.member.1.Name"  => "Env",
          "MetricDataQueries.member.1.MetricStat.Metric.Dimensions.member.1.Value" => "test",
          "MetricDataQueries.member.1.MetricStat.Period"                           => "300",
          "MetricDataQueries.member.1.MetricStat.Stat"                             => "Sum",
          "MetricDataQueries.member.1.MetricStat.Unit"                             => "Count",
          "MetricDataQueries.member.2.Id"                                          => "e1",
          "MetricDataQueries.member.2.Expression"                                  => "m1 * 2",
          "MetricDataQueries.member.2.Label"                                       => "Doubled",
          "MetricDataQueries.member.2.Period"                                      => "300",
          "MetricDataQueries.member.2.AccountId"                                   => "123456789012",
          "StartTime"                                                              => "2026-09-15T18:00:00Z",
          "EndTime"                                                                => "2026-09-15T19:00:00Z",
          "ScanBy"                                                                 => "TimestampAscending",
          "MaxDatapoints"                                                          => "100",
          "NextToken"                                                              => "tok",
        })
        result.metric_data_results.size.should eq 2
        m1 = result.metric_data_results[0]
        m1.id.should eq "m1"
        m1.label.should eq "Requests"
        m1.timestamps.should eq [Time.utc(2026, 9, 15, 18, 59, 0)]
        m1.values.should eq [3.0]
        m1.status_code.should eq "Complete"
        m1.messages.should be_empty
        result.metric_data_results[1].values.should eq [6.0]
        result.messages.should be_empty
        result.next_token.should be_nil
      end
    end

    it "parses partial results with messages" do
      with_metric_client do |client, server|
        server.reply(CW::Spec.fixture("get_metric_data"))
        result = client.get_metric_data([CW::MetricDataQuery.new("e1", expression: "m1 * 2")],
          start_time: Time.utc, end_time: Time.utc)

        e1 = result.metric_data_results[1]
        e1.status_code.should eq "PartialData"
        e1.timestamps.should be_empty
        e1.messages.first.code.should eq "PartialData"
        e1.messages.first.value.to_s.should start_with "The expression may contain partial data"
      end
    end
  end

  describe "#get_metric_widget_image" do
    it "decodes the PNG" do
      with_metric_client do |client, server|
        server.reply(CW::Spec.fixture("get_metric_widget_image"))
        png = client.get_metric_widget_image(%({"metrics":[["MyApp","Requests"]]})).image

        server.last_request.params.should eq CW::Spec.params("GetMetricWidgetImage", {
          "MetricWidget" => %({"metrics":[["MyApp","Requests"]]}),
          "OutputFormat" => "png",
        })
        png[0, 8].should eq Bytes[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
      end
    end
  end

  describe "dashboards" do
    it "puts, gets, lists and deletes" do
      with_metric_client do |client, server|
        client.put_dashboard("Main", %({"widgets":[]}))
        server.last_request.params.should eq CW::Spec.params("PutDashboard", {
          "DashboardName" => "Main",
          "DashboardBody" => %({"widgets":[]}),
        })

        server.reply(CW::Spec.fixture("get_dashboard"))
        dashboard = client.get_dashboard("Main")
        server.last_request.params.should eq CW::Spec.params("GetDashboard", {"DashboardName" => "Main"})
        dashboard.dashboard_name.should eq "test-awscr-20260915-dashboard"
        dashboard.dashboard_arn.should eq "arn:aws:cloudwatch::123456789012:dashboard/test-awscr-20260915-dashboard"
        dashboard.dashboard_body.should eq %({"widgets":[{"type":"text","x":0,"y":0,"width":6,"height":3,"properties":{"markdown":"# test"}}]})

        server.reply(CW::Spec.fixture("list_dashboards"))
        list = client.list_dashboards(dashboard_name_prefix: "test", next_token: "t")
        server.last_request.params.should eq CW::Spec.params("ListDashboards", {"DashboardNamePrefix" => "test", "NextToken" => "t"})
        entry = list.dashboard_entries.first
        entry.dashboard_name.should eq "test-awscr-20260915-dashboard"
        entry.size.should eq 134
        entry.last_modified.should eq Time.utc(2026, 9, 15, 19, 14, 18)
        list.next_token.should be_nil

        client.delete_dashboards(["Main", "Other"])
        server.last_request.params.should eq CW::Spec.params("DeleteDashboards", {
          "DashboardNames.member.1" => "Main",
          "DashboardNames.member.2" => "Other",
        })
      end
    end
  end

  describe "anomaly detectors" do
    it "puts, describes and deletes" do
      with_metric_client do |client, server|
        client.put_anomaly_detector("MyApp", "Requests", "Sum", dimensions: {"Env" => "test"})
        server.last_request.params.should eq CW::Spec.params("PutAnomalyDetector", {
          "SingleMetricAnomalyDetector.Namespace"                 => "MyApp",
          "SingleMetricAnomalyDetector.MetricName"                => "Requests",
          "SingleMetricAnomalyDetector.Stat"                      => "Sum",
          "SingleMetricAnomalyDetector.Dimensions.member.1.Name"  => "Env",
          "SingleMetricAnomalyDetector.Dimensions.member.1.Value" => "test",
        })

        server.reply(CW::Spec.fixture("describe_anomaly_detectors"))
        result = client.describe_anomaly_detectors(namespace: "MyApp", metric_name: "Requests", dimensions: {"Env" => "test"})
        server.last_request.params.should eq CW::Spec.params("DescribeAnomalyDetectors", {
          "Namespace"                 => "MyApp",
          "MetricName"                => "Requests",
          "Dimensions.member.1.Name"  => "Env",
          "Dimensions.member.1.Value" => "test",
        })
        detector = result.anomaly_detectors.first
        detector.namespace.should eq "test-awscr-20260915"
        detector.metric_name.should eq "Requests"
        detector.stat.should eq "Sum"
        detector.dimensions.should eq({"Env" => "test"})
        detector.state_value.should eq "PENDING_TRAINING"
        detector.metric_timezone.should be_nil

        client.delete_anomaly_detector("MyApp", "Requests", "Sum")
        server.last_request.params.should eq CW::Spec.params("DeleteAnomalyDetector", {
          "SingleMetricAnomalyDetector.Namespace"  => "MyApp",
          "SingleMetricAnomalyDetector.MetricName" => "Requests",
          "SingleMetricAnomalyDetector.Stat"       => "Sum",
        })
      end
    end
  end

  describe "metric streams" do
    it "serializes the requests" do
      with_metric_client do |client, server|
        client.put_metric_stream("s", "arn:firehose", "arn:role", "json", include_filters: ["MyApp"], exclude_filters: ["AWS/EC2"])
        server.last_request.params.should eq CW::Spec.params("PutMetricStream", {
          "Name"                              => "s",
          "FirehoseArn"                       => "arn:firehose",
          "RoleArn"                           => "arn:role",
          "OutputFormat"                      => "json",
          "IncludeFilters.member.1.Namespace" => "MyApp",
          "ExcludeFilters.member.1.Namespace" => "AWS/EC2",
        })

        server.reply(CW::Spec.fixture("list_metric_streams"))
        client.list_metric_streams.entries.should be_empty

        client.delete_metric_stream("s")
        server.last_request.params.should eq CW::Spec.params("DeleteMetricStream", {"Name" => "s"})
      end
    end
  end
end
