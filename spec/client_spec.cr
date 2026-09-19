require "./spec_helper"

describe CW::Client do
  it "bundles a metric and an alarm client for one region" do
    client = CW::Client.new("eu-central-1", "key", "secret")
    client.metrics.endpoint.to_s.should eq "https://monitoring.eu-central-1.amazonaws.com"
    client.alarms.endpoint.to_s.should eq "https://monitoring.eu-central-1.amazonaws.com"
    client.metrics.region.should eq "eu-central-1"
  end

  it "sends both clients to the custom endpoint" do
    CW::Spec.with_fake_server do |server|
      client = CW::Client.new("us-east-1", "key", "secret", "token", endpoint: server.endpoint, max_attempts: 1)
      client.metrics.put_counter("MyApp", "Requests")
      client.alarms.delete_alarms(["old"])

      server.requests.map(&.params["Action"]).should eq ["PutMetricData", "DeleteAlarms"]
      server.requests.map(&.headers["X-Amz-Security-Token"]).should eq ["token", "token"]

      server.reply("", 503)
      expect_raises(CW::Exception, "HTTP 503") { client.alarms.delete_alarms(["old"]) }
      server.requests.size.should eq 3
    end
  end
end
