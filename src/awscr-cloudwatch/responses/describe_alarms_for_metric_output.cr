module Awscr::CloudWatch::Response
  class DescribeAlarmsForMetricOutput < Base
    getter metric_alarms : Array(MetricAlarm)

    def initialize(@metric_alarms : Array(MetricAlarm), response)
      super(response)
    end

    # :nodoc:
    def self.from_response(response : HTTP::Client::Response) : self
      result = XML.new(response.body).first("DescribeAlarmsForMetricResponse/DescribeAlarmsForMetricResult")
      new(result.map("MetricAlarms/member") { |a| MetricAlarm.from_xml(a) }, response)
    end
  end
end
