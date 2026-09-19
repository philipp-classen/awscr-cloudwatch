module Awscr::CloudWatch::Response
  class ListTagsForResourceOutput < Base
    getter tags : Hash(String, String)

    def initialize(@tags : Hash(String, String), response)
      super(response)
    end

    # :nodoc:
    def self.from_response(response : HTTP::Client::Response) : self
      new(XML.new(response.body).pairs("ListTagsForResourceResponse/ListTagsForResourceResult/Tags", "Key", "Value"), response)
    end
  end
end
