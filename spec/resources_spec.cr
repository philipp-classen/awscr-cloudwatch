require "./spec_helper"

private def open_fds : Int32
  Dir.children("/proc/self/fd").size
end

describe "resource usage" do
  it "does not leak file descriptors or memory" do
    pending! "needs /proc" unless File.directory?("/proc/self/fd")

    CW::Spec.with_fake_server do |server|
      client = CW::Spec.metric_client(server, max_attempts: 1)
      50.times { client.put_counter("MyApp", "Warmup") }
      GC.collect
      fds = open_fds
      heap = GC.stats.heap_size.to_i64

      2000.times { client.put_counter("MyApp", "Requests", dimensions: {"Env" => "test"}) }
      200.times do
        server.reply(CW::Spec.fixture("error_invalid_value"), 400)
        expect_raises(CW::Exception) { client.put_counter("MyApp", "Requests") }
      end
      200.times do
        server.reply(CW::Spec.fixture("list_metrics"))
        client.list_metrics.metrics.size.should eq 4
      end

      GC.collect
      (open_fds - fds).should be <= 3
      (GC.stats.heap_size.to_i64 - heap).should be < 64 * 1024 * 1024
    end
  end
end
