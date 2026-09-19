require "http"

module Awscr::CloudWatch::Response
  # Common functionality of every response wrapper: access to the raw HTTP
  # response and the AWS request id.
  abstract class Base
    getter response : HTTP::Client::Response

    def initialize(@response : HTTP::Client::Response)
    end

    # Helps AWS support to trace a request.
    def request_id : String?
      XML.new(response.body).string?("//ResponseMetadata/RequestId")
    end

    delegate status, headers, to: response
  end
end
