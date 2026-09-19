module Awscr::CloudWatch
  # Provides the `HTTP::Client` for each request. Subclasses decide about
  # connection reuse: one client per request (`DefaultHttpClientFactory`),
  # a persistent connection, or a pool.
  abstract class HttpClientFactory
    # Returns a client for *endpoint*. Requests are signed by the caller,
    # so handing out the same client again is fine, but never to two
    # fibers at once.
    abstract def acquire_client(endpoint : URI) : HTTP::Client

    # Called once the request is done, also when it failed.
    def release(client : HTTP::Client?)
      # No-op
    end
  end
end
