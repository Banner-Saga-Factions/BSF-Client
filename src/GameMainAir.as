package
{
   import air.fmod.ane.FmodSoundDriver;
   import air.steamworks.ane.SteamworksAne;
   import engine.anim.def.AnimClipDef;
   import engine.anim.view.AnimClipSprite;
   import engine.anim.view.AnimController;
   import engine.battle.ability.effect.op.def.IdEffectOp;
   import engine.core.RunMode;
   import engine.core.logging.Logger;
   import engine.core.util.EngineEnumInit;
   import engine.core.util.Enum;
   import engine.def.EngineJsonDef;
   import engine.def.EngineJsonDefImpl;
   import engine.gui.core.GuiApplication;
   import engine.gui.core.GuiHList;
   import engine.gui.core.GuiSprite;
   import engine.sound.NullSoundDriver;
   import engine.steamworks.ISteamworks;
   import engine.steamworks.NullSteamworks;
   import flash.desktop.NativeApplication;
   import flash.display.DisplayObject;
   import flash.display.NativeWindow;
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.events.InvokeEvent;
   import flash.events.KeyboardEvent;
   import flash.events.MouseEvent;
   import flash.events.TimerEvent;
   import flash.filesystem.File;
   import flash.filters.GlowFilter;
   import flash.geom.Point;
   import flash.system.Capabilities;
   import flash.text.TextField;
   import flash.text.TextFormat;
   import flash.utils.Timer;
   import game.cfg.GameConfig;
   import game.cfg.GameEnumInit;
   import game.view.GameWrapper;
   import lib.engine.util.air.AirAppInfo;
   import starling.core.Starling;
   
   public class GameMainAir extends GuiApplication
   {
      
      public static const DEFAULT_RUNMODE:RunMode = RunMode.BETA;
      
      public var font_vinque_normal:Class = VinqueFont;
      
      public var font_minionpro_normal:Class = MinionProRegularFont;
      
      public var font_minionpro_bold:Class = MinionProBoldFont;
      
      public var wrappers:Vector.<GameWrapper> = new Vector.<GameWrapper>();
      
      private var appInfo:AirAppInfo;
      
      public var hbox:GuiHList;
      
      public var hboxMasker:GuiHList;
      
      public var masks:Vector.<GuiSprite>;
      
      private var s:Starling;
      
      private var overlay:Sprite;
      
      private var assets:String;
      
      private var gui:String;
      
      private var local_assets:Boolean;
      
      private var locally:Boolean;
      
      private var assetsOverridden:Boolean;
      
      private var serverOverridden:Boolean;
      
      private var steamworks:ISteamworks;
      
      private var enableSteam:Boolean = true;
      
      private var offline:Boolean;
      
      private var steam_ids:Array = [];
      
      private var spritesheet:Boolean = true;
      
      private var fmod_port:int = 0;
      
      private var fmod_profile:Boolean;
      
      private var debugTxnImmediateFinalize:Boolean;
      
      private var tutorial:Boolean;
      
      private var new_music:Boolean;
      
      private var childs:Array;
      
      private var betaBuildText:TextField;
      
      private var softwareMouse:Boolean = false;
      
      private var sagaUrl:String;
      
      private var sagaHappening:String;
      
      private var startInVs:Boolean;
      
      private var fixingAdobeDebugLaucher:Boolean;
      
      private var fixedAdobeDebugLauncher:Boolean;
      
      private var sound:Boolean = true;
      
      private var parties:Vector.<Vector.<String>> = null;
      
      private var runMode:RunMode = DEFAULT_RUNMODE;
      
      private var versusCountdownOverrideSecs:int = -1;
      
      private var fullscreen:Boolean = false;
      
      private var fullscreenSet:Boolean = false;
      
      private var debug:Boolean;
      
      private var server:String;
      
      private var cwd:String;
      
      private var invokeArguments:Array;
      
      private var readyToSetup:Boolean;
      
      private var invoked:Boolean;
      
      private var exitTimer:Timer = new Timer(500,1);
      
      private var handledExit:Boolean;
      
      public function GameMainAir()
      {
         super();
         EngineJsonDef._validate = EngineJsonDefImpl.validate;
         new EngineEnumInit();
         new GameEnumInit();
         stage.quality = "low";
         stage.stageFocusRect = false;
         var _loc1_:Boolean = false;
         if(_loc1_)
         {
            doFixAdobeDebugLauncher();
         }
         IdEffectOp;
         stage.color = 0;
         resizeHandler();
         overlay = this;
         stage.scaleMode = "noScale";
         appInfo = new AirAppInfo(this,"1.10.51","2013-07-13_21-45-52","dev",0);
         var _loc2_:GameWrapper = new GameWrapper(0,appInfo,FmodSoundDriver,false);
         wrappers.push(_loc2_);
         appInfo.loadIni("tbs_config.ini");
         NativeApplication.nativeApplication.addEventListener("invoke",invokeHandler);
         NativeApplication.nativeApplication.addEventListener("exiting",exitingHandler);
         0;
         locally = appInfo.buildVersion.indexOf("locally") == 0;
      }
      
      private function doFixAdobeDebugLauncher() : void
      {
         fixingAdobeDebugLaucher = true;
         var _loc2_:AneFixer = new AneFixer("air.steamworks.ane.SteamworksAneContext",null);
         var _loc1_:Boolean = _loc2_.fix();
         fixedAdobeDebugLauncher = true;
         if(readyToSetup)
         {
            doSetup();
         }
      }
      
      override protected function resizeHandler() : void
      {
         var _loc3_:int = 0;
         var _loc1_:DisplayObject = null;
         var _loc2_:GuiSprite = null;
         super.resizeHandler();
         if(betaBuildText)
         {
            betaBuildText.width = betaBuildText.textWidth + 10;
            betaBuildText.x = this.width - betaBuildText.width - 20;
            betaBuildText.y = -5;
         }
         if(overlay)
         {
            overlay.width = width;
            overlay.height = height;
            _loc3_ = 0;
            while(_loc3_ < overlay.numChildren)
            {
               _loc1_ = overlay.getChildAt(_loc3_);
               _loc2_ = _loc1_ as GuiSprite;
               if(_loc2_)
               {
                  _loc2_.setSize(width,height);
               }
               else
               {
                  _loc1_.width = width;
                  _loc1_.height = height;
               }
               _loc3_++;
            }
         }
      }
      
      override protected function addedToStageHandler(param1:Event) : void
      {
         super.addedToStageHandler(param1);
         stage.addEventListener("keyDown",keyDownHandler);
      }
      
      private function keyDownHandler(param1:KeyboardEvent) : void
      {
      }
      
      private function initWrapper(param1:int, param2:Array) : GameWrapper
      {
         var _loc5_:String = null;
         var _loc3_:AirAppInfo = null;
         var _loc4_:GameWrapper = null;
         if(wrappers.length > param1)
         {
            _loc4_ = wrappers[param1];
         }
         else
         {
            if(wrappers.length != param1)
            {
               throw new ArgumentError("bad ordinal");
            }
            _loc5_ = param1 > 0 ? wrappers[0].appInfo.buildVersion : "1.10.51";
            _loc3_ = new AirAppInfo(this,_loc5_,"2013-07-13_21-45-52","dev",1);
            _loc4_ = new GameWrapper(param1,_loc3_,NullSoundDriver,debug);
            wrappers.push(_loc4_);
         }
         if(param1 < param2.length)
         {
            _loc4_.config.username = param2[param1];
         }
         (_loc4_.logger as Logger).debugEnabled = debug;
         return _loc4_;
      }
      
      private function initWrappers(param1:Array, param2:Boolean) : void
      {
         var _loc5_:int = 0;
         var _loc3_:GameWrapper = null;
         var _loc4_:GuiSprite = null;
         initWrapper(0,param1);
         if(param1.length == 1)
         {
            overlay.addChild(wrappers[0]);
            wrappers[0].anchor.percentWidth = 100;
            wrappers[0].anchor.percentHeight = 100;
            return;
         }
         hbox = new GuiHList();
         hbox.padding = 0;
         hbox.margin = 0;
         hboxMasker = new GuiHList();
         hboxMasker.padding = 0;
         hboxMasker.margin = 0;
         masks = new Vector.<GuiSprite>();
         _loc5_ = 0;
         while(_loc5_ < param1.length)
         {
            _loc3_ = initWrapper(_loc5_,param1);
            _loc4_ = new GuiSprite();
            _loc4_.debugRender = 0;
            hboxMasker.addChild(_loc4_);
            hbox.addChild(_loc3_);
            _loc3_.mask = _loc4_;
            _loc5_++;
         }
         hboxMasker.anchor.percentHeight = 100;
         hboxMasker.anchor.percentWidth = 100;
         overlay.addChild(hboxMasker);
         hbox.anchor.percentHeight = 100;
         hbox.anchor.percentWidth = 100;
         overlay.addChild(hbox);
      }
      
      private function logInfo(param1:String) : void
      {
         for each(var _loc2_ in wrappers)
         {
            _loc2_.logger.info(param1);
         }
      }
      
      private function logError(param1:String) : void
      {
         for each(var _loc2_ in wrappers)
         {
            _loc2_.logger.error(param1);
         }
      }
      
      private function setUsername(param1:int, param2:String) : void
      {
         wrappers[param1].config.username = param2;
      }
      
      private function parseArguments(param1:Array) : void
      {
         var _loc21_:GameWrapper = null;
         var _loc15_:int = 0;
         var _loc18_:String = null;
         var _loc5_:String = null;
         var _loc8_:Array = null;
         var _loc16_:String = null;
         var _loc13_:String = null;
         var _loc9_:Array = null;
         var _loc7_:int = 0;
         var _loc20_:int = 0;
         var _loc17_:int = 0;
         var _loc14_:int = 0;
         var _loc22_:String = null;
         var _loc23_:Array = null;
         var _loc6_:int = 0;
         var _loc4_:String = null;
         var _loc2_:Array = null;
         var _loc19_:String = null;
         var _loc3_:Array = null;
         var _loc10_:int = 0;
         logInfo("parseArguments " + param1);
         var _loc12_:NativeWindow = NativeApplication.nativeApplication.activeWindow;
         var _loc11_:int = 0;
         _loc15_ = 0;
         while(_loc15_ < param1.length)
         {
            _loc18_ = param1[_loc15_];
            logInfo("parsing arg " + _loc18_);
            if(_loc18_ == "--local_assets")
            {
               assetsOverridden = true;
               local_assets = true;
               assets = File.userDirectory.url + "/stoic/tbs/compile-assets";
            }
            if(_loc18_ == "--debug")
            {
               debug = true;
               for each(_loc21_ in wrappers)
               {
                  logInfo("setting debug on wrapper logger " + _loc21_.logger.name);
                  (_loc21_.logger as Logger).debugEnabled = true;
               }
            }
            else if(_loc18_ == "--mouse")
            {
               softwareMouse = true;
            }
            else if(_loc18_ == "--username")
            {
               _loc5_ = param1[++_loc15_];
               logInfo("setting usernames " + _loc5_);
               _loc8_ = _loc5_.split(",");
               initWrappers(_loc8_,debug);
            }
            else if(_loc18_ == "--child")
            {
               childs = param1[++_loc15_].split(",");
            }
            else if(_loc18_ == "--sound")
            {
               sound = param1[++_loc15_] == "true";
            }
            else if(_loc18_ == "--server")
            {
               serverOverridden = true;
               server = param1[++_loc15_];
            }
            else if(_loc18_ == "--qa")
            {
               serverOverridden = true;
               server = "http://tbs-dev-qa.stoicstudio.com/";
            }
            else if(_loc18_ == "--version")
            {
               _loc16_ = param1[++_loc15_];
               for each(_loc21_ in wrappers)
               {
                  _loc21_.appInfo.buildVersionOverride = _loc16_;
               }
            }
            else if(_loc18_ == "--assets")
            {
               assetsOverridden = true;
               assets = param1[++_loc15_];
            }
            else if(_loc18_ == "--gui")
            {
               gui = param1[++_loc15_];
            }
            else if(_loc18_ == "--party")
            {
               parties = parseParties(param1[++_loc15_]);
            }
            else if(_loc18_ == "--run_mode")
            {
               runMode = Enum.parse(RunMode,param1[++_loc15_]) as RunMode;
            }
            else if(_loc18_ == "--kiosk")
            {
               runMode = RunMode.KIOSK;
            }
            else if(_loc18_ == "--beta")
            {
               runMode = RunMode.BETA;
            }
            else if(_loc18_ == "--developer")
            {
               runMode = RunMode.DEVELOPER;
            }
            else if(_loc18_ == "--reset_prefs")
            {
               for each(_loc21_ in wrappers)
               {
                  _loc21_.config.globalPrefs.reset();
               }
            }
            else if(_loc18_ == "--turn")
            {
               _loc13_ = param1[++_loc15_];
               _loc9_ = _loc13_.split(",");
               _loc11_ = 0;
               while(_loc11_ < _loc9_.length && _loc11_ < wrappers.length)
               {
                  _loc21_ = wrappers[_loc11_];
                  _loc21_.config.options.overrideTurnLengthSecs = _loc9_[_loc11_];
                  _loc11_++;
               }
            }
            else if(_loc18_ == "--versus_countdown")
            {
               versusCountdownOverrideSecs = int(param1[++_loc15_]);
            }
            else if(_loc18_ == "--width")
            {
               _loc7_ = int(param1[++_loc15_]);
               _loc12_.x = Math.max(0,_loc12_.x - (_loc7_ - _loc12_.width));
               _loc12_.width = _loc7_;
            }
            else if(_loc18_ == "--height")
            {
               _loc20_ = int(param1[++_loc15_]);
               _loc12_.y = Math.max(0,_loc12_.y - (_loc20_ - _loc12_.height));
               _loc12_.height = _loc20_;
            }
            else if(_loc18_ == "--min_size")
            {
               _loc17_ = int(param1[++_loc15_]);
               _loc14_ = int(param1[++_loc15_]);
               appInfo.minSize = new Point(_loc17_,_loc14_);
            }
            else if(_loc18_ == "--versus_opponent")
            {
               _loc22_ = param1[++_loc15_];
               _loc23_ = _loc22_.split(",");
               _loc11_ = 0;
               while(_loc11_ < _loc23_.length && _loc11_ < wrappers.length)
               {
                  _loc21_ = wrappers[_loc11_];
                  _loc21_.config.options.versusForceOpponentId = _loc23_[_loc11_];
                  _loc11_++;
               }
            }
            else if(_loc18_ == "--versus_start")
            {
               runMode = RunMode.FACTIONS;
               startInVs = true;
            }
            else if(_loc18_ == "--tourney")
            {
               _loc6_ = int(param1[++_loc15_]);
               for each(_loc21_ in wrappers)
               {
                  _loc21_.config.options.versusForceTourneyId = _loc6_;
               }
            }
            else if(_loc18_ == "--versus_scene")
            {
               _loc4_ = param1[++_loc15_];
               _loc2_ = _loc4_.split(",");
               _loc11_ = 0;
               while(_loc11_ < _loc2_.length && _loc11_ < wrappers.length)
               {
                  _loc21_ = wrappers[_loc11_];
                  _loc21_.config.options.versusForceScene = _loc2_[_loc11_];
                  _loc11_++;
               }
            }
            else if(_loc18_ == "--combat")
            {
               _loc19_ = param1[++_loc15_];
               logInfo("setting combats " + _loc19_);
               _loc3_ = _loc19_.split(",");
               _loc11_ = 0;
               while(_loc11_ < _loc3_.length && _loc11_ < wrappers.length)
               {
                  _loc21_ = wrappers[_loc11_];
                  _loc21_.config.options.startInCombat = _loc19_;
                  _loc11_++;
               }
            }
            else if(_loc18_ == "--saga")
            {
               sagaUrl = param1[++_loc15_];
               _loc10_ = sagaUrl.indexOf(":");
               if(_loc10_ > 0)
               {
                  sagaHappening = sagaUrl.substring(_loc10_ + 1);
                  sagaUrl = sagaUrl.substring(0,_loc10_);
               }
            }
            else if(_loc18_ == "--happening")
            {
               sagaHappening = param1[++_loc15_];
            }
            else if(_loc18_ == "--factions")
            {
               runMode = RunMode.FACTIONS;
            }
            else if(_loc18_ == "--fullscreen")
            {
               fullscreen = param1[++_loc15_] == "true";
               fullscreenSet = true;
            }
            else if(_loc18_ == "--log_anim_events")
            {
               AnimController.log_anim_events = true;
            }
            else if(_loc18_ == "--steam")
            {
               enableSteam = param1[++_loc15_] == "true";
            }
            else if(_loc18_ == "--offline")
            {
               offline = true;
            }
            else if(_loc18_ == "--steam_id")
            {
               steam_ids = (param1[++_loc15_] as String).split(",");
            }
            else if(_loc18_ == "--spritesheet")
            {
               spritesheet = param1[++_loc15_] == "true";
            }
            else if(_loc18_ == "--fmod_port")
            {
               fmod_port = param1[++_loc15_];
            }
            else if(_loc18_ == "--fmod_profile")
            {
               fmod_profile = param1[++_loc15_] == "true";
            }
            else if(_loc18_ == "--debug_txn_immediate_finalize")
            {
               debugTxnImmediateFinalize = true;
            }
            else if(_loc18_ == "--tutorial")
            {
               tutorial = true;
            }
            else if(_loc18_ != "--miner")
            {
               if(_loc18_ == "--spritesheet_debug_render")
               {
                  AnimClipSprite.DEBUG_RENDER_SPRITESHEET = true;
               }
               else if(_loc18_ == "--new_music")
               {
                  new_music = true;
               }
            }
            _loc15_++;
         }
      }
      
      protected function invokeHandler(param1:InvokeEvent) : void
      {
         logInfo("invokeHandler reason=" + param1.reason + " arguments=" + param1.arguments);
         if(invoked)
         {
            return;
         }
         invoked = true;
         logInfo("invokeHandler appInfo.nativeAppUrlRoot=" + appInfo.nativeAppUrlRoot);
         cwd = param1.currentDirectory.url;
         logInfo("cwd=" + cwd);
         invokeArguments = param1.arguments;
         readyToSetup = true;
         if(!fixingAdobeDebugLaucher || fixedAdobeDebugLauncher)
         {
            doSetup();
         }
      }
      
      private function doSetup() : void
      {
         var args:Array;
         var iniArgs:String;
         var iniArgsv:Array;
         var iniArg:String;
         var wrapper:GameWrapper;
         var j:int;
         var wi:int;
         var overrideBar:TextField;
         var txt:String;
         if(locally)
         {
            assets = GameConfig.massageResourcePath(appInfo.nativeAppUrlRoot,wrappers[0].logger,"../../../../../compile-assets");
            gui = GameConfig.massageResourcePath(appInfo.nativeAppUrlRoot,wrappers[0].logger,"../../../../gui/flash/");
         }
         else if(Capabilities.os.indexOf("Windows") == 0)
         {
            assets = GameConfig.massageResourcePath(appInfo.nativeAppUrlRoot,wrappers[0].logger,"../assets");
            gui = GameConfig.massageResourcePath(appInfo.nativeAppUrlRoot,wrappers[0].logger,"../gui/");
         }
         else if(Capabilities.os.indexOf("Mac") == 0)
         {
            assets = GameConfig.massageResourcePath(appInfo.nativeAppUrlRoot,wrappers[0].logger,"../../../assets/");
            gui = GameConfig.massageResourcePath(appInfo.nativeAppUrlRoot,wrappers[0].logger,"../../../gui/");
         }
         else
         {
            logInfo("UNSUPPORTED OS: " + Capabilities.os);
            assets = "assets/";
            gui = "gui/";
         }
         logInfo("arguments length=" + invokeArguments.length + ", value=" + invokeArguments);
         if(NativeApplication.nativeApplication && NativeApplication.nativeApplication.activeWindow)
         {
            logInfo("renderMode=" + NativeApplication.nativeApplication.activeWindow.renderMode);
         }
         else
         {
            logInfo("renderMode=NO ACTIVE WINDOW");
         }
         args = invokeArguments.concat();
         iniArgs = appInfo.ini["args"];
         if(args.length == 0)
         {
            logInfo("No command line arguments, using AppInfo args=[" + iniArgs + "]");
            if(iniArgs)
            {
               iniArgsv = iniArgs.split(" ");
               logInfo("iniArgsv=" + iniArgsv.length + ", " + iniArgsv);
               for each(iniArg in iniArgsv)
               {
                  args.push(iniArg);
               }
               logInfo("args now " + args);
            }
         }
         else
         {
            logInfo("Command line arguments found, ignoring AppInfo args=[" + iniArgs + "]");
         }
         j = 0;
         appInfo.ini["server"];
         if(server)
         {
            logInfo("serverOverridden by " + server);
            serverOverridden = true;
         }
         parseArguments(args);
         if(wrappers[0].parent == null)
         {
            initWrappers([""],debug);
         }
         if(fullscreenSet)
         {
            wrappers[0].cmdFullscreen = true;
            wrappers[0].cmdFullscreenSet = fullscreen;
         }
         initSteam();
         logInfo("spritesheet=" + spritesheet);
         AnimClipDef.ALLOW_SPRITESHEET = spritesheet;
         wi = 0;
         while(wi < wrappers.length)
         {
            wrapper = wrappers[wi];
            wrapper.config.steamworks = steamworks;
            if(steam_ids.length > wi)
            {
               wrapper.config.options.overrideSteamId = steam_ids[wi];
            }
            if(server)
            {
               wrapper.config.gameServerUrl = server;
            }
            if(assets)
            {
               wrapper.config.options.assetPath = assets;
            }
            wrapper.config.options.alwaysOffline = offline;
            wrapper.config.options.softwareMouse = softwareMouse;
            wrapper.config.options.startInSaga = sagaUrl;
            wrapper.config.options.startInSagaHappening = sagaHappening;
            wrapper.config.options.startInFactions = runMode == RunMode.FACTIONS;
            wrapper.config.options.startInVersus = startInVs;
            wrapper.config.options.debugTxnImmediateFinalize = debugTxnImmediateFinalize;
            wrapper.config.options.testTutorial = tutorial;
            wrapper.config.options.newMusic = new_music;
            if(gui)
            {
               wrapper.config.options.guiPath = gui;
            }
            if(parties && parties.length > wi)
            {
               wrapper.config.options.partyOverride = parties[wi];
            }
            wrapper.config.options.overrideVersusCountdownSecs = versusCountdownOverrideSecs;
            if(childs && childs.length > wi)
            {
               wrapper.config.options.accountChildNumber = childs[wi];
            }
            wrapper.config.runMode = runMode;
            wrapper.config.options.soundEnabled = sound;
            wrapper.config.options.fmodPort = fmod_port;
            wrapper.config.options.fmodProfile = fmod_profile;
            wrapper.startLoading();
            wi = wi + 1;
         }
         if(betaBuildText)
         {
            betaBuildText.name = "beta";
            betaBuildText.defaultTextFormat = new TextFormat("Vinque",16,16711680,true);
            betaBuildText.filters = [new GlowFilter(0,1,6,6,3)];
            betaBuildText.text = "BETA BUILD";
            betaBuildText.width = betaBuildText.textWidth + 10;
            betaBuildText.height = betaBuildText.textHeight * 2;
            betaBuildText.x = this.width - betaBuildText.width - 20;
            betaBuildText.y = -5;
            betaBuildText.mouseEnabled = false;
            addChild(betaBuildText);
         }
         if(serverOverridden || assetsOverridden)
         {
            overrideBar = new TextField();
            overrideBar.name = "override";
            overrideBar.defaultTextFormat = new TextFormat("Vinque",16,16711680,true);
            overrideBar.filters = [new GlowFilter(0,1,6,6,3)];
            addChild(overrideBar);
            overrideBar.mouseEnabled = true;
            txt = "";
            if(serverOverridden)
            {
               txt += "     SERVER: " + server;
            }
            if(assetsOverridden)
            {
               txt += "      ASSETS: " + assets;
            }
            overrideBar.text = txt;
            overrideBar.x = 100;
            overrideBar.width = overrideBar.textWidth + 10;
            overrideBar.height = overrideBar.textHeight * 2;
            overrideBar.addEventListener("click",function(param1:MouseEvent):void
            {
               if(overrideBar && overrideBar.parent)
               {
                  logInfo("Removing OVERRIDE BAR: " + overrideBar.text);
                  removeChild(overrideBar);
                  overrideBar = null;
               }
            });
         }
      }
      
      private function parseParties(param1:String) : Vector.<Vector.<String>>
      {
         var _loc2_:Array = null;
         var _loc5_:* = undefined;
         var _loc3_:Array = param1.split(",");
         var _loc6_:Vector.<Vector.<String>> = new Vector.<Vector.<String>>();
         for each(var _loc7_ in _loc3_)
         {
            _loc2_ = _loc7_.split(":");
            _loc5_ = new Vector.<String>();
            for each(var _loc4_ in _loc2_)
            {
               _loc5_.push(_loc4_);
            }
            _loc6_.push(_loc5_);
         }
         return _loc6_;
      }
      
      protected function exitingHandler(param1:Event) : void
      {
         stage.color = 0;
         if(handledExit)
         {
            return;
         }
         handledExit = true;
         logInfo("GameMainAir.exitingHandler autoExit=" + NativeApplication.nativeApplication.autoExit + ", event=" + param1);
         for each(var _loc2_ in wrappers)
         {
            _loc2_.cleanup();
         }
         param1.preventDefault();
         exitTimer.addEventListener("timerComplete",exitTimerCompleteHandler);
         exitTimer.start();
      }
      
      private function exitTimerCompleteHandler(param1:TimerEvent) : void
      {
         logInfo("exitTimerCompleteHandler");
         NativeApplication.nativeApplication.exit(appInfo.exitCode);
      }
      
      private function initSteam() : void
      {
         var _loc3_:Boolean = false;
         var _loc1_:int = 0;
         _loc1_ = 10;
         var _loc2_:int = 0;
         if(enableSteam)
         {
            try
            {
               steamworks = new SteamworksAne(wrappers[0].logger);
               steamworks.create();
               _loc3_ = steamworks.SteamAPI_RestartAppIfNecessary(219340);
               if(_loc3_)
               {
                  logInfo("STEAM requires that we restart...");
                  appInfo.exitGame("Steam restart required");
                  return;
               }
               _loc2_ = 0;
               while(_loc2_ < _loc1_)
               {
                  if(steamworks.SteamAPI_Init())
                  {
                     logInfo("STEAM Init OK attempt " + _loc2_);
                     break;
                  }
                  _loc2_++;
               }
               if(!steamworks.initialized)
               {
                  logInfo("STEAM Init FAIL");
               }
            }
            catch(error:Error)
            {
               logError("STEAM failed: " + error);
               steamworks = null;
            }
         }
         if(!steamworks)
         {
            steamworks = new NullSteamworks(enableSteam);
         }
      }
   }
}

