package engine.battle.board.view.indicator
{
   import as3isolib.display.IsoSprite;
   import engine.battle.entity.view.EntityView;
   import engine.tile.Tile;
   import flash.display.Sprite;
   import flash.events.TimerEvent;
   import flash.utils.Timer;
   import flash.utils.getTimer;
   
   public class EntityFlyText extends IsoSprite
   {
      
      public static const DURATION:int = 2000;
      
      public static const MAX_ENTRIES:int = 4;
      
      private var entries:Vector.<FlyTextEntry> = new Vector.<FlyTextEntry>();
      
      private var popped:Vector.<FlyTextEntry> = new Vector.<FlyTextEntry>();
      
      private var timer:Timer = new Timer(1000,1);
      
      private var slider:Sprite = new Sprite();
      
      public var view:EntityView;
      
      public var tile:Tile;
      
      private var ids:int;
      
      public function EntityFlyText(param1:EntityView, param2:Tile)
      {
         super("flytext");
         this.view = param1;
         this.tile = param2;
         slider.mouseEnabled = false;
         slider.mouseChildren = false;
         container.mouseEnabled = false;
         container.mouseChildren = false;
         timer.addEventListener("timerComplete",timerCompleteHandler);
         sprites = [slider];
      }
      
      public function push(param1:String, param2:uint, param3:String, param4:int) : void
      {
         var _loc5_:FlyTextEntry = new FlyTextEntry(++ids,this,param1,param2,param3,param4);
         slider.addChild(_loc5_);
         entries.push(_loc5_);
         _loc5_.enter();
         popFirst();
         checkTimer();
      }
      
      public function toString() : String
      {
         return "EntityFlyText [view=" + view + ", tile=" + tile + ", entries=" + entries.length + "]";
      }
      
      public function flyTextEntryCompleteHandler(param1:FlyTextEntry) : void
      {
         var _loc2_:int = popped.indexOf(param1);
         if(_loc2_ > 0)
         {
            popped.splice(_loc2_,1);
         }
      }
      
      protected function timerCompleteHandler(param1:TimerEvent) : void
      {
         popFirst();
         checkTimer();
      }
      
      private function popFirst() : void
      {
         var _loc3_:int = 0;
         if(entries.length == 0)
         {
            return;
         }
         timer.stop();
         var _loc2_:FlyTextEntry = entries[0];
         var _loc1_:int = 0;
         var _loc5_:int = 0;
         for each(var _loc4_ in popped)
         {
            if(_loc4_.isOverlappingY(_loc2_))
            {
               _loc3_ = _loc4_.horizontalMargin + _loc2_.horizontalMargin;
               _loc1_ = Math.min(_loc1_,_loc4_.x - _loc3_);
               _loc5_ = Math.max(_loc5_,_loc4_.x + _loc3_);
            }
         }
         if(Math.abs(_loc1_) <= Math.abs(_loc5_))
         {
            _loc2_.x = _loc1_;
         }
         else
         {
            _loc2_.x = _loc5_;
         }
         popped.push(_loc2_);
         _loc2_.depart();
         entries.splice(0,1);
      }
      
      private function checkTimer() : void
      {
         var _loc3_:FlyTextEntry = null;
         var _loc2_:int = 0;
         var _loc1_:int = 0;
         if(!timer.running)
         {
            if(entries.length > 0)
            {
               _loc3_ = entries[0];
               _loc2_ = getTimer();
               _loc1_ = Math.max(200,_loc3_.timestamp + 2000 - _loc2_);
               timer.reset();
               timer.delay = _loc1_;
               timer.start();
            }
         }
      }
   }
}

import com.greensock.TweenMax;
import com.greensock.easing.Linear;
import com.greensock.easing.Strong;
import engine.gui.core.GuiLabel;
import engine.gui.core.GuiSprite;
import flash.filters.DropShadowFilter;
import flash.utils.getTimer;
// JPEXS artifact fix: file-internal classes (after the package block) don't inherit its imports.
import engine.battle.board.view.indicator.EntityFlyText;

class FlyTextEntry extends GuiSprite
{
   
   private var eft:EntityFlyText;
   
   public var timestamp:int;
   
   private var label:GuiLabel;
   
   private var entered:Boolean;
   
   private var shouldDepart:Boolean;
   
   public var horizontalMargin:int;
   
   public var verticalMargin:int;
   
   public var id:int;
   
   public function FlyTextEntry(param1:int, param2:EntityFlyText, param3:String, param4:uint, param5:String, param6:int)
   {
      super();
      this.eft = param2;
      this.id = param1;
      label = new GuiLabel(param5,param6,param4);
      addChild(label);
      mouseEnabled = false;
      mouseChildren = false;
      label.mouseEnabled = false;
      label.mouseChildren = false;
      timestamp = getTimer();
      label.text = param3;
      label.sizeToContent();
      label.center();
      horizontalMargin = 16 + label.width / 2;
      verticalMargin = 8 + label.height / 2;
      this.cacheAsBitmap = true;
      label.cacheAsBitmap = true;
      this.filters = [new DropShadowFilter(2,122,0,1,1,1,1.5)];
   }
   
   override public function toString() : String
   {
      return "FlyTextEntry [id=" + id + ", label=" + label + ", timestamp=" + timestamp + ", pos=" + x + "," + y + ", margin=" + horizontalMargin + "," + verticalMargin + "]";
   }
   
   public function isOverlapping(param1:FlyTextEntry) : Boolean
   {
      return Math.abs(this.x - param1.x) < this.horizontalMargin + param1.horizontalMargin && Math.abs(this.y - param1.y) < this.verticalMargin + param1.verticalMargin;
   }
   
   public function isOverlappingY(param1:FlyTextEntry) : Boolean
   {
      return Math.abs(this.y - param1.y) < this.verticalMargin + param1.verticalMargin;
   }
   
   public function set scale(param1:Number) : void
   {
      scaleX = scaleY = param1;
   }
   
   public function get scale() : Number
   {
      return scaleX;
   }
   
   public function enter() : void
   {
      alpha = 0;
      scale = 0;
      TweenMax.to(this,0.5,{
         "scale":1,
         "alpha":1,
         "ease":Strong.easeOut
      });
      var _loc1_:Number = label.y - 72;
      TweenMax.to(label,1,{
         "y":_loc1_,
         "ease":Linear.easeOut,
         "onComplete":enterCompleteHandler
      });
   }
   
   public function depart() : void
   {
      if(!entered)
      {
         shouldDepart = true;
         return;
      }
      TweenMax.to(this,2,{
         "y":y - 400,
         "alpha":0,
         "ease":Linear.easeOut,
         "onComplete":tweenCompleteHandler
      });
   }
   
   public function tweenCompleteHandler() : void
   {
      if(parent)
      {
         parent.removeChild(this);
      }
      eft.flyTextEntryCompleteHandler(this);
   }
   
   public function enterCompleteHandler() : void
   {
      entered = true;
      if(shouldDepart)
      {
         depart();
      }
   }
}
