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

class MetricPlugin < OpenShift::Runtime::WatchmanPlugin
  def initialize(config,gears,restart,operation)
    super(config,gears,restart,operation)
    # Initiallize metrics to run every 60 seconds
    @metrics = ::OpenShift::Runtime::Utils::Cgroups::Metrics.new 60
  end

  def apply(iteration)
    return
  end
end
module OpenShift
  module Runtime
    module Utils
      class Cgroups
        class Metrics
          attr_accessor :delay

          def initialize delay
            Syslog.info "Initializing watchmen metrics plugin"
            # Set the sleep time for the metrics thread
            @delay = delay
            initialize_cgroups_vars
            # Begin collection thread
            start
          end

          # Step that is run on each interval
          def tick
             gear_metric_time = time_method {call_gear_metrics}
             Syslog.info "type=metric gear.metric_time=#{gear_metric_time}\n"
          end

          def start
            Thread.new do
              loop do
                tick
                sleep @delay
              end
            end
          end

          def time_method
            start = Time.now
            yield
            Time.now - start
          end

          def call_gear_metrics
            #We need to make sure we have the most up-to-date list of gears on each run
            output = []
            gear_geco = `grep "GEAR_GECOS" /etc/openshift/node.conf | cut -d = -f 2 | cut -d '#' -f 1`.strip.gsub(/\"/, '')
            @gear_uuids = `grep ":#{gear_geco}:" /etc/passwd | cut -d: -f1`.split("\n")
            @gear_uuids.each do |uuid|
              cgroup_name = "/openshift/#{uuid}"
              output.concat get_cgroup_metrics(cgroup_name)
            end
            output.each { |metric| $stdout.write("type=metric #{metric}\n") }
          end

          def initialize_cgroups_vars

            @cgroups_single_metrics = %w(cpu.cfs_period_us
                              cpu.cfs_quota_us
                              cpu.rt_period_us
                              cpu.rt_runtime_us
                              cpu.shares
                              cpuacct.usage
                              freezer.state
                              memory.failcnt
                              memory.limit_in_bytes
                              memory.max_usage_in_bytes
                              memory.memsw.failcnt
                              memory.memsw.limit_in_bytes
                              memory.memsw.max_usage_in_bytes
                              memory.memsw.usage_in_bytes
                              memory.move_charge_at_immigrate
                              memory.soft_limit_in_bytes
                              memory.swappiness
                              memory.usage_in_bytes
                              memory.use_hierarchy
                              net_cls.classid
                              notify_on_release)

            @cgroups_kv_metrics = %w(cpu.stat
                      cpuacct.stat
                      memory.oom_control
                      memory.stat)

            @cgroups_multivalue_metrics = %w(cpuacct.usage_percpu)


          end

          def get_cgroup_metrics(path)
            output = []

            #one_call_metrics = @cgroups_single_metrics.concat(@cgroups_kv_metrics).concat(@cgroups_multivalue_metrics)
            output.concat(get_cgroups_single_metric(@cgroups_single_metrics, path))
            output.concat(get_cgroups_multivalue_metric(@cgroups_multivalue_metrics, path))
            output.concat(get_cgroups_kv_metric(@cgroups_kv_metrics, path))

            output
          end

          def get_cgroups_single_metric(metrics, path)
            output = []
            joined_metrics = metrics.join(" -r ")
            retrieved_values = execute_cgget(joined_metrics, path).split("\n")
            retrieved_values.each_with_index do |value, index|
              output.push("#{metrics[index]}=#{value}")
            end
            output
          end

          def get_cgroups_multivalue_metric(metrics, path)
            output = []
            joined_metrics = metrics.join(" -r ")
            lines = execute_cgget(joined_metrics, path).split("\n")
            lines.each_with_index do |line, index|
              line.split.each { |value| output.push("#{metrics[index]}=#{value}") }
            end
            output
          end

          def get_cgroups_kv_metric(metrics, path)
            output = []
            joined_metrics = metrics.join(" -r ")
            cg_output = execute_cgget(joined_metrics, path)
            kv_groups = cg_output.split(/\\n(?!\\t)/)
            metric_prefix = ""
            metric_index = 0
            kv_groups.each_with_index do |group, index|
              lines = group.split("\n")
              lines.each_with_index do |line, sub_index|
                key, value = line.split.map { |item| item.strip }
                if sub_index == 0
                  metric_prefix = key
                  output.push("#{metrics[index]}.#{key}=#{value}")
                end
                output.push("#{metrics[index]}.#{metric_prefix}.#{key}=#{value}")
              end
            end
            output
          end

          # This method returns a string to be processed, is it worth wrapping the execute?
          def execute_cgget(metrics, path)
            `cgget -n -v -r #{metrics} #{path}`
          end
        end
      end
    end
  end
end
