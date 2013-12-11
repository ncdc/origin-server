require "logstash/inputs/base"
require "logstash/namespace"
require "socket"

#Used to get cgroup data for OpenShift gears or for path
class LogStash::Inputs::Cgroups < LogStash::Inputs::Base
  config_name "cgroups"
  milestone 1

  default :codec, "plain"

  # Iterates through all Gear UUIDs and does cgget for each gear
  config :all, :validate => :boolean, :default => true

  # Interval to get cgroup data
  config :interval, :validate => :number, :required => true

  # If not using all, path will be used
  config :path, :validate => :string, :required => false

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
        if @all
          #TODO use threads?
          gear_uuids.each do |uuid|
            cgroup_name = "/openshift/#{uuid}"
            output = get_cgroup_metrics(cgroup_name)
            push_to_queue(queue, hostname, output, uuid)
          end
        else
          output = get_cgroup_metrics(@path)
          push_to_queue(queue, hostname, output, nil)
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

  private
  def push_to_queue(queue, hostname, output, uuid)
    output.each_with_index do |line, index|
      @codec.decode(line) do |event|
        decorate(event)
        event["host"] = @host
        event["gear_uuid"] = uuid
        queue << event
      end
    end
  end

  def get_cgroup_metrics(path)
    output = []
    output.concat(get_cgroups_single_metric(@cgroups_single_metrics, path))

    @cgroups_kv_metrics.each do |metric|
      output.concat(get_cgroups_kv_metric(metric, path))
    end

    @cgroups_multivalue_metrics.each do |metric|
      output.concat(get_cgroups_multivalue_metric(metric, path))
    end
    output
  end

  def get_cgroups_single_metric(metrics, path)
    output = []
    metrics_path = metrics.join(" -r ")
    retrieved_values = `cgget -n -v -r #{metrics_path} #{path}`.split("\n")
    retrieved_values.each_with_index do |value, index|
      output.push("#{metrics[index]}=#{value}")
    end
    output
  end

  def get_cgroups_multivalue_metric(metric_name, path)
    output = []
    values = `cgget -n -v -r #{metric_name} #{path}`.split(' ')
    values.each_with_index do |value, index|
      output.push("#{metric_name}=#{value}")
    end
    output
  end

  def get_cgroups_kv_metric(metric_name, path)
    output = []
    lines = `cgget -n -v -r #{metric_name} #{path}`.split("\n")
    lines.each do |line|
      key, value = line.split(' ')
      output.push("#{metric_name}.#{key}=#{value}")
    end
    output
  end
end
