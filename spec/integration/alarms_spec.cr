require "../spec_helper"

# Runs against real AWS. See spec_helper.cr for the environment variables.
if CW::Spec.integration?
  describe "AlarmClient (integration)" do
    client = CW::Spec.integration_client.alarms
    prefix = CW::Spec.test_prefix
    alarm_name = "#{prefix}-alarm-#{Time.utc.to_unix}"
    composite_name = "#{prefix}-composite-#{Time.utc.to_unix}"

    it "manages metric and composite alarms" do
      begin
        client.put_metric_alarm(alarm_name,
          namespace: prefix, metric_name: "Requests", dimensions: {"Env" => "test"}, statistic: "Sum", period: 60, unit: "Count",
          evaluation_periods: 2, datapoints_to_alarm: 1, threshold: 100.5, comparison_operator: "GreaterThanThreshold",
          treat_missing_data: "notBreaching", actions_enabled: false,
          alarm_description: "created by awscr-cloudwatch specs", tags: {"team" => "awscr"})

        alarm = client.describe_alarms(alarm_names: [alarm_name]).metric_alarms.first
        alarm.alarm_name.should eq alarm_name
        alarm.alarm_description.should eq "created by awscr-cloudwatch specs"

        # Descriptions may contain anything; tags and names are ASCII only.
        description = "Ünïcödé ✓ <tag> & \"quote\"\nsecond line\ttab"
        client.put_metric_alarm(alarm_name, alarm_description: description,
          namespace: prefix, metric_name: "Requests", statistic: "Sum", period: 60, actions_enabled: false,
          evaluation_periods: 2, threshold: 100.5, comparison_operator: "GreaterThanThreshold", dimensions: {"Env" => "test"})
        client.describe_alarms(alarm_names: [alarm_name]).metric_alarms.first.alarm_description.should eq description
        client.put_metric_alarm(alarm_name, alarm_description: "created by awscr-cloudwatch specs",
          namespace: prefix, metric_name: "Requests", statistic: "Sum", period: 60, unit: "Count", actions_enabled: false,
          evaluation_periods: 2, datapoints_to_alarm: 1, threshold: 100.5, comparison_operator: "GreaterThanThreshold",
          dimensions: {"Env" => "test"}, treat_missing_data: "notBreaching")
        alarm.namespace.should eq prefix
        alarm.dimensions.should eq({"Env" => "test"})
        alarm.statistic.should eq "Sum"
        alarm.period.should eq 60
        alarm.evaluation_periods.should eq 2
        alarm.datapoints_to_alarm.should eq 1
        alarm.threshold.should eq 100.5
        alarm.treat_missing_data.should eq "notBreaching"
        alarm.actions_enabled.should be_false
        alarm.state_value.should eq "INSUFFICIENT_DATA"

        client.list_tags_for_resource(alarm.alarm_arn).tags.should eq({"team" => "awscr"})
        client.tag_resource(alarm.alarm_arn, {"owner" => "specs"})
        client.list_tags_for_resource(alarm.alarm_arn).tags.should eq({"team" => "awscr", "owner" => "specs"})
        client.untag_resource(alarm.alarm_arn, ["owner"])
        client.list_tags_for_resource(alarm.alarm_arn).tags.should eq({"team" => "awscr"})

        client.describe_alarms_for_metric(prefix, "Requests", dimensions: {"Env" => "test"}).metric_alarms.map(&.alarm_name).should contain(alarm_name)
        client.describe_alarms(alarm_name_prefix: prefix).metric_alarms.map(&.alarm_name).should contain(alarm_name)

        client.set_alarm_state(alarm_name, "ALARM", "spec", %({"spec":true}))
        history = client.describe_alarm_history(alarm_name: alarm_name, history_item_type: "StateUpdate")
        history.alarm_history_items.first.history_summary.should eq "Alarm updated from INSUFFICIENT_DATA to ALARM"

        client.enable_alarm_actions([alarm_name])
        client.describe_alarms(alarm_names: [alarm_name]).metric_alarms.first.actions_enabled.should be_true
        client.disable_alarm_actions([alarm_name])
        client.describe_alarms(alarm_names: [alarm_name]).metric_alarms.first.actions_enabled.should be_false

        client.put_composite_alarm(composite_name, %(ALARM("#{alarm_name}")), actions_enabled: false)
        composite = client.describe_alarms(alarm_names: [composite_name], alarm_types: ["CompositeAlarm"]).composite_alarms.first
        composite.alarm_rule.should eq %(ALARM("#{alarm_name}"))
        composite.actions_enabled.should be_false
        client.describe_alarms(children_of_alarm_name: composite_name).metric_alarms.map(&.alarm_name).should eq [alarm_name]
      ensure
        client.delete_alarms([composite_name])
        client.delete_alarms([alarm_name])
      end

      remaining = client.describe_alarms(alarm_names: [alarm_name, composite_name], alarm_types: ["MetricAlarm", "CompositeAlarm"])
      remaining.metric_alarms.should be_empty
      remaining.composite_alarms.should be_empty
    end

    it "manages metric math alarms and pages through results" do
      run_prefix = "#{prefix}-math-#{Time.utc.to_unix}"
      names = ["#{run_prefix}-rate", "#{run_prefix}-simple"]
      begin
        client.put_metric_alarm(names[0], actions_enabled: false,
          evaluation_periods: 1, threshold: 0.5, comparison_operator: "GreaterThanThreshold",
          metrics: [
            CW::MetricDataQuery.new("errors", return_data: false,
              metric_stat: CW::MetricStat.new(CW::Metric.new(prefix, "Errors", {"Env" => "test"}), 60, "Sum", unit: "Count")),
            CW::MetricDataQuery.new("requests", return_data: false,
              metric_stat: CW::MetricStat.new(CW::Metric.new(prefix, "Requests"), 60, "Sum")),
            CW::MetricDataQuery.new("rate", expression: "errors / requests", label: "Error rate", return_data: true),
          ])
        client.put_metric_alarm(names[1], actions_enabled: false,
          namespace: prefix, metric_name: "Requests", statistic: "Sum", period: 60,
          evaluation_periods: 1, threshold: 1, comparison_operator: "GreaterThanThreshold")

        alarm = client.describe_alarms(alarm_names: [names[0]]).metric_alarms.first
        alarm.metric_name.should be_nil
        alarm.metrics.map(&.id).should eq ["errors", "requests", "rate"]
        alarm.metrics[0].metric_stat.should eq CW::MetricStat.new(CW::Metric.new(prefix, "Errors", {"Env" => "test"}), 60, "Sum", unit: "Count")
        alarm.metrics[2].expression.should eq "errors / requests"
        alarm.metrics[2].label.should eq "Error rate"
        alarm.metrics[2].return_data.should be_true

        page = client.describe_alarms(alarm_name_prefix: run_prefix, max_records: 1)
        page.metric_alarms.size.should eq 1
        token = page.next_token.should_not be_nil
        rest = client.describe_alarms(alarm_name_prefix: run_prefix, max_records: 1, next_token: token)
        (page.metric_alarms + rest.metric_alarms).map(&.alarm_name).sort!.should eq names
      ensure
        client.delete_alarms(names)
      end
    end
  end
end
