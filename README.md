# awscr-cloudwatch

A low-level Crystal client for AWS CloudWatch:

1. Metrics: publish counters and other data points, query statistics
2. Alarms: create, inspect and delete metric and composite alarms

Dashboards, anomaly detectors, tags, metric streams and Contributor Insights
rules are covered as well, but with less testing (see "Status").

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     awscr-cloudwatch:
       github: philipp-classen/awscr-cloudwatch
   ```

2. Run `shards install`

## Usage

```crystal
require "awscr-cloudwatch"

client = Awscr::CloudWatch::Client.new("us-east-1", "key", "secret")
# With temporary credentials: Client.new("us-east-1", "key", "secret", "session_token")
```

### Publishing metrics

```crystal
metrics = client.metrics

# One counter increment
metrics.put_counter("MyApp", "Requests", dimensions: {"Env" => "prod"})

# Several data points in one request (up to 1000 metrics / 1 MB)
metrics.put_metric_data("MyApp", [
  Awscr::CloudWatch::MetricDatum.counter("Requests", 42, {"Env" => "prod"}),
  Awscr::CloudWatch::MetricDatum.new("Latency", values: [1.5, 2.5], counts: [20.0, 1.0], unit: "Milliseconds"),
  Awscr::CloudWatch::MetricDatum.new("BatchSize", unit: "Count",
    statistic_values: Awscr::CloudWatch::StatisticSet.new(sample_count: 4, sum: 10, minimum: 1, maximum: 4)),
])
```

Metric names, namespaces and dimensions must be ASCII. Calls return `nil` on
success and raise `Awscr::CloudWatch::Exception` when AWS rejects the request. The exception carries the AWS error `code` (for example
`InvalidParameterValue`), the `request_id` and the HTTP `status`. Throttling,
5xx responses and connection errors are retried with exponential backoff
(`max_attempts: 3` by default). CloudWatch has no idempotency token, so a
retry after a timeout can store a data point twice; every SDK shares that
property.

### Querying metrics

```crystal
stats = metrics.get_metric_statistics("MyApp", "Requests",
  start_time: Time.utc - 1.hour, end_time: Time.utc, period: 300,
  statistics: ["Sum"], dimensions: {"Env" => "prod"})
stats.datapoints.each { |dp| puts "#{dp.timestamp}: #{dp.sum}" }

data = metrics.get_metric_data([
  Awscr::CloudWatch::MetricDataQuery.new("requests",
    metric_stat: Awscr::CloudWatch::MetricStat.new(Awscr::CloudWatch::Metric.new("MyApp", "Requests"), 300, "Sum")),
  Awscr::CloudWatch::MetricDataQuery.new("per_second", expression: "requests / 300"),
], start_time: Time.utc - 1.hour, end_time: Time.utc)
data.metric_data_results.each { |r| puts "#{r.id}: #{r.values}" }

metrics.list_metrics(namespace: "MyApp").metrics.each { |m| puts m.metric_name }
```

### Alarms

```crystal
alarms = client.alarms

alarms.put_metric_alarm("MyApp-HighErrorRate",
  namespace: "MyApp", metric_name: "Errors", statistic: "Sum", period: 60,
  evaluation_periods: 3, threshold: 100, comparison_operator: "GreaterThanThreshold",
  alarm_actions: ["arn:aws:sns:us-east-1:123456789012:oncall"])

alarms.describe_alarms(alarm_name_prefix: "MyApp-").metric_alarms.each do |alarm|
  puts "#{alarm.alarm_name}: #{alarm.state_value}"
end

alarms.delete_alarms(["MyApp-HighErrorRate"])
```

`MetricClient` and `AlarmClient` can also be used on their own; they take
the same constructor arguments as `Client`.

### Custom endpoint and HTTP clients

```crystal
# Local mock such as Ministack
client = Awscr::CloudWatch::Client.new("us-east-1", "dummy", "dummy", endpoint: "http://localhost:4566")

# Shorter timeouts (defaults: 15 s to connect, 60 s to read)
factory = Awscr::CloudWatch::DefaultHttpClientFactory.new(connect_timeout: 5.seconds, read_timeout: 10.seconds)
client = Awscr::CloudWatch::Client.new("us-east-1", "key", "secret", client_factory: factory)

# Connection pooling: subclass HttpClientFactory (acquire_client / release)
```

## Development

```
crystal spec
bin/ameba
```

The fake server verifies every SigV4 signature. The unit specs also cover
malformed HTTP, fuzzed response bodies and resource leaks.

Integration specs run against a real account (or a mock via `AWS_ENDPOINT_URL`):

```
export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... AWS_REGION=us-east-1
AWSCR_CLOUDWATCH_INTEGRATION=1 AWSCR_CLOUDWATCH_TEST_PREFIX=my-test crystal spec spec/integration
```

Be careful when running tests again a real account. Do it at your own risk only.

The tests create alarms, a dashboard and an anomaly detector under the prefix and
delete them again. Published metrics cannot be deleted (they expire after 15
months). The specs expect real AWS behaviour. Ministack passes only the basic
ones (uploads, dashboards, connection reuse).

## Contributing

1. Fork it (<https://github.com/philipp-classen/awscr-cloudwatch/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Philipp Claßen](https://github.com/philipp-classen) - creator and maintainer
