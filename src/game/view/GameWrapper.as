package game.view
{
   import engine.core.cmd.Cmd;
   import engine.core.cmd.CmdExec;
   import engine.core.logging.ILogger;
   import engine.core.logging.Log;
   import engine.core.logging.targets.DebugLogTarget;
   import engine.core.logging.targets.TraceLogTarget;
   import engine.core.util.AppInfo;
   import engine.core.util.EngineCoreContext;
   import engine.gui.ConsoleGui;
   import engine.gui.GuiSoundDebug;
   import engine.gui.core.GuiSprite;
   import engine.gui.page.Page;
   import engine.mod.ModGameSpeed;
   import flash.errors.IllegalOperationError;
   import flash.events.Event;
   import flash.filters.GlowFilter;
   import flash.text.TextField;
   import flash.text.TextFormat;
   import flash.utils.getTimer;
   import game.cfg.GameConfig;
   import game.gui.GuiMouse;
   import game.session.GameFsm;
   
   public class GameWrapper extends GuiSprite
   {
      
      public var config:GameConfig;
      
      public var logger:ILogger;
      
      public var dialogLayer:DialogLayer;
      
      public var tutorialLayer:TutorialLayer;
      
      public var cmdFullscreen:Boolean;
      
      public var cmdFullscreenSet:Boolean;
      
      private var context:EngineCoreContext;
      
      private var console:ConsoleGui;
      
      public var appInfo:AppInfo;
      
      private var pageManager:GamePageManagerAdapter;
      
      private var perf:PerfSprite;
      
      private var guiMouse:GuiMouse;
      
      private var systemMessageText:TextField;
      
      private var soundDebug:GuiSoundDebug;
      
      private var networkProblemDisplay:NetworkProblemDisplay;
      
      private var lastUpdateTime:int = 0;
      
      private var frameNumber:int = 0;
      
      private var cleanedup:Boolean;
      
      public function GameWrapper(param1:int, param2:AppInfo, param3:Class, param4:Boolean)
      {
         super();
         name = "wrapper_" + param2.ordinal;
         logger = Log.getLogger("TBS-" + param1);
         logger.addTarget(new TraceLogTarget());
         var _loc5_:DebugLogTarget = new DebugLogTarget();
         logger.addTarget(_loc5_);
         if(param4)
         {
            logger.debugEnabled = param4;
         }
         tutorialLayer = new TutorialLayer(logger);
         addChild(tutorialLayer);
         dialogLayer = new DialogLayer();
         addChild(dialogLayer);
         console = new ConsoleGui(logger,_loc5_);
         soundDebug = new GuiSoundDebug(this,logger);
         logger.info("GAME START " + new Date());
         _loc5_.addEventListener("DebugLogEvent.ERROR",debugLogErrorHandler);
         param2.init(logger);
         this.appInfo = param2;
         addChild(console);
         layoutGuiSprite();
         context = new EngineCoreContext(null,param2,logger);
         config = new GameConfig(context,GameFsm,param3,configLoadedHandler,dialogLayer,param1);
         config.tutorialLayer = tutorialLayer;
         console.keybinder = config.keybinder;
         console.shell = config.shell;
         console.prefs = config.globalPrefs;
         config.keybinder.bind(true,false,true,80,new Cmd("toggle_perfsprite",cmdFuncTogglePerfSprite),"KeyBindGroup.COMBAT");
         config.keybinder.bind(true,false,true,49,new Cmd("toggle_sound_debug",cmdFuncToggleSoundDebug),"KeyBindGroup.COMBAT");
         config.shell.add("page",cmdFuncPage);
         config.shell.add("debug",shellFuncDebug);
         addEventListener("addedToStage",addedToStageHandler);
         addedToStageHandler(null);
         perf = new PerfSprite(this);
         addChild(perf);
         perf.width = 400;
         perf.height = 30;
         perf.perfEnabled = config.globalPrefs.getPref("show_perf");
      }
      
      private function sizeSystemMessageText() : void
      {
         if(!systemMessageText)
         {
            return;
         }
         systemMessageText.width = this.width;
         systemMessageText.height = 300;
         systemMessageText.x = 0;
         systemMessageText.y = this.height - systemMessageText.height;
      }
      
      private function updateSystemMessage() : void
      {
         if(config.systemMessage.msg)
         {
            if(!systemMessageText)
            {
               systemMessageText = new TextField();
               systemMessageText.defaultTextFormat = new TextFormat("Vinque",32,16711680,true,null,null,null,null,"center");
               systemMessageText.filters = [new GlowFilter(0,1,16,16,3)];
               systemMessageText.selectable = false;
               systemMessageText.mouseEnabled = false;
               systemMessageText.wordWrap = true;
               addChild(systemMessageText);
               sizeSystemMessageText();
            }
            if(systemMessageText.text != config.systemMessage.msg)
            {
               systemMessageText.text = config.systemMessage.msg;
            }
         }
         else if(systemMessageText)
         {
            removeChild(systemMessageText);
            systemMessageText = null;
         }
      }
      
      private function addedToStageHandler(param1:Event) : void
      {
         config.keybinder.stage = stage;
      }
      
      private function configLoadedHandler() : void
      {
         pageManager = new GamePageManagerAdapter(config,this,0);
         pageManager.setRect(0,0,width,height);
         config.pageManager = pageManager;
         addChild(config.guiAlerts);
         config.guiAlerts.anchor.percentHeight = 100;
         config.guiAlerts.anchor.percentWidth = 100;
         dialogLayer.bringToFront();
         tutorialLayer.bringToFront();
         console.bringToFront();
         soundDebug.bringToFront();
         addEventListener("enterFrame",enterFrameHandler);
         soundDebug.soundConfig = config.soundSystem;
         soundDebug.animDispatcher = config.animDispatcher;
         perf.bringToFront();
         guiMouse = new GuiMouse();
         guiMouse.init(config.resman,stage,config.options.softwareMouse);
         updateSystemMessage();
         tutorialLayer.context = config.gameGuiContext;
         config.systemMessage.addEventListener("change",systemMessageChangeHandler);
         networkProblemDisplay = new NetworkProblemDisplay(this,config,config.fsm.communicator,config.guiresman,config.context.locale);
         if(cmdFullscreen)
         {
            appInfo.fullscreen = cmdFullscreenSet;
         }
         else
         {
            appInfo.fullscreen = config.globalPrefs.getPref("option_fullscreen");
         }
         config.soundSystem.musicEnabled = config.globalPrefs.getPref("option_music");
         config.soundSystem.ambienceEnabled = config.globalPrefs.getPref("option_sfx");
         config.soundSystem.sfxEnabled = config.globalPrefs.getPref("option_sfx");
         config.fsm.startFsm(null);
      }
      
      private function systemMessageChangeHandler(param1:Event) : void
      {
         updateSystemMessage();
      }
      
      private function enterFrameHandler(param1:Event) : void
      {
         if(cleanedup)
         {
            return;
         }
         var _loc2_:int = getTimer();
         var _loc3_:int = _loc2_ - lastUpdateTime;
         if(lastUpdateTime == 0)
         {
            _loc3_ = 0;
         }
         lastUpdateTime = _loc2_;
         // [Inference] BSF-Client #31: developer fast-forward for the match runner. This is
         // the one place the game learns how much time passed since the last frame, and it
         // hands that on to everything that animates (fsm.update, pageManager.update). Scaling
         // it here makes the whole game run N times faster. ModGameSpeed.scale is 1 unless the
         // bridge's set_game_speed command raised it during an offline practice battle.
         _loc3_ *= ModGameSpeed.scale;
         config.updateGameConfig(_loc3_);
         frameNumber = frameNumber + 1;
         logger.frameNumber = frameNumber;
      }
      
      private function pageCtor(param1:Class) : Page
      {
         return new param1(config) as Page;
      }
      
      public function startLoading() : void
      {
         console.runMode = config.runMode;
         config.startLoading();
      }
      
      override protected function resizeHandler() : void
      {
         super.resizeHandler();
         if(pageManager)
         {
            pageManager.setRect(0,0,width,height);
         }
         sizeSystemMessageText();
      }
      
      protected function debugLogErrorHandler(param1:Event) : void
      {
         if(config.soundSystem && config.soundSystem.controller)
         {
            if(!config.soundSystem.driver.disposed)
            {
               if(config.options.lite)
               {
                  config.soundSystem.controller.playSound("error",null);
               }
            }
         }
      }
      
      public function cleanup() : void
      {
         if(cleanedup)
         {
            throw new IllegalOperationError("Why cleanedup twice?");
         }
         cleanedup = true;
         removeEventListener("enterFrame",enterFrameHandler);
         if(pageManager)
         {
            pageManager.cleanup();
         }
         if(config)
         {
            config.cleanup();
         }
      }
      
      public function cmdFuncTogglePerfSprite(param1:CmdExec) : void
      {
         perf.toggle();
         config.globalPrefs.setPref("show_perf",perf.perfEnabled);
      }
      
      public function cmdFuncToggleSoundDebug(param1:CmdExec) : void
      {
         soundDebug.toggle();
      }
      
      public function cmdFuncPage(param1:CmdExec) : void
      {
         if(pageManager)
         {
            pageManager.shell.execSubShell(param1);
         }
      }
      
      public function shellFuncDebug(param1:CmdExec) : void
      {
         logger.debugEnabled = !logger.debugEnabled;
         logger.info("debug " + logger.debugEnabled);
      }
   }
}

