require "./spec_helper"

describe CW::Period do
  it "accepts the periods CloudWatch accepts" do
    [1.second, 5.seconds, 10.seconds, 20.seconds, 30.seconds, 1.minute, 5.minutes, 90.minutes, 1.hour, 1.day].each do |period|
      CW::Period.valid?(period).should be_true
      CW::Period.validate(period)
    end
    CW::Period.validate(nil)
  end

  it "rejects every other period" do
    [0.seconds, -1.minute, 2.seconds, 15.seconds, 45.seconds, 61.seconds, 90.seconds, 1.5.seconds, 3599.seconds].each do |period|
      CW::Period.valid?(period).should be_false
      expect_raises(ArgumentError, /multiple of 60 seconds/) { CW::Period.validate(period) }
    end
  end

  it "serializes as whole seconds" do
    CW::Period.seconds(5.minutes).should eq 300
    CW::Period.seconds(10.seconds).should eq 10
    CW::Period.seconds(nil).should be_nil
    expect_raises(ArgumentError) { CW::Period.seconds(1.5.seconds) }
  end

  it "is checked wherever a period enters the library, before a request is sent" do
    metric = CW::Metric.new("MyApp", "Requests")
    expect_raises(ArgumentError) { CW::MetricStat.new(metric, 15.seconds, "Sum") }
    expect_raises(ArgumentError) { CW::MetricDataQuery.new("e1", expression: "m1 * 2", period: 15.seconds) }

    CW::Spec.with_fake_server do |server|
      now = Time.utc
      metrics = CW::Spec.metric_client(server)
      alarms = CW::Spec.alarm_client(server)
      expect_raises(ArgumentError) { metrics.get_metric_statistics("MyApp", "Requests", start_time: now - 1.hour, end_time: now, period: 15.seconds) }
      expect_raises(ArgumentError) do
        alarms.put_metric_alarm("HighErrorRate", namespace: "MyApp", metric_name: "Requests", statistic: "Sum", period: 15.seconds,
          evaluation_periods: 1, threshold: 1, comparison_operator: "GreaterThanThreshold")
      end
      expect_raises(ArgumentError) { alarms.describe_alarms_for_metric("MyApp", "Requests", period: 15.seconds) }
      server.requests.should be_empty
    end
  end
end
