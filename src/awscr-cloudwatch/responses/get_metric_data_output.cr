module Awscr::CloudWatch::Response
  record MessageData, code : String?, value : String? do
    # :nodoc:
    def self.from_xml(node) : self
      new(node.string?("Code"), node.string?("Value"))
    end
  end

  # Time series of one `MetricDataQuery`. `timestamps[i]` belongs to `values[i]`.
  # `status_code` is `Complete`, `PartialData`, `InternalError` or `Forbidden`.
  record MetricDataResult,
    id : String,
    label : String?,
    timestamps : Array(Time),
    values : Array(Float64),
    status_code : String?,
    messages : Array(MessageData) do
    # :nodoc:
    def self.from_xml(node) : self
      new(
        id: node.string("Id"),
        label: node.string?("Label"),
        timestamps: node.map("Timestamps/member") { |t| Time.parse_rfc3339(t.text) },
        values: node.map("Values/member", &.text.to_f64),
        status_code: node.string?("StatusCode"),
        messages: node.map("Messages/member") { |m| MessageData.from_xml(m) },
      )
    end
  end

  class GetMetricDataOutput < Base
    getter metric_data_results : Array(MetricDataResult)
    getter messages : Array(MessageData)
    getter next_token : String?

    def initialize(@metric_data_results : Array(MetricDataResult), @messages : Array(MessageData), @next_token : String?, response)
      super(response)
    end

    # :nodoc:
    def self.from_response(response : HTTP::Client::Response) : self
      result = XML.new(response.body).first("GetMetricDataResponse/GetMetricDataResult")
      new(
        result.map("MetricDataResults/member") { |m| MetricDataResult.from_xml(m) },
        result.map("Messages/member") { |m| MessageData.from_xml(m) },
        result.string?("NextToken"),
        response
      )
    end
  end
end
