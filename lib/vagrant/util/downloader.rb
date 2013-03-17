require "log4r"

require "vagrant/util/busy"
require "vagrant/util/subprocess"

module Vagrant
  module Util
    # This class downloads files using various protocols by subprocessing
    # to cURL. cURL is a much more capable and complete download tool than
    # a hand-rolled Ruby library, so we defer to it's expertise.
    class Downloader
      def initialize(source, destination, options=nil)
        @logger      = Log4r::Logger.new("vagrant::util::downloader")
        @source      = source.to_s
        @destination = destination.to_s

        # Get the various optional values
        options     ||= {}
        @ui          = options[:ui]
      end

      # This executes the actual download, downloading the source file
      # to the destination with the given opens used to initialize this
      # class.
      #
      # If this method returns without an exception, the download
      # succeeded. An exception will be raised if the download failed.
      def download!
        # Build the list of parameters to execute with cURL
        options = [
          "--fail",
          "--output", @destination,
          @source
        ]

        # This variable can contain the proc that'll be sent to
        # the subprocess execute.
        data_proc = nil

        if @ui
          # If we're outputting progress, then setup the subprocess to
          # tell us output so we can parse it out.
          options << { :notify => :stderr }

          # Setup the proc that'll receive the real-time data from
          # the downloader.
          data_proc = Proc.new do |type, data|
            # Type will always be "stderr" because that is the only
            # type of data we're subscribed for notifications.

            # If the data doesn't start with a \r then it isn't a progress
            # notification, so ignore it.
            next if data[0] != "\r"

            # Ignore the first \r and split by whitespace to grab the columns
            columns = data[1..-1].split(/\s+/)

            # COLUMN DATA:
            #
            # 0 - blank
            # 1 - % total
            # 2 - Total size
            # 3 - % received
            # 4 - Received size
            # 5 - % transferred
            # 6 - Transferred size
            # 7 - Average download speed
            # 8 - Average upload speed
            # 9 - Total time
            # 10 - Time spent
            # 11 - Time left
            # 12 - Current speed

            output = "Progress: #{columns[1]}% (Rate: #{columns[12]}/s, Estimated time remaining: #{columns[11]})"
            @ui.clear_line
            @ui.info(output, :new_line => false)
          end
        end

        # Create the callback that is called if we are interrupted
        interrupted  = false
        int_callback = Proc.new do
          @logger.info("Downloader interrupted!")
          interrupted = true
        end

        @logger.info("Downloader starting download: ")
        @logger.info("  -- Source: #{@source}")
        @logger.info("  -- Destination: #{@destination}")

        # Execute!
        result = Busy.busy(int_callback) do
          Subprocess.execute("curl", *options, &data_proc)
        end

        # If the download was interrupted, then raise a specific error
        raise Errors::DownloaderInterrupted if interrupted

        # If we're outputting to the UI, clear the output to
        # avoid lingering progress meters.
        @ui.clear_line if @ui

        # If it didn't exit successfully, we need to parse the data and
        # show an error message.
        if result.exit_code != 0
          @logger.warn("Downloader exit code: #{result.exit_code}")
          parts    = result.stderr.split(/\n*curl:\s+\(\d+\)\s*/, 2)
          parts[1] ||= ""
          raise Errors::DownloaderError, :message => parts[1].chomp
        end

        # Everything succeeded
        true
      end
    end
  end
end
