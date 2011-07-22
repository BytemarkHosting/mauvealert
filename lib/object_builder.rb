# ObjectBuilder is a class to help you build Ruby-based configuration syntaxes.
# You can use it to make "builder" classes to help build particular types
# of objects, typically translating simple command-based syntax to creating
# classes and setting attributes.  e.g. here is a description of a day at 
# the zoo:
#   
#   person "Alice"
#   person "Matthew"
#
#   zoo("London") {
#     enclosure("Butterfly House") {
#
#       has_roof
#       allow_visitors
#       
#       animals("moth", 10) {
#         wings 2
#         legs 2
#       }
#
#       animals("butterfly", 200) {
#         wings 2
#         legs 2
#       }
#     }
#
#     enclosure("Aquarium") {
#       no_roof
#
#       animal("killer whale") {
#         called "Shamu"
#         wings 0
#         legs 0
#         tail
#       }
#     }
#   }
#
# Here is the basic builder class for a Zoo...
#
# TODO: finish this convoluted example, if it kills me
#
class ObjectBuilder
  class BuildException < StandardError; end 
  
  attr_reader   :result
  attr_accessor :block_result
  
  def initialize(context, *args)
    @context = context
    @result  = nil
    builder_setup(*args)
  end
  
  def anonymous_name
    @@sequence ||= 0 # not inherited, don't want it to be
    @@sequence  += 1
    "anon.#{Time.now.to_i}.#{@@sequence}"
  end
  
  class << self
  
    def is_builder(word, clazz)
      define_method(word.to_sym) do |*args, &block|
        builder = clazz.new(*([@context] + args))
        builder.instance_eval(&block) if block
        ["created_#{word}", "created"].each do |created_method|
          created_method = created_method.to_sym
          if respond_to?(created_method)
            __send__(created_method, builder.result)
            break
          end
        end
      end
    end
    
    # FIXME: implement is_builder_deferred to create object at end of block?
    
    def is_block_attribute(word)
      define_method(word.to_sym) do |*args, &block|
        @result.__send__("#{word}=".to_sym, block)
      end
    end
    
    def is_attribute(word)
      define_method(word.to_sym) do |*args, &block|
        @result.__send__("#{word}=".to_sym, args[0])
      end
    end
    
    def is_flag_attribute(word)
      define_method(word.to_sym) do |*args, &block|
        @result.__send__("#{word}=".to_sym, true)
      end
    end
  
    def load(file)
      parse(File.read(file), file)
    end
   
    def parse(string, file="string")
      builder = self.new
      begin
        builder.instance_eval(string, file)
      rescue NameError => ex
        # 
        # Ugh.  Catch NameError and re-raise as a BuildException
        #
        f,l = ex.backtrace.first.split(":").first(2)
        if f == file
          build_ex = BuildException.new "Unknown word `#{ex.name}' in #{file} at line #{l}"
          build_ex.set_backtrace ex.backtrace
          raise build_ex
        else
          raise ex
        end
      rescue SyntaxError, ArgumentError => ex
        if ex.backtrace.find{|l| l =~ /^#{file}:(\d+):/}
          build_ex = BuildException.new "#{ex.message} in #{file} at line #{$1}"
          build_ex.set_backtrace ex.backtrace
          raise build_ex
        else
          raise ex
        end
      end

      builder.result
    end
 
    def inherited(*args)
      initialize_class
    end
    
    def initialize_class
      @words = {}
    end
  end
 
  initialize_class
end


