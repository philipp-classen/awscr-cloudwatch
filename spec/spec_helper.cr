require "spec"
require "../src/awscr-cloudwatch"
require "./support/fake_cloudwatch"

alias CW = Awscr::CloudWatch

module Awscr::CloudWatch::Spec
  def self.fixture(name : String) : String
    File.read(File.join(__DIR__, "fixtures", "#{name}.xml"))
  end

  # The parameters every request carries, plus *extra*.
  def self.params(action : String, extra = {} of String => String) : Hash(String, String)
    {"Action" => action, "Version" => API_VERSION}.merge(extra)
  end

  def self.with_fake_server(& : FakeCloudWatch ->)
    server = FakeCloudWatch.new
    begin
      yield server
    ensure
      server.close
    end
  end

  def self.metric_client(server : FakeCloudWatch, aws_session_key : String? = nil, max_attempts : Int32 = 3,
                         client_factory : HttpClientFactory = DefaultHttpClientFactory.new) : MetricClient
    MetricClient.new("us-east-1", "key", "secret", aws_session_key,
      endpoint: server.endpoint, client_factory: client_factory, max_attempts: max_attempts)
  end

  def self.alarm_client(server : FakeCloudWatch) : AlarmClient
    AlarmClient.new("us-east-1", "key", "secret", endpoint: server.endpoint)
  end

  # Integration specs run against real AWS (or a mock via AWS_ENDPOINT_URL)
  # when AWSCR_CLOUDWATCH_INTEGRATION=1. Everything they create is prefixed
  # with AWSCR_CLOUDWATCH_TEST_PREFIX so leftovers are easy to find.
  def self.integration? : Bool
    ENV["AWSCR_CLOUDWATCH_INTEGRATION"]? == "1"
  end

  def self.test_prefix : String
    ENV.fetch("AWSCR_CLOUDWATCH_TEST_PREFIX", "awscr-cloudwatch-spec")
  end

  def self.integration_client : Client
    Client.new(
      ENV.fetch("AWS_REGION", "us-east-1"),
      ENV["AWS_ACCESS_KEY_ID"],
      ENV["AWS_SECRET_ACCESS_KEY"],
      ENV["AWS_SESSION_TOKEN"]?,
      endpoint: ENV["AWS_ENDPOINT_URL"]?
    )
  end

  # Metric data becomes queryable a few seconds after publishing.
  def self.eventually(timeout : Time::Span = 2.minutes, & : -> Bool) : Nil
    deadline = Time.monotonic + timeout
    until yield
      raise "condition not met within #{timeout}" if Time.monotonic > deadline
      sleep 3.seconds
    end
  end
end
