require "./metrics/client"
require "./metrics/streams"
require "./alarms/client"
require "./alarms/insight_rules"

module Awscr::CloudWatch
  # Entry point that bundles a `MetricClient` and an `AlarmClient`.
  #
  # ```
  # client = Client.new("us-east-1", "key", "secret")
  # client.metrics.put_counter("MyApp", "Requests")
  # client.alarms.describe_alarms(alarm_name_prefix: "MyApp")
  # ```
  #
  # Temporary credentials need the session token:
  #
  # ```
  # client = Client.new("us-east-1", "key", "secret", "session_token")
  # ```
  #
  # A custom *endpoint* targets a local mock such as Ministack:
  #
  # ```
  # client = Client.new("us-east-1", "key", "secret", endpoint: "http://localhost:4566")
  # ```
  class Client
    getter metrics : MetricClient
    getter alarms : AlarmClient

    def initialize(
      region : String,
      aws_access_key : String,
      aws_secret_key : String,
      aws_session_key : String? = nil,
      endpoint : String? = nil,
      client_factory : HttpClientFactory = DefaultHttpClientFactory.new,
      max_attempts : Int32 = 3,
    )
      @metrics = MetricClient.new(region, aws_access_key, aws_secret_key, aws_session_key, endpoint, client_factory, max_attempts)
      @alarms = AlarmClient.new(region, aws_access_key, aws_secret_key, aws_session_key, endpoint, client_factory, max_attempts)
    end
  end
end
