package game.gui
{
   import engine.ability.IAbilityDef;
   import engine.achievement.AchievementDef;
   import engine.battle.SceneListDef;
   import engine.core.RunMode;
   import engine.core.locale.LocaleCategory;
   import engine.core.logging.ILogger;
   import engine.entity.def.EntityIconType;
   import engine.entity.def.IEntityAppearanceDef;
   import engine.entity.def.IEntityClassDef;
   import engine.entity.def.IEntityDef;
   import engine.entity.def.IPartyDef;
   import engine.entity.def.Legend;
   import engine.resource.AnimClipResource;
   import engine.resource.BitmapResource;
   import engine.resource.MovieClipResource;
   import engine.resource.Resource;
   import engine.resource.ResourceGroup;
   import engine.resource.ResourceManager;
   import engine.resource.event.ResourceLoadedEvent;
   import engine.session.IIapManager;
   import engine.sound.view.ISound;
   import engine.sound.view.ISoundController;
   import engine.tourney.TourneyDefList;
   import flash.events.Event;
   import flash.events.EventDispatcher;
   import flash.events.MouseEvent;
   import flash.utils.Dictionary;
   import game.cfg.AccountInfoDef;
   import game.cfg.BattleHudConfig;
   import game.cfg.GameAssetsDef;
   import game.cfg.GameConfig;
   import game.entity.GameStatCosts;
   import game.view.IDialogLayer;
   import tbs.srv.data.FriendData;
   import tbs.srv.data.FriendsData;
   import tbs.srv.util.PurchaseCounts;
   import tbs.srv.util.Tourney;
   import tbs.srv.util.TourneyProgressData;
   import tbs.srv.util.TourneyWinnerData;
   import tbs.srv.util.UnlockData;
   
   public class GameGuiContext extends EventDispatcher implements IGuiContext
   {
      
      private static var symbols:Dictionary;
      
      public var _logger:ILogger;
      
      public var _ready:Boolean;
      
      private var soundController:ISoundController;
      
      private var resman:ResourceManager;
      
      private var _resourceGroup:ResourceGroup;
      
      private var _accountInfo:AccountInfoDef;
      
      private var dialogResource:MovieClipResource;
      
      private var callback:Function;
      
      private var assets:GameAssetsDef;
      
      private var dialogLayer:IDialogLayer;
      
      public var eaten:MouseEvent;
      
      public var config:GameConfig;
      
      private var _currencySymbol:String;
      
      public function GameGuiContext(param1:ILogger, param2:ResourceManager, param3:ISoundController, param4:AccountInfoDef, param5:MovieClipResource, param6:IDialogLayer, param7:GameConfig)
      {
         super();
         if(!param3)
         {
            throw new ArgumentError("null soundController");
         }
         this.config = param7;
         this._ready = false;
         this._logger = param1;
         this.resman = param2;
         this.accountInfo = param4;
         this.soundController = param3;
         this.assets = assets;
         this.dialogLayer = param6;
         this.dialogResource = param5;
      }
      
      private static function getCurrencySymbol(param1:String, param2:ILogger) : String
      {
         if(!symbols)
         {
            symbols = new Dictionary();
            symbols["USD"] = "$";
            symbols["EUR"] = "€";
            symbols["GBP"] = "£";
            symbols["RUB"] = "p.";
            symbols["BRL"] = "R$";
         }
         var _loc3_:String = symbols[param1];
         if(!_loc3_)
         {
            param2.error("Invalid currency: " + param1);
            return "¿";
         }
         return _loc3_;
      }
      
      public function isClassAvailable(param1:String) : Boolean
      {
         return config.runMode.isClassAvailable(param1);
      }
      
      public function load(param1:Function) : void
      {
         this.callback = param1;
         dialogResource.addResourceListener(dialogResourceCompletedHandler);
      }
      
      private function dialogResourceCompletedHandler(param1:ResourceLoadedEvent) : void
      {
         ready = true;
         if(callback != null)
         {
            callback(this);
         }
      }
      
      public function get resourceGroup() : ResourceGroup
      {
         return _resourceGroup;
      }
      
      public function set resourceGroup(param1:ResourceGroup) : void
      {
         if(_resourceGroup == param1)
         {
            return;
         }
         if(_resourceGroup)
         {
            _resourceGroup.release();
         }
         _resourceGroup = param1;
      }
      
      public function get logger() : ILogger
      {
         return _logger;
      }
      
      public function get ready() : Boolean
      {
         return _ready;
      }
      
      public function set ready(param1:Boolean) : void
      {
         _ready = param1;
      }
      
      public function playSound(param1:String) : void
      {
         if(!config.soundSystem.sfxEnabled)
         {
            return;
         }
         if(!ready)
         {
            return;
         }
         if(!soundController.library)
         {
            return;
         }
         var _loc2_:ISound = soundController.getSound(param1,null);
         if(!_loc2_)
         {
            logger.error("GameGuiContext.playSound INVALID " + param1);
            return;
         }
         _loc2_.start();
      }
      
      private function soundControllerCallback() : void
      {
         _ready = true;
      }
      
      public function getFriendAvatar(param1:FriendData, param2:int) : GuiIcon
      {
         var _loc5_:String = null;
         if(param2 >= 128)
         {
            _loc5_ = param1.avatar128;
         }
         if(!_loc5_ || param2 >= 64)
         {
            _loc5_ = param1.avatar64;
         }
         if(!_loc5_)
         {
            _loc5_ = param1.avatar32;
         }
         var _loc4_:Resource = resman.getResource(_loc5_,BitmapResource,_resourceGroup);
         return new GuiIcon(_loc4_,GuiIconLayoutType.ACTUAL);
      }
      
      public function getEntityIconAtAppIndex(param1:IEntityClassDef, param2:EntityIconType, param3:int) : GuiIcon
      {
         var _loc5_:IEntityAppearanceDef = param1.getEntityClassAppearanceDef(param3);
         var _loc7_:String = _loc5_.getIconUrl(param2);
         var _loc6_:Resource = resman.getResource(_loc7_,BitmapResource,_resourceGroup);
         return new GuiIcon(_loc6_,GuiIconLayoutType.ACTUAL);
      }
      
      public function getAwardIcon(param1:String) : GuiIcon
      {
         var _loc3_:Resource = resman.getResource(param1,BitmapResource,_resourceGroup);
         return new GuiIcon(_loc3_,GuiIconLayoutType.ACTUAL);
      }
      
      public function getAchievementDef(param1:String) : AchievementDef
      {
         return config.achievementListDef.fetch(param1);
      }
      
      public function getEntityIcon(param1:IEntityDef, param2:EntityIconType) : GuiIcon
      {
         var _loc5_:String = param1.appearance.getIconUrl(param2);
         var _loc4_:Resource = resman.getResource(_loc5_,BitmapResource,_resourceGroup);
         return new GuiIcon(_loc4_,GuiIconLayoutType.ACTUAL);
      }
      
      public function getEntityClassPortrait(param1:IEntityDef) : GuiIcon
      {
         var _loc3_:IEntityAppearanceDef = param1.appearance;
         var _loc2_:Resource = resman.getResource(_loc3_.portraitUrl,AnimClipResource,_resourceGroup);
         return new GuiIcon(_loc2_,GuiIconLayoutType.ACTUAL);
      }
      
      public function getEntityVersusPortrait(param1:IEntityDef) : GuiIcon
      {
         if(!param1)
         {
            return null;
         }
         var _loc3_:IEntityAppearanceDef = param1.appearance;
         var _loc2_:Resource = resman.getResource(_loc3_.versusPortraitUrl,BitmapResource,_resourceGroup);
         return new GuiIcon(_loc2_,GuiIconLayoutType.ACTUAL);
      }
      
      public function getEntityAppearancePromotePortrait(param1:IEntityAppearanceDef) : GuiIcon
      {
         var _loc2_:Resource = resman.getResource(param1.promotePortraitUrl,BitmapResource,_resourceGroup);
         return new GuiIcon(_loc2_,GuiIconLayoutType.ACTUAL);
      }
      
      public function getEntityClassPromotePortraitAtAppIndex(param1:IEntityClassDef, param2:int) : GuiIcon
      {
         if(!param1)
         {
            return null;
         }
         var _loc3_:IEntityAppearanceDef = param1.getEntityClassAppearanceDef(param2);
         return getEntityAppearancePromotePortrait(_loc3_);
      }
      
      public function getEntityPromotePortrait(param1:IEntityDef) : GuiIcon
      {
         if(!param1)
         {
            return null;
         }
         var _loc2_:IEntityAppearanceDef = param1.appearance;
         return getEntityAppearancePromotePortrait(_loc2_);
      }
      
      public function getAbilityDefById(param1:String) : IAbilityDef
      {
         return config.abilityFactory.fetch(param1);
      }
      
      public function getAbilityBuffIcon(param1:IAbilityDef) : GuiIcon
      {
         var _loc2_:Resource = null;
         if(param1.iconBuffUrl)
         {
            _loc2_ = resman.getResource(param1.iconBuffUrl,BitmapResource,_resourceGroup);
            return new GuiIcon(_loc2_,GuiIconLayoutType.ACTUAL);
         }
         logger.error("No icon for " + param1);
         return null;
      }
      
      public function getAbilityIcon(param1:IAbilityDef) : GuiIcon
      {
         var _loc3_:Resource = null;
         var _loc2_:Resource = null;
         if(param1 == null)
         {
            _loc3_ = resman.getResource("common/ability/icon/icon_no_special.png",BitmapResource,_resourceGroup);
            return new GuiIcon(_loc3_,GuiIconLayoutType.ACTUAL);
         }
         if(param1.iconUrl)
         {
            _loc2_ = resman.getResource(param1.iconUrl,BitmapResource,_resourceGroup);
            return new GuiIcon(_loc2_,GuiIconLayoutType.ACTUAL);
         }
         logger.error("No icon for " + param1);
         return null;
      }
      
      public function getLargeAbilityIcon(param1:IAbilityDef) : GuiIcon
      {
         var _loc2_:Resource = null;
         if(param1.iconLargeUrl)
         {
            _loc2_ = resman.getResource(param1.iconLargeUrl,BitmapResource,_resourceGroup);
            return new GuiIcon(_loc2_,GuiIconLayoutType.ACTUAL);
         }
         logger.error("No icon for " + param1);
         return null;
      }
      
      public function getIcon(param1:String) : GuiIcon
      {
         var _loc2_:Resource = resman.getResource(param1,BitmapResource,_resourceGroup);
         return new GuiIcon(_loc2_,GuiIconLayoutType.ACTUAL);
      }
      
      public function get legend() : Legend
      {
         return config.legend;
      }

      public function get party() : IPartyDef
      {
         return legend.party;
      }

      public function get renown() : int
      {
         return legend.renown;
      }

      public function get accountInfo() : AccountInfoDef
      {
         return _accountInfo;
      }
      
      public function getAbilityDef(param1:String) : IAbilityDef
      {
         return config.abilityFactory.fetch(param1);
      }
      
      public function set accountInfo(param1:AccountInfoDef) : void
      {
         if(_accountInfo == param1)
         {
            return;
         }
         if(_accountInfo)
         {
            _accountInfo.removeEventListener("AccountInfoDef.CURRENCY",currencyHandler);
            _accountInfo.removeEventListener("AccountInfoDef.UNLOCKS",unlocksHandler);
            _accountInfo.purchases.removeEventListener("change",purchasesHandler);
         }
         _accountInfo = param1;
         if(_accountInfo)
         {
            _accountInfo.addEventListener("AccountInfoDef.CURRENCY",currencyHandler);
            _accountInfo.addEventListener("AccountInfoDef.UNLOCKS",unlocksHandler);
            _accountInfo.purchases.addEventListener("change",purchasesHandler);
            unlocksHandler(null);
            currencyHandler(null);
            purchasesHandler(null);
         }
      }
      
      private function currencyHandler(param1:Event) : void
      {
         _currencySymbol = getCurrencySymbol(_accountInfo.currency,logger);
         dispatchEvent(new GuiContextEvent("GuiContextEvent.CURRENCY"));
      }
      
      private function unlocksHandler(param1:Event) : void
      {
         dispatchEvent(new GuiContextEvent("GuiContextEvent.UNLOCKS"));
      }
      
      private function purchasesHandler(param1:Event) : void
      {
         dispatchEvent(new GuiContextEvent("GuiContextEvent.PURCHASES"));
      }
      
      public function createDialog() : IGuiDialog
      {
         var _loc1_:IGuiDialog = null;
         if(dialogResource.ok)
         {
            _loc1_ = dialogResource.movieClip as IGuiDialog;
            _loc1_.init(this);
            dialogLayer.addDialog(_loc1_);
         }
         return _loc1_;
      }
      
      public function removeDialog(param1:IGuiDialog) : void
      {
         dialogLayer.removeDialog(param1);
      }
      
      public function eatEvent(param1:MouseEvent) : void
      {
      }
      
      public function get username() : String
      {
         return config.fsm.credentials.vbb_name;
      }
      
      public function get displayname() : String
      {
         return config.fsm.credentials.displayName;
      }
      
      public function reportUserAbuse(param1:String) : void
      {
         logger.info("TODO REPORTING USER ABUSE: " + param1);
      }
      
      public function setPref(param1:String, param2:*) : void
      {
         config.globalPrefs.setPref(param1,param2);
      }
      
      public function getPref(param1:String) : *
      {
         return config.globalPrefs.getPref(param1);
      }
      
      public function translate(param1:String) : String
      {
         return config.context.locale.translate(LocaleCategory.GUI,param1);
      }
      
      public function translateRaw(param1:String) : String
      {
         return config.context.locale.translate(LocaleCategory.GUI,param1,true);
      }
      
      public function replaceTranslatedTokens(param1:String, param2:Array) : String
      {
         return config.context.locale.replaceTranslatedTokens(param1,param2);
      }
      
      public function get randomMaleName() : String
      {
         return config.namegen.randomMale;
      }
      
      public function get randomFemaleName() : String
      {
         return config.namegen.randomFemale;
      }
      
      public function get statCosts() : GameStatCosts
      {
         return config.statCosts;
      }
      
      public function getCrownChitIcon() : GuiIcon
      {
         var _loc1_:Resource = resman.getResource("common/battle/banner/chit/crown_jade_backer.png",BitmapResource,_resourceGroup);
         return new GuiIcon(_loc1_,GuiIconLayoutType.ACTUAL);
      }
      
      public function getCrownIcon() : GuiIcon
      {
         var _loc1_:Resource = resman.getResource("common/battle/banner/crown/crown_base.png",BitmapResource,_resourceGroup);
         return new GuiIcon(_loc1_,GuiIconLayoutType.ACTUAL);
      }
      
      public function get friends() : FriendsData
      {
         return config.friends;
      }
      
      public function get account_id() : int
      {
         return config.fsm.credentials.userId;
      }
      
      public function get sceneList() : SceneListDef
      {
         return config.sceneListDef;
      }
      
      public function translateTaunt(param1:String) : String
      {
         return config.context.locale.translate(LocaleCategory.TAUNT,param1);
      }
      
      public function getTaunts() : Vector.<String>
      {
         return config.context.locale.getTokens(LocaleCategory.TAUNT);
      }
      
      public function get iap() : IIapManager
      {
         if(config.factions)
         {
            return config.factions.iapManager;
         }
         return null;
      }
      
      public function get currencySymbol() : String
      {
         return _currencySymbol;
      }
      
      public function get currencyCode() : String
      {
         return accountInfo.currency;
      }
      
      public function hasUnlock(param1:String) : Boolean
      {
         return accountInfo.hasUnlock(param1);
      }
      
      public function get purchases() : PurchaseCounts
      {
         return accountInfo.purchases;
      }
      
      public function getUnlock(param1:String) : UnlockData
      {
         return accountInfo.getUnlockById(param1);
      }
      
      public function showMarket(param1:Boolean, param2:String, param3:String, param4:Function) : void
      {
         config.pageManager.showMarketplace(true,param2,param3,param4);
      }
      
      public function get battleHudConfig() : BattleHudConfig
      {
         return config.battleHudConfig;
      }
      
      public function tutorialMode() : Boolean
      {
         return config.accountInfo.tutorial;
      }
      
      public function get tourney() : Tourney
      {
         if(config.factions)
         {
            return config.factions.tourneys.tourney;
         }
         return null;
      }
      
      public function get tourneyWinner() : TourneyWinnerData
      {
         if(config.factions)
         {
            return config.factions.tourneys.tourneyWinner;
         }
         return null;
      }
      
      public function get tourneyProgress() : TourneyProgressData
      {
         if(config.factions)
         {
            return config.factions.tourneys.tourneyProgress;
         }
         return null;
      }
      
      public function joinTourney(param1:int, param2:Function) : void
      {
         if(config.factions)
         {
            config.factions.tourneys.joinTourney(param1,param2);
         }
      }
      
      public function get tourneyDefList() : TourneyDefList
      {
         if(config.factions)
         {
            return config.factions.tourneyDefList;
         }
         return null;
      }
      
      public function get runMode() : RunMode
      {
         return config.runMode;
      }
   }
}

