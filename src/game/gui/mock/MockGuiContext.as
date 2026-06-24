package game.gui.mock
{
   import engine.ability.IAbilityDef;
   import engine.achievement.AchievementDef;
   import engine.battle.SceneListDef;
   import engine.core.RunMode;
   import engine.core.logging.ILogger;
   import engine.core.logging.Log;
   import engine.core.logging.targets.TraceLogTarget;
   import engine.entity.def.EntityIconType;
   import engine.entity.def.IEntityAppearanceDef;
   import engine.entity.def.IEntityClassDef;
   import engine.entity.def.IEntityDef;
   import engine.entity.def.IPurchasableUnit;
   import engine.entity.def.IPartyDef;
   import engine.entity.def.Legend;
   import engine.session.IIapManager;
   import engine.stat.def.StatPurchaseInfo;
   import engine.stat.def.StatType;
   import engine.tourney.TourneyDefList;
   import flash.events.EventDispatcher;
   import flash.events.MouseEvent;
   import game.cfg.BattleHudConfig;
   import game.entity.GameStatCosts;
   import game.gui.GuiIcon;
   import game.gui.IGuiContext;
   import game.gui.IGuiDialog;
   import tbs.srv.data.FriendData;
   import tbs.srv.data.FriendsData;
   import tbs.srv.util.PurchaseCounts;
   import tbs.srv.util.Tourney;
   import tbs.srv.util.TourneyProgressData;
   import tbs.srv.util.TourneyWinnerData;
   import tbs.srv.util.UnlockData;
   
   public class MockGuiContext extends EventDispatcher implements IGuiContext
   {
      
      private var _logger:ILogger = Log.getLogger("MOCK");
      
      private var _battleHudConfig:BattleHudConfig = new BattleHudConfig();
      
      public function MockGuiContext()
      {
         super();
         _logger.addTarget(new TraceLogTarget());
      }
      
      public function get logger() : ILogger
      {
         return _logger;
      }
      
      public function get ready() : Boolean
      {
         return true;
      }
      
      public function set ready(param1:Boolean) : void
      {
         logger.info("MockGuiContext.ready " + param1);
      }
      
      public function playSound(param1:String) : void
      {
         logger.info("MockGuiContext.playSound " + param1);
      }
      
      public function getEntityPortrait(param1:IEntityDef) : GuiIcon
      {
         return null;
      }
      
      public function getEntityIconAtAppIndex(param1:IEntityClassDef, param2:EntityIconType, param3:int) : GuiIcon
      {
         return null;
      }
      
      public function getEntityIcon(param1:IEntityDef, param2:EntityIconType) : GuiIcon
      {
         return null;
      }
      
      public function getAbilityIcon(param1:IAbilityDef) : GuiIcon
      {
         return null;
      }
      
      public function get renown() : int
      {
         return 468;
      }

      public function get party() : IPartyDef
      {
         return null;
      }

      public function setStatsToMinimum(param1:String, param2:Vector.<StatType>) : void
      {
      }
      
      public function purchaseStat(param1:String, param2:StatType, param3:int) : void
      {
      }
      
      public function promote(param1:String, param2:String, param3:String, param4:Function) : void
      {
      }
      
      public function createDialog() : IGuiDialog
      {
         return null;
      }
      
      public function eatEvent(param1:MouseEvent) : void
      {
      }
      
      public function get username() : String
      {
         return "mock_username";
      }
      
      public function get displayname() : String
      {
         return "mock_displayname";
      }
      
      public function removeDialog(param1:IGuiDialog) : void
      {
      }
      
      public function reportUserAbuse(param1:String) : void
      {
      }
      
      public function purchaseStats(param1:String, param2:Vector.<StatPurchaseInfo>) : void
      {
      }
      
      public function getEntityVersusPortrait(param1:IEntityDef) : GuiIcon
      {
         return null;
      }
      
      public function getEntityAppearancePromotePortrait(param1:IEntityAppearanceDef) : GuiIcon
      {
         return null;
      }
      
      public function getEntityPromotePortrait(param1:IEntityDef) : GuiIcon
      {
         return null;
      }
      
      public function setPref(param1:String, param2:*) : void
      {
      }
      
      public function getPref(param1:String) : *
      {
      }
      
      public function translate(param1:String) : String
      {
         return "NOT TRANSLATED";
      }
      
      public function translateRaw(param1:String) : String
      {
         return null;
      }
      
      public function isClassAvailable(param1:String) : Boolean
      {
         return false;
      }
      
      public function getEntityClassPortrait(param1:IEntityDef) : GuiIcon
      {
         return null;
      }
      
      public function getAbilityDef(param1:String) : IAbilityDef
      {
         return null;
      }
      
      public function get randomMaleName() : String
      {
         return null;
      }
      
      public function get randomFemaleName() : String
      {
         return null;
      }
      
      public function purchaseRosterUnit(param1:IPurchasableUnit, param2:Boolean, param3:Function) : void
      {
      }
      
      public function rosterSlotAvailable() : Boolean
      {
         return false;
      }
      
      public function getLargeAbilityIcon(param1:IAbilityDef) : GuiIcon
      {
         return null;
      }
      
      public function getAbilityBuffIcon(param1:IAbilityDef) : GuiIcon
      {
         return null;
      }
      
      public function getAbilityDefById(param1:String) : IAbilityDef
      {
         return null;
      }
      
      public function get friends() : FriendsData
      {
         return null;
      }
      
      public function getFriendAvatar(param1:FriendData, param2:int) : GuiIcon
      {
         return null;
      }
      
      public function get account_id() : int
      {
         return 0;
      }
      
      public function get sceneList() : SceneListDef
      {
         return null;
      }
      
      public function getIcon(param1:String) : GuiIcon
      {
         return null;
      }
      
      public function getTaunts() : Vector.<String>
      {
         return null;
      }
      
      public function translateTaunt(param1:String) : String
      {
         return null;
      }
      
      public function rename(param1:String, param2:String) : void
      {
      }
      
      public function getKillsRequiredToPromote(param1:int) : int
      {
         return 0;
      }
      
      public function getAchievementDef(param1:String) : AchievementDef
      {
         return null;
      }
      
      public function getAwardIcon(param1:String) : GuiIcon
      {
         return null;
      }
      
      public function get iap() : IIapManager
      {
         return null;
      }
      
      public function get currencySymbol() : String
      {
         return null;
      }
      
      public function get currencyCode() : String
      {
         return null;
      }
      
      public function hasUnlock(param1:String) : Boolean
      {
         return false;
      }
      
      public function get purchases() : PurchaseCounts
      {
         return null;
      }
      
      public function getUnlock(param1:String) : UnlockData
      {
         return null;
      }
      
      public function showMarket(param1:Boolean, param2:String, param3:String, param4:Function) : void
      {
      }
      
      public function getCrownChitIcon() : GuiIcon
      {
         return null;
      }
      
      public function getCrownIcon() : GuiIcon
      {
         return null;
      }
      
      public function get statCosts() : GameStatCosts
      {
         return null;
      }
      
      public function getEntityClassPromotePortraitAtAppIndex(param1:IEntityClassDef, param2:int) : GuiIcon
      {
         return null;
      }
      
      public function purchaseVariation(param1:IEntityDef, param2:int) : void
      {
      }
      
      public function get battleHudConfig() : BattleHudConfig
      {
         return _battleHudConfig;
      }
      
      public function tutorialMode() : Boolean
      {
         return false;
      }
      
      public function get tourney() : Tourney
      {
         return null;
      }
      
      public function get tourneyWinner() : TourneyWinnerData
      {
         return null;
      }
      
      public function get tourneyProgress() : TourneyProgressData
      {
         return null;
      }
      
      public function joinTourney(param1:int, param2:Function) : void
      {
      }
      
      public function get tourneyDefList() : TourneyDefList
      {
         return null;
      }
      
      public function replaceTranslatedTokens(param1:String, param2:Array) : String
      {
         return null;
      }
      
      public function get runMode() : RunMode
      {
         return null;
      }
      
      public function get legend() : Legend
      {
         return null;
      }
   }
}

