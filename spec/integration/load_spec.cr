require "../spec_helper"

# Runs against real AWS. See spec_helper.cr for the environment variables.
if CW::Spec.integration?
  describe "load (integration)" do
    client = CW::Spec.integration_client.metrics
    namespace = CW::Spec.test_prefix
    dims = {"Load" => Time.utc.to_unix.to_s}

    sum_of = ->(metric : String, start_time : Time) do
      stats = client.get_metric_statistics(namespace, metric, dimensions: dims,
        start_time: start_time, end_time: Time.utc + 1.minute, period: 300, statistics: ["Sum", "SampleCount"])
      {stats.datapoints.sum { |d| d.sum || 0.0 }, stats.datapoints.sum { |d| d.sample_count || 0.0 }}
    end

    it "sustains sequential and parallel uploads" do
      start_time = Time.utc - 1.minute

      elapsed = Time.measure { 100.times { client.put_counter(namespace, "Sequential", dimensions: dims) } }
      (elapsed / 100).should be < 1.second

      results = Channel(Exception?).new
      50.times do
        spawn do
          client.put_counter(namespace, "Parallel", dimensions: dims)
          results.send(nil)
        rescue ex
          results.send(ex)
        end
      end
      (1..50).compact_map { results.receive }.should be_empty

      CW::Spec.eventually { sum_of.call("Sequential", start_time)[0] == 100.0 }
      CW::Spec.eventually { sum_of.call("Parallel", start_time)[0] == 50.0 }
    end

    it "accepts a batch close to the 1 MB limit" do
      start_time = Time.utc - 1.minute
      values = (1..150).map(&.to_f64)
      batch = (1..150).map { CW::MetricDatum.new("Bulk", values: values, unit: "Count", dimensions: dims) }
      body = URI::Params.encode(CW::Params.new("PutMetricData").add_structs("MetricData", batch).to_h)
      body.bytesize.should be > 700 * 1024
      body.bytesize.should be < 1024 * 1024

      client.put_metric_data(namespace, batch)

      CW::Spec.eventually { sum_of.call("Bulk", start_time) == {150 * values.sum, 150.0 * 150} }
    end

    it "reports connect timeouts" do
      factory = CW::DefaultHttpClientFactory.new(connect_timeout: 1.millisecond)
      slow = CW::MetricClient.new(client.region, ENV["AWS_ACCESS_KEY_ID"], ENV["AWS_SECRET_ACCESS_KEY"], ENV["AWS_SESSION_TOKEN"]?,
        endpoint: ENV["AWS_ENDPOINT_URL"]?, client_factory: factory, max_attempts: 2)
      expect_raises(IO::Error) { slow.list_metrics(namespace: namespace) }
    end
  end
end
