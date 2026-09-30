module Awscr::CloudWatch
  # The granularity of statistics. CloudWatch accepts multiples of 60 seconds, and
  # 1, 5, 10, 20 or 30 seconds for high-resolution metrics. Other periods fail here,
  # before a request is sent.
  module Period
    HIGH_RESOLUTION = {1, 5, 10, 20, 30}

    # Whether CloudWatch accepts *period*.
    def self.valid?(period : Time::Span) : Bool
      seconds = period.to_i
      period.nanoseconds == 0 && (seconds.in?(HIGH_RESOLUTION) || (seconds > 0 && seconds.divisible_by?(60)))
    end

    # Raises `ArgumentError` for a period CloudWatch does not accept.
    def self.validate(period : Time::Span?) : Nil
      return if period.nil? || valid?(period)
      raise ArgumentError.new("period must be a multiple of 60 seconds, or 1, 5, 10, 20 or 30 seconds for high-resolution metrics, got #{period}")
    end

    # The period as a request carries it: whole seconds.
    def self.seconds(period : Time::Span?) : Int64?
      validate(period)
      period.try(&.to_i)
    end
  end
end
