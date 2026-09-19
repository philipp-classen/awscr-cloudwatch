require "../base_client"
require "../metrics/metric_data_query"

module Awscr::CloudWatch
  # Manages alarms.
  #
  # ```
  # client = AlarmClient.new("us-east-1", "key", "secret")
  # client.put_metric_alarm("HighErrorRate",
  #   namespace: "MyApp", metric_name: "Errors", statistic: "Sum", period: 60,
  #   evaluation_periods: 3, threshold: 100, comparison_operator: "GreaterThanThreshold",
  #   alarm_actions: ["arn:aws:sns:us-east-1:123456789012:oncall"])
  # ```
  class AlarmClient < BaseClient
    # Creates or replaces an alarm. Either watch one metric (*namespace*,
    # *metric_name*, *statistic* or *extended_statistic*, *period*) or a metric
    # math expression (*metrics*, with `return_data: true` on the watched entry).
    def put_metric_alarm(alarm_name : String, *,
                         comparison_operator : String, evaluation_periods : Int32,
                         threshold : Number? = nil,
                         namespace : String? = nil, metric_name : String? = nil,
                         statistic : String? = nil, extended_statistic : String? = nil,
                         period : Int32? = nil, dimensions : Hash(String, String)? = nil,
                         unit : String? = nil, metrics : Array(MetricDataQuery)? = nil,
                         threshold_metric_id : String? = nil,
                         datapoints_to_alarm : Int32? = nil, treat_missing_data : String? = nil,
                         evaluate_low_sample_count_percentile : String? = nil,
                         alarm_description : String? = nil, actions_enabled : Bool? = nil,
                         alarm_actions : Array(String)? = nil, ok_actions : Array(String)? = nil,
                         insufficient_data_actions : Array(String)? = nil,
                         tags : Hash(String, String)? = nil) : Nil
      request Params.new("PutMetricAlarm")
        .add("AlarmName", alarm_name)
        .add("ComparisonOperator", comparison_operator)
        .add("EvaluationPeriods", evaluation_periods)
        .add("Threshold", threshold)
        .add("Namespace", namespace)
        .add("MetricName", metric_name)
        .add("Statistic", statistic)
        .add("ExtendedStatistic", extended_statistic)
        .add("Period", period)
        .add_pairs("Dimensions", dimensions)
        .add("Unit", unit)
        .add_structs("Metrics", metrics)
        .add("ThresholdMetricId", threshold_metric_id)
        .add("DatapointsToAlarm", datapoints_to_alarm)
        .add("TreatMissingData", treat_missing_data)
        .add("EvaluateLowSampleCountPercentile", evaluate_low_sample_count_percentile)
        .add("AlarmDescription", alarm_description)
        .add("ActionsEnabled", actions_enabled)
        .add_list("AlarmActions", alarm_actions)
        .add_list("OKActions", ok_actions)
        .add_list("InsufficientDataActions", insufficient_data_actions)
        .add_pairs("Tags", tags, {"Key", "Value"})
    end

    # Creates or replaces a composite alarm. *alarm_rule* combines other
    # alarms, e.g. `ALARM("cpu-high") AND ALARM("errors-high")`.
    def put_composite_alarm(alarm_name : String, alarm_rule : String, *,
                            alarm_description : String? = nil, actions_enabled : Bool? = nil,
                            alarm_actions : Array(String)? = nil, ok_actions : Array(String)? = nil,
                            insufficient_data_actions : Array(String)? = nil,
                            tags : Hash(String, String)? = nil) : Nil
      request Params.new("PutCompositeAlarm")
        .add("AlarmName", alarm_name)
        .add("AlarmRule", alarm_rule)
        .add("AlarmDescription", alarm_description)
        .add("ActionsEnabled", actions_enabled)
        .add_list("AlarmActions", alarm_actions)
        .add_list("OKActions", ok_actions)
        .add_list("InsufficientDataActions", insufficient_data_actions)
        .add_pairs("Tags", tags, {"Key", "Value"})
    end

    # Lists alarms, 100 per page. Only metric alarms are returned unless
    # *alarm_types* includes `CompositeAlarm`.
    def describe_alarms(alarm_names : Array(String)? = nil, alarm_name_prefix : String? = nil,
                        alarm_types : Array(String)? = nil, state_value : String? = nil,
                        action_prefix : String? = nil, children_of_alarm_name : String? = nil,
                        parents_of_alarm_name : String? = nil, max_records : Int32? = nil,
                        next_token : String? = nil) : Response::DescribeAlarmsOutput
      query Response::DescribeAlarmsOutput, Params.new("DescribeAlarms")
        .add_list("AlarmNames", alarm_names)
        .add("AlarmNamePrefix", alarm_name_prefix)
        .add_list("AlarmTypes", alarm_types)
        .add("StateValue", state_value)
        .add("ActionPrefix", action_prefix)
        .add("ChildrenOfAlarmName", children_of_alarm_name)
        .add("ParentsOfAlarmName", parents_of_alarm_name)
        .add("MaxRecords", max_records)
        .add("NextToken", next_token)
    end

    # Alarms watching one metric.
    def describe_alarms_for_metric(namespace : String, metric_name : String, *,
                                   statistic : String? = nil, extended_statistic : String? = nil,
                                   dimensions : Hash(String, String)? = nil,
                                   period : Int32? = nil, unit : String? = nil) : Response::DescribeAlarmsForMetricOutput
      query Response::DescribeAlarmsForMetricOutput, Params.new("DescribeAlarmsForMetric")
        .add("Namespace", namespace)
        .add("MetricName", metric_name)
        .add("Statistic", statistic)
        .add("ExtendedStatistic", extended_statistic)
        .add_pairs("Dimensions", dimensions)
        .add("Period", period)
        .add("Unit", unit)
    end

    # State changes, configuration updates and actions, newest first.
    # *history_item_type* is `ConfigurationUpdate`, `StateUpdate` or `Action`.
    def describe_alarm_history(alarm_name : String? = nil, alarm_types : Array(String)? = nil,
                               history_item_type : String? = nil,
                               start_date : Time? = nil, end_date : Time? = nil,
                               scan_by : String? = nil, max_records : Int32? = nil,
                               next_token : String? = nil) : Response::DescribeAlarmHistoryOutput
      query Response::DescribeAlarmHistoryOutput, Params.new("DescribeAlarmHistory")
        .add("AlarmName", alarm_name)
        .add_list("AlarmTypes", alarm_types)
        .add("HistoryItemType", history_item_type)
        .add("StartDate", start_date)
        .add("EndDate", end_date)
        .add("ScanBy", scan_by)
        .add("MaxRecords", max_records)
        .add("NextToken", next_token)
    end

    # Deletes up to 100 alarms. Unknown names are ignored.
    def delete_alarms(alarm_names : Array(String)) : Nil
      request Params.new("DeleteAlarms").add_list("AlarmNames", alarm_names)
    end

    # Forces an alarm into `OK`, `ALARM` or `INSUFFICIENT_DATA`, e.g. to test
    # its actions. The next evaluation sets the real state again.
    def set_alarm_state(alarm_name : String, state_value : String, state_reason : String,
                        state_reason_data : String? = nil) : Nil
      request Params.new("SetAlarmState")
        .add("AlarmName", alarm_name)
        .add("StateValue", state_value)
        .add("StateReason", state_reason)
        .add("StateReasonData", state_reason_data)
    end

    def enable_alarm_actions(alarm_names : Array(String)) : Nil
      request Params.new("EnableAlarmActions").add_list("AlarmNames", alarm_names)
    end

    def disable_alarm_actions(alarm_names : Array(String)) : Nil
      request Params.new("DisableAlarmActions").add_list("AlarmNames", alarm_names)
    end
  end
end
