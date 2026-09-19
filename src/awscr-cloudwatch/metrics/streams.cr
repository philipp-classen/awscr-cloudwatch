require "./client"

module Awscr::CloudWatch
  class MetricClient
    # Metric streams.
    #
    # TODO: not verified against real AWS (needs a Firehose delivery stream
    # and an IAM role). Parameters follow the API reference.

    def put_metric_stream(name : String, firehose_arn : String, role_arn : String,
                          output_format : String, include_filters : Array(String)? = nil,
                          exclude_filters : Array(String)? = nil) : Nil
      params = Params.new("PutMetricStream")
        .add("Name", name)
        .add("FirehoseArn", firehose_arn)
        .add("RoleArn", role_arn)
        .add("OutputFormat", output_format)
      include_filters.try &.each_with_index(1) { |ns, i| params.add("IncludeFilters.member.#{i}.Namespace", ns) }
      exclude_filters.try &.each_with_index(1) { |ns, i| params.add("ExcludeFilters.member.#{i}.Namespace", ns) }

      request params
    end

    def get_metric_stream(name : String) : Response::GetMetricStreamOutput
      query Response::GetMetricStreamOutput, Params.new("GetMetricStream").add("Name", name)
    end

    def delete_metric_stream(name : String) : Nil
      request Params.new("DeleteMetricStream").add("Name", name)
    end

    def list_metric_streams(next_token : String? = nil) : Response::ListMetricStreamsOutput
      query Response::ListMetricStreamsOutput, Params.new("ListMetricStreams").add("NextToken", next_token)
    end
  end
end
