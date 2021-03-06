module Fauna
  class Set

    attr_reader :ref

    def initialize(ref)
      @ref = ref
    end

    def page(pagination = {})
      SetPage.find(ref, {}, pagination)
    end

    def events(pagination = {})
      EventsPage.find("#{ref}/events", {}, pagination)
    end

    # query DSL

    def self.query(&block)
      module_eval(&block)
    end

    def self.union(*args)
      QuerySet.new('union', *args)
    end

    def self.intersection(*args)
      QuerySet.new('intersection', *args)
    end

    def self.difference(*args)
      QuerySet.new('difference', *args)
    end

    def self.merge(*args)
      QuerySet.new('merge', *args)
    end

    def self.join(*args)
      QuerySet.new('join', *args)
    end

    def self.match(*args)
      QuerySet.new('match', *args)
    end

    # although each is handled via the query DSL, it might make more
    # sense to add it as a modifier on Set instances, similar to events.

    def self.each(*args)
      EachSet.new(*args)
    end
  end

  class QuerySet < Set
    def initialize(function, *params)
      @function = function
      @params = params
    end

    def param_strings
      @param_strings ||= @params.map do |p|
        if p.respond_to? :expr
          p.expr
        elsif p.respond_to? :ref
          p.ref
        else
          p
        end
      end
    end

    def expr
      @expr ||= "#{@function}(#{param_strings.join ','})"
    end

    def ref
      "query?q=#{expr}"
    end

    def page(pagination = {})
      SetPage.find('query', { 'q' => expr }, pagination)
    end

    def events(pagination = {})
      EventsPage.find("query", { 'q' => "events(#{expr})" }, pagination)
    end
  end

  class EachSet < QuerySet
    def initialize(*params)
      super('each', *params)
    end

    def events(pagination = {})
      query = param_strings.first
      subqueries = param_strings.drop(1).join ','
      EventsPage.find("query", { 'q' => "each(events(#{query}),#{subqueries})" }, pagination)
    end
  end

  class CustomSet < Set
    def add(resource)
      self.class.add(self, resource)
    end

    def remove(resource)
      self.class.remove(self, resource)
    end

    def self.add(set, resource)
      set = set.ref if set.respond_to? :ref
      resource = resource.ref if resource.respond_to? :ref
      Fauna::Client.put("#{set}/#{resource}")
    end

    def self.remove(set, resource)
      set = set.ref if set.respond_to? :ref
      resource = resource.ref if resource.respond_to? :ref
      Fauna::Client.delete("#{set}/#{resource}")
    end
  end

  class SetPage < Fauna::Resource
    include Enumerable

    def refs
      @refs ||= struct['resources']
    end

    def each(&block)
      refs.each(&block)
    end

    def empty?
      refs.empty?
    end

    def length; refs.length end
    def size; refs.size end
  end

  class EventsPage < Fauna::Resource
    include Enumerable

    def events
      @events ||= struct['events'].map { |e| Event.new(e) }
    end

    def each(&block)
      events.each(&block)
    end

    def empty?
      events.empty?
    end

    def length; events.length end
    def size; events.size end
  end

  class Event
    def initialize(attrs)
      @attrs = attrs
    end

    def ref
      "#{resource}/events/#{@attrs['ts']}/#{action}"
    end

    def ts
      Fauna.time_from_usecs(@attrs['ts'])
    end

    def resource
      @attrs['resource']
    end

    def set
      @attrs['set']
    end

    def action
      @attrs['action']
    end
  end
end
