module Awscr::CloudWatch::Response
  # Aggregated values of one period. `extended_statistics` holds percentiles
  # such as `p99` when they were requested.
  record Datapoint,
    timestamp : Time?,
    sample_count : Float64?,
    average : Float64?,
    sum : Float64?,
    minimum : Float64?,
    maximum : Float64?,
    unit : String?,
    extended_statistics : Hash(String, Float64) do
    # :nodoc:
    def self.from_xml(node) : self
      new(
        timestamp: node.time?("Timestamp"),
        sample_count: node.float?("SampleCount"),
        average: node.float?("Average"),
        sum: node.float?("Sum"),
        minimum: node.float?("Minimum"),
        maximum: node.float?("Maximum"),
        unit: node.string?("Unit"),
        extended_statistics: node.map("ExtendedStatistics/entry") { |e| {e.string("key"), e.string("value").to_f64} }.to_h,
      )
    end
  end

  class GetMetricStatisticsOutput < Base
    getter label : String?
    getter datapoints : Array(Datapoint)

    def initialize(@label : String?, @datapoints : Array(Datapoint), response)
      super(response)
    end

    # :nodoc:
    def self.from_response(response : HTTP::Client::Response) : self
      result = XML.new(response.body).first("GetMetricStatisticsResponse/GetMetricStatisticsResult")
      datapoints = result.map("Datapoints/member") { |d| Datapoint.from_xml(d) }
      new(result.string?("Label"), datapoints, response)
    end
  end
end
