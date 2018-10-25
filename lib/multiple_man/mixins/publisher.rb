require 'active_support/core_ext'

module MultipleMan
  module Publisher
    def Publisher.included(base)	
      base.extend(ClassMethods)
      if base.respond_to?(:after_commit)
        base.after_commit(on: :create) { |r| r.publish_record(:create) }
        base.after_commit(on: :update) do |r|		
          if !r.respond_to?(:previous_changes) || r.previous_changes.any? 
            #r.multiple_man_publish(:update) if !(r.previous_changes.keys & r.class.published_fields).blank?
	     				r.publish_record(:update) if !(r.previous_changes.keys & r.class.published_fields).blank?
          end
        end
        base.after_commit(on: :destroy) { |r| r.multiple_man_publish(:destroy) }
      end

      base.class_attribute :multiple_man_publisher
    end

    def multiple_man_publish(operation=:create)
      self.class.multiple_man_publisher.publish(self, operation)
    end
		
		def publish_record(operation=:create)
			dependent_fields = self.class.try(:dependent_fields) || []				
			dependent_fields && dependent_fields.each do |f|
	  			self.send(f).try(:publish_record)
	    end
			self.class.multiple_man_publisher.publish(self, operation)       	    	
	  end
		

    module ClassMethods

      def multiple_man_publish(operation=:create)				
        multiple_man_publisher.publish(self, operation)
      end

      def publish(options = {})
        self.multiple_man_publisher = ModelPublisher.new(options)
      end

      def publish_dependant_fields(dependant_fields = [])

      end

			#def publish_record(operation=:create)
				#self.dependent_fields.each do |f|
	  			#self.send(f).publish_record
	    	#end       
	   # 	multiple_man_publisher.publish(self, operation)
	  #	end
      
    end
  end
end
