module Awscr::CloudWatch::Response
  # TODO: not verified against real AWS (needs a Firehose delivery stream).
  class GetMetricStreamOutput < Base
    getter name : String?
    getter arn : String?
    getter creation_date : Time?
    getter last_update_date : Time?
    getter firehose_arn : String?
    getter role_arn : String?
    getter output_format : String?
    getter state : String?
    getter include_filters : Array(String)
    getter exclude_filters : Array(String)

    def initialize(@name : String?, @arn : String?, @creation_date : Time?, @last_update_date : Time?,
                   @firehose_arn : String?, @role_arn : String?, @output_format : String?, @state : String?,
                   @include_filters : Array(String), @exclude_filters : Array(String), response)
      super(response)
    end

    # :nodoc:
    def self.from_response(response : HTTP::Client::Response) : self
      result = XML.new(response.body).first("GetMetricStreamResponse/GetMetricStreamResult")
      new(
        result.string?("Name"),
        result.string?("Arn"),
        result.time?("CreationDate"),
        result.time?("LastUpdateDate"),
        result.string?("FirehoseArn"),
        result.string?("RoleArn"),
        result.string?("OutputFormat"),
        result.string?("State"),
        result.map("IncludeFilters/member", &.string("Namespace")),
        result.map("ExcludeFilters/member", &.string("Namespace")),
        response
      )
    end
  end
end
