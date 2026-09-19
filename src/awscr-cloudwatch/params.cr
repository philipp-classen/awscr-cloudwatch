module Awscr::CloudWatch
  # Serializes API arguments into AWS Query protocol parameters.
  #
  # Lists use the `Key.member.N` convention, nested fields are joined with
  # dots. `nil` values are skipped, so optional arguments can be passed
  # through unchanged.
  class Params
    def initialize(action : String)
      @params = {"Action" => action, "Version" => API_VERSION}
    end

    def add(key : String, value : Nil) : self
      self
    end

    def add(key : String, value : String | Number | Bool) : self
      @params[key] = value.to_s
      self
    end

    def add(key : String, value : Time) : self
      @params[key] = value.to_rfc3339
      self
    end

    # `Key.member.1`, `Key.member.2`, ...
    def add_list(key : String, values : Array(T)?) forall T
      values.try &.each_with_index(1) { |value, i| add("#{key}.member.#{i}", value) }
      self
    end

    # Structs that know how to serialize themselves under a prefix.
    def add_structs(key : String, values : Array(T)?) forall T
      values.try &.each_with_index(1) { |value, i| value.add_to(self, "#{key}.member.#{i}") }
      self
    end

    # `Key.member.N.Name` / `Key.member.N.Value` pairs (dimensions, tags, ...).
    def add_pairs(key : String, pairs : Hash(String, String)?, names = {"Name", "Value"}) : self
      pairs.try &.each_with_index(1) do |(name, value), i|
        add("#{key}.member.#{i}.#{names[0]}", name)
        add("#{key}.member.#{i}.#{names[1]}", value)
      end
      self
    end

    def to_h : Hash(String, String)
      @params
    end
  end
end
