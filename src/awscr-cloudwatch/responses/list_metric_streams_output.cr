module Awscr::CloudWatch::Response
  record MetricStreamEntry,
    name : String?,
    arn : String?,
    state : String?,
    creation_date : Time?,
    last_update_date : Time?,
    firehose_arn : String?,
    output_format : String? do
    # :nodoc:
    def self.from_xml(node) : self
      new(
        node.string?("Name"),
        node.string?("Arn"),
        node.string?("State"),
        node.time?("CreationDate"),
        node.time?("LastUpdateDate"),
        node.string?("FirehoseArn"),
        node.string?("OutputFormat"),
      )
    end
  end

  class ListMetricStreamsOutput < Base
    getter entries : Array(MetricStreamEntry)
    getter next_token : String?

    def initialize(@entries : Array(MetricStreamEntry), @next_token : String?, response)
      super(response)
    end

    # :nodoc:
    def self.from_response(response : HTTP::Client::Response) : self
      result = XML.new(response.body).first("ListMetricStreamsResponse/ListMetricStreamsResult")
      new(result.map("Entries/member") { |e| MetricStreamEntry.from_xml(e) }, result.string?("NextToken"), response)
    end
  end
end
