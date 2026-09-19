module Awscr::CloudWatch
  # Identifies a metric by namespace, name and dimensions.
  struct Metric
    getter namespace : String
    getter metric_name : String
    getter dimensions : Hash(String, String)

    def initialize(@namespace : String, @metric_name : String, @dimensions : Hash(String, String) = {} of String => String)
    end

    # :nodoc:
    def self.from_xml(node) : self
      new(node.string("Namespace"), node.string("MetricName"), node.pairs("Dimensions", "Name", "Value"))
    end

    # :nodoc:
    def add_to(params : Params, prefix : String) : Nil
      params.add("#{prefix}.Namespace", namespace)
        .add("#{prefix}.MetricName", metric_name)
        .add_pairs("#{prefix}.Dimensions", dimensions)
    end
  end
end
