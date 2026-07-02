package game.gui.page
{
   import engine.battle.board.model.IBattleEntity;
   import engine.resource.MovieClipResource;
   import engine.resource.event.ResourceLoadedEvent;
   import flash.display.DisplayObjectContainer;
   import flash.display.MovieClip;
   import flash.events.Event;
   import game.cfg.GameConfig;
   import game.gui.battle.IGuiAbilityPopup;
   import game.gui.battle.IGuiBattleHelp;
   import game.gui.battle.IGuiBattleHud;
   import game.gui.battle.IGuiEnemyPopup;
   import game.gui.battle.IGuiInitiative;
   import game.gui.battle.IGuiMovePopup;
   import game.gui.battle.IGuiOptions;
   import game.gui.battle.IGuiSelfPopup;
   
   public class BattleHudPageLoadHelper
   {
      
      private var guiSelfPopupRes:MovieClipResource;
      
      private var _guiSelfPopup:IGuiSelfPopup;
      
      private var guiMovePopupRes:MovieClipResource;
      
      private var _guiMovePopup:IGuiMovePopup;
      
      private var guiAbilityPopupRes:MovieClipResource;
      
      private var _guiAbilityPopup:IGuiAbilityPopup;
      
      private var guiEnemyPopupRes:MovieClipResource;
      
      private var _guiEnemyPopup:IGuiEnemyPopup;
      
      private var _guihud:IGuiBattleHud;
      
      private var rhud:MovieClipResource;
      
      private var _battleHelp:IGuiBattleHelp;
      
      private var rBattleHelp:MovieClipResource;
      
      private var rinitiative:MovieClipResource;
      
      private var _initiative:IGuiInitiative;
      
      private var rOptions:MovieClipResource;
      
      private var _options:IGuiOptions;
      
      private var rBattleGo:MovieClipResource;
      
      private var _battleGo:MovieClip;
      
      private var rBattlePillage:MovieClipResource;
      
      private var battlePillage:MovieClip;
      
      private var rBattlePillage2:MovieClipResource;
      
      private var battlePillage2:MovieClip;
      
      private var rForgeAhead:MovieClipResource;
      
      private var forgeAhead:MovieClip;
      
      private var rForgeAheadPillage:MovieClipResource;
      
      private var forgeAheadPillage:MovieClip;
      
      private var battleHudPage:BattleHudPage;
      
      private var config:GameConfig;
      
      private var initiativeEntities:Vector.<IBattleEntity>;
      
      private var initiativeDeployMode:Boolean;
      
      private var parentPlayPillageOnce:DisplayObjectContainer;
      
      private var parentPlayPillage2Once:DisplayObjectContainer;
      
      private var parentPlayForgeAheadOnce:DisplayObjectContainer;
      
      private var parentPlayForgeAheadPillageOnce:DisplayObjectContainer;
      
      public function BattleHudPageLoadHelper(param1:BattleHudPage, param2:GameConfig)
      {
         super();
         this.battleHudPage = param1;
         this.config = param2;
         guiSelfPopupRes = param1.getGuiPageResource("battle_self_popup.swf/gui.self_popup");
         guiSelfPopupRes.addResourceListener(selfPopupLoadedHandler);
         guiMovePopupRes = param1.getGuiPageResource("battle_self_popup.swf/gui.move_popup");
         guiMovePopupRes.addResourceListener(movePopupLoadedHandler);
         guiAbilityPopupRes = param1.getGuiPageResource("battle_self_popup.swf/gui.ability_popup");
         guiAbilityPopupRes.addResourceListener(abilityPopupLoadedHandler);
         guiEnemyPopupRes = param1.getGuiPageResource("battle_enemy_popup.swf/gui_enemy_popup");
         guiEnemyPopupRes.addResourceListener(enemyPopupLoadedHandler);
         rhud = param1.getGuiPageResource("battle.swf/gui.battle_hud");
         rhud.addResourceListener(hudLoadedHandler);
         rBattleHelp = param1.getGuiPageResource("battle.swf/gui.battle.help");
         rBattleHelp.addResourceListener(battleHelpHandler);
         rinitiative = param1.getGuiPageResource("battle_initiative.swf/gui.battle_initiative");
         rinitiative.addResourceListener(initiativeLoadedHandler);
         rOptions = param1.getGuiPageResource("battle.swf/gui.battle.options");
         rOptions.addResourceListener(optionsLoadedHandler);
         rBattleGo = param1.getGuiPageResource("go_battle.swf/assets.battle_text");
         rBattleGo.addResourceListener(battleGoLoadedHandler);
         rBattlePillage = param1.getGuiPageResource("go_pillage.swf/assets.pillage_text");
         rBattlePillage.addResourceListener(battlePillageLoadedHandler);
         rBattlePillage2 = param1.getGuiPageResource("go_pillage2.swf/assets.pillage_text");
         rBattlePillage2.addResourceListener(battlePillage2LoadedHandler);
         rForgeAhead = param1.getGuiPageResource("forge_ahead.swf/forgeahead_normal_gethit");
         rForgeAhead.addResourceListener(forgeAheadLoadedHandler);
         rForgeAheadPillage = param1.getGuiPageResource("forge_ahead.swf/forgeahead_pillage_gethit");
         rForgeAheadPillage.addResourceListener(forgeAheadPillageLoadedHandler);
         param1.getGuiPageResource("match_resolution.swf/assets.match_resolution");
      }
      
      public function get battleHelp() : IGuiBattleHelp
      {
         return _battleHelp;
      }
      
      public function get guiAbilityPopup() : IGuiAbilityPopup
      {
         return _guiAbilityPopup;
      }
      
      public function get guiMovePopup() : IGuiMovePopup
      {
         return _guiMovePopup;
      }
      
      public function set guihud(param1:IGuiBattleHud) : void
      {
         _guihud = param1;
      }
      
      public function set battleGo(param1:MovieClip) : void
      {
         _battleGo = param1;
      }
      
      public function get battleGo() : MovieClip
      {
         return _battleGo;
      }
      
      private function battleGoLoadedHandler(param1:ResourceLoadedEvent) : void
      {
         if(rBattleGo.ok)
         {
            _battleGo = rBattleGo.movieClip;
            _battleGo.mouseEnabled = _battleGo.mouseChildren = false;
            battleGo.stop();
         }
      }
      
      public function playPillageOnce(param1:DisplayObjectContainer) : void
      {
         parentPlayPillageOnce = param1;
         checkPlayPillage();
      }
      
      public function playPillage2Once(param1:DisplayObjectContainer) : void
      {
         parentPlayPillage2Once = param1;
         checkPlayPillage2();
      }
      
      public function playForgeAheadOnce(param1:DisplayObjectContainer) : void
      {
         parentPlayForgeAheadOnce = param1;
         checkForgeAhead();
      }
      
      public function playForgeAheadPillageOnce(param1:DisplayObjectContainer) : void
      {
         parentPlayForgeAheadPillageOnce = param1;
         checkForgeAheadPillage();
      }
      
      public function checkPlayPillage() : void
      {
         if(battlePillage && parentPlayPillageOnce)
         {
            parentPlayPillageOnce.addChild(battlePillage);
            battlePillage.x = parentPlayPillageOnce.width / 2;
            battlePillage.y = parentPlayPillageOnce.height / 2;
            parentPlayPillageOnce = null;
            battlePillage.addEventListener("enterFrame",battlePillageEnterFrameHandler);
            battlePillage.gotoAndPlay(1);
         }
      }
      
      public function checkPlayPillage2() : void
      {
         if(battlePillage2 && parentPlayPillage2Once)
         {
            parentPlayPillage2Once.addChild(battlePillage2);
            battlePillage2.x = 0;
            battlePillage2.y = parentPlayPillage2Once.height;
            parentPlayPillage2Once = null;
            battlePillage2.addEventListener("enterFrame",battlePillage2EnterFrameHandler);
            battlePillage2.gotoAndPlay(1);
         }
      }
      
      public function checkForgeAhead() : void
      {
         if(forgeAhead && parentPlayForgeAheadOnce)
         {
            parentPlayForgeAheadOnce.addChild(forgeAhead);
            forgeAhead.x = 0;
            forgeAhead.y = parentPlayForgeAheadOnce.height;
            parentPlayForgeAheadOnce = null;
            forgeAhead.addEventListener("enterFrame",forgeAheadEnterFrameHandler);
            forgeAhead.gotoAndPlay(1);
         }
      }
      
      public function checkForgeAheadPillage() : void
      {
         if(forgeAheadPillage && parentPlayForgeAheadPillageOnce)
         {
            parentPlayForgeAheadPillageOnce.addChild(forgeAheadPillage);
            forgeAheadPillage.x = 0;
            forgeAheadPillage.y = parentPlayForgeAheadPillageOnce.height;
            parentPlayForgeAheadPillageOnce = null;
            forgeAheadPillage.addEventListener("enterFrame",forgeAheadPillageEnterFrameHandler);
            forgeAheadPillage.gotoAndPlay(1);
         }
      }
      
      private function battlePillageEnterFrameHandler(param1:Event) : void
      {
         if(battlePillage && battlePillage.currentFrame == battlePillage.framesLoaded)
         {
            battlePillage.stop();
            battlePillage.parent.removeChild(battlePillage);
            battlePillage = null;
         }
      }
      
      private function battlePillage2EnterFrameHandler(param1:Event) : void
      {
         if(battlePillage2 && battlePillage2.currentFrame == battlePillage2.framesLoaded)
         {
            battlePillage2.stop();
            battlePillage2.parent.removeChild(battlePillage2);
            battlePillage2 = null;
         }
      }
      
      private function forgeAheadEnterFrameHandler(param1:Event) : void
      {
         if(forgeAhead && forgeAhead.currentFrame == forgeAhead.framesLoaded)
         {
            forgeAhead.stop();
         }
      }
      
      private function forgeAheadPillageEnterFrameHandler(param1:Event) : void
      {
         if(forgeAheadPillage && forgeAheadPillage.currentFrame == forgeAheadPillage.framesLoaded)
         {
            forgeAheadPillage.stop();
         }
      }
      
      private function battlePillageLoadedHandler(param1:ResourceLoadedEvent) : void
      {
         if(rBattlePillage.ok)
         {
            battlePillage = rBattlePillage.movieClip;
            battlePillage.mouseEnabled = battlePillage.mouseChildren = false;
            battlePillage.stop();
            checkPlayPillage();
         }
      }
      
      private function battlePillage2LoadedHandler(param1:ResourceLoadedEvent) : void
      {
         if(rBattlePillage2.ok)
         {
            battlePillage2 = rBattlePillage2.movieClip;
            battlePillage2.mouseEnabled = battlePillage2.mouseChildren = false;
            battlePillage2.stop();
            checkPlayPillage2();
         }
      }
      
      private function forgeAheadLoadedHandler(param1:ResourceLoadedEvent) : void
      {
         if(rForgeAhead.ok)
         {
            forgeAhead = rForgeAhead.movieClip;
            forgeAhead.mouseEnabled = forgeAhead.mouseChildren = false;
            forgeAhead.stop();
            checkForgeAhead();
         }
      }
      
      private function forgeAheadPillageLoadedHandler(param1:ResourceLoadedEvent) : void
      {
         if(rForgeAheadPillage.ok)
         {
            forgeAheadPillage = rForgeAheadPillage.movieClip;
            forgeAheadPillage.mouseEnabled = forgeAheadPillage.mouseChildren = false;
            forgeAheadPillage.stop();
            checkForgeAheadPillage();
         }
      }
      
      private function optionsLoadedHandler(param1:ResourceLoadedEvent) : void
      {
         if(rOptions.ok)
         {
            _options = rOptions.movieClip as IGuiOptions;
            options.init(config.gameGuiContext,battleHudPage);
            battleHudPage.addChild(options as MovieClip);
         }
      }
      
      private function movePopupLoadedHandler(param1:ResourceLoadedEvent) : void
      {
         if(this.guiMovePopupRes.ok)
         {
            _guiMovePopup = guiMovePopupRes.movieClip as IGuiMovePopup;
            _guiMovePopup.init(config.gameGuiContext,battleHudPage);
            battleHudPage.addChild(_guiMovePopup.movieClip);
            battleHudPage.checkPopupHelper();
         }
      }
      
      private function abilityPopupLoadedHandler(param1:ResourceLoadedEvent) : void
      {
         if(this.guiAbilityPopupRes.ok)
         {
            _guiAbilityPopup = guiAbilityPopupRes.movieClip as IGuiAbilityPopup;
            _guiAbilityPopup.init(config.gameGuiContext,battleHudPage);
            battleHudPage.addChild(_guiAbilityPopup.movieClip);
            battleHudPage.checkPopupHelper();
         }
      }
      
      private function selfPopupLoadedHandler(param1:ResourceLoadedEvent) : void
      {
         if(guiSelfPopupRes.ok)
         {
            _guiSelfPopup = guiSelfPopupRes.movieClip as IGuiSelfPopup;
            battleHudPage.addChild(_guiSelfPopup.movieClip);
            _guiSelfPopup.init(config.gameGuiContext,battleHudPage);
            battleHudPage.checkPopupHelper();
         }
      }
      
      private function enemyPopupLoadedHandler(param1:ResourceLoadedEvent) : void
      {
         if(guiEnemyPopupRes.ok)
         {
            _guiEnemyPopup = guiEnemyPopupRes.movieClip as IGuiEnemyPopup;
            battleHudPage.addChild(_guiEnemyPopup.movieClip);
            _guiEnemyPopup.init(config.gameGuiContext,battleHudPage);
            battleHudPage.checkPopupHelper();
         }
      }
      
      private function battleHelpHandler(param1:ResourceLoadedEvent) : void
      {
         if(rBattleHelp.ok)
         {
            _battleHelp = rBattleHelp.movieClip as IGuiBattleHelp;
            _battleHelp.init(config.gameGuiContext);
         }
      }
      
      private function hudLoadedHandler(param1:ResourceLoadedEvent) : void
      {
         if(rhud.ok)
         {
            _guihud = rhud.movieClip as IGuiBattleHud;
            battleHudPage.addChild(_guihud.movieClip);
            _guihud.movieClip.cacheAsBitmap = true;
            _guihud.init(config.gameGuiContext,battleHudPage,battleHudPage);
            _guihud.initiative = initiative;
         }
      }
      
      private function initiativeLoadedHandler(param1:ResourceLoadedEvent) : void
      {
         if(rinitiative.ok)
         {
            _initiative = rinitiative.movieClip as IGuiInitiative;
            if(_guihud)
            {
               _guihud.initiative = initiative;
            }
            _initiative.init(config.gameGuiContext,battleHudPage,rinitiative.swfResource.displayLoader);
            checkInitiativeEntities();
         }
         else
         {
            config.logger.error("BattleHudPageLoadHelper FAILED " + rinitiative);
         }
      }
      
      public function setInitiativeEntities(param1:Vector.<IBattleEntity>, param2:Boolean) : void
      {
         initiativeEntities = param1;
         initiativeDeployMode = param2;
         checkInitiativeEntities();
      }
      
      private function checkInitiativeEntities() : void
      {
         // [Inference] BSF-Client #12 finding #2: the initiative SWF can finish loading
         // before any entities exist (initiativeEntities defaults to null). The runtime
         // copy of GuiInitiative that lives inside gui\battle_initiative.swf crashes
         // (TypeError #1009 in GuiUtil.updateDisplayList) in its empty/"nonsetting" branch
         // on this initial setInitiativeEntities(null) call, which kills the whole battle
         // HUD -> deploy controls never work -> battle stuck in BattleStateDeploy. The
         // original game survives the same null call via load-order timing; the offline
         // AI-battle path (AiBattleLoadState) hits it. Guarding null here keeps the bar at
         // its default-hidden state; the real, populated call runs later. Empty (length 0)
         // vectors are a legitimate "hide the bar" signal and still pass through.
         // Evidence: A-8.log-AI-battle-failed.txt (GuiInitiative.setEntities null -> #1009).
         if(_initiative && initiativeEntities)
         {
            _initiative.setInitiativeEntities(initiativeEntities,initiativeDeployMode);
         }
      }
      
      public function get options() : IGuiOptions
      {
         return _options;
      }
      
      public function get guiSelfPopup() : IGuiSelfPopup
      {
         return _guiSelfPopup;
      }
      
      public function get guiEnemyPopup() : IGuiEnemyPopup
      {
         return _guiEnemyPopup;
      }
      
      public function get initiative() : IGuiInitiative
      {
         return _initiative;
      }
      
      public function get guihud() : IGuiBattleHud
      {
         return _guihud;
      }
   }
}

