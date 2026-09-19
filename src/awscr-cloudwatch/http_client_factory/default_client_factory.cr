require "./http_client_factory"

module Awscr::CloudWatch
  # Default `HttpClientFactory`: a new connection per request, with timeouts
  # so a stalled connection cannot block the caller forever.
  class DefaultHttpClientFactory < HttpClientFactory
    # Shared by all connections: creating a context loads the CA store,
    # which is too slow to repeat per request.
    @tls = OpenSSL::SSL::Context::Client.new

    def initialize(@connect_timeout : Time::Span = 15.seconds, @read_timeout : Time::Span = 60.seconds)
    end

    def acquire_client(endpoint : URI) : HTTP::Client
      client = HTTP::Client.new(endpoint, tls: endpoint.scheme == "https" ? @tls : nil)
      client.connect_timeout = @connect_timeout
      client.read_timeout = @read_timeout
      client.write_timeout = @read_timeout
      client
    end

    def release(client : HTTP::Client?)
      client.try &.close
    end
  end
end
