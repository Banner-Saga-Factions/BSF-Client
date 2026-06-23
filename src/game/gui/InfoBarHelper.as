package game.gui
{
   import engine.ability.IAbilityDef;
   import engine.ability.def.AbilityDefLevel;
   import engine.battle.ability.def.BattleAbilityDefLevels;
   import engine.battle.ability.def.BattleAbilityTag;
   import engine.battle.board.model.IBattleEntity;
   import engine.battle.fsm.state.BattleStateAborted;
   import engine.battle.fsm.state.BattleStateError;
   import engine.battle.sim.IBattleParty;
   import engine.core.logging.ILogger;
   import game.gui.battle.IGuiBattleHud;
   import game.gui.page.BattleHudPage;
   import game.gui.page.BattleHudPageLoadHelper;
   
   public class InfoBarHelper
   {
      
      private var _battleHudPage:BattleHudPage;
      
      private var abilityTextColor:uint = 12823805;
      
      private var defaultTextColor:uint = 14413817;
      
      private var passiveTextColor:uint = 16110508;
      
      public function InfoBarHelper(param1:BattleHudPage)
      {
         super();
         _battleHudPage = param1;
      }
      
      public function updateInfo() : void
      {
         if(!_battleHudPage.board)
         {
            return;
         }
         _battleHudPage.turn = _battleHudPage.fsm.turn;
         var _loc1_:BattleHudPageLoadHelper = _battleHudPage.battleHudPageLoadHelper;
         var _loc4_:IGuiBattleHud = _loc1_.guihud;
         if(!_loc4_.initiative)
         {
            return;
         }
         var _loc2_:BattleStateError = _battleHudPage.fsm.current as BattleStateError;
         if(_loc2_)
         {
            showErrorPage(_loc2_);
            return;
         }
         var _loc3_:BattleStateAborted = _battleHudPage.fsm.current as BattleStateAborted;
         if(_loc3_)
         {
            logger.info("InfoBarHelper.updateInfo BattleStateAborted showAbortedPage()");
            showAbortedPage();
            return;
         }
         if(_battleHudPage.turn)
         {
            _battleHudPage.battleHudPageLoadHelper.guihud.initiative.infobar.text = getEntityAbilityString(_battleHudPage.turn.turnInteract);
         }
      }
      
      private function showErrorPage(param1:BattleStateError) : void
      {
         var _loc2_:IGuiDialog = _battleHudPage.config.gameGuiContext.createDialog();
         _loc2_.init(_battleHudPage.config.gameGuiContext);
         _loc2_.openDialog("Battle Error","An error occurred:\n" + param1.message,"OK",errorDialogCallback);
      }
      
      private function showAbortedPage() : void
      {
         var _loc4_:int = 0;
         var _loc2_:IBattleParty = null;
         var _loc3_:IGuiDialog = _battleHudPage.config.gameGuiContext.createDialog();
         _loc3_.init(_battleHudPage.config.gameGuiContext);
         var _loc1_:String = "The other player";
         if(_battleHudPage.fsm && _battleHudPage.fsm.board)
         {
            _loc4_ = 0;
            while(_loc4_ < _battleHudPage.fsm.board.numParties)
            {
               _loc2_ = _battleHudPage.fsm.board.getParty(_loc4_);
               if(_loc2_.aborted)
               {
                  _loc1_ = _loc2_.partyName;
                  break;
               }
               _loc4_++;
            }
         }
         _loc3_.openDialog("Battle Aborted",_loc1_ + " fled the battlefield in terror.","Typical",abortedDialogCallback);
      }
      
      public function hideAbilityInfo() : void
      {
         _battleHudPage.battleHudPageLoadHelper.guihud.initiative.infobar.setVisible(false);
      }
      
      public function showAbilityInfo() : void
      {
         // [Inference] BSF-Client #12: the original walks guihud.initiative.infobar and
         // turn.ability.def.description with no null-guards; selecting an ability (e.g. siege
         // archer) threw #1009 when a link in that chain was null (the gui-SWF GuiInitiative's
         // infobar can be unset in the offline-AI HUD state). Walk it null-safely; if anything is
         // missing we just skip showing the info bar rather than crash. See Plan-Fix-Issue-12.
         var _loc1_:IGuiBattleHud = _battleHudPage.battleHudPageLoadHelper ? _battleHudPage.battleHudPageLoadHelper.guihud : null;
         var _loc2_:* = _loc1_ ? _loc1_.initiative : null;
         var _loc3_:* = _loc2_ ? _loc2_.infobar : null;
         if(_battleHudPage.turn.ability && _loc3_)
         {
            _loc3_.setVisible(true);
            if(_battleHudPage.turn.ability.def)
            {
               _loc3_.text = _battleHudPage.turn.ability.def.description;
            }
         }
      }
      
      private function getEntityAbilityString(param1:IBattleEntity) : String
      {
         var _loc5_:IAbilityDef = null;
         var _loc4_:BattleAbilityDefLevels = null;
         var _loc3_:AbilityDefLevel = null;
         var _loc2_:String = "";
         if(param1 != null)
         {
            if(param1.def.passives.numAbilities > 0)
            {
               _loc5_ = param1.def.passives.getAbilityDef(0);
               _loc2_ = "<font color=\"#f5d3ac\">";
               _loc2_ += _loc5_.name + " - " + _loc5_.descriptionBrief;
               _loc2_ += "</font>";
            }
            _loc4_ = param1.def.actives as BattleAbilityDefLevels;
            _loc3_ = _loc4_.getFirstAbilityByTag(BattleAbilityTag.SPECIAL);
            if(_loc3_ != null)
            {
               if(_loc2_.length > 0)
               {
                  _loc2_ += "\n";
               }
               _loc2_ += "<font color=\"#c3acfd\">";
               _loc2_ += _loc3_.def.name + " - " + _loc3_.def.descriptionBrief;
               _loc2_ += "</font>";
            }
         }
         return _loc2_;
      }
      
      private function abortedDialogCallback(param1:String) : void
      {
         _battleHudPage.board.scene.focusedBoard = null;
      }
      
      private function errorDialogCallback(param1:String) : void
      {
         _battleHudPage.board.scene.focusedBoard = null;
      }
      
      public function get logger() : ILogger
      {
         return _battleHudPage.logger;
      }
   }
}

