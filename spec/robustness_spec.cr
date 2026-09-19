require "./spec_helper"
require "./support/raw_server"

private def client_for(server : CW::Spec::RawServer, max_attempts = 3)
  CW::MetricClient.new("us-east-1", "key", "secret", endpoint: server.endpoint, max_attempts: max_attempts)
end

describe "malformed HTTP" do
  it "retries when the connection is closed without a response" do
    server = CW::Spec::RawServer.new([nil, nil, nil] of String?)
    expect_raises(IO::Error) { client_for(server).list_metrics }
    server.connections.should be >= 3 # HTTP::Client itself reconnects once per attempt
    server.close
  end

  it "recovers when a later attempt succeeds" do
    ok = "HTTP/1.1 200 OK\r\nContent-Type: text/xml\r\nContent-Length: #{CW::Spec.fixture("list_metrics").bytesize}\r\n\r\n#{CW::Spec.fixture("list_metrics")}"
    server = CW::Spec::RawServer.new([nil, ok] of String?)
    client_for(server).list_metrics.metrics.size.should eq 4
    server.close
  end

  it "fails cleanly on a truncated body" do
    truncated = "HTTP/1.1 200 OK\r\nContent-Length: 1000\r\n\r\n<ListMetricsResponse>"
    server = CW::Spec::RawServer.new([truncated, truncated, truncated] of String?)
    expect_raises(IO::Error | CW::Exception) { client_for(server).list_metrics }
    server.close
  end

  it "fails cleanly on garbage instead of HTTP" do
    server = CW::Spec::RawServer.new(Array(String?).new(3, "not http at all\r\n\r\n"))
    expect_raises(IO::Error | CW::Exception) { client_for(server).list_metrics }
    server.close
  end

  it "fails cleanly on a body without Content-Length" do
    server = CW::Spec::RawServer.new(["HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n" + CW::Spec.fixture("list_metrics")] of String?)
    client_for(server).list_metrics.metrics.size.should eq 4
    server.close
  end

  it "retries DNS failures" do
    client = CW::MetricClient.new("us-east-1", "key", "secret", endpoint: "http://awscr-cloudwatch.invalid", max_attempts: 2)
    expect_raises(IO::Error) { client.list_metrics }
  end
end

describe "response parsing under fuzzing" do
  now = Time.utc
  calls = {
    "list_metrics"               => ->(c : CW::Client) { c.metrics.list_metrics; nil },
    "get_metric_statistics"      => ->(c : CW::Client) { c.metrics.get_metric_statistics("n", "m", start_time: now, end_time: now, period: 60); nil },
    "get_metric_data_values"     => ->(c : CW::Client) { c.metrics.get_metric_data([] of CW::MetricDataQuery, start_time: now, end_time: now); nil },
    "describe_alarms"            => ->(c : CW::Client) { c.alarms.describe_alarms; nil },
    "describe_math_alarm"        => ->(c : CW::Client) { c.alarms.describe_alarms; nil },
    "describe_alarm_history"     => ->(c : CW::Client) { c.alarms.describe_alarm_history; nil },
    "describe_anomaly_detectors" => ->(c : CW::Client) { c.metrics.describe_anomaly_detectors; nil },
    "list_dashboards"            => ->(c : CW::Client) { c.metrics.list_dashboards; nil },
    "get_metric_widget_image"    => ->(c : CW::Client) { c.metrics.get_metric_widget_image("{}"); nil },
    "list_tags_for_resource"     => ->(c : CW::Client) { c.metrics.list_tags_for_resource("arn"); nil },
  }

  it "only ever raises the library exception" do
    random = Random.new(42)
    CW::Spec.with_fake_server do |server|
      client = CW::Client.new("us-east-1", "key", "secret", endpoint: server.endpoint, max_attempts: 1)
      calls.each do |name, call|
        body = CW::Spec.fixture(name)
        variants = [] of String
        (0...body.size).step(37) { |i| variants << body[0, i] }
        200.times do
          bytes = body.to_slice.dup
          3.times { bytes[random.rand(bytes.size)] = random.rand(256).to_u8 }
          variants << String.new(bytes)
        end
        variants << "<?xml version=\"1.0\"?>"
        variants << body.gsub(/<Timestamp>[^<]+/, "<Timestamp>garbage")
        variants << body.gsub(/<Threshold>[^<]+/, "<Threshold>abc")
        variants << body.gsub(/<Period>[^<]+/, "<Period>99999999999")
        variants << body.gsub(/<MetricWidgetImage>[^<]+/, "<MetricWidgetImage>@@@")

        variants.each do |variant|
          server.reply(variant)
          begin
            call.call(client)
          rescue CW::Exception
            # expected for broken input
          rescue ex
            fail "#{name}: #{ex.class} escaped for #{variant[0, 80].inspect}..."
          end
        end
      end
    end
  end
end
