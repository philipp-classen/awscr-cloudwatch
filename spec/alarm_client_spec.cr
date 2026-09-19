require "./spec_helper"

private def with_alarm_client(&)
  CW::Spec.with_fake_server do |server|
    yield CW::Spec.alarm_client(server), server
  end
end

describe CW::AlarmClient do
  describe "#put_metric_alarm" do
    it "serializes an alarm on a single metric" do
      with_alarm_client do |client, server|
        client.put_metric_alarm("HighErrors",
          namespace: "MyApp", metric_name: "Errors", statistic: "Sum", period: 60, unit: "Count",
          dimensions: {"Env" => "prod"}, evaluation_periods: 3, datapoints_to_alarm: 2,
          threshold: 100, comparison_operator: "GreaterThanThreshold", treat_missing_data: "notBreaching",
          alarm_description: "too many errors", actions_enabled: true,
          alarm_actions: ["arn:alarm"], ok_actions: ["arn:ok"], insufficient_data_actions: ["arn:insufficient"],
          tags: {"team" => "core"})

        server.last_request.params.should eq CW::Spec.params("PutMetricAlarm", {
          "AlarmName"                        => "HighErrors",
          "ComparisonOperator"               => "GreaterThanThreshold",
          "EvaluationPeriods"                => "3",
          "Threshold"                        => "100",
          "Namespace"                        => "MyApp",
          "MetricName"                       => "Errors",
          "Statistic"                        => "Sum",
          "Period"                           => "60",
          "Dimensions.member.1.Name"         => "Env",
          "Dimensions.member.1.Value"        => "prod",
          "Unit"                             => "Count",
          "DatapointsToAlarm"                => "2",
          "TreatMissingData"                 => "notBreaching",
          "AlarmDescription"                 => "too many errors",
          "ActionsEnabled"                   => "true",
          "AlarmActions.member.1"            => "arn:alarm",
          "OKActions.member.1"               => "arn:ok",
          "InsufficientDataActions.member.1" => "arn:insufficient",
          "Tags.member.1.Key"                => "team",
          "Tags.member.1.Value"              => "core",
        })
      end
    end

    it "serializes a metric math alarm" do
      with_alarm_client do |client, server|
        client.put_metric_alarm("ErrorRate",
          metrics: [
            CW::MetricDataQuery.new("errors", metric_stat: CW::MetricStat.new(CW::Metric.new("MyApp", "Errors"), 60, "Sum"), return_data: false),
            CW::MetricDataQuery.new("rate", expression: "errors / 100", return_data: true),
          ],
          evaluation_periods: 1, threshold: 0.5, comparison_operator: "GreaterThanThreshold")

        server.last_request.params.should eq CW::Spec.params("PutMetricAlarm", {
          "AlarmName"                                     => "ErrorRate",
          "ComparisonOperator"                            => "GreaterThanThreshold",
          "EvaluationPeriods"                             => "1",
          "Threshold"                                     => "0.5",
          "Metrics.member.1.Id"                           => "errors",
          "Metrics.member.1.ReturnData"                   => "false",
          "Metrics.member.1.MetricStat.Metric.Namespace"  => "MyApp",
          "Metrics.member.1.MetricStat.Metric.MetricName" => "Errors",
          "Metrics.member.1.MetricStat.Period"            => "60",
          "Metrics.member.1.MetricStat.Stat"              => "Sum",
          "Metrics.member.2.Id"                           => "rate",
          "Metrics.member.2.Expression"                   => "errors / 100",
          "Metrics.member.2.ReturnData"                   => "true",
        })
      end
    end
  end

  describe "#put_composite_alarm" do
    it "serializes the rule and actions" do
      with_alarm_client do |client, server|
        client.put_composite_alarm("Outage", %(ALARM("HighErrors") AND ALARM("HighLatency")),
          alarm_description: "both", actions_enabled: false, alarm_actions: ["arn:alarm"], tags: {"team" => "core"})

        server.last_request.params.should eq CW::Spec.params("PutCompositeAlarm", {
          "AlarmName"             => "Outage",
          "AlarmRule"             => %(ALARM("HighErrors") AND ALARM("HighLatency")),
          "AlarmDescription"      => "both",
          "ActionsEnabled"        => "false",
          "AlarmActions.member.1" => "arn:alarm",
          "Tags.member.1.Key"     => "team",
          "Tags.member.1.Value"   => "core",
        })
      end
    end
  end

  describe "#describe_alarms" do
    it "sends filters and parses metric alarms" do
      with_alarm_client do |client, server|
        server.reply(CW::Spec.fixture("describe_alarms"))
        result = client.describe_alarms(alarm_names: ["a", "b"], alarm_name_prefix: "p", alarm_types: ["MetricAlarm"],
          state_value: "ALARM", action_prefix: "arn", children_of_alarm_name: "c", parents_of_alarm_name: "d",
          max_records: 10, next_token: "t")

        server.last_request.params.should eq CW::Spec.params("DescribeAlarms", {
          "AlarmNames.member.1" => "a",
          "AlarmNames.member.2" => "b",
          "AlarmNamePrefix"     => "p",
          "AlarmTypes.member.1" => "MetricAlarm",
          "StateValue"          => "ALARM",
          "ActionPrefix"        => "arn",
          "ChildrenOfAlarmName" => "c",
          "ParentsOfAlarmName"  => "d",
          "MaxRecords"          => "10",
          "NextToken"           => "t",
        })
        result.metric_alarms.size.should eq 1
        result.composite_alarms.should be_empty
        result.next_token.should be_nil

        alarm = result.metric_alarms.first
        alarm.alarm_name.should eq "test-awscr-20260915-alarm"
        alarm.alarm_arn.should eq "arn:aws:cloudwatch:us-east-1:123456789012:alarm:test-awscr-20260915-alarm"
        alarm.alarm_description.should eq "test alarm"
        alarm.alarm_configuration_updated_timestamp.should eq Time.utc(2026, 9, 15, 19, 0, 36, nanosecond: 329_000_000)
        alarm.actions_enabled.should be_false
        alarm.alarm_actions.should be_empty
        alarm.ok_actions.should be_empty
        alarm.insufficient_data_actions.should be_empty
        alarm.state_value.should eq "ALARM"
        alarm.state_reason.should eq "testing"
        alarm.state_reason_data.should eq %({"k":1})
        alarm.state_updated_timestamp.should eq Time.utc(2026, 9, 15, 19, 0, 37, nanosecond: 543_000_000)
        alarm.state_transitioned_timestamp.should eq Time.utc(2026, 9, 15, 19, 0, 37, nanosecond: 543_000_000)
        alarm.namespace.should eq "test-awscr-20260915"
        alarm.metric_name.should eq "Requests"
        alarm.statistic.should eq "Sum"
        alarm.extended_statistic.should be_nil
        alarm.dimensions.should eq({"Env" => "test"})
        alarm.period.should eq 60
        alarm.unit.should eq "Count"
        alarm.evaluation_periods.should eq 2
        alarm.datapoints_to_alarm.should eq 1
        alarm.threshold.should eq 100.5
        alarm.comparison_operator.should eq "GreaterThanThreshold"
        alarm.treat_missing_data.should eq "notBreaching"
        alarm.evaluate_low_sample_count_percentile.should be_nil
        alarm.metrics.should be_empty
        alarm.threshold_metric_id.should be_nil
      end
    end

    it "parses composite alarms" do
      with_alarm_client do |client, server|
        server.reply(CW::Spec.fixture("describe_composite_alarms"))
        result = client.describe_alarms(alarm_types: ["CompositeAlarm"])

        result.metric_alarms.should be_empty
        alarm = result.composite_alarms.first
        alarm.alarm_name.should eq "test-awscr-20260915-composite"
        alarm.alarm_arn.should eq "arn:aws:cloudwatch:us-east-1:123456789012:alarm:test-awscr-20260915-composite"
        alarm.alarm_rule.should eq %(ALARM("test-awscr-20260915-alarm"))
        alarm.alarm_description.should eq "composite test"
        alarm.actions_enabled.should be_false
        alarm.state_value.should eq "OK"
        alarm.state_reason_data.to_s.should start_with %({"triggeringAlarms")
        alarm.state_updated_timestamp.should eq Time.utc(2026, 9, 15, 19, 14, 14, nanosecond: 15_000_000)
      end
    end

    it "parses metric math alarms" do
      with_alarm_client do |client, server|
        server.reply(CW::Spec.fixture("describe_math_alarm"))
        alarm = client.describe_alarms(alarm_names: ["test-awscr-20260915-math"]).metric_alarms.first

        alarm.metric_name.should be_nil
        alarm.dimensions.should be_empty
        alarm.threshold.should eq 0.5
        alarm.metrics.size.should eq 3

        errors = alarm.metrics[0]
        errors.id.should eq "errors"
        errors.return_data.should be_false
        errors.expression.should be_nil
        stat = errors.metric_stat.should_not be_nil
        stat.metric.should eq CW::Metric.new("test-awscr-20260915", "Errors", {"Env" => "test"})
        stat.period.should eq 60
        stat.stat.should eq "Sum"
        stat.unit.should eq "Count"

        requests = alarm.metrics[1]
        requests.metric_stat.should eq CW::MetricStat.new(CW::Metric.new("test-awscr-20260915", "Requests"), 60, "Sum")

        rate = alarm.metrics[2]
        rate.metric_stat.should be_nil
        rate.expression.should eq "errors / requests"
        rate.label.should eq "Error rate"
        rate.return_data.should be_true
      end
    end

    it "returns the token of the next page" do
      with_alarm_client do |client, server|
        server.reply(CW::Spec.fixture("describe_alarms_page"))
        result = client.describe_alarms(alarm_name_prefix: "test-awscr-20260915", max_records: 1)
        result.metric_alarms.map(&.alarm_name).should eq ["test-awscr-20260915-math"]
        result.next_token.should eq "test-awscr-20260915-second"
      end
    end

    it "handles an empty result" do
      with_alarm_client do |client, server|
        server.reply(CW::Spec.fixture("describe_alarms_empty"))
        result = client.describe_alarms
        server.last_request.params.should eq CW::Spec.params("DescribeAlarms")
        result.metric_alarms.should be_empty
        result.composite_alarms.should be_empty
      end
    end
  end

  describe "#describe_alarms_for_metric" do
    it "returns the alarms of a metric" do
      with_alarm_client do |client, server|
        server.reply(CW::Spec.fixture("describe_alarms_for_metric"))
        result = client.describe_alarms_for_metric("MyApp", "Requests", statistic: "Sum", extended_statistic: "p99",
          dimensions: {"Env" => "test"}, period: 60, unit: "Count")

        server.last_request.params.should eq CW::Spec.params("DescribeAlarmsForMetric", {
          "Namespace"                 => "MyApp",
          "MetricName"                => "Requests",
          "Statistic"                 => "Sum",
          "ExtendedStatistic"         => "p99",
          "Dimensions.member.1.Name"  => "Env",
          "Dimensions.member.1.Value" => "test",
          "Period"                    => "60",
          "Unit"                      => "Count",
        })
        result.metric_alarms.map(&.alarm_name).should eq ["test-awscr-20260915-alarm"]
        result.request_id.should eq "38721bdb-6b8c-4816-968a-d159c1c15c88"
      end
    end
  end

  describe "#describe_alarm_history" do
    it "sends filters and parses history items" do
      with_alarm_client do |client, server|
        server.reply(CW::Spec.fixture("describe_alarm_history"))
        result = client.describe_alarm_history(alarm_name: "a", alarm_types: ["MetricAlarm"], history_item_type: "StateUpdate",
          start_date: Time.utc(2026, 9, 15), end_date: Time.utc(2026, 9, 16), scan_by: "TimestampAscending",
          max_records: 5, next_token: "t")

        server.last_request.params.should eq CW::Spec.params("DescribeAlarmHistory", {
          "AlarmName"           => "a",
          "AlarmTypes.member.1" => "MetricAlarm",
          "HistoryItemType"     => "StateUpdate",
          "StartDate"           => "2026-09-15T00:00:00Z",
          "EndDate"             => "2026-09-16T00:00:00Z",
          "ScanBy"              => "TimestampAscending",
          "MaxRecords"          => "5",
          "NextToken"           => "t",
        })
        result.alarm_history_items.size.should eq 2
        result.next_token.should be_nil

        item = result.alarm_history_items.first
        item.alarm_name.should eq "test-awscr-20260915-alarm"
        item.alarm_type.should eq "MetricAlarm"
        item.history_item_type.should eq "StateUpdate"
        item.history_summary.should eq "Alarm updated from INSUFFICIENT_DATA to ALARM"
        item.history_data.to_s.should start_with %({"version":"1.0","oldState")
        item.timestamp.should eq Time.utc(2026, 9, 15, 19, 0, 37, nanosecond: 543_000_000)
        result.alarm_history_items[1].history_item_type.should eq "ConfigurationUpdate"
      end
    end
  end

  describe "state and actions" do
    it "serializes the requests" do
      with_alarm_client do |client, server|
        client.set_alarm_state("a", "ALARM", "testing", %({"k":1}))
        server.last_request.params.should eq CW::Spec.params("SetAlarmState", {
          "AlarmName"       => "a",
          "StateValue"      => "ALARM",
          "StateReason"     => "testing",
          "StateReasonData" => %({"k":1}),
        })

        client.delete_alarms(["a", "b"])
        server.last_request.params.should eq CW::Spec.params("DeleteAlarms", {"AlarmNames.member.1" => "a", "AlarmNames.member.2" => "b"})

        client.enable_alarm_actions(["a"])
        server.last_request.params.should eq CW::Spec.params("EnableAlarmActions", {"AlarmNames.member.1" => "a"})

        client.disable_alarm_actions(["a"])
        server.last_request.params.should eq CW::Spec.params("DisableAlarmActions", {"AlarmNames.member.1" => "a"})
      end
    end
  end

  describe "tags" do
    it "tags, untags and lists" do
      with_alarm_client do |client, server|
        client.tag_resource("arn:alarm", {"team" => "core", "env" => "test"})
        server.last_request.params.should eq CW::Spec.params("TagResource", {
          "ResourceARN"         => "arn:alarm",
          "Tags.member.1.Key"   => "team",
          "Tags.member.1.Value" => "core",
          "Tags.member.2.Key"   => "env",
          "Tags.member.2.Value" => "test",
        })

        client.untag_resource("arn:alarm", ["env"])
        server.last_request.params.should eq CW::Spec.params("UntagResource", {"ResourceARN" => "arn:alarm", "TagKeys.member.1" => "env"})

        server.reply(CW::Spec.fixture("list_tags_for_resource"))
        client.list_tags_for_resource("arn:alarm").tags.should eq({"env" => "test", "team" => "core"})
        server.last_request.params.should eq CW::Spec.params("ListTagsForResource", {"ResourceARN" => "arn:alarm"})
      end
    end
  end

  describe "insight rules" do
    it "serializes the requests" do
      with_alarm_client do |client, server|
        client.put_insight_rule("TopTalkers", %({"Schema":{"Name":"CloudWatchLogRule","Version":1}}), tags: {"team" => "core"})
        server.last_request.params.should eq CW::Spec.params("PutInsightRule", {
          "RuleName"            => "TopTalkers",
          "RuleDefinition"      => %({"Schema":{"Name":"CloudWatchLogRule","Version":1}}),
          "RuleState"           => "ENABLED",
          "Tags.member.1.Key"   => "team",
          "Tags.member.1.Value" => "core",
        })

        server.reply(CW::Spec.fixture("describe_insight_rules"))
        client.describe_insight_rules(max_results: 10).insight_rules.should be_empty
        server.last_request.params.should eq CW::Spec.params("DescribeInsightRules", {"MaxResults" => "10"})

        client.delete_insight_rules(["TopTalkers"])
        server.last_request.params.should eq CW::Spec.params("DeleteInsightRules", {"RuleNames.member.1" => "TopTalkers"})
      end
    end
  end
end
