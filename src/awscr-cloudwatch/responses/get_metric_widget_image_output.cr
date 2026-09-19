require "base64"

module Awscr::CloudWatch::Response
  class GetMetricWidgetImageOutput < Base
    # PNG bytes.
    getter image : Bytes

    def initialize(@image : Bytes, response)
      super(response)
    end

    # :nodoc:
    def self.from_response(response : HTTP::Client::Response) : self
      encoded = XML.new(response.body).string("GetMetricWidgetImageResponse/GetMetricWidgetImageResult/MetricWidgetImage")
      new(Base64.decode(encoded), response)
    end
  end
end
