module Awscr::CloudWatch
  # One sample to publish with `MetricClient#put_metric_data`.
  #
  # Use exactly one of `value`, `values` (optionally with `counts`) or
  # `statistic_values`. Without a `timestamp` CloudWatch uses the receive time.
  #
  # AWS limits: ASCII names and dimensions, 30 dimensions, 150 values, and
  # timestamps between two weeks ago and two hours ahead.
  struct MetricDatum
    getter metric_name : String
    getter value : Float64?
    getter values : Array(Float64)?
    getter counts : Array(Float64)?
    getter statistic_values : StatisticSet?
    getter unit : String?
    getter dimensions : Hash(String, String)?
    getter timestamp : Time?
    getter storage_resolution : Int32?

    def initialize(
      @metric_name : String,
      value : Number? = nil,
      *,
      @values : Array(Float64)? = nil,
      @counts : Array(Float64)? = nil,
      @statistic_values : StatisticSet? = nil,
      @unit : String? = nil,
      @dimensions : Hash(String, String)? = nil,
      @timestamp : Time? = nil,
      @storage_resolution : Int32? = nil,
    )
      @value = value.try(&.to_f64)
    end

    # A datum with unit `Count`.
    def self.counter(metric_name : String, value : Number = 1,
                     dimensions : Hash(String, String)? = nil, timestamp : Time? = nil) : self
      new(metric_name, value, unit: "Count", dimensions: dimensions, timestamp: timestamp)
    end

    # :nodoc:
    def add_to(params : Params, prefix : String) : Nil
      params.add("#{prefix}.MetricName", metric_name)
        .add("#{prefix}.Value", value)
        .add_list("#{prefix}.Values", values)
        .add_list("#{prefix}.Counts", counts)
        .add("#{prefix}.Unit", unit)
        .add("#{prefix}.Timestamp", timestamp)
        .add("#{prefix}.StorageResolution", storage_resolution)
        .add_pairs("#{prefix}.Dimensions", dimensions)
      statistic_values.try &.add_to(params, "#{prefix}.StatisticValues")
    end
  end

  # Pre-aggregated samples: publish a whole batch as one datum.
  struct StatisticSet
    getter sample_count : Float64
    getter sum : Float64
    getter minimum : Float64
    getter maximum : Float64

    def initialize(*, sample_count : Number, sum : Number, minimum : Number, maximum : Number)
      @sample_count = sample_count.to_f64
      @sum = sum.to_f64
      @minimum = minimum.to_f64
      @maximum = maximum.to_f64
    end

    # :nodoc:
    def add_to(params : Params, prefix : String) : Nil
      params.add("#{prefix}.SampleCount", sample_count)
        .add("#{prefix}.Sum", sum)
        .add("#{prefix}.Minimum", minimum)
        .add("#{prefix}.Maximum", maximum)
    end
  end
end
