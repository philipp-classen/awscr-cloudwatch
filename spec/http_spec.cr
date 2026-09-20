require "./spec_helper"

describe CW::Http do
  it "signs requests with SigV4 for the monitoring service" do
    CW::Spec.with_fake_server do |server|
      server.reply(CW::Spec.fixture("list_metrics"))
      CW::Spec.metric_client(server).list_metrics
      req = server.last_request
      req.method.should eq "POST"
      req.path.should eq "/"
      req.headers["Content-Type"].should eq "application/x-www-form-urlencoded; charset=utf-8"
      req.headers["Authorization"].should match(/^AWS4-HMAC-SHA256 Credential=key\/\d{8}\/us-east-1\/monitoring\/aws4_request, SignedHeaders=.*, Signature=[0-9a-f]{64}$/)
      req.headers["X-Amz-Date"].should match(/^\d{8}T\d{6}Z$/)
      req.headers["X-Amz-Security-Token"]?.should be_nil
    end
  end

  it "is rejected by the fake server when the signature is wrong" do
    CW::Spec.with_fake_server do |server|
      client = CW::MetricClient.new("us-east-1", "key", "wrong", endpoint: server.endpoint, max_attempts: 1)
      ex = expect_raises(CW::Exception, "SignatureDoesNotMatch") { client.list_metrics }
      ex.status.should eq HTTP::Status::FORBIDDEN
    end
  end

  it "sends the session token of temporary credentials" do
    CW::Spec.with_fake_server do |server|
      server.reply(CW::Spec.fixture("list_metrics"))
      CW::Spec.metric_client(server, aws_session_key: "token").list_metrics
      server.last_request.headers["X-Amz-Security-Token"].should eq "token"
    end
  end

  it "raises with code, message, request id and status for client errors" do
    CW::Spec.with_fake_server do |server|
      server.reply(CW::Spec.fixture("error_invalid_value"), 400)
      ex = expect_raises(CW::Exception, "InvalidParameterValue: The value NaN for parameter MetricData.member.1.Value is invalid.") do
        CW::Spec.metric_client(server).list_metrics
      end
      ex.code.should eq "InvalidParameterValue"
      ex.request_id.should eq "3bce2626-6128-46bd-b6aa-a22368ac2f02"
      ex.status.should eq HTTP::Status::BAD_REQUEST
      ex.retryable?.should be_false
      server.requests.size.should eq 1
    end
  end

  it "handles error responses without a message" do
    CW::Spec.with_fake_server do |server|
      server.reply(CW::Spec.fixture("error_not_found"), 404)
      ex = expect_raises(CW::Exception, "ResourceNotFound") { CW::Spec.metric_client(server).list_metrics }
      ex.code.should eq "ResourceNotFound"
      ex.status.should eq HTTP::Status::NOT_FOUND
    end
  end

  it "raises ExpiredTokenException for expired session tokens" do
    CW::Spec.with_fake_server do |server|
      server.reply(CW::Spec.fixture("error_expired_token"), 403)
      ex = expect_raises(CW::ExpiredTokenException, "ExpiredTokenException: The security token included in the request has expired. Request a new security token and try again.") do
        CW::Spec.metric_client(server).list_metrics
      end
      ex.code.should eq "ExpiredTokenException"
      ex.status.should eq HTTP::Status::FORBIDDEN
      ex.retryable?.should be_false
      server.requests.size.should eq 1 # callers refresh instead of retrying

      # STS reports the same condition as "ExpiredToken".
      server.reply(CW::Spec.fixture("error_expired_token").sub("ExpiredTokenException", "ExpiredToken"), 403)
      expect_raises(CW::ExpiredTokenException) { CW::Spec.metric_client(server).list_metrics }
    end
  end

  it "parses errors from the generic AWS fault namespace" do
    CW::Spec.with_fake_server do |server|
      server.reply(CW::Spec.fixture("error_invalid_action"), 400)
      ex = expect_raises(CW::Exception, "InvalidAction: Could not find operation NoSuchAction for version 2010-08-01") do
        CW::Spec.metric_client(server).list_metrics
      end
      ex.request_id.should eq "bfd984dd-6a89-4ab3-a3cc-4ecf47228768"
    end
  end

  it "parses responses without a namespace or with a prefixed one" do
    CW::Spec.with_fake_server do |server|
      fixture = CW::Spec.fixture("list_metrics")
      server.reply(fixture.sub(%( xmlns="http://monitoring.amazonaws.com/doc/2010-08-01/"), ""))
      CW::Spec.metric_client(server).list_metrics.metrics.size.should eq 4

      prefixed = fixture.gsub(%( xmlns="http://monitoring.amazonaws.com/doc/2010-08-01/"), %( xmlns:cw="http://monitoring.amazonaws.com/doc/2010-08-01/"))
        .gsub(/<(\/?)([A-Za-z]+)/) { "<#{$1}cw:#{$2}" }
      server.reply(prefixed)
      CW::Spec.metric_client(server).list_metrics.metrics.size.should eq 4
    end
  end

  it "posts to the path of a custom endpoint" do
    CW::Spec.with_fake_server do |server|
      server.reply(CW::Spec.fixture("list_metrics"))
      CW::MetricClient.new("us-east-1", "key", "secret", endpoint: "#{server.endpoint}/cloudwatch/").list_metrics
      server.last_request.path.should eq "/cloudwatch/"
    end
  end

  it "reads compressed responses and bodies with a byte order mark" do
    CW::Spec.with_fake_server do |server|
      server.reply_gzipped(CW::Spec.fixture("list_metrics"))
      CW::Spec.metric_client(server).list_metrics.metrics.size.should eq 4

      server.reply("\uFEFF" + CW::Spec.fixture("list_metrics"))
      CW::Spec.metric_client(server).list_metrics.metrics.size.should eq 4
    end
  end

  it "does not follow redirects" do
    CW::Spec.with_fake_server do |server|
      server.reply("", 301)
      ex = expect_raises(CW::Exception, "HTTP 301 Moved Permanently") { CW::Spec.metric_client(server).list_metrics }
      ex.retryable?.should be_false
      server.requests.size.should eq 1
    end
  end

  it "handles non-XML error responses" do
    CW::Spec.with_fake_server do |server|
      server.reply("<html>Bad Gateway</html>", 502)
      server.reply("Bad Gateway", 502)
      server.reply("", 502)
      ex = expect_raises(CW::Exception, "HTTP 502") { CW::Spec.metric_client(server).list_metrics }
      ex.code.should be_nil
      ex.status.should eq HTTP::Status::BAD_GATEWAY
    end
  end

  it "retries server errors" do
    CW::Spec.with_fake_server do |server|
      server.reply("<ErrorResponse><Error><Code>InternalFailure</Code></Error></ErrorResponse>", 500)
      server.reply(CW::Spec.fixture("list_metrics"))
      CW::Spec.metric_client(server).list_metrics.metrics.size.should eq 4
      server.requests.size.should eq 2
    end
  end

  it "retries throttling" do
    CW::Spec.with_fake_server do |server|
      throttled = "<ErrorResponse><Error><Type>Sender</Type><Code>Throttling</Code><Message>Rate exceeded</Message></Error></ErrorResponse>"
      server.reply(throttled, 400)
      server.reply(throttled, 400)
      server.reply(CW::Spec.fixture("put_metric_data"))
      CW::Spec.metric_client(server).put_counter("MyApp", "Requests")
      server.requests.size.should eq 3
    end
  end

  it "gives up after max_attempts" do
    CW::Spec.with_fake_server do |server|
      3.times { server.reply("", 503) }
      expect_raises(CW::Exception, "HTTP 503") { CW::Spec.metric_client(server).list_metrics }
      server.requests.size.should eq 3

      server.reply("", 503)
      server.reply("", 503)
      expect_raises(CW::Exception, "HTTP 503") { CW::Spec.metric_client(server, max_attempts: 1).list_metrics }
      server.requests.size.should eq 4

      expect_raises(CW::Exception, "HTTP 503") { CW::Spec.metric_client(server, max_attempts: 0).list_metrics }
      server.requests.size.should eq 5
    end
  end

  it "retries connection errors" do
    server = CW::Spec::FakeCloudWatch.new
    client = CW::Spec.metric_client(server)
    server.close
    expect_raises(IO::Error) { client.list_metrics }
  end

  it "retries read timeouts" do
    CW::Spec.with_fake_server do |server|
      # HTTP::Client itself retries once per attempt when the connection drops.
      6.times { server.reply(CW::Spec.fixture("list_metrics"), delay: 300.milliseconds) }
      factory = CW::DefaultHttpClientFactory.new(read_timeout: 50.milliseconds)
      expect_raises(IO::TimeoutError) { CW::Spec.metric_client(server, client_factory: factory).list_metrics }
      server.requests.size.should be >= 3
    end
  end

  it "raises when a 2xx body is empty" do
    CW::Spec.with_fake_server do |server|
      expect_raises(CW::Exception, "Invalid XML") { CW::Spec.metric_client(server).list_metrics }
    end
  end

  it "raises when a 2xx body is not the expected document" do
    CW::Spec.with_fake_server do |server|
      server.reply("<html>proxy</html>")
      expect_raises(CW::Exception, "Missing element: ListMetricsResponse/ListMetricsResult") do
        CW::Spec.metric_client(server).list_metrics
      end
    end
  end

  it "works with a factory that reuses connections" do
    CW::Spec.with_fake_server do |server|
      factory = CW::Spec::SingleConnectionFactory.new
      client = CW::Spec.metric_client(server, client_factory: factory)
      server.reply(CW::Spec.fixture("list_metrics"))
      server.reply(CW::Spec.fixture("list_metrics"))
      client.list_metrics
      client.list_metrics
      server.requests.size.should eq 2
      factory.acquired.should eq 2
      factory.released.should eq 2
    end
  end

  it "serves concurrent requests" do
    CW::Spec.with_fake_server do |server|
      client = CW::Spec.metric_client(server)
      results = Channel(Exception?).new
      20.times do |i|
        spawn do
          client.put_counter("MyApp", "Requests", i)
          results.send(nil)
        rescue ex
          results.send(ex)
        end
      end
      20.times { results.receive.should be_nil }
      server.requests.map(&.params["MetricData.member.1.Value"]).sort!.should eq (0...20).map(&.to_f64.to_s).sort!
    end
  end
end

describe CW::Exception do
  it "knows which errors are transient" do
    CW::Exception.new("x", HTTP::Status::BAD_REQUEST, "Throttling").retryable?.should be_true
    CW::Exception.new("x", HTTP::Status::BAD_REQUEST, "ThrottlingException").retryable?.should be_true
    CW::Exception.new("x", HTTP::Status::TOO_MANY_REQUESTS).retryable?.should be_true
    CW::Exception.new("x", HTTP::Status::SERVICE_UNAVAILABLE).retryable?.should be_true
    CW::Exception.new("x", HTTP::Status::BAD_REQUEST, "InvalidParameterValue").retryable?.should be_false
    CW::Exception.new("x", HTTP::Status::FORBIDDEN, "InvalidClientTokenId").retryable?.should be_false
  end
end

describe CW::BaseClient do
  it "derives the regional endpoint" do
    CW::MetricClient.new("eu-west-1", "key", "secret").endpoint.to_s.should eq "https://monitoring.eu-west-1.amazonaws.com"
    CW::AlarmClient.new("us-east-1", "key", "secret", endpoint: "http://localhost:4566").endpoint.to_s.should eq "http://localhost:4566"
  end

  it "rejects endpoints that are not URLs" do
    {"localhost:4566", "monitoring.us-east-1.amazonaws.com", "http://", "ftp://x"}.each do |endpoint|
      expect_raises(ArgumentError, "endpoint must be a URL") { CW::MetricClient.new("us-east-1", "key", "secret", endpoint: endpoint) }
    end
  end
end

describe CW::Params do
  it "serializes scalars, lists and pairs" do
    params = CW::Params.new("Test")
      .add("String", "a b")
      .add("Int", 60)
      .add("Float", 1.5)
      .add("Bool", false)
      .add("Time", Time.utc(2026, 9, 15, 12, 30, 45))
      .add("Skipped", nil)
      .add_list("List", ["x", "y"])
      .add_list("Floats", [1.0, 2.0])
      .add_list("NoList", nil)
      .add_pairs("Dimensions", {"Env" => "prod"})
      .add_pairs("Tags", {"team" => "core"}, {"Key", "Value"})

    params.to_h.should eq({
      "Action"                    => "Test",
      "Version"                   => "2010-08-01",
      "String"                    => "a b",
      "Int"                       => "60",
      "Float"                     => "1.5",
      "Bool"                      => "false",
      "Time"                      => "2026-09-15T12:30:45Z",
      "List.member.1"             => "x",
      "List.member.2"             => "y",
      "Floats.member.1"           => "1.0",
      "Floats.member.2"           => "2.0",
      "Dimensions.member.1.Name"  => "Env",
      "Dimensions.member.1.Value" => "prod",
      "Tags.member.1.Key"         => "team",
      "Tags.member.1.Value"       => "core",
    })
  end

  it "sends times as UTC" do
    berlin = Time.utc(2026, 9, 15, 12, 30, 45).in(Time::Location.load("Europe/Berlin"))
    CW::Params.new("Test").add("Time", berlin).to_h["Time"].should eq "2026-09-15T12:30:45Z"
  end
end
