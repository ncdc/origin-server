require "logstash/inputs/base"
require "logstash/namespace"
require "socket"

#Used to get cgroup data for OpenShift gears or for path
class LogStash::Inputs::Cgroups < LogStash::Inputs::Base
  config_name "cgroups"
  milestone 1

  default :codec, "plain"

  # Interval to get cgroup data
  config :interval, :validate => :number, :required => true

  attr_reader :host, :cgroups_single_metrics, :cgroups_kv_metrics, :cgroups_multivalue_metrics

  def register
    @host = Socket.gethostname

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


    @logger.info("Registering cgroups plugin", :type => @type,
                 :interval => @interval, :path => @path)
  end

  def run(queue)
    while true
      begin
        gear_gecos = `grep "GEAR_GECOS" /etc/openshift/node.conf | cut -d = -f 2 | cut -d '#' -f 1`.strip.gsub(/\"/, '')
        gear_uuids = `grep ":#{gear_gecos}:" /etc/passwd | cut -d: -f1`.split("\n")

        start = Time.now

        processor = CgroupProcessor.new(self, queue)
        #TODO use threads?
        gear_uuids.each do |uuid|
          processor.process_gear(uuid)
        end

        duration = Time.now - start
        sleeptime = [0, @interval - duration].max
        if sleeptime == 0
          logger.info("Execution ran longer than the interval. Skipping sleep.",
                      :duration => duration, :interval => @interval)
        else
          sleep(sleeptime)
        end
      rescue LogStash::ShutdownSignal
        break
      end
    end
    finished
  end

  def enqueue(uuid, key, value, queue)
    event = LogStash::Event.new
    decorate(event)
    event["host"] = @host
    event["gear_uuid"] = uuid
    event[key] = value
    queue << event
  end

  class CgroupProcessor
    def initialize(plugin, queue)
      @plugin = plugin
      @queue = queue
    end

    def process_gear(uuid)
      @uuid = uuid
      @path = "/openshift/#{uuid}"
      get_cgroups_single_metrics
      get_cgroups_kv_metrics
      get_cgroups_multivalue_metrics
    end

    def get_cgroups_single_metrics
      metrics_path = @plugin.cgroups_single_metrics.join(" -r ")
      retrieved_values = `cgget -n -v -r #{metrics_path} #{@path}`.split("\n")
      retrieved_values.each_with_index do |value, index|
        enqueue(@plugin.cgroups_single_metrics[index], value)
      end
    end

    def get_cgroups_kv_metrics
      @plugin.cgroups_kv_metrics.each do |metric|
        get_cgroups_kv_metric(metric)
      end
    end

    def get_cgroups_kv_metric(metric_name)
      lines = `cgget -n -v -r #{metric_name} #{@path}`.split("\n")
      lines.each do |line|
        key, value = line.split(' ')
        enqueue("#{metric_name}.#{key}", value)
      end
    end

    def get_cgroups_multivalue_metrics
      @plugin.cgroups_multivalue_metrics.each do |metric|
        get_cgroups_multivalue_metric(metric)
      end
    end

    def get_cgroups_multivalue_metric(metric_name)
      values = `cgget -n -v -r #{metric_name} #{@path}`.split(' ')
      values.each_with_index do |value, index|
        enqueue("#{metric_name}.#{index}", value)
      end
    end

    def enqueue(key, value)
      @plugin.enqueue(@uuid, key, value, @queue)
    end
  end
end
