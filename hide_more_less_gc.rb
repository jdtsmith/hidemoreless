=begin
Copyright 2018, JDS
All Rights Reserved
THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
License: GPLv2
Author: JD Smith
Organization: 
Name: HideMoreLess
Version: 0.4
SU Version: ?
Date: 2018-11-20
Description: Hide all non-ancestor groups/components, down to some depth >=0 (starting at top level)
Usage: Extensions/Hide More, Extensions/Hide Less.  To cancel, just close the group/component
History:
 0.1 2018-11-19 Written
 0.3 2018-11-20 Preserve hidden state when directly opening other nested geometry
 0.4 2019-01-14 Renamed HideMoreLess and implemented depth-based hiding with multiple model support
=end
require "sketchup.rb"
module HideMoreLess
  class TrackHiders 
    def initialize
      @hiders={}
    end
    
    def get(model)
      @hiders[model]=HideUnhide.new(model) unless @hiders[model] # create if it doesn't exist
      @hiders[model]
    end
  end
  @tracker=TrackHiders.new
      
  class Observer < Sketchup::InstanceObserver
    def onClose(instance)
      model=Sketchup.active_model
      return unless tr=@tracker.get(model)
      tr.unhide(instance) # unhide and de-register this level
      if model.entities.member?(instance) # Top-level closed?  
        tr.hide  # Reapply hidden state
        Sketchup.set_status_text("HideMoreLess" + (tr.hidden ? ": Reapplied (#{tr.hidden})" : " Disabled"))
      end 
    end
  end

  class HideUnhide  
    attr_accessor :hidden
    def initialize(model)
      @model=model    # which model we are operating on
      @hidden=false   # hidden state: false, or a depth >=0; set before calling hide
      @hideList={}    # store the entities we have hidden
    end 
    
    def unhide(instance)
      if @hideList[instance]
        @hideList[instance].each {|en| en.hidden=false}
      end 
      instance.remove_observer(@observer) if @observer
      @hideList.delete(instance)
    end

    def unhideall
      @hideList.keys.each { |instance| self.unhide(instance) }
    end
    
    def hide
      active=@model.active_path
      unless @hidden && active && active.length>1 #need nested geometry >= 2 levels deep
        @hidden=false
        self.unhideall
        return
      end

      @hidden=[@hidden,active.length-1].min if @hidden # clip to maximum depth

      active.first.hidden=false # Always show top-level group/component

      parent=@model
      for d in 0..@hidden do # Hide all non-ancestors to given depth
        next if @hideList[active[d]]
        children=parent.entities
        children=children.grep(Sketchup::Group) +
                 children.grep(Sketchup::ComponentInstance)
        break if children.empty? 
        h=@hideList[active[d]]=[] # tag by the visible sibling
        children.each { |en|
          if en.layer.visible? && en!=active[d] 
            h.push(en) unless en.hidden? # never unhide if already hidden
            en.hidden=true
          end
        }
        parent=active[d].definition
        active[d].add_observer(@observer || (@observer=HideMoreLess::Observer.new))
      end
    end
  end
  
  # Create menu items
  unless file_loaded?(__FILE__)
    mymenu = UI.menu("Plugins").add_submenu("HideMoreLess")

    item=mymenu.add_item("Hide Less") {
      model=Sketchup.active_model
      break unless tr=@tracker.get(model)
      active=model.active_path
      if tr.hidden && active && active.length>1 
        model.start_operation("Hide Less",true)
        tr.unhideall
        if tr.hidden==0
          tr.hidden=false
        else
          tr.hidden-=1
          tr.hide
        end
        Sketchup.set_status_text(tr.hidden ?
                                   "HideLess: Depth #{tr.hidden}":
                                   "HideMoreLess Disabled")
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
    
    item=mymenu.add_item("Hide More") {
      model=Sketchup.active_model
      break unless tr=@tracker.get(model)
      active=model.active_path
      if active && active.length>1
        if tr.hidden && tr.hidden>=active.length-1
          Sketchup.set_status_text("HideMore: At Maximum Depth (#{tr.hidden})")
        else 
          model.start_operation("Hide More",true)
          tr.unhideall
          tr.hidden=tr.hidden ? tr.hidden + 1 : 0
          tr.hide
          Sketchup.set_status_text("HideMore: Depth #{tr.hidden}")
          model.commit_operation
        end
      else
        Sketchup.set_status_text("HideMoreLess: Nothing to Hide")
      end 
    }
    mymenu.set_validation_proc(item) {
      tr=@tracker.get(Sketchup.active_model)
      active=Sketchup.active_model.active_path
      tr && active && active.length>1 && (!tr.hidden || tr.hidden<active.length-1) ?
        MF_UNCHECKED : MF_GRAYED
    }

    file_loaded(__FILE__)
  end
end
