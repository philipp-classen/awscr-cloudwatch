module Awscr::CloudWatch::Response
  class GetDashboardOutput < Base
    getter dashboard_name : String
    getter dashboard_arn : String
    # The widget definition, as JSON.
    getter dashboard_body : String

    def initialize(@dashboard_name : String, @dashboard_arn : String, @dashboard_body : String, response)
      super(response)
    end

    # :nodoc:
    def self.from_response(response : HTTP::Client::Response) : self
      result = XML.new(response.body).first("GetDashboardResponse/GetDashboardResult")
      new(result.string("DashboardName"), result.string("DashboardArn"), result.string("DashboardBody"), response)
    end
  end
end
