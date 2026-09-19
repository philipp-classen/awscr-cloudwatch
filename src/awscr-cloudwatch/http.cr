require "uri"

module Awscr::CloudWatch
  # Sends signed requests to CloudWatch and retries transient failures.
  class Http
    BACKOFF_BASE = 100.milliseconds
    BACKOFF_MAX  = 5.seconds

    def initialize(
      @signer : Awscr::Signer::Signers::V4,
      @endpoint : URI,
      @factory : HttpClientFactory,
      @max_attempts : Int32,
    )
    end

    # Sends *params* as a form-encoded POST.
    #
    # 5xx, throttling and connection errors are retried with exponential
    # backoff. Anything else raises `Exception`.
    def post(params : Hash(String, String)) : HTTP::Client::Response
      body = URI::Params.encode(params)
      attempt = 0

      loop do
        attempt += 1
        client = @factory.acquire_client(@endpoint)

        begin
          resp = client.exec(signed_request(body))
          return resp if resp.success?

          error = Exception.from_response(resp)
          raise error unless error.retryable? && attempt < @max_attempts
          Log.debug &.emit("Retrying failed request", attempt: attempt, status: resp.status_code, code: error.code)
        rescue ex : IO::Error | OpenSSL::SSL::Error
          raise ex unless attempt < @max_attempts
          Log.debug exception: ex, &.emit("Retrying after connection error", attempt: attempt)
        ensure
          @factory.release(client)
        end

        sleep backoff(attempt)
      end
    end

    # Built per attempt so every retry carries a fresh signature date.
    # The Host header must be set before signing; SigV4 covers it.
    private def signed_request(body : String) : HTTP::Request
      request = HTTP::Request.new("POST", @endpoint.path.presence || "/", body: body)
      request.headers["Host"] = @endpoint.port ? "#{@endpoint.host}:#{@endpoint.port}" : @endpoint.host.to_s
      request.headers["Content-Type"] = "application/x-www-form-urlencoded; charset=utf-8"
      @signer.sign(request)
      request
    end

    # Full jitter: a random delay between zero and the exponentially growing cap.
    private def backoff(attempt : Int32) : Time::Span
      cap = {BACKOFF_BASE * 2 ** (attempt - 1), BACKOFF_MAX}.min
      cap * rand
    end
  end
end
