require "logstash/filters/base"
require "logstash/namespace"

# The OpenShift filter is used to retrieve OpenShift gear environment variables
# from a gear's .env directory. For each variable specified in the `variables`
# configuration option, this filter will attempt to read its value and set
# a field on the event.
#
# For example, given this configuration:
#
#     filter {
#       openshift {
#         variables => [ "OPENSHIFT_APP_NAME", "OPENSHIFT_NAMESPACE" ]
#       }
#     }
#
# the filter will attempt to read the values of /var/lib/openshift/%{gear_uuid}/.env/OPENSHIFT_APP_NAME
# and /var/lib/openshift/%{gear_uuid}/.env/OPENSHIFT_NAMESPACE.
class LogStash::Filters::OpenShift < LogStash::Filters::Base
  config_name "openshift"

  milestone 1

  # List of variable names to retrieve from each gear's .env directory
  config :variables, :validate => :array, :required => true

  public
  def register
    # nothing to do
  end

  public
  def filter(event)
    # return nothing unless there's an actual filter event
    return unless filter?(event)

    # make sure we have the gear_uuid field in the event already
    if event['gear_uuid']
      @variables.each do |var|
        path = File.join(%W(/ var lib openshift #{event['gear_uuid']} .env #{var}))
        begin
          value = IO.readlines(path)[0].chomp
          event[var] = value
        rescue => e
          @logger.error? and @logger.error("Error reading #{path}: #{e.message}")
        end
      end
    end

    # filter_matched should go in the last line of our successful code
    filter_matched(event)
  end
end
