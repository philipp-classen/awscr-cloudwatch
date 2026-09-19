module Awscr::CloudWatch::Response
  # TODO: not verified against real AWS.
  record InsightRule,
    name : String?,
    state : String?,
    schema : String?,
    definition : String?,
    managed_rule : Bool? do
    # :nodoc:
    def self.from_xml(node) : self
      new(node.string?("Name"), node.string?("State"), node.string?("Schema"), node.string?("Definition"), node.bool?("ManagedRule"))
    end
  end

  class DescribeInsightRulesOutput < Base
    getter insight_rules : Array(InsightRule)
    getter next_token : String?

    def initialize(@insight_rules : Array(InsightRule), @next_token : String?, response)
      super(response)
    end

    # :nodoc:
    def self.from_response(response : HTTP::Client::Response) : self
      result = XML.new(response.body).first("DescribeInsightRulesResponse/DescribeInsightRulesResult")
      new(result.map("InsightRules/member") { |r| InsightRule.from_xml(r) }, result.string?("NextToken"), response)
    end
  end
end
