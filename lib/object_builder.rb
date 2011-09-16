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
 
  # Generates a new builder
  # 
  # @param [ObjectBuidler] context The level of the builder
  # @param [Array] args The arguments to pass on to the builder_setup
  #
  def initialize(context, *args)
    @context = context
    @result  = nil
    builder_setup(*args)
  end
  
  # Generates an anonymous name
  #
  # @return [String]
  def anonymous_name
    @@sequence ||= 0 # not inherited, don't want it to be
    @@sequence  += 1
    "anon.#{Time.now.to_i}.#{@@sequence}"
  end
  
  class << self
  
    # Defines a new builder
    #
    # @param [String] word The builder's name
    # @param [Class] clazz The Class the builder represents
    #
    # @macro [attach] is_builder
    #   @return The +$1+ builder.
    #
    # @return [NilClass]
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

      return nil
    end
    
    # FIXME: implement is_builder_deferred to create object at end of block?
    
    # Defines a new block attribute
    # @param [String] word The block attribute's name
    # @macro [attach] is_block_attribute
    #   @return [NilClass] Allows use of the +$1+ word to define a block.
    def is_block_attribute(word)
      define_method(word.to_sym) do |*args, &block|
        @result.__send__("#{word}=".to_sym, block)
      end
    end
   
    # Defines a new attribute
    # @param [String] word The attribute's name
    # @macro [attach] is_attribute
    #   @return [NilClass] Allows use of the +$1+ word to set an attribute.
    #
    def is_attribute(word)
      define_method(word.to_sym) do |*args, &block|
        @result.__send__("#{word}=".to_sym, args[0])
      end
    end
    
    # Defines a new boolean attribute
    # @param [String] word The boolean attribute's name
    # @macro [attach] is_flag_attribute
    #   @return [NilClass] Allows use of the +$1+ word to set an boolean attribute.
    def is_flag_attribute(word)
      define_method(word.to_sym) do |*args, &block|
        @result.__send__("#{word}=".to_sym, true)
      end
    end
  
    # Loads a new file
    # 
    # @param [String] file
    def load(file)
      parse(File.read(file), file)
    end
   
    # Parses a string
    #
    # @param [String] string The string to parse
    # @param [String] file The filename that the string was read from, for helpful error messages.
    #
    # @raise [BuildException] When an expected exception is raised
    # @raise [NameError]
    # @raise [SyntaxError] 
    # @raise [ArgumentError]
    #
    # @return [ObjectBuidler] The 
    def parse(string, file="string")
      builder = self.new
      builder.instance_eval(string, file)
      builder.result
    rescue NameError, NoMethodError => ex
      # 
      # Ugh.  Catch NameError and re-raise as a BuildException
      #
      if ex.backtrace.find{|l| l =~ /^#{file}:(\d+):/}
        build_ex = BuildException.new "Unknown word `#{ex.name}' in #{file} at line #{$1}"
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
 
    def inherited(*args)
      initialize_class
    end
    
    def initialize_class
      @words = {}
    end
  end
 
  initialize_class
end


