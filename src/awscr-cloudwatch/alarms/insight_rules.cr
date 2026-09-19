require "./client"

module Awscr::CloudWatch
  class AlarmClient
    # Contributor Insights rules.
    #
    # TODO: not verified against real AWS (needs a CloudWatch Logs log group).
    # Parameters follow the API reference.

    def put_insight_rule(rule_name : String, rule_definition : String, rule_state : String = "ENABLED",
                         tags : Hash(String, String)? = nil) : Nil
      request Params.new("PutInsightRule")
        .add("RuleName", rule_name)
        .add("RuleDefinition", rule_definition)
        .add("RuleState", rule_state)
        .add_pairs("Tags", tags, {"Key", "Value"})
    end

    def describe_insight_rules(max_results : Int32? = nil, next_token : String? = nil) : Response::DescribeInsightRulesOutput
      query Response::DescribeInsightRulesOutput, Params.new("DescribeInsightRules")
        .add("MaxResults", max_results)
        .add("NextToken", next_token)
    end

    def delete_insight_rules(rule_names : Array(String)) : Nil
      request Params.new("DeleteInsightRules").add_list("RuleNames", rule_names)
    end

    def enable_insight_rules(rule_names : Array(String)) : Nil
      request Params.new("EnableInsightRules").add_list("RuleNames", rule_names)
    end

    def disable_insight_rules(rule_names : Array(String)) : Nil
      request Params.new("DisableInsightRules").add_list("RuleNames", rule_names)
    end
  end
end
