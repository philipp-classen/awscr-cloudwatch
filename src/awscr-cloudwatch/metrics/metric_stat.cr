module Awscr::CloudWatch
  # A metric together with the statistic (`Sum`, `Average`, `p99`, ...) and the
  # period to aggregate it by, e.g. `5.minutes` (see `Period` for the accepted values).
  struct MetricStat
    getter metric : Metric
    getter period : Time::Span
    getter stat : String
    getter unit : String?

    def initialize(@metric : Metric, @period : Time::Span, @stat : String, @unit : String? = nil)
      Period.validate(@period)
    end

    # :nodoc:
    def self.from_xml(node) : self
      new(Metric.from_xml(node.first("Metric")), node.string("Period").to_i.seconds, node.string("Stat"), node.string?("Unit"))
    end

    # :nodoc:
    def add_to(params : Params, prefix : String) : Nil
      metric.add_to(params, "#{prefix}.Metric")
      params.add("#{prefix}.Period", Period.seconds(period))
        .add("#{prefix}.Stat", stat)
        .add("#{prefix}.Unit", unit)
    end
  end
end
