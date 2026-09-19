require "socket"

module Awscr::CloudWatch::Spec
  # TCP server that answers each connection with canned bytes, or closes it
  # right away when the canned response is `nil`. For malformed HTTP.
  class RawServer
    getter connections = 0

    def initialize(@responses : Array(String?))
      @server = TCPServer.new("127.0.0.1", 0)
      spawn do
        while socket = @server.accept?
          @connections += 1
          response = @responses.shift?
          spawn answer(socket, response)
        end
      end
    end

    def endpoint : String
      "http://127.0.0.1:#{@server.local_address.port}"
    end

    def close
      @server.close
    end

    private def answer(socket : TCPSocket, response : String?)
      length = 0
      while line = socket.gets
        break if line.empty?
        length = line.split(':')[1].to_i if line.starts_with?("Content-Length:")
      end
      socket.skip(length)
      socket << response if response
    ensure
      socket.close
    end
  end
end
