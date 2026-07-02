/**
 * GuiInitiative -- INERT OVERLAY (this code does NOT run at runtime, even with the Wave-1 reroute).
 *
 * Runtime proof (2026-06-23 logs): battle_initiative.swf's OWN copy of this class runs -- it logs
 * "GuiInitiative.init" / "GuiInitiative.setEntities ... nonsetting-start", strings present in NEITHER the
 * raw _decompiled app copy NOR this overlay. The Wave-1 DisplayResourceLoader reroute
 * (battle_initiative.swf -> ApplicationDomain.currentDomain, allowCodeImport=true) did NOT make this
 * app.game.air.swf copy win the symbol linkage -- the gui-SWF copy still binds and runs.
 *
 * The reroute DID fix Crash A, though: across ~4 offline AI battles (turns up to 39, two battles in one
 * session) there were ZERO #1009s, vs. a reliable crash before. [Inference] mechanism: GuiUtil is
 * referenced BY NAME, so in currentDomain the gui-SWF GuiInitiative's GuiUtil.updateDisplayList calls
 * resolve to our GUARDED app GuiUtil (src/game/gui/GuiUtil.as), which absorbs the null child.
 *
 * The frameleft guards below stay SPECULATIVE/inert: they only become load-bearing if the reroute is
 * later switched to allowCodeImport=false to force THIS copy to win. See Plan-Fix-Issue-12.
 */
package game.gui.battle.initiative
{
   import com.greensock.TweenMax;
   import engine.battle.board.model.IBattleEntity;
   import engine.entity.model.IEntity;
   import engine.resource.loader.IDisplayResourceLoader;
   import flash.display.MovieClip;
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.text.TextField;
   import game.gui.ButtonWithIndex;
   import game.gui.GuiBase;
   import game.gui.GuiUtil;
   import game.gui.IGuiContext;
   import game.gui.battle.GuiBattleInfo;
   import game.gui.battle.IGuiBattleInfo;
   import game.gui.battle.IGuiInitiative;
   import game.gui.battle.IGuiInitiativeListener;

   public class GuiInitiative extends GuiBase implements IGuiInitiative
   {

      public var activeFrame:GuiInitiativeActiveFrame;

      public var statFlags:GuiInitiativeStatFlags;

      private var _infobar:GuiBattleInfo;

      private var lowTime:ButtonWithIndex;

      public var order:GuiInitiativeOrder;

      public var entities:Vector.<IBattleEntity>;

      public var partition:int;

      public var round:int;

      public var frameMid:MovieClip;

      public var frameRight:MovieClip;

      public var frameleft:MovieClip;

      public var nameflagPlayer:MovieClip;

      public var nameflagEnemy:MovieClip;

      public var currentNameflag:MovieClip;

      private var listener:IGuiInitiativeListener;

      private var _turnCommited:Boolean;

      private var orderDeployX:int = 10;

      private var orderNormX:int = 131;

      private var deployMode:Boolean = false;

      private var startingParent:Sprite;

      private var unitInfoBanner:GuiInitiativeUnitInfoBanner;

      public function GuiInitiative()
      {
         super();
         visible = false;
      }

      public function get infobar() : IGuiBattleInfo
      {
         return _infobar;
      }

      public function init(param1:IGuiContext, param2:IGuiInitiativeListener, param3:IDisplayResourceLoader) : void
      {
         this.listener = param2;
         initGuiBase(param1);
         startingParent = this.parent as Sprite;
         requireGuiChild("activeFrame");
         requireGuiChild("order");
         frameMid = order.getChildByName("frameMid") as MovieClip;
         frameRight = order.getChildByName("frameRight") as MovieClip;
         frameleft = getChildByName("frameLeft") as MovieClip;
         requireGuiChild("statFlags");
         lowTime = getChildByName("lowTime") as ButtonWithIndex;
         lowTime.mouseEnabled = false;
         lowTime.mouseChildren = false;
         lowTime.visible = false;
         GuiUtil.updateDisplayList(lowTime,this);
         nameflagPlayer.visible = false;
         nameflagPlayer.stop();
         GuiUtil.updateDisplayList(nameflagPlayer,this);
         nameflagEnemy.visible = false;
         nameflagEnemy.stop();
         GuiUtil.updateDisplayList(nameflagEnemy,this);
         nameflagPlayer.x = -nameflagPlayer.width;
         nameflagEnemy.x = -nameflagEnemy.width;
         activeFrame.init(param1);
         order.init(param1);
         statFlags.init(param1,param3);
         activeFrame.addEventListener("change",activeFrameChangeHandler);
         activeFrame.addEventListener("complete",activeFrameCompleteHandler);
         activeFrame.addEventListener("GuiInitiativeActiveFrame.INTERACT",activeFrameInteractHandler);
         order.addEventListener("change",orderChangeHandler);
         orderChangeHandler(null);
         order.addEventListener("GuiInitiativeOrder.INTERACT",orderInteractHandler);
         _infobar = getChildByName("infoBar") as GuiBattleInfo;
         _infobar.init(param1);
         mouseEnabled = false;
         param1.battleHudConfig.addEventListener("BattleHudConfig.EVENT_CHANGED",battleHudConfigHandler);
         unitInfoBanner = getChildByName("unitInfoBanner") as GuiInitiativeUnitInfoBanner;
         unitInfoBanner.init(param1);
         unitInfoBanner.entity = null;
      }

      private function battleHudConfigHandler(param1:Event) : void
      {
      }

      private function activeFrameCompleteHandler(param1:Event) : void
      {
         if(listener)
         {
            listener.guiInitiativeEndTurn();
         }
      }

      public function displayLowOnTime(param1:Number, param2:Number) : void
      {
         lowTime.visible = true;
         GuiUtil.updateDisplayList(lowTime,this);
         resizehandler(param1,param2);
         lowTime.pulseHover(1000);
      }

      private function orderChangeHandler(param1:Event) : void
      {
         var _loc2_:Number = -139;
         frameRight.x = order.x + order.lastX + _loc2_;
         frameMid.scaleX = (frameRight.x - frameMid.x) / 2;
      }

      private function activeFrameChangeHandler(param1:Event) : void
      {
         var _loc2_:int = 1;
         if(deployMode)
         {
            _loc2_ = 0;
         }
         this.order.setOrderEntities(entities,_loc2_);
      }

      public function setInitiativeEntities(param1:Vector.<IBattleEntity>, param2:Boolean) : void
      {
         this.entities = param1;
         if(this.deployMode && !param2)
         {
            order.clearHighlights();
         }
         this.deployMode = param2;
         if(entities && entities.length > 0)
         {
            activeFrame.entity = entities[0];
            activeFrame.updateBuffs(entities[0].effects);
            statFlags.entity = entities[0];
            if(!visible)
            {
               visible = true;
               GuiUtil.updateDisplayList(this,startingParent);
            }
            if(deployMode && statFlags.visible)
            {
               order.x = orderDeployX;
               statFlags.visible = false;
               GuiUtil.updateDisplayList(statFlags,this);
               activeFrame.visible = false;
               GuiUtil.updateDisplayList(activeFrame,this);
               // [Inference] SPECULATIVE guard -- this overlay is INERT at runtime (gui-SWF copy runs;
               // see file header). frameleft = getChildByName("frameLeft") and can be null; guarded in
               // case this copy is ever made live (reroute switched to allowCodeImport=false). The live
               // Crash-A fix is the guarded GuiUtil, not this. See Plan-Fix-Issue-12.
               if(frameleft)
               {
                  frameleft.visible = true;
                  GuiUtil.updateDisplayListAtIndex(frameleft,this,0);
               }
            }
            else if(!deployMode)
            {
               order.x = orderNormX;
               activeFrame.visible = true;
               GuiUtil.updateDisplayListAtIndex(activeFrame,this,1);
               statFlags.visible = true;
               GuiUtil.updateDisplayListAtIndex(statFlags,this,0);
               tweenFlagIn();
               orderChangeHandler(null);
               activeFrameChangeHandler(null);
               // [Inference] Same SPECULATIVE frameleft guard as the deploy branch above; INERT at
               // runtime (gui-SWF copy runs -- see file header). See Plan-Fix-Issue-12.
               if(frameleft && frameleft.visible)
               {
                  frameleft.visible = false;
                  GuiUtil.updateDisplayList(frameleft,this);
               }
            }
         }
         else
         {
            activeFrame.entity = null;
            statFlags.entity = null;
            visible = false;
            GuiUtil.updateDisplayList(this,startingParent);
         }
      }

      private function tweenFlagOut() : void
      {
         if(!currentNameflag)
         {
            return;
         }
         TweenMax.killTweensOf(currentNameflag);
         var _loc1_:TextField = currentNameflag.getChildByName("text") as TextField;
         var _loc3_:Number = -4.5;
         var _loc2_:Number = _loc1_.width - _loc1_.textWidth + _loc3_;
         TweenMax.to(currentNameflag,0.25,{"x":-_loc2_});
      }

      private function tweenFlagIn() : void
      {
         if(currentNameflag)
         {
            TweenMax.killTweensOf(currentNameflag);
            TweenMax.to(currentNameflag,0.25,{
               "x":-currentNameflag.width,
               "onComplete":tweenInCompleteHandler
            });
         }
         else
         {
            tweenInCompleteHandler();
         }
      }

      private function tweenInCompleteHandler() : void
      {
         var _loc1_:TextField = null;
         if(currentNameflag)
         {
            currentNameflag.visible = false;
            GuiUtil.updateDisplayList(currentNameflag,this);
            currentNameflag = null;
         }
         var _loc2_:IEntity = entities.length > 0 ? entities[0] : null;
         if(_loc2_)
         {
            currentNameflag = _loc2_.isPlayer ? nameflagPlayer : nameflagEnemy;
            currentNameflag.visible = true;
            GuiUtil.updateDisplayListAtIndex(currentNameflag,this,0);
            _loc1_ = currentNameflag.getChildByName("text") as TextField;
            _loc1_.text = _loc2_.name;
            tweenFlagOut();
         }
      }

      public function set timerPercent(param1:Number) : void
      {
         activeFrame.timerPercent = param1;
      }

      public function clearEndButton() : void
      {
      }

      public function interact(param1:IBattleEntity, param2:Boolean, param3:Boolean) : void
      {
         order.interact = param1;
         if(order.selectedFrame && param2)
         {
            _infobar.setVisible(true);
            unitInfoBanner.setVisible(false);
            _infobar.displayBuffs(order.selectedFrame);
         }
         else if(param2 && param1)
         {
            _infobar.setVisible(true);
            unitInfoBanner.setVisible(false);
            _infobar.displayBuffs(activeFrame);
         }
         else if(param1 && param3)
         {
            _infobar.setVisible(false);
            unitInfoBanner.setVisible(true);
            unitInfoBanner.entity = param1;
         }
         else
         {
            _infobar.setVisible(false);
            unitInfoBanner.setVisible(false);
         }
      }

      private function activeFrameInteractHandler(param1:Event) : void
      {
         listener.guiInitiativeInteract(activeFrame.entity);
      }

      private function orderInteractHandler(param1:Event) : void
      {
         listener.guiInitiativeInteract(order.interact);
      }

      public function set turnCommitted(param1:Boolean) : void
      {
         _turnCommited = param1;
         activeFrame.canShowTimer = !_turnCommited;
         if(_turnCommited && lowTime.visible)
         {
            lowTime.setStateToNormal();
            lowTime.visible = false;
            GuiUtil.updateDisplayList(lowTime,this);
         }
      }

      public function resizehandler(param1:Number, param2:Number) : void
      {
         lowTime.x = param1 * 0.5 - lowTime.width * 0.5;
      }
   }
}
