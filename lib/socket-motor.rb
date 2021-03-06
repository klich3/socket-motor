require 'em-zeromq'
require 'dripdrop'
require 'logger'
require 'hashie/mash'

Thread.abort_on_exception = true

class SocketMotor < DripDrop::Node
  attr_reader :options

  def self.uuid
    @uuid ||= SpectraUUID.create_random.to_s
  end
   
  def initialize(*args)
    super
    @options  = Hashie::Mash.new
  end
 
  def configure(options={})
    @options.merge! options
    @run_list = @options[:run_list] if @options[:run_list]
  end

  def error_handler(e)
    $stderr.write "SOCKET MOTOR ERROR"
    $stderr.write e.message
    $stderr.write e.backtrace.join("\t\n")
    log_warn(e)
  end
  
  def uuid
    self.class.uuid
  end

  def action
    route :logger_broadcast, :zmq_publish, options.logger_broadcast, :connect

    nodelet :ws_listener, WSListener do |n|
      puts "WS INIT"
      o = options.nodelets.ws_listener
      n.route :ws_in,        :websocket,     o.ws_in
      n.route :channels_in,  :zmq_subscribe, o.channels_in,  :connect, :message_class => SocketMotor::ChannelMessage
      n.route :proxy_out,    :zmq_xreq,      o.proxy_out,    :connect, :message_class => SocketMotor::ReqRepMessage
    end

    nodelet :channel_master, ChannelMaster do |n|
      o = options.nodelets.channel_master
      n.route :channels_out, :zmq_publish,  o.channels_out, :bind, :message_class => SocketMotor::ChannelMessage
      n.route :channels_in,  :zmq_subscribe, o.channels_in,  :bind, :message_class => SocketMotor::ChannelMessage
    end

    nodelet :proxy_master, ProxyMaster do |n|
      o = options.nodelets.proxy_master
      n.route :proxy_in,  :zmq_xrep, o.proxy_in,  :bind, :message_class => SocketMotor::ReqRepMessage
      n.route :proxy_out, :zmq_xreq, o.proxy_out, :bind, :message_class => SocketMotor::ReqRepMessage
    end
  
    nodelet :logger, LogReceiver do |n|
      n.route :logger_in, :zmq_subscribe, options.nodelets.logger.logger_in, :bind
    end
    
    puts "Available Nodelets: #{nodelets.inspect}"
    nodelets.each do |name,nlet|
      puts "Running nodelet: #{name}"
      nlet.run
    end

    puts "Starting #{uuid}"
  end

  # :stopdoc:
  LIBPATH = ::File.expand_path(::File.dirname(__FILE__)) + ::File::SEPARATOR
  PATH = ::File.dirname(LIBPATH) + ::File::SEPARATOR
  VERSION = ::File.read(PATH + 'version.txt').strip
  # :startdoc:

  # Returns the library path for the module. If any arguments are given,
  # they will be joined to the end of the libray path using
  # <tt>File.join</tt>.
  #
  def self.libpath( *args )
    rv =  args.empty? ? LIBPATH : ::File.join(LIBPATH, args.flatten)
    if block_given?
      begin
        $LOAD_PATH.unshift LIBPATH
        rv = yield
      ensure
        $LOAD_PATH.shift
      end
    end
    return rv
  end

  # Returns the lpath for the module. If any arguments are given,
  # they will be joined to the end of the path using
  # <tt>File.join</tt>.
  #
  def self.path( *args )
    rv = args.empty? ? PATH : ::File.join(PATH, args.flatten)
    if block_given?
      begin
        $LOAD_PATH.unshift PATH
        rv = yield
      ensure
        $LOAD_PATH.shift
      end
    end
    return rv
  end

  # Utility method used to require all files ending in .rb that lie in the
  # directory below this file that has the same name as the filename passed
  # in. Optionally, a specific _directory_ name can be passed in such that
  # the _filename_ does not have to be equivalent to the directory.
  #
  def self.require_all_libs_relative_to( fname, dir = nil )
    dir ||= ::File.basename(fname, '.*')
    search_me = ::File.expand_path(
        ::File.join(::File.dirname(fname), dir, '**', '*.rb'))

    require "#{self.libpath}/socket-motor/log_broadcaster"
    Dir.glob(search_me).sort.each {|rb| require rb}
  end

end  # module SocketMotor

SocketMotor.require_all_libs_relative_to(__FILE__)

#This is ugly
class SocketMotor
  include LogBroadcaster
end
