require "awscr-signer"
require "log"

require "./awscr-cloudwatch/*"

module Awscr::CloudWatch
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify }}
  Log     = ::Log.for("awscr-cloudwatch")

  # :nodoc:
  SERVICE_NAME = "monitoring"
  # :nodoc:
  API_VERSION = "2010-08-01"
end
