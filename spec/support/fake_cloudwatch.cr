require "http/server"
require "compress/gzip"

module Awscr::CloudWatch::Spec
  # In-process stand-in for the CloudWatch endpoint. Verifies the SigV4
  # signature of every request (credentials "key"/"secret", region
  # us-east-1), records it, and answers with the queued replies. An empty
  # 200 is sent once the queue is empty.
  class FakeCloudWatch
    record Request, method : String, path : String, headers : HTTP::Headers, params : Hash(String, String)
    record Reply, status : Int32, body : String, delay : Time::Span

    CREDENTIALS = Awscr::Signer::Credentials.new("key", "secret")
    FORBIDDEN   = <<-XML
      <ErrorResponse xmlns="http://monitoring.amazonaws.com/doc/2010-08-01/">
        <Error><Type>Sender</Type><Code>SignatureDoesNotMatch</Code><Message>Bad signature</Message></Error>
      </ErrorResponse>
      XML

    getter requests = [] of Request
    # Computes the reply from the request; takes precedence over queued replies.
    property responder : (Request -> Reply)?

    def initialize
      @replies = Deque(Reply).new
      @mutex = Mutex.new # requests arrive on several threads under -Dpreview_mt
      @server = HTTP::Server.new do |ctx|
        req = ctx.request
        body = req.body.try(&.gets_to_end) || ""
        request = Request.new(req.method, req.resource, req.headers, URI::Params.parse(body).to_h)
        reply = @mutex.synchronize do
          @requests << request
          if !valid_signature?(req, body)
            Reply.new(403, FORBIDDEN, Time::Span.zero)
          else
            @responder.try(&.call(request)) || @replies.shift? || Reply.new(200, "", Time::Span.zero)
          end
        end
        sleep reply.delay
        ctx.response.status_code = reply.status
        ctx.response.content_type = "text/xml"
        if @gzip_next
          @gzip_next = false
          ctx.response.headers["Content-Encoding"] = "gzip"
          Compress::Gzip::Writer.open(ctx.response) { |gzip| gzip << reply.body }
        else
          ctx.response << reply.body
        end
      end
      @address = @server.bind_unused_port("127.0.0.1")
      spawn { @server.listen }
      Fiber.yield # let the server start before the first request or close
    end

    def endpoint : String
      "http://#{@address}"
    end

    def reply(body : String, status : Int32 = 200, delay : Time::Span = Time::Span.zero) : self
      @mutex.synchronize { @replies << Reply.new(status, body, delay) }
      self
    end

    # Next reply is sent gzip-compressed.
    def reply_gzipped(body : String) : self
      @gzip_next = true
      reply(body)
    end

    def last_request : Request
      requests.last
    end

    def close
      @server.close
    end

    # Recomputes the signature from the headers the client claims to have signed.
    private def valid_signature?(req : HTTP::Request, body : String) : Bool
      authorization = req.headers["Authorization"]? || return false
      signed_headers = authorization[/SignedHeaders=([^,]+)/, 1]? || return false
      date = req.headers["X-Amz-Date"]? || return false

      scope = Awscr::Signer::Scope.new("us-east-1", "monitoring", Time.parse_utc(date, "%Y%m%dT%H%M%SZ"))
      canonical = Awscr::Signer::V4::Request.new(req.method, req.path, body)
      req.query_params.each { |key, value| canonical.query.add(key, value) }
      signed_headers.split(';').each { |name| canonical.headers.add(name, req.headers[name]) }
      signature = Awscr::Signer::V4::Signature.new(scope, canonical.to_s, CREDENTIALS)

      authorization == "AWS4-HMAC-SHA256 Credential=key/#{scope}, SignedHeaders=#{signed_headers}, Signature=#{signature}"
    end
  end

  # Keeps one connection open across requests, like a pool would.
  class SingleConnectionFactory < HttpClientFactory
    getter acquired = 0
    getter released = 0

    def acquire_client(endpoint : URI) : HTTP::Client
      @acquired += 1
      @client ||= HTTP::Client.new(endpoint)
    end

    def release(client : HTTP::Client?)
      @released += 1
    end
  end
end
