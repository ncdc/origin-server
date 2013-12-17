#!/usr/bin/env oo-ruby
require 'rubygems'
require 'json'
require 'stomp'
require 'fileutils'
require 'openshift-origin-node'
require 'openshift-origin-node/utils/hourglass'

module OpenShift
  module Runtime
    class NodeAgent
      def initialize(client, request_queue, reply_queue)
        @client = client
        @request_queue = request_queue
        @reply_queue = reply_queue
      end

      def get_app_container_from_args(args)
        app_uuid = args['--with-app-uuid'].to_s if args['--with-app-uuid']
        app_name = args['--with-app-name'].to_s if args['--with-app-name']
        gear_uuid = args['--with-container-uuid'].to_s if args['--with-container-uuid']
        gear_name = args['--with-container-name'].to_s if args['--with-container-name']
        namespace = args['--with-namespace'].to_s if args['--with-namespace']
        quota_blocks = args['--with-quota-blocks']
        quota_files  = args['--with-quota-files']
        uid          = args['--with-uid']

        quota_blocks = nil if quota_blocks && quota_blocks.to_s.empty?
        quota_files = nil if quota_files && quota_files.to_s.empty?
        uid = nil if uid && uid.to_s.empty?

        OpenShift::Runtime::ApplicationContainer.new(app_uuid, gear_uuid, uid, app_name, gear_name, namespace, quota_blocks, quota_files, OpenShift::Runtime::Utils::Hourglass.new(235))
      end

      def with_container_from_args(args)
        output = ''
        exitcode = 0
        begin
          container = get_app_container_from_args(args)
          yield(container, output)
        rescue OpenShift::Runtime::Utils::ShellExecutionException => e
          #report_exception e
          output << "\n" unless output.empty?
          output << "Error: #{e.message}" if e.message
          output << "\n#{e.stdout}" if e.stdout.is_a?(String)
          output << "\n#{e.stderr}" if e.stderr.is_a?(String)
          exitcode = e.rc
        rescue Exception => e
          #report_exception e
          Log.instance.error e.message
          Log.instance.error e.backtrace.join("\n")
          exitcode = 1
          output = e.message
        end

        #{exitcode: exitcode, output: output}
        [exitcode, output]
      end

      def app_create(args)
        output = ''
        exitcode = 0
        begin
          token = args.key?('--with-secret-token') ? args['--with-secret-token'].to_s : nil

          container = get_app_container_from_args(args)
          output = container.create(token)
        rescue OpenShift::Runtime::UserCreationException => e
          #report_exception e
          Log.instance.info e.message
          Log.instance.info e.backtrace
          exitcode = 129
          output = e.message
        rescue OpenShift::Runtime::GearCreationException => e
          report_exception e
          Log.instance.info e.message
          Log.instance.info e.backtrace
          exitcode = 146
          output = e.message
        rescue Exception => e
          report_exception e
          Log.instance.info e.message
          Log.instance.info e.backtrace
          exitcode = 1
          output = e.message
        end

        #{exitcode: exitcode, output: output}
        [exitcode, output]
      end

      def execute
        puts "NodeAgent is starting to process requests from #{@request_queue}; replies => #{@reply_queue}"

        msg_count = 0
        @client.subscribe(@request_queue, { :ack => "client", "activemq.prefetchSize" => 1 }) do |msg|
          puts "Got a message: #{msg}"
          content = JSON.load(msg.body)
          puts "Got message: #{content}"

          action = content['action'].gsub('-', '_')
          args = content['args']
          exitcode, output = self.send(action, args)

          result = {
            'exitcode' => exitcode,
            'output' => output
          }
          puts "Sending reply hash: #{result}"
          @client.publish(@reply_queue, JSON.dump(result), {:persistent => true})
          @client.acknowledge(msg)

        end

        loop do
          sleep 1
        end
      end
    end
  end
end

hostname = `hostname`.strip
request_queue = "/queue/mcollective.node.#{hostname}.request"
reply_queue = "/queue/mcollective.node.#{hostname}.reply"

pid = $$
FileUtils.mkdir_p('/tmp/oo-hackday')
pid_file = "/tmp/oo-hackday/nodeagent.pid.#{pid}"

FileUtils.touch(pid_file)

Signal.trap('TERM') do
  begin
    puts "Cleaning up pidfile at #{pid_file}"
    FileUtils.rm_f(pid_file) if File.exist?(pid_file)
  rescue
  ensure
    exit 0
  end
end

opts = { hosts: [ { login: "mcollective", passcode: "marionette", host: 'localhost', port: 6163 } ] }

begin
  ::OpenShift::Runtime::NodeAgent.new(Stomp::Client.new(opts), request_queue, reply_queue).execute
rescue => e
  puts e.message
  puts e.backtrace.join("\n")
ensure
  FileUtils.rm_f(pid_file) if File.exist?(pid_file)
end
