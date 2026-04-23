require 'grpc'
require 'loggregator-api/v2/ingress_services_pb'

class FakeLoggregatorServer
  attr_reader :port

  def initialize(port)
    @port = port
    @envelopes = []
    @mutex = Mutex.new
  end

  def start
    service = FakeIngressService.new(@envelopes, @mutex)
    @server = GRPC::RpcServer.new
    @server.add_http2_port("localhost:#{@port}", :this_port_is_insecure)
    @server.handle(service)
    @thread = Thread.new { @server.run }
    @server.wait_till_running
  end

  def stop
    @server.stop
    @thread.join
  end

  def messages
    @mutex.synchronize { @envelopes.flat_map { |batch| batch.batch.to_a } }
  end

  class FakeIngressService < Loggregator::V2::Ingress::Service
    def initialize(envelopes, mutex)
      @envelopes = envelopes
      @mutex = mutex
    end

    def send(envelope_batch, _call)
      @mutex.synchronize { @envelopes << envelope_batch }
      Loggregator::V2::SendResponse.new
    end
  end
end
