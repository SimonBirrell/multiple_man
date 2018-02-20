module MultipleMan
  module Producers
    class General
      def run_producer
        MultipleMan.logger.info "Starting producer"

        require_relative '../outbox/db'
        require_relative '../outbox/message/sequel'

        last_run = Time.now
        loop do
          timeout(last_run)
          Connection.connect { |connection| produce_all(connection) }
          last_run = Time.now
        end
      end

      private

      # We are grouping by model because it allows us to reduce the amount of
      # confirms while still preserving the respective model messages ordering.
      # For example
      # [
      #   [ModelA_message_1, ModelA_message_2],
      #   [ModelB_message_1, ModelB_message_2]
      # ]
      # Allows us to:
      #
      # On iteration 1: published & confirm ModelA_message_1 and ModelB_message_1
      # On iteration 2: published & confirm ModelA_message_2 and ModelB_message_2
      # ...
      # iteration K: ModelA_message_K and ModelB_message_K are published & confirm
      # This will require at most K confirms where K is the largest amount of
      # messages / model. This is better than processing messages serially which
      # requires 1 confirm per message.
      def produce_all(connection)
        Outbox::Message::Sequel.in_batches_and_delete(batch_size) do |messages|
          grouped_messages = group_by_model(messages)

          while grouped_messages.any?
            sent_messages = send_messages!(grouped_messages, connection)
            confirm_published!(sent_messages, connection) if sent_messages
            remove_empty_lists!(grouped_messages)
          end
        end
      end

      def remove_empty_lists!(grouped_messages)
        grouped_messages.reject! { |m| m.empty? }
      end

      def send_messages!(grouped_messages, connection)
        grouped_messages.each_with_object([]) do |messages, sent_messages|
          next if messages.empty?

          message = messages.delete_at(0)
          publish(connection, message)
          sent_messages << message
        end
      end

      def confirm_published!(messages, connection)
        channel = connection.channel
        raise ProducerError.new(channel.nacked_set.to_a) unless channel.wait_for_confirms

        MultipleMan.logger.debug("published #{messages.size} messages")
      end

      def group_by_model(messages)
        grouped_messages = Hash.new { |h, k| h[k] = [] }
        messages.each do |message|
          model_name = RoutingKey.model_name(message.routing_key)
          grouped_messages[model_name] << message
        end
        grouped_messages.values
      end

      def publish(connection, message)
        connection.topic.publish(
          message.values[:payload],
          routing_key: message.values[:routing_key],
          persistent:  true,
          headers:     { published_at: Time.now.to_i }
        )
      end

      def timeout(last_run)
        sleep_time      = MultipleMan.configuration.producer_sleep_timeout
        time_since_last = Time.now - last_run
        sleep_time      = sleep_time - time_since_last

        sleep sleep_time if time_since_last < sleep_time
      end

      def batch_size
        MultipleMan.configuration.producer_batch_size
      end
    end
  end
end
