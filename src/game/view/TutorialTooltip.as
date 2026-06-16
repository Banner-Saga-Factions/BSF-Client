package game.view
{
   import engine.gui.IGuiButton;
   import engine.gui.core.GuiSprite;
   import flash.display.DisplayObject;
   import flash.display.MovieClip;
   import flash.events.Event;
   import flash.geom.Point;
   import flash.geom.Rectangle;
   import flash.text.TextField;

   // JPEXS artifact fix: the CLI decompile of this file was badly corrupted (unrecoverable control
   // flow + invalid bytes). This is the JPEXS *GUI* decompile, which recovered the whole class; the
   // only remaining artifact was in updateWidgetPosition() -- see the comment there. Everything else
   // is verbatim from the decompile.
   public class TutorialTooltip extends GuiSprite
   {

      public static const EVENT_BUTTON:String = "TutorialTooltip.EVENT_BUTTON";

      private static const MARGIN:int = 8;

      private static const SCREEN_MARGIN:int = 20;

      private var tf:TextField;

      private var tt_align:TutorialTooltipAlign;

      private var tt_anchor:TutorialTooltipAnchor;

      private var tt_anchor_offset:Number = 0;

      private var path:String;

      public var layer:TutorialLayer;

      private var block:MovieClip;

      private var bg:MovieClip;

      private var arrow:MovieClip = null;

      private var button:IGuiButton;

      private var ADJUST_THRESHOLD:Number = 0;

      private var attach:DisplayObject;

      public function TutorialTooltip(param1:TutorialLayer, param2:String, param3:TutorialTooltipAlign, param4:TutorialTooltipAnchor, param5:Number, param6:String, param7:Boolean, param8:Boolean, param9:Number)
      {
         super();
         this.ADJUST_THRESHOLD = param9;
         this.layer = param1;
         this.path = param2;
         this.tt_align = param3;
         this.tt_anchor = param4;
         this.tt_anchor_offset = param5;
         this.block = param1.block;
         setupTextField(param6);
         var _loc10_:Point = new Point(0,0);
         _loc10_.x = tf.width + 8 * 2;
         _loc10_.y = tf.height + 8 * 2;
         tf.x = 8;
         tf.y = 8;
         bg = block.getChildByName("bg") as MovieClip;
         bg.scaleX = _loc10_.x / bg.width;
         bg.scaleY = _loc10_.y / bg.height;
         if(param8)
         {
            button = param1.button;
            button.movieClip.x = block.width - button.movieClip.width * 0.3;
            button.movieClip.y = block.height - button.movieClip.height * 0.3;
            block.addChild(button.movieClip);
            button.setDownFunction(buttonHandler);
            button.context = param1.context;
         }
         if(param7)
         {
            arrow = param1.arrow;
            arrow.mouseEnabled = false;
            arrow.mouseChildren = false;
            arrow.x = -1.7976931348623157e+308;
            arrow.y = -1.7976931348623157e+308;
            block.x = -1.7976931348623157e+308;
            block.y = -1.7976931348623157e+308;
            addChild(arrow);
         }
         addChild(block);
      }

      public function cleanup() : void
      {
         if(!attach)
         {
         }
      }

      private function setupTextField(param1:String) : void
      {
         tf = block.getChildByName("text") as TextField;
         tf.width = 1000;
         tf.height = 1000;
         tf.selectable = false;
         tf.mouseEnabled = false;
         tf.htmlText = param1;
         tf.cacheAsBitmap = true;
         tf.width = tf.textWidth + 10;
         tf.height = tf.textHeight + 4;
      }

      public function update() : Boolean
      {
         var _loc9_:Object = null;
         var _loc6_:Rectangle = null;
         var _loc11_:Point = null;
         var _loc8_:Point = null;
         var _loc10_:Point = null;
         var _loc7_:Point = null;
         var _loc3_:int = 0;
         _loc3_ = 60;
         if(!stage || !parent)
         {
            return true;
         }
         if(!attach)
         {
            _loc9_ = layer.findObject(path,false);
            attach = _loc9_ ? _loc9_.object as DisplayObject : null;
         }
         if(!attach || !attach.stage)
         {
            attach = null;
            visible = false;
            return false;
         }
         visible = true;
         if(attach is GuiSprite)
         {
            _loc11_ = attach.localToGlobal(new Point(0,0));
            _loc8_ = this.globalToLocal(_loc11_);
            _loc10_ = attach.localToGlobal(new Point(attach.width,attach.height));
            _loc7_ = this.globalToLocal(_loc10_);
            _loc6_ = new Rectangle(_loc8_.x,_loc8_.y,_loc7_.x - _loc8_.x,_loc7_.y - _loc8_.y);
         }
         else
         {
            _loc6_ = attach.getBounds(this);
         }
         var _loc5_:Number = Number(arrow ? 60 : 0);
         var _loc1_:Number = button ? button.movieClip.height / 2 : 0;
         var _loc2_:Number = 0;
         var _loc4_:Number = 0;
         switch(tt_align)
         {
            case TutorialTooltipAlign.LEFT:
               _loc2_ = -_loc5_;
               break;
            case TutorialTooltipAlign.RIGHT:
               _loc2_ = _loc5_;
               break;
            case TutorialTooltipAlign.TOP:
               _loc4_ = -_loc5_;
               break;
            case TutorialTooltipAlign.BOTTOM:
               _loc4_ = _loc5_;
         }
         updateWidgetPosition(attach,_loc6_,block,block.bg.width,block.bg.height,_loc2_,_loc4_,20);
         if(arrow)
         {
            updateWidgetPosition(attach,_loc6_,arrow,arrow.width,arrow.height,arrow.width / 2,arrow.height / 2,0);
            switch(tt_align)
            {
               case TutorialTooltipAlign.LEFT:
                  arrow.rotation = -90;
                  break;
               case TutorialTooltipAlign.RIGHT:
                  arrow.rotation = 90;
                  break;
               case TutorialTooltipAlign.TOP:
                  arrow.rotation = 0;
                  break;
               case TutorialTooltipAlign.BOTTOM:
                  arrow.rotation = 180;
                  break;
               case TutorialTooltipAlign.CENTER:
               case TutorialTooltipAlign.NONE:
            }
         }
         return true;
      }

      private function updateWidgetPosition(param1:DisplayObject, param2:Rectangle, param3:DisplayObject, param4:Number, param5:Number, param6:Number, param7:Number, param8:Number) : void
      {
         var _loc10_:Point = null;
         var _loc11_:Point = null;
         if(!param3)
         {
            return;
         }
         var _loc12_:Number = param3.x;
         var _loc9_:Number = param3.y;
         // JPEXS artifact fix: the decompiler merged two consecutive switches (on tt_anchor, then
         // tt_align) into one with raw goto-jumps (addr0131) and a spurious nested switch on the
         // first case. Reconstructed as the original two stages: pick the anchor point on the attach
         // rect, then apply the alignment offset.
         switch(tt_anchor)
         {
            case TutorialTooltipAnchor.LEFT:
               _loc12_ = param2.x;
               _loc9_ = param2.y + param2.height / 2;
               break;
            case TutorialTooltipAnchor.RIGHT:
               _loc12_ = param2.right;
               _loc9_ = param2.y + param2.height / 2;
               break;
            case TutorialTooltipAnchor.TOP:
               _loc12_ = param2.x + param2.width / 2;
               _loc9_ = param2.y;
               break;
            case TutorialTooltipAnchor.BOTTOM:
               _loc12_ = param2.x + param2.width / 2;
               _loc9_ = param2.bottom;
               break;
            case TutorialTooltipAnchor.CENTER:
               _loc12_ = param2.x + param2.width / 2;
               _loc9_ = param2.y + param2.height / 2;
               break;
            case TutorialTooltipAnchor.NONE:
               _loc10_ = param1.localToGlobal(new Point(0,0));
               _loc11_ = this.globalToLocal(_loc10_);
               _loc12_ = _loc11_.x;
               _loc9_ = _loc11_.y;
               break;
         }
         switch(tt_align)
         {
            case TutorialTooltipAlign.RIGHT:
               _loc12_ += tt_anchor_offset;
               _loc9_ -= param5 / 2;
               break;
            case TutorialTooltipAlign.LEFT:
               _loc12_ += -param4 + tt_anchor_offset;
               _loc9_ -= param5 / 2;
               break;
            case TutorialTooltipAlign.TOP:
               _loc12_ -= param4 / 2;
               _loc9_ += -param5 + tt_anchor_offset;
               break;
            case TutorialTooltipAlign.BOTTOM:
               _loc12_ -= param4 / 2;
               _loc9_ += tt_anchor_offset;
               break;
            case TutorialTooltipAlign.CENTER:
               _loc12_ -= param4 / 2;
               _loc9_ -= param5 / 2;
               break;
            case TutorialTooltipAlign.NONE:
               break;
         }
         _loc12_ += param6;
         _loc9_ += param7;
         _loc12_ = Math.max(param8,_loc12_);
         _loc12_ = Math.min(parent.width - param4 - param8,_loc12_);
         _loc9_ = Math.max(param8,_loc9_);
         _loc9_ = Math.min(parent.height - param5 - param8,_loc9_);
         if(Math.abs(param3.x - _loc12_) > ADJUST_THRESHOLD)
         {
            param3.x = _loc12_;
         }
         if(Math.abs(param3.y - _loc9_) > ADJUST_THRESHOLD)
         {
            param3.y = _loc9_;
         }
      }

      public function buttonHandler(param1:IGuiButton) : void
      {
         dispatchEvent(new Event("TutorialTooltip.EVENT_BUTTON"));
      }
   }
}
