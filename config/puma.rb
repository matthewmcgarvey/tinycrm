require "puma"

workers Integer(ENV["WEB_CONCURRENCY"] || 1)
threads_count = Integer(ENV["RAILS_MAX_THREADS"] || 1)
threads threads_count, threads_count

rackup      DefaultRackup
port        ENV['PORT']     || 9001
environment ENV['RACK_ENV'] || "development"