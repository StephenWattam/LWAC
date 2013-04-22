

require 'socket'               # Get sockets from stdlib
require 'lwac/shared/serialiser'

module LWAC

  class RPCServer

    # Create a new server for a given proxy object
    def initialize(proxy, port, serialise_method=:msgpack)
      @proxy = proxy
      @port = port

      # What format to use.
      @serialise_method = serialise_method
    end

    # Start listening forever
    def listen
      @s = TCPServer.open(@port)

      loop{
        handle_client(@s.accept)
      }
    end

  private
    # Handle the protocol for client c
    def handle_client(c)
      m, arity = recv(c)

      # Check the call is valid for the proxy object
      valid_call = (@proxy.respond_to?(m) and @proxy.method(m).arity == arity)

      send(c, valid_call)

      # Make the call if valid and send the result back
      if valid_call then
        args = recv(c)
        send(c, @proxy.send(m, *args) )
      end

      c.close
    end

    # Send obj to client c
    def send(c, obj)
      payload = Serialiser.serialise(obj, @serialise_method)
      c.puts payload.length.to_s
      c.write( payload )
    end

    # Receive data from client c
    def recv(c)
      len = c.gets.chomp.to_i
      buf = ""
      while( len > 0 and x = c.read(len) )
        len -= x.length
        buf += x
      end
      Serialiser.unserialise( x, @serialise_method)
    end
  end


end
