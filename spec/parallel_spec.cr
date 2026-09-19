require "./spec_helper"

# Crystal 1.21 starts with a parallelism of 1; opt in for the whole run.
# Older releases (and -Dpreview_mt) size their scheduler from CRYSTAL_WORKERS.
{% if compare_versions(Crystal::VERSION, "1.21.0") >= 0 && Fiber.has_constant?("ExecutionContext") %}
  Fiber::ExecutionContext.default.resize(maximum: 4)
{% end %}

# Crystal's execution contexts occasionally lose a connect wakeup under
# parallelism (about 1 in 10,000 connects, also with a plain HTTP::Client).
# A short connect timeout lets the client's retry cover it.
private def parallel_client(server, max_attempts = 3)
  factory = CW::DefaultHttpClientFactory.new(connect_timeout: 1.second)
  CW::Spec.metric_client(server, max_attempts: max_attempts, client_factory: factory)
end

# Runs *workers* fibers and re-raises the first failure in the caller.
private def in_parallel(workers : Int32, &block : Int32 ->)
  results = Channel(Exception?).new
  workers.times do |w|
    spawn do
      block.call(w)
      results.send(nil)
    rescue ex
      results.send(ex)
    end
  end
  workers.times { results.receive.try { |ex| raise ex } }
end

describe "parallelism" do
  it "serves many fibers at once" do
    CW::Spec.with_fake_server do |server|
      client = parallel_client(server)
      in_parallel(16) do |w|
        40.times { |i| client.put_counter("MyApp", "Requests", i, dimensions: {"Worker" => w.to_s}) }
      end
      server.requests.size.should eq 640
      server.requests.map(&.params["MetricData.member.1.Dimensions.member.1.Value"]).tally.values.all?(40).should be_true
    end
  end

  it "keeps parallel responses and errors apart" do
    CW::Spec.with_fake_server do |server|
      template = CW::Spec.fixture("list_metrics")
      error = CW::Spec.fixture("error_invalid_value")
      server.responder = ->(req : CW::Spec::FakeCloudWatch::Request) do
        namespace = req.params["Namespace"]
        if namespace.ends_with?("-bad")
          CW::Spec::FakeCloudWatch::Reply.new(400, error.sub("The value NaN", "Bad #{namespace}"), Time::Span.zero)
        else
          CW::Spec::FakeCloudWatch::Reply.new(200, template.gsub("test-awscr-20260915", namespace), Time::Span.zero)
        end
      end
      client = parallel_client(server)

      in_parallel(16) do |w|
        40.times do |i|
          namespace = "ns-#{w}-#{i}"
          client.list_metrics(namespace: namespace).metrics.map(&.namespace).should eq [namespace] * 4
          ex = expect_raises(CW::Exception) { client.list_metrics(namespace: "#{namespace}-bad") }
          ex.message.should eq "InvalidParameterValue: Bad #{namespace}-bad for parameter MetricData.member.1.Value is invalid."
        end
      end
    end
  end

  it "parses XML in parallel" do
    in_parallel(8) do |w|
      300.times do |i|
        CW::XML.new(CW::Spec.fixture("describe_alarms")).string("DescribeAlarmsResponse/DescribeAlarmsResult/MetricAlarms/member/AlarmName").should eq "test-awscr-20260915-alarm"
        CW::XML.new("<a><b>#{w}-#{i}</b></a>").string("a/b").should eq "#{w}-#{i}"
        expect_raises(CW::Exception, "Invalid XML") { CW::XML.new("") }
      end
    end
  end
end
