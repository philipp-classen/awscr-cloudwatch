module Awscr::CloudWatch
  # `list_metrics` filter: a dimension name, optionally with a value.
  struct DimensionFilter
    getter name : String
    getter value : String?

    def initialize(@name : String, @value : String? = nil)
    end

    # :nodoc:
    def add_to(params : Params, prefix : String) : Nil
      params.add("#{prefix}.Name", name).add("#{prefix}.Value", value)
    end
  end
end
