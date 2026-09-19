module Awscr::CloudWatch::Response
  class ListMetricsOutput < Base
    getter metrics : Array(Metric)
    getter next_token : String?

    def initialize(@metrics : Array(Metric), @next_token : String?, response)
      super(response)
    end

    # :nodoc:
    def self.from_response(response : HTTP::Client::Response) : self
      result = XML.new(response.body).first("ListMetricsResponse/ListMetricsResult")
      new(result.map("Metrics/member") { |m| Metric.from_xml(m) }, result.string?("NextToken"), response)
    end
  end
end
