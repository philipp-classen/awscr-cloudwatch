require "./http_client_factory/*"
require "./responses/*"

module Awscr::CloudWatch
  # Shared by `MetricClient` and `AlarmClient`: credentials, endpoint,
  # request execution and the tagging API.
  #
  # Calls raise `Awscr::CloudWatch::Exception` when AWS rejects the request.
  class BaseClient
    getter endpoint : URI
    getter region : String

    private getter http : Http

    # *max_attempts* bounds the retries of throttled or failed requests.
    def initialize(
      @region : String,
      aws_access_key : String,
      aws_secret_key : String,
      aws_session_key : String? = nil,
      endpoint : String? = nil,
      client_factory : HttpClientFactory = DefaultHttpClientFactory.new,
      max_attempts : Int32 = 3,
    )
      @endpoint = URI.parse(endpoint || "https://#{SERVICE_NAME}.#{@region}.amazonaws.com")
      unless @endpoint.scheme.in?("http", "https") && @endpoint.host.presence
        raise ArgumentError.new("endpoint must be a URL like http://localhost:4566, got #{endpoint.inspect}")
      end

      signer = Awscr::Signer::Signers::V4.new(
        service: SERVICE_NAME,
        region: @region,
        aws_access_key: aws_access_key,
        aws_secret_key: aws_secret_key,
        amz_security_token: aws_session_key
      )
      @http = Http.new(signer, @endpoint, client_factory, max_attempts)
    end

    # Adds or replaces tags on an alarm or Contributor Insights rule.
    def tag_resource(resource_arn : String, tags : Hash(String, String)) : Nil
      request Params.new("TagResource")
        .add("ResourceARN", resource_arn)
        .add_pairs("Tags", tags, {"Key", "Value"})
    end

    def untag_resource(resource_arn : String, tag_keys : Array(String)) : Nil
      request Params.new("UntagResource")
        .add("ResourceARN", resource_arn)
        .add_list("TagKeys", tag_keys)
    end

    def list_tags_for_resource(resource_arn : String) : Response::ListTagsForResourceOutput
      query Response::ListTagsForResourceOutput, Params.new("ListTagsForResource").add("ResourceARN", resource_arn)
    end

    protected def request(params : Params) : HTTP::Client::Response
      http.post(params.to_h)
    end

    # Sends *params* and parses the reply as *output*.
    protected def query(output : T.class, params : Params) : T forall T
      resp = request(params)
      begin
        output.from_response(resp)
      rescue ex : ArgumentError | Time::Format::Error | Base64::Error
        raise Exception.new("Unexpected response: #{ex.message}", resp.status)
      end
    end
  end
end
