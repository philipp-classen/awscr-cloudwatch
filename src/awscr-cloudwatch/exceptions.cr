require "http"

module Awscr::CloudWatch
  # Raised for every non-2xx response.
  #
  # `code` is the AWS error code (e.g. `InvalidParameterValue`, `Throttling`),
  # `request_id` helps AWS support to trace a request.
  class Exception < ::Exception
    getter status : HTTP::Status
    getter code : String?
    getter request_id : String?

    # Error codes that AWS SDKs retry with backoff.
    RETRYABLE_CODES = %w[Throttling ThrottlingException RequestLimitExceeded ServiceUnavailable InternalFailure InternalServiceError]

    def initialize(message : String, @status = HTTP::Status::INTERNAL_SERVER_ERROR, @code = nil, @request_id = nil)
      super(message)
    end

    def self.from_response(response : HTTP::Client::Response) : Exception
      code = message = request_id = nil

      if body = response.body.presence
        xml = XML.new(body)
        code = xml.string?("//Error/Code")
        message = xml.string?("//Error/Message")
        request_id = xml.string?("//RequestId")
      end

      text = [code, message].compact.join(": ").presence || "HTTP #{response.status_code} #{response.status_message}"

      case code
      # STS reports "ExpiredToken", CloudWatch "ExpiredTokenException".
      when "ExpiredToken", "ExpiredTokenException"
        ExpiredTokenException.new(text, response.status, code, request_id)
      else
        new(text, response.status, code, request_id)
      end
    rescue Awscr::CloudWatch::Exception # unparsable body
      new("HTTP #{response.status_code}: #{response.body}", response.status)
    end

    # Transient errors that are worth retrying.
    def retryable? : Bool
      status.server_error? || status.too_many_requests? || RETRYABLE_CODES.includes?(code)
    end
  end

  # The session token of the request has expired: refresh the credentials
  # and send the request again.
  class ExpiredTokenException < Exception
  end
end
