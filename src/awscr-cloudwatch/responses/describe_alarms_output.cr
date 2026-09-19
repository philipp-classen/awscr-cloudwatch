module Awscr::CloudWatch::Response
  # An alarm on a single metric or a metric math expression.
  record MetricAlarm,
    alarm_name : String,
    alarm_arn : String,
    alarm_description : String?,
    alarm_configuration_updated_timestamp : Time?,
    actions_enabled : Bool?,
    ok_actions : Array(String),
    alarm_actions : Array(String),
    insufficient_data_actions : Array(String),
    state_value : String?,
    state_reason : String?,
    state_reason_data : String?,
    state_updated_timestamp : Time?,
    state_transitioned_timestamp : Time?,
    metric_name : String?,
    namespace : String?,
    statistic : String?,
    extended_statistic : String?,
    dimensions : Hash(String, String),
    period : Int32?,
    unit : String?,
    evaluation_periods : Int32?,
    datapoints_to_alarm : Int32?,
    threshold : Float64?,
    comparison_operator : String?,
    treat_missing_data : String?,
    evaluate_low_sample_count_percentile : String?,
    metrics : Array(MetricDataQuery),
    threshold_metric_id : String? do
    # :nodoc:
    def self.from_xml(node) : self
      new(
        alarm_name: node.string("AlarmName"),
        alarm_arn: node.string("AlarmArn"),
        alarm_description: node.string?("AlarmDescription"),
        alarm_configuration_updated_timestamp: node.time?("AlarmConfigurationUpdatedTimestamp"),
        actions_enabled: node.bool?("ActionsEnabled"),
        ok_actions: node.map("OKActions/member", &.text),
        alarm_actions: node.map("AlarmActions/member", &.text),
        insufficient_data_actions: node.map("InsufficientDataActions/member", &.text),
        state_value: node.string?("StateValue"),
        state_reason: node.string?("StateReason"),
        state_reason_data: node.string?("StateReasonData"),
        state_updated_timestamp: node.time?("StateUpdatedTimestamp"),
        state_transitioned_timestamp: node.time?("StateTransitionedTimestamp"),
        metric_name: node.string?("MetricName"),
        namespace: node.string?("Namespace"),
        statistic: node.string?("Statistic"),
        extended_statistic: node.string?("ExtendedStatistic"),
        dimensions: node.pairs("Dimensions", "Name", "Value"),
        period: node.int?("Period"),
        unit: node.string?("Unit"),
        evaluation_periods: node.int?("EvaluationPeriods"),
        datapoints_to_alarm: node.int?("DatapointsToAlarm"),
        threshold: node.float?("Threshold"),
        comparison_operator: node.string?("ComparisonOperator"),
        treat_missing_data: node.string?("TreatMissingData"),
        evaluate_low_sample_count_percentile: node.string?("EvaluateLowSampleCountPercentile"),
        metrics: node.map("Metrics/member") { |m| MetricDataQuery.from_xml(m) },
        threshold_metric_id: node.string?("ThresholdMetricId"),
      )
    end
  end

  # An alarm whose state is a boolean `alarm_rule` over other alarms.
  record CompositeAlarm,
    alarm_name : String,
    alarm_arn : String,
    alarm_description : String?,
    alarm_rule : String?,
    alarm_configuration_updated_timestamp : Time?,
    actions_enabled : Bool?,
    ok_actions : Array(String),
    alarm_actions : Array(String),
    insufficient_data_actions : Array(String),
    state_value : String?,
    state_reason : String?,
    state_reason_data : String?,
    state_updated_timestamp : Time?,
    state_transitioned_timestamp : Time? do
    # :nodoc:
    def self.from_xml(node) : self
      new(
        alarm_name: node.string("AlarmName"),
        alarm_arn: node.string("AlarmArn"),
        alarm_description: node.string?("AlarmDescription"),
        alarm_rule: node.string?("AlarmRule"),
        alarm_configuration_updated_timestamp: node.time?("AlarmConfigurationUpdatedTimestamp"),
        actions_enabled: node.bool?("ActionsEnabled"),
        ok_actions: node.map("OKActions/member", &.text),
        alarm_actions: node.map("AlarmActions/member", &.text),
        insufficient_data_actions: node.map("InsufficientDataActions/member", &.text),
        state_value: node.string?("StateValue"),
        state_reason: node.string?("StateReason"),
        state_reason_data: node.string?("StateReasonData"),
        state_updated_timestamp: node.time?("StateUpdatedTimestamp"),
        state_transitioned_timestamp: node.time?("StateTransitionedTimestamp"),
      )
    end
  end

  class DescribeAlarmsOutput < Base
    getter metric_alarms : Array(MetricAlarm)
    getter composite_alarms : Array(CompositeAlarm)
    getter next_token : String?

    def initialize(@metric_alarms : Array(MetricAlarm), @composite_alarms : Array(CompositeAlarm), @next_token : String?, response)
      super(response)
    end

    # :nodoc:
    def self.from_response(response : HTTP::Client::Response) : self
      result = XML.new(response.body).first("DescribeAlarmsResponse/DescribeAlarmsResult")
      new(
        result.map("MetricAlarms/member") { |a| MetricAlarm.from_xml(a) },
        result.map("CompositeAlarms/member") { |a| CompositeAlarm.from_xml(a) },
        result.string?("NextToken"),
        response
      )
    end
  end
end
