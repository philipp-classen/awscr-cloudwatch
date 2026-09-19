require "xml"

module Awscr::CloudWatch
  # Thin XPath wrapper that hides the default namespace of AWS responses.
  class XML
    # :nodoc:
    struct NamespacedNode
      def initialize(@node : ::XML::Node)
      end

      # Text content of this node.
      def text : String
        @node.content
      end

      def string(name : String) : String
        @node.xpath("string(#{build_path(name)})", namespaces).as(String)
      end

      # Text of the child element, or `nil` if missing or empty.
      def string?(name : String) : String?
        s = string(name)
        s.empty? ? nil : s
      end

      def int?(name : String) : Int32?
        string?(name).try(&.to_i32)
      end

      def float?(name : String) : Float64?
        string?(name).try(&.to_f64)
      end

      def bool?(name : String) : Bool?
        string?(name).try { |s| s == "true" }
      end

      def time?(name : String) : Time?
        string?(name).try { |s| Time.parse_rfc3339(s) }
      end

      def map(query : String, & : NamespacedNode -> T) : Array(T) forall T
        @node.xpath(build_path(query), namespaces).as(::XML::NodeSet).map do |node|
          yield NamespacedNode.new(node)
        end
      end

      # First element matching *query*, or `nil`.
      def first?(query : String) : NamespacedNode?
        map(query) { |n| n }.first?
      end

      # First element matching *query*. Raises if there is none.
      def first(query : String) : NamespacedNode
        first?(query) || raise Awscr::CloudWatch::Exception.new("Missing element: #{query}")
      end

      # Parses `<query><member><key>..</key><value>..</value></member>...` into a Hash.
      def pairs(query : String, key : String, value : String) : Hash(String, String)
        map("#{query}/member") { |m| {m.string(key), m.string(value)} }.to_h
      end

      # Prefixes every step of *path* with the root namespace, registered
      # under the same name that `XML::XPathContext` uses.
      private def build_path(path : String) : String
        key = namespaces.has_key?("xmlns") ? "xmlns" : namespaces.keys.first?
        prefix = key ? "#{key.lchop("xmlns:")}:" : ""
        steps = path.lchop("//").split('/').join('/') { |step| "#{prefix}#{step}" }
        path.starts_with?("//") ? "//#{steps}" : steps
      end

      private def namespaces
        @node.root.try(&.namespaces) || {} of String => String?
      end
    end

    def initialize(xml : String | IO)
      @xml = NamespacedNode.new(XML.parse(xml))
    end

    protected def self.parse(xml : String | IO) : ::XML::Node
      ::XML.parse(xml)
    rescue ex : ::XML::Error
      raise Awscr::CloudWatch::Exception.new("Invalid XML: #{ex.message}")
    end

    # :nodoc:
    forward_missing_to @xml
  end
end
