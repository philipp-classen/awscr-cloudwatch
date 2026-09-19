module Awscr::CloudWatch
  # A metric together with the statistic (`Sum`, `Average`, `p99`, ...) and
  # period in seconds to aggregate it by.
  struct MetricStat
    getter metric : Metric
    getter period : Int32
    getter stat : String
    getter unit : String?

    def initialize(@metric : Metric, @period : Int32, @stat : String, @unit : String? = nil)
    end

    # :nodoc:
    def self.from_xml(node) : self
      new(Metric.from_xml(node.first("Metric")), node.string("Period").to_i32, node.string("Stat"), node.string?("Unit"))
    end

    # :nodoc:
    def add_to(params : Params, prefix : String) : Nil
      metric.add_to(params, "#{prefix}.Metric")
      params.add("#{prefix}.Period", period)
        .add("#{prefix}.Stat", stat)
        .add("#{prefix}.Unit", unit)
    end
  end
end
