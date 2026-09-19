module Awscr::CloudWatch::Response
  record DashboardEntry,
    dashboard_name : String,
    dashboard_arn : String,
    last_modified : Time?,
    size : Int64? do
    # :nodoc:
    def self.from_xml(node) : self
      new(node.string("DashboardName"), node.string("DashboardArn"), node.time?("LastModified"), node.string?("Size").try(&.to_i64))
    end
  end

  class ListDashboardsOutput < Base
    getter dashboard_entries : Array(DashboardEntry)
    getter next_token : String?

    def initialize(@dashboard_entries : Array(DashboardEntry), @next_token : String?, response)
      super(response)
    end

    # :nodoc:
    def self.from_response(response : HTTP::Client::Response) : self
      result = XML.new(response.body).first("ListDashboardsResponse/ListDashboardsResult")
      entries = result.map("DashboardEntries/member") { |e| DashboardEntry.from_xml(e) }
      new(entries, result.string?("NextToken"), response)
    end
  end
end
