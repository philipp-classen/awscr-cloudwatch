module Awscr::CloudWatch::Response
  # An anomaly detection model on a single metric. `state_value` is
  # `PENDING_TRAINING`, `TRAINED_INSUFFICIENT_DATA` or `TRAINED`.
  record AnomalyDetector,
    namespace : String?,
    metric_name : String?,
    stat : String?,
    dimensions : Hash(String, String),
    state_value : String?,
    metric_timezone : String? do
    # :nodoc:
    def self.from_xml(node) : self
      single = node.first?("SingleMetricAnomalyDetector") || node
      new(
        namespace: single.string?("Namespace"),
        metric_name: single.string?("MetricName"),
        stat: single.string?("Stat"),
        dimensions: single.pairs("Dimensions", "Name", "Value"),
        state_value: node.string?("StateValue"),
        metric_timezone: node.string?("Configuration/MetricTimezone"),
      )
    end
  end

  class DescribeAnomalyDetectorsOutput < Base
    getter anomaly_detectors : Array(AnomalyDetector)
    getter next_token : String?

    def initialize(@anomaly_detectors : Array(AnomalyDetector), @next_token : String?, response)
      super(response)
    end

    # :nodoc:
    def self.from_response(response : HTTP::Client::Response) : self
      result = XML.new(response.body).first("DescribeAnomalyDetectorsResponse/DescribeAnomalyDetectorsResult")
      detectors = result.map("AnomalyDetectors/member") { |d| AnomalyDetector.from_xml(d) }
      new(detectors, result.string?("NextToken"), response)
    end
  end
end
