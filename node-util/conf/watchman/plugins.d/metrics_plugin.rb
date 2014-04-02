#--
# Copyright 2014 Red Hat, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#++

require 'openshift-origin-node/model/watchman/watchman_plugin'

class MetricsPlugin < OpenShift::Runtime::WatchmanPlugin
  def initialize(config, logger, gears, operation)
    super

    @gears_last_updated = nil

    @gear_app_uuids = {}
    lookup_app_uuids

    # default to running every 60 seconds if not set in node.conf
    delay = Integer(@config.get('WATCHMAN_METRICS_INTERVAL')) rescue 60
    @metrics = ::OpenShift::Runtime::WatchmanPlugin::Metrics.new(delay)
  end

  def apply(iteration)
    if @gears.last_updated != @gears_last_updated
      @gear_app_uuids.clear
      lookup_app_uuids
      @metrics.update_gears(@gear_app_uuids)
    end
  end

  # cache the app uuids for each gear
  def lookup_app_uuids
    @gears.each do |uuid|
      @gear_app_uuids[uuid] = File.read(PathUtils.join(@config.get('GEAR_BASE_DIR'), uuid, '.env', 'OPENSHIFT_APP_UUID'))
    end
  end
end

module OpenShift
  module Runtime
    class WatchmanPlugin

      class SyslogLineShipper
        def <<(line)
          Syslog.info(line)
        end
      end

      class Metrics
        attr_accessor :delay, :running_apps

        def initialize(delay)
          Syslog.info "Initializing Watchman metrics plugin"

          # Set the sleep time for the metrics thread
          @delay = delay
          @mutex = Mutex.new
          @running_apps = {}
          @syslog_line_shipper = SyslogLineShipper.new
          @cgget_metrics_parser = CggetMetricsParser.new(@running_apps)

          # Begin collection thread
          start
        end

        # Step that is run on each interval
        def tick
          @mutex.synchronize do
            if @running_apps.size > 0
              call_gear_metrics
              call_application_container_metrics
            end
          end
        rescue => e
          Syslog.info("Metric: unhandled exception #{e.message}\n" + e.backtrace.join("\n"))
        end

        def start
          Thread.new do
            loop do
              tick
              sleep @delay
            end
          end
        end

        def update_gears(gears)
          @mutex.synchronize do
            # can't just overwrite the reference because @cgget_metrics_parser also has a
            # references to @running_apps, so they need to stay in sync
            @running_apps.clear
            @running_apps.merge!(gears)
          end
        end

        def call_application_container_metrics
          Utils.oo_spawn("oo-admin-ctl-gears metricsall", out: @syslog_line_shipper)
        end

        def call_gear_metrics
          get_cgroups_metrics(@running_apps.keys)
        end

        def get_cgroups_metrics(gear_uuids)
          paths = gear_uuids.map { |uuid| "/openshift/#{uuid}" }
                            .join(' ')

          command = "cgget -a #{paths}"

          @cgget_metrics_parser.reset
          out, err, rc = ::OpenShift::Runtime::Utils.oo_spawn(command, out: @cgget_metrics_parser)
        end
      end

      class CggetMetricsParser
        def initialize(apps)
          reset
          @apps = apps
        end

        def reset
          @gear = nil
          @saved = ''
          @group = nil
        end

        # Processes output from cgget and sends each metric to Syslog
        #
        # The ouput has the following sequences/types of data
        #
        # HEADER
        # /openshift/$gear_uuid:
        #
        # SINGLE KEY-VALUE PAIR
        # cpu.rt_period_us: 1000000
        #
        # PARENT-CHILD KEY-VALUE PAIRS
        # cpu.stat: nr_periods 6266
        #     nr_throttled 0
        #     throttled_time 0
        #
        # SEPARATOR
        # <a blank line separates gears>
        #
        # This method will take each chunk of output from cgget, keep track
        # of what it is in the middle of processing, and emit individual
        # metrics to Syslog as it sees them.
        #
        def <<(data)
          scanner = StringScanner.new(data)
          loop do
            # look for a newline
            line = scanner.scan_until(/\n/)
            if line.nil?
              # no newline, save what we got and wait for the next call to <<
              @saved += scanner.rest
              break
            end

            # got a full line
            line = @saved + line

            # clear out anything we might have previously saved
            @saved = ''

            # strip off any newline
            line.chomp!

            # HEADER check
            # see if we're looking for the gear
            if @gear.nil?
              # line must be a gear of the form /openshift/$uuid
              @gear = line[0..-2].gsub('/openshift/', '')

              # there may be more data to process, so move on to the next
              # loop iteration
              next
            end

            # SEPARATOR check
            # see if we've reached the end of data for the current gear
            # i.e. a blank line
            if line =~ /^\s*$/
              # clear out the gear
              @gear = nil

              # there may be more data to process, so move on to the next
              # loop iteration
              next
            end

            # CHILD check
            # currently in a group
            if line =~ /^\s/
              key, value = line.split
              publish(key, value)
            else
              # no longer in a group if we previously were
              @group = nil

              key, value = line.split(':')
              value.strip!

              if key == 'cpuacct.usage_percpu'
                # got a line of the form "cpuacct.usage_percpu: 3180064217 3240110361"
                value.split.each_with_index do |usage, i|
                  publish("#{key}.#{i}", usage)
                end
              elsif value =~ /\s/
                # got a line of the form "cpu.stat: nr_periods 6266"
                # so we're now in a group
                @group = "#{key}."

                key, value = value.split
                publish(key, value)
              else
                # not in a group, got a line of the form "cpu.rt_runtime_us: 0"
                publish(key, value)
              end
            end
          end
        end

        def publish(key, value)
          Syslog.info("type=metric app=#{@apps[@gear]} gear=#{@gear} #{@group}#{key}=#{value}")
        end
      end

    end
  end
end
