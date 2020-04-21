=begin
Copyright 2018-2020 JDS
All Rights Reserved
THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
License: GPLv2
Author: JD Smith
Organization: 
Name: HideMoreLess
Version: 0.5
SU Version: >=2018
Date: 2020-04-09
Description: Hide all non-direct-ancestor groups & components, down to some depth >=0 (starting at top level)
Usage: Edit/Hide More, Edit/Hide Less.  To cancel, just close the group or component
History:
 0.5 2020-04-09 Auto-disable "Hide Rest of Model", preserve hide depth across saves
 0.4 2019-01-14 Renamed HideMoreLess. Implemented depth-based hiding with multiple model support. Relocated commands under Edit.
 0.3 2018-11-20 Preserve hidden state when directly opening other nested geometry
 0.1 2018-11-19 Written
=end
require "sketchup.rb"
module HideMoreLess
  class << self
    attr_reader :tracker
  end

  # ------
  # Observer: Watch for registered Groups or Components closing, and
  # reset or reapply hidden state, including across the close/open sequence of saves
  class Observer < Sketchup::InstanceObserver
    def initialize(hider)
      @hider=hider
      @hidden=[]
      @openclose={"opened"=>[],"closed"=>[]}
      self.reset
      super()
    end

    def reset(opened:false)
      if opened
        @openclose["opened"]=[]
      else
        @hidden=[]
        @openclose.each {|k,_| @openclose[k]=[]}
      end
    end

    def add(instance,closed:false)
      type=closed ? "closed" : "opened"
      if @openclose[type].empty? ||
         (closed && instance.definition.entities.member?(@openclose[type].last)) ||
         (!closed && @openclose[type].last.definition.entities.member?(instance))
        @openclose[type] << instance
        @hidden << @hider.hidden if closed
      else
        self.reset
      end
    end

    def startSave
      self.reset(opened:true)   # prepare for re-opening!
    end
    
    def checkSave
      if !@openclose["opened"].empty? && !@openclose["closed"].empty? &&
         @openclose["opened"] == @openclose["closed"].last(@openclose["opened"].length).reverse
        @hider.hidden=@hidden[@openclose["opened"].length-1] # restore oldest hidden setting
        @hider.hide
        Sketchup.set_status_text("HideMoreLess: reapplied depth #{@hider.hidden} after Save ")
        self.reset
      end
    end
    
    def onClose(instance)
      self.add(instance,closed:true)
      @hider.unhide(instance)
      if @hider.model.entities.member?(instance) # top-level closed: disable or reapply
        @hider.hide
        Sketchup.set_status_text("HideMoreLess" +
                                 (@hider.hidden ?
                                    ": Reapplied (#{@hider.hidden})" :
                                    " Disabled"))
      end
    end

    def onOpen(instance)
      self.add(instance)
      return unless tr=HideMoreLess.tracker.get(instance.model)
    end 
  end

  # ------
  # SaveObserver: Work around save's habit of closing then re-opening
  class SaveObserver < Sketchup::ModelObserver
    def onPreSaveModel(model) #Comes *after* geometry is closed :(
      return unless tr=HideMoreLess.tracker.get(model)
      tr.observer.startSave
    end

    def onPostSaveModel(model)
      return unless tr=HideMoreLess.tracker.get(model)
      tr.observer.checkSave
    end
  end
  
  # ------
  # Tracker: Create and track a single Hider object for each new model
  # encountered
  class Tracker
    def initialize; @hiders={} end
    def get(model); @hiders[model] ||= Hider.new(model) end
    def destroy; @hiders.each {|_,h| h.destroy} end
  end
  @tracker.destroy if @tracker
  @tracker=Tracker.new

  # ------
  # Hider: Hide all non-ancestors of the currently opened
  # entity of the associated model, down to a given depth (tracked in
  # the hider.hidden variable).  E.g. Depth=0 means hide all top-level
  # non-direct-ancestors.
  class Hider
    attr_accessor :hidden, :observer, :model
    def initialize(model)
      @model=model    # which model we are operating on
      @hidden=false   # hidden state: false, or a depth >=0 (set before calling hide)
      @hideList={}    # store the entities we have hidden
      @observer=HideMoreLess::Observer.new(self) # Instance observer to track closes
      @saveobserver=HideMoreLess::SaveObserver.new
      @model.add_observer(@saveobserver)
    end 

    def destroy
      @observer.reset
      self.unhideall
      @model.remove_observer(@saveobserver)
    end
    
    # hide - Hide non-direct-ancestors to depth @hidden
    def hide                    
      active=@model.active_path
      unless @hidden && active && active.length>1 #need nested geometry >= 2 levels deep
        @hidden=false
        self.unhideall
        return
      end

      @hidden=[@hidden,active.length-1].min  # clip to maximum possible depth
      active.first.hidden=false # Must always show the top-level group/component ancestor

      parent=@model            # Start at the very top level
      for d in 0..@hidden do # Hide all non-ancestors to given depth
        children=parent.entities
        children=children.grep(Sketchup::Group) +
                 children.grep(Sketchup::ComponentInstance)
        break if children.empty? 
        h=@hideList[active[d]]=[] # tag by the still-visible sibling
        children.each do |en|
          unless en==active[d] || !en.layer.visible? || en.hidden?
            en.hidden=true
            h.push(en) # Keep track of it
          end
        end
        parent=active[d].definition
        active[d].add_observer(@observer)
      end
    end

    # unhide - Un-hide non-ancestors associated with some instance
    def unhide(instance)
      if @hideList[instance]
        @hideList[instance].each {|en| en.hidden=false}
      end 
      @hideList.delete(instance)
    end

    # deregister - remove observers from instance
    def deregister(instance)
      instance.remove_observer(@observer) if @observer
    end 
    
    # unhideall - Un-hide and de-register all registered entities
    def unhideall
      @hideList.keys.each do |instance|
        self.unhide(instance)
        self.deregister(instance)
      end
    end
  end

  # ------
  # Create Menu Items
  unless file_loaded?(__FILE__)
    mymenu = UI.menu("Edit")

    item=mymenu.add_item("Hide Less",15) {
      model=Sketchup.active_model
      break unless tr=@tracker.get(model)
      tr.observer.reset
      active=model.active_path
      if tr.hidden && active && active.length>1 
        model.start_operation("Hide Less",true)
        tr.unhideall
        if tr.hidden==0
          tr.hidden=false
          msg="HideMoreLess Disabled"
        else
          tr.hidden-=1
          tr.hide
          msg="HideLess: Depth #{tr.hidden}"
          inactiveHidden=model.rendering_options["InactiveHidden"]
          if inactiveHidden
            model.rendering_options["InactiveHidden"]=false
            msg+=" (hide rest disabled)"
          end
        end
        Sketchup.set_status_text(msg)
        model.commit_operation
      else
        Sketchup.set_status_text("HideMoreLess: Nothing Hidden")
      end     
    }
    mymenu.set_validation_proc(item) {
      tr=@tracker.get(Sketchup.active_model)
      active=Sketchup.active_model.active_path
      tr && tr.hidden && active && active.length>1 ? MF_UNCHECKED : MF_GRAYED
    }
    
    item=mymenu.add_item("Hide More",16) {
      model=Sketchup.active_model
      break unless tr=@tracker.get(model)
      tr.observer.reset # only relevant after Save
      active=model.active_path
      if active && active.length>1
        if tr.hidden && tr.hidden>=active.length-1
          Sketchup.set_status_text("HideMore: At Maximum Depth (#{tr.hidden})")
        else 
          model.start_operation("Hide More",true)
          tr.unhideall
          tr.hidden=tr.hidden ? tr.hidden + 1 : 0
          tr.hide

          msg="HideMore: Depth #{tr.hidden}"
          inactiveHidden=model.rendering_options["InactiveHidden"]
          if inactiveHidden
            model.rendering_options["InactiveHidden"]=false
            msg+=" (hide rest disabled)"
          end
            
          Sketchup.set_status_text(msg)
          model.commit_operation
        end
      else
        Sketchup.set_status_text("HideMoreLess: Nothing to Hide")
      end 
    }
    mymenu.set_validation_proc(item) {
      tr=@tracker.get(Sketchup.active_model)
      active=Sketchup.active_model.active_path
      tr && active && active.length>1 &&
        (!tr.hidden || tr.hidden<active.length-1) ? MF_UNCHECKED : MF_GRAYED
    }

    file_loaded(__FILE__)
  end
end
