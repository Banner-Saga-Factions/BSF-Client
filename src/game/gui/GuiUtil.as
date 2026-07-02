package game.gui
{
   import flash.display.MovieClip;
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.events.TimerEvent;
   import flash.text.TextField;
   import flash.utils.Dictionary;
   import flash.utils.Timer;
   
   public class GuiUtil
   {
      
      public function GuiUtil()
      {
         super();
      }
      
      public static function delayPlay(param1:Number, param2:MovieClip) : void
      {
         var myTimer:Timer;
         var secs:Number = param1;
         var movie:MovieClip = param2;
         var resume:* = function(param1:TimerEvent):void
         {
            movie.play();
            myTimer.removeEventListener("timer",resume);
         };
         movie.stop();
         myTimer = new Timer(secs * 1000,1);
         myTimer.addEventListener("timer",resume);
         myTimer.start();
      }
      
      public static function delayFunction(param1:Number, param2:Function) : void
      {
         var myTimer:Timer;
         var secs:Number = param1;
         var func:Function = param2;
         var resume:* = function(param1:TimerEvent):void
         {
            func();
            myTimer.removeEventListener("timer",resume);
         };
         if(func == null)
         {
            throw new Error("Argument error function is null");
         }
         myTimer = new Timer(secs * 1000,1);
         myTimer.addEventListener("timer",resume);
         myTimer.start();
      }
      
      private static function playReverse(param1:Event) : void
      {
         var _loc2_:MovieClip = param1.currentTarget as MovieClip;
         if(_loc2_.currentFrame == 1)
         {
            _loc2_.stop();
            _loc2_.removeEventListener("enterFrame",playReverse);
         }
         else
         {
            _loc2_.prevFrame();
         }
      }
      
      public static function stopPlayReverse(param1:MovieClip) : void
      {
         param1.addEventListener("enterFrame",playReverse);
      }
      
      public static function playStopOnFrame(param1:MovieClip, param2:int, param3:Function) : void
      {
         var movieClip:MovieClip = param1;
         var frameToStop:int = param2;
         var callback:Function = param3;
         movieClip.play();
         movieClip.addEventListener("exitFrame",(function():*
         {
            var stop:Function;
            return stop = function():void
            {
               if(movieClip.currentFrame == frameToStop)
               {
                  movieClip.removeEventListener("exitFrame",stop);
                  movieClip.stop();
                  if(callback != null)
                  {
                     callback();
                  }
               }
            };
         })());
      }
      
      public static function playStopOnLastFrame(param1:MovieClip, param2:Function) : void
      {
         playStopOnFrame(param1,param1.totalFrames,param2);
      }
      
      public static function scaleTextToFit(param1:TextField, param2:Number) : void
      {
         var _loc3_:Number = NaN;
         if(param1.textWidth > param2)
         {
            _loc3_ = param1.height;
            param1.width = param1.textWidth + 5;
            param1.scaleX = param1.scaleY = Math.min(1,param2 / param1.textWidth);
            param1.y -= (param1.height - _loc3_) * 0.5;
         }
      }
      
      public static function clone(param1:Dictionary) : Dictionary
      {
         var _loc2_:Dictionary = new Dictionary();
         for(var _loc3_ in param1)
         {
            _loc2_[_loc3_] = param1[_loc3_];
         }
         return _loc2_;
      }
      
      public static function countKeys(param1:Dictionary) : int
      {
         var _loc2_:int = 0;
         for(var _loc3_ in param1)
         {
            _loc2_++;
         }
         return _loc2_;
      }
      
      public static function updateDisplayList(param1:Sprite, param2:Sprite) : void
      {
         // [Inference] BSF-Client #12: also guard a null CHILD (param1). The older gui-SWF copy of
         // GuiInitiative's deploy branch can pass a null child here (its statFlags/activeFrame
         // wiring differs from the app.game.air.swf copy), and "param1.visible" then throws #1009
         // mid-deploy -> battle HUD breaks. A null child means nothing to add/remove, so returning
         // is behavior-preserving. (param2/null-parent was already guarded.) See Plan-Fix-Issue-12.
         if(!param1 || !param2)
         {
            return;
         }
         if(param1.visible)
         {
            param2.addChild(param1);
         }
         else if(param1.parent == param2)
         {
            param2.removeChild(param1);
         }
      }

      public static function updateDisplayListAtIndex(param1:Sprite, param2:Sprite, param3:int) : void
      {
         // [Inference] Same null-child / null-parent guard as updateDisplayList (BSF-Client #12);
         // the gui-SWF GuiInitiative deploy branch uses this for "frameleft", which can be null.
         if(!param1 || !param2)
         {
            return;
         }
         if(param1.visible)
         {
            param2.addChildAt(param1,param3);
         }
         else if(param1.parent == param2)
         {
            param2.removeChild(param1);
         }
      }
   }
}

