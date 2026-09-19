module Awscr::CloudWatch::Response
  # `history_item_type` is `ConfigurationUpdate`, `StateUpdate` or `Action`;
  # `history_data` holds the details as JSON.
  record AlarmHistoryItem,
    alarm_name : String?,
    alarm_type : String?,
    history_item_type : String?,
    history_summary : String?,
    history_data : String?,
    timestamp : Time? do
    # :nodoc:
    def self.from_xml(node) : self
      new(
        alarm_name: node.string?("AlarmName"),
        alarm_type: node.string?("AlarmType"),
        history_item_type: node.string?("HistoryItemType"),
        history_summary: node.string?("HistorySummary"),
        history_data: node.string?("HistoryData"),
        timestamp: node.time?("Timestamp"),
      )
    end
  end

  class DescribeAlarmHistoryOutput < Base
    getter alarm_history_items : Array(AlarmHistoryItem)
    getter next_token : String?

    def initialize(@alarm_history_items : Array(AlarmHistoryItem), @next_token : String?, response)
      super(response)
    end

    # :nodoc:
    def self.from_response(response : HTTP::Client::Response) : self
      result = XML.new(response.body).first("DescribeAlarmHistoryResponse/DescribeAlarmHistoryResult")
      items = result.map("AlarmHistoryItems/member") { |i| AlarmHistoryItem.from_xml(i) }
      new(items, result.string?("NextToken"), response)
    end
  end
end
