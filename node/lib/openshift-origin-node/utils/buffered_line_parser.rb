require "strscan"

module OpenShift
  module Runtime
    module Utils
      class BufferedLineParser
        NEWLINE_REGEX = /\n/

        def initialize(buf_max = 20, line_handler)
          @buf = ""
          @buf_max = buf_max
          @discard_current = false
          @line_handler = line_handler
        end

        def <<(input)
          s = StringScanner.new(input)

          loop do
            line = s.scan_until(NEWLINE_REGEX)

            unless line
              if (@buf.length + s.rest.length) > @buf_max
                @discard_current = true
              else
                @buf += s.rest
              end

              break
            end

            unless @discard_current
              @line_handler.process(@buf + line)
            end

            @discard_current = false
            @buf = ""
          end
        end
      end
    end
  end
end
