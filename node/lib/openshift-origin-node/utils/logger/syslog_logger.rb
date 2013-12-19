#--
# Copyright 2013 Red Hat, Inc.
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

require 'syslog'

module OpenShift
  module Runtime
    module NodeLogger
      #
      # This NodeLogger implementation is backed by the Ruby stdlib +logger+ class.
      #
      # NOTE: The +trace+ method is unimplemented.
      #
      class SyslogLogger
        def initialize(config=nil, context=nil)
          @context = context
          reinitialize
        end

        def reinitialize
          Syslog.open("openshift", Syslog::LOG_PID, Syslog::LOG_USER) unless Syslog.opened?
        end

        def info(*args, &block)
          Syslog.log(Syslog::LOG_INFO, format(*args))
        end

        def debug(*args, &block)
          Syslog.log(Syslog::LOG_DEBUG, format(*args))
        end

        def warn(*args, &block)
          Syslog.log(Syslog::LOG_WARNING, format(*args))
        end

        def error(*args, &block)
          Syslog.log(Syslog::LOG_ERR, format(*args))
        end

        def fatal(*args, &block)
          Syslog.log(Syslog::LOG_CRIT, format(*args))
        end

        def trace(*args, &block)
          # not supported
        end

        private
        def format(*args)
          ctx = @context.map {|k,v| "#{k}:#{v}"}.join(";")
          "[#{ctx}] #{args[0]}"
        end
      end
    end
  end
end
