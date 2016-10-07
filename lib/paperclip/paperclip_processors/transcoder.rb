module Paperclip
  class Transcoder < Processor

    attr_accessor :time, :dst

    attr_reader :basename, :cli, :meta, :whiny, :convert_options, :format, :geometry, :auto_rotate, :path, :current_format


    def initialize file, options = {}, attachment = nil

      @file                         = file
      @path                         = file.path
      @current_format               = File.extname(path)
      @basename                     = File.basename(path, current_format)
      @cli                          = ::Av.cli
      @meta                         = ::Av.cli.identify(path)
      @whiny                        = options.fetch(:whiny) { true }
      @convert_options              = options.fetch(:convert_options) { { output: {} } }
      @format                       = options.fetch(:format) { current_format }
      @geometry                     = options[:geometry]
      @time                         = options.fetch(:time) { 3 }
      @auto_rotate                  = options.fetch(:auto_rotate) { false }
      @convert_options[:output][:s] = geometry.gsub(/[#!<>)]/, '') if geometry.present? && convert_options[:output][:vf].blank?

      attachment.instance_write(:meta, meta) if attachment

    end

    def make
      ::Av.logger = Paperclip.logger
      cli.add_source(file)
      self.dst = Tempfile.new([basename, ".#{format}"])
      dst.binmode
      meta ? transcode : skip_transcode
      dst
    end

    def transcode
      log "Transcoding supported file #{path}"
      cli.add_source(path)
      cli.add_destination(dst.path)
      cli.reset_input_filters
      configure_image if output_is_image?
      transfer_convert_options
      run
    end

    def skip_transcode
      log "Unsupported file #{path}"
      dst << file.read
      dst.close
    end

    def run
      begin
        cli.run
        log "Successfully transcoded #{basename} to #{dst}"
      rescue Cocaine::ExitStatusError => e
        raise Paperclip::Error, "error while transcoding #{basename}: #{e}" if whiny
      end
    end

    def configure_image
      self.time = time.call(meta, options) if time.respond_to?(:call)
      cli.filter_seek(time)
      cli.filter_rotate(meta[:rotate]) if auto_rotate && !meta[:rotate].nil?
    end

    def transfer_convert_options
      convert_options.slice(:input, :output).each do |key, params|
        params.each do |param|
          param[1] = param[1].call(meta, options) if param[1].respond_to?(:call)
          cli.send(:"add_#{key}_param", param)
        end
      end
    end

    def log message
      Paperclip.log "[transcoder] #{message}"
    end

    def output_is_image?
      !!format.to_s.match(/jpe?g|png|gif$/)
    end
  end

  class Attachment
    def meta
      instance_read(:meta)
    end
  end

end