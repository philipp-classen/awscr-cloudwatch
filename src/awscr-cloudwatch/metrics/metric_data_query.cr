module Awscr::CloudWatch
  # One entry of a `get_metric_data` query or a metric math alarm: either a
  # `metric_stat` to fetch, or an `expression` over the ids of other entries.
  struct MetricDataQuery
    getter id : String
    getter metric_stat : MetricStat?
    getter expression : String?
    getter label : String?
    getter return_data : Bool?
    getter period : Int32?
    getter account_id : String?

    def initialize(
      @id : String,
      *,
      @metric_stat : MetricStat? = nil,
      @expression : String? = nil,
      @label : String? = nil,
      @return_data : Bool? = nil,
      @period : Int32? = nil,
      @account_id : String? = nil,
    )
    end

    # :nodoc:
    def self.from_xml(node) : self
      new(
        node.string("Id"),
        metric_stat: node.first?("MetricStat").try { |n| MetricStat.from_xml(n) },
        expression: node.string?("Expression"),
        label: node.string?("Label"),
        return_data: node.bool?("ReturnData"),
        period: node.int?("Period"),
        account_id: node.string?("AccountId"),
      )
    end

    # :nodoc:
    def add_to(params : Params, prefix : String) : Nil
      params.add("#{prefix}.Id", id)
        .add("#{prefix}.Expression", expression)
        .add("#{prefix}.Label", label)
        .add("#{prefix}.ReturnData", return_data)
        .add("#{prefix}.Period", period)
        .add("#{prefix}.AccountId", account_id)
      metric_stat.try &.add_to(params, "#{prefix}.MetricStat")
    end
  end
end
