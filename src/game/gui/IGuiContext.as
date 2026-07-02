package game.gui
{
   import engine.ability.IAbilityDef;
   import engine.achievement.AchievementDef;
   import engine.battle.SceneListDef;
   import engine.core.RunMode;
   import engine.core.logging.ILogger;
   import engine.entity.def.EntityIconType;
   import engine.entity.def.IEntityAppearanceDef;
   import engine.entity.def.IEntityClassDef;
   import engine.entity.def.IEntityDef;
   import engine.entity.def.IPartyDef;
   import engine.entity.def.IPurchasableUnit;
   import engine.entity.def.Legend;
   import engine.session.IIapManager;
   import engine.tourney.TourneyDefList;
   import flash.events.IEventDispatcher;
   import flash.events.MouseEvent;
   import game.cfg.BattleHudConfig;
   import game.entity.GameStatCosts;
   import tbs.srv.data.FriendData;
   import tbs.srv.data.FriendsData;
   import tbs.srv.util.PurchaseCounts;
   import tbs.srv.util.Tourney;
   import tbs.srv.util.TourneyProgressData;
   import tbs.srv.util.TourneyWinnerData;
   import tbs.srv.util.UnlockData;
   
   public interface IGuiContext extends IEventDispatcher
   {
      
      function get account_id() : int;
      
      function get username() : String;
      
      function get displayname() : String;
      
      function get logger() : ILogger;
      
      function get ready() : Boolean;
      
      function set ready(param1:Boolean) : void;
      
      function playSound(param1:String) : void;
      
      function getAchievementDef(param1:String) : AchievementDef;
      
      function getEntityClassPortrait(param1:IEntityDef) : GuiIcon;
      
      function getEntityIconAtAppIndex(param1:IEntityClassDef, param2:EntityIconType, param3:int) : GuiIcon;
      
      function getEntityIcon(param1:IEntityDef, param2:EntityIconType) : GuiIcon;
      
      function getAwardIcon(param1:String) : GuiIcon;
      
      function getAbilityBuffIcon(param1:IAbilityDef) : GuiIcon;
      
      function getAbilityDefById(param1:String) : IAbilityDef;
      
      function getAbilityIcon(param1:IAbilityDef) : GuiIcon;
      
      function getLargeAbilityIcon(param1:IAbilityDef) : GuiIcon;
      
      function getEntityVersusPortrait(param1:IEntityDef) : GuiIcon;
      
      function getEntityAppearancePromotePortrait(param1:IEntityAppearanceDef) : GuiIcon;
      
      function getEntityClassPromotePortraitAtAppIndex(param1:IEntityClassDef, param2:int) : GuiIcon;
      
      function getEntityPromotePortrait(param1:IEntityDef) : GuiIcon;
      
      function getFriendAvatar(param1:FriendData, param2:int) : GuiIcon;
      
      function getIcon(param1:String) : GuiIcon;
      
      function get statCosts() : GameStatCosts;
      
      function get legend() : Legend;

      function get party() : IPartyDef;

      function get renown() : int;

      // [Inference] Re-add roster members the refactor moved onto Legend, so the stale
      // mead_house.swf symbol class resolves them by name (mirrors the party/renown shim).
      function rosterSlotAvailable() : Boolean;

      function purchaseRosterUnit(param1:IPurchasableUnit, param2:Boolean, param3:Function) : void;

      function getCrownChitIcon() : GuiIcon;
      
      function getCrownIcon() : GuiIcon;
      
      function createDialog() : IGuiDialog;
      
      function removeDialog(param1:IGuiDialog) : void;
      
      function eatEvent(param1:MouseEvent) : void;
      
      function reportUserAbuse(param1:String) : void;
      
      function setPref(param1:String, param2:*) : void;
      
      function getPref(param1:String) : *;
      
      function translateRaw(param1:String) : String;
      
      function translate(param1:String) : String;
      
      function translateTaunt(param1:String) : String;
      
      function getTaunts() : Vector.<String>;
      
      function replaceTranslatedTokens(param1:String, param2:Array) : String;
      
      function isClassAvailable(param1:String) : Boolean;
      
      function getAbilityDef(param1:String) : IAbilityDef;
      
      function get randomMaleName() : String;
      
      function get randomFemaleName() : String;
      
      function get friends() : FriendsData;
      
      function get sceneList() : SceneListDef;
      
      function get iap() : IIapManager;
      
      function get currencySymbol() : String;
      
      function get currencyCode() : String;
      
      function getUnlock(param1:String) : UnlockData;
      
      function hasUnlock(param1:String) : Boolean;
      
      function get purchases() : PurchaseCounts;
      
      function showMarket(param1:Boolean, param2:String, param3:String, param4:Function) : void;
      
      function tutorialMode() : Boolean;
      
      function get battleHudConfig() : BattleHudConfig;
      
      function get tourney() : Tourney;
      
      function get tourneyWinner() : TourneyWinnerData;
      
      function get tourneyProgress() : TourneyProgressData;
      
      function joinTourney(param1:int, param2:Function) : void;
      
      function get tourneyDefList() : TourneyDefList;
      
      function get runMode() : RunMode;
   }
}

